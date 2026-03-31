param(
    [string]$PatentTxt,
    [string]$OutputDir,
    [string]$Prefix,
    [int]$SpecStartLine,
    [int]$SpecEndLine,
    [int]$ClaimsStartLine,
    [int]$ClaimsEndLine,
    [int]$AbstractStartLine,
    [int]$AbstractEndLine
)

# USPTO DOCX Generator -- creates Specification, Claims, Abstract DOCX files
# with double spacing, line numbers, correct margins per 37 C.F.R. 1.52

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PatentTxt)) {
    Write-Error "Source file not found: $PatentTxt"
    exit 1
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$allLines = Get-Content $PatentTxt

function New-PatentDocx {
    param(
        [string]$OutputPath,
        [string[]]$ContentLines,
        [string]$DocTitle
    )

    Write-Host "Creating $OutputPath ..." -ForegroundColor Cyan

    $word = New-Object -ComObject Word.Application
    $word.Visible = $false

    try {
        $doc = $word.Documents.Add()

        # Page setup (37 C.F.R. 1.52)
        $sec = $doc.Sections.Item(1)
        $ps = $sec.PageSetup
        $ps.TopMargin    = $word.CentimetersToPoints(2.5)
        $ps.LeftMargin   = $word.CentimetersToPoints(2.5)
        $ps.RightMargin  = $word.CentimetersToPoints(1.5)
        $ps.BottomMargin = $word.CentimetersToPoints(1.0)
        $ps.PageWidth    = $word.CentimetersToPoints(21.59)  # Letter
        $ps.PageHeight   = $word.CentimetersToPoints(27.94)
        $ps.LineNumbering.Active = $true
        $ps.LineNumbering.CountBy = 1
        $ps.LineNumbering.RestartMode = 0  # wdRestartContinuous

        # Footer with page numbers
        $sec.Footers.Item(1).Range.InsertAfter("")
        $sec.Footers.Item(1).PageNumbers.Add(4)  # wdAlignPageNumberCenter=1, but 4 = centered

        # Content
        $range = $doc.Content
        $text = ($ContentLines -join "`r`n")
        $range.Text = $text

        # Font: Times New Roman 12pt
        $range.Font.Name = "Times New Roman"
        $range.Font.Size = 12
        $range.Font.Color = 0  # Black

        # Double spacing
        $range.ParagraphFormat.LineSpacingRule = 2  # wdLineSpaceDouble
        $range.ParagraphFormat.SpaceAfter = 0
        $range.ParagraphFormat.SpaceBefore = 0

        $doc.SaveAs([ref]$OutputPath, [ref]16)  # 16 = wdFormatDocumentDefault (.docx)
        $doc.Close()

        Write-Host "  OK: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        try { $doc.Close($false) } catch {}
    }
    finally {
        $word.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

# Extract sections (line numbers are 1-based, array is 0-based)
$specLines     = $allLines[($SpecStartLine - 1)..($SpecEndLine - 1)]
$claimsLines   = $allLines[($ClaimsStartLine - 1)..($ClaimsEndLine - 1)]
$abstractLines = $allLines[($AbstractStartLine - 1)..($AbstractEndLine - 1)]

# Strip the ====== separator lines from extracted content
$specLines     = $specLines | Where-Object { $_ -notmatch '^={5,}$' }
$claimsLines   = $claimsLines | Where-Object { $_ -notmatch '^={5,}$' }
$abstractLines = $abstractLines | Where-Object { $_ -notmatch '^={5,}$' }

# Generate DOCX files
$specPath     = Join-Path $OutputDir "${Prefix}_Specification.docx"
$claimsPath   = Join-Path $OutputDir "${Prefix}_Claims.docx"
$abstractPath = Join-Path $OutputDir "${Prefix}_Abstract.docx"

New-PatentDocx -OutputPath (Resolve-Path $OutputDir | Join-Path -ChildPath "${Prefix}_Specification.docx") -ContentLines $specLines -DocTitle "$Prefix Specification"

# Small delay to ensure COM cleanup
Start-Sleep -Seconds 2

New-PatentDocx -OutputPath (Join-Path (Resolve-Path $OutputDir) "${Prefix}_Claims.docx") -ContentLines $claimsLines -DocTitle "$Prefix Claims"

Start-Sleep -Seconds 2

New-PatentDocx -OutputPath (Join-Path (Resolve-Path $OutputDir) "${Prefix}_Abstract.docx") -ContentLines $abstractLines -DocTitle "$Prefix Abstract"

Write-Host ""
Write-Host "Done: 3 DOCX files generated for $Prefix" -ForegroundColor Green
