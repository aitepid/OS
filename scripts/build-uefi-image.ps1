# build-uefi-image.ps1 -- Generate UEFI boot image (GPT + ESP + BOOTX64.EFI)
#
# Creates hicos-uefi.img with:
#   - Protective MBR + GPT header
#   - EFI System Partition (FAT16) containing \EFI\BOOT\BOOTX64.EFI
#   - The EFI app writes "HicOS UEFI OK" to EFI_SIMPLE_TEXT_OUTPUT via ConOut->OutputString

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Write-Host '=== Building UEFI Image ===' -ForegroundColor Cyan

# ====================================================================
# Step 1: Build minimal PE32+ EFI application (BOOTX64.EFI)
# ====================================================================
# The EFI app is a valid PE32+ that:
#   1. Calls ConOut->OutputString(ConOut, L"HicOS UEFI OK\r\n")
#   2. Writes to serial port 0x3F8 for test verification
#   3. Halts
#
# We build this as raw x86-64 machine code in a PE32+ wrapper.

$efi = [System.Collections.ArrayList]::new()
function efi_emit([byte]$b) { [void]$efi.Add($b) }
function efi_emit16([uint16]$v) { efi_emit ($v -band 0xFF); efi_emit (($v -shr 8) -band 0xFF) }
function efi_emit32([int64]$v) {
    $bytes = [System.BitConverter]::GetBytes([int32]($v -band [int64]0xFFFFFFFF))
    foreach ($b in $bytes) { efi_emit $b }
}
function efi_emit64([int64]$v) {
    efi_emit32 ($v -band [int64]0xFFFFFFFF)
    efi_emit32 (($v -shr 32) -band [int64]0xFFFFFFFF)
}
function efi_pad_to([int]$target) { while ($efi.Count -lt $target) { efi_emit 0 } }
function efi_set([int]$idx,[byte]$val) { $efi[$idx] = $val }
function efi_set16([int]$idx,[uint16]$v) {
    $efi[$idx]   = [byte]($v -band 0xFF)
    $efi[$idx+1] = [byte](($v -shr 8) -band 0xFF)
}
function efi_set32([int]$idx,[int64]$v) {
    $bytes = [System.BitConverter]::GetBytes([int32]($v -band [int64]0xFFFFFFFF))
    for ($i=0;$i -lt 4;$i++) { $efi[$idx+$i] = $bytes[$i] }
}

# --- PE32+ Header ---
# DOS Header (64 bytes)
efi_emit16 0x5A4D  # e_magic = "MZ"
efi_pad_to 60
efi_emit32 64       # e_lfanew → PE header at offset 64

# PE Signature at offset 64
efi_emit32 0x00004550  # "PE\0\0"

# COFF Header (20 bytes)
efi_emit16 0x8664   # Machine: AMD64
efi_emit16 2        # NumberOfSections: 2 (.text + .reloc)
efi_emit32 0        # TimeDateStamp
efi_emit32 0        # PointerToSymbolTable
efi_emit32 0        # NumberOfSymbols
efi_emit16 240      # SizeOfOptionalHeader (PE32+)
efi_emit16 0x0022   # Characteristics: EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE

# Optional Header (PE32+, 240 bytes)
$optHdrStart = $efi.Count
efi_emit16 0x020B   # Magic: PE32+
efi_emit 0          # MajorLinkerVersion
efi_emit 0          # MinorLinkerVersion
efi_emit32 0x200    # SizeOfCode
efi_emit32 512      # SizeOfInitializedData (.reloc)
efi_emit32 0        # SizeOfUninitializedData
efi_emit32 0x1000   # AddressOfEntryPoint (RVA, section start)
efi_emit32 0x1000   # BaseOfCode
efi_emit64 0x10000000  # ImageBase
efi_emit32 0x1000   # SectionAlignment
efi_emit32 0x200    # FileAlignment
efi_emit16 0        # MajorOperatingSystemVersion
efi_emit16 0        # MinorOperatingSystemVersion
efi_emit16 0        # MajorImageVersion
efi_emit16 0        # MinorImageVersion
efi_emit16 0        # MajorSubsystemVersion
efi_emit16 0        # MinorSubsystemVersion
efi_emit32 0        # Win32VersionValue
efi_emit32 0x3000   # SizeOfImage
efi_emit32 0x200    # SizeOfHeaders (aligned)
efi_emit32 0        # CheckSum
efi_emit16 10       # Subsystem: EFI Application
efi_emit16 0        # DllCharacteristics
efi_emit64 0x10000  # SizeOfStackReserve (64KB)
efi_emit64 0x10000  # SizeOfStackCommit (64KB)
efi_emit64 0        # SizeOfHeapReserve
efi_emit64 0        # SizeOfHeapCommit
efi_emit32 0        # LoaderFlags
efi_emit32 16       # NumberOfRvaAndSizes

