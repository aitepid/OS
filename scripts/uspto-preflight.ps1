param(
    [switch]$Verbose
)

# USPTO Patent Center 提交前预检脚本
# 检查 IP-Protection 目录中的文档完整性和格式就绪状态
# 用法: powershell -File scripts\uspto-preflight.ps1 [-Verbose]

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$ipDir = 'IP-Protection'
$errors = @()
$warnings = @()
$passed = @()

function Check-Pass($msg)  { $script:passed   += $msg; if ($Verbose) { Write-Host "  PASS: $msg" -ForegroundColor Green } }
function Check-Warn($msg)  { $script:warnings += $msg; Write-Host "  WARN: $msg" -ForegroundColor Yellow }
function Check-Fail($msg)  { $script:errors   += $msg; Write-Host "  FAIL: $msg" -ForegroundColor Red }

Write-Host ''
Write-Host '=====================================================================' -ForegroundColor Cyan
Write-Host '  USPTO Patent Center -- Pre-Submission Preflight Check' -ForegroundColor Cyan
Write-Host '  Applicant: CHEN SONG' -ForegroundColor Cyan
Write-Host '=====================================================================' -ForegroundColor Cyan
Write-Host ''

# =====================================================================
# 1. 源文件完整性检查
# =====================================================================
Write-Host '[1/8] Source file inventory' -ForegroundColor White

$requiredTxtFiles = @(
    'USPTO_PATENT_01_HILBERT_CURVE_OS.txt',
    'USPTO_PATENT_02_SELF_BOOTSTRAP_TOOLCHAIN.txt',
    'USPTO_APPLICATION_DATA_SHEET.txt',
    'USPTO_DECLARATION.txt',
    'USPTO_MICRO_ENTITY_CERT.txt',
    'USPTO_IDS.txt',
    'USPTO_DRAWING_SPECS.txt',
    'USPTO_FEE_TRANSMITTAL.txt',
    'USPTO_FILING_CHECKLIST.txt',
    'USPTO_FILING_CONVERSION_GUIDE.txt'
)

foreach ($f in $requiredTxtFiles) {
    $path = Join-Path $ipDir $f
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        if ($size -lt 100) {
            Check-Warn "$f exists but suspiciously small ($size bytes)"
        } else {
            Check-Pass "$f ($size bytes)"
        }
    } else {
        Check-Fail "Missing: $f"
    }
}

# =====================================================================
# 2. 申请人信息填写检查
# =====================================================================
Write-Host ''
Write-Host '[2/8] Applicant info populated' -ForegroundColor White

$adsContent = Get-Content (Join-Path $ipDir 'USPTO_APPLICATION_DATA_SHEET.txt') -Raw

$requiredFields = @(
    @('Given name:\s+SONG',           'ADS: Given name'),
    @('Family name:\s+CHEN',          'ADS: Family name'),
    @('Citizenship:\s+CN',            'ADS: Citizenship'),
    @('Email:\s+luckysong519',        'ADS: Email'),
    @('\+86\s*14700000519',           'ADS: Phone'),
    @('Postal code:\s+350300',        'ADS: Postal code'),
    @('Fuqing City',                  'ADS: City'),
    @('Fujian Province',              'ADS: Province'),
    @('\[X\]\s*Individual',           'ADS: Applicant type = Individual'),
    @('\[X\]\s*Applicant acts',       'ADS: Pro se declaration')
)

foreach ($check in $requiredFields) {
    if ($adsContent -match $check[0]) {
        Check-Pass $check[1]
    } else {
        Check-Fail "$($check[1]) -- not found or incorrect"
    }
}

# Declaration
$declContent = Get-Content (Join-Path $ipDir 'USPTO_DECLARATION.txt') -Raw
$declFields = @(
    @('Given name:\s+SONG',  'Declaration: Given name'),
    @('Family name:\s+CHEN', 'Declaration: Family name'),
    @('Citizenship:\s+CN',   'Declaration: Citizenship'),
    @('Postal code:\s+350300','Declaration: Postal code')
)
foreach ($check in $declFields) {
    if ($declContent -match $check[0]) {
        Check-Pass $check[1]
    } else {
        Check-Fail "$($check[1]) -- not found"
    }
}

