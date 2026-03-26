param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

if ($Args.Count -lt 1) {
    Write-Host 'H-L Self-Hosting Bootstrap Compiler v6.0' -ForegroundColor Green
    Write-Host 'Usage: hl-bootstrap <command|target.hl> [args...]' -ForegroundColor Red
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  build                Build hicos-hl.img from source'
    Write-Host '  compile              Run compilation pipeline (lex all modules)'
    Write-Host '  test                 Run the built-in test suite'
    Write-Host '  interpret <file.hl>  Interpret an H-L source file'
    Write-Host '  lex <file.hl>        Tokenize and print tokens'
    Write-Host '  info                 Show compiler/system info'
    Write-Host '  gate                 Run full readiness gate checks'
    Write-Host '  boot                 Build and boot in QEMU'
    Write-Host ''
    Write-Host 'Legacy targets:'
    Write-Host '  bare-kernel/hl/build.hl        -> build'
    Write-Host '  bare-kernel/hl/test-runner.hl  -> test'
    exit 1
}

$target = $Args[0]

# ==============================
# Legacy target mapping
# ==============================
if ($target.Replace('/', '\') -eq 'bare-kernel\hl\build.hl') {
    Write-Host '[hl-bootstrap] build -> running readiness gates + build' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\boot-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    powershell -ExecutionPolicy Bypass -File '.\scripts\image-layout-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host 'Running hl-bootstrap build...' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\rebuild-image.ps1'
    exit $LASTEXITCODE
}

if ($target.Replace('/', '\') -eq 'bare-kernel\hl\test-runner.hl') {
    Write-Host '[hl-bootstrap] test -> running strict workspace/runtime checks' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\validate-workspace.ps1' -StrictLanguagePurity -StrictNoStubs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    powershell -ExecutionPolicy Bypass -File '.\scripts\runtime-path-readiness.ps1'
    exit $LASTEXITCODE
}

# ==============================
# New command dispatch
# ==============================
if ($target -eq 'build') {
    Write-Host '[hl-bootstrap] build' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\boot-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    powershell -ExecutionPolicy Bypass -File '.\scripts\image-layout-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    # Phase 1: Compilation pipeline (lex all modules)
    powershell -ExecutionPolicy Bypass -File '.\scripts\hl-compile-pipeline.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    powershell -ExecutionPolicy Bypass -File '.\scripts\hl-bootstrap-build-test.ps1'
    exit $LASTEXITCODE
}

if ($target -eq 'compile') {
    Write-Host '[hl-bootstrap] compile (Phase 1: Lex all modules)' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\hl-compile-pipeline.ps1'
    exit $LASTEXITCODE
}

if ($target -eq 'test') {
    Write-Host '[hl-bootstrap] test' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\validate-workspace.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    powershell -ExecutionPolicy Bypass -File '.\scripts\runtime-path-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    # Run bootstrap build-test suite
    powershell -ExecutionPolicy Bypass -File '.\scripts\hl-bootstrap-build-test.ps1'
    exit $LASTEXITCODE
}

if ($target -eq 'gate') {
    Write-Host '[hl-bootstrap] full gate' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\full-gate.ps1'
    exit $LASTEXITCODE
}

if ($target -eq 'boot') {
    Write-Host '[hl-bootstrap] build + boot' -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File '.\scripts\boot-readiness.ps1'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (Test-Path '.\scripts\run-qemu.ps1') {
        powershell -ExecutionPolicy Bypass -File '.\scripts\run-qemu.ps1'
    } else {
        Write-Host 'QEMU runner not found. Ensure scripts/run-qemu.ps1 exists.' -ForegroundColor Yellow
    }
    exit $LASTEXITCODE
}

if ($target -eq 'info') {
    Write-Host 'H-L Self-Hosting Bootstrap Compiler v6.0' -ForegroundColor Green
    Write-Host "Source: hl-bootstrap.hl ($((Get-Content hl-bootstrap.hl | Measure-Object -Line).Lines) lines)" -ForegroundColor White
    Write-Host "Binary: hicos-hl.img ($((Get-Item hicos-hl.img).Length) bytes)" -ForegroundColor White
    $hlFiles = (Get-ChildItem -Recurse -Filter '*.hl' -Exclude '.vs' | Measure-Object).Count
    $kernelModules = (Get-ChildItem -Path 'bare-kernel/hl' -Filter '*.hl' | Measure-Object).Count
    Write-Host "H-L source files: $hlFiles" -ForegroundColor White
    Write-Host "Kernel modules:   $kernelModules" -ForegroundColor White
    Write-Host ''
    Write-Host 'The compiler IS the OS. The OS IS the compiler.' -ForegroundColor Green
    Write-Host 'Zero JavaScript. Zero Rust. Zero external dependencies.' -ForegroundColor Green
    exit 0
}

if ($target -eq 'interpret') {
    if ($Args.Count -lt 2) {
        Write-Host 'Usage: hl-bootstrap interpret <file.hl>' -ForegroundColor Red
        exit 1
    }
    $hlFile = $Args[1]
    if (-not (Test-Path $hlFile)) {
        Write-Host "File not found: $hlFile" -ForegroundColor Red
        exit 1
    }
    $script:hlArgs = @()
    $script:hlReturn = $false
    $script:hlReturnVal = $null
    if ($Args.Count -gt 2) { $script:hlArgs = $Args[2..($Args.Count-1)] }
    Write-Host "[hl-bootstrap] interpret $hlFile (args: $($script:hlArgs -join ', '))" -ForegroundColor Cyan
    # Auto-load stdlib.hl if present (provides str_*, array_*, map_* etc.)
    $stdlibPath = Join-Path $repoRoot 'stdlib.hl'
    $stdlibLines = @()
    if ((Test-Path $stdlibPath) -and -not $hlFile.EndsWith('stdlib.hl')) {
        $stdlibContent = Get-Content $stdlibPath -Raw
        # Only load function definitions from stdlib (skip self-test section)
        $stdlibAll = $stdlibContent -split "`n"
        $stdlibFiltered = [System.Collections.ArrayList]::new()
        $inSelfTest = $false
        foreach ($sl in $stdlibAll) {
            if ($sl -match '// SELF-TEST') { $inSelfTest = $true }
            if (-not $inSelfTest) { [void]$stdlibFiltered.Add($sl) }
        }
        $stdlibLines = $stdlibFiltered.ToArray()
        Write-Host "  Stdlib: loaded $($stdlibLines.Count) lines (functions only)" -ForegroundColor DarkGray
    }
    $content = Get-Content $hlFile -Raw
    $lines = $content -split "`n"
    # Prepend stdlib lines before user code
    if ($stdlibLines.Count -gt 0) { $lines = $stdlibLines + $lines }
    Write-Host "  File: $hlFile ($((Get-Content $hlFile).Count) lines + $($stdlibLines.Count) stdlib)" -ForegroundColor White

    # === Minimal H-L interpreter (Phase 1: expressions + print + let + fn + if + while) ===
    # Variable store
    $vars = @{}
    $funcs = @{}
    $callStack = [System.Collections.Stack]::new()
    $output = [System.Collections.ArrayList]::new()

    function Split-Args {
        param([string]$s)
        $result = [System.Collections.ArrayList]::new()
        $cur = ''; $pd = 0; $bd = 0; $inS = $false
        for ($j = 0; $j -lt $s.Length; $j++) {
            $c = $s[$j]
            if ($c -eq '"') { $inS = !$inS }
            if (-not $inS) {
                if ($c -eq '(') { $pd++ } elseif ($c -eq ')') { $pd-- }
                if ($c -eq '[') { $bd++ } elseif ($c -eq ']') { $bd-- }
                if ($c -eq ',' -and $pd -eq 0 -and $bd -eq 0) {
                    [void]$result.Add($cur); $cur = ''; continue
                }
            }
            $cur += $c
        }
        if ($cur -ne '') { [void]$result.Add($cur) }
        return ,$result
    }

    # Split by semicolons respecting brace/string nesting (for single-line function bodies)
    # Also splits when } brings brace depth back to 0 so that
    #   "if cond { body; } return x;" becomes ["if cond { body; }", "return x"]
    function Split-Stmts {
        param([string]$s)
        $result = [System.Collections.ArrayList]::new()
        $cur = ''; $bd = 0; $inS = $false
        for ($j = 0; $j -lt $s.Length; $j++) {
            $c = $s[$j]
            if ($c -eq '"') { $inS = !$inS }
            if (-not $inS) {
                if ($c -eq '{') { $bd++ }
                elseif ($c -eq '}') {
                    $bd--
                    if ($bd -eq 0) {
                        $cur += $c
                        $t = $cur.Trim()
                        if ($t -ne '') { [void]$result.Add($t) }
                        $cur = ''; continue
                    }
                }
                if ($c -eq ';' -and $bd -eq 0) {
                    $t = $cur.Trim()
                    if ($t -ne '') { [void]$result.Add($t) }
                    $cur = ''; continue
                }
            }
            $cur += $c
        }
        $t = $cur.Trim()
        if ($t -ne '') { [void]$result.Add($t) }
        return $result.ToArray()
    }

    # String-aware net brace count: ignores { } inside "..."
    function Net-Braces {
        param([string]$line)
        $net = 0; $inStr = $false
        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = $line[$i]
            if ($c -eq '"') { $inStr = !$inStr }
            if (-not $inStr) {
                if ($c -eq '{') { $net++ }
                elseif ($c -eq '}') { $net-- }
            }
        }
        return $net
    }

    function Eval-Expr {
        param([string]$expr, [hashtable]$localVars)
        $e = $expr.Trim()
        if ($e -eq '') { return 0 }
        # String literal with escape sequences
        if ($e.StartsWith('"') -and $e.EndsWith('"') -and $e.Length -ge 2) {
            $inner = $e.Substring(1, $e.Length - 2)
            if (-not $inner.Contains('"')) {
                $inner = $inner.Replace('\r', [string][char]13).Replace('\n', [string][char]10).Replace('\t', [string][char]9)
                return $inner
            }
        }
        # Integer literal
        if ($e -match '^\-?\d+$') { return [long]$e }
        # nil / true / false literals
        if ($e -eq 'nil') { return $null }
        if ($e -eq 'true') { return 1 }
        if ($e -eq 'false') { return 0 }
        # Array/string indexing: name[expr] or name[expr][expr]...
        # Only handle as pure indexing if nothing follows the brackets (no trailing binary ops)
        if ($e -match '^(\w+)\[') {
            $baseName = $Matches[1]
            # Direct assignment avoids PowerShell pipeline enumeration of single-element collections
            $base = $null
            if ($localVars -and $localVars.ContainsKey($baseName)) { $base = $localVars[$baseName] }
            elseif ($vars.ContainsKey($baseName)) { $base = $vars[$baseName] }
            $rest = $e.Substring($baseName.Length)
            while ($rest -ne '' -and $rest[0] -eq '[') {
                $bd = 0; $ei = -1
                for ($bi = 0; $bi -lt $rest.Length; $bi++) {
                    if ($rest[$bi] -eq '[') { $bd++ } elseif ($rest[$bi] -eq ']') { $bd--; if ($bd -eq 0) { $ei = $bi; break } }
                }
                if ($ei -lt 0) { break }
                $idxExpr = $rest.Substring(1, $ei - 1)
                $idx = Eval-Expr $idxExpr $localVars
                if ($base -is [string]) { $base = [string]$base[[int]$idx] } else { $base = $base[[int]$idx] }
                $rest = $rest.Substring($ei + 1)
            }
            # If rest is non-empty (e.g., " == val", " + 1"), there are trailing binary ops.
            # Rebuild the expression with the resolved indexed value and re-evaluate.
            if ($rest.Trim() -ne '') {
                $resolvedLeft = $base
                $resolvedExpr = $rest.TrimStart()
                # Re-evaluate: resolvedLeft <op> <right>
                # Find the operator at the start of resolvedExpr
                $rebuilt = "($resolvedLeft)$rest"
                # Simpler: directly scan resolvedExpr for the operator and evaluate right side
                foreach ($op in @(' || ',' && ',' == ',' != ',' >= ',' <= ',' > ',' < ',' + ',' - ',' * ',' / ',' % ')) {
                    if ($rest.StartsWith($op) -or $rest.StartsWith($op.TrimStart())) {
                        $opTrimmed = $op.Trim()
                        $rightExpr = $rest.Substring($rest.IndexOf($opTrimmed) + $opTrimmed.Length)
                        $right = Eval-Expr $rightExpr $localVars
                        switch ($opTrimmed) {
                            '||' { if (($resolvedLeft -and $resolvedLeft -ne 0) -or ($right -and $right -ne 0)) { return 1 } else { return 0 } }
                            '&&' { if (($resolvedLeft -and $resolvedLeft -ne 0) -and ($right -and $right -ne 0)) { return 1 } else { return 0 } }
                            '+' { if ($resolvedLeft -is [string] -or $right -is [string]) { return "$resolvedLeft$right" } else { return [long]$resolvedLeft + [long]$right } }
                            '-' { return [long]$resolvedLeft - [long]$right }
                            '*' { return [long]$resolvedLeft * [long]$right }
                            '/' { if ([long]$right -eq 0) { throw "DIVZERO $resolvedLeft / $right in $e" } else { return [math]::Floor([long]$resolvedLeft / [long]$right) } }
                            '%' { if ([long]$right -eq 0) { throw "MODZERO $resolvedLeft % $right in $e" } else { return [long]$resolvedLeft % [long]$right } }
                            '==' { if ($resolvedLeft -eq $right) { return 1 } else { return 0 } }
                            '!=' { if ($resolvedLeft -ne $right) { return 1 } else { return 0 } }
                            '>=' { if ([long]$resolvedLeft -ge [long]$right) { return 1 } else { return 0 } }
                            '<=' { if ([long]$resolvedLeft -le [long]$right) { return 1 } else { return 0 } }
                            '>' { if ([long]$resolvedLeft -gt [long]$right) { return 1 } else { return 0 } }
                            '<' { if ([long]$resolvedLeft -lt [long]$right) { return 1 } else { return 0 } }
                        }
                    }
                }
                # Fallback: return indexed value (shouldn't reach here normally)
                if ($base -is [System.Collections.IList]) { return ,$base }
                return $base
            }
            if ($base -is [System.Collections.IList]) { return ,$base }
            return $base
        }
        # Logical NOT prefix: !expr
        if ($e.StartsWith('!') -and $e.Length -gt 1 -and $e[1] -ne '=') {
            $notVal = Eval-Expr $e.Substring(1) $localVars
            if ($notVal -and $notVal -ne 0) { return 0 } else { return 1 }
        }
        # Variable lookup (comma prevents ArrayList unrolling)
        if ($localVars -and $localVars.ContainsKey($e)) { $lv = $localVars[$e]; if ($lv -is [System.Collections.IList]) { return ,$lv }; return $lv }
        if ($vars.ContainsKey($e)) { $gv = $vars[$e]; if ($gv -is [System.Collections.IList]) { return ,$gv }; return $gv }
        # Binary ops (right-to-left scan for correct left-associativity)
        # Pre-compute nesting depth at each position
        if ($e.Length -gt 2) {
            $dP = [int[]]::new($e.Length); $dB = [int[]]::new($e.Length); $sF = [bool[]]::new($e.Length)
            $p0 = 0; $b0 = 0; $s0 = $false
            for ($ci = 0; $ci -lt $e.Length; $ci++) {
                $ch = $e[$ci]
                if ($ch -eq '"') { $s0 = !$s0 }
                if (-not $s0) { if ($ch -eq '(') { $p0++ } elseif ($ch -eq ')') { $p0-- }; if ($ch -eq '[') { $b0++ } elseif ($ch -eq ']') { $b0-- } }
                $dP[$ci] = $p0; $dB[$ci] = $b0; $sF[$ci] = $s0
            }
            foreach ($op in @(' || ',' && ',' == ',' != ',' >= ',' <= ',' > ',' < ',' + ',' - ',' * ',' / ',' % ')) {
                $oLen = $op.Length
                for ($ci = $e.Length - $oLen; $ci -ge 0; $ci--) {
                    if (-not $sF[$ci] -and $dP[$ci] -eq 0 -and $dB[$ci] -eq 0 -and $e.Substring($ci, $oLen) -eq $op) {
                        $left = Eval-Expr $e.Substring(0, $ci) $localVars
                        $right = Eval-Expr $e.Substring($ci + $oLen) $localVars
                        switch ($op.Trim()) {
                            '||' { if (($left -and $left -ne 0) -or ($right -and $right -ne 0)) { return 1 } else { return 0 } }
                            '&&' { if (($left -and $left -ne 0) -and ($right -and $right -ne 0)) { return 1 } else { return 0 } }
                            '+' { if ($left -is [string] -or $right -is [string]) { return "$left$right" } else { return [long]$left + [long]$right } }
                            '-' { return [long]$left - [long]$right }
                            '*' { return [long]$left * [long]$right }
                            '/' { if ([long]$right -eq 0) { throw "DIVZERO $left / $right in $e" } else { return [math]::Floor([long]$left / [long]$right) } }
                            '%' { if ([long]$right -eq 0) { throw "MODZERO $left % $right in $e" } else { return [long]$left % [long]$right } }
                            '==' { if ($left -eq $right) { return 1 } else { return 0 } }
                            '!=' { if ($left -ne $right) { return 1 } else { return 0 } }
                            '>=' { if ([long]$left -ge [long]$right) { return 1 } else { return 0 } }
                            '<=' { if ([long]$left -le [long]$right) { return 1 } else { return 0 } }
                            '>' { if ([long]$left -gt [long]$right) { return 1 } else { return 0 } }
                            '<' { if ([long]$left -lt [long]$right) { return 1 } else { return 0 } }
                        }
                    }
                }
            }
        }
        # Function call: name(args) or qualified.name(args)
        if ($e -match '^([\w.]+)\s*\(') {
            $fname = $Matches[1]
            $pStart = $e.IndexOf('(')
            $pd = 0; $pEnd = -1; $inQ = $false
            for ($pi = $pStart; $pi -lt $e.Length; $pi++) {
                $pc = $e[$pi]
                if ($pc -eq '"') { $inQ = !$inQ }
                if (-not $inQ) {
                    if ($pc -eq '(') { $pd++ }
                    elseif ($pc -eq ')') { $pd--; if ($pd -eq 0) { $pEnd = $pi; break } }
                }
            }
            if ($pEnd -gt 0) {
                $fargs = ''
                if ($pEnd -gt $pStart + 1) { $fargs = $e.Substring($pStart + 1, $pEnd - $pStart - 1) }
            # Built-in: print
            if ($fname -eq 'print') {
                $val = Eval-Expr $fargs $localVars
                [void]$output.Add("$val")
                Write-Host "  > $val"
                return 0
            }
            # Built-in: to_string
            if ($fname -eq 'to_string') {
                $val = Eval-Expr $fargs $localVars
                return "$val"
            }
            # Built-in: len
            if ($fname -eq 'len') {
                $val = Eval-Expr $fargs $localVars
                if ($val -is [string]) { return $val.Length }
                if ($val -is [System.Collections.ICollection]) { return $val.Count }
                if ($val -is [array]) { return $val.Count }
                return 0
            }
            # Built-in: push (mutates array)
            if ($fname -eq 'push') {
                $pParts = Split-Args $fargs
                $arrRef = Eval-Expr ([string]$pParts[0]).Trim() $localVars
                $pVal = Eval-Expr ([string]$pParts[1]).Trim() $localVars
                if ($pVal -is [array] -and $pVal.Length -eq 1 -and $pVal[0] -is [System.Collections.IList]) { $pVal = $pVal[0] }
                if ($arrRef -is [System.Collections.ArrayList]) { [void]$arrRef.Add($pVal) }
                return $null
            }
            # Built-in: set_at(arr, idx, val) — mutate array element
            if ($fname -eq 'set_at') {
                $saParts = Split-Args $fargs
                $saArr = Eval-Expr ([string]$saParts[0]).Trim() $localVars
                $saIdx = [int](Eval-Expr ([string]$saParts[1]).Trim() $localVars)
                $saVal = Eval-Expr ([string]$saParts[2]).Trim() $localVars
                if ($saArr -is [System.Collections.IList]) { $saArr[$saIdx] = $saVal }
                return $saArr
            }
            # Built-in: byte_array(size) — create zero-filled mutable byte array
            if ($fname -eq 'byte_array') {
                $baSize = [int](Eval-Expr $fargs $localVars)
                $ba = [System.Collections.ArrayList]::new($baSize)
                for ($bai = 0; $bai -lt $baSize; $bai++) { [void]$ba.Add([long]0) }
                return ,$ba
            }
            # Built-in: file_write(path, data) — write byte array to disk file
            if ($fname -eq 'file_write') {
                $fwParts = Split-Args $fargs
                $fwPath = Eval-Expr ([string]$fwParts[0]).Trim() $localVars
                $fwData = Eval-Expr ([string]$fwParts[1]).Trim() $localVars
                if ($fwData -is [System.Collections.IList]) {
                    $bytes = [byte[]]::new($fwData.Count)
                    for ($fwi = 0; $fwi -lt $fwData.Count; $fwi++) { $bytes[$fwi] = [byte]([long]$fwData[$fwi] -band 0xFF) }
                    [System.IO.File]::WriteAllBytes((Join-Path $repoRoot $fwPath), $bytes)
                    Write-Host "  [file_write] $fwPath ($($bytes.Length) bytes)" -ForegroundColor Green
                }
                return 0
            }
            # Built-in: file_read(path) — read file contents as string
            if ($fname -eq 'file_read') {
                $frPath = Eval-Expr $fargs $localVars
                $frFull = Join-Path $repoRoot $frPath
                if (Test-Path $frFull) { return (Get-Content $frFull -Raw) }
                return $null
            }
            # Built-in: file_exists(path)
            if ($fname -eq 'file_exists') {
                $fePath = Eval-Expr $fargs $localVars
                if (Test-Path (Join-Path $repoRoot $fePath)) { return 1 } else { return 0 }
            }
            # Built-in: native string operations (override stdlib H-L implementations for speed)
            if ($fname -eq 'str_find') {
                $sfParts = Split-Args $fargs
                $sfStr = Eval-Expr ([string]$sfParts[0]).Trim() $localVars
                $sfNeedle = Eval-Expr ([string]$sfParts[1]).Trim() $localVars
                if ($null -eq $sfStr -or $null -eq $sfNeedle) { return [long]-1 }
                $pos = "$sfStr".IndexOf("$sfNeedle"); return [long]$pos
            }
            if ($fname -eq 'str_sub') {
                $ssParts = Split-Args $fargs
                $ssStr = Eval-Expr ([string]$ssParts[0]).Trim() $localVars
                $ssStart = [int](Eval-Expr ([string]$ssParts[1]).Trim() $localVars)
                $ssEnd = [int](Eval-Expr ([string]$ssParts[2]).Trim() $localVars)
                if ($null -eq $ssStr) { return "" }
                $s = "$ssStr"; if ($ssStart -lt 0) { $ssStart = 0 }; if ($ssEnd -gt $s.Length) { $ssEnd = $s.Length }
                if ($ssEnd -le $ssStart) { return "" }
                return $s.Substring($ssStart, $ssEnd - $ssStart)
            }
            if ($fname -eq 'str_contains') {
                $scParts = Split-Args $fargs
                $scStr = Eval-Expr ([string]$scParts[0]).Trim() $localVars
                $scNeedle = Eval-Expr ([string]$scParts[1]).Trim() $localVars
                if ("$scStr".Contains("$scNeedle")) { return 1 } else { return 0 }
            }
            if ($fname -eq 'str_starts_with') {
                $swParts = Split-Args $fargs
                $swStr = Eval-Expr ([string]$swParts[0]).Trim() $localVars
                $swPfx = Eval-Expr ([string]$swParts[1]).Trim() $localVars
                if ("$swStr".StartsWith("$swPfx")) { return 1 } else { return 0 }
            }
            if ($fname -eq 'str_ends_with') {
                $seParts = Split-Args $fargs
                $seStr = Eval-Expr ([string]$seParts[0]).Trim() $localVars
                $seSfx = Eval-Expr ([string]$seParts[1]).Trim() $localVars
                if ("$seStr".EndsWith("$seSfx")) { return 1 } else { return 0 }
            }
            if ($fname -eq 'str_trim') {
                $stVal = Eval-Expr $fargs $localVars
                return "$stVal".Trim()
            }
            if ($fname -eq 'str_len') {
                $slVal = Eval-Expr $fargs $localVars
                return [long]"$slVal".Length
            }
            if ($fname -eq 'str_split') {
                $ssParts = Split-Args $fargs
                $ssStr = Eval-Expr ([string]$ssParts[0]).Trim() $localVars
                $ssSep = Eval-Expr ([string]$ssParts[1]).Trim() $localVars
                $result = [System.Collections.ArrayList]::new()
                if ("$ssSep" -eq '') {
                    for ($ssi = 0; $ssi -lt "$ssStr".Length; $ssi++) { [void]$result.Add([string]"$ssStr"[$ssi]) }
                } else {
                    $parts = "$ssStr".Split("$ssSep")
                    foreach ($p in $parts) { [void]$result.Add($p) }
                }
                return ,$result
            }
            if ($fname -eq 'str_replace') {
                $srParts = Split-Args $fargs
                $srStr = Eval-Expr ([string]$srParts[0]).Trim() $localVars
                $srOld = Eval-Expr ([string]$srParts[1]).Trim() $localVars
                $srNew = Eval-Expr ([string]$srParts[2]).Trim() $localVars
                return "$srStr".Replace("$srOld", "$srNew")
            }
            if ($fname -eq 'str_upper') {
                $suVal = Eval-Expr $fargs $localVars
                return "$suVal".ToUpper()
            }
            if ($fname -eq 'str_lower') {
                $slVal = Eval-Expr $fargs $localVars
                return "$slVal".ToLower()
            }
            if ($fname -eq 'str_repeat') {
                $srParts = Split-Args $fargs
                $srStr = Eval-Expr ([string]$srParts[0]).Trim() $localVars
                $srN = [int](Eval-Expr ([string]$srParts[1]).Trim() $localVars)
                return "$srStr" * $srN
            }
            # Built-in: process_args() — return script arguments
            if ($fname -eq 'process_args') {
                $pa = [System.Collections.ArrayList]::new()
                if ($script:hlArgs) { foreach ($a in $script:hlArgs) { [void]$pa.Add($a) } }
                return ,$pa
            }
            # Built-in: floor(v)
            if ($fname -eq 'floor') {
                $flVal = Eval-Expr $fargs $localVars
                return [long][math]::Floor([double]$flVal)
            }
            # Built-in: str_from_code(code) — convert char code to single-char string
            if ($fname -eq 'str_from_code') {
                $codeVal = [int](Eval-Expr $fargs $localVars)
                if ($codeVal -ge 32 -and $codeVal -le 126) { return [string][char]$codeVal }
                if ($codeVal -eq 10) { return "`n" }
                if ($codeVal -eq 13) { return "`r" }
                if ($codeVal -eq 9) { return "`t" }
                return [string][char]$codeVal
            }
            # Built-in: str_char_at(s, i) / char_at(s, i) — return char code at position
            if ($fname -eq 'str_char_at' -or $fname -eq 'char_at') {
                $scaParts = Split-Args $fargs
                $scaStr = Eval-Expr ([string]$scaParts[0]).Trim() $localVars
                $scaIdx = [int](Eval-Expr ([string]$scaParts[1]).Trim() $localVars)
                if ($scaStr -is [string] -and $scaIdx -ge 0 -and $scaIdx -lt $scaStr.Length) { return [long][char]$scaStr[$scaIdx] }
                return [long]0
            }
            # Built-in: type_of(val)
            if ($fname -eq 'type_of') {
                $toVal = Eval-Expr $fargs $localVars
                if ($null -eq $toVal) { return "nil" }
                if ($toVal -is [string]) { return "string" }
                if ($toVal -is [System.Collections.IList]) { return "array" }
                return "number"
            }
            # Built-in: file_list(dir) — list files in directory
            if ($fname -eq 'file_list') {
                $flDir = Eval-Expr $fargs $localVars
                $flFull = Join-Path $repoRoot $flDir
                $flResult = [System.Collections.ArrayList]::new()
                if (Test-Path $flFull) {
                    Get-ChildItem $flFull -File | ForEach-Object { [void]$flResult.Add($_.Name) }
                }
                return ,$flResult
            }
            # Built-in: parse_int(s) — parse string to integer
            if ($fname -eq 'parse_int') {
                $piStr = Eval-Expr $fargs $localVars
                $piVal = 0
                if ([long]::TryParse("$piStr", [ref]$piVal)) { return $piVal }
                return 0
            }
            # Built-in: le_u32(v) — split 32-bit value into 4 LE bytes
            if ($fname -eq 'le_u32') {
                $leV = [long](Eval-Expr $fargs $localVars)
                $leArr = [System.Collections.ArrayList]::new()
                [void]$leArr.Add($leV % 256)
                [void]$leArr.Add(([long][math]::Floor($leV / 256)) % 256)
                [void]$leArr.Add(([long][math]::Floor($leV / 65536)) % 256)
                [void]$leArr.Add(([long][math]::Floor($leV / 16777216)) % 256)
                return ,$leArr
            }
            # Built-in: le_u16(v) — split 16-bit value into 2 LE bytes
            if ($fname -eq 'le_u16') {
                $leV = [long](Eval-Expr $fargs $localVars)
                $leArr = [System.Collections.ArrayList]::new()
                [void]$leArr.Add($leV % 256)
                [void]$leArr.Add(([long][math]::Floor($leV / 256)) % 256)
                return ,$leArr
            }
            # User-defined function
            if ($funcs.ContainsKey($fname)) {
                $fdef = $funcs[$fname]
                $newLocals = @{}
                if ($fargs -and $fdef.Params.Count -gt 0) {
                    $argVals = Split-Args $fargs
                    for ($ai = 0; $ai -lt [math]::Min($argVals.Count, $fdef.Params.Count); $ai++) {
                        $pname = [string]$fdef.Params[$ai]
                        $pname = $pname.Trim()
                        $aval = [string]$argVals[$ai]
                        $aval = $aval.Trim()
                        $newLocals[$pname] = Eval-Expr $aval $localVars
                    }
                }
                Exec-Block $fdef.Body $newLocals | Out-Null
                $callRes = $script:hlReturnVal
                $script:hlReturn = $false
                $script:hlReturnVal = $null
                if ($callRes -is [System.Collections.IList]) { return ,$callRes }
                return $callRes
            }
            return 0
            } # end if ($pEnd -gt 0)
            return 0
        }
        # Parenthesized expression
        if ($e.StartsWith('(') -and $e.EndsWith(')')) {
            $parenRes = Eval-Expr $e.Substring(1, $e.Length - 2) $localVars
            if ($parenRes -is [System.Collections.IList]) { return ,$parenRes }
            return $parenRes
        }
        # Array literal: [expr, expr, ...] (returns mutable ArrayList, comma prevents unrolling)
        if ($e.StartsWith('[') -and $e.EndsWith(']')) {
            $arrInner = $e.Substring(1, $e.Length - 2).Trim()
            if ($arrInner -eq '') { return ,([System.Collections.ArrayList]::new()) }
            $arrParts = Split-Args $arrInner
            $arrResult = [System.Collections.ArrayList]::new()
            foreach ($ap in $arrParts) { [void]$arrResult.Add((Eval-Expr ([string]$ap).Trim() $localVars)) }
            return ,$arrResult
        }
        return 0
    }

    function Exec-Block {
        param([string[]]$blockLines, [hashtable]$localVars)
        $result = 0
        $bi = 0
        $lastIfTaken = $false
        while ($bi -lt $blockLines.Count) {
            $line = [string]$blockLines[$bi]
            $line = $line.Trim()
            $bi++
            if ($line -eq '' -or $line.StartsWith('//')) { continue }

            # --- inline if: if COND { BODY; } [else { BODY; }] ---
            if ($line -match '^if\s+(.+?)\s*\{(.+?)\}\s*(else\s*\{(.+?)\})?\s*$') {
                $cond = Eval-Expr $Matches[1] $localVars
                if ($cond -and $cond -ne 0) {
                    $innerLines = @($Matches[2] -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
                    Exec-Block $innerLines $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                    $lastIfTaken = $true
                } elseif ($Matches[4]) {
                    $innerLines = @($Matches[4] -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
                    Exec-Block $innerLines $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                    $lastIfTaken = $true
                } else {
                    $lastIfTaken = $false
                }
                continue
            }

            # --- inline else if: else if COND { BODY; } ---
            if ($line -match '^else\s+if\s+(.+?)\s*\{(.+?)\}\s*$') {
                if (-not $lastIfTaken) {
                    $cond = Eval-Expr $Matches[1] $localVars
                    if ($cond -and $cond -ne 0) {
                        $innerLines = @($Matches[2] -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
                        Exec-Block $innerLines $localVars | Out-Null
                        if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                        $lastIfTaken = $true
                    }
                }
                continue
            }

            # --- multi-line else if: else if COND { ---
            if ($line -match '^else\s+if\s+(.+?)\s*\{\s*$') {
                $eifCond = $Matches[1]
                $depth = 1; $eifBody = [System.Collections.ArrayList]::new()
                while ($bi -lt $blockLines.Count -and $depth -gt 0) {
                    $el = [string]$blockLines[$bi]; $bi++
                    $depth += Net-Braces $el
                    if ($depth -gt 0) { [void]$eifBody.Add($el) }
                }
                if (-not $lastIfTaken) {
                    $cond = Eval-Expr $eifCond $localVars
                    if ($cond -and $cond -ne 0) {
                        Exec-Block $eifBody.ToArray() $localVars | Out-Null
                        if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                        $lastIfTaken = $true
                    }
                }
                continue
            }

            # --- inline else: else { BODY; } ---
            if ($line -match '^else\s*\{(.+?)\}\s*$') {
                if (-not $lastIfTaken) {
                    $innerLines = @($Matches[1] -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
                    Exec-Block $innerLines $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                }
                $lastIfTaken = $false
                continue
            }

            # --- multi-line else: else { ---
            if ($line -match '^else\s*\{\s*$') {
                $depth = 1; $elseBody = [System.Collections.ArrayList]::new()
                while ($bi -lt $blockLines.Count -and $depth -gt 0) {
                    $el = [string]$blockLines[$bi]; $bi++
                    $depth += Net-Braces $el
                    if ($depth -gt 0) { [void]$elseBody.Add($el) }
                }
                if (-not $lastIfTaken) {
                    Exec-Block $elseBody.ToArray() $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                }
                $lastIfTaken = $false
                continue
            }

            # --- multi-line if (braces span multiple lines) ---
            if ($line -match '^if\s+(.+?)\s*\{\s*$') {
                $condExpr = $Matches[1]
                $cond = Eval-Expr $condExpr $localVars
                $depth = 1; $ifBody = [System.Collections.ArrayList]::new()
                $handledElse = $false
                while ($bi -lt $blockLines.Count -and $depth -gt 0) {
                    $il = [string]$blockLines[$bi]; $bi++
                    $trimIl = $il.Trim()
                    # Check for } else {
                    if ($depth -eq 1 -and $trimIl -match '^\}\s*else\s*\{\s*$') {
                        $handledElse = $true
                        # Collect else body
                        $elseBody = [System.Collections.ArrayList]::new()
                        $edepth = 1
                        while ($bi -lt $blockLines.Count -and $edepth -gt 0) {
                            $el = [string]$blockLines[$bi]; $bi++
                            $edepth += Net-Braces $el
                            if ($edepth -gt 0) { [void]$elseBody.Add($el) }
                        }
                        if ($cond -and $cond -ne 0) {
                            Exec-Block $ifBody.ToArray() $localVars | Out-Null
                            if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                            $lastIfTaken = $true
                        } else {
                            Exec-Block $elseBody.ToArray() $localVars | Out-Null
                            if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                            $lastIfTaken = $true
                        }
                        $depth = 0
                        continue
                    }
                    $depth += Net-Braces $il
                    if ($depth -gt 0) { [void]$ifBody.Add($il) }
                }
                if (-not $handledElse -and $ifBody.Count -gt 0) {
                    if ($cond -and $cond -ne 0) {
                        Exec-Block $ifBody.ToArray() $localVars | Out-Null
                        if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                        $lastIfTaken = $true
                    } else {
                        $lastIfTaken = $false
                    }
                }
                continue
            }

            # --- inline while: while COND { BODY; } ---
            if ($line -match '^while\s+(.+?)\s*\{(.+)\}\s*$') {
                $condExpr = $Matches[1]
                $wBodyText = $Matches[2]
                $wBodyLines = @($wBodyText -split ';' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
                $guard = 100000
                while ($guard -gt 0) {
                    $cond = Eval-Expr $condExpr $localVars
                    if (-not $cond -or $cond -eq 0) { break }
                    Exec-Block $wBodyLines $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                    $guard--
                }
                continue
            }

            # --- multi-line while loop ---
            if ($line -match '^while\s+(.+?)\s*\{\s*$') {
                $condExpr = $Matches[1]
                $startBi = $bi; $depth = 1
                $wBody = [System.Collections.ArrayList]::new()
                while ($bi -lt $blockLines.Count -and $depth -gt 0) {
                    $wl = [string]$blockLines[$bi]; $bi++
                    $depth += Net-Braces $wl
                    if ($depth -gt 0) { [void]$wBody.Add($wl) }
                }
                $guard = 100000
                while ($guard -gt 0) {
                    $cond = Eval-Expr $condExpr $localVars
                    if (-not $cond -or $cond -eq 0) { break }
                    Exec-Block $wBody.ToArray() $localVars | Out-Null
                    if ($script:hlReturn) { $rv = $script:hlReturnVal; if ($rv -is [System.Collections.IList]) { return ,$rv }; return $rv }
                    $guard--
                }
                continue
            }

            # let [mut] name = expr;
            if ($line -match '^let\s+(mut\s+)?(\w+)\s*=\s*(.+)$') {
                $vname = $Matches[2]; $vexpr = $Matches[3] -replace '\s*;\s*$',''
                $val = Eval-Expr $vexpr $localVars
                if ($localVars) { $localVars[$vname] = $val } else { $vars[$vname] = $val }
                continue
            }
            # Array index assignment: arr[i] = expr or arr[i][j] = expr
            if ($line -match '^(\w+)(\[.+)$') {
                $aName = $Matches[1]; $aRest = $Matches[2]
                if ($aRest -match '^((?:\[[^\]]+\])+)\s*=\s*(.+)$') {
                    $indexPart = $Matches[1]; $valExpr = $Matches[2] -replace '\s*;\s*$',''
                    $idxMatches = [regex]::Matches($indexPart, '\[([^\]]+)\]')
                    $base = $null
                    if ($localVars -and $localVars.ContainsKey($aName)) { $base = $localVars[$aName] }
                    elseif ($vars.ContainsKey($aName)) { $base = $vars[$aName] }
                    if ($null -ne $base -and $idxMatches.Count -gt 0) {
                        $target = $base
                        for ($aii = 0; $aii -lt $idxMatches.Count - 1; $aii++) {
                            $idx = [int](Eval-Expr $idxMatches[$aii].Groups[1].Value $localVars)
                            $target = $target[$idx]
                        }
                        $lastIdx = [int](Eval-Expr $idxMatches[$idxMatches.Count - 1].Groups[1].Value $localVars)
                        $val = Eval-Expr $valExpr $localVars
                        $target[$lastIdx] = $val
                    }
                    continue
                }
            }
            # var = expr;
            if ($line -match '^(\w+)\s*=\s*(.+)$') {
                $vname = $Matches[1]; $vexpr = $Matches[2] -replace '\s*;\s*$',''
                if ($vname -notin @('fn','let','if','while','return')) {
                    $val = Eval-Expr $vexpr $localVars
                    if ($localVars -and $localVars.ContainsKey($vname)) { $localVars[$vname] = $val }
                    else { $vars[$vname] = $val }
                    continue
                }
            }
            # return expr;
            if ($line -match '^return\s+(.+)$') {
                $retExpr = $Matches[1] -replace '\s*;\s*$',''
                $retVal = Eval-Expr $retExpr $localVars
                $script:hlReturn = $true
                $script:hlReturnVal = $retVal
                if ($retVal -is [System.Collections.IList]) { return ,$retVal }
                return $retVal
            }
            # return; (bare)
            if ($line -match '^return\s*;?\s*$') {
                $script:hlReturn = $true
                $script:hlReturnVal = 0
                return 0
            }
            # Bare expression (function call, incl. qualified names like x86enc.emit_cli)
            if ($line -match '^[\w.]+\s*\(') {
                $line = $line -replace ';$',''
                Eval-Expr $line $localVars | Out-Null
                continue
            }
        }
        return $result
    }

    # === Pre-parse: collect function definitions and top-level code ===
    # Supports quadrant blocks: functions inside quadrant NAME { ... } are registered
    # as both "NAME.func" (qualified) and "func" (short) for cross-quadrant calls.
    $topLines = [System.Collections.ArrayList]::new()
    $currentQuadrant = $null
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i].Trim()
        if ($line -eq '' -or $line.StartsWith('//')) {
            if (-not $currentQuadrant) { [void]$topLines.Add($line) }
            $i++; continue
        }
        # Detect quadrant start
        if ($line -match '^quadrant\s+(\w+)\s*\{') {
            $currentQuadrant = $Matches[1]
            $i++; continue
        }
        # Detect quadrant end (lone closing brace)
        if ($currentQuadrant -and $line -eq '}') {
            $currentQuadrant = $null
            $i++; continue
        }
        if ($line -match '^fn\s+(\w+)\s*\(([^)]*)\)\s*\{') {
            $fname = $Matches[1]; $params = @($Matches[2] -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -ne '' })
            $qualName = $fname
            if ($currentQuadrant) { $qualName = "$currentQuadrant.$fname" }
            # Check if function body is on the same line (single-line function)
            $afterMatch = $line.Substring($line.IndexOf('{'))
            $netBr = Net-Braces $afterMatch
            if ($netBr -le 0) {
                # Single-line function: extract body between { and }
                $bodyStart = $line.IndexOf('{') + 1
                $bodyEnd = $line.LastIndexOf('}')
                $bodyText = ''
                if ($bodyEnd -gt $bodyStart) { $bodyText = $line.Substring($bodyStart, $bodyEnd - $bodyStart) }
                $bodyLines = @(Split-Stmts $bodyText)
                $fdef = @{ Params = $params; Body = $bodyLines }
                $funcs[$qualName] = $fdef
                if ($currentQuadrant) { $funcs[$fname] = $fdef }
                $i++
            } else {
                # Multi-line function
                $depth = 1; $body = [System.Collections.ArrayList]::new()
                $i++
                while ($i -lt $lines.Count -and $depth -gt 0) {
                    $fline = [string]$lines[$i]
                    $depth += Net-Braces $fline
                    if ($depth -gt 0) { [void]$body.Add($fline) }
                    $i++
                }
                $fdef = @{ Params = $params; Body = $body.ToArray() }
                $funcs[$qualName] = $fdef
                if ($currentQuadrant) { $funcs[$fname] = $fdef }
            }
        } else {
            # Non-function lines: always add to topLines (including let inside quadrants)
            [void]$topLines.Add($line)
            $i++
        }
    }

    Write-Host "  Functions: $($funcs.Count), Top-level lines: $($topLines.Count)" -ForegroundColor White
    Write-Host '  --- Execution ---' -ForegroundColor Cyan

    # Execute top-level code
    Exec-Block $topLines.ToArray() $null | Out-Null

    Write-Host '  --- Done ---' -ForegroundColor Green
    Write-Host "  Output lines: $($output.Count)" -ForegroundColor White
    exit 0
}

if ($target -eq 'lex') {
    if ($Args.Count -lt 2) {
        Write-Host 'Usage: hl-bootstrap lex <file.hl>' -ForegroundColor Red
        exit 1
    }
    $hlFile = $Args[1]
    if (-not (Test-Path $hlFile)) {
        Write-Host "File not found: $hlFile" -ForegroundColor Red
        exit 1
    }
    Write-Host "[hl-bootstrap] lex $hlFile" -ForegroundColor Cyan
    $content = Get-Content $hlFile -Raw
    # Basic lexer check
    $tokens = [regex]::Matches($content, '(?:"[^"]*"|''[^'']*''|\b\w+\b|[+\-*/=<>!&|^~%]+|[(){}\[\];,.])')
    Write-Host "Tokens: $($tokens.Count)" -ForegroundColor White
    $first20 = $tokens | Select-Object -First 20
    foreach ($tok in $first20) {
        Write-Host "  $($tok.Value)" -ForegroundColor Gray
    }
    if ($tokens.Count -gt 20) {
        Write-Host "  ... and $($tokens.Count - 20) more" -ForegroundColor DarkGray
    }
    exit 0
}

# ==============================
# Direct file target (legacy)
# ==============================
if (Test-Path $target.Replace('/', '\')) {
    Write-Host "[hl-bootstrap] target not yet mapped: $target" -ForegroundColor Yellow
    Write-Host 'Supported commands: build, test, gate, boot, interpret, lex, info' -ForegroundColor Yellow
    exit 1
}

Write-Host "Unknown command or target: $target" -ForegroundColor Red
Write-Host 'Run hl-bootstrap without arguments for usage.' -ForegroundColor Yellow
exit 1
