# diag-balance-detail.ps1 -- Show exact balance errors per file with token context
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\diag-balance-detail.ps1

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

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
            if ($ch -eq '0' -and ($i+1) -lt $len -and $src[$i+1] -eq 'x') { $i += 2; $numS = $i; while ($i -lt $len -and $src[$i] -match '[0-9a-fA-F]') { $i++ }; $num = '0x' + $src.Substring($numS, $i - $numS) }
            else { $numS = $i; while ($i -lt $len -and $src[$i] -match '[\d\.]') { $i++ }; $num = $src.Substring($numS, $i - $numS) }
            [void]$tokens.Add(@('Num', $num)); continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $q = $ch; $i++; $s = ''; while ($i -lt $len -and $src[$i] -ne $q) { if ($src[$i] -eq '\' -and ($i+1) -lt $len) { $s += $src[$i]; $i++; $s += $src[$i]; $i++ } else { $s += $src[$i]; $i++ } }; if ($i -lt $len) { $i++ }; [void]$tokens.Add(@('Str', $s)); continue }
        if ($ch -match '[a-zA-Z_]') { $idS = $i; while ($i -lt $len -and $src[$i] -match '[a-zA-Z0-9_]') { $i++ }; $id = $src.Substring($idS, $i - $idS); if ($id -eq 'true' -or $id -eq 'false') { [void]$tokens.Add(@('Bool', $id)) } elseif ($id -eq 'nil') { [void]$tokens.Add(@('Nil', $id)) } elseif ($script:hlKeywords -contains $id) { [void]$tokens.Add(@($id, $id)) } else { [void]$tokens.Add(@('Ident', $id)) }; continue }
        $three = if (($i+2) -lt $len) { $src.Substring($i, 3) } else { '' }
        if ($three -eq '**=' -or $three -eq '//=' -or $three -eq '<<=' -or $three -eq '>>=' -or $three -eq '...') { [void]$tokens.Add(@($three, $three)); $i += 3; continue }
        $two = if (($i+1) -lt $len) { $src.Substring($i, 2) } else { '' }
        $twoOps = @('**','==','!=','<=','>=','&&','||','->','+=','-=','*=','/=','%=','<<','>>','//','&=','|=','^=')
        if ($twoOps -contains $two) { [void]$tokens.Add(@($two, $two)); $i += 2; continue }
        $singleOps = @('+','-','*','/','%','=','!','<','>','(',')','{','}','[',']',',',';','.','~','&','|','^','@',':','#')
        if ($singleOps -contains [string]$ch) { [void]$tokens.Add(@([string]$ch, [string]$ch)); $i++; continue }
        $i++
    }
    [void]$tokens.Add(@('EOF', '')); return $tokens
}

function Test-Balanced-Detail {
    param($tokens, [string]$fileName)
    $stack = [System.Collections.Stack]::new()
    $errors = [System.Collections.ArrayList]::new()
    $openers = @{ ')' = '('; '}' = '{'; ']' = '[' }
    $idx = 0
    foreach ($tok in $tokens) {
        $t = $tok[0]
        if ($t -eq '(' -or $t -eq '{' -or $t -eq '[') {
            [void]$stack.Push(@{ ch = $t; idx = $idx })
        } elseif ($openers.ContainsKey($t)) {
            $expected = $openers[$t]
            if ($stack.Count -eq 0) {
                Write-Host "  ERROR: Unmatched '$t' at token $idx (stack empty)" -ForegroundColor Red
                # Show context (prev 3 tokens)
                $ctx = for ($j = [Math]::Max(0,$idx-3); $j -le [Math]::Min($idx+2,$tokens.Count-1); $j++) { "$($tokens[$j][0]):'$($tokens[$j][1])'" }
                Write-Host "    Context: $($ctx -join ' ')" -ForegroundColor DarkGray
                [void]$errors.Add("Unmatched $t @ $idx")
            } elseif ($stack.Peek().ch -ne $expected) {
                $opener = $stack.Peek()
                Write-Host "  ERROR: Mismatched '$t' at token $idx (expected closer for '$($opener.ch)' opened at $($opener.idx))" -ForegroundColor Red
                $ctx = for ($j = [Math]::Max(0,$idx-3); $j -le [Math]::Min($idx+2,$tokens.Count-1); $j++) { "$($tokens[$j][0]):'$($tokens[$j][1])'" }
                Write-Host "    Context: $($ctx -join ' ')" -ForegroundColor DarkGray
                [void]$errors.Add("Mismatched $t @ $idx")
            } else {
                [void]$stack.Pop()
            }
        }
        $idx++
    }
    while ($stack.Count -gt 0) {
        $opener = $stack.Pop()
        Write-Host "  ERROR: Unclosed '$($opener.ch)' (opened at token $($opener.idx))" -ForegroundColor Red
        $ctx = for ($j = [Math]::Max(0,$opener.idx-1); $j -le [Math]::Min($opener.idx+3,$tokens.Count-1); $j++) { "$($tokens[$j][0]):'$($tokens[$j][1])'" }
        Write-Host "    Context: $($ctx -join ' ')" -ForegroundColor DarkGray
        [void]$errors.Add("Unclosed $($opener.ch) @ $($opener.idx)")
    }
    return $errors
}

# Files with known balance errors
$targets = @(
    'a11y', 'app_texteditor', 'consistent_hash', 'display_topology',
    'ime', 'neural', 'shell_dock', 'shell_form', 'shell_wallpaper',
    'vdesktop', 'visual_audit'
)

foreach ($name in $targets) {
    $path = Join-Path $repoRoot "bare-kernel/hl/$name.hl"
    if (-not (Test-Path $path)) { continue }
    $src = Get-Content $path -Raw -Encoding UTF8
    $tokens = Tokenize-HL $src
    $errs = Test-Balanced-Detail $tokens $name
    if ($errs.Count -gt 0) {
        Write-Host "=== $name.hl: $($errs.Count) errors ===" -ForegroundColor Yellow
    } else {
        Write-Host "=== $name.hl: OK ===" -ForegroundColor Green
    }
}
