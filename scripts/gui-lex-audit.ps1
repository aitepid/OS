# gui-lex-audit.ps1 -- Lex/parse audit of G1-G8 GUI modules (Sprint Phase 1.5)
#
# Loads the existing hl-compile-pipeline.ps1 tokenizer + balance checker and
# runs them against the 49 GUI .hl modules added across Sprints G1-G8.
# Reports per-file token count, paren/brace balance, fn count, and aggregate.

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# === Tokenizer (port of hl-compile-pipeline.ps1, no side effects) ===

function Tokenize-HL2 {
    param([string]$src)
    $kws = @('let','mut','fn','return','if','else','while','for','in','print','quadrant','emit','spawn','near','fold','from','with','break','continue','try','catch','finally','import','as','assert','del','pass','elif','not','class','self','super','yield','raise','true','false','nil')
    $tokens = [System.Collections.ArrayList]::new()
    $i = 0; $len = $src.Length
    while ($i -lt $len) {
        $ch = $src[$i]
        if ([char]::IsWhiteSpace($ch)) { $i++; continue }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '/') {
            while ($i -lt $len -and $src[$i] -ne "`n") { $i++ }; continue
        }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '*') {
            $i += 2
            while ($i -lt ($len-1)) {
                if ($src[$i] -eq '*' -and $src[$i+1] -eq '/') { $i += 2; break }
                $i++
            }
            continue
        }
        if ([char]::IsDigit($ch)) {
            $num = ''
            if ($ch -eq '0' -and ($i+1) -lt $len -and $src[$i+1] -eq 'x') {
                $num = '0x'; $i += 2
                while ($i -lt $len -and $src[$i] -match '[0-9a-fA-F]') { $num += $src[$i]; $i++ }
            } else {
                while ($i -lt $len -and $src[$i] -match '[\d\.]') { $num += $src[$i]; $i++ }
            }
            [void]$tokens.Add(@('Num',$num)); continue
        }
        if ($ch -eq '"' -or $ch -eq "'") {
            $q = $ch; $i++; $s = ''
            while ($i -lt $len -and $src[$i] -ne $q) {
                if ($src[$i] -eq '\' -and ($i+1) -lt $len) { $s += $src[$i]; $i++; $s += $src[$i]; $i++ }
                else { $s += $src[$i]; $i++ }
            }
            if ($i -lt $len) { $i++ }
            [void]$tokens.Add(@('Str',$s)); continue
        }
        if ($ch -match '[a-zA-Z_]') {
            $id = ''
            while ($i -lt $len -and $src[$i] -match '[a-zA-Z0-9_]') { $id += $src[$i]; $i++ }
            if ($kws -contains $id) { [void]$tokens.Add(@($id,$id)) }
            else { [void]$tokens.Add(@('Ident',$id)) }
            continue
        }
        $three = ''; if (($i+2) -lt $len) { $three = "$ch$($src[$i+1])$($src[$i+2])" }
        if ($three -in @('**=','//=','<<=','>>=','...')) { [void]$tokens.Add(@($three,$three)); $i += 3; continue }
        $two = ''; if (($i+1) -lt $len) { $two = "$ch$($src[$i+1])" }
        $twoOps = @('**','==','!=','<=','>=','&&','||','->','+=','-=','*=','/=','%=','<<','>>','//','&=','|=','^=')
        if ($twoOps -contains $two) { [void]$tokens.Add(@($two,$two)); $i += 2; continue }
        $singleOps = @('+','-','*','/','%','=','!','<','>','(',')','{','}','[',']',',',';','.','~','&','|','^','@',':','#')
        if ($singleOps -contains [string]$ch) { [void]$tokens.Add(@([string]$ch,[string]$ch)); $i++; continue }
        $i++
    }
    [void]$tokens.Add(@('EOF',''))
    return $tokens
}

function Check-Balance {
    param($tokens)
    $stack = [System.Collections.Stack]::new()
    $errors = [System.Collections.ArrayList]::new()
    $openers = @{ ')' = '('; '}' = '{'; ']' = '[' }
    foreach ($tok in $tokens) {
        $t = $tok[0]
        if ($t -eq '(' -or $t -eq '{' -or $t -eq '[') { [void]$stack.Push($t) }
        elseif ($openers.ContainsKey($t)) {
            $expected = $openers[$t]
            if ($stack.Count -eq 0) { [void]$errors.Add("Unmatched $t") }
            elseif ($stack.Peek() -ne $expected) { [void]$errors.Add("Mismatched $t") }
            else { [void]$stack.Pop() }
        }
    }
    while ($stack.Count -gt 0) { [void]$errors.Add("Unclosed $($stack.Pop())") }
    return $errors
}