# Patent specs
foreach ($patFile in @('USPTO_PATENT_01_HILBERT_CURVE_OS.txt','USPTO_PATENT_02_SELF_BOOTSTRAP_TOOLCHAIN.txt')) {
    $patContent = Get-Content (Join-Path $ipDir $patFile) -Raw
    $label = if ($patFile -match '01') { 'Patent #1' } else { 'Patent #2' }
    if ($patContent -match 'Name:\s*CHEN SONG') {
        Check-Pass "$label : Inventor name"
    } else {
        Check-Fail "$label : Inventor name not filled"
    }
    if ($patContent -match 'Citizenship:\s*CN') {
        Check-Pass "$label : Citizenship"
    } else {
        Check-Fail "$label : Citizenship not filled"
    }
}

# IDS + Micro Entity
$idsContent = Get-Content (Join-Path $ipDir 'USPTO_IDS.txt') -Raw
if ($idsContent -match 'Name:\s+CHEN SONG') { Check-Pass 'IDS: Name' } else { Check-Fail 'IDS: Name not filled' }

$meContent = Get-Content (Join-Path $ipDir 'USPTO_MICRO_ENTITY_CERT.txt') -Raw
if ($meContent -match 'Printed Name:\s+CHEN SONG') { Check-Pass 'Micro Entity: Printed Name' } else { Check-Fail 'Micro Entity: Printed Name not filled' }

# =====================================================================
# 3. 残留占位符检查
# =====================================================================
Write-Host ''
Write-Host '[3/8] Remaining placeholders' -ForegroundColor White

$placeholderPattern = '\[TO BE COMPLETED\]'
$allTxtFiles = Get-ChildItem $ipDir -File -Filter '*.txt'
$placeholderCount = 0

foreach ($f in $allTxtFiles) {
    $hits = Select-String -Path $f.FullName -Pattern $placeholderPattern
    if ($hits) {
        $placeholderCount += $hits.Count
        Check-Fail "$($f.Name): $($hits.Count) x [TO BE COMPLETED] remaining"
        if ($Verbose) {
            $hits | ForEach-Object { Write-Host "    L$($_.LineNumber): $($_.Line.Trim())" -ForegroundColor DarkYellow }
        }
    }
}
if ($placeholderCount -eq 0) {
    Check-Pass 'No [TO BE COMPLETED] placeholders remaining'
}

# =====================================================================
# 4. DOCX 输出文件检查 (转换后的文件)
# =====================================================================
Write-Host ''
Write-Host '[4/8] Converted DOCX files' -ForegroundColor White

$expectedDocx = @(
    'Patent01_Specification.docx',
    'Patent01_Claims.docx',
    'Patent01_Abstract.docx',
    'Patent02_Specification.docx',
    'Patent02_Claims.docx',
    'Patent02_Abstract.docx'
)

$docxFound = 0
foreach ($d in $expectedDocx) {
    $path = Join-Path $ipDir $d
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Check-Pass "$d ($size bytes)"
        $docxFound++
    } else {
        Check-Warn "$d not yet created (manual conversion needed)"
    }
}

if ($docxFound -eq 0) {
    Check-Warn 'No DOCX files found -- TXT to DOCX conversion not yet done'
    Write-Host '    Action: Open Word, set double-spacing + line numbers,' -ForegroundColor DarkYellow
    Write-Host '            copy spec content, save as DOCX' -ForegroundColor DarkYellow
}

# =====================================================================
# 5. 附图 PDF 检查
# =====================================================================
Write-Host ''
Write-Host '[5/8] Drawing PDFs' -ForegroundColor White

$expectedDrawings = @(
    'Patent01_Drawings.pdf',
    'Patent02_Drawings.pdf'
)

