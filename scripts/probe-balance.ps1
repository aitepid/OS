# probe-balance.ps1 — 定位 a11y.hl 等文件 tokenizer 看到的括号失衡位置
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$files = @('a11y.hl','app_texteditor.hl','consistent_hash.hl','display_topology.hl','ime.hl','neural.hl','shell_dock.hl','shell_form.hl','shell_wallpaper.hl','vdesktop.hl','visual_audit.hl')

foreach ($f in $files) {
    $p = Join-Path $repoRoot "bare-kernel\hl\$f"
    if (-not (Test-Path $p)) { continue }
    $src = Get-Content $p -Raw -Encoding UTF8
    $depth_b = 0; $depth_p = 0; $depth_s = 0
    $line = 1; $col = 1
    $i = 0; $len = $src.Length
    $events = @()
    while ($i -lt $len) {
        $ch = $src[$i]
        if ($ch -eq "`n") { $line++; $col = 1; $i++; continue }
        # line comment
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '/') {
            while ($i -lt $len -and $src[$i] -ne "`n") { $i++; $col++ }
            continue
        }
        # block comment
        if ($ch -eq '/' -and ($i+1) -lt $len -and $src[$i+1] -eq '*') {
            $i += 2; $col += 2
            while ($i -lt ($len - 1)) {
                if ($src[$i] -eq "`n") { $line++; $col = 1; $i++; continue }
                if ($src[$i] -eq '*' -and $src[$i+1] -eq '/') { $i += 2; $col += 2; break }
                $i++; $col++
            }
            continue
        }
        # string
        if ($ch -eq '"' -or $ch -eq "'") {
            $q = $ch; $i++; $col++
            while ($i -lt $len -and $src[$i] -ne $q) {
                if ($src[$i] -eq "`n") { $line++; $col = 1; $i++; continue }
                if ($src[$i] -eq '\' -and ($i+1) -lt $len) { $i += 2; $col += 2 } else { $i++; $col++ }
            }
            if ($i -lt $len) { $i++; $col++ }
            continue
        }
        if ($ch -eq '{') { $depth_b++ }
        elseif ($ch -eq '}') { $depth_b--; if ($depth_b -lt 0) { $events += "  L${line}:${col}  '}' depth went $depth_b"; $depth_b = 0 } }
        elseif ($ch -eq '(') { $depth_p++ }
        elseif ($ch -eq ')') { $depth_p--; if ($depth_p -lt 0) { $events += "  L${line}:${col}  ')' depth went $depth_p"; $depth_p = 0 } }
        elseif ($ch -eq '[') { $depth_s++ }
        elseif ($ch -eq ']') { $depth_s--; if ($depth_s -lt 0) { $events += "  L${line}:${col}  ']' depth went $depth_s"; $depth_s = 0 } }
        $i++; $col++
    }
    Write-Host ("=== {0}  end depth: ()={1} {{}}={2} []={3} ===" -f $f,$depth_p,$depth_b,$depth_s) -ForegroundColor Cyan
    foreach ($e in $events) { Write-Host $e }
    if ($depth_b -gt 0 -or $depth_p -gt 0 -or $depth_s -gt 0) {
        Write-Host "  >> end-of-file unclosed: { x$depth_b ( x$depth_p [ x$depth_s" -ForegroundColor DarkYellow
    }
}
