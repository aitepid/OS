# probe-unresolved.ps1 -- Sprint 35 static pre-scan: candidate unresolved symbols (upper bound)
# Skips the full 115-min pipeline. Strategy: called - defined - builtin - kernel = candidates.
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# stdlib builtins (from HILBERT_LANG_BNF.md section 4.1)
$builtins = @(
    'print','input',
    'int','float','str','bool','chr','ord','hex','to_string',
    'type_of','isinstance',
    'len','push','pop','range','set_at',
    'array_slice','array_find','array_contains','array_remove','array_reverse',
    'array_concat','array_sort','array_unique','array_flat','array_join',
    'str_len','str_char_at','str_sub','str_find','str_contains','str_starts_with',
    'str_ends_with','str_replace','str_split','str_trim','str_upper','str_lower',
    'str_repeat','str_pad_start','str_from_code','str_to_code',
    'abs','min','max','floor','round','clamp','pow','divmod','sum',
    'math_sqrt','math_pow','math_log2','math_gcd','math_lcm',
    'map_new','map_set','map_get','map_has','map_delete','map_keys','map_values',
    'map_entries','map_size','map_clear',
    'hilbert_encode','hilbert_decode','hilbert_dist',
    'map','filter','sorted','reversed','enumerate','zip','any','all',
    'dict','list','keys','values','items','hasattr','getattr','setattr',
    'set_new','set_add','set_union','set_intersection','set_difference','set_is_subset',
    # kernel-exposed builtins (bound via stub trampoline)
    'mem_read_u8','mem_read_u16','mem_read_u32','mem_read_u64',
    'mem_write_u8','mem_write_u16','mem_write_u32','mem_write_u64',
    'serial_puts','serial_hex_byte',
    # control-flow pseudo
    'self','super'
)
$builtinSet = @{}
foreach ($b in $builtins) { $builtinSet[$b] = $true }

# kernel-symbols.json
$kernelSet = @{}
$ksPath = Join-Path $repoRoot 'bare-kernel\kernel-symbols.json'
if (Test-Path $ksPath) {
    $ks = Get-Content $ksPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $ks.PSObject.Properties) { $kernelSet[$p.Name] = $true }
}

# Collect all .hl source files
$sources = @()
$sources += Get-ChildItem -Path (Join-Path $repoRoot 'bare-kernel\hl') -Filter '*.hl' -File
$sources += Get-ChildItem -Path $repoRoot -Filter 'HicOS_*.hl' -File
$extras = @('stdlib.hl','hl-bootstrap.hl','bootstrap.hl','build.hl','build-hl-image.hl','manifest.hl')
foreach ($e in $extras) {
    $p = Join-Path $repoRoot $e
    if (Test-Path $p) { $sources += Get-Item $p }
}

# Extract: fn <name>( definitions and call-site identifiers
$defined = @{}
$called  = @{}
foreach ($f in $sources) {
    $src = Get-Content $f.FullName -Raw -Encoding UTF8
    $src = $src -replace '//[^\n]*', ''
    foreach ($m in [regex]::Matches($src, '\bfn\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')) {
        $defined[$m.Groups[1].Value] = $true
    }
    foreach ($m in [regex]::Matches($src, '\b([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')) {
        $name = $m.Groups[1].Value
        if ($called.ContainsKey($name)) { $called[$name]++ } else { $called[$name] = 1 }
    }
}

# Exclude keywords / control structures
$keywords = @('if','elif','while','for','return','print','fn','let','mut','class','quadrant',
              'try','catch','finally','raise','assert','del','import','from','as','pass',
              'break','continue','yield','spawn','emit','warp','near','fold','in','not',
              'and','or','true','false','nil','self','super','match','case','do','then',
              'switch','default','typeof','sizeof','new','delete','using','with')
foreach ($k in $keywords) { $defined[$k] = $true; $builtinSet[$k] = $true }

# Candidates = called - defined - builtin - kernel - D-class noise
# D-class filters (false positives from regex):
#   - Names starting with uppercase letter (H-L convention: fn names are snake_case lowercase)
#     -> filters class constructors / type names: Set, Find, LCA, Key, Tree, Speed, OK
#   - Single-character names (F, O, q) -> always variables
#   - Two-character lowercase short names that are typical loop vars (re-include if frequent)
$cand = @{}
$noise = @{}
foreach ($name in $called.Keys) {
    if ($defined.ContainsKey($name)) { continue }
    if ($builtinSet.ContainsKey($name)) { continue }
    if ($kernelSet.ContainsKey($name)) { continue }
    # D-class: uppercase first letter -> probable class/type, not fn call
    if ($name -cmatch '^[A-Z]') { $noise[$name] = $called[$name]; continue }
    # D-class: single char -> probable variable
    if ($name.Length -le 1) { $noise[$name] = $called[$name]; continue }
    $cand[$name] = $called[$name]
}

# Sort and dump
$tmpDir = Join-Path $repoRoot '.tmp'
if (-not (Test-Path $tmpDir)) { [void](New-Item -ItemType Directory -Path $tmpDir -Force) }
$out = Join-Path $tmpDir 'unresolved-candidates.txt'

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Sprint 35 static pre-scan: candidate unresolved (upper bound by call sites)")
[void]$sb.AppendLine("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("# Sources: $($sources.Count) files")
[void]$sb.AppendLine("# Defined fns: $($defined.Count - $keywords.Count)")
[void]$sb.AppendLine("# Distinct call names: $($called.Keys.Count)")
[void]$sb.AppendLine("# Builtins/keywords: $($builtinSet.Keys.Count)")
[void]$sb.AppendLine("# Kernel symbols: $($kernelSet.Keys.Count)")
[void]$sb.AppendLine("# Candidate unresolved (distinct): $($cand.Keys.Count)")
[void]$sb.AppendLine("# D-class noise filtered (distinct): $($noise.Keys.Count)")
[void]$sb.AppendLine("#")
[void]$sb.AppendLine("# Format: <call_count>`t<symbol>")
[void]$sb.AppendLine("")
$sorted = $cand.GetEnumerator() | Sort-Object -Property Value -Descending
foreach ($kv in $sorted) {
    [void]$sb.AppendLine(("{0}`t{1}" -f $kv.Value, $kv.Key))
}
[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

Write-Host "Sources scanned     : $($sources.Count)" -ForegroundColor Cyan
Write-Host "Functions defined   : $($defined.Keys.Count - $keywords.Count)" -ForegroundColor White
Write-Host "Distinct call names : $($called.Keys.Count)" -ForegroundColor White
Write-Host "Kernel symbols      : $($kernelSet.Keys.Count)" -ForegroundColor White
Write-Host "Builtin/runtime     : $($builtins.Count)" -ForegroundColor White
Write-Host ("Candidate unresolved: {0}" -f $cand.Keys.Count) -ForegroundColor Yellow
Write-Host ("D-class noise filt. : {0}" -f $noise.Keys.Count) -ForegroundColor DarkGray
Write-Host ""
Write-Host "Top 30 by call frequency:" -ForegroundColor Cyan
$sorted | Select-Object -First 30 | ForEach-Object { Write-Host ("  {0,5}  {1}" -f $_.Value, $_.Name) }
Write-Host ""
Write-Host "Full dump: $out"
