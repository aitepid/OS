param(
    [string]$PatentTxt,
    [string]$OutputDir,
    [string]$OutputName,
    [int]$StartLine,
    [int]$EndLine
)

$ErrorActionPreference = 'Stop'
$allLines = Get-Content $PatentTxt
$contentLines = $allLines[($StartLine - 1)..($EndLine - 1)] | Where-Object { $_ -notmatch '^={5,}$' }

$outputPath = Join-Path (Resolve-Path $OutputDir) $OutputName
Write-Host "Creating $outputPath ..." -ForegroundColor Cyan

$word = New-Object -ComObject Word.Application
$word.Visible = $false

try {
    $doc = $word.Documents.Add()
    $sec = $doc.Sections.Item(1)
    $ps = $sec.PageSetup
    $ps.TopMargin    = $word.CentimetersToPoints(2.5)
    $ps.LeftMargin   = $word.CentimetersToPoints(2.5)
    $ps.RightMargin  = $word.CentimetersToPoints(1.5)
    $ps.BottomMargin = $word.CentimetersToPoints(1.0)
    $ps.PageWidth    = $word.CentimetersToPoints(21.59)
    $ps.PageHeight   = $word.CentimetersToPoints(27.94)
    $ps.LineNumbering.Active = $true
    $ps.LineNumbering.CountBy = 1
    $ps.LineNumbering.RestartMode = 0

    try { $sec.Footers.Item(1).PageNumbers.Add(4) | Out-Null } catch { }

    $range = $doc.Content
    $range.Text = ($contentLines -join "`r`n")
    $range.Font.Name = "Times New Roman"
    $range.Font.Size = 12
    $range.Font.Color = 0
    $range.ParagraphFormat.LineSpacingRule = 2
    $range.ParagraphFormat.SpaceAfter = 0
    $range.ParagraphFormat.SpaceBefore = 0

    $doc.SaveAs([ref]$outputPath, [ref]16)
    $doc.Close()
    Write-Host "  OK" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    try { $doc.Close($false) } catch {}
}
finally {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
