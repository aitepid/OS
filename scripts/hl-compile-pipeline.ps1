# hl-compile-pipeline.ps1 -- H-L Compilation Pipeline (Phase 1+2)
# Phase 1: Tokenize all modules (mirrors hl-bootstrap.hl S2)
# Phase 2: Parse -> AST -> IR -> Optimize (mirrors S3 + ir.hl)
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot
$script:hlKeywords = @('let','mut','fn','return','if','else','while','for','in','print','quadrant','emit','spawn','near','fold','from','with','break','continue','try','catch','finally','import','as','assert','del','pass','elif','not','class','self','super','yield','raise','true','false','nil')
# ================================================================
#  PHASE 1: TOKENIZER
# ================================================================
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
function Count-Functions { param($tokens); $c = 0; for ($j = 0; $j -lt $tokens.Count - 1; $j++) { if ($tokens[$j][0] -eq 'fn' -and $tokens[$j+1][0] -eq 'Ident') { $c++ } }; return $c }
# ================================================================
#  PHASE 2: RECURSIVE-DESCENT PARSER (hl-bootstrap.hl S3 port)
# ================================================================
$script:ptok = $null; $script:ppos = 0; $script:pnodes = 0; $script:perrors = 0; $script:_ltok = @('EOF','')
function pk  { if ($script:ppos -lt $script:ptok_len) { return $script:ptok[$script:ppos] }; return @('EOF','') }
function adv { if ($script:ppos -lt $script:ptok_len) { $script:_ltok = $script:ptok[$script:ppos] } else { $script:_ltok = @('EOF','') }; $script:ppos++ }
function advt { adv; return $script:_ltok }
function chk([string]$ty) { return (pk)[0] -eq $ty }
function skp([string]$ty) { if (chk $ty) { $script:ppos++ } }
function eat([string]$ty) { if (chk $ty) { adv } else { throw "expected $ty got $((pk)[0])" } }
function nd($type) { $script:pnodes++; return $type }
function p_program { $stmts = [System.Collections.ArrayList]::new(); while ((pk)[0] -ne 'EOF') { try { $s = p_stmt; if ($null -ne $s) { [void]$stmts.Add($s) } } catch { $script:perrors++; while ($script:ppos -lt $script:ptok_len) { $t = (pk)[0]; if ($t -eq ';') { $script:ppos++; break }; if ($t -eq '}') { $script:ppos++; break }; if ($t -eq 'EOF') { break }; if ($t -eq 'let' -or $t -eq 'fn' -or $t -eq 'class' -or $t -eq 'if' -or $t -eq 'while' -or $t -eq 'for' -or $t -eq 'return' -or $t -eq 'print' -or $t -eq 'quadrant') { break }; $script:ppos++ } } }; return $stmts }
function p_stmt { $tt = (pk)[0]; if ($tt -eq '@') { return p_decorated }; if ($tt -eq 'let') { return p_let }; if ($tt -eq 'fn') { return p_fn }; if ($tt -eq 'class') { return p_class }; if ($tt -eq 'if') { return p_if }; if ($tt -eq 'while') { return p_while }; if ($tt -eq 'for') { return p_for }; if ($tt -eq 'return') { return p_return }; if ($tt -eq 'yield') { adv; $v = $null; if ((pk)[0] -ne ';' -and (pk)[0] -ne '}') { $v = p_expr }; skp ';'; return @((nd 'Yield'), $v) }; if ($tt -eq 'raise') { adv; $v = $null; if ((pk)[0] -ne ';' -and (pk)[0] -ne '}') { $v = p_expr }; skp ';'; return @((nd 'Raise'), $v) }; if ($tt -eq 'print') { return p_print }; if ($tt -eq 'quadrant') { return p_quadrant }; if ($tt -eq 'break') { adv; skp ';'; return @((nd 'Break')) }; if ($tt -eq 'continue') { adv; skp ';'; return @((nd 'Continue')) }; if ($tt -eq 'pass') { adv; skp ';'; return @((nd 'Pass')) }; if ($tt -eq 'try') { return p_try }; if ($tt -eq 'import') { return p_import }; if ($tt -eq 'from') { return p_from }; if ($tt -eq 'assert') { adv; $c = p_expr; $m = $null; if (chk ',') { adv; $m = p_expr }; skp ';'; return @((nd 'Assert'), $c, $m) }; if ($tt -eq 'del') { adv; $n = (advt)[1]; skp ';'; return @((nd 'Del'), $n) }; if ($tt -eq '{') { return p_block_stmt }; return p_expr_stmt }
function p_let { adv; $mut = $false; if (chk 'mut') { $mut = $true; adv }; if ((pk)[0] -in @('[','(')) { $close = if ((pk)[0] -eq '[') { ']' } else { ')' }; adv; $names = [System.Collections.ArrayList]::new(); while (-not (chk $close) -and -not (chk 'EOF')) { if ((pk)[0] -eq 'Ident' -or (pk)[1] -eq '_') { [void]$names.Add((advt)[1]) } elseif (chk '[') { [void]$names.Add('_nested'); p_skip_brackets } else { adv }; skp ',' }; skp $close; skp '='; $val = p_expr; skp ';'; return @((nd 'LetDestruct'), $names, $mut, $val) }; $name = (advt)[1]; if (chk ':') { adv; while ((pk)[0] -in @('Ident','[',']',',','|')) { adv } }; $init = $null; if (chk '=') { adv; $init = p_expr }; skp ';'; return @((nd 'Let'), $name, $mut, $init) }
function p_skip_brackets { $depth = 0; while ($script:ppos -lt $script:ptok_len) { $t = (pk)[0]; if ($t -eq '[' -or $t -eq '(') { $depth++; adv } elseif ($t -eq ']' -or $t -eq ')') { $depth--; adv; if ($depth -le 0) { return } } else { adv } } }
function p_fn { adv; $name = (advt)[1]; eat '('; $params = [System.Collections.ArrayList]::new(); if (-not (chk ')')) { [void]$params.Add((p_param)); while (chk ',') { adv; [void]$params.Add((p_param)) } }; eat ')'; if (chk '->') { adv; while ((pk)[0] -in @('Ident','[',']',',','|')) { adv } }; if (chk ';') { adv; return @((nd 'FnDecl'), $name, $params) }; $body = p_block; return @((nd 'FnDef'), $name, $params, $body) }
function p_param { if (chk '*') { adv; $n = (advt)[1]; p_param_type; return "*$n" }; if (chk '**') { adv; $n = (advt)[1]; p_param_type; return "**$n" }; $n = (advt)[1]; p_param_type; if (chk '=') { adv; $null = p_expr }; return $n }
function p_param_type { if (chk ':') { adv; while ((pk)[0] -in @('Ident','[',']',',','|')) { adv } } }
function p_class { adv; $name = (advt)[1]; $parent = $null; if (chk ':') { adv; $parent = (advt)[1] }; $body = p_block; return @((nd 'ClassDef'), $name, $parent, $body) }
function p_if { adv; $cond = p_expr; $then = p_block; $els = $null; if (chk 'elif') { $els = @(,(p_if)) } elseif (chk 'else') { adv; if ((pk)[0] -in @('if','elif')) { $els = @(,(p_if)) } else { $els = p_block } }; return @((nd 'If'), $cond, $then, $els) }
function p_while { adv; $cond = p_expr; $body = p_block; return @((nd 'While'), $cond, $body) }
function p_for { adv; $var = (advt)[1]; adv; $iter = p_expr; $body = p_block; return @((nd 'For'), $var, $iter, $body) }
function p_return { adv; $val = $null; if ((pk)[0] -ne ';' -and (pk)[0] -ne '}') { $val = p_expr }; skp ';'; return @((nd 'Return'), $val) }
function p_print { adv; eat '('; $val = p_expr; eat ')'; skp ';'; return @((nd 'Print'), $val) }
function p_quadrant { adv; $name = (advt)[1]; $body = p_block; return @((nd 'Quadrant'), $name, $body) }
function p_try { adv; $tbody = p_block; $catches = [System.Collections.ArrayList]::new(); while (chk 'catch') { adv; $cn = $null; $ct = $null; if (chk 'Ident') { $cn = (advt)[1]; if (chk ':') { adv; $ct = (advt)[1] } }; $cb = p_block; [void]$catches.Add(@($cn, $ct, $cb)) }; $fin = $null; if (chk 'finally') { adv; $fin = p_block }; return @((nd 'Try'), $tbody, $catches, $fin) }
function p_import { adv; $path = (advt)[1]; $alias = $null; if (chk 'as') { adv; $alias = (advt)[1] }; skp ';'; return @((nd 'Import'), $path, $alias) }
function p_from { adv; $mod = (advt)[1]; adv; $name = (advt)[1]; skp ';'; return @((nd 'Import'), "$mod.$name", $null) }
function p_decorated { $decs = [System.Collections.ArrayList]::new(); while (chk '@') { adv; $dn = (advt)[1]; if (chk '(') { adv; $depth = 1; while ($depth -gt 0 -and (pk)[0] -ne 'EOF') { if ((pk)[0] -eq '(') { $depth++ }; if ((pk)[0] -eq ')') { $depth-- }; if ($depth -gt 0) { adv } }; skp ')' }; [void]$decs.Add($dn) }; $inner = p_stmt; return @((nd 'Decorated'), $decs, $inner) }
function p_block { eat '{'; $stmts = [System.Collections.ArrayList]::new(); while (-not (chk '}') -and -not (chk 'EOF')) { try { $s = p_stmt; if ($null -ne $s) { [void]$stmts.Add($s) } } catch { $script:perrors++; while ($script:ppos -lt $script:ptok_len) { $t = (pk)[0]; if ($t -eq ';') { $script:ppos++; break }; if ($t -eq '}' -or $t -eq 'EOF') { break }; if ($t -eq 'let' -or $t -eq 'fn' -or $t -eq 'if' -or $t -eq 'while' -or $t -eq 'for' -or $t -eq 'return') { break }; $script:ppos++ } } }; skp '}'; return ,$stmts }
function p_block_stmt { $b = p_block; return @((nd 'Block'), $b) }
function p_expr_stmt { $expr = p_expr; $aop = (pk)[0]; if ($expr -is [array] -and $expr.Count -ge 2 -and $expr[0] -eq 'Var' -and ($aop -in @('=','+=','-=','*=','/=','%=','**='))) { adv; $val = p_expr; skp ';'; if ($aop -eq '=') { return @((nd 'Assign'), $expr[1], $val) }; $binop = switch ($aop) { '+=' { '+' } '-=' { '-' } '*=' { '*' } '/=' { '/' } '%=' { '%' } '**=' { '**' } }; return @((nd 'Assign'), $expr[1], @((nd 'BinOp'), $binop, $expr, $val)) }; if ($expr -is [array] -and $expr.Count -ge 3 -and $expr[0] -eq 'Index' -and (chk '=')) { adv; $val = p_expr; skp ';'; return @((nd 'IndexAssign'), $expr[1], $expr[2], $val) }; if ($expr -is [array] -and $expr.Count -ge 3 -and $expr[0] -eq 'Field' -and ((pk)[0] -in @('=','+=','-=','*=','/='))) { $fop = (advt)[0]; $val = p_expr; skp ';'; if ($fop -eq '=') { return @((nd 'FieldAssign'), $expr[1], $expr[2], $val) }; $binop = switch ($fop) { '+=' { '+' } '-=' { '-' } '*=' { '*' } '/=' { '/' } }; return @((nd 'FieldAssign'), $expr[1], $expr[2], @((nd 'BinOp'), $binop, $expr, $val)) }; skp ';'; return @((nd 'ExprStmt'), $expr) }
function p_expr   { return p_or }
function p_or     { $l = p_and;    while (chk '||') { adv; $r = p_and;    $l = @((nd 'BinOp'), '||', $l, $r) }; return $l }
function p_and    { $l = p_bitor;  while (chk '&&') { adv; $r = p_bitor;  $l = @((nd 'BinOp'), '&&', $l, $r) }; return $l }
function p_bitor  { $l = p_bitxor; while (chk '|')  { adv; $r = p_bitxor; $l = @((nd 'BinOp'), '|',  $l, $r) }; return $l }
function p_bitxor { $l = p_bitand; while (chk '^')  { adv; $r = p_bitand; $l = @((nd 'BinOp'), '^',  $l, $r) }; return $l }
function p_bitand { $l = p_eq;     while (chk '&')  { adv; $r = p_eq;     $l = @((nd 'BinOp'), '&',  $l, $r) }; return $l }
function p_eq     { $l = p_cmp;    while ((pk)[0] -in @('==','!=')) { $op = (advt)[0]; $r = p_cmp; $l = @((nd 'BinOp'), $op, $l, $r) }; return $l }
function p_cmp    { $l = p_shift; while ((pk)[0] -in @('<','>','<=','>=','in','not')) { $op = (pk)[0]; if ($op -eq 'in') { adv; $r = p_shift; $l = @((nd 'BinOp'), 'in', $l, $r) } elseif ($op -eq 'not') { adv; adv; $r = p_shift; $l = @((nd 'Unary'), '!', @((nd 'BinOp'), 'in', $l, $r)) } else { $op = (advt)[0]; $r = p_shift; $l = @((nd 'BinOp'), $op, $l, $r) } }; return $l }
function p_shift  { $l = p_add; while ((pk)[0] -in @('<<','>>')) { $op = (advt)[0]; $r = p_add; $l = @((nd 'BinOp'), $op, $l, $r) }; return $l }
function p_add    { $l = p_mul; while ((pk)[0] -in @('+','-')) { $op = (advt)[0]; $r = p_mul; $l = @((nd 'BinOp'), $op, $l, $r) }; return $l }
function p_mul    { $l = p_power; while ((pk)[0] -in @('*','/','%','//')) { $op = (advt)[0]; $r = p_power; $l = @((nd 'BinOp'), $op, $l, $r) }; return $l }
function p_power  { $base = p_unary; if (chk '**') { adv; $exp = p_power; return @((nd 'BinOp'), '**', $base, $exp) }; return $base }
function p_unary  { if (chk '-') { adv; $r = p_unary; return @((nd 'Unary'), '-', $r) }; if (chk '!') { adv; $r = p_unary; return @((nd 'Unary'), '!', $r) }; if (chk 'not') { adv; $r = p_unary; return @((nd 'Unary'), '!', $r) }; if (chk '~') { adv; $r = p_unary; return @((nd 'Unary'), '~', $r) }; return p_postfix }
function p_postfix { $e = p_primary; while ($true) { if (chk '(') { adv; $args = [System.Collections.ArrayList]::new(); if (-not (chk ')')) { [void]$args.Add((p_expr)); while (chk ',') { adv; if (-not (chk ')')) { [void]$args.Add((p_expr)) } } }; eat ')'; $e = @((nd 'Call'), $e, $args) } elseif (chk '[') { adv; if (chk ':') { adv; $end = p_expr; eat ']'; $e = @((nd 'Slice'), $e, @('Num','0'), $end) } else { $idx = p_expr; if (chk ':') { adv; if (chk ']') { eat ']'; $e = @((nd 'Slice'), $e, $idx, $null) } else { $end = p_expr; eat ']'; $e = @((nd 'Slice'), $e, $idx, $end) } } else { eat ']'; $e = @((nd 'Index'), $e, $idx) } } } elseif (chk '.') { adv; $field = (advt)[1]; if (chk '(') { adv; $args = [System.Collections.ArrayList]::new(); if (-not (chk ')')) { [void]$args.Add((p_expr)); while (chk ',') { adv; if (-not (chk ')')) { [void]$args.Add((p_expr)) } } }; eat ')'; $e = @((nd 'MethodCall'), $e, $field, $args) } else { $e = @((nd 'Field'), $e, $field) } } else { break } }; return $e }
function p_primary {
    $tt = (pk)[0]; $val = (pk)[1]
    if ($tt -eq 'Num')   { adv; return @((nd 'Num'), $val) }
    if ($tt -eq 'Str')   { adv; return @((nd 'Str'), $val) }
    if ($tt -eq 'Bool')  { adv; return @((nd 'Bool'), $val) }
    if ($tt -eq 'Nil')   { adv; return @((nd 'Nil')) }
    if ($tt -eq 'Ident') { adv; return @((nd 'Var'), $val) }
    if ($tt -eq 'self')  { adv; return @((nd 'Var'), 'self') }
    if ($tt -eq 'if')    { adv; $cond = p_expr; $then = p_block; $els = $null; if (chk 'else') { adv; $els = p_block }; return @((nd 'IfExpr'), $cond, $then, $els) }
    if ($tt -eq '(') { adv; $e = p_expr; eat ')'; return $e }
    if ($tt -eq '[') {
        adv; $elems = [System.Collections.ArrayList]::new()
        if (-not (chk ']')) {
            [void]$elems.Add((p_expr))
            if (chk 'for') { adv; $vn = (advt)[1]; adv; $it = p_expr; $flt = $null; if (chk 'if') { adv; $flt = p_expr }; eat ']'; return @((nd 'ListComp'), $elems[0], $vn, $it, $flt) }
            while (chk ',') { adv; if (-not (chk ']')) { [void]$elems.Add((p_expr)) } }
        }
        eat ']'; return @((nd 'Array'), $elems)
    }
    if ($tt -eq '{') {
        $next = $script:ptok[$script:ppos + 1][0]
        if ($next -eq '}') { adv; adv; return @((nd 'Dict'), @()) }
        $next2 = if (($script:ppos + 2) -lt $script:ptok_len) { $script:ptok[$script:ppos + 2][0] } else { '' }
        if ($next2 -eq ':') { adv; $pairs = [System.Collections.ArrayList]::new(); while (-not (chk '}') -and -not (chk 'EOF')) { $k = p_expr; eat ':'; $v = p_expr; [void]$pairs.Add(@($k, $v)); skp ',' }; skp '}'; return @((nd 'Dict'), $pairs) }
    }
    if ($tt -eq 'fn' -and ($script:ppos + 1) -lt $script:ptok_len -and $script:ptok[$script:ppos + 1][0] -eq '(') {
        adv; eat '('; $params = [System.Collections.ArrayList]::new()
        if (-not (chk ')')) { [void]$params.Add((advt)[1]); while (chk ',') { adv; [void]$params.Add((advt)[1]) } }
        eat ')'
        if (chk '{') { $body = p_block; return @((nd 'Lambda'), $params, $body) }
        else { $bexpr = p_expr; return @((nd 'Lambda'), $params, @(@((nd 'Return'), $bexpr))) }
    }
    adv; return @((nd 'Nil'))
}

