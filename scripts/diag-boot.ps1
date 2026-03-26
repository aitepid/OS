$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$qemu = $null
$qemuCmd = Get-Command 'qemu-system-x86_64' -ErrorAction SilentlyContinue
if ($qemuCmd) { $qemu = $qemuCmd.Source }
if (-not $qemu -or -not (Test-Path $qemu)) {
    foreach ($p in @(
        'C:\Program Files\qemu\qemu-system-x86_64.exe',
        'C:\Program Files (x86)\qemu\qemu-system-x86_64.exe',
        "$env:USERPROFILE\scoop\apps\qemu\current\qemu-system-x86_64.exe",
        'C:\ProgramData\chocolatey\bin\qemu-system-x86_64.exe',
        'C:\msys64\usr\bin\qemu-system-x86_64.exe'
    )) {
        if (Test-Path $p) { $qemu = $p; break }
    }
}
if ((-not $qemu -or -not (Test-Path $qemu)) -and $env:QEMU_HOME) {
    $qemuHomePath = Join-Path $env:QEMU_HOME 'qemu-system-x86_64.exe'
    if (Test-Path $qemuHomePath) { $qemu = $qemuHomePath }
}
if (-not $qemu) {
    Write-Host 'QEMU not found. Skipping diagnostic boot.' -ForegroundColor Yellow
    exit 2
}

$serialLog = Join-Path $repoRoot "qemu-serial-diag.log"
$debugLog  = Join-Path $repoRoot "qemu-debug-diag.log"
if (Test-Path $serialLog) { Remove-Item $serialLog -Force }
if (Test-Path $debugLog)  { Remove-Item $debugLog -Force }

if (-not (Test-Path (Join-Path $repoRoot "hicos-disk.img"))) {
    $s = [System.IO.File]::Create((Join-Path $repoRoot "hicos-disk.img"))
    $s.SetLength(32MB)
    $s.Close()
}

Write-Host "=== Diagnostic Boot ===" -ForegroundColor Cyan
Write-Host "QEMU: $qemu"

# Run with debug logging to capture exceptions/faults
$qemuArgs = @(
    '-drive', "format=raw,file=$repoRoot\hicos-hl.img",
    '-serial', "file:$serialLog",
    '-m', '128',
    '-display', 'none',
    '-device', 'virtio-blk-pci,drive=disk0,disable-modern=on',
    '-drive', "id=disk0,file=$repoRoot\hicos-disk.img,format=raw,if=none",
    '-netdev', 'user,id=net0',
    '-device', 'virtio-net-pci,netdev=net0,disable-modern=on',
    '-no-reboot',
    '-no-shutdown',
    '-d', 'int,cpu_reset',
    '-D', $debugLog
)

$proc = Start-Process -FilePath $qemu -ArgumentList $qemuArgs -PassThru -NoNewWindow
Start-Sleep 10

if (-not $proc.HasExited) {
    Write-Host "Killing QEMU (timeout)..." -ForegroundColor Yellow
    $proc.Kill()
    Start-Sleep 1
}

Write-Host ""
Write-Host "--- Serial Output ($((Get-Item $serialLog -ErrorAction SilentlyContinue).Length) bytes) ---" -ForegroundColor Cyan
if (Test-Path $serialLog) {
    $sc = [System.IO.File]::ReadAllText($serialLog)
    if ($sc.Length -eq 0) {
        Write-Host "(empty)" -ForegroundColor Yellow
    } else {
        Write-Host $sc.Substring(0, [Math]::Min($sc.Length, 3000))
    }
}

Write-Host ""
Write-Host "--- Debug Log (first 80 lines) ---" -ForegroundColor Cyan
if (Test-Path $debugLog) {
    $allLines = Get-Content $debugLog
    Write-Host "Total debug lines: $($allLines.Count)"
    $show = [Math]::Min($allLines.Count, 80)
    for ($i = 0; $i -lt $show; $i++) { Write-Host $allLines[$i] }
    Write-Host ""
    Write-Host "--- Debug Log (last 40 lines) ---" -ForegroundColor Cyan
    $tailStart = [Math]::Max(0, $allLines.Count - 40)
    for ($i = $tailStart; $i -lt $allLines.Count; $i++) { Write-Host $allLines[$i] }
    # Count unique interrupt types
    Write-Host ""
    Write-Host "--- Interrupt Summary ---" -ForegroundColor Cyan
    $allLines | Group-Object | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { Write-Host "  $($_.Count)x $($_.Name)" }
} else {
    Write-Host "(no debug log)" -ForegroundColor Yellow
}
