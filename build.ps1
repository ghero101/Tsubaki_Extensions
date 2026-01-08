# =============================================================================
# Tsubaki Extensions Build Script (Windows PowerShell)
# =============================================================================
# This script:
#   1. Reads manifest.json from each extension to get version info
#   2. Updates index.json with current versions and download URLs
#   3. Creates versioned zip files (e.g., flamecomics-rhai_1-1-5.zip)
#   4. Creates _latest.zip copies for convenience
#   5. Organizes everything in dist/{extension-name}/ folders
# =============================================================================

param(
    [switch]$Clean,
    [switch]$Help,
    [string]$Single
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourcesDir = Join-Path $ScriptDir "sources"
$DistDir = Join-Path $ScriptDir "dist"
$IndexFile = Join-Path $ScriptDir "index.json"

# GitHub raw URL base for download URLs
$GitHubRawBase = "https://raw.githubusercontent.com/ghero101/Tsubaki_Extensions/master"

# Store built extensions for index update
$Script:BuiltExtensions = @()

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-Host @"
Tsubaki Extensions Build Script (Windows)

Usage: .\build.ps1 [options]

Options:
    -Help       Show this help message
    -Clean      Clean dist directory before building
    -Single     Build only a single extension (e.g., -Single "flamecomics-rhai")

Examples:
    .\build.ps1                           # Build all extensions
    .\build.ps1 -Clean                    # Clean and rebuild all
    .\build.ps1 -Single "mangadex-rhai"   # Build only mangadex-rhai

"@
}

function Get-ManifestValue {
    param(
        [string]$ManifestPath,
        [string]$Key
    )

    try {
        $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        return $manifest.$Key
    }
    catch {
        return $null
    }
}

function ConvertTo-VersionFilename {
    param([string]$Version)
    return $Version -replace '\.', '-'
}

function Build-Extension {
    param([string]$ExtDir)

    $extName = Split-Path $ExtDir -Leaf
    $manifestFile = Join-Path $ExtDir "manifest.json"

    # Check if manifest exists
    if (-not (Test-Path $manifestFile)) {
        Write-ColorOutput "  Skipping $extName (no manifest.json)" "Yellow"
        return
    }

    # Read manifest values
    $extId = Get-ManifestValue $manifestFile "id"
    $version = Get-ManifestValue $manifestFile "version"
    $name = Get-ManifestValue $manifestFile "name"

    if (-not $version) {
        Write-ColorOutput "  Skipping $extName (no version in manifest)" "Yellow"
        return
    }

    $versionFilename = ConvertTo-VersionFilename $version
    $extDistDir = Join-Path $DistDir $extName
    $zipFilename = "${extName}_${versionFilename}.zip"
    $zipPath = Join-Path $extDistDir $zipFilename
    $latestPath = Join-Path $extDistDir "${extName}_latest.zip"

    Write-ColorOutput "  Building: $name ($extName) v$version" "Green"

    # Create extension dist directory
    New-Item -ItemType Directory -Force -Path $extDistDir | Out-Null

    # Check if this version already exists
    if (Test-Path $zipPath) {
        Write-ColorOutput "    Version $version already exists, rebuilding..." "Yellow"
        Remove-Item $zipPath -Force
    }

    # Remove latest if exists
    if (Test-Path $latestPath) {
        Remove-Item $latestPath -Force
    }

    # Create the zip file
    # PowerShell's Compress-Archive needs special handling for folder structure
    $tempZipPath = Join-Path $env:TEMP "$zipFilename"

    # Create zip with folder structure
    try {
        # Remove temp file if exists
        if (Test-Path $tempZipPath) {
            Remove-Item $tempZipPath -Force
        }

        # Compress the extension folder
        Compress-Archive -Path $ExtDir -DestinationPath $tempZipPath -Force

        # Move to final location
        Move-Item $tempZipPath $zipPath -Force

        # Create latest.zip copy
        Copy-Item $zipPath $latestPath -Force

        # Get file size
        $size = (Get-Item $zipPath).Length
        $sizeKB = [math]::Round($size / 1KB, 2)
        Write-Host "    Created: $zipFilename ($sizeKB KB)"

        # Store for index update
        $Script:BuiltExtensions += [PSCustomObject]@{
            ExtId = $extId
            ExtName = $extName
            Version = $version
            ZipFilename = $zipFilename
        }
    }
    catch {
        Write-ColorOutput "    Error creating zip: $_" "Red"
    }
}