# ================================================================
#  PHASE 3: AST -> IR LOWERING (mirrors ir.hl)
# ================================================================
# IR instruction: [op, dst, src1, src2]
# 37 opcodes mirroring bare-kernel/hl/ir.hl
$script:IR_CONST=1;  $script:IR_COPY=2;  $script:IR_ADD=3;  $script:IR_SUB=4
$script:IR_MUL=5;    $script:IR_DIV=6;   $script:IR_MOD=7;  $script:IR_NEG=8
$script:IR_AND=9;    $script:IR_OR=10;    $script:IR_XOR=11; $script:IR_SHL=12
$script:IR_SHR=13;   $script:IR_NOT=14;   $script:IR_CMP_EQ=15; $script:IR_CMP_NE=16
$script:IR_CMP_LT=17;$script:IR_CMP_LE=18;$script:IR_CMP_GT=19;$script:IR_CMP_GE=20
$script:IR_JMP=21;   $script:IR_JZ=22;    $script:IR_JNZ=23; $script:IR_LABEL=24
$script:IR_CALL=25;  $script:IR_ARG=26;   $script:IR_RET=27; $script:IR_LOAD=28
$script:IR_STORE=29; $script:IR_PHI=30;   $script:IR_NOP=31; $script:IR_STR_CONST=32
$script:IR_PRINT=36
$script:IR_PORT_OUT=38
$script:IR_PORT_IN=39;   $script:IR_CLI=40;     $script:IR_STI=41;     $script:IR_HLT=42
$script:IR_MEM_STORE8=43; $script:IR_MEM_LOAD64=44; $script:IR_MEM_STORE64=45; $script:IR_LIDT=46
$script:IR_PORT_OUT32=47; $script:IR_PORT_IN32=48; $script:IR_MEM_STORE32=49; $script:IR_MEM_LOAD32=50; $script:IR_MEM_LOAD8=51
$script:IR_PARAM=52  # function parameter receive (ABI reg -> vreg)

$script:ir_op = $null
$script:ir_dead = $null; $script:ir_count = 0; $script:ir_next_tmp = 0
$script:ir_label_counter = 0; $script:ir_vars = $null; $script:ir_fns = $null

function IR-Init {
    $script:ir_op = [int[]]::new(16384); $script:ir_dst = [int[]]::new(16384)
    $script:ir_src1 = [System.Object[]]::new(16384); $script:ir_src2 = [System.Object[]]::new(16384)
    $script:ir_dead = [int[]]::new(16384)
    $script:ir_count = 0; $script:ir_next_tmp = 0; $script:ir_label_counter = 0
    $script:ir_vars = @{}; $script:ir_fns = @{}
}
function IR-Tmp  { $t = $script:ir_next_tmp; $script:ir_next_tmp++; return $t }
function IR-Lbl  { $script:ir_label_counter++; return $script:ir_label_counter }
function IR-Emit($op, $d, $s1, $s2) {
    $i = $script:ir_count; if ($i -ge 16384) { return -1 }
    $script:ir_op[$i]=$op; $script:ir_dst[$i]=$d; $script:ir_src1[$i]=$s1; $script:ir_src2[$i]=$s2
    $script:ir_dead[$i]=0; $script:ir_count++; return $i
}

