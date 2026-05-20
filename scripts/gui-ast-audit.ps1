# gui-ast-audit.ps1 -- Phase 1.6 AST试构�?#
# �?gui-lex-audit 之上叠加一个简化的 Pratt 解析器，�?G1-G8 47 �?GUI
# 模块�?.hl 源码构建顶层 AST（let / let mut / fn）并打印每文件的函数
# 签名清单。任何解析错误以红字报告，不抛异常中断后续文件�?
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# === 1. Tokenizer (�?gui-lex-audit �? ===
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

# === 2. Parser 状�?===
$script:tk = $null
$script:p  = 0
function PPeek    { param([int]$n=0) return $script:tk[$script:p + $n] }
function PType    { param([int]$n=0) return $script:tk[$script:p + $n][0] }
function PEat     { $t = $script:tk[$script:p]; $script:p = $script:p + 1; return $t }
function PExpect  { param([string]$t)
    if ((PType) -ne $t) {
        $ctx = ''
        for ($k = [Math]::Max(0,$script:p-3); $k -le [Math]::Min($script:tk.Count-1,$script:p+1); $k++) {
            $ctx += " [$k]$($script:tk[$k][0])=$($script:tk[$k][1])"
        }
        throw "expect '$t' got '$(PType)'='$($script:tk[$script:p][1])' at tok#$($script:p) ctx:$ctx"
    }
    return (PEat)
}

# === 3. 优先级表（双目） ===
$binOps = @{
    '||' = 1; '&&' = 2;
    '==' = 3; '!=' = 3;
    '<'  = 4; '>'  = 4; '<=' = 4; '>=' = 4;
    '|'  = 5; '^'  = 5;
    '&'  = 6;
    '<<' = 7; '>>' = 7;
    '+'  = 8; '-'  = 8;
    '*'  = 9; '/'  = 9; '%' = 9; '//' = 9;
}
$assignOps = @('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=', '//=', '**=')

# === 4. 表达式解�?===
function PExpr {
    param([int]$minP=0)
    $left = PUnary
    while ($true) {
        $op = PType
        if ($binOps.ContainsKey($op)) {
            $prec = $binOps[$op]
            if ($prec -lt $minP) { break }
            [void](PEat)
            $right = PExpr -minP ($prec + 1)
            $left = @{ kind='BinOp'; op=$op; l=$left; r=$right }
            continue
        }
        break
    }
    return $left
}
function PUnary {
    $t = PType
    if ($t -eq '-' -or $t -eq '!' -or $t -eq 'not' -or $t -eq '~') {
        [void](PEat); $e = PUnary
        return @{ kind='UnOp'; op=$t; v=$e }
    }
    return PPostfix
}
function PPostfix {
    $e = PPrimary
    while ($true) {
        $t = PType
        if ($t -eq '(') {
            [void](PEat); $args = @()
            if ((PType) -ne ')') {
                $args += , (PExpr)
                while ((PType) -eq ',') { [void](PEat); $args += , (PExpr) }
            }
            [void](PExpect ')')
            $e = @{ kind='Call'; callee=$e; args=$args }
            continue
        }
        if ($t -eq '[') {
            [void](PEat); $idx = PExpr; [void](PExpect ']')
            $e = @{ kind='Index'; o=$e; i=$idx }; continue
        }
        if ($t -eq '.') {
            [void](PEat); $m = PExpect 'Ident'
            $e = @{ kind='Member'; o=$e; m=$m[1] }; continue
        }
        break
    }
    return $e
}
function PPrimary {
    $t = PPeek
    switch ($t[0]) {
        'Num'  { [void](PEat); return @{ kind='Num'; v=$t[1] } }
        'Str'  { [void](PEat); return @{ kind='Str'; v=$t[1] } }
        'Ident'{ [void](PEat); return @{ kind='Ident'; n=$t[1] } }
        'true' { [void](PEat); return @{ kind='Bool'; v=$true } }
        'false'{ [void](PEat); return @{ kind='Bool'; v=$false } }
        'nil'  { [void](PEat); return @{ kind='Nil' } }
        'self' { [void](PEat); return @{ kind='Ident'; n='self' } }
        'super'{ [void](PEat); return @{ kind='Ident'; n='super' } }
        'print'{ [void](PEat); return @{ kind='Ident'; n='print' } }
        '(' {
            [void](PEat); $e = PExpr; [void](PExpect ')'); return $e
        }
        '[' {
            [void](PEat); $els = @()
            if ((PType) -ne ']') {
                $els += ,(PExpr)
                while ((PType) -eq ',') { [void](PEat); $els += ,(PExpr) }
            }
            [void](PExpect ']'); return @{ kind='Array'; e=$els }
        }
    }
    # Soft keyword fallback: any kw-typed token whose value is a bare identifier
    if ($t[1] -match '^[a-zA-Z_][a-zA-Z0-9_]*$' -and $t[0] -ne 'EOF') {
        [void](PEat); return @{ kind='Ident'; n=$t[1] }
    }
    throw "unexpected primary '$($t[0])'='$($t[1])' at tok#$($script:p)"
}

