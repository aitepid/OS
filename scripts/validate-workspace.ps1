param(
    [switch]$RunHlBuild,
    [switch]$RunHlTests,
    [switch]$StrictLanguagePurity,
    [switch]$StrictNoStubs
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$errors = @()

$requiredFiles = @(
    'README.md',
    'ARCHITECTURE.md',
    'manifest.hl',
    'bare-kernel/hl/build.hl',
    'bare-kernel/hl/kernel_init.hl'
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        $errors += "Missing required file: $file"
    }
}

$manifest = Get-Content 'manifest.hl' -Raw

function Get-ManifestValue([string]$name) {
    $pattern = 'let\s+' + [regex]::Escape($name) + '\s*=\s*"([^"]+)";'
    $m = [regex]::Match($manifest, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-ManifestIntValue([string]$name) {
    $pattern = 'let\s+' + [regex]::Escape($name) + '\s*=\s*(\d+);'
    $m = [regex]::Match($manifest, $pattern)
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return $null
}

$manifestVersion = Get-ManifestValue 'HICOS_VERSION'
$manifestKernelModules = Get-ManifestIntValue 'KERNEL_MODULES'
$manifestHlFiles = Get-ManifestIntValue 'HL_FILES'

$actualKernelModules = (Get-ChildItem 'bare-kernel/hl' -File -Filter '*.hl').Count
$hlFiles = Get-ChildItem -Recurse -File -Filter '*.hl' | Where-Object { $_.FullName -notmatch '\\.vs\\' -and $_.FullName -notmatch '\\archive\\' }
$actualHlFiles = $hlFiles.Count

if ($manifestKernelModules -ne $actualKernelModules) {
    $errors += "KERNEL_MODULES mismatch: manifest=$manifestKernelModules actual=$actualKernelModules"
}

if ($manifestHlFiles -ne $actualHlFiles) {
    $errors += "HL_FILES mismatch: manifest=$manifestHlFiles actual=$actualHlFiles"
}

$readme = Get-Content 'README.md' -Raw
if ($readme -notmatch '# HicOS 6\.0') {
    $errors += 'README version header is not 6.0'
}
if ($manifestVersion -ne '6.0') {
    $errors += "manifest version is not 6.0 (actual: $manifestVersion)"
}

$hlBootstrap = Get-Command 'hl-bootstrap' -ErrorAction SilentlyContinue
if ($RunHlBuild -or $RunHlTests) {
    if (-not $hlBootstrap) {
        $errors += 'hl-bootstrap not found in PATH; cannot run H-L build/tests'
    }
}

if ($hlBootstrap -and $RunHlBuild) {
    & hl-bootstrap 'bare-kernel/hl/build.hl'
    if ($LASTEXITCODE -ne 0) {
        $errors += "hl build failed with code $LASTEXITCODE"
    }
}

if ($hlBootstrap -and $RunHlTests) {
    & hl-bootstrap 'bare-kernel/hl/test-runner.hl'
    if ($LASTEXITCODE -ne 0) {
        $errors += "hl tests failed with code $LASTEXITCODE"
    }
}

$forbiddenPattern = 'require\(|module\.exports|JSON\.stringify|process\.argv|#!/usr/bin/env node'
$forbiddenFiles = $hlFiles | Where-Object { (Get-Content $_.FullName -Raw) -match $forbiddenPattern }

if ($forbiddenFiles.Count -gt 0) {
    $msg = "Found non-HL dependency patterns in $($forbiddenFiles.Count) file(s)."
    if ($StrictLanguagePurity) {
        $errors += $msg
    } else {
        Write-Host "Warning: $msg" -ForegroundColor Yellow
    }
    $forbiddenFiles | Select-Object -ExpandProperty FullName | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

$stubPattern = '(?i)\bplaceholder\b|This would implement|Implementation for'
$stubFiles = $hlFiles | Where-Object { (Get-Content $_.FullName -Raw) -match $stubPattern }

if ($stubFiles.Count -gt 0) {
    $msg = "Found potential stubs/placeholders in $($stubFiles.Count) file(s)."
    if ($StrictNoStubs) {
        $errors += $msg
    } else {
        Write-Host "Warning: $msg" -ForegroundColor Yellow
    }
    $stubFiles | Select-Object -First 30 -ExpandProperty FullName | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    if ($stubFiles.Count -gt 30) {
        Write-Host "  - ... and $($stubFiles.Count - 30) more" -ForegroundColor Yellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'Workspace validation failed:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Workspace validation passed.' -ForegroundColor Green
Write-Host "- HICOS_VERSION: $manifestVersion"
Write-Host "- KERNEL_MODULES: $manifestKernelModules"
Write-Host "- HL_FILES: $manifestHlFiles"
Write-Host "- bare-kernel/hl/*.hl: $actualKernelModules"
Write-Host "- all *.hl (excluding .vs): $actualHlFiles"
Write-Host "- non-HL pattern files: $($forbiddenFiles.Count)"
Write-Host "- potential stub files: $($stubFiles.Count)"
