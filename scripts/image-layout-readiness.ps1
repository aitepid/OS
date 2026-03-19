$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$errors = @()

if (-not (Test-Path 'hicos-hl.img')) {
    $errors += 'Missing boot image: hicos-hl.img'
} else {
    $img = Get-Item 'hicos-hl.img'
    if ($img.Length -lt 512) {
        $errors += 'Boot image too small (<512 bytes).'
    }

    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path 'hicos-hl.img'))
    if ($bytes.Length -ge 512) {
        $sig0 = $bytes[510]
        $sig1 = $bytes[511]
        if (-not ($sig0 -eq 0x55 -and $sig1 -eq 0xAA)) {
            $errors += ('Invalid MBR signature at 0x1FE: got 0x{0:X2} 0x{1:X2}, expected 0x55 0xAA' -f $sig0, $sig1)
        }
    }

    $manifest = Get-Content 'manifest.hl' -Raw
    $m = [regex]::Match($manifest, 'let\s+BOOT_IMAGE_BYTES\s*=\s*(\d+);')
    if ($m.Success) {
        $expected = [int]$m.Groups[1].Value
        # Allow size variation due to kernel.bin compilation output changes
        # Accept if actual is within 20% of expected (kernel.bin size may fluctuate)
        $tolerance = [math]::Max(4096, [int]($expected * 0.2))
        if ([math]::Abs($img.Length - $expected) -gt $tolerance) {
            $errors += "Image size mismatch: manifest=$expected actual=$($img.Length) (tolerance=$tolerance)"
        }
    } else {
        $errors += 'manifest missing BOOT_IMAGE_BYTES'
    }
}

$buildScript = Get-Content 'bare-kernel/hl/build.hl' -Raw
foreach ($must in @('stage1.hl','stage2.hl','kernel_entry.hl')) {
    if ($buildScript -notmatch [regex]::Escape($must)) {
        $errors += "build script missing boot stage reference: $must"
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'Image layout readiness check failed:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Image layout readiness check passed.' -ForegroundColor Green
Write-Host '- image file exists: OK'
Write-Host '- image size vs manifest: OK'
Write-Host '- MBR signature (0x55AA): OK'
Write-Host '- boot stage references in build script: OK'