# === 5. 语句解析 ===
function PBlock {
    [void](PExpect '{')
    $stmts = @()
    while ((PType) -ne '}' -and (PType) -ne 'EOF') {
        $stmts += ,(PStmt)
    }
    [void](PExpect '}')
    return @{ kind='Block'; s=$stmts }
}
function PStmt {
    $t = PType
    if ($t -eq 'let')      { return PLet }
    if ($t -eq 'return')   { [void](PEat); $v = $null; if ((PType) -ne ';') { $v = PExpr }; [void](PExpect ';'); return @{ kind='Return'; v=$v } }
    if ($t -eq 'if')       { return PIf }
    if ($t -eq 'while')    { [void](PEat); $c = PExpr; $b = PBlock; return @{ kind='While'; c=$c; b=$b } }
    if ($t -eq 'break')    { [void](PEat); [void](PExpect ';'); return @{ kind='Break' } }
    if ($t -eq 'continue') { [void](PEat); [void](PExpect ';'); return @{ kind='Continue' } }
    if ($t -eq '{')        { return PBlock }
    $e = PExpr
    $op = PType
    if ($assignOps -contains $op) {
        [void](PEat); $r = PExpr; [void](PExpect ';')
        return @{ kind='Assign'; op=$op; l=$e; r=$r }
    }
    [void](PExpect ';')
    return @{ kind='ExprStmt'; e=$e }
}
function PIf {
    [void](PExpect 'if'); $c = PExpr; $t = PBlock
    $f = $null
    if ((PType) -eq 'else') {
        [void](PEat)
        if ((PType) -eq 'if') { $f = PIf } else { $f = PBlock }
    }
    return @{ kind='If'; c=$c; t=$t; f=$f }
}
function PLet {
    [void](PExpect 'let')
    $mut = $false
    if ((PType) -eq 'mut') { [void](PEat); $mut = $true }
    $nm = (PExpect 'Ident')[1]
    $v = $null
    if ((PType) -eq '=') { [void](PEat); $v = PExpr }
    [void](PExpect ';')
    return @{ kind='Let'; mut=$mut; n=$nm; v=$v }
}
function PExpectName {
    # Accept Ident token, or any keyword-typed token whose value is a bare identifier
    # (covers params like 'from' which lex as kw but are just names).
    $tok = $script:tk[$script:p]
    if ($tok[0] -eq 'Ident' -or ($tok[1] -match '^[a-zA-Z_][a-zA-Z0-9_]*$')) {
        return (PEat)
    }
    throw "expect 'Ident' got '$($tok[0])'='$($tok[1])' at tok#$($script:p)"
}
function PFn {
    [void](PExpect 'fn')
    $nm = (PExpect 'Ident')[1]
    [void](PExpect '(')
    $params = @()
    if ((PType) -ne ')') {
        $params += (PExpectName)[1]
        while ((PType) -eq ',') { [void](PEat); $params += (PExpectName)[1] }
    }
    [void](PExpect ')')
    $body = PBlock
    return @{ kind='Fn'; n=$nm; p=$params; b=$body }
}

# === 6. 模块顶层 ===
function PModule {
    $decls = @()
    while ((PType) -ne 'EOF') {
        $t = PType
        if     ($t -eq 'let') { $decls += ,(PLet) }
        elseif ($t -eq 'fn')  { $decls += ,(PFn)  }
        elseif ($t -eq 'print') {
            # 顶层 print("...") 语句（loaded 标记等）
            $decls += ,(PStmt)
        }
        else {
            throw "unexpected top-level '$t' at tok#$($script:p)"
        }
    }
    return @{ kind='Module'; d=$decls }
}

