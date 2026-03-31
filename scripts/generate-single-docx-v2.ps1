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
$text = ($contentLines -join "`r`n")

$outputPath = Join-Path (Resolve-Path $OutputDir).Path $OutputName
Write-Host "Creating $outputPath ..." -ForegroundColor Cyan

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0  # wdAlertsNone

    $doc = $word.Documents.Add()

    # Page setup using points directly (1 cm = 28.35 pt)
    $sec = $doc.Sections.Item(1)
    $ps = $sec.PageSetup
    $ps.TopMargin    = 71   # 2.5cm
    $ps.LeftMargin   = 71   # 2.5cm
    $ps.RightMargin  = 43   # 1.5cm
    $ps.BottomMargin = 28   # 1.0cm

    # Line numbering
    $ps.LineNumbering.Active = $true
    $ps.LineNumbering.CountBy = 1
    $ps.LineNumbering.RestartMode = 0

    # Insert text
    $range = $doc.Content
    $range.Text = $text

    # Format
    $range.Font.Name = "Times New Roman"
    $range.Font.Size = 12
    $range.Font.ColorIndex = 1  # wdBlack
    $range.ParagraphFormat.LineSpacingRule = 2  # wdLineSpaceDouble
    $range.ParagraphFormat.SpaceAfter = 0
    $range.ParagraphFormat.SpaceBefore = 0

    # Save as DOCX
    [ref]$savePath = $outputPath
    [ref]$saveFormat = 16  # wdFormatDocumentDefault
    $doc.SaveAs($savePath, $saveFormat)
    Write-Host "  OK: $outputPath" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($doc) {
        try { $doc.Close($false) } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } catch { }
    }
    if ($word) {
        try { $word.Quit() } catch { }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) } catch { }
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
