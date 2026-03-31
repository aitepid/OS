param(
    [Parameter(Mandatory)][string]$PatentTxt,
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][string]$OutputName,
    [Parameter(Mandatory)][int]$StartLine,
    [Parameter(Mandatory)][int]$EndLine
)

# USPTO DOCX Generator v3
# Fixes: per-paragraph formatting to avoid mixed-format 9999999 issue
# Format: Times New Roman 12pt, double spacing, line numbers, USPTO margins

$ErrorActionPreference = 'Stop'

$allLines = Get-Content $PatentTxt -Encoding UTF8
$contentLines = $allLines[($StartLine - 1)..($EndLine - 1)] | Where-Object { $_ -notmatch '^={5,}$' }

$outputPath = Join-Path (Resolve-Path $OutputDir).Path $OutputName
Write-Host "Creating $outputPath ..." -ForegroundColor Cyan

# Kill any stale Word
Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0

    $doc = $word.Documents.Add()

    # ---- Page Setup (37 C.F.R. 1.52) ----
    $sec = $doc.Sections.Item(1)
    $ps = $sec.PageSetup

    # Margins in points (1 cm = 28.35 pt)
    $ps.TopMargin    = 71    # 2.5 cm
    $ps.LeftMargin   = 71    # 2.5 cm
    $ps.RightMargin  = 43    # 1.5 cm
    $ps.BottomMargin = 28    # 1.0 cm

    # Line numbering (continuous)
    $ps.LineNumbering.Active     = $true
    $ps.LineNumbering.CountBy    = 1
    $ps.LineNumbering.RestartMode = 0  # wdRestartContinuous

    # ---- Set default style for Normal ----
    $normalStyle = $doc.Styles.Item(-1)  # wdStyleNormal
    $normalStyle.Font.Name = "Times New Roman"
    $normalStyle.Font.Size = 12
    $normalStyle.Font.Bold = $false
    $normalStyle.Font.Italic = $false
    $normalStyle.Font.ColorIndex = 1  # wdBlack
    $normalStyle.ParagraphFormat.LineSpacingRule = 2  # wdLineSpaceDouble
    $normalStyle.ParagraphFormat.SpaceAfter  = 0
    $normalStyle.ParagraphFormat.SpaceBefore = 0
    $normalStyle.ParagraphFormat.Alignment   = 0  # wdAlignParagraphLeft

    # ---- Insert content paragraph by paragraph ----
    $range = $doc.Content

    for ($i = 0; $i -lt $contentLines.Count; $i++) {
        $line = $contentLines[$i]

        if ($i -eq 0) {
            $range.Text = $line
        } else {
            # Move to end, insert paragraph break, then text
            $range = $doc.Content
            $range.Collapse(0)  # wdCollapseEnd
            $range.InsertParagraphAfter()
            $range = $doc.Content
            $range.Collapse(0)
            $range.InsertAfter($line)
        }
    }

    # ---- Force format on entire content ----
    $all = $doc.Content
    $all.Style = -1  # wdStyleNormal
    $all.Font.Name = "Times New Roman"
    $all.Font.Size = 12
    $all.Font.ColorIndex = 1

    # ---- Page numbers (bottom center) ----
    # Page numbers - use PageNumbers collection (simpler, avoids Fields.Add issues)
    try {
        $sec.Footers.Item(1).PageNumbers.Add(1) | Out-Null  # 1 = wdAlignPageNumberCenter
    } catch {
        Write-Host "  Note: Could not add page numbers automatically" -ForegroundColor DarkYellow
    }

    # ---- Save ----
    $missing = [System.Reflection.Missing]::Value
    $doc.SaveAs2($outputPath, 16, $missing, $missing, $false)
    Write-Host "  OK: $outputPath" -ForegroundColor Green

    # Verify
    $pgCount = $doc.ComputeStatistics(2)  # wdStatisticPages
    $wdCount = $doc.ComputeStatistics(0)  # wdStatisticWords
    Write-Host "  Pages: $pgCount  Words: $wdCount" -ForegroundColor DarkCyan
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
}
finally {
    if ($doc) { try { $doc.Close($false) } catch { } }
    if ($word) { try { $word.Quit() } catch { } }
    Start-Sleep -Seconds 1
    if ($doc)  { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)  | Out-Null } catch { } }
    if ($word) { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch { } }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
