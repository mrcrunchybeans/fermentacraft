# Quick script to check what version would be used
$localPropertiesPath = ".\android\local.properties"
if (Test-Path $localPropertiesPath) {
    Get-Content $localPropertiesPath | ForEach-Object {
        if ($_ -match "flutter\.version") {
            Write-Host $_
        }
    }
} else {
    Write-Host "local.properties not found"
}

# Also check pubspec
$pubspecPath = ".\pubspec.yaml"
if (Test-Path $pubspecPath) {
    $version = Get-Content $pubspecPath | Select-String "version:"
    Write-Host "pubspec.yaml: $version"
}