foreach ($d in $expectedDrawings) {
    $path = Join-Path $ipDir $d
    if (Test-Path $path) {
        Check-Pass "$d exists"
    } else {
        Check-Warn "$d not yet created (manual drawing needed)"
        Write-Host '    Action: Use Draw.io/Visio to create drawings' -ForegroundColor DarkYellow
        Write-Host '            per USPTO_DRAWING_SPECS.txt, export as PDF' -ForegroundColor DarkYellow
    }
}

# Figure count verification from DRAWING_SPECS
$drawSpecContent = Get-Content (Join-Path $ipDir 'USPTO_DRAWING_SPECS.txt') -Raw
$fig1Count = ([regex]::Matches($drawSpecContent, 'APPLICATION #1.*?APPLICATION #2' , 'Singleline') |
    ForEach-Object { ([regex]::Matches($_.Value, 'FIG\.\s+\d+')).Count })
$fig2Count = ([regex]::Matches($drawSpecContent, 'APPLICATION #2.*$', 'Singleline') |
    ForEach-Object { ([regex]::Matches($_.Value, 'FIG\.\s+\d+')).Count })

if ($fig1Count -gt 0) { Check-Pass "Patent #1 drawing specs: $fig1Count figures described" }
if ($fig2Count -gt 0) { Check-Pass "Patent #2 drawing specs: $fig2Count figures described" }

# =====================================================================
# 6. 签名表格 PDF 检查
# =====================================================================
Write-Host ''
Write-Host '[6/8] Signed form PDFs' -ForegroundColor White

$expectedSignedForms = @(
    @('Declaration_Patent01_signed.pdf',      'Declaration #1 (PTO/AIA/01)'),
    @('Declaration_Patent02_signed.pdf',      'Declaration #2 (PTO/AIA/01)'),
    @('MicroEntity_Patent01_signed.pdf',      'Micro Entity Cert #1 (PTO/SB/15A)'),
    @('MicroEntity_Patent02_signed.pdf',      'Micro Entity Cert #2 (PTO/SB/15A)'),
    @('IDS_Patent01_signed.pdf',              'IDS #1 (PTO/SB/08b)'),
    @('IDS_Patent02_signed.pdf',              'IDS #2 (PTO/SB/08b)')
)

foreach ($form in $expectedSignedForms) {
    $path = Join-Path $ipDir $form[0]
    if (Test-Path $path) {
        Check-Pass "$($form[1]) -- signed PDF found"
    } else {
        Check-Warn "$($form[1]) -- not yet signed ($($form[0]))"
    }
}

# Also check for any PDF with "signed" in name
$signedPdfs = Get-ChildItem $ipDir -File -Filter '*signed*.pdf' -ErrorAction SilentlyContinue
if ($signedPdfs) {
    Write-Host "    Found signed PDFs:" -ForegroundColor DarkCyan
    $signedPdfs | ForEach-Object { Write-Host "      - $($_.Name) ($($_.Length) bytes)" -ForegroundColor DarkCyan }
}

# =====================================================================
# 7. 独立申请套件完整性
# =====================================================================
Write-Host ''
Write-Host '[7/8] Independent application bundles' -ForegroundColor White

Write-Host '  --- Patent #1 (Hilbert Curve OS Architecture) ---' -ForegroundColor DarkCyan
$p1checks = @(
    @('Patent01_Specification.docx',          'Specification DOCX'),
    @('Patent01_Claims.docx',                 'Claims DOCX'),
    @('Patent01_Abstract.docx',               'Abstract DOCX'),
    @('Patent01_Drawings.pdf',                'Drawings PDF (10 figs)'),
    @('Declaration_Patent01_signed.pdf',      'Declaration signed'),
    @('MicroEntity_Patent01_signed.pdf',      'Micro Entity signed'),
    @('IDS_Patent01_signed.pdf',              'IDS signed + NPL')
)
$p1ready = 0
foreach ($c in $p1checks) {
    if (Test-Path (Join-Path $ipDir $c[0])) { $p1ready++; Check-Pass "P1: $($c[1])" }
    else { Check-Warn "P1: $($c[1]) -- MISSING" }
}

