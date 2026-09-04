#Requires -Version 5.1
# ============================================================================
#  bench/win-longrun.ps1 — اجرای بلند ویندوزی (معادل bench/longrun.sh)
#
#  چه می‌کند:
#    • اگر لازم باشد با g++ (MinGW-w64) بیلد می‌گیرد (استاتیک، بدون نیاز به DLL)
#    • مغز را در چند قطعه‌ی پشت‌سرهم اجرا می‌کند (ادامه از brain.dat)
#    • سقف CPU: فقط بخشی از هسته‌های منطقی + اولویت BelowNormal
#      → لپ‌تاپ روان می‌ماند
#    • تا پایان اجرا، خوابِ سیستم را غیرفعال می‌کند (SetThreadExecutionState)
#      و در پایان (یا با Ctrl+C) خودکار برمی‌گرداند
#    • خط RESULT هر قطعه را در longrun_win_seed<N>.txt می‌نویسد
#
#  استفاده (از ریشه‌ی ریپو):
#     powershell -ExecutionPolicy Bypass -File bench\win-longrun.ps1
#     powershell -ExecutionPolicy Bypass -File bench\win-longrun.ps1 -Seed 2
#     ... -Segs 3 -SegSecs 600        (ران کوتاه‌تر)
#     ... -CpuCap 0.25                (سقف ۲۵٪)
#     ... -KeepDisplayOn              (صفحه هم خاموش نشود)
#     ... -Rebuild                    (کامپایل دوباره از سورس)
#
#  پیش‌نیاز: هیچ — باینری از پیش ساخته‌شده داخل ریپو است (bench\smile-bench.exe،
#  استاتیک، فقط به DLLهای خود ویندوز وابسته است). فقط برای -Rebuild کامپایلر
#  لازم است؛ نصب (اگر msstore تایم‌اوت داد، --source winget را حتماً نگه دارید):
#     winget install --source winget -e --id BrechtSanders.WinLibs.POSIX.UCRT
# ============================================================================
param(
    [int]$Seed = 1,
    [int]$Segs = 9,
    [int]$SegSecs = 1200,
    [int]$Neurons = 1000,
    [int]$Strength = 60,
    [int]$Holdout = 10,
    [int]$Talk = 400,
    [string]$ExtraFlags = '--teach-feed 3 --silence --mutate --sprout 5',
    [double]$CpuCap = 0.5,
    [switch]$Rebuild,
    [switch]$KeepDisplayOn,
    [switch]$NormalPriority
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ----------------------------------------------------------------------------
#  ۰) کامپایلر — فقط برای -Rebuild لازم می‌شود (باینری از پیش‌ساخته داخل ریپو است)
# ----------------------------------------------------------------------------
function Find-Gxx {
    $c = Get-Command g++ -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $spots = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\g++.exe",
        'C:\msys64\mingw64\bin\g++.exe',
        'C:\mingw64\bin\g++.exe',
        "$env:LOCALAPPDATA\Programs\WinLibs\mingw64\bin\g++.exe"
    )
    foreach ($s in $spots) { if (Test-Path $s) { return $s } }
    return $null
}

$bin = Join-Path $root 'bench\smile-bench.exe'
if ((Test-Path $bin) -and (-not $Rebuild)) {
    Write-Host '[build] using prebuilt bench\smile-bench.exe (-Rebuild to recompile from source)'
} else {
    $gxx = Find-Gxx
    if (-not $gxx) {
        Write-Host 'bench\smile-bench.exe not found and no g++ available to build it.' -ForegroundColor Red
        Write-Host 'Re-download the repo zip (it ships a prebuilt exe), or install a compiler:'
        Write-Host '  winget install --source winget -e --id BrechtSanders.WinLibs.POSIX.UCRT'
        Write-Host '  winget install --source winget -e --id MSYS2.MSYS2'
        exit 1
    }
    Write-Host "[build] $gxx -O2 -std=c++17 -pthread -static smile.cpp"
    & $gxx -O2 -std=c++17 -pthread -static smile.cpp -o $bin -lws2_32
    if ($LASTEXITCODE -ne 0) { throw "build failed (exit code $LASTEXITCODE)" }
    Write-Host '[build] OK'
}

# ----------------------------------------------------------------------------
# ۱) سقف CPU — بخشی از هسته‌های منطقی + اولویت پایین‌تر
# ----------------------------------------------------------------------------
$logical = [Environment]::ProcessorCount
$n = [int][Math]::Max(1, [Math]::Floor($logical * $CpuCap + 0.5))
if ($n -gt 62) { $n = 62 }
$mask = [int64]([Math]::Pow(2, $n) - 1)
$pr = 'BelowNormal'
if ($NormalPriority) { $pr = 'Normal' }
# پاورشل ۳۲بیتی ماسکِ بالای ۳۱ بیت را نمی‌پذیرد
$affinityOK = -not ([IntPtr]::Size -eq 4 -and $n -gt 31)
Write-Host ('[cpu] cap {0:P0}: {1} of {2} logical cores, process priority {3}' -f $CpuCap, $n, $logical, $pr)