# Data Directories (16 entries × 8 bytes = 128 bytes)
# Directory[5] = Base Relocation Table → .reloc section at RVA 0x2000
for ($i = 0; $i -lt 16; $i++) {
    if ($i -eq 5) {
        efi_emit32 0x2000  # RVA of .reloc
        efi_emit32 12      # Size (minimum reloc block: 8-byte header + 2-byte padding + 2-byte entry = 12)
    } else {
        efi_emit64 0
    }
}

# Section Header: .text
$sectionHdrStart = $efi.Count
# Name: ".text\0\0\0"
foreach ($c in [byte[]]@(0x2E,0x74,0x65,0x78,0x74,0,0,0)) { efi_emit $c }
efi_emit32 512      # VirtualSize
efi_emit32 0x1000   # VirtualAddress (RVA)
efi_emit32 512      # SizeOfRawData
efi_emit32 0x200    # PointerToRawData (file offset)
efi_emit32 0        # PointerToRelocations
efi_emit32 0        # PointerToLinenumbers
efi_emit16 0        # NumberOfRelocations
efi_emit16 0        # NumberOfLinenumbers
efi_emit32 0x60000020  # Characteristics: CODE|EXECUTE|READ

# Section Header: .reloc
foreach ($c in [byte[]]@(0x2E,0x72,0x65,0x6C,0x6F,0x63,0,0)) { efi_emit $c }  # ".reloc\0\0"
efi_emit32 12       # VirtualSize
efi_emit32 0x2000   # VirtualAddress (RVA)
efi_emit32 512      # SizeOfRawData (file-aligned to 512)
efi_emit32 0x400    # PointerToRawData (after .text section)
efi_emit32 0        # PointerToRelocations
efi_emit32 0        # PointerToLinenumbers
efi_emit16 0        # NumberOfRelocations
efi_emit16 0        # NumberOfLinenumbers
efi_emit32 0x42000040  # Characteristics: INITIALIZED_DATA|DISCARDABLE|READ

# Pad headers to FileAlignment (0x200 = 512)
efi_pad_to 0x200

# --- .text Section (the EFI entry point code) ---
# EFI entry: RCX = ImageHandle, RDX = SystemTable
# SystemTable->ConOut is at offset 64 (0x40)
# ConOut->OutputString is at offset 8
# OutputString(ConOut, L"string")
#
# Also write "HicOS UEFI OK\r\n" to serial 0x3F8 for test capture.

# Save RDX (SystemTable)
efi_emit 0x53                           # push rbx
efi_emit 0x48; efi_emit 0x89; efi_emit 0xD3  # mov rbx, rdx

# --- Serial output: write "HicOS UEFI OK\r\n" to 0x3F8 ---
$serialMsg = "HicOS UEFI OK`r`n"
foreach ($ch in $serialMsg.ToCharArray()) {
    $code = [byte][char]$ch
    # Wait TX ready: in al, 0x3FD; test al, 0x20; jz -4
    efi_emit 0xBA; efi_emit32 0x3FD     # mov edx, 0x3FD
    efi_emit 0xEC                        # in al, dx
    efi_emit 0xA8; efi_emit 0x20        # test al, 0x20
    efi_emit 0x74; efi_emit 0xFA        # jz -6
    efi_emit 0xBA; efi_emit32 0x3F8     # mov edx, 0x3F8
    efi_emit 0xB0; efi_emit $code       # mov al, char
    efi_emit 0xEE                        # out dx, al
}

