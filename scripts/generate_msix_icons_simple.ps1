# scripts/generate_msix_icons_simple.ps1
# Simple PowerShell-only version using System.Drawing (if available)

param(
    [string]$SourceImage = "assets\images\logo256.png",
    [string]$OutputDir = "assets\images"
)

Write-Host "Generating MSIX icons using .NET System.Drawing..." -ForegroundColor Green

# Load System.Drawing assembly
try {
    Add-Type -AssemblyName System.Drawing
    Write-Host "✓ System.Drawing loaded successfully" -ForegroundColor Green
} catch {
    Write-Error "System.Drawing not available. Please use the ImageMagick version instead."
    Write-Host "Run: .\scripts\generate_msix_icons.ps1" -ForegroundColor Yellow
    exit 1
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

# Function to resize image
function Resize-Image {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$Width,
        [int]$Height
    )
    
    try {
        # Load the source image
        $sourceImage = [System.Drawing.Image]::FromFile((Resolve-Path $InputPath))
        
        # Create new bitmap with desired size
        $resizedBitmap = New-Object System.Drawing.Bitmap($Width, $Height)
        $graphics = [System.Drawing.Graphics]::FromImage($resizedBitmap)
        
        # Set high quality rendering
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        
        # Draw resized image
        $graphics.DrawImage($sourceImage, 0, 0, $Width, $Height)
        
        # Save the resized image
        $resizedBitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        
        # Clean up
        $graphics.Dispose()
        $resizedBitmap.Dispose()
        $sourceImage.Dispose()
        
        Write-Host "✓ Generated $(Split-Path $OutputPath -Leaf) (${Width}x${Height})" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to generate $(Split-Path $OutputPath -Leaf): $_"
        return $false
    }
}

# Define required icon sizes
$iconSizes = @{
    "Square44x44Logo.png" = @{Width=44; Height=44}
    "Square71x71Logo.png" = @{Width=71; Height=71}
    "Square89x89Logo.png" = @{Width=89; Height=89}
    "Square107x107Logo.png" = @{Width=107; Height=107}
    "Square142x142Logo.png" = @{Width=142; Height=142}
    "Square150x150Logo.png" = @{Width=150; Height=150}
    "Square284x284Logo.png" = @{Width=284; Height=284}
    "Square310x310Logo.png" = @{Width=310; Height=310}
    "StoreLogo.png" = @{Width=50; Height=50}
    "LargeTile.png" = @{Width=310; Height=310}
    "SmallTile.png" = @{Width=71; Height=71}
    "SplashScreen.png" = @{Width=620; Height=300}
    "Wide310x150Logo.png" = @{Width=310; Height=150}
}

Write-Host "Creating icons..." -ForegroundColor Cyan

foreach ($icon in $iconSizes.GetEnumerator()) {
    $outputPath = Join-Path $OutputDir $icon.Key
    $width = $icon.Value.Width
    $height = $icon.Value.Height
    
    Resize-Image -InputPath $SourceImage -OutputPath $outputPath -Width $width -Height $height
}

Write-Host ""
Write-Host "Icon generation complete!" -ForegroundColor Green
Write-Host "Generated icons are in: $OutputDir" -ForegroundColor Cyan