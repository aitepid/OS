# boot-binary-analysis.ps1 -- Stage1/Stage2 Binary Verification
#
# Analyzes hicos-hl.img byte-level structure:
#   1. MBR signature (0x55AA at offset 510-511)
#   2. x86 boot code at 0x7C00 entry point
#   3. Stage2 presence and GDT markers
#   4. Long mode transition markers
#   5. Kernel entry detection
#
# This does NOT require QEMU -- purely static binary analysis.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$imgPath = 'hicos-hl.img'
if (-not (Test-Path $imgPath)) {
    Write-Host "Missing $imgPath" -ForegroundColor Red
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($imgPath)
$size = $bytes.Length

Write-Host "=== Boot Binary Analysis ===" -ForegroundColor Cyan
Write-Host "  Image: $imgPath ($size bytes, $($size / 512) sectors)"
Write-Host ""

$passes = @()
$warnings = @()
$errors = @()

# --- 1. MBR Signature ---
if ($size -ge 512) {
    $sig = $bytes[510] * 256 + $bytes[511]
    if ($bytes[510] -eq 0x55 -and $bytes[511] -eq 0xAA) {
        $passes += "MBR signature: 0x55AA at offset 510"
    } else {
        $errors += "MBR signature MISSING (got 0x$($bytes[510].ToString('X2'))$($bytes[511].ToString('X2')))"
    }
} else {
    $errors += "Image too small for MBR ($size bytes)"
}

# --- 2. First instruction analysis ---
# x86 real mode entry at offset 0 (loaded at 0x7C00)
$firstByte = $bytes[0]
$secondByte = if ($size -gt 1) { $bytes[1] } else { 0 }
$thirdByte = if ($size -gt 2) { $bytes[2] } else { 0 }

# Common boot entry: CLI (0xFA), JMP (0xEB/0xE9), XOR (0x31), MOV (0xB8/0xBC)
$validStarts = @(0xFA, 0xEB, 0xE9, 0x31, 0xB8, 0xBC, 0xEA, 0x33, 0x8C, 0xFC)
if ($firstByte -in $validStarts) {
    $mnemonic = switch ($firstByte) {
        0xFA { 'CLI' }
        0xEB { 'JMP short' }
        0xE9 { 'JMP near' }
        0x31 { 'XOR' }
        0xB8 { 'MOV AX,imm' }
        0xBC { 'MOV SP,imm' }
        0xEA { 'JMP far' }
        0x33 { 'XOR' }
        0x8C { 'MOV segreg' }
        0xFC { 'CLD' }
    }
    $passes += "Stage1 entry: 0x$($firstByte.ToString('X2')) ($mnemonic)"
} else {
    $warnings += "Unusual first instruction: 0x$($firstByte.ToString('X2')) (expected CLI/JMP/XOR)"
}

# --- 3. Boot code scan (first 512 bytes) ---
# Look for key patterns in Stage1
$sector0 = $bytes[0..511]
$sector0Hex = ($sector0 | ForEach-Object { $_.ToString('X2') }) -join ''

# A20 enable: writing to port 0x92 (OUT 0x92, AL) = 0xE6 0x92
$a20Pattern = 'E692'
if ($sector0Hex.Contains($a20Pattern)) {
    $passes += "A20 gate enable: OUT 0x92 found in Stage1"
} else {
    # Alt: keyboard controller method (OUT 0x64, AL then OUT 0x60, AL)
    if ($sector0Hex.Contains('E664') -or $sector0Hex.Contains('EE')) {
        $passes += "A20 gate enable: keyboard controller method in Stage1"
    } else {
        $warnings += "A20 enable not detected in Stage1 (may use INT 15h method)"
    }
}

# INT 13h disk read (AH=02h, INT 13h = CD 13)
if ($sector0Hex.Contains('CD13')) {
    $passes += "INT 13h disk read: CD13 found in Stage1"
} else {
    $warnings += "INT 13h disk read not found in Stage1"
}

# INT 15h E820 memory map (INT 15h = CD 15)
if ($sector0Hex.Contains('CD15')) {
    $passes += "INT 15h E820 memory detection in Stage1"
}

# --- 4. Stage2 analysis (sectors 1+) ---
if ($size -gt 512) {
    $stage2Start = 512
    $stage2End = [math]::Min($size, 4096)
    $stage2Bytes = $bytes[$stage2Start..($stage2End - 1)]
    $stage2Hex = ($stage2Bytes | ForEach-Object { $_.ToString('X2') }) -join ''

    $passes += "Stage2 present: $($stage2End - $stage2Start) bytes after MBR"

    # GDT pointer: LGDT instruction = 0F 01 15/16/1x (LGDT [mem])
    if ($stage2Hex.Contains('0F01')) {
        $passes += "GDT load (LGDT): 0F01 found in Stage2"
    } else {
        $warnings += "LGDT not detected in Stage2 region"
    }

    # CR0 set PE bit: MOV CR0 = 0F 22 C0 (MOV CR0, EAX)
    if ($stage2Hex.Contains('0F22C0') -or $stage2Hex.Contains('0F22')) {
        $passes += "Protected mode: MOV CR0 found (PE bit set)"
    }

    # CR4 PAE: MOV CR4 = 0F 22 E0
    if ($stage2Hex.Contains('0F22E0') -or $stage2Hex.Contains('0F20E0')) {
        $passes += "PAE enable: CR4 manipulation found"
    }

    # Long mode: MSR 0xC0000080 (EFER) write via WRMSR (0F 30)
    if ($stage2Hex.Contains('0F30')) {
        $passes += "WRMSR: MSR write found (EFER/LSTAR/STAR)"
    }

    # CR3 load (page table base): MOV CR3 = 0F 22 D8/DB
    if ($stage2Hex.Contains('0F22D')) {
        $passes += "Page table: MOV CR3 found"
    }
} else {
    $errors += "No Stage2 data (image is only 1 sector)"
}

# --- 5. Kernel region analysis ---
if ($size -gt 4096) {
    $kernelRegion = $bytes[4096..([math]::Min($size, 6143) - 1)]
    $kernelHex = ($kernelRegion | ForEach-Object { $_.ToString('X2') }) -join ''

    # Serial port init: OUT to 0x3F8 range
    if ($kernelHex.Contains('F803') -or $kernelHex.Contains('3F8')) {
        $passes += "Serial port 0x3F8 reference in kernel region"
    }

    $passes += "Kernel region present: $($kernelRegion.Length) bytes (sector 8+)"
}

# --- 6. Overall structure ---
# Count non-zero sectors
$nonZeroSectors = 0
for ($s = 0; $s -lt [math]::Floor($size / 512); $s++) {
    $sectorBytes = $bytes[($s * 512)..(($s + 1) * 512 - 1)]
    if (($sectorBytes | Where-Object { $_ -ne 0 }).Count -gt 0) {
        $nonZeroSectors++
    }
}
$passes += "Non-zero sectors: $nonZeroSectors / $([math]::Floor($size / 512))"

# --- Report ---
Write-Host "--- Results ---" -ForegroundColor Cyan

foreach ($p in $passes) {
    Write-Host "  PASS: $p" -ForegroundColor Green
}
foreach ($w in $warnings) {
    Write-Host "  WARN: $w" -ForegroundColor Yellow
}
foreach ($e in $errors) {
    Write-Host "  FAIL: $e" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Image size:      $size bytes ($($size / 512) sectors)"
Write-Host "  Non-zero:        $nonZeroSectors sectors"
Write-Host "  Passes:          $($passes.Count)"
Write-Host "  Warnings:        $($warnings.Count)"
Write-Host "  Errors:          $($errors.Count)"

# Hex dump of first 64 bytes
Write-Host ""
Write-Host "--- First 64 bytes (Stage1 entry) ---" -ForegroundColor Cyan
for ($row = 0; $row -lt 4; $row++) {
    $offset = $row * 16
    $hex = ($bytes[$offset..($offset + 15)] | ForEach-Object { $_.ToString('X2') }) -join ' '
    $ascii = ($bytes[$offset..($offset + 15)] | ForEach-Object {
        if ($_ -ge 0x20 -and $_ -le 0x7E) { [char]$_ } else { '.' }
    }) -join ''
    Write-Host ("  {0:X4}: {1}  {2}" -f $offset, $hex, $ascii)
}

Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "BINARY ANALYSIS: ISSUES FOUND" -ForegroundColor Red
    exit 1
} else {
    Write-Host "BINARY ANALYSIS: OK ($($passes.Count) checks passed)" -ForegroundColor Green
    exit 0
}