# --- EFI ConOut->OutputString ---
# Get ConOut: mov rcx, [rbx+0x40] (SystemTable->ConOut)
efi_emit 0x48; efi_emit 0x8B; efi_emit 0x4B; efi_emit 0x40

# Load string address (relative to ImageBase + section RVA + offset)
# String will be at the end of our code. We'll patch this.
$leaStringPatch = $efi.Count
efi_emit 0x48; efi_emit 0x8D; efi_emit 0x15  # lea rdx, [rip+disp32]
efi_emit32 0  # placeholder, patched later

# Call OutputString: call [rcx+8]
# Need to align stack (ABI: 16-byte aligned before CALL)
efi_emit 0x48; efi_emit 0x83; efi_emit 0xEC; efi_emit 0x28  # sub rsp, 40 (shadow space + align)
efi_emit 0xFF; efi_emit 0x51; efi_emit 0x08                  # call [rcx+8]
efi_emit 0x48; efi_emit 0x83; efi_emit 0xC4; efi_emit 0x28  # add rsp, 40

# Infinite halt loop
$haltLoop = $efi.Count
efi_emit 0xF4  # hlt
efi_emit 0xEB; efi_emit 0xFD  # jmp -3

# UTF-16LE string: "HicOS UEFI Boot OK\r\n\0"
$stringOffset = $efi.Count
$ustr = "HicOS UEFI Boot OK`r`n"
foreach ($ch in $ustr.ToCharArray()) {
    efi_emit16 ([uint16][char]$ch)
}
efi_emit16 0  # null terminator

# Patch LEA RDX displacement
# RIP at time of LEA = (ImageBase + 0x1000 + ($leaStringPatch + 7) - 0x200)
# Target = (ImageBase + 0x1000 + $stringOffset - 0x200)
# disp32 = target - rip = $stringOffset - ($leaStringPatch + 7)
$leaDisp = $stringOffset - ($leaStringPatch + 7)
$dispBytes = [System.BitConverter]::GetBytes([int32]$leaDisp)
for ($i=0;$i -lt 4;$i++) { efi_set ($leaStringPatch + 3 + $i) $dispBytes[$i] }

# Pad .text section to 512 bytes
efi_pad_to 0x400

# --- .reloc Section (minimal, at file offset 0x400) ---
# Base Relocation Block: Page RVA=0, Size=12, one ABSOLUTE entry (nop)
efi_emit32 0x1000   # Page RVA (must point to a valid page)
efi_emit32 12       # Block Size (header=8 + 1 entry=2 + padding=2)
efi_emit16 0        # Type=0 (IMAGE_REL_BASED_ABSOLUTE, padding/nop)
efi_emit16 0        # padding to align block

# Pad .reloc section to 512 bytes
efi_pad_to 0x600

$efiBytes = [byte[]]$efi.ToArray()
$efiPath = Join-Path $repoRoot 'BOOTX64.EFI'
[System.IO.File]::WriteAllBytes($efiPath, $efiBytes)
Write-Host "  BOOTX64.EFI: $($efiBytes.Length) bytes" -ForegroundColor Green

# ====================================================================
# Step 2: Build disk image with GPT + ESP (FAT16)
# ====================================================================
# CRC32 (IEEE 802.3) for GPT headers
function Compute-CRC32([byte[]]$data, [int]$offset, [int]$length) {
    [int64]$crc = 0xFFFFFFFF
    for ($i = $offset; $i -lt ($offset + $length); $i++) {
        $crc = $crc -bxor $data[$i]
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crc -band 1) { $crc = (($crc -shr 1) -band 0x7FFFFFFF) -bxor 0xEDB88320 }
            else { $crc = ($crc -shr 1) -band 0x7FFFFFFF }
        }
    }
    return [System.BitConverter]::GetBytes([int32](($crc -bxor 0xFFFFFFFF) -band 0xFFFFFFFF))
}