function IR-LowerExpr($node) {
    if ($null -eq $node) { return 0 }
    if ($node -isnot [array] -or $node.Count -lt 1) { $t=IR-Tmp; IR-Emit $IR_CONST $t 0 0 | Out-Null; return $t }
    $nt = $node[0]
    if ($nt -eq 'Num')  { $t=IR-Tmp; $v=0; try{$v=[long]$node[1]}catch{}; IR-Emit $IR_CONST $t $v 0 | Out-Null; return $t }
    if ($nt -eq 'Str')  { $t=IR-Tmp; IR-Emit $IR_STR_CONST $t $node[1] 0 | Out-Null; return $t }
    if ($nt -eq 'Bool') { $t=IR-Tmp; $v=if($node[1] -eq 'true'){1}else{0}; IR-Emit $IR_CONST $t $v 0 | Out-Null; return $t }
    if ($nt -eq 'Nil')  { $t=IR-Tmp; IR-Emit $IR_CONST $t 0 0 | Out-Null; return $t }
    if ($nt -eq 'Var')  { $vr=$script:ir_vars[$node[1]]; if($null -ne $vr){$t=IR-Tmp; IR-Emit $IR_COPY $t $vr 0 | Out-Null; return $t}; $t=IR-Tmp; IR-Emit $IR_CONST $t 0 0 | Out-Null; return $t }
    if ($nt -eq 'BinOp') {
        $l = IR-LowerExpr $node[2]; $r = IR-LowerExpr $node[3]; $t = IR-Tmp
        $opMap = @{'+' = $IR_ADD; '-' = $IR_SUB; '*' = $IR_MUL; '/' = $IR_DIV; '%' = $IR_MOD
                   '&' = $IR_AND; '|' = $IR_OR; '^' = $IR_XOR; '<<' = $IR_SHL; '>>' = $IR_SHR
                   '==' = $IR_CMP_EQ; '!=' = $IR_CMP_NE; '<' = $IR_CMP_LT; '<=' = $IR_CMP_LE
                   '>' = $IR_CMP_GT; '>=' = $IR_CMP_GE }
        $irop = $opMap[$node[1]]; if ($null -eq $irop) { $irop = $IR_COPY }
        IR-Emit $irop $t $l $r | Out-Null; return $t
    }
    if ($nt -eq 'Unary') {
        $inner = IR-LowerExpr $node[2]; $t = IR-Tmp
        $uop = if ($node[1] -eq '-') { $IR_NEG } elseif ($node[1] -in @('!','~')) { $IR_NOT } else { $IR_COPY }
        IR-Emit $uop $t $inner 0 | Out-Null; return $t
    }
    if ($nt -eq 'Call') {
        $args = $node[2]; $ai = 0
        $fn = ''; if ($node[1] -is [array] -and $node[1].Count -ge 2 -and $node[1][0] -eq 'Var') { $fn = $node[1][1] }
        # Intrinsic: port_out_u8(port, value) -> IR_PORT_OUT
        if ($fn -eq 'port_out_u8' -and $args.Count -ge 2) {
            $portReg = IR-LowerExpr $args[0]
            $valReg  = IR-LowerExpr $args[1]
            $t = IR-Tmp
            IR-Emit $IR_PORT_OUT $t $portReg $valReg | Out-Null
            return $t
        }
        # Intrinsic: port_in_u8(port) -> IR_PORT_IN (returns value in RAX)
        if ($fn -eq 'port_in_u8' -and $args.Count -ge 1) {
            $portReg = IR-LowerExpr $args[0]
            $t = IR-Tmp
            IR-Emit $IR_PORT_IN $t $portReg 0 | Out-Null
            return $t
        }
        # Intrinsic: cli() -> IR_CLI
        if ($fn -eq 'cli') { $t = IR-Tmp; IR-Emit $IR_CLI $t 0 0 | Out-Null; return $t }
        # Intrinsic: sti() -> IR_STI
        if ($fn -eq 'sti') { $t = IR-Tmp; IR-Emit $IR_STI $t 0 0 | Out-Null; return $t }
        # Intrinsic: hlt() -> IR_HLT
        if ($fn -eq 'hlt') { $t = IR-Tmp; IR-Emit $IR_HLT $t 0 0 | Out-Null; return $t }
        # Intrinsic: port_out_u32(port, val) -> IR_PORT_OUT32
        if ($fn -eq 'port_out_u32' -and $args.Count -ge 2) {
            $portReg = IR-LowerExpr $args[0]; $valReg = IR-LowerExpr $args[1]
            $t = IR-Tmp; IR-Emit $IR_PORT_OUT32 $t $portReg $valReg | Out-Null; return $t
        }
        # Intrinsic: port_in_u32(port) -> IR_PORT_IN32
        if ($fn -eq 'port_in_u32' -and $args.Count -ge 1) {
            $portReg = IR-LowerExpr $args[0]
            $t = IR-Tmp; IR-Emit $IR_PORT_IN32 $t $portReg 0 | Out-Null; return $t
        }
        # Intrinsic: mem_write_u8(addr, val) -> IR_MEM_STORE8
        if ($fn -eq 'mem_write_u8' -and $args.Count -ge 2) {
            $addrReg = IR-LowerExpr $args[0]; $valReg = IR-LowerExpr $args[1]
            $t = IR-Tmp; IR-Emit $IR_MEM_STORE8 $t $addrReg $valReg | Out-Null; return $t
        }
        # Intrinsic: mem_write_u32(addr, val) -> IR_MEM_STORE32
        if ($fn -eq 'mem_write_u32' -and $args.Count -ge 2) {
            $addrReg = IR-LowerExpr $args[0]; $valReg = IR-LowerExpr $args[1]
            $t = IR-Tmp; IR-Emit $IR_MEM_STORE32 $t $addrReg $valReg | Out-Null; return $t
        }
        # Intrinsic: mem_read_u8(addr) -> IR_MEM_LOAD8
        if ($fn -eq 'mem_read_u8' -and $args.Count -ge 1) {
            $addrReg = IR-LowerExpr $args[0]
            $t = IR-Tmp; IR-Emit $IR_MEM_LOAD8 $t $addrReg 0 | Out-Null; return $t
        }
        # Intrinsic: mem_read_u32(addr) -> IR_MEM_LOAD32
        if ($fn -eq 'mem_read_u32' -and $args.Count -ge 1) {
            $addrReg = IR-LowerExpr $args[0]
            $t = IR-Tmp; IR-Emit $IR_MEM_LOAD32 $t $addrReg 0 | Out-Null; return $t
        }
        # Intrinsic: mem_read_u64(addr) -> IR_MEM_LOAD64
        if ($fn -eq 'mem_read_u64' -and $args.Count -ge 1) {
            $addrReg = IR-LowerExpr $args[0]
            $t = IR-Tmp; IR-Emit $IR_MEM_LOAD64 $t $addrReg 0 | Out-Null; return $t
        }
        # Intrinsic: mem_write_u64(addr, val) -> IR_MEM_STORE64
        if ($fn -eq 'mem_write_u64' -and $args.Count -ge 2) {
            $addrReg = IR-LowerExpr $args[0]; $valReg = IR-LowerExpr $args[1]
            $t = IR-Tmp; IR-Emit $IR_MEM_STORE64 $t $addrReg $valReg | Out-Null; return $t
        }
        # Intrinsic: lidt(addr) -> IR_LIDT
        if ($fn -eq 'lidt' -and $args.Count -ge 1) {
            $addrReg = IR-LowerExpr $args[0]
            $t = IR-Tmp; IR-Emit $IR_LIDT $t $addrReg 0 | Out-Null; return $t
        }
        foreach ($a in $args) { $av = IR-LowerExpr $a; IR-Emit $IR_ARG $ai $av 0 | Out-Null; $ai++ }
        $t = IR-Tmp
        # Store function label (local) or name string (external) for linker
        $fl = if ($script:ir_fns.ContainsKey($fn)) { $script:ir_fns[$fn] } else { $fn }
        IR-Emit $IR_CALL $t $fl $ai | Out-Null; return $t
    }
    if ($nt -eq 'Index') { $base = IR-LowerExpr $node[1]; $idx = IR-LowerExpr $node[2]; $t = IR-Tmp; IR-Emit $IR_LOAD $t $base $idx | Out-Null; return $t }
    if ($nt -eq 'Array') { $t = IR-Tmp; IR-Emit $IR_CONST $t 0 0 | Out-Null; return $t }
    if ($nt -eq 'IfExpr') { $c=IR-LowerExpr $node[1]; $el=IR-Lbl; $end=IR-Lbl; IR-Emit $IR_JZ $c $el 0|Out-Null; $tv=0; if($node[2] -is [array] -and $node[2].Count -gt 0){$tv=IR-LowerExpr $node[2][0]}; IR-Emit $IR_JMP $end 0 0|Out-Null; IR-Emit $IR_LABEL $el 0 0|Out-Null; $ev=0; if($null -ne $node[3] -and $node[3] -is [array] -and $node[3].Count -gt 0){$ev=IR-LowerExpr $node[3][0]}; IR-Emit $IR_LABEL $end 0 0|Out-Null; $t=IR-Tmp; IR-Emit $IR_COPY $t $tv 0|Out-Null; return $t }
    # Fallback
    $t = IR-Tmp; IR-Emit $IR_CONST $t 0 0 | Out-Null; return $t
}

# Unwrap a body produced by p_block. p_block returns ",$stmts" — a 1-element wrapper
# whose [0] is an ArrayList of statements. Without unwrapping, foreach iterates the
# wrapper once and hands the ArrayList to IR-LowerStmt as if it were a single stmt.
function IR-StmtBody($body) {
    if ($null -eq $body) { return @() }
    if ($body -is [System.Collections.IList] -and $body.Count -eq 1 -and $body[0] -is [System.Collections.IList] -and -not ($body[0] -is [string])) {
        $inner = $body[0]
        if ($inner.Count -ge 1 -and -not ($inner[0] -is [string])) { return $inner }
        if ($inner -is [System.Collections.ArrayList]) { return $inner }
    }
    return $body
}

