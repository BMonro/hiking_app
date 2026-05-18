# Заповнення БД тестовими даними через Supabase CLI.
# Потрібно: npx supabase link (проєкт привʼязаний) АБО виконайте seed_data.sql вручну в SQL Editor.
#
# Використання:
#   cd d:\HikingApp\hiking_app
#   .\scripts\seed-database.ps1
#
# Або з явним project ref:
#   .\scripts\seed-database.ps1 -ProjectRef your-project-ref

param(
  [string]$ProjectRef = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$SeedFile = Join-Path $Root "supabase\seed_data.sql"

if (-not (Test-Path $SeedFile)) {
  Write-Error "Не знайдено $SeedFile"
}

Write-Host "HikingApp — seed БД" -ForegroundColor Cyan
Write-Host "Файл: $SeedFile" -ForegroundColor Gray

if ($ProjectRef) {
  Write-Host "Привʼязка проєкту: $ProjectRef" -ForegroundColor Yellow
  Push-Location $Root
  npx --yes supabase@latest link --project-ref $ProjectRef
  Pop-Location
}

Write-Host ""
Write-Host "Спроба виконати SQL через Supabase CLI..." -ForegroundColor Yellow
Push-Location $Root

try {
  npx --yes supabase@latest db execute --file $SeedFile
  Write-Host ""
  Write-Host "Готово." -ForegroundColor Green
}
catch {
  Write-Host ""
  Write-Host "CLI не виконав SQL (можливо, проєкт не привʼязаний)." -ForegroundColor Red
  Write-Host ""
  Write-Host "Зробіть вручну:" -ForegroundColor Yellow
  Write-Host "  1. Відкрийте https://supabase.com/dashboard → ваш проєкт → SQL Editor"
  Write-Host "  2. Скопіюйте вміст файлу supabase\seed_data.sql"
  Write-Host "  3. Натисніть Run"
  Write-Host ""
  Write-Host "Перед цим зареєструйтесь у застосунку (для походів і журналу в seed)."
}

Pop-Location
