# Запуск навантажувального тесту Hikora (JMeter CLI + HTML-звіт)
# Приклад:
#   .\run_jmeter.ps1 -Email "you@mail.com" -Password "YourPass"

param(
    [Parameter(Mandatory = $false)]
    [string] $Email = $env:HIKORA_TEST_EMAIL,
    [Parameter(Mandatory = $false)]
    [string] $Password = $env:HIKORA_TEST_PASSWORD,
    [string] $JmeterHome = $env:JMETER_HOME
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$jmx = Join-Path $here "hikora_supabase_load.jmx"
$resultsDir = Join-Path $here "results"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jtl = Join-Path $resultsDir "run_$stamp.jtl"
$html = Join-Path $resultsDir "report_$stamp"

if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

function Find-JMeter {
    if ($JmeterHome) {
        $bat = Join-Path $JmeterHome "bin\jmeter.bat"
        if (Test-Path $bat) { return $bat }
    }
    $cmd = Get-Command jmeter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "C:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat",
        "C:\apache-jmeter-5.6.3\bin\jmeter.bat",
        "$env:ProgramFiles\apache-jmeter\bin\jmeter.bat"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$jmeter = Find-JMeter
if (-not $jmeter) {
    Write-Host "JMeter не знайдено. Встановіть: choco install jmeter"
    Write-Host "Або задайте JMETER_HOME=C:\path\to\apache-jmeter-5.6.3"
    Write-Host "Інструкція: docs\jmeter\HIKORA_JMETER_UA.md"
    exit 1
}

if (-not $Email -or -not $Password) {
    Write-Host "Задайте -Email та -Password або env HIKORA_TEST_EMAIL / HIKORA_TEST_PASSWORD"
    exit 1
}

$args = @(
    "-n",
    "-t", $jmx,
    "-l", $jtl,
    "-e", "-o", $html,
    "-JTEST_EMAIL=$Email",
    "-JTEST_PASSWORD=$Password"
)

Write-Host "JMeter: $jmeter"
Write-Host "JTL: $jtl"
Write-Host "HTML: $html"
& $jmeter @args
Write-Host "Готово. Відкрийте: $html\index.html"