function IR-LowerStmt($node) {
    if ($null -eq $node) { return }
    if ($node -isnot [System.Collections.IList] -or $node.Count -lt 1) { return }
    $nt = $node[0]
    if ($nt -isnot [string]) { foreach ($s in $node) { IR-LowerStmt $s }; return }
    if ($nt -eq 'Let') { $vr = IR-Tmp; $script:ir_vars[$node[1]] = $vr; if ($null -ne $node[3]) { $val = IR-LowerExpr $node[3]; IR-Emit $IR_COPY $vr $val 0 | Out-Null } else { IR-Emit $IR_CONST $vr 0 0 | Out-Null }; return }
    if ($nt -eq 'Assign') { $val = IR-LowerExpr $node[2]; $vr = $script:ir_vars[$node[1]]; if ($null -ne $vr) { IR-Emit $IR_COPY $vr $val 0 | Out-Null }; return }
    if ($nt -eq 'FnDef') { $lbl = IR-Lbl; $script:ir_fns[$node[1]] = $lbl; IR-Emit $IR_LABEL $lbl 0 0 | Out-Null; $pi=0; if ($node[2] -is [System.Collections.IList]) { foreach ($p in $node[2]) { $pv=IR-Tmp; $script:ir_vars[$p]=$pv; IR-Emit $IR_PARAM $pv $pi 0|Out-Null; $pi++ } }; foreach ($s in (IR-StmtBody $node[3])) { IR-LowerStmt $s }; $z=IR-Tmp; IR-Emit $IR_CONST $z 0 0|Out-Null; IR-Emit $IR_RET $z 0 0|Out-Null; return }
    if ($nt -eq 'Return') { if ($null -ne $node[1]) { $val = IR-LowerExpr $node[1]; IR-Emit $IR_RET $val 0 0 | Out-Null } else { $z=IR-Tmp; IR-Emit $IR_CONST $z 0 0|Out-Null; IR-Emit $IR_RET $z 0 0|Out-Null }; return }
    if ($nt -eq 'If') { $c = IR-LowerExpr $node[1]; $el = IR-Lbl; $end = IR-Lbl; IR-Emit $IR_JZ $c $el 0|Out-Null; foreach ($s in (IR-StmtBody $node[2])) { IR-LowerStmt $s }; IR-Emit $IR_JMP $end 0 0|Out-Null; IR-Emit $IR_LABEL $el 0 0|Out-Null; if ($null -ne $node[3]) { foreach ($s in (IR-StmtBody $node[3])) { IR-LowerStmt $s } }; IR-Emit $IR_LABEL $end 0 0|Out-Null; return }
    if ($nt -eq 'While') { $lp = IR-Lbl; $end = IR-Lbl; IR-Emit $IR_LABEL $lp 0 0|Out-Null; $c = IR-LowerExpr $node[1]; IR-Emit $IR_JZ $c $end 0|Out-Null; foreach ($s in (IR-StmtBody $node[2])) { IR-LowerStmt $s }; IR-Emit $IR_JMP $lp 0 0|Out-Null; IR-Emit $IR_LABEL $end 0 0|Out-Null; return }
    if ($nt -eq 'For') { IR-Emit $IR_NOP 0 0 0 | Out-Null; return }
    if ($nt -eq 'Print') { $val = IR-LowerExpr $node[1]; IR-Emit $IR_PRINT $val 0 0 | Out-Null; return }
    if ($nt -eq 'ExprStmt') { IR-LowerExpr $node[1] | Out-Null; return }
    if ($nt -eq 'Quadrant') { foreach ($s in (IR-StmtBody $node[2])) { IR-LowerStmt $s }; return }
    if ($nt -eq 'Block') { foreach ($s in (IR-StmtBody $node[1])) { IR-LowerStmt $s }; return }
    if ($nt -eq 'IndexAssign') { return }
    if ($nt -eq 'FnDecl') { return }
    IR-Emit $IR_NOP 0 0 0 | Out-Null
}

function IR-LowerModule($ast) {
    if ($null -eq $ast) { return }
    foreach ($s in $ast) { IR-LowerStmt $s }
}

# Optimization: constant folding
function IR-OptConstFold {
    $changed = 0
    for ($i = 0; $i -lt $script:ir_count; $i++) {
        if ($script:ir_dead[$i] -ne 0) { continue }
        $op = $script:ir_op[$i]; $s1v = $null; $s2v = $null
        for ($j = 0; $j -lt $i; $j++) {
            if ($script:ir_dead[$j] -eq 0 -and $script:ir_op[$j] -eq $IR_CONST) {
                if ($script:ir_dst[$j] -eq $script:ir_src1[$i]) { $s1v = $script:ir_src1[$j] }
                if ($script:ir_dst[$j] -eq $script:ir_src2[$i]) { $s2v = $script:ir_src1[$j] }
            }
        }
        if ($null -ne $s1v -and $null -ne $s2v -and $s1v -is [int] -and $s2v -is [int]) {
            $r = $null
            switch ($op) {
                $IR_ADD { $r = $s1v + $s2v } $IR_SUB { $r = $s1v - $s2v }
                $IR_MUL { $r = $s1v * $s2v } $IR_AND { $r = $s1v -band $s2v }
                $IR_OR  { $r = $s1v -bor $s2v } $IR_XOR { $r = $s1v -bxor $s2v }
                $IR_DIV { if ($s2v -ne 0) { $r = [math]::Truncate($s1v / $s2v) } }
                $IR_CMP_EQ { $r = [int]($s1v -eq $s2v) } $IR_CMP_NE { $r = [int]($s1v -ne $s2v) }
                $IR_CMP_LT { $r = [int]($s1v -lt $s2v) } $IR_CMP_LE { $r = [int]($s1v -le $s2v) }
            }
            if ($null -ne $r) { $script:ir_op[$i] = $IR_CONST; $script:ir_src1[$i] = $r; $script:ir_src2[$i] = 0; $changed++ }
        }
    }
    return $changed
}

# Optimization: dead code elimination — O(n) via HashSet use-set
function IR-OptDCE {
    $changed = 0
    $skip = @($IR_JMP,$IR_JZ,$IR_JNZ,$IR_LABEL,$IR_CALL,$IR_RET,$IR_STORE,$IR_ARG,$IR_PARAM,$IR_NOP,$IR_PRINT,$IR_PORT_OUT,$IR_PORT_IN,$IR_CLI,$IR_STI,$IR_HLT,$IR_MEM_STORE8,$IR_MEM_LOAD64,$IR_MEM_STORE64,$IR_LIDT,$IR_PORT_OUT32,$IR_PORT_IN32,$IR_MEM_STORE32,$IR_MEM_LOAD32,$IR_MEM_LOAD8)
    # Pass 1: collect all vreg numbers that appear as read operands (O(n))
    $usedVregs = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $script:ir_count; $i++) {
        if ($script:ir_dead[$i] -ne 0) { continue }
        $op = $script:ir_op[$i]
        $s1 = $script:ir_src1[$i]; if ($s1 -is [int]) { [void]$usedVregs.Add($s1) }
        $s2 = $script:ir_src2[$i]; if ($s2 -is [int]) { [void]$usedVregs.Add($s2) }
        # IR_JZ/IR_JNZ/IR_RET: condition/return-value vreg is in dst field (it's a READ)
        if ($op -eq $IR_JZ -or $op -eq $IR_JNZ -or $op -eq $IR_RET) {
            [void]$usedVregs.Add($script:ir_dst[$i])
        }
    }
    # Pass 2: mark dead any instruction whose dst vreg has no readers (O(n))
    for ($i = 0; $i -lt $script:ir_count; $i++) {
        if ($script:ir_dead[$i] -ne 0) { continue }
        if ($script:ir_op[$i] -in $skip) { continue }
        if (-not $usedVregs.Contains($script:ir_dst[$i])) {
            $script:ir_dead[$i] = 1; $changed++
        }
    }
    return $changed
}

# Optimization: strength reduction (mul/div by powers of 2 �� shift)
function IR-OptStrength {
    $changed = 0
    for ($i = 0; $i -lt $script:ir_count; $i++) {
        if ($script:ir_dead[$i] -ne 0) { continue }
        $op = $script:ir_op[$i]; $s2v = $null
        for ($j = 0; $j -lt $i; $j++) {
            if ($script:ir_dead[$j] -eq 0 -and $script:ir_op[$j] -eq $IR_CONST -and $script:ir_dst[$j] -eq $script:ir_src2[$i]) { $s2v = $script:ir_src1[$j] }
        }
        if ($op -eq $IR_MUL -and $null -ne $s2v) {
            if ($s2v -eq 2) {$script:ir_op[$i]=$IR_SHL;$script:ir_src2[$i]=1;$changed++}
            elseif ($s2v -eq 4) {$script:ir_op[$i]=$IR_SHL;$script:ir_src2[$i]=2;$changed++}
            elseif ($s2v -eq 8) {$script:ir_op[$i]=$IR_SHL;$script:ir_src2[$i]=3;$changed++}
        }
        if ($op -eq $IR_DIV -and $null -ne $s2v) {
            if ($s2v -eq 2) {$script:ir_op[$i]=$IR_SHR;$script:ir_src2[$i]=1;$changed++}
            elseif ($s2v -eq 4) {$script:ir_op[$i]=$IR_SHR;$script:ir_src2[$i]=2;$changed++}
        }
    }
    return $changed
}

function IR-Optimize {
    $total = 0
    for ($iter = 0; $iter -lt 5; $iter++) {
        $c = 0; $c += IR-OptConstFold; $c += IR-OptDCE; $c += IR-OptStrength
        $total += $c; if ($c -eq 0) { break }
    }
    return $total
}

function IR-LiveCount {
    $c = 0; for ($i = 0; $i -lt $script:ir_count; $i++) { if ($script:ir_dead[$i] -eq 0) { $c++ } }; return $c
}

# ================================================================
#  PHASE 4: REGISTER ALLOCATION + x86_64 CODE EMISSION
#  (mirrors regalloc.hl + x86enc.hl + codegen.hl)
# ================================================================
# Register pool: RAX=0 RCX=1 RDX=2 RBX=3 RSP=4(res) RBP=5(res) RSI=6 RDI=7 R8-R15=8-15
$script:REG_POOL = @(0,1,2,3,6,7,8,9,10,11,12,13,14,15)
$script:ra_map = $null  # vreg �� physical reg or -1 (spilled)
$script:ra_spill_map = $null  # vreg �� spill offset
$script:ra_spill_top = 0

function RA-Init {
    $script:ra_map = @{}; $script:ra_spill_map = @{}; $script:ra_spill_top = 0
    $script:ra_free = [System.Collections.ArrayList]::new()
    foreach ($r in $script:REG_POOL) { [void]$script:ra_free.Add($r) }
}

function RA-Alloc([int]$vreg) {
    if ($script:ra_map.ContainsKey($vreg)) { return $script:ra_map[$vreg] }
    if ($script:ra_free.Count -gt 0) {
        $r = $script:ra_free[$script:ra_free.Count - 1]; $script:ra_free.RemoveAt($script:ra_free.Count - 1)
        $script:ra_map[$vreg] = $r; return $r
    }
    # Spill: assign stack slot
    $script:ra_map[$vreg] = -1
    $script:ra_spill_top += 8; $script:ra_spill_map[$vreg] = $script:ra_spill_top
    return -1
}

# x86_64 byte buffer
$script:x86_buf = $null
# Sprint 36: handwritten-kernel symbol addresses for direct codegen
$script:kernSyms = @{}
$kernSymPath = Join-Path $repoRoot 'bare-kernel\kernel-symbols.json'
if (Test-Path $kernSymPath) {
    $raw = Get-Content $kernSymPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $raw.PSObject.Properties) {
        $v = $p.Value; if ($v -is [string] -and $v.StartsWith('0x')) { $v = [Convert]::ToInt64($v.Substring(2),16) }
        $script:kernSyms[$p.Name] = [int64]$v
    }
}
function X86-Init { $script:x86_buf = [System.Collections.ArrayList]::new() }
function X86-Byte([int]$b) { [void]$script:x86_buf.Add([byte]($b -band 0xFF)) }
function X86-Imm32([long]$v) { X86-Byte ($v -band 0xFF); X86-Byte (($v -shr 8) -band 0xFF); X86-Byte (($v -shr 16) -band 0xFF); X86-Byte (($v -shr 24) -band 0xFF) }
function X86-Imm64([long]$v) {
    $b = [System.BitConverter]::GetBytes([int64]$v)
    for ($i = 0; $i -lt 8; $i++) { X86-Byte $b[$i] }
}