Write-Host "  --- Patent #2 (Self-Bootstrap Toolchain) ---" -ForegroundColor DarkCyan
$p2checks = @(
    @('Patent02_Specification.docx',          'Specification DOCX'),
    @('Patent02_Claims.docx',                 'Claims DOCX'),
    @('Patent02_Abstract.docx',               'Abstract DOCX'),
    @('Patent02_Drawings.pdf',                'Drawings PDF (12 figs)'),
    @('Declaration_Patent02_signed.pdf',      'Declaration signed'),
    @('MicroEntity_Patent02_signed.pdf',      'Micro Entity signed'),
    @('IDS_Patent02_signed.pdf',              'IDS signed + NPL')
)
$p2ready = 0
foreach ($c in $p2checks) {
    if (Test-Path (Join-Path $ipDir $c[0])) { $p2ready++; Check-Pass "P2: $($c[1])" }
    else { Check-Warn "P2: $($c[1]) -- MISSING" }
}

# =====================================================================
# 8. 终极自测项
# =====================================================================
Write-Host ''
Write-Host '[8/8] Final self-test reminders' -ForegroundColor White

$selfTests = @(
    'Two independent DOCX bundles prepared (one per invention)',
    'No hidden revisions / colored text / macros in DOCX files',
    'Every page has page number, every line has line number',
    'FIG. numbers in Drawings PDF match Brief Description of Drawings in Specification',
    'Micro Entity: PTO/SB/15A "Gross Income Basis" checkbox is checked',
    'All electronic signatures use slash format: /CHEN SONG/',
    'Cross-reference: Patent #2 spec references Patent #1 application number (fill after #1 filed)',
    'Abstract is 150 words or fewer',
    'Claims begin on a new page in Claims.docx',
    'Fee ready: $432.00 per application, $864.00 total (Micro Entity)',
    'Patent Center account created at https://patentcenter.uspto.gov',
    'ABSOLUTE DEADLINE: File before 2027-03-19 (12-month grace period)'
)

foreach ($t in $selfTests) {
    Write-Host "  [ ] $t" -ForegroundColor DarkYellow
}

# =====================================================================
# Summary
# =====================================================================
Write-Host ''
Write-Host '=====================================================================' -ForegroundColor Cyan
Write-Host '  PREFLIGHT SUMMARY' -ForegroundColor Cyan
Write-Host '=====================================================================' -ForegroundColor Cyan
Write-Host "  Passed:   $($passed.Count)" -ForegroundColor Green
Write-Host "  Warnings: $($warnings.Count)" -ForegroundColor Yellow
Write-Host "  Failures: $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host ''
Write-Host "  Patent #1 bundle: $p1ready / $($p1checks.Count) files ready" -ForegroundColor $(if ($p1ready -eq $p1checks.Count) { 'Green' } else { 'Yellow' })
Write-Host "  Patent #2 bundle: $p2ready / $($p2checks.Count) files ready" -ForegroundColor $(if ($p2ready -eq $p2checks.Count) { 'Green' } else { 'Yellow' })
Write-Host ''

if ($errors.Count -gt 0) {
    Write-Host '  STATUS: NOT READY TO FILE' -ForegroundColor Red
    Write-Host "  Fix $($errors.Count) failure(s) before proceeding." -ForegroundColor Red
    exit 1
} elseif ($warnings.Count -gt 0) {
    Write-Host '  STATUS: SOURCE TEXT READY -- manual conversion pending' -ForegroundColor Yellow
    Write-Host '  Complete DOCX/PDF conversion and sign forms to proceed.' -ForegroundColor Yellow
    exit 0
} else {
    Write-Host '  STATUS: READY TO FILE' -ForegroundColor Green
    Write-Host '  Go to https://patentcenter.uspto.gov and submit.' -ForegroundColor Green
    exit 0
}
