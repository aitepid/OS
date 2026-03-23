$ErrorActionPreference = 'Stop'
$repoRoot = "C:\Users\Administrator\HicOS"
$imgPath = Join-Path $repoRoot "hicos-hl.img"
$bytes = [System.IO.File]::ReadAllBytes($imgPath)

Write-Host "Image size: $($bytes.Length) bytes ($([Math]::Ceiling($bytes.Length/512)) sectors)"
Write-Host ""

# Dump MBR (first 512 bytes) as hex
Write-Host "=== MBR (sector 0) ===" -ForegroundColor Cyan
for ($row = 0; $row -lt 512; $row += 16) {
    $hex = ""
    $ascii = ""
    for ($col = 0; $col -lt 16 -and ($row + $col) -lt 512; $col++) {
        $b = $bytes[$row + $col]
        $hex += "{0:X2} " -f $b
        if ($b -ge 0x20 -and $b -le 0x7E) { $ascii += [char]$b } else { $ascii += "." }
    }
    Write-Host ("{0:X4}: {1,-48} {2}" -f $row, $hex, $ascii)
    # Stop after the boot signature or after 0x1E0 (before partition table)
    if ($row -ge 0x01F0) { break }
}

# Check boot signature
Write-Host ""
$sig = $bytes[510] * 256 + $bytes[511]
Write-Host "Boot signature at 0x1FE: $("{0:X4}" -f (([uint16]$bytes[511] -shl 8) -bor $bytes[510]))" -ForegroundColor $(if ($bytes[510] -eq 0x55 -and $bytes[511] -eq 0xAA) { "Green" } else { "Red" })

# Find key bytes in MBR
Write-Host ""
Write-Host "=== MBR Code Analysis ===" -ForegroundColor Cyan

# Look for INT 13h (CD 13)
$found13 = @()
for ($i = 0; $i -lt 510; $i++) {
    if ($bytes[$i] -eq 0xCD -and $bytes[$i+1] -eq 0x13) {
        $found13 += $i
    }
}
Write-Host "INT 13h (CD 13) found at offsets: $($found13 -join ', ')"

# Look for INT 10h (CD 10)
$found10 = @()
for ($i = 0; $i -lt 510; $i++) {
    if ($bytes[$i] -eq 0xCD -and $bytes[$i+1] -eq 0x10) {
        $found10 += $i
    }
}
Write-Host "INT 10h (CD 10) found at offsets: $($found10 -join ', ')"

# Look for JMP rel8 (EB xx) backward jumps
$foundJmp = @()
for ($i = 0; $i -lt 510; $i++) {
    if ($bytes[$i] -eq 0xEB) {
        $disp = [sbyte]$bytes[$i+1]
        $target = $i + 2 + $disp
        if ($disp -lt 0) {
            $foundJmp += "0x{0:X2}: JMP -$(-$disp) -> 0x{1:X2}" -f $i, $target
        }
    }
}
Write-Host "Backward JMP rel8:"
$foundJmp | ForEach-Object { Write-Host "  $_" }

# Look for JE/JZ (74 xx) forward jumps  
$foundJe = @()
for ($i = 0; $i -lt 510; $i++) {
    if ($bytes[$i] -eq 0x74) {
        $disp = [sbyte]$bytes[$i+1]
        $target = $i + 2 + $disp
        $foundJe += "0x{0:X2}: JE +$disp -> 0x{1:X2}" -f $i, $target
    }
}
Write-Host "JE/JZ forward:"
$foundJe | ForEach-Object { Write-Host "  $_" }

# Dump Stage2 first 64 bytes
Write-Host ""
Write-Host "=== Stage 2 (sector 1, first 64 bytes) ===" -ForegroundColor Cyan
for ($row = 512; $row -lt 576; $row += 16) {
    $hex = ""
    for ($col = 0; $col -lt 16; $col++) {
        $hex += "{0:X2} " -f $bytes[$row + $col]
    }
    Write-Host ("{0:X4}: {1}" -f ($row - 512), $hex)
}