# Emit: mov reg, imm64 (REX.W B8+r)
function X86-MovRegImm([int]$r, [long]$v) {
    if ($r -ge 8) { X86-Byte 0x49 } else { X86-Byte 0x48 }
    X86-Byte (0xB8 + ($r -band 7)); X86-Imm32 ($v -band 0xFFFFFFFF)
    X86-Imm32 (($v -shr 32) -band 0xFFFFFFFF)
}
# Emit: mov dst, src (REX.W 89)
function X86-MovRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x89; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}
# Emit: add dst, src
function X86-AddRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x01; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}
# Emit: sub dst, src
function X86-SubRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x29; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}
# Emit: imul dst, src
function X86-ImulRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($dst -ge 8) { $rex = $rex -bor 4 }; if ($src -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x0F; X86-Byte 0xAF; X86-Byte (0xC0 + (($dst -band 7) -shl 3) + ($src -band 7))
}
# Emit: cmp r1, r2 + setcc al + movzx rax, al
function X86-CmpSet([int]$r1, [int]$r2, [int]$setcc) {
    $rex = 0x48; if ($r2 -ge 8) { $rex = $rex -bor 4 }; if ($r1 -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x39; X86-Byte (0xC0 + (($r2 -band 7) -shl 3) + ($r1 -band 7))  # cmp
    X86-Byte 0x0F; X86-Byte $setcc; X86-Byte 0xC0  # setcc al
    X86-Byte 0x48; X86-Byte 0x0F; X86-Byte 0xB6; X86-Byte 0xC0  # movzx rax, al
}
# Emit: neg r
function X86-NegR([int]$r) {
    $rex = 0x48; if ($r -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0xF7; X86-Byte (0xD8 + ($r -band 7))
}
# Emit: not r
function X86-NotR([int]$r) {
    $rex = 0x48; if ($r -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0xF7; X86-Byte (0xD0 + ($r -band 7))
}
# Emit: ret
function X86-Ret { X86-Byte 0xC3 }
# Emit: push rbp; mov rbp,rsp
function X86-Prologue { X86-Byte 0x55; X86-Byte 0x48; X86-Byte 0x89; X86-Byte 0xE5 }
# Emit: mov rsp,rbp; pop rbp
function X86-Epilogue { X86-Byte 0x48; X86-Byte 0x89; X86-Byte 0xEC; X86-Byte 0x5D }
# Emit: shl r, imm8
function X86-ShlRI([int]$r, [int]$imm) {
    $rex = 0x48; if ($r -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0xC1; X86-Byte (0xE0 + ($r -band 7)); X86-Byte $imm
}
# Emit: shr r, imm8
function X86-ShrRI([int]$r, [int]$imm) {
    $rex = 0x48; if ($r -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0xC1; X86-Byte (0xE8 + ($r -band 7)); X86-Byte $imm
}
# Emit: and dst, src
function X86-AndRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x21; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}
# Emit: or dst, src
function X86-OrRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x09; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}
# Emit: xor dst, src
function X86-XorRR([int]$dst, [int]$src) {
    $rex = 0x48; if ($src -ge 8) { $rex = $rex -bor 4 }; if ($dst -ge 8) { $rex = $rex -bor 1 }
    X86-Byte $rex; X86-Byte 0x31; X86-Byte (0xC0 + (($src -band 7) -shl 3) + ($dst -band 7))
}

# Translate one IR instruction �� x86_64 bytes
function X86-EmitIR([int]$idx) {
    $op = $script:ir_op[$idx]; $dst = $script:ir_dst[$idx]
    $s1 = $script:ir_src1[$idx]; $s2 = $script:ir_src2[$idx]
    $rd = RA-Alloc $dst
    switch ($op) {
        $IR_CONST  { if ($rd -ge 0) { X86-MovRegImm $rd $s1 } }
        $IR_STR_CONST {
            # Sprint 38: pool the literal, emit mov reg, imm64 0 + abs64 reloc.
            if ($rd -ge 0) {
                $idx = $script:mod_strings.Count
                [void]$script:mod_strings.Add([string]$s1)
                $sym = "__str`$$($script:current_module)`$$idx"
                X86-MovRegImm $rd 0
                $site = $script:x86_buf.Count - 8
                [void]$script:mod_relocs.Add(@($site, $sym, 'abs64'))
            }
        }
        $IR_COPY   { $rs = RA-Alloc $s1; if ($rd -ge 0 -and $rs -ge 0) { X86-MovRR $rd $rs } }
        $IR_ADD    { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0) { if ($rd -ne $r1 -and $r1 -ge 0) { X86-MovRR $rd $r1 }; if ($r2 -ge 0) { X86-AddRR $rd $r2 } } }
        $IR_SUB    { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0) { if ($rd -ne $r1 -and $r1 -ge 0) { X86-MovRR $rd $r1 }; if ($r2 -ge 0) { X86-SubRR $rd $r2 } } }
        $IR_MUL    { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0 -and $r1 -ge 0 -and $r2 -ge 0) { if ($rd -ne $r1) { X86-MovRR $rd $r1 }; X86-ImulRR $rd $r2 } }
        $IR_AND    { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0) { if ($rd -ne $r1 -and $r1 -ge 0) { X86-MovRR $rd $r1 }; if ($r2 -ge 0) { X86-AndRR $rd $r2 } } }
        $IR_OR     { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0) { if ($rd -ne $r1 -and $r1 -ge 0) { X86-MovRR $rd $r1 }; if ($r2 -ge 0) { X86-OrRR $rd $r2 } } }
        $IR_XOR    { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($rd -ge 0) { if ($rd -ne $r1 -and $r1 -ge 0) { X86-MovRR $rd $r1 }; if ($r2 -ge 0) { X86-XorRR $rd $r2 } } }
        $IR_SHL    { $r1 = RA-Alloc $s1; if ($rd -ge 0 -and $r1 -ge 0) { if ($rd -ne $r1) { X86-MovRR $rd $r1 }; X86-ShlRI $rd ([int]$s2) } }
        $IR_SHR    { $r1 = RA-Alloc $s1; if ($rd -ge 0 -and $r1 -ge 0) { if ($rd -ne $r1) { X86-MovRR $rd $r1 }; X86-ShrRI $rd ([int]$s2) } }
        $IR_NEG    { $r1 = RA-Alloc $s1; if ($rd -ge 0 -and $r1 -ge 0) { if ($rd -ne $r1) { X86-MovRR $rd $r1 }; X86-NegR $rd } }
        $IR_NOT    { $r1 = RA-Alloc $s1; if ($rd -ge 0 -and $r1 -ge 0) { if ($rd -ne $r1) { X86-MovRR $rd $r1 }; X86-NotR $rd } }
        $IR_CMP_EQ { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x94 }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_CMP_NE { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x95 }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_CMP_LT { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x9C }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_CMP_LE { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x9E }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_CMP_GT { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x9F }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_CMP_GE { $r1 = RA-Alloc $s1; $r2 = RA-Alloc $s2; if ($r1 -ge 0 -and $r2 -ge 0) { X86-CmpSet $r1 $r2 0x9D }; if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 } }
        $IR_LABEL  {
            # Labels: emit nop alignment; if this is a function entry, emit prologue
            $lbl = $dst; $isFn = $false
            foreach ($kv in $script:ir_fns.GetEnumerator()) { if ($kv.Value -eq $lbl) { $isFn = $true } }
            if ($isFn) { RA-Init; X86-Prologue } else { X86-Byte 0x90 }
        }
        $IR_JMP    { X86-Byte 0xE9; X86-Imm32 0 <# near JMP rel32 placeholder #> }
        $IR_JZ     { X86-Byte 0x0F; X86-Byte 0x84; X86-Imm32 0 <# near JE rel32 placeholder #> }
        $IR_RET    { $r1 = RA-Alloc $dst; if ($null -ne $r1 -and $r1 -ge 0 -and $r1 -ne 0) { X86-MovRR 0 $r1 <# result→RAX #> }; X86-Epilogue; X86-Ret }
        $IR_CALL   { X86-Byte 0xE8; X86-Imm32 0 <# call rel32 placeholder #> }
        $IR_ARG    {
            # Call-site arg setup: move value vreg to ABI register
            # dst = arg position (0-5), src1 = value vreg
            $abiRegs = @(7,6,2,1,8,9)  # RDI RSI RDX RCX R8 R9
            $argIdx = $dst; $valReg = RA-Alloc $s1
            if ($argIdx -ge 0 -and $argIdx -lt 6 -and $valReg -ge 0) {
                $targetReg = $abiRegs[$argIdx]
                if ($valReg -ne $targetReg) { X86-MovRR $targetReg $valReg }
            }
        }
        $IR_PARAM  {
            # Function entry: receive parameter from ABI register to vreg
            # dst = dest vreg, src1 = param index (0-5)
            $abiRegs = @(7,6,2,1,8,9)  # RDI RSI RDX RCX R8 R9
            $paramIdx = $s1
            if ($paramIdx -ge 0 -and $paramIdx -lt 6 -and $rd -ge 0) {
                $srcReg = $abiRegs[$paramIdx]
                if ($rd -ne $srcReg) { X86-MovRR $rd $srcReg }
            }
        }
        $IR_PRINT  {
            # Sprint 36: emit direct call to handwritten serial_puts.
            # IR layout: s1 = vreg holding string pointer.
            $srcReg = RA-Alloc $s1
            if ($srcReg -ge 0 -and $script:kernSyms.ContainsKey('serial_puts')) {
                if ($srcReg -ne 6) { X86-MovRR 6 $srcReg }   # rsi = ptr
                X86-Byte 0x48; X86-Byte 0xB8; X86-Imm64 $script:kernSyms['serial_puts']  # mov rax, abs
                X86-Byte 0xFF; X86-Byte 0xD0                  # call rax
            } else {
                X86-Byte 0x90  # fallback nop
            }
        }
        $IR_PORT_OUT {
            # port_out_u8: mov edx, port_reg; mov eax, val_reg; out dx, al
            $rPort = RA-Alloc $s1; $rVal = RA-Alloc $s2
            if ($rPort -ge 0 -and $rVal -ge 0) {
                if ($rPort -ne 2) { X86-MovRR 2 $rPort }
                if ($rVal -ne 0) { X86-MovRR 0 $rVal }
                X86-Byte 0xEE  # out dx, al
            }
        }
        $IR_PORT_IN {
            # port_in_u8: mov edx, port_reg; in al, dx; movzx rax, al
            $rPort = RA-Alloc $s1
            if ($rPort -ge 0) {
                if ($rPort -ne 2) { X86-MovRR 2 $rPort }
                X86-Byte 0xEC  # in al, dx
                X86-Byte 0x48; X86-Byte 0x0F; X86-Byte 0xB6; X86-Byte 0xC0  # movzx rax, al
                if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 }
            }
        }
        $IR_CLI { X86-Byte 0xFA }
        $IR_STI { X86-Byte 0xFB }
        $IR_HLT { X86-Byte 0xF4 }
        $IR_MEM_STORE8 {
            # mem_write_u8(addr, val): mov [rAddr], valByte
            $rAddr = RA-Alloc $s1; $rVal = RA-Alloc $s2
            if ($rAddr -ge 0 -and $rVal -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }  # rdi = addr
                if ($rVal -ne 0) { X86-MovRR 0 $rVal }    # rax = val
                X86-Byte 0x88; X86-Byte 0x07  # mov [rdi], al
            }
        }
        $IR_MEM_LOAD64 {
            # mem_read_u64(addr): mov rax, [rAddr]
            $rAddr = RA-Alloc $s1
            if ($rAddr -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }  # rdi = addr
                X86-Byte 0x48; X86-Byte 0x8B; X86-Byte 0x07  # mov rax, [rdi]
                if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 }
            }
        }
        $IR_MEM_STORE64 {
            # mem_write_u64(addr, val): mov [rAddr], rVal
            $rAddr = RA-Alloc $s1; $rVal = RA-Alloc $s2
            if ($rAddr -ge 0 -and $rVal -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }  # rdi = addr
                if ($rVal -ne 0) { X86-MovRR 0 $rVal }    # rax = val
                X86-Byte 0x48; X86-Byte 0x89; X86-Byte 0x07  # mov [rdi], rax
            }
        }
        $IR_LIDT {
            # lidt [rAddr]: load IDT register from 10-byte descriptor
            $rAddr = RA-Alloc $s1
            if ($rAddr -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }  # rdi = addr
                X86-Byte 0x0F; X86-Byte 0x01; X86-Byte 0x1F  # lidt [rdi]
            }
        }
        $IR_PORT_OUT32 {
            # port_out_u32: mov edx, port_reg; mov eax, val_reg; out dx, eax
            $rPort = RA-Alloc $s1; $rVal = RA-Alloc $s2
            if ($rPort -ge 0 -and $rVal -ge 0) {
                if ($rPort -ne 2) { X86-MovRR 2 $rPort }
                if ($rVal -ne 0) { X86-MovRR 0 $rVal }
                X86-Byte 0xEF  # out dx, eax
            }
        }
        $IR_PORT_IN32 {
            # port_in_u32: mov edx, port_reg; in eax, dx (zero-extends to rax)
            $rPort = RA-Alloc $s1
            if ($rPort -ge 0) {
                if ($rPort -ne 2) { X86-MovRR 2 $rPort }
                X86-Byte 0xED  # in eax, dx
                if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 }
            }
        }
        $IR_MEM_STORE32 {
            # mem_write_u32(addr, val): mov [rdi], eax (32-bit store)
            $rAddr = RA-Alloc $s1; $rVal = RA-Alloc $s2
            if ($rAddr -ge 0 -and $rVal -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }
                if ($rVal -ne 0) { X86-MovRR 0 $rVal }
                X86-Byte 0x89; X86-Byte 0x07  # mov [rdi], eax
            }
        }
        $IR_MEM_LOAD32 {
            # mem_read_u32(addr): mov eax, [rdi] (zero-extends to rax)
            $rAddr = RA-Alloc $s1
            if ($rAddr -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }
                X86-Byte 0x8B; X86-Byte 0x07  # mov eax, [rdi]
                if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 }
            }
        }
        $IR_MEM_LOAD8 {
            # mem_read_u8(addr): movzx eax, byte [rdi]
            $rAddr = RA-Alloc $s1
            if ($rAddr -ge 0) {
                if ($rAddr -ne 7) { X86-MovRR 7 $rAddr }
                X86-Byte 0x0F; X86-Byte 0xB6; X86-Byte 0x07  # movzx eax, byte [rdi]
                if ($rd -ge 0 -and $rd -ne 0) { X86-MovRR $rd 0 }
            }
        }
        $IR_NOP    { X86-Byte 0x90 }
    }
}

