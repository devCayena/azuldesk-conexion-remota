# pack-single-exe.ps1
# Empaqueta el build release de Flutter en UN solo .exe autosuficiente:
#   AzulRemote.exe = bootstrap + payload (.dll, data/, assets embebidos como recursos)
# Al ejecutarse extrae solo lo que falte/cambie a %LOCALAPPDATA%\AzulRemote y lanza la app.
#
# Uso:
#   .\pack-single-exe.ps1 [-ReleaseDir <ruta>] [-Output <ruta exe>]
#     -ReleaseDir: carpeta build\windows\x64\runner\Release (default)
#     -Output: ruta del exe generado (default build\installers\azulremote-<ver>.exe)

param(
    [string]$ReleaseDir = "",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BootstrapDir = "$ScriptDir\windows\bootstrap"
$WorkDir = "$ScriptDir\build\pack"

if (-not $ReleaseDir) {
    $ReleaseDir = "$ScriptDir\build\windows\x64\runner\Release"
}
if (-not (Test-Path "$ReleaseDir\AzulRemote.exe")) {
    throw "No se encontró el build release en $ReleaseDir. Corré: flutter build windows --release"
}
$Pubspec = Get-Content "$ScriptDir\pubspec.yaml"
$VersionFull = ($Pubspec | Select-String '^version: (.+)$').Matches[0].Groups[1].Value.Trim()
$Version = $VersionFull -replace '\+.*', ''

if (-not $Output) {
    $Output = "$ScriptDir\build\installers\azulremote-$Version.exe"
}

$verParts = $Version -split '\.'
$verBuild = if ($VersionFull -match '\+(\d+)$') { $Matches[1] } else { '0' }
$verComma = "$($verParts[0]),$($verParts[1]),$($verParts[2]),$verBuild"
$verDot = "$Version.$verBuild"

# 1. MSVC + SDK paths (auto-detectados)
$vsWhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vsWhere -latest -property installationPath 2>$null
if (-not $vsPath) { $vsPath = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\*" -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName }
$msvc = Get-ChildItem "$vsPath\VC\Tools\MSVC\*" -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$kitBinRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
$kitVer = (Get-ChildItem $kitBinRoot -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name)
$kitRoot = "$kitBinRoot\$kitVer"
$sdkBin = "$kitRoot\x64"
$sdkLib = "C:\Program Files (x86)\Windows Kits\10\Lib\$kitVer"
$sdkInclude = "C:\Program Files (x86)\Windows Kits\10\Include\$kitVer"
$binHost = "$msvc\bin\Hostx64\x64"

# Rutas cortas 8.3: evitan que PowerShell/cmd rompan argumentos con espacios
function Get-ShortPath([string]$p) {
    if (-not (Test-Path $p)) { return $p }
    $fso = New-Object -ComObject Scripting.FileSystemObject
    return $fso.GetFolder($p).ShortPath
}
$sdkBin83 = Get-ShortPath "$kitRoot\x64"
$msvcInc83  = Get-ShortPath "$msvc\include"
$sdkInc83   = Get-ShortPath "$sdkInclude"
$msvcLib83  = Get-ShortPath "$msvc\lib\x64"
$sdkLib83   = Get-ShortPath $sdkLib
$binHost83  = Get-ShortPath $binHost
$outShort   = Get-ShortPath (Split-Path -Parent $Output)
$workShort  = Get-ShortPath $WorkDir
$bootDir83  = Get-ShortPath $BootstrapDir

$env:INCLUDE = "$msvcInc83;$sdkInc83\ucrt;$sdkInc83\um;$sdkInc83\shared"
$env:LIB = "$msvcLib83;$sdkLib83\ucrt\x64;$sdkLib83\um\x64"

Write-Host "VS: $vsPath"
Write-Host "MSVC: $msvc"
Write-Host "SDK: $kitVer"

# 2. Recolectar archivos del Release
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# Copiar logo para que quede embebido y se use en system tray + window icon
$logo = "$ScriptDir\windows\runner\resources\logo.png"
if (Test-Path $logo) { Copy-Item $logo "$ReleaseDir\logo.png" -Force; Write-Host "Logo copiado al payload" }

$files = Get-ChildItem -Path $ReleaseDir -Recurse -File | Where-Object { $_.Name -notmatch '^azulremote-.*\.zip$' }
Write-Host "`nEmpaquetando $($files.Count) archivos..."

# 3. Generar manifest (path|id|size|sha256)
$manifest = @()
$rcLines = @(
    '#include <windows.h>'
    '1 VERSIONINFO'
    "FILEVERSION $verComma"
    "PRODUCTVERSION $verComma"
    'FILEOS VOS_NT_WINDOWS32'
    'FILETYPE VFT_APP'
    '{'
    '  BLOCK "StringFileInfo"'
    '  {'
    '    BLOCK "040904B0"'
    '    {'
    '      VALUE "CompanyName", "Cayena Azul"'
    '      VALUE "FileDescription", "AzulRemote - Conexion Remota"'
    "      VALUE ""FileVersion"", ""$verDot"""
    '      VALUE "InternalName", "AzulRemote"'
    '      VALUE "LegalCopyright", "Cayena Azul"'
    '      VALUE "OriginalFilename", "AzulRemote.exe"'
    '      VALUE "ProductName", "AzulRemote"'
    "      VALUE ""ProductVersion"", ""$verDot"""
    '    }'
    '  }'
    '  BLOCK "VarFileInfo" { VALUE "Translation", 0x0409, 0x04B0 }'
    '}'
)
$id = 2   # el 1 está reservado para el manifest
foreach ($f in $files) {
    $rel = $f.FullName.Substring($ReleaseDir.Length).TrimStart('\')
    $relUnix = $rel.Replace('\', '/')
    $sha = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item $f.FullName).Length
    $manifest += "$relUnix`t$id`t$size`t$sha"
    $rcLines += "$id RCDATA `"$($f.FullName.Replace('\', '\\'))`""
    $id++
}
$manifest += "# manifest generado por pack-single-exe.ps1"
# el manifest se indexa como recurso 1
$manifestContent = $manifest -join "`r`n"
[System.IO.File]::WriteAllText("$WorkDir\manifest.txt", $manifestContent, (New-Object System.Text.UTF8Encoding($false)))
$rcLines += "1 RCDATA `"$WorkDir\manifest.txt`""
[System.IO.File]::WriteAllText("$WorkDir\payload.rc", ($rcLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

# 4. Compilar recursos
Write-Host "`nCompilando recursos..."
& "$sdkBin83\rc.exe" /fo "$workShort\payload.res" "$workShort\payload.rc"
if ($LASTEXITCODE -ne 0) { throw "rc.exe falló" }

# 5. Compilar bootstrap + enlazar
Write-Host "Compilando bootstrap..."
New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
& "$binHost83\cl.exe" /nologo /O1 /MT /utf-8 /DUNICODE /D_UNICODE /W3 `
    "$bootDir83\bootstrap.c" "$workShort\payload.res" `
    /Fe:"$outShort\azulremote-pack.exe" /link `
    /SUBSYSTEM:WINDOWS /ENTRY:wmainCRTStartup `
    /LIBPATH:"$msvcLib83" /LIBPATH:"$sdkLib83\ucrt\x64" /LIBPATH:"$sdkLib83\um\x64" `
    kernel32.lib user32.lib shell32.lib shlwapi.lib bcrypt.lib ole32.lib advapi32.lib
if ($LASTEXITCODE -ne 0) { throw "cl.exe falló" }

Move-Item -Force "$outShort\azulremote-pack.exe" $Output

# 6. Verificar
$info = Get-Item $Output
$shaOut = (Get-FileHash $Output -Algorithm SHA256).Hash.ToLower()
Write-Host "`n=== Empaquetado OK ==="
Write-Host "  Archivo: $Output"
Write-Host "  Tamaño:  $([math]::Round($info.Length / 1MB, 2)) MB"
Write-Host "  SHA-256: $shaOut"
Write-Host "  Payload: $($files.Count) archivos embebidos"