# ----------------------------------------------------------------------------
# ۲) جلوگیری از خواب لپ‌تاپ تا پایان اجرا (خودکار برمی‌گردد)
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
$dispNote = 'display may turn off; use -KeepDisplayOn to keep it on'
if ($KeepDisplayOn) { $dispNote = 'display kept on' }
Write-Host "[power] sleep prevention ON ($dispNote)"
try {
    Add-Type -AssemblyName System.Windows.Forms
    if ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -ne 'Online') {
        Write-Warning 'On battery: idle sleep is prevented, but closing the lid still sleeps. Keep the lid open.'
    }
} catch { }

# ----------------------------------------------------------------------------
# ۳) اجرای قطعه‌قطعه با ادامه از چک‌پوینت (معادل bench/longrun.sh)
# ----------------------------------------------------------------------------
foreach ($f in @('persian_words.tsv', 'my_words.tsv')) {
    if (-not (Test-Path (Join-Path $root $f))) { throw "missing repo file: $f" }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('smile-win-' + [IO.Path]::GetRandomFileName())
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$log = Join-Path $root ('longrun_win_seed{0}.txt' -f $Seed)
$hdr = 'seed={0} segs={1} x{2}s neurons={3} flags=[{4}] cpu={5}/{6} prio={7} started={8}' -f $Seed, $Segs, $SegSecs, $Neurons, $ExtraFlags, $n, $logical, $pr, (Get-Date -Format s)
$hdr | Out-File -FilePath $log -Encoding utf8
Write-Host "[log] $log"
Write-Host ''

$baseArgs = @(
    '--neurons', $Neurons,
    '--headless', $SegSecs,
    '--seed', $Seed,
    '--teacher-strength', $Strength,
    '--holdout', $Holdout,
    '--talk', $Talk,
    '--no-browser',
    '--words', (Join-Path $root 'persian_words.tsv'),
    '--user-words', (Join-Path $root 'my_words.tsv')
)
$baseArgs += @($ExtraFlags -split '\s+' | Where-Object { $_ })

function QuoteArg([string]$s) {
    if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
    return $s
}

$segLines = @()
$swTotal = [Diagnostics.Stopwatch]::StartNew()
try {
    for ($i = 0; $i -lt $Segs; $i++) {
        $a = $baseArgs
        if ($i -gt 0) { $a += @('--load', (Join-Path $tmp 'brain.dat')) }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $bin
        $psi.WorkingDirectory = $tmp
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $false   # تا Ctrl+C به فرایند مغز هم برسد
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $psi.Arguments = ($a | ForEach-Object { QuoteArg $_ }) -join ' '

        $sw = [Diagnostics.Stopwatch]::StartNew()
        Write-Host ('[seg {0}/{1}] {2}s virtual ... ' -f ($i + 1), $Segs, $SegSecs) -NoNewline
        $proc = [System.Diagnostics.Process]::Start($psi)
        try {
            if ($affinityOK) { $proc.ProcessorAffinity = [IntPtr]$mask }
            $proc.PriorityClass = $pr
        } catch { }
        $outT = $proc.StandardOutput.ReadToEndAsync()
        $errT = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $sw.Stop()

        $result = (($outT.Result -split "`r?`n") | Where-Object { $_ -match '^RESULT' } | Select-Object -First 1)
        if (-not $result) {
            $errFirst = (($errT.Result -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' | '
            throw ('segment {0}: no RESULT line (exit={1}) {2}' -f $i, $proc.ExitCode, $errFirst)
        }
        $line = ('seg={0} ' -f $i) + ($result -replace '^RESULT\s*', '').Trim()
        $segLines += $line
        Add-Content -Path $log -Value $line -Encoding utf8
        Write-Host ('done in {0:n0}s wall' -f $sw.Elapsed.TotalSeconds)
        Write-Host "  $line"
        if ($i -eq 0 -and $Segs -gt 1) {
            Write-Host ('  [eta] ~{0:n0} min total' -f ($sw.Elapsed.TotalMinutes * $Segs))
        }
    }
}
finally {
    # برگرداندن وضعیت خواب (با بسته‌شدن پاورشل هم خودکار برمی‌گردد)
    [void][SmileWin.Power]::SetThreadExecutionState($ES_CONTINUOUS)
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
$swTotal.Stop()

# ----------------------------------------------------------------------------
# ۴) خلاصه
# ----------------------------------------------------------------------------
$stats = @()
foreach ($l in $segLines) {
    $d = @{}
    foreach ($kv in ($l -split '\s+')) {
        $eq = $kv.IndexOf('=')
        if ($eq -gt 0) { $d[$kv.Substring(0, $eq)] = $kv.Substring($eq + 1) }
    }
    $stats += $d
}
function MeanOf([string]$key) {
    $vals = @()
    foreach ($d in $stats) { if ($d.ContainsKey($key)) { $vals += [double]$d[$key] } }
    if ($vals.Count -eq 0) { return 0 }
    return ($vals | Measure-Object -Average).Average
}
Write-Host ''
Write-Host ('===== seed {0}: {1} segments done in {2:n1} min wall =====' -f $Seed, $segLines.Count, $swTotal.Elapsed.TotalMinutes)
$sumLine = '  mean exact% = {0:n2}   mean words = {1:n1}   mean avgQ = {2:n2}   mean distinct = {3:n1}' -f (MeanOf 'exactpct'), (MeanOf 'words'), (MeanOf 'avgQ'), (MeanOf 'distinct')
Write-Host $sumLine
if ($stats.Count -gt 0) { Write-Host ('  final population = {0}' -f $stats[$stats.Count - 1]['pop']) }
Write-Host "  full log: $log"
