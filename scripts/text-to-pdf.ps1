param(
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$OutputPdf,
    [string]$FontName = "Consolas",
    [int]$FontSize = 9,
    [switch]$Landscape,
    [switch]$SingleSpacing
)

# Converts a text file to a formatted PDF via Word COM
# Used for patent drawings (monospace) and form fills

$ErrorActionPreference = 'Stop'

Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$inputPath = (Resolve-Path $InputFile).Path
$outputPath = Join-Path (Split-Path $inputPath) (Split-Path $OutputPdf -Leaf)
if ([System.IO.Path]::IsPathRooted($OutputPdf)) { $outputPath = $OutputPdf }

Write-Host "Converting: $InputFile -> $outputPath" -ForegroundColor Cyan

$word = $null
$doc = $null
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $word.DisplayAlerts = 0

    $doc = $word.Documents.Add()

    # Page setup
    $sec = $doc.Sections.Item(1)
    $ps = $sec.PageSetup
    if ($Landscape) {
        $ps.Orientation = 1  # wdOrientLandscape
    }
    $ps.TopMargin    = 57   # 2.0 cm
    $ps.LeftMargin   = 57   # 2.0 cm
    $ps.RightMargin  = 43   # 1.5 cm
    $ps.BottomMargin = 28   # 1.0 cm

    # Set Normal style
    $normalStyle = $doc.Styles.Item(-1)
    $normalStyle.Font.Name = $FontName
    $normalStyle.Font.Size = $FontSize
    $normalStyle.Font.Bold = $false
    $normalStyle.Font.ColorIndex = 1
    if ($SingleSpacing) {
        $normalStyle.ParagraphFormat.LineSpacingRule = 0  # wdLineSpaceSingle
    } else {
        $normalStyle.ParagraphFormat.LineSpacingRule = 0
    }
    $normalStyle.ParagraphFormat.SpaceAfter = 0
    $normalStyle.ParagraphFormat.SpaceBefore = 0

    # Read and insert content
    $lines = Get-Content $inputPath -Encoding UTF8
    $text = ($lines -join "`r`n")
    $doc.Content.Text = $text
    $doc.Content.Style = -1
    $doc.Content.Font.Name = $FontName
    $doc.Content.Font.Size = $FontSize
    $doc.Content.Font.ColorIndex = 1

    # Page numbers bottom center
    try { $sec.Footers.Item(1).PageNumbers.Add(1) | Out-Null } catch { }

    # Save as PDF (17 = wdFormatPDF)
    $missing = [System.Reflection.Missing]::Value
    $doc.SaveAs2($outputPath.Replace('.pdf','.docx'), 16, $missing, $missing, $false)
    $doc.ExportAsFixedFormat($outputPath, 17, $false, 0, 0, 0, 0, 0, $false, $false, 0)

    $pdfSize = (Get-Item $outputPath).Length
    Write-Host "  OK: $outputPath ($([math]::Round($pdfSize/1024,1)) KB)" -ForegroundColor Green

    # Clean up temp docx
    $tempDocx = $outputPath.Replace('.pdf','.docx')
    $doc.Close($false)
    $doc = $null
    if (Test-Path $tempDocx) { Remove-Item $tempDocx -Force -ErrorAction SilentlyContinue }
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkRed
}
finally {
    if ($doc) { try { $doc.Close($false) } catch {} }
    if ($word) { try { $word.Quit() } catch {} }
    Start-Sleep -Seconds 1
    if ($doc)  { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)  | Out-Null } catch {} }
    if ($word) { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch {} }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
