# Diagnose why a single .hl module produces 0 bytes of x86.
# Loads the pipeline as a module by stripping the trailing driver loop, then
# runs Phases 1-4 on a target file and surfaces any silent codegen exception.
param([string]$Target = 'stdlib.hl')

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$pipeline = Join-Path $repoRoot 'scripts\hl-compile-pipeline.ps1'

# Load text, cut off at the driver section ("# Phase 1: collect modules" or similar)
$src = Get-Content $pipeline -Raw -Encoding UTF8
# Find the driver: the foreach over $hlFiles. Cut just before it.
$markerIdx = $src.IndexOf('Write-Host "Phase 1')
if ($markerIdx -lt 0) { $markerIdx = $src.IndexOf('# Phase 1') }
if ($markerIdx -lt 0) { Write-Host "Cannot find driver marker" -ForegroundColor Red; exit 1 }
Write-Host ("Marker at: {0} of {1}" -f $markerIdx, $src.Length)
$libSrc = $src.Substring(0, $markerIdx)
Write-Host ("Lib src length: {0}" -f $libSrc.Length)

# Replace $PSScriptRoot references with the actual scripts dir so evaluation works
$scriptsDir = Join-Path $repoRoot 'scripts'
$libSrc = $libSrc -replace '\$PSScriptRoot', "'$scriptsDir'".Replace('\','\\')

# Write a temp file and dot-source it into current scope (functions will be in script: scope)
$tmpFile = Join-Path $env:TEMP ("hl-pipeline-lib-" + [guid]::NewGuid().ToString('N') + ".ps1")
[System.IO.File]::WriteAllText($tmpFile, $libSrc, [System.Text.UTF8Encoding]::new($false))
. $tmpFile
Remove-Item $tmpFile -ErrorAction SilentlyContinue

# Resolve target
$path = Join-Path $repoRoot $Target
if (-not (Test-Path $path)) { $path = Join-Path $repoRoot ('bare-kernel\hl\' + $Target) }
if (-not (Test-Path $path)) { Write-Host "Not found: $Target" -ForegroundColor Red; exit 1 }

Write-Host "=== Diag codegen: $Target ===" -ForegroundColor Cyan
$source = Get-Content $path -Raw -Encoding UTF8
$tokens = Tokenize-HL $source
Write-Host ("Tokens: {0}" -f $tokens.Count)

$script:ppos = 0; $script:ptok = $tokens; $script:ptok_len = $tokens.Count; $script:perrors = 0; $script:pnodes = 0
$ast = $null
try { $ast = p_program } catch { Write-Host "Parse error: $_" -ForegroundColor Red; exit 1 }
Write-Host ("AST nodes: {0}; parse errors: {1}" -f $ast.Count, $script:perrors)

IR-Init
try { IR-LowerModule $ast } catch { Write-Host "IR error: $_" -ForegroundColor Red; exit 1 }
$irLive = IR-LiveCount
Write-Host ("IR total: {0}; live: {1}; fns: {2}" -f $script:ir_count, $irLive, $script:ir_fns.Count)

$script:current_module = (Split-Path $path -Leaf)

# Pre-scan: report any IR_JZ/IR_JNZ where src1 isn't a plain int label
$bad = 0
for ($i = 0; $i -lt $script:ir_count; $i++) {
    $op = $script:ir_op[$i]
    if ($op -eq $script:IR_JZ -or $op -eq $script:IR_JNZ -or $op -eq $script:IR_JMP) {
        $s1 = $script:ir_src1[$i]
        $d  = $script:ir_dst[$i]
        if ($op -eq $script:IR_JMP) {
            if ($d -isnot [int]) { Write-Host "JMP idx=$i dst type=$($d.GetType().Name) val=$d" -ForegroundColor Yellow; $bad++; if ($bad -le 5) {} }
        } else {
            if ($s1 -isnot [int]) { Write-Host "JZ/JNZ idx=$i src1 type=$($s1.GetType().Name) val=$s1" -ForegroundColor Yellow; $bad++ }
        }
        if ($bad -gt 8) { break }
    }
}
Write-Host ("Pre-scan: bad jump operands = {0}" -f $bad)

$x86Bytes = 0
try {
    $x86Bytes = X86-CompileModule
    Write-Host ("X86 bytes: {0}" -f $x86Bytes) -ForegroundColor Green
}
catch {
    Write-Host ("X86 EXCEPTION: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("ScriptStackTrace:") -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host ("Buffer at exception: {0} bytes" -f $script:x86_buf.Count)
}