# Compile a module's live IR
function X86-CompileModule {
    RA-Init; X86-Init; X86-Prologue
    $script:mod_symbols = [System.Collections.ArrayList]::new()
    $script:mod_relocs  = [System.Collections.ArrayList]::new()
    $script:mod_strings = [System.Collections.ArrayList]::new()
    $labelOffsets = @{}   # non-fn label_num -> x86_buf offset (for jump backpatch)
    $jmpSites = [System.Collections.ArrayList]::new()  # @(imm32_site, target_label_num)
    for ($i = 0; $i -lt $script:ir_count; $i++) {
        if ($script:ir_dead[$i] -eq 0) {
            # Track function labels as exported symbols; track non-fn labels for jump backpatch
            if ($script:ir_op[$i] -eq $IR_LABEL) {
                $lbl = $script:ir_dst[$i]
                $isFnLbl = $false
                foreach ($kv in $script:ir_fns.GetEnumerator()) {
                    if ($kv.Value -eq $lbl) {
                        [void]$script:mod_symbols.Add(@($kv.Key, $script:x86_buf.Count, 'fn'))
                        $isFnLbl = $true
                    }
                }
                if (-not $isFnLbl) { $labelOffsets[$lbl] = $script:x86_buf.Count }
            }
            # Track jump sites for rel32 backpatch (IR_JMP dst=label; IR_JZ dst=cond src1=label)
            if ($script:ir_op[$i] -eq $IR_JMP) {
                $cnt = [int]$script:x86_buf.Count
                [void]$jmpSites.Add(@(($cnt + 1), [int]$script:ir_dst[$i]))
            } elseif ($script:ir_op[$i] -eq $IR_JZ -or $script:ir_op[$i] -eq $IR_JNZ) {
                $cnt = [int]$script:x86_buf.Count
                $tgt = $script:ir_src1[$i]
                if ($tgt -isnot [int]) { $tgt = [int]$tgt }
                [void]$jmpSites.Add(@(($cnt + 2), $tgt))
            }
            # Track CALL sites as relocations
            if ($script:ir_op[$i] -eq $IR_CALL) {
                $callSite = [int]$script:x86_buf.Count + 1  # offset of imm32 in E8 xx xx xx xx
                $fnLabel = $script:ir_src1[$i]
                $fnName = ''
                if ($fnLabel -is [string] -and $fnLabel -ne '') {
                    # External call: function name stored directly
                    $fnName = $fnLabel
                } else {
                    # Local call: look up label in ir_fns
                    foreach ($kv in $script:ir_fns.GetEnumerator()) {
                        if ($kv.Value -eq $fnLabel) { $fnName = $kv.Key }
                    }
                }
                if ($fnName -ne '') {
                    [void]$script:mod_relocs.Add(@($callSite, $fnName, 'rel32'))
                }
            }
            X86-EmitIR $i
        }
    }
    # Backpatch all jump rel32 offsets now that label offsets are known
    foreach ($js in $jmpSites) {
        $imm32site = $js[0]; $tgtLbl = $js[1]
        if ($labelOffsets.ContainsKey($tgtLbl)) {
            $rel = $labelOffsets[$tgtLbl] - ($imm32site + 4)
            $script:x86_buf[$imm32site]     = [byte]($rel -band 0xFF)
            $script:x86_buf[$imm32site + 1] = [byte](($rel -shr 8)  -band 0xFF)
            $script:x86_buf[$imm32site + 2] = [byte](($rel -shr 16) -band 0xFF)
            $script:x86_buf[$imm32site + 3] = [byte](($rel -shr 24) -band 0xFF)
        }
    }
    X86-Epilogue; X86-Ret
    if ($env:HL_DUMP_SYMS_FOR -and $script:current_module -eq $env:HL_DUMP_SYMS_FOR) {
        $sorted = $script:mod_symbols | Sort-Object { $_[1] }
        $prev = $null
        foreach ($s in $sorted) {
            if ($null -ne $prev) {
                $sz = $s[1] - $prev[1]
                Write-Host ("  symdump[{0}]: {1,-30} off={2,-6} sz={3}" -f $env:HL_DUMP_SYMS_FOR, $prev[0], $prev[1], $sz) -ForegroundColor DarkCyan
            }
            $prev = $s
        }
        if ($null -ne $prev) {
            $sz = $script:x86_buf.Count - $prev[1]
            Write-Host ("  symdump[{0}]: {1,-30} off={2,-6} sz={3}" -f $env:HL_DUMP_SYMS_FOR, $prev[0], $prev[1], $sz) -ForegroundColor DarkCyan
        }
    }
    return $script:x86_buf.Count
}

# ================================================================
#  PHASE 5: CROSS-MODULE LINKER (mirrors linker.hl)
# ================================================================
$script:LINK_TEXT_BASE = 0x120000   # 1 MB + 128 KB -- .text segment start (after padded handwritten kernel)
$script:link_modules = $null        # array of @{Name;Code;Symbols;Relocs}
$script:link_global_syms = $null    # hashtable: name �� absolute offset
$script:link_combined = $null       # flat byte array

function Link-Init {
    $script:link_modules = [System.Collections.ArrayList]::new()
    $script:link_global_syms = @{}
    $script:link_combined = [System.Collections.ArrayList]::new()
    $script:link_builtin_stubs = @{}  # builtin name -> stub offset
    $script:link_fwd_decls = @{}      # pre-scanned fn names -> source module
}

# Pass 1: layout modules sequentially, collect global symbol table
function Link-Pass1 {
    $offset = 0
    foreach ($mod in $script:link_modules) {
        $mod.Offset = $offset
        foreach ($sym in $mod.Symbols) {
            $absOff = $offset + $sym[1]
            $script:link_global_syms[$sym[0]] = $absOff
        }
        $offset += $mod.Code.Count
    }
    return $offset
}

# Pre-scan: collect all fn declarations across all source files for forward binding
function Link-PreScan {
    param([string[]]$sourcePaths)
    foreach ($p in $sourcePaths) {
        if (-not (Test-Path $p)) { continue }
        $src = Get-Content $p -Raw -Encoding UTF8
        $modName = [System.IO.Path]::GetFileName($p)
        # Match fn <name>( patterns
        $matches = [regex]::Matches($src, '\bfn\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(')
        foreach ($m in $matches) {
            $fnName = $m.Groups[1].Value
            if (-not $script:link_fwd_decls.ContainsKey($fnName)) {
                $script:link_fwd_decls[$fnName] = $modName
            }
        }
    }
}

