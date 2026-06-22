# Flock CLI Installer for Windows
# Usage: irm get.flockagents.ai/windows | iex

$ErrorActionPreference = "Stop"

$Repo = "flock-agents/releases"
$BinaryName = "flockagents"
$InstallDir = "$env:LOCALAPPDATA\Programs\flockagents"

function Main {
    Write-Log "Installing flockagents CLI..."
    $Version = Get-LatestVersion
    $TempDir = New-TempDirectory
    try {
        Download-Binary -Version $Version -TempDir $TempDir
        Verify-Checksum -TempDir $TempDir
        Install-Binary -TempDir $TempDir
        Add-ToPath
        Check-Docker
        Write-Success -Version $Version
    }
    finally {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
}

function Get-LatestVersion {
    Write-Log "Fetching latest version..."
    $Url = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $Response = Invoke-RestMethod -Uri $Url -UseBasicParsing
    }
    catch {
        Write-Error-Exit "Could not fetch latest version from GitHub. Check your internet connection."
    }
    $Tag = $Response.tag_name
    if (-not $Tag) {
        Write-Error-Exit "Could not determine latest version from GitHub releases."
    }
    Write-Log "Latest version: $Tag"
    return $Tag
}

function New-TempDirectory {
    $TempPath = Join-Path $env:TEMP "flockagents-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    return $TempPath
}

function Download-Binary {
    param([string]$Version, [string]$TempDir)

    $BinaryFile = "$BinaryName-cli-windows-amd64.exe"
    $script:BinaryFile = $BinaryFile
    $DownloadUrl = "https://github.com/$Repo/releases/download/$Version/$BinaryFile"
    $ChecksumsUrl = "https://github.com/$Repo/releases/download/$Version/checksums.txt"

    Write-Log "Downloading $BinaryFile..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile "$TempDir\$BinaryFile" -UseBasicParsing
    }
    catch {
        Write-Error-Exit "Failed to download binary from $DownloadUrl"
    }

    Write-Log "Downloading checksums..."
    try {
        Invoke-WebRequest -Uri $ChecksumsUrl -OutFile "$TempDir\checksums.txt" -UseBasicParsing
    }
    catch {
        Write-Error-Exit "Failed to download checksums from $ChecksumsUrl"
    }
}

function Verify-Checksum {
    param([string]$TempDir)

    Write-Log "Verifying checksum..."
    $ChecksumLines = Get-Content "$TempDir\checksums.txt"
    $ExpectedLine = $ChecksumLines | Where-Object { $_ -like "*$($script:BinaryFile)*" }
    if (-not $ExpectedLine) {
        Write-Error-Exit "Checksum not found for $($script:BinaryFile) in checksums.txt"
    }
    $Expected = ($ExpectedLine -split '\s+')[0]

    $Actual = (Get-FileHash -Path "$TempDir\$($script:BinaryFile)" -Algorithm SHA256).Hash.ToLower()
    if ($Expected -ne $Actual) {
        Write-Error-Exit "Checksum mismatch: expected $Expected, got $Actual"
    }
    Write-Log "Checksum verified"
}

function Install-Binary {
    param([string]$TempDir)

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $Dest = Join-Path $InstallDir "$BinaryName.exe"
    Copy-Item "$TempDir\$($script:BinaryFile)" $Dest -Force
    Write-Log "Installed to $Dest"
}

function Add-ToPath {
    $CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($CurrentPath -split ';' -contains $InstallDir) {
        return
    }

    Write-Log "Adding $InstallDir to user PATH..."
    [Environment]::SetEnvironmentVariable(
        "Path",
        "$CurrentPath;$InstallDir",
        "User"
    )
    $env:Path = "$env:Path;$InstallDir"
    Write-Log "PATH updated. Restart your terminal for it to take effect."
}

function Check-Docker {
    try {
        $null = & docker compose version 2>&1
    }
    catch {
        Write-Host ""
        Write-Log "WARNING: Docker Desktop not found. Flock requires Docker Desktop with WSL2."
        Write-Log "Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    }
}

function Write-Success {
    param([string]$Version)
    $VersionNum = $Version -replace '^cli-', ''
    Write-Host ""
    Write-Log "flockagents installed ($VersionNum). Run 'flockagents install' to set up Flock."
}

function Write-Log {
    param([string]$Message)
    Write-Host "[flockagents] $Message"
}

function Write-Error-Exit {
    param([string]$Message)
    Write-Host "[flockagents] ERROR: $Message" -ForegroundColor Red
    exit 1
}

Main
