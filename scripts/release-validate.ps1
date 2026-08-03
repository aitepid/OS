# release-validate.ps1 -- Validate v6.0 release artifacts
#
# Checks all required release artifacts exist and meet minimum criteria.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\release-validate.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Write-Host '=== HicOS v6.0 Release Validation ===' -ForegroundColor Cyan

$passes = @()
$fails = @()

# --- 1. BIOS image ---
if (Test-Path 'hicos-hl.img') {
    $sz = (Get-Item 'hicos-hl.img').Length
    if ($sz -ge 40960) {
        $passes += "hicos-hl.img exists ($sz bytes, $([int]($sz/512)) sectors)"
    } else {
        $fails += "hicos-hl.img too small ($sz bytes)"
    }
    # MBR signature check
    $bytes = [System.IO.File]::ReadAllBytes('hicos-hl.img')
    if ($bytes.Length -ge 512 -and $bytes[510] -eq 0x55 -and $bytes[511] -eq 0xAA) {
        $passes += 'hicos-hl.img MBR signature 0x55AA valid'
    } else {
        $fails += 'hicos-hl.img missing MBR 0x55AA signature'
    }
} else {
    $fails += 'hicos-hl.img not found'
}

# --- 2. UEFI image ---
if (Test-Path 'hicos-uefi.img') {
    $sz = (Get-Item 'hicos-uefi.img').Length
    if ($sz -ge 1MB) {
        $passes += "hicos-uefi.img exists ($([int]($sz/1MB)) MB)"
    } else {
        $fails += "hicos-uefi.img too small ($sz bytes)"
    }
    # Protective MBR check
    $uefiBytes = [System.IO.File]::ReadAllBytes('hicos-uefi.img')
    if ($uefiBytes.Length -ge 512 -and $uefiBytes[510] -eq 0x55 -and $uefiBytes[511] -eq 0xAA) {
        $passes += 'hicos-uefi.img protective MBR signature valid'
    } else {
        $fails += 'hicos-uefi.img missing protective MBR'
    }
} else {
    $fails += 'hicos-uefi.img not found'
}

# --- 3. UEFI app ---
if (Test-Path 'BOOTX64.EFI') {
    $sz = (Get-Item 'BOOTX64.EFI').Length
    $efiBytes = [System.IO.File]::ReadAllBytes('BOOTX64.EFI')
    if ($efiBytes.Length -ge 64 -and $efiBytes[0] -eq 0x4D -and $efiBytes[1] -eq 0x5A) {
        $passes += "BOOTX64.EFI PE32+ valid ($sz bytes)"
    } else {
        $fails += 'BOOTX64.EFI not a valid PE file'
    }
} else {
    $fails += 'BOOTX64.EFI not found'
}

# --- 4. Bootstrap compiler ---
if (Test-Path 'hl-bootstrap.hl') {
    $lines = (Get-Content 'hl-bootstrap.hl' | Measure-Object -Line).Lines
    if ($lines -ge 4000) {
        $passes += "hl-bootstrap.hl present ($lines lines)"
    } else {
        $fails += "hl-bootstrap.hl too short ($lines lines)"
    }
} else {
    $fails += 'hl-bootstrap.hl not found'
}

# --- 5. Kernel modules ---
$kernelModules = Get-ChildItem -Path 'bare-kernel/hl' -Filter '*.hl' -ErrorAction SilentlyContinue
$modCount = $kernelModules.Count
if ($modCount -ge 100) {
    $passes += "Kernel modules: $modCount (>=100)"
} else {
    $fails += "Kernel modules: only $modCount (<100)"
}

# --- 6. Documentation ---
$docs = @('README.md', 'ROADMAP.md', 'CHANGELOG.md', 'ARCHITECTURE.md')
foreach ($d in $docs) {
    if (Test-Path $d) {
        $passes += "$d present"
    } else {
        $fails += "$d missing"
    }
}

# --- 7. Build scripts ---
$requiredScripts = @(
    'scripts/rebuild-image.ps1',
    'scripts/qemu-boot-test.ps1',
    'scripts/full-gate.ps1',
    'scripts/validate-workspace.ps1',
    'scripts/hl_pipeline.py'
)
foreach ($s in $requiredScripts) {
    if (Test-Path $s) {
        $passes += "$s present"
    } else {
        $fails += "$s missing"
    }
}

# --- 8. Language purity ---
$jsFiles = Get-ChildItem -Recurse -Filter '*.js' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.vs' }
$rsFiles = Get-ChildItem -Recurse -Filter '*.rs' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\.git|\.vs' }
$jsonFiles = Get-ChildItem -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.vs' }

if ($jsFiles.Count -eq 0 -and $rsFiles.Count -eq 0 -and $jsonFiles.Count -eq 0) {
    $passes += 'Language purity: 0 JS, 0 Rust, 0 JSON files'
} else {
    $fails += "Language purity violation: $($jsFiles.Count) JS, $($rsFiles.Count) Rust, $($jsonFiles.Count) JSON"
}

# --- 9. Source stats ---
$hlAll = Get-ChildItem -Recurse -Filter '*.hl' | Where-Object { $_.FullName -notmatch 'node_modules|\.git|\.vs|\\archive' }
if ($hlAll.Count -ge 170) {
    $passes += "Total H-L files: $($hlAll.Count) (>=170)"
} else {
    $fails += "Total H-L files: $($hlAll.Count) (<170)"
}

# --- Results ---
Write-Host ''
foreach ($p in $passes) {
    Write-Host "  PASS: $p" -ForegroundColor Green
}
foreach ($f in $fails) {
    Write-Host "  FAIL: $f" -ForegroundColor Red
}

Write-Host ''
$total = $passes.Count + $fails.Count
Write-Host "Release Validation: $($passes.Count)/$total passed" -ForegroundColor $(if ($fails.Count -eq 0) { 'Green' } else { 'Yellow' })

if ($fails.Count -gt 0) {
    Write-Host 'RELEASE VALIDATION: FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'RELEASE VALIDATION: PASSED' -ForegroundColor Green
exit 0