# Generate stub trampolines for builtins and unresolved forward declarations
function Link-GenerateStubs {
    # H-L language builtins that have no .hl source definition
    $builtins = @('print','println','len','push','pop','set_at','to_string',
                  'lfsr_next','tcp_send','tcp_recv','tcp_connect','dns_resolve',
                  'input','type_of','str_split','str_trim','str_find','str_sub',
                  'array_new','array_fill','sort','char_at','char_code',
                  'from_char_code','str_contains','str_starts_with','str_ends_with',
                  'str_replace','str_to_upper','str_to_lower','str_join',
                  'abs','min','max','floor','ceil','sqrt','pow','log',
                  'random','time_ms','sleep_ms','panic',
                  # Sprint 35 阶段 1：A 类高频别名（trampoline 桩，消化 ~2,142 unresolved 站点）
                  'array','to_int','parse_int','str_char_code','_starts_with',
                  'str_slice','substr','str_index_of','str_to_bytes','str_from_byte',
                  'to_char','str_byte','strlen',
                  # Sprint 35 阶段 1：B 类 kernel 符号（暂时 no-op 桩，待 kernel.entry 暴露真实实现）
                  'serial_print','_ke_pci_read','mem_set32','wrmsr','random_get',
                  # Sprint 35 阶段 1：C 类高频前向声明（待对应 .hl 模块实现后自动接管）
                  '_find_space','cstr_from_addr','udp_recv','file_read',
                  'ui_fill_rect','font_draw_string','socket_send','socket_close',
                  'partition','encode','close','search','insert','send')
    # Sprint 36: read handwritten-kernel symbol export, route specific builtins
    # to real subroutines instead of no-op stubs.
    $kernSyms = @{}
    $kernSymPath = Join-Path $repoRoot 'bare-kernel\kernel-symbols.json'
    if (Test-Path $kernSymPath) {
        $raw = Get-Content $kernSymPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $raw.PSObject.Properties) { $kernSyms[$p.Name] = [int64]$p.Value }
    }
    $stubBase = $script:link_combined.Count
    $stubCount = 0
    foreach ($name in $builtins) {
        if (-not $script:link_global_syms.ContainsKey($name)) {
            $stubOff = $script:link_combined.Count
            if ($name -eq 'print' -and $kernSyms.ContainsKey('serial_puts')) {
                # Trampoline: mov rsi,rdi ; mov rax,abs ; call rax ; ret  (15 bytes)
                $abs = $kernSyms['serial_puts']
                [void]$script:link_combined.Add([byte]0x48); [void]$script:link_combined.Add([byte]0x89); [void]$script:link_combined.Add([byte]0xFE)  # mov rsi,rdi
                [void]$script:link_combined.Add([byte]0x48); [void]$script:link_combined.Add([byte]0xB8)                                              # mov rax,imm64
                $ab = [System.BitConverter]::GetBytes([int64]$abs)
                for ($bi = 0; $bi -lt 8; $bi++) { [void]$script:link_combined.Add([byte]$ab[$bi]) }
                [void]$script:link_combined.Add([byte]0xFF); [void]$script:link_combined.Add([byte]0xD0)                                              # call rax
                [void]$script:link_combined.Add([byte]0xC3)                                                                                            # ret
            } else {
                # No-op fallback: push rbp; mov rbp,rsp; xor eax,eax; pop rbp; ret (8 bytes)
                [void]$script:link_combined.Add([byte]0x55)
                [void]$script:link_combined.Add([byte]0x48)
                [void]$script:link_combined.Add([byte]0x89)
                [void]$script:link_combined.Add([byte]0xE5)
                [void]$script:link_combined.Add([byte]0x31)
                [void]$script:link_combined.Add([byte]0xC0)
                [void]$script:link_combined.Add([byte]0x5D)
                [void]$script:link_combined.Add([byte]0xC3)
            }
            $script:link_global_syms[$name] = $stubOff
            $script:link_builtin_stubs[$name] = $stubOff
            $stubCount++
        }
    }
    # Also generate stubs for forward-declared functions not yet in symbol table
    foreach ($kv in $script:link_fwd_decls.GetEnumerator()) {
        $fnName = $kv.Key
        if (-not $script:link_global_syms.ContainsKey($fnName)) {
            $stubOff = $script:link_combined.Count
            [void]$script:link_combined.Add([byte]0x55)
            [void]$script:link_combined.Add([byte]0x48)
            [void]$script:link_combined.Add([byte]0x89)
            [void]$script:link_combined.Add([byte]0xE5)
            [void]$script:link_combined.Add([byte]0x31)
            [void]$script:link_combined.Add([byte]0xC0)
            [void]$script:link_combined.Add([byte]0x5D)
            [void]$script:link_combined.Add([byte]0xC3)
            $script:link_global_syms[$fnName] = $stubOff
            $script:link_builtin_stubs[$fnName] = $stubOff
            $stubCount++
        }
    }
    return @($stubBase, $stubCount)
}

