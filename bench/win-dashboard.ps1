#Requires -Version 5.1
# ============================================================================
#  bench/win-dashboard.ps1 — داشبورد زنده‌ی مغز در مرورگر (ویندوز)
#
#  • مغز را با سرور وب اجرا می‌کند؛ مرورگر خودکار روی http://localhost:8420
#    باز می‌شود و مغز را زنده می‌بینید
#  • برخلاف ران بلند (آزمایش معین ۹ قطعه‌ای) این تا وقتی خودتان نبندید
#    اجرا می‌شود
#  • دکمه‌ی «ذخیره» در داشبورد = نوشتن brain.dat + توقف موقت مغز
#  • سقف CPU (پیش‌فرض ۵۰٪) + اولویت پایین + جلوگیری از خواب لپ‌تاپ
#
#  استفاده از ریشه‌ی ریپو:
#     powershell -NoProfile -ExecutionPolicy Bypass -File bench\win-dashboard.ps1
#     ... -Seed 2                    (بذر دیگر)
#     ... -Load                      (ادامه از brain.dat قبلی)
#     ... -CpuCap 0.25 -KeepDisplayOn
#
#  خروج تمیز: اول در داشبورد «ذخیره» بزنید، بعد در پاورشل Ctrl+C.
#  (Ctrl+C بدون ذخیره‌ی قبلی، مغز را بدون brain.dat می‌بندد)
# ============================================================================
param(
    [int]$Seed = 1,
    [int]$Neurons = 1000,
    [int]$Port = 8420,
    [int]$Strength = 60,
    [int]$Holdout = 10,
    [int]$Talk = 400,
    [string]$ExtraFlags = '--teach-feed 3 --silence --mutate --sprout 5',
    [double]$CpuCap = 0.5,
    [switch]$KeepDisplayOn,
    [switch]$NormalPriority,
    [switch]$Load
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$bin = Join-Path $root 'bench\smile-bench.exe'
if (-not (Test-Path $bin)) { throw 'bench\smile-bench.exe not found - re-download the repo zip' }
foreach ($f in @('persian_words.tsv', 'my_words.tsv')) {
    if (-not (Test-Path (Join-Path $root $f))) { throw "missing repo file: $f" }
}

# ----------------------------------------------------------------------------
# سقف CPU — بخشی از هسته‌های منطقی + اولویت پایین‌تر
# ----------------------------------------------------------------------------
$logical = [Environment]::ProcessorCount
$n = [int][Math]::Max(1, [Math]::Floor($logical * $CpuCap + 0.5))
if ($n -gt 62) { $n = 62 }
$mask = [int64]([Math]::Pow(2, $n) - 1)
$pr = 'BelowNormal'
if ($NormalPriority) { $pr = 'Normal' }
$affinityOK = -not ([IntPtr]::Size -eq 4 -and $n -gt 31)
Write-Host ('[cpu] cap {0:P0}: {1} of {2} logical cores, process priority {3}' -f $CpuCap, $n, $logical, $pr)

# ----------------------------------------------------------------------------
# جلوگیری از خواب لپ‌تاپ تا وقتی مغز روشن است (خودکار برمی‌گردد)
# ----------------------------------------------------------------------------
if (-not ('SmileWin.Power' -as [type])) {
    Add-Type -Namespace SmileWin -Name Power -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
}
$ES_CONTINUOUS       = [uint32]2147483648
$ES_SYSTEM_REQUIRED  = [uint32]1
$ES_DISPLAY_REQUIRED = [uint32]2
$es = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
if ($KeepDisplayOn) { $es = $es -bor $ES_DISPLAY_REQUIRED }
[void][SmileWin.Power]::SetThreadExecutionState($es)
Write-Host '[power] sleep prevention ON'

function QuoteArg([string]$s) {
    if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
    return $s
}

$a = @(
    '--neurons', $Neurons,
    '--seed', $Seed,
    '--port', $Port,
    '--teacher-strength', $Strength,
    '--holdout', $Holdout,
    '--talk', $Talk,
    '--words', (Join-Path $root 'persian_words.tsv'),
    '--user-words', (Join-Path $root 'my_words.tsv')
)
$a += @($ExtraFlags -split '\s+' | Where-Object { $_ })
if ($Load) {
    if (Test-Path (Join-Path $root 'brain.dat')) {
        $a += @('--load', (Join-Path $root 'brain.dat'))
        Write-Host '[load] continuing from brain.dat'
    } else {
        Write-Warning 'no brain.dat found - starting fresh'
    }
}

Write-Host ('[run] dashboard: http://localhost:{0}  (Ctrl+C here to quit)' -f $Port)
$p = Start-Process -FilePath $bin -ArgumentList (($a | ForEach-Object { QuoteArg $_ }) -join ' ') -WorkingDirectory $root -NoNewWindow -PassThru
try {
    try { if ($affinityOK) { $p.ProcessorAffinity = [IntPtr]$mask } } catch { }
    try { $p.PriorityClass = $pr } catch { }
    $p.WaitForExit()
}
finally {
    [void][SmileWin.Power]::SetThreadExecutionState($ES_CONTINUOUS)
}
Write-Host 'stopped.'
