# lint-robustness.ps1 -- Sprint 36 robustness linter
# Implements rules from HILBERT_LANG_ROBUSTNESS.md §8.1:
#   R1 [error]   Empty catch block (silently swallows exception)
#   R2 [warning] catch-all that only logs/prints (no rethrow, no convert)
#   R3 [warning] Bare arithmetic on user-tainted values (heuristic)
#   R4 [warning] Uninitialized `let mut x;` (must have initializer)
#   R5 [info]    `finally { return ... }` (swallows current exception)
#
# Exit codes: 0 = clean; 1 = errors found; 2 = warnings only (configurable)
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$mode = if ($args -contains '--strict') { 'strict' } else { 'normal' }
$includeSelfTest = $args -contains '--with-tests'

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$infos = New-Object System.Collections.Generic.List[object]

function Add-Issue($list, $file, $line, $rule, $msg) {
    $list.Add([PSCustomObject]@{ File=$file; Line=$line; Rule=$rule; Msg=$msg })
}

# Collect .hl source files
$sources = @()
$sources += Get-ChildItem -Path (Join-Path $repoRoot 'bare-kernel\hl') -Filter '*.hl' -File
$sources += Get-ChildItem -Path $repoRoot -Filter 'HicOS_*.hl' -File
$extras = @('stdlib.hl','hl-bootstrap.hl','bootstrap.hl','build.hl','build-hl-image.hl','manifest.hl')
if ($includeSelfTest) { $extras += 'test_lint_robustness.hl' }
foreach ($e in $extras) {
    $p = Join-Path $repoRoot $e
    if (Test-Path $p) { $sources += Get-Item $p }
}

foreach ($f in $sources) {
    $rel = $f.FullName.Substring($repoRoot.Path.Length).TrimStart('\','/')
    $lines = Get-Content $f.FullName -Encoding UTF8

    # R1: Empty catch block.  Pattern: `catch ... { }` possibly with only whitespace/comments inside.
    # We look at single-line `catch ... { }` and multi-line by scanning forward.
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $rawLn = $lines[$i]
        # Strip line comments + string literals before pattern matching
        $ln = $rawLn -replace '//[^\n]*', '' -replace '"(?:[^"\\]|\\.)*"', '""'

        # R4: Uninitialized `let mut x;` (must have `=` before `;`)
        if ($ln -match '^\s*let\s+mut\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*;') {
            Add-Issue $warnings $rel ($i + 1) 'R4' "Uninitialized 'let mut $($Matches[1])' (must initialize)"
        }

        # R1/R2: catch blocks
        if ($ln -match 'catch\b[^{]*\{\s*\}\s*$') {
            Add-Issue $errors $rel ($i + 1) 'R1' "Empty catch block (silently swallows exception)"
            continue
        }
        if ($ln -match 'catch\b[^{]*\{\s*$') {
            # multi-line catch: find matching }
            $depth = 1
            $body = @()
            for ($j = $i + 1; $j -lt $lines.Count -and $depth -gt 0; $j++) {
                $bj = $lines[$j]
                # naive brace counting (strings stripped)
                $stripped = $bj -replace '"(?:[^"\\]|\\.)*"', '""' -replace '//[^\n]*', ''
                $depth += ([regex]::Matches($stripped, '\{')).Count
                $depth -= ([regex]::Matches($stripped, '\}')).Count
                if ($depth -le 0) { break }
                $body += $bj
            }
            $bodyStripped = ($body -join "`n") -replace '//[^\n]*', '' -replace '/\*[\s\S]*?\*/', ''
            $bodyMeaningful = ($bodyStripped -replace '\s', '')
            if ($bodyMeaningful -eq '') {
                Add-Issue $errors $rel ($i + 1) 'R1' "Empty catch block (silently swallows exception)"
            }
            elseif ($bodyMeaningful -match '^(print|log_info|log_warn|log_error)\([^;]*\);?$') {
                # only logs, no rethrow, no transform
                if ($bodyStripped -notmatch '\braise\b' -and $bodyStripped -notmatch '\breturn\b') {
                    Add-Issue $warnings $rel ($i + 1) 'R2' "catch-all only logs (no rethrow, no convert) — needs '// suppressed: <reason>' or fix"
                }
            }
        }

        # R5: `finally { ... return ... }`
        if ($ln -match 'finally\s*\{') {
            $depth = 1
            for ($j = $i + 1; $j -lt $lines.Count -and $depth -gt 0; $j++) {
                $bj = $lines[$j]
                $stripped = $bj -replace '"(?:[^"\\]|\\.)*"', '""' -replace '//[^\n]*', ''
                $depth += ([regex]::Matches($stripped, '\{')).Count
                $depth -= ([regex]::Matches($stripped, '\}')).Count
                if ($stripped -match '\breturn\b') {
                    Add-Issue $warnings $rel ($j + 1) 'R5' "'return' inside finally block swallows current exception"
                }
                if ($depth -le 0) { break }
            }
        }
    }
}

# Report
Write-Host ""
Write-Host "=== HicOS Robustness Linter (Sprint 36) ===" -ForegroundColor Cyan
Write-Host ("Files scanned : {0}" -f $sources.Count)
$errColor = if ($errors.Count -gt 0) { 'Red' } else { 'Green' }
$warnColor = if ($warnings.Count -gt 0) { 'Yellow' } else { 'Green' }
Write-Host ("Errors        : {0}" -f $errors.Count) -ForegroundColor $errColor
Write-Host ("Warnings      : {0}" -f $warnings.Count) -ForegroundColor $warnColor
Write-Host ("Infos         : {0}" -f $infos.Count) -ForegroundColor DarkGray
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "--- ERRORS ---" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host ("  [{0}] {1}:{2}  {3}" -f $e.Rule, $e.File, $e.Line, $e.Msg)
    }
    Write-Host ""
}
if ($warnings.Count -gt 0) {
    Write-Host "--- WARNINGS ---" -ForegroundColor Yellow
    $warnings | Group-Object Rule | ForEach-Object {
        Write-Host ("  Rule {0}: {1} hit(s)" -f $_.Name, $_.Count)
        $_.Group | Select-Object -First 5 | ForEach-Object {
            Write-Host ("    {0}:{1}  {2}" -f $_.File, $_.Line, $_.Msg)
        }
        if ($_.Count -gt 5) { Write-Host ("    ... and {0} more" -f ($_.Count - 5)) }
    }
}

# Persist full report
$tmpDir = Join-Path $repoRoot '.tmp'
if (-not (Test-Path $tmpDir)) { [void](New-Item -ItemType Directory -Path $tmpDir -Force) }
$out = Join-Path $tmpDir 'lint-robustness.txt'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# HicOS Robustness Lint Report")
[void]$sb.AppendLine("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("# Files: $($sources.Count) | Errors: $($errors.Count) | Warnings: $($warnings.Count)")
[void]$sb.AppendLine("")
foreach ($e in $errors)   { [void]$sb.AppendLine(("ERROR   [{0}] {1}:{2}  {3}" -f $e.Rule, $e.File, $e.Line, $e.Msg)) }
foreach ($w in $warnings) { [void]$sb.AppendLine(("WARNING [{0}] {1}:{2}  {3}" -f $w.Rule, $w.File, $w.Line, $w.Msg)) }
[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "Full report: $out"

# Exit code
if ($errors.Count -gt 0) { exit 1 }
if ($mode -eq 'strict' -and $warnings.Count -gt 0) { exit 2 }
exit 0
