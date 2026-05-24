# Відкриває JMeter GUI з планом Hikora і без помилки «Could not delete ... bin»
param(
    [string] $JmeterHome = "D:\Downloads\apache-jmeter-5.6.3\apache-jmeter-5.6.3"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$jmx = Join-Path $here "hikora_supabase_load.jmx"
$props = Join-Path $here "jmeter.gui.properties"
$resultsDir = Join-Path $here "results"

if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$bat = Join-Path $JmeterHome "bin\jmeter.bat"
if (-not (Test-Path $bat)) {
    Write-Host "Не знайдено: $bat"
    Write-Host "Задайте -JmeterHome 'C:\path\to\apache-jmeter-5.6.3'"
    exit 1
}

Write-Host "JMeter GUI + Hikora plan"
Write-Host "Properties: $props"
Write-Host "JMX: $jmx"
& $bat -q $props -t $jmx
