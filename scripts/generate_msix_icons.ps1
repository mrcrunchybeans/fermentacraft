# scripts/generate_msix_icons.ps1
# Generates all required MSIX/Microsoft Store icon sizes from a source image

param(
    [string]$SourceImage = "assets\images\logo256.png",
    [string]$OutputDir = "assets\images"
)

Write-Host "Generating MSIX icons from $SourceImage..." -ForegroundColor Green

# Check if ImageMagick is available
$magickPath = Get-Command "magick" -ErrorAction SilentlyContinue
if (-not $magickPath) {
    Write-Host "ImageMagick not found. Attempting to install via winget..." -ForegroundColor Yellow
    try {
        winget install ImageMagick.ImageMagick
        Write-Host "ImageMagick installed. Please restart your terminal and run this script again." -ForegroundColor Green
        exit 0
    } catch {
        Write-Error "Failed to install ImageMagick. Please install it manually from https://imagemagick.org/script/download.php#windows"
        exit 1
    }
}

# Check if source image exists
if (-not (Test-Path $SourceImage)) {
    Write-Error "Source image not found: $SourceImage"
    exit 1
}

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force
}

# Define required icon sizes for MSIX/Microsoft Store
$iconSizes = @{
    "Square44x44Logo.png" = "44x44"
    "Square71x71Logo.png" = "71x71"
    "Square89x89Logo.png" = "89x89"
    "Square107x107Logo.png" = "107x107"
    "Square142x142Logo.png" = "142x142"
    "Square150x150Logo.png" = "150x150"
    "Square284x284Logo.png" = "284x284"
    "Square310x310Logo.png" = "310x310"
    "StoreLogo.png" = "50x50"
    "LargeTile.png" = "310x310"
    "SmallTile.png" = "71x71"
    "SplashScreen.png" = "620x300"
    # Wide tile (not square)
    "Wide310x150Logo.png" = "310x150"
}

Write-Host "Creating icons..." -ForegroundColor Cyan

foreach ($icon in $iconSizes.GetEnumerator()) {
    $outputPath = Join-Path $OutputDir $icon.Key
    $size = $icon.Value
    
    try {
        if ($icon.Key -eq "Wide310x150Logo.png") {
            # Special handling for wide logo - create with transparent background and center the logo
            magick $SourceImage -background transparent -gravity center -extent $size $outputPath
        } elseif ($icon.Key -eq "SplashScreen.png") {
            # Special handling for splash screen
            magick $SourceImage -background transparent -gravity center -extent $size $outputPath
        } else {
            # Standard square resize
            magick $SourceImage -resize $size -background transparent -gravity center -extent $size $outputPath
        }
        
        Write-Host "✓ Generated $($icon.Key) ($size)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to generate $($icon.Key): $_"
    }
}

Write-Host ""
Write-Host "Icon generation complete!" -ForegroundColor Green
Write-Host "Generated icons are in: $OutputDir" -ForegroundColor Cyan

# Update pubspec.yaml with the new configuration
$pubspecPath = "pubspec.yaml"
if (Test-Path $pubspecPath) {
    Write-Host ""
    Write-Host "Updating pubspec.yaml with optimized icon configuration..." -ForegroundColor Yellow
    
    $pubspecContent = Get-Content $pubspecPath -Raw
    
    # Replace the msix_config section
    $newMsixConfig = @"
msix_config:
  display_name: FermentaCraft
  publisher_display_name: Brian Petry 
  identity_name: BrianPetry.FermentaCraft
  publisher: CN=115FAB00-DFE0-4774-9445-C1D4196A50C4
  msix_version: 2.0.0.54
  logo_path: assets/images/Square150x150Logo.png
  start_menu_icon_path: assets/images/Square44x44Logo.png
  tile_icon_path: assets/images/Square150x150Logo.png
  vs_generated_images_folder_path: assets/images
  icons_background_color: transparent
  store: true
"@

    # Update the msix_config section
    if ($pubspecContent -match '(?s)msix_config:.*?(?=\n\S|\n$|\Z)') {
        $updatedContent = $pubspecContent -replace '(?s)msix_config:.*?(?=\n\S|\n$|\Z)', $newMsixConfig
        Set-Content $pubspecPath $updatedContent -NoNewline
        Write-Host "✓ Updated pubspec.yaml with optimized icon paths" -ForegroundColor Green
    } else {
        Write-Warning "Could not find msix_config section in pubspec.yaml"
    }
}

Write-Host ""
Write-Host "All done! Your MSIX icons should now look perfect in the Microsoft Store." -ForegroundColor Green
Write-Host "Run your build script to test: .\scripts\build_windows_release.ps1" -ForegroundColor Cyan