# Layout constants
$imgSize       = 33 * 1024 * 1024         # 33 MB
$sectorSize    = 512
$totalSectors  = $imgSize / $sectorSize   # 67584
$espStartLBA   = 2048                     # 1 MB offset
$espSectors    = 32768                    # 16 MB
$espEndLBA     = $espStartLBA + $espSectors - 1
$numPartEntries = 128                     # GPT spec minimum
$partEntrySize  = 128
$partArrayBytes = $numPartEntries * $partEntrySize   # 16384 = 32 sectors
$partArraySectors = $partArrayBytes / $sectorSize    # 32

# LBA assignments
$primaryPartLBA   = 2                                # partition entries LBA 2-33
$firstUsableLBA   = $primaryPartLBA + $partArraySectors  # 34
$lastUsableLBA    = $totalSectors - 1 - $partArraySectors - 1  # leave room for backup
$backupPartLBA    = $lastUsableLBA + 1               # backup partition entries
$backupHeaderLBA  = $totalSectors - 1                # backup GPT header = last sector

$img = [byte[]]::new($imgSize)

# --- Protective MBR (LBA 0) ---
$img[446] = 0x00                        # status (not bootable)
$img[447] = 0x00; $img[448] = 0x02; $img[449] = 0x00  # CHS first
$img[450] = 0xEE                        # type = GPT protective
$img[451] = 0xFF; $img[452] = 0xFF; $img[453] = 0xFF  # CHS last
[System.BitConverter]::GetBytes([uint32]1).CopyTo($img, 454)                    # LBA start = 1
[System.BitConverter]::GetBytes([uint32]($totalSectors - 1)).CopyTo($img, 458)  # size
$img[510] = 0x55; $img[511] = 0xAA      # MBR signature

# --- GPT Partition Entries (primary, at LBA 2) ---
$peOff = $primaryPartLBA * $sectorSize
# Entry 0: EFI System Partition
# PartitionTypeGUID: C12A7328-F81F-11D2-BA4B-00A0C93EC93B
$espTypeGuid = [byte[]]@(0x28,0x73,0x2A,0xC1,0x1F,0xF8,0xD2,0x11,0xBA,0x4B,0x00,0xA0,0xC9,0x3E,0xC9,0x3B)
[System.Array]::Copy($espTypeGuid, 0, $img, $peOff, 16)
# UniquePartitionGUID
$partGuid = [byte[]]@(0x48,0x69,0x63,0x4F,0x53,0x45,0x53,0x50,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02)
[System.Array]::Copy($partGuid, 0, $img, $peOff + 16, 16)
[System.BitConverter]::GetBytes([uint64]$espStartLBA).CopyTo($img, $peOff + 32)   # StartingLBA
[System.BitConverter]::GetBytes([uint64]$espEndLBA).CopyTo($img, $peOff + 40)     # EndingLBA
[System.BitConverter]::GetBytes([uint64]0).CopyTo($img, $peOff + 48)              # Attributes
$partName = "EFI System"
for ($i = 0; $i -lt $partName.Length; $i++) {
    [System.BitConverter]::GetBytes([uint16][char]$partName[$i]).CopyTo($img, $peOff + 56 + $i * 2)
}
# (entries 1-127 stay zero = unused)

# Compute PartitionEntryArrayCRC32 over all 128 entries
$partCRCBytes = Compute-CRC32 $img $peOff $partArrayBytes

# --- Write backup partition entries (at $backupPartLBA) ---
$backupPeOff = $backupPartLBA * $sectorSize
[System.Array]::Copy($img, $peOff, $img, $backupPeOff, $partArrayBytes)

