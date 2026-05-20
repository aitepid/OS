# gui-symbol-audit.ps1 -- Phase 1.7 symbol resolution for G1-G8 GUI modules
#
# Builds a global symbol table from ALL bare-kernel/hl/*.hl top-level fn/let
# declarations (depth-0 scan, no full parse — fast), then for each of the 47
# GUI modules parses to AST and verifies every Ident reference resolves to:
#   1. function parameter
#   2. local let in current scope
#   3. global symbol (any module's top-level fn/let)
#   4. known kernel primitive
# Unresolved references are reported as warnings (likely typos).

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# === Reuse tokenizer ===
function Tokenize-HL2 {
    param([string]$src)
    $kws = @('let','mut','fn','return','if','else','while','for','in','print','quadrant','emit','spawn','near','fold','from','with','break','continue','try','catch','finally','import','as','assert','del','pass','elif','not','class','self','super','yield','raise','true','false','nil')
    $tokens = [System.Collections.ArrayList]::new()
    $i = 0; $len = $src.Length
    while ($i -lt $len) {
        $ch = $src[$i]
        if ([char]::IsWhiteSpace($ch)) { $i++; continue }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '/') { while ($i -lt $len -and $src[$i] -ne "`n") { $i++ }; continue }
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '*') {
            $i += 2
            while ($i -lt ($len-1)) { if ($src[$i] -eq '*' -and $src[$i+1] -eq '/') { $i += 2; break }; $i++ }
            continue
        }
        if ([char]::IsDigit($ch)) {
            $num = ''
            if ($ch -eq '0' -and ($i+1) -lt $len -and $src[$i+1] -eq 'x') { $num = '0x'; $i += 2; while ($i -lt $len -and $src[$i] -match '[0-9a-fA-F]') { $num += $src[$i]; $i++ } }
            else { while ($i -lt $len -and $src[$i] -match '[\d\.]') { $num += $src[$i]; $i++ } }
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
            if ($kws -contains $id) { [void]$tokens.Add(@($id,$id)) } else { [void]$tokens.Add(@('Ident',$id)) }
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

# === Fast top-level decl scanner (depth-0 fn/let only) ===
function ScanTopDecls {
    param($tokens)
    $names = [System.Collections.Generic.HashSet[string]]::new()
    $depth = 0
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i][0]
        if ($t -eq '{' -or $t -eq '(' -or $t -eq '[') { $depth++; continue }
        if ($t -eq '}' -or $t -eq ')' -or $t -eq ']') { $depth--; continue }
        if ($depth -ne 0) { continue }
        if ($t -eq 'fn' -and $tokens[$i+1][0] -eq 'Ident') { [void]$names.Add($tokens[$i+1][1]); continue }
        if ($t -eq 'let') {
            $j = $i + 1
            if ($tokens[$j][0] -eq 'mut') { $j++ }
            if ($tokens[$j][0] -eq 'Ident') { [void]$names.Add($tokens[$j][1]) }
        }
    }
    return $names
}

# === Build global symbol table from ALL .hl in bare-kernel/hl/ ===
Write-Host '=== HicOS GUI Symbol Audit (Phase 1.7) ===' -ForegroundColor Cyan
Write-Host '  Scanning all bare-kernel/hl/*.hl for top-level decls...' -ForegroundColor DarkGray
$globals = [System.Collections.Generic.HashSet[string]]::new()
$allFiles = Get-ChildItem 'bare-kernel/hl' -Filter '*.hl' -File
foreach ($f in $allFiles) {
    $src = [System.IO.File]::ReadAllText($f.FullName)
    $toks = Tokenize-HL2 -src $src
    $names = ScanTopDecls -tokens $toks
    foreach ($n in $names) { [void]$globals.Add($n) }
}
Write-Host ("  Global symbols collected: {0} (from {1} files)" -f $globals.Count, $allFiles.Count)

# === Kernel primitives whitelist ===
$primitives = @(
    # Memory
    'mem_read_u8','mem_read_u16','mem_read_u32','mem_read_u64',
    'mem_write_u8','mem_write_u16','mem_write_u32','mem_write_u64',
    'mem_copy','mem_set8','mem_set16','mem_set32','mem_zero','mem_cmp',
    # Strings / arrays
    'to_string','cstr_from_addr','strlen','str_byte','str_sub','str_eq','str_concat','str_index',
    'array_new','array_of','set_at','get_at','push','pop','len','len_of','slice','sort','reverse',
    # I/O ports
    'io_in_u8','io_in_u16','io_in_u32','io_out_u8','io_out_u16','io_out_u32',
    # Math helpers
    'min','max','clamp',
    # PowerShell self-host stubs we expect
    'panic','halt',
    # Built-in callables exposed by Hilbert engine
    'print','format_hex','format_dec'
)
foreach ($p in $primitives) { [void]$globals.Add($p) }

