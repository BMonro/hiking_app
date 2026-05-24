# Створює release keystore для MobSF / production (не комітиться в git).
# Запуск з папки android:  .\create_release_keystore.ps1

$ErrorActionPreference = "Stop"
$keystore = Join-Path $PSScriptRoot "app\hikora-release.keystore"
$props = Join-Path $PSScriptRoot "key.properties"

if (Test-Path $keystore) {
    Write-Host "Keystore вже існує: $keystore"
    exit 0
}

$storePass = Read-Host "Пароль keystore (запам'ятайте для key.properties)"
$keyPass = Read-Host "Пароль ключа (Enter = той самий)" 
if ([string]::IsNullOrWhiteSpace($keyPass)) { $keyPass = $storePass }

& keytool -genkey -v `
    -keystore $keystore `
    -alias hikora `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $storePass -keypass $keyPass `
    -dname "CN=Hikora, OU=Dev, O=Hikora, L=Kyiv, ST=Kyiv, C=UA"

@"
storePassword=$storePass
keyPassword=$keyPass
keyAlias=hikora
storeFile=app/hikora-release.keystore
"@ | Set-Content -Path $props -Encoding UTF8

Write-Host "Готово. key.properties створено. Зберіть APK:"
Write-Host "  cd .."
Write-Host "  flutter build apk --release"
