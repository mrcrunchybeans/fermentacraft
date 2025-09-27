#!/usr/bin/env pwsh
# Memory monitoring script for FermantaCraft app

Write-Host "🔍 FermantaCraft Memory Monitor" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Yellow
Write-Host ""

$initialMemory = $null
$previousMemory = $null

while ($true) {
    try {
        # Get memory usage for fermentacraft.exe
        $process = Get-Process -Name "fermentacraft" -ErrorAction SilentlyContinue
        
        if ($process) {
            $memoryMB = [Math]::Round($process.WorkingSet64 / 1MB, 1)
            $timestamp = Get-Date -Format "HH:mm:ss"
            
            if ($null -eq $initialMemory) {
                $initialMemory = $memoryMB
                Write-Host "🚀 Initial Memory: $memoryMB MB" -ForegroundColor Green
            }
            
            $change = ""
            if ($null -ne $previousMemory) {
                $delta = $memoryMB - $previousMemory
                if ($delta -gt 5) {
                    $change = " (+$([Math]::Round($delta, 1))MB ⬆️)"
                } elseif ($delta -lt -5) {
                    $change = " ($([Math]::Round($delta, 1))MB ⬇️)"
                }
            }
            
            # Color coding based on memory level
            $color = switch ($memoryMB) {
                { $_ -lt 300 } { "Green" }
                { $_ -lt 400 } { "Yellow" }
                { $_ -lt 500 } { "DarkYellow" }
                default { "Red" }
            }
            
            Write-Host "[$timestamp] Memory: $memoryMB MB$change" -ForegroundColor $color
            
            # Memory level indicators
            if ($memoryMB -gt 500) {
                Write-Host "  ☢️ CRITICAL - Use Nuclear Cleanup!" -ForegroundColor Red
            } elseif ($memoryMB -gt 400) {
                Write-Host "  ⚡ HIGH - Use Extreme Reduction!" -ForegroundColor Magenta
            } elseif ($memoryMB -lt 300) {
                Write-Host "  ✅ EXCELLENT - Target achieved!" -ForegroundColor Green
            } elseif ($memoryMB -lt 400) {
                Write-Host "  👍 GOOD - Getting close to target" -ForegroundColor Yellow
            }
            
            $previousMemory = $memoryMB
        } else {
            Write-Host "⚠️ FermantaCraft app not running" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Error monitoring memory: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 3
}