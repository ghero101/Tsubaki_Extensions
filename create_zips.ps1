$sourcesDir = "C:\Users\Arch\Desktop\komga-rebuild\tsubaki-addons\sources"
$distDir = "C:\Users\Arch\Desktop\komga-rebuild\tsubaki-addons\dist"

# Create dist directory if it doesn't exist
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

# Get all addon directories
$addonDirs = Get-ChildItem -Path $sourcesDir -Directory

foreach ($addon in $addonDirs) {
    $zipPath = Join-Path $distDir "$($addon.Name).zip"
    Write-Host "Creating $zipPath..."

    # Remove existing zip if present
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    # Create zip
    Compress-Archive -Path (Join-Path $addon.FullName "*") -DestinationPath $zipPath -Force
}

Write-Host ""
Write-Host "Created zip files:"
Get-ChildItem -Path $distDir -Filter "*.zip" | ForEach-Object {
    Write-Host "  $($_.Name) - $([math]::Round($_.Length / 1KB, 2)) KB"
}