# Pass 2: concatenate code, generate stubs, resolve relocations (two-pass resolve)
function Link-Pass2 {
    # Concatenate all module code into flat binary
    foreach ($mod in $script:link_modules) {
        foreach ($b in $mod.Code) { [void]$script:link_combined.Add($b) }
    }
    # Generate builtin + forward-declaration stubs after module code
    $stubResult = Link-GenerateStubs
    $script:link_stub_base = $stubResult[0]
    $script:link_stub_count = $stubResult[1]
    # Sprint 38: append string-literal pool after stubs; register each as a global symbol.
    foreach ($mod in $script:link_modules) {
        if (-not $mod.ContainsKey('Strings') -or $null -eq $mod.Strings) { continue }
        $modName = $mod.Name
        for ($si = 0; $si -lt $mod.Strings.Count; $si++) {
            $sym = "__str`$$modName`$$si"
            $script:link_global_syms[$sym] = $script:link_combined.Count
            $raw = [string]$mod.Strings[$si]
            $sb = New-Object System.Text.StringBuilder
            $i = 0
            while ($i -lt $raw.Length) {
                $ch = $raw[$i]
                if ($ch -eq '\' -and ($i + 1) -lt $raw.Length) {
                    $n = $raw[$i + 1]
                    $repl = switch ($n) { 'n' { "`n" } 't' { "`t" } 'r' { "`r" } '0' { [char]0 } '\' { '\' } '"' { '"' } "'" { "'" } default { [string]$n } }
                    [void]$sb.Append($repl); $i += 2
                } else {
                    [void]$sb.Append($ch); $i++
                }
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
            foreach ($b in $bytes) { [void]$script:link_combined.Add([byte]$b) }
            [void]$script:link_combined.Add([byte]0)  # NUL terminator
        }
    }
    # Resolve relocations (now with stubs + strings available)
    $resolved = 0; $unresolved = 0
    # Sprint 35: 收集未解析 target → 数量映射，便于事后分类
    $script:link_unresolved_map = @{}
    foreach ($mod in $script:link_modules) {
        foreach ($reloc in $mod.Relocs) {
            $site = $mod.Offset + $reloc[0]   # absolute site in combined binary
            $target = $reloc[1]                # symbol name
            $rtype = $reloc[2]                 # 'rel32' or 'abs64'
            if ($script:link_global_syms.ContainsKey($target)) {
                $targetOff = $script:link_global_syms[$target]
                if ($rtype -eq 'rel32' -and ($site + 3) -lt $script:link_combined.Count) {
                    $rel = $targetOff - ($site + 4)
                    $script:link_combined[$site]     = [byte]($rel -band 0xFF)
                    $script:link_combined[$site + 1] = [byte](($rel -shr 8) -band 0xFF)
                    $script:link_combined[$site + 2] = [byte](($rel -shr 16) -band 0xFF)
                    $script:link_combined[$site + 3] = [byte](($rel -shr 24) -band 0xFF)
                    $resolved++
                } elseif ($rtype -eq 'abs64' -and ($site + 7) -lt $script:link_combined.Count) {
                    $abs = [int64]($script:LINK_TEXT_BASE + $targetOff)
                    for ($bi = 0; $bi -lt 8; $bi++) {
                        $script:link_combined[$site + $bi] = [byte](($abs -shr ($bi * 8)) -band 0xFF)
                    }
                    $resolved++
                }
            } else {
                $unresolved++
                if ($script:link_unresolved_map.ContainsKey($target)) {
                    $script:link_unresolved_map[$target]++
                } else {
                    $script:link_unresolved_map[$target] = 1
                }
            }
        }
    }
    return @($resolved, $unresolved)
}

# Write flat binary to disk
function Link-WriteBinary([string]$path) {
    [System.IO.File]::WriteAllBytes($path, [byte[]]$script:link_combined.ToArray())
    return $script:link_combined.Count
}

# ================================================================
#  MAIN: Compile all kernel modules (Phase 1 + Phase 2 + Phase 3 + Phase 4)
# ================================================================
$modulePaths = @(Get-ChildItem -Path (Join-Path $repoRoot 'bare-kernel/hl') -Filter '*.hl' | Sort-Object Name)
# Ensure kernel_entry.hl is first in compilation order so _start lands at offset 0
$keFile = $modulePaths | Where-Object { $_.Name -eq 'kernel_entry.hl' }
$otherFiles = $modulePaths | Where-Object { $_.Name -ne 'kernel_entry.hl' }
$modulePaths = @()
if ($keFile) { $modulePaths = @($keFile) + @($otherFiles) } else { $modulePaths = @($otherFiles) }
$totalFiles = $modulePaths.Count
$totalTokens = 0
$totalNodes = 0
$totalParseErrors = 0
$totalBalErrors = 0
$successCount = 0
$warnFiles = [System.Collections.ArrayList]::new()
$totalIR = 0; $totalIRLive = 0; $totalIROpt = 0; $totalFns = 0; $totalX86 = 0
$moduleASTs = [System.Collections.ArrayList]::new()
Link-Init

# Pre-scan all source files for forward function declarations (iteration 109)
$preScanPaths = @($modulePaths | ForEach-Object { $_.FullName })
$preScanPaths += @('stdlib.hl', 'hl-bootstrap.hl') | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ }
Link-PreScan $preScanPaths

Write-Host '=== H-L Compilation Pipeline ===' -ForegroundColor Green
Write-Host "Phase 1-5: Tokenize + Parse + IR + x86_64 + Link  ($totalFiles kernel modules)" -ForegroundColor Cyan
Write-Host ''

foreach ($file in $modulePaths) {
    $src = Get-Content $file.FullName -Raw -Encoding UTF8
    if ($null -eq $src) { $src = '' }

    # Phase 1: Tokenize
    $tokens = Tokenize-HL $src
    $tokCount = $tokens.Count
    $totalTokens += $tokCount

    # Validate balanced brackets
    $balErrors = Test-Balanced $tokens
    if ($balErrors.Count -gt 0 -and $env:HL_DUMP_BAL -eq '1') {
        Write-Host ("    bal[" + $file.Name + "]: " + ($balErrors -join '; ')) -ForegroundColor DarkYellow
    }
    $fnCount = Count-Functions $tokens

    # Phase 2: Parse — convert ArrayList to plain array for faster indexed access
    $script:ptok = if ($tokens -is [System.Collections.ArrayList]) { $tokens.ToArray() } else { $tokens }
    $script:ptok_len = $script:ptok.Count
    $script:ppos = 0
    $script:pnodes = 0
    $script:perrors = 0

    try {
        $ast = p_program
    } catch {
        # Parser error - recovery already happened inside p_program
    }
    $nodeCount = $script:pnodes
    $parseErrors = $script:perrors

    $totalNodes += $nodeCount
    $totalParseErrors += $parseErrors
    $totalBalErrors += $balErrors.Count

    # Balance errors are treated as warnings, not hard stops.
    # The recursive-descent parser has error recovery and can still produce
    # a usable AST for large files with minor bracket mismatches.
    # Skipping codegen for kernel_entry.hl would lose _start entirely.
    $hasWarnings = ($parseErrors -gt 0 -or $balErrors.Count -gt 0)
    if ($hasWarnings) {
        [void]$warnFiles.Add($file.Name)
    }

    # Phase 3: IR lowering + optimize (proceed even with balance warnings)
    IR-Init
    try { IR-LowerModule $ast } catch {}
    $irOpt = IR-Optimize
    $irTotal = $script:ir_count
    $irLive = IR-LiveCount
    # Phase 4: x86_64 codegen
    $x86Bytes = 0
    $script:current_module = $file.Name
    try { $x86Bytes = X86-CompileModule } catch {
        if ($env:HL_DEBUG_CODEGEN) {
            Write-Host ("  [CODEGEN-ERR] {0}: {1}" -f $file.Name, $_.Exception.Message) -ForegroundColor Magenta
            Write-Host ("    at {0}" -f $_.ScriptStackTrace) -ForegroundColor DarkMagenta
        }
    }
    # Register module for linking
    if ($x86Bytes -gt 0) {
        if ($file.Name -eq 'kernel_entry.hl') {
            $hasStart = $false; foreach ($s in $script:mod_symbols) { if ($s[0] -eq '_start') { $hasStart = $true; Write-Host ("  [DBG] _start in mod_symbols @ off={0}" -f $s[1]) -ForegroundColor Magenta } }
            if (-not $hasStart) { Write-Host "  [DBG] _start NOT in kernel_entry mod_symbols !" -ForegroundColor Red }
            $startLbl = $script:ir_fns['_start']
            Write-Host ("  [DBG] ir_fns has _start? {0}; ir_fns count = {1}; _start label = {2}; irTotal = {3}" -f $script:ir_fns.ContainsKey('_start'), $script:ir_fns.Count, $startLbl, $irTotal) -ForegroundColor Magenta
            $foundIdx = -1; $foundDead = -1
            for ($ii = 0; $ii -lt $script:ir_count; $ii++) {
                if ($script:ir_op[$ii] -eq $IR_LABEL -and $script:ir_dst[$ii] -eq $startLbl) {
                    $foundIdx = $ii; $foundDead = $script:ir_dead[$ii]; break
                }
            }
            Write-Host ("  [DBG] _start IR_LABEL idx={0} dead={1}" -f $foundIdx, $foundDead) -ForegroundColor Magenta
        }
        [void]$script:link_modules.Add(@{ Name = $file.Name; Code = [System.Collections.ArrayList]::new($script:x86_buf); Symbols = $script:mod_symbols; Relocs = $script:mod_relocs; Strings = $script:mod_strings; Offset = 0 })
    }
    $totalIR += $irTotal; $totalIRLive += $irLive; $totalIROpt += $irOpt; $totalFns += $fnCount; $totalX86 += $x86Bytes
    [void]$moduleASTs.Add(@{ Name = $file.Name; AST = $ast; IR = $irTotal; Live = $irLive; Opt = $irOpt; X86 = $x86Bytes })

    $successCount++
    if ($hasWarnings) {
        $detail = ''
        if ($parseErrors -gt 0) { $detail += " parse=$parseErrors" }
        if ($balErrors.Count -gt 0) { $detail += " bal=$($balErrors.Count)" }
        Write-Host "  [WARN] $($file.Name): $tokCount tok, $nodeCount ast, $fnCount fn, $irLive ir, $x86Bytes B$detail" -ForegroundColor Yellow
    } else {
        Write-Host "  [OK]   $($file.Name): $tokCount tok, $nodeCount ast, $fnCount fn, $irLive ir, $x86Bytes B" -ForegroundColor Green
    }
}

# Also compile stdlib.hl and hl-bootstrap.hl
$extraFiles = @('stdlib.hl', 'hl-bootstrap.hl')
foreach ($extra in $extraFiles) {
    $extraPath = Join-Path $repoRoot $extra
    if (Test-Path $extraPath) {
        $src = Get-Content $extraPath -Raw -Encoding UTF8
        $tokens = Tokenize-HL $src
        $tokCount = $tokens.Count
        $totalTokens += $tokCount
        $fnCount = Count-Functions $tokens

        $script:ptok = if ($tokens -is [System.Collections.ArrayList]) { $tokens.ToArray() } else { $tokens }
        $script:ptok_len = $script:ptok.Count
        $script:ppos = 0
        $script:pnodes = 0
        $script:perrors = 0
        try { $ast = p_program } catch { }
        $nodeCount = $script:pnodes
        $parseErrors = $script:perrors
        $totalNodes += $nodeCount
        $totalParseErrors += $parseErrors

        if ($parseErrors -eq 0) {
            IR-Init
            try { IR-LowerModule $ast } catch {}
            $irOpt = IR-Optimize
            $irTotal = $script:ir_count
            $irLive = IR-LiveCount
            $x86Bytes = 0
            try { $x86Bytes = X86-CompileModule } catch {
        if ($env:HL_DEBUG_CODEGEN) {
            Write-Host ("  [CODEGEN-ERR] {0}: {1}" -f $file.Name, $_.Exception.Message) -ForegroundColor Magenta
            Write-Host ("    at {0}" -f $_.ScriptStackTrace) -ForegroundColor DarkMagenta
        }
    }
            if ($x86Bytes -gt 0) {
                [void]$script:link_modules.Add(@{ Name = $extra; Code = [System.Collections.ArrayList]::new($script:x86_buf); Symbols = $script:mod_symbols; Relocs = $script:mod_relocs; Offset = 0 })
            }
            $totalIR += $irTotal; $totalIRLive += $irLive; $totalIROpt += $irOpt; $totalX86 += $x86Bytes

            $successCount++
            Write-Host "  [OK]   $extra`: $tokCount tok, $nodeCount ast, $fnCount fn, $irLive ir, $x86Bytes B" -ForegroundColor Cyan
        } else {
            Write-Host "  [WARN] $extra`: $tokCount tok, $nodeCount ast, $fnCount fn parse=$parseErrors" -ForegroundColor Yellow
        }
        $totalFiles++
    }
}

Write-Host ''

# ================================================================
#  PHASE 5: Link all modules �� kernel.bin
# ================================================================
$textSize = Link-Pass1
$linkResult = Link-Pass2
$resolved = $linkResult[0]; $unresolved = $linkResult[1]
$stubCount = $script:link_stub_count
$kernelBin = Join-Path (Join-Path $repoRoot 'bare-kernel') 'kernel.bin'
$binSize = 0
if ($script:link_combined.Count -gt 0) {
    $binSize = Link-WriteBinary $kernelBin
}
# Write _start entry point offset to kernel.entry for rebuild-image.ps1
$entryFile = Join-Path (Join-Path $repoRoot 'bare-kernel') 'kernel.entry'
if ($script:link_global_syms.ContainsKey('_start')) {
    $startOff = $script:link_global_syms['_start']
    [System.IO.File]::WriteAllText($entryFile, "$startOff")
    Write-Host "  _start offset: $startOff (0x$($startOff.ToString('X')))" -ForegroundColor Cyan
} else {
    [System.IO.File]::WriteAllText($entryFile, "0")
    Write-Host "  WARNING: _start symbol not found, defaulting to offset 0" -ForegroundColor Yellow
}
$symCount = $script:link_global_syms.Count

Write-Host '=== Compilation Pipeline Summary ===' -ForegroundColor Green
Write-Host "  Modules compiled: $successCount / $totalFiles" -ForegroundColor White
Write-Host "  Total tokens:     $totalTokens" -ForegroundColor White
Write-Host "  Total AST nodes:  $totalNodes" -ForegroundColor White
Write-Host "  Total IR instrs:  $totalIR ($totalIRLive live, $($totalIR - $totalIRLive) dead)" -ForegroundColor White
Write-Host "  IR optimizations: $totalIROpt (const-fold + DCE + strength-reduce)" -ForegroundColor White
Write-Host "  x86_64 output:    $totalX86 bytes (.text)" -ForegroundColor White
Write-Host "  Linker:           $($script:link_modules.Count) modules, $symCount symbols, $resolved relocs resolved" -ForegroundColor White
if ($stubCount -gt 0) {
    Write-Host "  Builtin stubs:    $stubCount (runtime-bound trampolines)" -ForegroundColor DarkCyan
}
if ($unresolved -gt 0) {
    Write-Host "  Unresolved relocs: $unresolved" -ForegroundColor Yellow
    # Sprint 35: dump 未解析符号 → .tmp/unresolved-syms.txt（按出现次数降序）
    $tmpDir = Join-Path $repoRoot '.tmp'
    if (-not (Test-Path $tmpDir)) { [void](New-Item -ItemType Directory -Path $tmpDir -Force) }
    $dumpPath = Join-Path $tmpDir 'unresolved-syms.txt'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Unresolved relocations dump — Sprint 35 诊断输入")
    [void]$sb.AppendLine("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("# Total unresolved sites: $unresolved")
    [void]$sb.AppendLine("# Distinct symbols: $($script:link_unresolved_map.Count)")
    [void]$sb.AppendLine("# Format: <count>`t<symbol>")
    [void]$sb.AppendLine("")
    $sorted = $script:link_unresolved_map.GetEnumerator() | Sort-Object -Property Value -Descending
    foreach ($kv in $sorted) {
        [void]$sb.AppendLine(("{0}`t{1}" -f $kv.Value, $kv.Key))
    }
    [System.IO.File]::WriteAllText($dumpPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  Unresolved dump:   $dumpPath ($($script:link_unresolved_map.Count) distinct)" -ForegroundColor DarkYellow
}
Write-Host "  kernel.bin:       $binSize bytes @ 0x$($script:LINK_TEXT_BASE.ToString('X'))" -ForegroundColor White
Write-Host "  Functions found:  $totalFns" -ForegroundColor White
if ($totalParseErrors -gt 0) {
    Write-Host "  Parse warnings:   $totalParseErrors (non-fatal, recovery applied)" -ForegroundColor Yellow
}
if ($totalBalErrors -gt 0) {
    Write-Host "  Balance errors:   $totalBalErrors" -ForegroundColor Yellow
}
if ($warnFiles.Count -gt 0) {
    Write-Host "  Files with warnings:" -ForegroundColor DarkGray
    foreach ($wf in $warnFiles) { Write-Host "    - $wf" -ForegroundColor DarkGray }
}
Write-Host ''
Write-Host 'Pipeline Phase 1-5 complete.' -ForegroundColor Green
exit 0