# --- Helper to write GPT header ---
function Write-GPTHeader([byte[]]$buf, [int]$off, [uint64]$myLBA, [uint64]$altLBA, [uint64]$peStartLBA, [byte[]]$peCRC) {
    [System.Text.Encoding]::ASCII.GetBytes("EFI PART").CopyTo($buf, $off)
    [System.BitConverter]::GetBytes([uint32]0x00010000).CopyTo($buf, $off + 8)
    [System.BitConverter]::GetBytes([uint32]92).CopyTo($buf, $off + 12)
    [System.BitConverter]::GetBytes([uint32]0).CopyTo($buf, $off + 16)   # CRC placeholder
    [System.BitConverter]::GetBytes([uint32]0).CopyTo($buf, $off + 20)   # Reserved
    [System.BitConverter]::GetBytes($myLBA).CopyTo($buf, $off + 24)
    [System.BitConverter]::GetBytes($altLBA).CopyTo($buf, $off + 32)
    [System.BitConverter]::GetBytes([uint64]$firstUsableLBA).CopyTo($buf, $off + 40)
    [System.BitConverter]::GetBytes([uint64]$lastUsableLBA).CopyTo($buf, $off + 48)
    $diskGuid = [byte[]]@(0x48,0x69,0x63,0x4F,0x53,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01)
    [System.Array]::Copy($diskGuid, 0, $buf, $off + 56, 16)
    [System.BitConverter]::GetBytes($peStartLBA).CopyTo($buf, $off + 72)
    [System.BitConverter]::GetBytes([uint32]$numPartEntries).CopyTo($buf, $off + 80)
    [System.BitConverter]::GetBytes([uint32]$partEntrySize).CopyTo($buf, $off + 84)
    [System.Array]::Copy($peCRC, 0, $buf, $off + 88, 4)
    # Compute header CRC32 over 92 bytes (with CRC field zeroed)
    $hdrCRC = Compute-CRC32 $buf $off 92
    [System.Array]::Copy($hdrCRC, 0, $buf, $off + 16, 4)
}

# Primary GPT Header at LBA 1
$gptOff = 1 * $sectorSize
Write-GPTHeader $img $gptOff ([uint64]1) ([uint64]$backupHeaderLBA) ([uint64]$primaryPartLBA) $partCRCBytes

# Backup GPT Header at last LBA
$bkpOff = $backupHeaderLBA * $sectorSize
Write-GPTHeader $img $bkpOff ([uint64]$backupHeaderLBA) ([uint64]1) ([uint64]$backupPartLBA) $partCRCBytes

# --- FAT16 filesystem on ESP ---
$fatBase = $espStartLBA * $sectorSize
$fatSectors = $espSectors
$bytesPerSector = 512
$sectorsPerCluster = 4
$reservedSectors = 1
$numFATs = 2
$rootEntryCount = 512
$rootDirSectors = [int][math]::Ceiling(($rootEntryCount * 32) / $bytesPerSector)
# FAT size calculation for FAT16
$dataSectors = $fatSectors - $reservedSectors - $rootDirSectors
$fatSectorCount = [int][math]::Ceiling($dataSectors / ($sectorsPerCluster * 256 + $numFATs))
if ($fatSectorCount -lt 32) { $fatSectorCount = 32 }

