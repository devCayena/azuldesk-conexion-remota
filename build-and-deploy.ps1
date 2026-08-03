param(
    [string]$Server = "devc@192.168.9.211",
    [string]$RemotePath = "/opt/azul_desk/conexion-remota/updates",
    [string]$ReleaseNotes = "",
    [switch]$Windows,
    [switch]$Android,
    [switch]$Linux,
    [switch]$Both = $true,
    [switch]$UploadAll,
    [switch]$OnlyUpload
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputDir = "$ScriptDir\build\installers"
$SshOpts = @()

$Pubspec = Get-Content "$ScriptDir\pubspec.yaml"
$VersionFull = ($Pubspec | Select-String '^version: (.+)$').Matches[0].Groups[1].Value.Trim()
$Version = $VersionFull -replace '\+.*', ''

if ($OnlyUpload) { Write-Host "Solo subida (sin build)" }
Write-Host "Versión: $Version`n"

if (-not $Windows -and -not $Android) { $Windows = $Android = $Both }
if (-not (Get-Command "flutter" -ErrorAction SilentlyContinue) -and -not $OnlyUpload) {
    throw "Flutter no está instalado"
}

$ManifestPath = if (Test-Path "..\backend\updates\manifest.json") { "..\backend\updates\manifest.json" }
                else { "$ScriptDir\..\backend\updates\manifest.json" }

# Lee SERVER_HOST del .env y lo compila dentro del binario (--dart-define),
# así el build release no depende de que el .env viaje empaquetado.
$EnvFile = "$ScriptDir\.env"
$ServerHost = ""
if (Test-Path $EnvFile) {
    $HostLine = Get-Content $EnvFile | Select-String '^SERVER_HOST=(.+)$'
    if ($HostLine) { $ServerHost = $HostLine.Matches[0].Groups[1].Value.Trim() }
}
$DartDefine = if ($ServerHost) { "--dart-define=SERVER_HOST=$ServerHost" } else { "" }
if ($DartDefine) { Write-Host "SERVER_HOST: $ServerHost (compilado en el binario)" }

function Compute-Sha256($path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
}

function Update-Manifest($file) {
    $sha = Compute-Sha256 $file
    $filename = [System.IO.Path]::GetFileName($file)
    $manifest = @{ version = $Version; download_url = $filename; checksum = $sha; mandatory = $false; release_notes = $ReleaseNotes }
    Set-Content -Path $ManifestPath -Value ($manifest | ConvertTo-Json -Compress)
    Write-Host "  manifest.json -> $filename ($sha)"
}

function Upload-All([string[]]$files, [string]$latest) {
    Write-Host "  Subiendo archivos... (pide contraseña 1 vez)"
    $output = scp @SshOpts @files "${Server}:${RemotePath}/" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Error SCP: $output" }

    if ($latest) {
        $latestLink = "azulremote-latest" + [System.IO.Path]::GetExtension($latest)
        $output = ssh @SshOpts $Server "cd '$RemotePath' && ln -sf $latest $latestLink" 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Warning "Error symlink: $output" }
    }
    Write-Host "  Hecho."
}

function Build-Platform($name, $buildCmd, $outputDir, $ext, $zipDir) {
    Write-Host "`n=== $name ($Version) ==="

    if (-not $OnlyUpload) {
        Push-Location $ScriptDir
        Invoke-Expression $buildCmd
        if ($LASTEXITCODE -ne 0) { throw "Build $name falló" }
        Pop-Location
    }

    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $needZip = $zipDir -and (Test-Path $zipDir)
    $uploadFiles = @()

    if ($needZip) {
        $uploadFile = "$OutputDir\azulremote-$Version.zip"
        Compress-Archive -Path "$zipDir\*" -DestinationPath $uploadFile -Force
        $uploadFiles += $uploadFile
    } else {
        $src = Get-ChildItem -Path $outputDir -Filter "*$ext" | Select-Object -First 1
        if (-not $src) { throw "No se encontró $ext compilado" }
        $uploadFile = "$OutputDir\azulremote-$Version$ext"
        Copy-Item $src.FullName $uploadFile
        $uploadFiles += $uploadFile
    }

    if ($UploadAll) {
        $pattern = if ($needZip) { "azulremote-*.zip" } else { "azulremote-*$ext" }
        Get-ChildItem "$OutputDir\$pattern" | Where-Object { $_.Name -ne "$([System.IO.Path]::GetFileName($uploadFile))" } | ForEach-Object {
            $uploadFiles += $_.FullName
        }
    }

    $uploadFiles += $ManifestPath
    $latest = [System.IO.Path]::GetFileName($uploadFile)

    Write-Host "  SHA-256: $(Compute-Sha256 $uploadFile)"
    Update-Manifest $uploadFile
    Upload-All $uploadFiles $latest
}

function Build-WindowsSingleExe {
    Write-Host "`n=== Windows: .exe autosuficiente ($Version) ==="

    if (-not $OnlyUpload) {
        Push-Location $ScriptDir
        flutter build windows --release $DartDefine
        if ($LASTEXITCODE -ne 0) { throw "Build Windows falló" }
        Pop-Location
    }

    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $uploadFile = "$OutputDir\azulremote-$Version.exe"

    # Empacar todo en un solo exe (bootstrap + payload embebido)
    & "$ScriptDir\pack-single-exe.ps1" -Output $uploadFile
    if ($LASTEXITCODE -ne 0) { throw "Empaquetado single-exe falló" }

    $uploadFiles = @($uploadFile)
    if ($UploadAll) {
        Get-ChildItem "$OutputDir\azulremote-*.exe" | Where-Object { $_.Name -ne "azulremote-$Version.exe" } | ForEach-Object {
            $uploadFiles += $_.FullName
        }
    }

    $uploadFiles += $ManifestPath
    $latest = [System.IO.Path]::GetFileName($uploadFile)

    Write-Host "  SHA-256: $(Compute-Sha256 $uploadFile)"
    Update-Manifest $uploadFile
    Upload-All $uploadFiles $latest
}

if ($Windows) { Build-WindowsSingleExe }
if ($Android) { Build-Platform "Android" "flutter build apk --release $DartDefine" "$ScriptDir\build\app\outputs\flutter-apk" ".apk" $null }
if ($Linux) {
    if ($IsWindows) {
        Write-Host "`n=== Linux: no se puede buildear en Windows. Usá -OnlyUpload si tenés el zip. ==="
    } else {
        Build-Platform "Linux" "flutter build linux --release $DartDefine" "$ScriptDir\build\linux/x64/release/bundle" "" "$ScriptDir\build\linux/x64/release/bundle"
    }
}

Write-Host "`n=== Deploy completado ==="
Write-Host "  Versión: $Version"
Write-Host "  Server: $Server"
