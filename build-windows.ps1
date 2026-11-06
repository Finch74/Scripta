# Builds ScriptaWin (ScriptaCore + Sources/ScriptaWin) on Windows with Swift Package Manager.
#
# Steps:
#   1. Visual Studio 2022 Community with the MSVC tools (x64 and ARM64) and the Windows 11 SDK,
#      installed with WinGet (needed by the Swift toolchain on Windows).
#   2. Swift toolchain, installed with WinGet.
#   3. swift build -c release --product ScriptaWin
#
# Usage (PowerShell):  .\build-windows.ps1            install the dependencies, then build
#                      .\build-windows.ps1 -SkipSetup  build only (dependencies already installed)
# Installing Visual Studio requires administrator rights: WinGet asks for elevation (UAC) if needed.
[CmdletBinding()]
param(
    [switch]$SkipSetup
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

if (-not $SkipSetup) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget non trovato: installa "App Installer" dal Microsoft Store.'
    }

    # Installazione dipendenze C++ e SDK Visual Studio
    Write-Host 'Installazione di Visual Studio 2022 (MSVC + Windows 11 SDK)...'
    winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Installazione di Visual Studio non riuscita (codice $LASTEXITCODE)." }

    # Installazione Toolchain Swift
    # Already installed: winget returns a non-zero code (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED
    # or "no applicable upgrade"), which is not an error here; whether `swift` works is checked below.
    Write-Host 'Installazione della toolchain Swift...'
    winget install --id Swift.Toolchain -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Write-Warning "winget ha restituito $LASTEXITCODE (Swift forse già installato)." }

    # The installers update PATH (and the Swift toolchain SDKROOT) in the registry, not in this session:
    # reload them so `swift` is found and can locate the Windows platform SDK.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($scope in 'Machine', 'User') {
        $sdkRoot = [Environment]::GetEnvironmentVariable('SDKROOT', $scope)
        if ($sdkRoot) { $env:SDKROOT = $sdkRoot }
    }
}

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    throw 'swift non trovato nel PATH: apri un nuovo terminale o reinstalla la toolchain Swift.'
}
swift --version

Write-Host 'Compilazione di ScriptaWin (release)...'
swift build -c release --product ScriptaWin
if ($LASTEXITCODE -ne 0) { throw "Compilazione non riuscita (codice $LASTEXITCODE)." }

$binPath = (swift build -c release --show-bin-path).Trim()
$exe = Join-Path $binPath 'ScriptaWin.exe'
if (-not (Test-Path $exe)) { throw "Eseguibile non trovato: $exe" }
Write-Host "Build completata: $exe"