# === Parser (port from gui-ast-audit) ===
$script:tk = $null
$script:p  = 0
function PPeek    { param([int]$n=0) return $script:tk[$script:p + $n] }
function PType    { param([int]$n=0) return $script:tk[$script:p + $n][0] }
function PEat     { $t = $script:tk[$script:p]; $script:p = $script:p + 1; return $t }
function PExpect  { param([string]$t)
    if ((PType) -ne $t) { throw "expect '$t' got '$(PType)'='$($script:tk[$script:p][1])' at tok#$($script:p)" }
    return (PEat)
}
function PExpectName {
    $tok = $script:tk[$script:p]
    if ($tok[0] -eq 'Ident' -or ($tok[1] -match '^[a-zA-Z_][a-zA-Z0-9_]*$')) { return (PEat) }
    throw "expect name got '$($tok[0])'='$($tok[1])' at tok#$($script:p)"
}
$binOps = @{ '||'=1;'&&'=2;'=='=3;'!='=3;'<'=4;'>'=4;'<='=4;'>='=4;'|'=5;'^'=5;'&'=6;'<<'=7;'>>'=7;'+'=8;'-'=8;'*'=9;'/'=9;'%'=9;'//'=9 }
$assignOps = @('=','+=','-=','*=','/=','%=','&=','|=','^=','<<=','>>=','//=','**=')

function PExpr { param([int]$minP=0)
    $left = PUnary
    while ($true) {
        $op = PType
        if ($binOps.ContainsKey($op)) {
            $prec = $binOps[$op]
            if ($prec -lt $minP) { break }
            [void](PEat); $right = PExpr -minP ($prec + 1)
            $left = @{ kind='BinOp'; op=$op; l=$left; r=$right }; continue
        }
        break
    }
    return $left
}
function PUnary {
    $t = PType
    if ($t -eq '-' -or $t -eq '!' -or $t -eq 'not' -or $t -eq '~') {
        [void](PEat); $e = PUnary; return @{ kind='UnOp'; op=$t; v=$e }
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
                $args += ,(PExpr)
                while ((PType) -eq ',') { [void](PEat); $args += ,(PExpr) }
            }
            [void](PExpect ')'); $e = @{ kind='Call'; callee=$e; args=$args }; continue
        }
        if ($t -eq '[') { [void](PEat); $idx = PExpr; [void](PExpect ']'); $e = @{ kind='Index'; o=$e; i=$idx }; continue }
        if ($t -eq '.') { [void](PEat); $m = PExpectName; $e = @{ kind='Member'; o=$e; m=$m[1] }; continue }
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
        '(' { [void](PEat); $e = PExpr; [void](PExpect ')'); return $e }
        '[' {
            [void](PEat); $els = @()
            if ((PType) -ne ']') { $els += ,(PExpr); while ((PType) -eq ',') { [void](PEat); $els += ,(PExpr) } }
            [void](PExpect ']'); return @{ kind='Array'; e=$els }
        }
    }
    if ($t[1] -match '^[a-zA-Z_][a-zA-Z0-9_]*$' -and $t[0] -ne 'EOF') {
        [void](PEat); return @{ kind='Ident'; n=$t[1] }
    }
    throw "unexpected primary '$($t[0])'='$($t[1])' at tok#$($script:p)"
}
function PBlock {
    [void](PExpect '{'); $stmts = @()
    while ((PType) -ne '}' -and (PType) -ne 'EOF') { $stmts += ,(PStmt) }
    [void](PExpect '}'); return @{ kind='Block'; s=$stmts }
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
    $e = PExpr; $op = PType
    if ($assignOps -contains $op) { [void](PEat); $r = PExpr; [void](PExpect ';'); return @{ kind='Assign'; op=$op; l=$e; r=$r } }
    [void](PExpect ';'); return @{ kind='ExprStmt'; e=$e }
}
function PIf {
    [void](PExpect 'if'); $c = PExpr; $t = PBlock; $f = $null
    if ((PType) -eq 'else') { [void](PEat); if ((PType) -eq 'if') { $f = PIf } else { $f = PBlock } }
    return @{ kind='If'; c=$c; t=$t; f=$f }
}
function PLet {
    [void](PExpect 'let'); $mut = $false
    if ((PType) -eq 'mut') { [void](PEat); $mut = $true }
    $nm = (PExpectName)[1]; $v = $null
    if ((PType) -eq '=') { [void](PEat); $v = PExpr }
    [void](PExpect ';'); return @{ kind='Let'; mut=$mut; n=$nm; v=$v }
}
function PFn {
    [void](PExpect 'fn'); $nm = (PExpectName)[1]; [void](PExpect '(')
    $params = @()
    if ((PType) -ne ')') {
        $params += (PExpectName)[1]
        while ((PType) -eq ',') { [void](PEat); $params += (PExpectName)[1] }
    }
    [void](PExpect ')'); $body = PBlock
    return @{ kind='Fn'; n=$nm; p=$params; b=$body }
}
function PModule {
    $decls = @()
    while ((PType) -ne 'EOF') {
        $t = PType
        if ($t -eq 'let') { $decls += ,(PLet) }
        elseif ($t -eq 'fn') { $decls += ,(PFn) }
        elseif ($t -eq 'print') { $decls += ,(PStmt) }
        else { throw "unexpected top-level '$t' at tok#$($script:p)" }
    }
    return @{ kind='Module'; d=$decls }
}

