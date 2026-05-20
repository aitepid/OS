# diag-balance.ps1 -- 列出 12 个告警文件中的括号失衡详情（独立扫描）
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# 直接复制 hl-compile-pipeline.ps1 第 11-39 行的两个函数
$script:hlKeywords = @('let','mut','fn','return','if','else','while','for','in','print','quadrant','emit','spawn','near','fold','from','with','break','continue','try','catch','finally','import','as','assert','del','pass','elif','not','class','self','super','yield','raise','true','false','nil')

function Tokenize-HL {
    param([string]$src)
    $tokens = [System.Collections.ArrayList]::new()
    $i = 0; $len = $src.Length
    while ($i -lt $len) {
        $ch = $src[$i]
        if ([char]::IsWhiteSpace($ch)) { $i++; continue }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '/') { while ($i -lt $len -and $src[$i] -ne "`n") { $i++ }; continue }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '*') { $i += 2; while ($i -lt ($len-1)) { if ($src[$i] -eq '*' -and $src[$i+1] -eq '/') { $i += 2; break }; $i++ }; continue }
        if ([char]::IsDigit($ch) -or ($ch -eq '0' -and ($i+1) -lt $len -and $src[$i+1] -eq 'x')) {
            $num = ''
            if ($ch -eq '0' -and ($i+1) -lt $len -and $src[$i+1] -eq 'x') { $num = '0x'; $i += 2; while ($i -lt $len -and $src[$i] -match '[0-9a-fA-F]') { $num += $src[$i]; $i++ } }
            else { while ($i -lt $len -and $src[$i] -match '[\d\.]') { $num += $src[$i]; $i++ } }
            [void]$tokens.Add(@('Num', $num)); continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $q = $ch; $i++; $s = ''; while ($i -lt $len -and $src[$i] -ne $q) { if ($src[$i] -eq '\' -and ($i+1) -lt $len) { $s += $src[$i]; $i++; $s += $src[$i]; $i++ } else { $s += $src[$i]; $i++ } }; if ($i -lt $len) { $i++ }; [void]$tokens.Add(@('Str', $s)); continue }
        if ($ch -match '[a-zA-Z_]') { $id = ''; while ($i -lt $len -and $src[$i] -match '[a-zA-Z0-9_]') { $id += $src[$i]; $i++ }; if ($id -eq 'true' -or $id -eq 'false') { [void]$tokens.Add(@('Bool', $id)) } elseif ($id -eq 'nil') { [void]$tokens.Add(@('Nil', $id)) } elseif ($script:hlKeywords -contains $id) { [void]$tokens.Add(@($id, $id)) } else { [void]$tokens.Add(@('Ident', $id)) }; continue }
        $three = ''; if (($i+2) -lt $len) { $three = "$ch$($src[$i+1])$($src[$i+2])" }
        if ($three -eq '**=' -or $three -eq '//=' -or $three -eq '<<=' -or $three -eq '>>=' -or $three -eq '...') { [void]$tokens.Add(@($three, $three)); $i += 3; continue }
        $two = ''; if (($i+1) -lt $len) { $two = "$ch$($src[$i+1])" }
        $twoOps = @('**','==','!=','<=','>=','&&','||','->','+=','-=','*=','/=','%=','<<','>>','//','&=','|=','^=')
        if ($twoOps -contains $two) { [void]$tokens.Add(@($two, $two)); $i += 2; continue }
        $singleOps = @('+','-','*','/','%','=','!','<','>','(',')','{','}','[',']',',',';','.','~','&','|','^','@',':','#')
        if ($singleOps -contains [string]$ch) { [void]$tokens.Add(@([string]$ch, [string]$ch)); $i++; continue }
        $i++
    }
    [void]$tokens.Add(@('EOF', '')); return $tokens
}
function Test-Balanced { param($tokens); $stack = [System.Collections.Stack]::new(); $errors = [System.Collections.ArrayList]::new(); $openers = @{ ')' = '('; '}' = '{'; ']' = '[' }; foreach ($tok in $tokens) { $t = $tok[0]; if ($t -eq '(' -or $t -eq '{' -or $t -eq '[') { [void]$stack.Push($t) } elseif ($openers.ContainsKey($t)) { $expected = $openers[$t]; if ($stack.Count -eq 0) { [void]$errors.Add("Unmatched $t") } elseif ($stack.Peek() -ne $expected) { [void]$errors.Add("Mismatched $t") } else { [void]$stack.Pop() } } }; while ($stack.Count -gt 0) { [void]$errors.Add("Unclosed $($stack.Pop())") }; return $errors }

$warnFiles = @('a11y.hl','app_texteditor.hl','consistent_hash.hl','display_topology.hl','ime.hl','neural.hl','shell.hl','shell_dock.hl','shell_form.hl','shell_wallpaper.hl','vdesktop.hl','visual_audit.hl')
$hlDir = Join-Path $repoRoot 'bare-kernel\hl'

$totalBal = 0
foreach ($f in $warnFiles) {
    $p = Join-Path $hlDir $f
    if (-not (Test-Path $p)) { Write-Host "[MISS] $f"; continue }
    $code = Get-Content $p -Raw
    $toks = Tokenize-HL $code
    $errs = Test-Balanced $toks
    $totalBal += $errs.Count
    Write-Host ("=== {0}  ({1} bal, {2} bytes) ===" -f $f, $errs.Count, $code.Length) -ForegroundColor Cyan
    if ($errs.Count -eq 0) { Write-Host "  (none — only parse warning)"; continue }
    $grp = $errs | Group-Object | Sort-Object Count -Descending
    foreach ($g in $grp) { Write-Host ("  {0,3}x  {1}" -f $g.Count, $g.Name) }
    $lines = $code -split "`n"
    $dR = 0; $dC = 0; $dS = 0
    for ($li = 0; $li -lt $lines.Count; $li++) {
        $cl = $lines[$li]
        $cl = $cl -replace '//.*$',''
        $cl = $cl -replace '"[^"]*"',''
        $cl = $cl -replace "'[^']*'",''
        $dR += ([regex]::Matches($cl,'\(').Count - [regex]::Matches($cl,'\)').Count)
        $dC += ([regex]::Matches($cl,'\{').Count - [regex]::Matches($cl,'\}').Count)
        $dS += ([regex]::Matches($cl,'\[').Count - [regex]::Matches($cl,'\]').Count)
    }
    Write-Host ("  EOF depth: ()={0}  {{}}={1}  []={2}" -f $dR,$dC,$dS) -ForegroundColor DarkYellow
}
Write-Host ""
Write-Host ("总计 balance errors: {0}" -f $totalBal) -ForegroundColor Yellow