# BPB (BIOS Parameter Block) at partition start
$img[$fatBase + 0] = 0xEB; $img[$fatBase + 1] = 0x3C; $img[$fatBase + 2] = 0x90  # JMP short + NOP
[System.Text.Encoding]::ASCII.GetBytes("HICOS   ").CopyTo($img, $fatBase + 3)
[System.BitConverter]::GetBytes([uint16]$bytesPerSector).CopyTo($img, $fatBase + 11)
$img[$fatBase + 13] = [byte]$sectorsPerCluster
[System.BitConverter]::GetBytes([uint16]$reservedSectors).CopyTo($img, $fatBase + 14)
$img[$fatBase + 16] = [byte]$numFATs
[System.BitConverter]::GetBytes([uint16]$rootEntryCount).CopyTo($img, $fatBase + 17)
if ($fatSectors -le 65535) {
    [System.BitConverter]::GetBytes([uint16]$fatSectors).CopyTo($img, $fatBase + 19)
} else {
    [System.BitConverter]::GetBytes([uint16]0).CopyTo($img, $fatBase + 19)
    [System.BitConverter]::GetBytes([uint32]$fatSectors).CopyTo($img, $fatBase + 32)
}
$img[$fatBase + 21] = 0xF8  # Media descriptor (hard disk)
[System.BitConverter]::GetBytes([uint16]$fatSectorCount).CopyTo($img, $fatBase + 22)
[System.BitConverter]::GetBytes([uint16]32).CopyTo($img, $fatBase + 24)    # sectors/track
[System.BitConverter]::GetBytes([uint16]2).CopyTo($img, $fatBase + 26)     # heads
[System.BitConverter]::GetBytes([uint32]$espStartLBA).CopyTo($img, $fatBase + 28) # hidden sectors
$img[$fatBase + 38] = 0x29  # Extended boot signature
[System.BitConverter]::GetBytes([uint32]0x48694F53).CopyTo($img, $fatBase + 39)
[System.Text.Encoding]::ASCII.GetBytes("HICOS  UEFI").CopyTo($img, $fatBase + 43)
[System.Text.Encoding]::ASCII.GetBytes("FAT16   ").CopyTo($img, $fatBase + 54)
$img[$fatBase + 510] = 0x55; $img[$fatBase + 511] = 0xAA

# Initialize FAT (2 copies)
$fat1Off = $fatBase + $reservedSectors * $bytesPerSector
$fat2Off = $fat1Off + $fatSectorCount * $bytesPerSector

# FAT entry 0 and 1 are reserved
# Entry 0 = media descriptor | 0xFF00
$img[$fat1Off] = 0xF8; $img[$fat1Off+1] = 0xFF
# Entry 1 = end-of-chain
$img[$fat1Off+2] = 0xFF; $img[$fat1Off+3] = 0xFF
# Copy to FAT2
[System.Array]::Copy($img, $fat1Off, $img, $fat2Off, $fatSectorCount * $bytesPerSector)

# Root directory offset
$rootDirOff = $fat2Off + $fatSectorCount * $bytesPerSector

# Create directory tree: \EFI\BOOT\BOOTX64.EFI + startup.nsh
# Entry 0: "EFI" directory, cluster 2
$entryOff = $rootDirOff
[System.Text.Encoding]::ASCII.GetBytes("EFI        ").CopyTo($img, $entryOff)
$img[$entryOff + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]2).CopyTo($img, $entryOff + 26)

# Entry 1: "STARTUP.NSH" file, cluster 5
$nshEntryOff = $rootDirOff + 32
[System.Text.Encoding]::ASCII.GetBytes("STARTUP NSH").CopyTo($img, $nshEntryOff)
$img[$nshEntryOff + 11] = 0x20  # Archive
[System.BitConverter]::GetBytes([uint16]5).CopyTo($img, $nshEntryOff + 26)
# startup.nsh content
$nshContent = [System.Text.Encoding]::ASCII.GetBytes("echo HicOS UEFI`r`nFS0:\EFI\BOOT\BOOTX64.EFI`r`n")
[System.BitConverter]::GetBytes([uint32]$nshContent.Length).CopyTo($img, $nshEntryOff + 28)

# Mark cluster 2 as end-of-chain in FAT
$img[$fat1Off + 4] = 0xFF; $img[$fat1Off + 5] = 0xFF

# Data region starts after root directory
$dataRegionOff = $rootDirOff + [int]$rootDirSectors * $bytesPerSector
# Cluster 2 data = EFI directory (contains "BOOT" entry)
$efiDirOff = $dataRegionOff + 0  # cluster 2 = first data cluster
# "." entry
[System.Text.Encoding]::ASCII.GetBytes(".          ").CopyTo($img, $efiDirOff)
$img[$efiDirOff + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]2).CopyTo($img, $efiDirOff + 26)
# ".." entry
[System.Text.Encoding]::ASCII.GetBytes("..         ").CopyTo($img, $efiDirOff + 32)
$img[$efiDirOff + 32 + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]0).CopyTo($img, $efiDirOff + 32 + 26)
# "BOOT" entry, cluster 3
[System.Text.Encoding]::ASCII.GetBytes("BOOT       ").CopyTo($img, $efiDirOff + 64)
$img[$efiDirOff + 64 + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]3).CopyTo($img, $efiDirOff + 64 + 26)