function Count-Functions {
    param($tokens)
    $c = 0
    for ($j = 0; $j -lt $tokens.Count - 1; $j++) {
        if ($tokens[$j][0] -eq 'fn' -and $tokens[$j+1][0] -eq 'Ident') { $c++ }
    }
    return $c
}

# === GUI module roster (Sprints G1-G8) ===
$guiModules = @(
    # G1 -- foundation (4)
    'gfx_backbuffer','gfx_aa','gfx_path','font_atlas',
    # G2 -- compositor / effects (5)
    'compositor','gfx_blur','gfx_shadow','gfx_anim','eyecare',
    # G3 -- input + WM extensions (6)
    'input_pointer','input_gesture','input_touch','input_pen','wm_snap','dnd',
    # G4 -- adaptive layout + widgets (10)
    'adaptive_layout','widget_core','widget_button','widget_input','widget_select',
    'widget_container','widget_list','widget_feedback','widget_nav',
    # G5 -- shells (9)
    'shell_wallpaper','shell_topbar','shell_dock','shell_startmenu','shell_spotlight',
    'shell_controlcenter','shell_lockscreen','shell_notification','shell_form',
    # G6 -- core apps (5)
    'app_files','app_settings','app_terminal','app_texteditor','app_sysmon',
    # G7 -- multi-display + IME + vdesktop + mission control (4)
    'display_topology','ime','vdesktop','mission_control',
    # G8 -- polish (5)
    'gfx_hidpi','a11y','anim_tuning','shell_themes','visual_audit'
)

Write-Host '=== HicOS GUI Lex Audit (Phase 1.5) ===' -ForegroundColor Cyan
Write-Host "  Modules: $($guiModules.Count) files across Sprints G1-G8"
Write-Host ''

$totalBytes = 0
$totalTokens = 0
$totalFns = 0
$failed = [System.Collections.ArrayList]::new()
$idx = 0
foreach ($mod in $guiModules) {
    $idx++
    $path = "bare-kernel/hl/$mod.hl"
    if (-not (Test-Path $path)) {
        Write-Host ("  [{0,2}/{1}] MISSING  {2}" -f $idx, $guiModules.Count, $mod) -ForegroundColor Red
        [void]$failed.Add(@($mod, 'missing'))
        continue
    }
    $src = [System.IO.File]::ReadAllText($path)
    $bytes = $src.Length
    $totalBytes += $bytes
    $tokens = Tokenize-HL2 -src $src
    $tokCount = $tokens.Count - 1
    $totalTokens += $tokCount
    $balErrors = Check-Balance -tokens $tokens
    $fnCount = Count-Functions -tokens $tokens
    $totalFns += $fnCount
    $tag = 'OK '
    $col = 'Green'
    if ($balErrors.Count -gt 0) {
        $tag = 'ERR'
        $col = 'Red'
        [void]$failed.Add(@($mod, ($balErrors -join '; ')))
    }
    Write-Host ("  [{0,2}/{1}] {2}  {3,-22}  {4,5} B  {5,5} tok  {6,3} fn" -f `
        $idx, $guiModules.Count, $tag, $mod, $bytes, $tokCount, $fnCount) -ForegroundColor $col
}

Write-Host ''
Write-Host '=== Aggregate ===' -ForegroundColor Cyan
Write-Host ("  Files     : {0}" -f $guiModules.Count)
Write-Host ("  Bytes     : {0:N0}" -f $totalBytes)
Write-Host ("  Tokens    : {0:N0}" -f $totalTokens)
Write-Host ("  Functions : {0:N0}" -f $totalFns)
Write-Host ("  Failed    : {0}" -f $failed.Count)
if ($failed.Count -gt 0) {
    Write-Host '' -ForegroundColor Red
    Write-Host '=== Failures ===' -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host ("  {0,-22}  {1}" -f $f[0], $f[1]) -ForegroundColor Red
    }
    exit 1
}
Write-Host ''
Write-Host 'GUI LEX AUDIT: PASSED' -ForegroundColor Green
exit 0