# === 7. GUI 模块花名�?===
$guiModules = @(
    'gfx_backbuffer','gfx_aa','gfx_path','font_atlas',
    'compositor','gfx_blur','gfx_shadow','gfx_anim','eyecare',
    'input_pointer','input_gesture','input_touch','input_pen','wm_snap','dnd',
    'adaptive_layout','widget_core','widget_button','widget_input','widget_select',
    'widget_container','widget_list','widget_feedback','widget_nav',
    'shell_wallpaper','shell_topbar','shell_dock','shell_startmenu','shell_spotlight',
    'shell_controlcenter','shell_lockscreen','shell_notification','shell_form',
    'app_files','app_settings','app_terminal','app_texteditor','app_sysmon',
    'display_topology','ime','vdesktop','mission_control',
    'gfx_hidpi','a11y','anim_tuning','shell_themes','visual_audit'
)

function Count-Stmts { param($n)
    if ($null -eq $n) { return 0 }
    $c = 0
    if ($n.kind -eq 'Block') { foreach ($s in $n.s) { $c += 1 + (Count-Stmts $s) } }
    elseif ($n.kind -eq 'If') { $c += (Count-Stmts $n.t); if ($n.f) { $c += (Count-Stmts $n.f) } }
    elseif ($n.kind -eq 'While') { $c += (Count-Stmts $n.b) }
    elseif ($n.kind -eq 'Fn') { $c += (Count-Stmts $n.b) }
    return $c
}

Write-Host '=== HicOS GUI AST Audit (Phase 1.6) ===' -ForegroundColor Cyan
Write-Host "  Modules: $($guiModules.Count)"
Write-Host ''

$totFns = 0; $totLets = 0; $totStmts = 0
$failed = [System.Collections.ArrayList]::new()
$idx = 0
foreach ($mod in $guiModules) {
    $idx++
    $path = "bare-kernel/hl/$mod.hl"
    if (-not (Test-Path $path)) {
        Write-Host ("  [{0,2}/{1}] MISSING  {2}" -f $idx,$guiModules.Count,$mod) -ForegroundColor Red
        [void]$failed.Add(@($mod,'missing')); continue
    }
    $src = [System.IO.File]::ReadAllText($path)
    $script:tk = Tokenize-HL2 -src $src
    $script:p  = 0
    try {
        $ast = PModule
        $fns  = @($ast.d | Where-Object { $_.kind -eq 'Fn'  })
        $lets = @($ast.d | Where-Object { $_.kind -eq 'Let' })
        $totFns  += $fns.Count
        $totLets += $lets.Count
        $sCount = 0
        foreach ($d in $ast.d) { $sCount += (Count-Stmts $d) }
        $totStmts += $sCount
        Write-Host ("  [{0,2}/{1}] OK   {2,-22}  {3,3} fn  {4,3} let  {5,4} stmt" -f `
            $idx,$guiModules.Count,$mod,$fns.Count,$lets.Count,$sCount) -ForegroundColor Green
    } catch {
        Write-Host ("  [{0,2}/{1}] ERR  {2,-22}  {3}" -f `
            $idx,$guiModules.Count,$mod,$_.Exception.Message) -ForegroundColor Red
        [void]$failed.Add(@($mod,$_.Exception.Message))
    }
}

Write-Host ''
Write-Host '=== Aggregate ===' -ForegroundColor Cyan
Write-Host ("  Files     : {0}" -f $guiModules.Count)
Write-Host ("  Functions : {0}" -f $totFns)
Write-Host ("  Let decls : {0}" -f $totLets)
Write-Host ("  Stmts     : {0}" -f $totStmts)
Write-Host ("  Failed    : {0}" -f $failed.Count)
if ($failed.Count -gt 0) {
    Write-Host '=== Failures ===' -ForegroundColor Red
    foreach ($f in $failed) {
        Write-Host ("  {0,-22}  {1}" -f $f[0], $f[1]) -ForegroundColor Red
    }
    exit 1
}
Write-Host ''
Write-Host 'GUI AST AUDIT: PASSED' -ForegroundColor Green
exit 0