# Mark cluster 3 as end-of-chain
$img[$fat1Off + 6] = 0xFF; $img[$fat1Off + 7] = 0xFF

# Cluster 3 data = BOOT directory (contains BOOTX64.EFI)
$bootDirOff = $dataRegionOff + $sectorsPerCluster * $bytesPerSector  # cluster 3
[System.Text.Encoding]::ASCII.GetBytes(".          ").CopyTo($img, $bootDirOff)
$img[$bootDirOff + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]3).CopyTo($img, $bootDirOff + 26)
[System.Text.Encoding]::ASCII.GetBytes("..         ").CopyTo($img, $bootDirOff + 32)
$img[$bootDirOff + 32 + 11] = 0x10
[System.BitConverter]::GetBytes([uint16]2).CopyTo($img, $bootDirOff + 32 + 26)

# BOOTX64.EFI entry (8.3 name: "BOOTX64 EFI"), cluster 4
[System.Text.Encoding]::ASCII.GetBytes("BOOTX64 EFI").CopyTo($img, $bootDirOff + 64)
$img[$bootDirOff + 64 + 11] = 0x20  # Archive attribute
[System.BitConverter]::GetBytes([uint16]4).CopyTo($img, $bootDirOff + 64 + 26)  # First cluster
[System.BitConverter]::GetBytes([uint32]$efiBytes.Length).CopyTo($img, $bootDirOff + 64 + 28)  # File size

# Write EFI binary to cluster 4+
$efiDataOff = $dataRegionOff + 2 * $sectorsPerCluster * $bytesPerSector  # cluster 4
[System.Array]::Copy($efiBytes, 0, $img, $efiDataOff, $efiBytes.Length)

# Write startup.nsh to cluster 5
$nshDataOff = $dataRegionOff + 3 * $sectorsPerCluster * $bytesPerSector  # cluster 5
[System.Array]::Copy($nshContent, 0, $img, $nshDataOff, $nshContent.Length)

# Mark clusters for BOOTX64.EFI in FAT (cluster 4+)
$efiClusters = [math]::Ceiling($efiBytes.Length / ($sectorsPerCluster * $bytesPerSector))
for ($c = 0; $c -lt $efiClusters; $c++) {
    $cluster = 4 + $c
    $fatIdx = $fat1Off + $cluster * 2
    if ($c -eq $efiClusters - 1) {
        $img[$fatIdx] = 0xFF; $img[$fatIdx+1] = 0xFF
    } else {
        $nextCluster = $cluster + 1
        [System.BitConverter]::GetBytes([uint16]$nextCluster).CopyTo($img, $fatIdx)
    }
}

# Cluster 5 = startup.nsh (end-of-chain)
$nshFatIdx = $fat1Off + 5 * 2
$img[$nshFatIdx] = 0xFF; $img[$nshFatIdx+1] = 0xFF

# Copy FAT1 to FAT2
[System.Array]::Copy($img, $fat1Off, $img, $fat2Off, $fatSectorCount * $bytesPerSector)

# Write image
$imgPath = Join-Path $repoRoot 'hicos-uefi.img'
[System.IO.File]::WriteAllBytes($imgPath, $img)
Write-Host "  hicos-uefi.img: $($img.Length) bytes ($($img.Length / 1MB) MB)" -ForegroundColor Green
Write-Host "  ESP: LBA $espStartLBA-$espEndLBA (FAT16, $($espSectors * 512 / 1024) KB)" -ForegroundColor Green
Write-Host "  Path: \EFI\BOOT\BOOTX64.EFI ($($efiBytes.Length) bytes)" -ForegroundColor Green

Write-Host '=== UEFI Image Built ===' -ForegroundColor Cyan