function Update-Index {
    Write-Host ""
    Write-ColorOutput "Updating index.json..." "Cyan"

    if (-not (Test-Path $IndexFile)) {
        Write-ColorOutput "Error: index.json not found" "Red"
        return
    }

    try {
        $index = Get-Content $IndexFile -Raw | ConvertFrom-Json
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $updatedCount = 0

        foreach ($ext in $Script:BuiltExtensions) {
            $downloadUrl = "$GitHubRawBase/dist/$($ext.ExtName)/$($ext.ZipFilename)"
            $manifestUrl = "$GitHubRawBase/sources/$($ext.ExtName)/manifest.json"

            # Find and update the addon in the index
            foreach ($addon in $index.addons) {
                if ($addon.id -eq $ext.ExtId) {
                    $addon.version = $ext.Version
                    $addon.latest_version = $ext.Version
                    $addon.download_url = $downloadUrl
                    $addon.manifest_url = $manifestUrl

                    # Add/update version entry
                    if (-not $addon.versions) {
                        $addon | Add-Member -NotePropertyName "versions" -NotePropertyValue @{} -Force
                    }

                    $addon.versions | Add-Member -NotePropertyName $ext.Version -NotePropertyValue @{
                        download_url = $downloadUrl
                        released_at = $timestamp
                        changelog = "Updated"
                    } -Force

                    $updatedCount++
                    break
                }
            }
        }

        # Update index version and timestamp
        $index.version = ($index.version -as [int]) + 1
        $index.updated_at = $timestamp

        # Write back to file with proper formatting
        $index | ConvertTo-Json -Depth 10 | Set-Content $IndexFile -Encoding UTF8

        Write-ColorOutput "  Updated $updatedCount extensions in index.json (version $($index.version))" "Green"
    }
    catch {
        Write-ColorOutput "Error updating index.json: $_" "Red"
    }
}

function Start-Build {
    Write-ColorOutput "==============================================================================" "Cyan"
    Write-ColorOutput "                    Tsubaki Extensions Build Script                          " "Cyan"
    Write-ColorOutput "==============================================================================" "Cyan"
    Write-Host ""
    Write-ColorOutput "Sources directory: $SourcesDir" "Cyan"
    Write-ColorOutput "Dist directory: $DistDir" "Cyan"
    Write-Host ""

    # Create dist directory if it doesn't exist
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

    Write-ColorOutput "Building extensions..." "Cyan"

    # Process each extension directory
    Get-ChildItem -Path $SourcesDir -Directory | ForEach-Object {
        Build-Extension $_.FullName
    }

    # Update index.json
    Update-Index

    Write-Host ""
    Write-ColorOutput "==============================================================================" "Cyan"
    Write-ColorOutput "Build complete!" "Green"
    Write-Host ""
    Write-Host "Built $($Script:BuiltExtensions.Count) extensions"
    Write-Host ""
    Write-ColorOutput "Next steps:" "Yellow"
    Write-Host "  1. Review changes: git status"
    Write-Host "  2. Commit: git add -A && git commit -m 'Update extensions'"
    Write-Host "  3. Push: git push"
    Write-ColorOutput "==============================================================================" "Cyan"
}

# Main entry point
if ($Help) {
    Show-Help
    exit 0
}

if ($Clean) {
    Write-ColorOutput "Cleaning dist directory..." "Yellow"
    if (Test-Path $DistDir) {
        Remove-Item "$DistDir\*" -Recurse -Force
    }
}

if ($Single) {
    $singlePath = Join-Path $SourcesDir $Single
    if (Test-Path $singlePath) {
        New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
        Build-Extension $singlePath
        Update-Index
    }
    else {
        Write-ColorOutput "Error: Extension '$Single' not found" "Red"
        exit 1
    }
}
else {
    Start-Build
}