# === Reference walker (scoped) ===
$script:refs = $null
function WalkExpr { param($e, $scope)
    if ($null -eq $e) { return }
    switch ($e.kind) {
        'Ident' { if (-not $scope.Contains($e.n)) { [void]$script:refs.Add($e.n) }; return }
        'Num' { return }
        'Str' { return }
        'Bool' { return }
        'Nil' { return }
        'BinOp' { WalkExpr $e.l $scope; WalkExpr $e.r $scope; return }
        'UnOp'  { WalkExpr $e.v $scope; return }
        'Call'  { WalkExpr $e.callee $scope; foreach ($a in $e.args) { WalkExpr $a $scope }; return }
        'Index' { WalkExpr $e.o $scope; WalkExpr $e.i $scope; return }
        'Member'{ WalkExpr $e.o $scope; return }
        'Array' { foreach ($x in $e.e) { WalkExpr $x $scope }; return }
    }
}
function WalkStmt { param($s, $locals)
    if ($null -eq $s) { return }
    switch ($s.kind) {
        'Let'      { if ($s.v) { WalkExpr $s.v $locals }; [void]$locals.Add($s.n); return }
        'Return'   { if ($s.v) { WalkExpr $s.v $locals }; return }
        'If'       { WalkExpr $s.c $locals; WalkBlock $s.t $locals; if ($s.f) { if ($s.f.kind -eq 'If') { WalkStmt $s.f $locals } else { WalkBlock $s.f $locals } }; return }
        'While'    { WalkExpr $s.c $locals; WalkBlock $s.b $locals; return }
        'Break'    { return }
        'Continue' { return }
        'Block'    { WalkBlock $s $locals; return }
        'Assign'   { WalkExpr $s.l $locals; WalkExpr $s.r $locals; return }
        'ExprStmt' { WalkExpr $s.e $locals; return }
    }
}
function WalkBlock { param($b, $outerLocals)
    $locals = [System.Collections.Generic.HashSet[string]]::new($outerLocals)
    foreach ($st in $b.s) { WalkStmt $st $locals }
}

# === GUI module roster ===
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

Write-Host ''
Write-Host '  Resolving references in 47 GUI modules...' -ForegroundColor DarkGray
$totRefs = 0
$totUnresolved = 0
$failedFiles = [System.Collections.ArrayList]::new()
$idx = 0
foreach ($mod in $guiModules) {
    $idx++
    $path = "bare-kernel/hl/$mod.hl"
    $src = [System.IO.File]::ReadAllText($path)
    $script:tk = Tokenize-HL2 -src $src
    $script:p  = 0
    try { $ast = PModule } catch { Write-Host ("  [{0,2}/{1}] PARSE-ERR  {2}" -f $idx,$guiModules.Count,$mod) -ForegroundColor Red; continue }

    # Per-file walk
    $modRefs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($d in $ast.d) {
        if ($d.kind -eq 'Fn') {
            $locals = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($p in $d.p) { [void]$locals.Add($p) }
            $script:refs = [System.Collections.Generic.HashSet[string]]::new()
            WalkBlock $d.b $locals
            foreach ($r in $script:refs) { [void]$modRefs.Add($r) }
        } elseif ($d.kind -eq 'Let') {
            if ($d.v) {
                $script:refs = [System.Collections.Generic.HashSet[string]]::new()
                $emptyScope = [System.Collections.Generic.HashSet[string]]::new()
                WalkExpr $d.v $emptyScope
                foreach ($r in $script:refs) { [void]$modRefs.Add($r) }
            }
        } elseif ($d.kind -eq 'ExprStmt') {
            $script:refs = [System.Collections.Generic.HashSet[string]]::new()
            $emptyScope = [System.Collections.Generic.HashSet[string]]::new()
            WalkExpr $d.e $emptyScope
            foreach ($r in $script:refs) { [void]$modRefs.Add($r) }
        }
    }

    $unresolved = @()
    foreach ($r in $modRefs) {
        if (-not $globals.Contains($r)) { $unresolved += $r }
    }
    $totRefs += $modRefs.Count
    $totUnresolved += $unresolved.Count
    if ($unresolved.Count -gt 0) {
        Write-Host ("  [{0,2}/{1}] WARN {2,-22}  {3,3} refs  {4,2} unresolved: {5}" -f `
            $idx,$guiModules.Count,$mod,$modRefs.Count,$unresolved.Count,($unresolved -join ',')) -ForegroundColor Yellow
        [void]$failedFiles.Add(@($mod, $unresolved))
    } else {
        Write-Host ("  [{0,2}/{1}] OK   {2,-22}  {3,3} refs" -f $idx,$guiModules.Count,$mod,$modRefs.Count) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '=== Aggregate ===' -ForegroundColor Cyan
Write-Host ("  Files          : {0}" -f $guiModules.Count)
Write-Host ("  Global symbols : {0}" -f $globals.Count)
Write-Host ("  Unique refs    : {0}" -f $totRefs)
Write-Host ("  Unresolved     : {0}" -f $totUnresolved)
Write-Host ("  Files w/ warn  : {0}" -f $failedFiles.Count)
exit 0
