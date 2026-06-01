# ============================================
# BRANDO FURNITURE - ALWAYS LIVE STARTER
# ============================================
# This script starts both the local server and
# the Cloudflare tunnel so your website is
# accessible from anywhere in the world!
# ============================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   BRANDO FURNITURE - GOING LIVE!          " -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Kill any existing instances
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force
# Kill any PowerShell running host_app.ps1
Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | 
    Where-Object { $_.CommandLine -like "*host_app.ps1*" } | 
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 2

# Step 1: Start local server
Write-Host "[1/2] Starting local server on port 8081..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$scriptDir\host_app.ps1`"" -WorkingDirectory $scriptDir
Start-Sleep -Seconds 3

# Verify server started
$port = netstat -ano | findstr ":8081"
if ($port) {
    Write-Host "  [OK] Server is running on http://localhost:8081" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Server failed to start!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 2: Start Cloudflare Tunnel
Write-Host "[2/2] Creating public tunnel..." -ForegroundColor Green
$tunnelLog = Join-Path $scriptDir "tunnel_log.txt"
Start-Process -FilePath "$scriptDir\cloudflared.exe" -ArgumentList "tunnel","--url","http://localhost:8081" -NoNewWindow -RedirectStandardError $tunnelLog
Start-Sleep -Seconds 12

# Extract public URL
$url = ""
$logContent = Get-Content $tunnelLog -ErrorAction SilentlyContinue
foreach ($line in $logContent) {
    if ($line -match "(https://[a-z0-9-]+\.trycloudflare\.com)") {
        $url = $matches[1]
        break
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   YOUR WEBSITE IS LIVE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  LOCAL ACCESS:" -ForegroundColor Yellow
Write-Host "    http://localhost:8081           (Main Site)" -ForegroundColor White
Write-Host "    http://localhost:8081/admin.html (Admin Panel)" -ForegroundColor White
Write-Host ""

if ($url) {
    Write-Host "  PUBLIC ACCESS (Share with Dad!):" -ForegroundColor Yellow
    Write-Host "    $url           (Main Site)" -ForegroundColor Magenta
    Write-Host "    $url/admin.html (Admin Panel)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Copy the PUBLIC link and send it to your Dad!" -ForegroundColor Cyan
    
    # Copy to clipboard
    $url | Set-Clipboard
    Write-Host "  [Link copied to clipboard!]" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Could not get public URL. Check tunnel_log.txt" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  KEEP THIS WINDOW OPEN TO STAY LIVE!" -ForegroundColor Red
Write-Host "  Press Ctrl+C to stop the server." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Keep alive - monitor and auto-restart if needed
while ($true) {
    Start-Sleep -Seconds 30
    
    # Check if server is still running
    $portCheck = netstat -ano | findstr ":8081"
    if (-not $portCheck) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Server stopped! Restarting..." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$scriptDir\host_app.ps1`"" -WorkingDirectory $scriptDir
        Start-Sleep -Seconds 3
    }
    
    # Check if tunnel is still running
    $tunnelProc = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if (-not $tunnelProc) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tunnel stopped! Restarting..." -ForegroundColor Yellow
        Start-Process -FilePath "$scriptDir\cloudflared.exe" -ArgumentList "tunnel","--url","http://localhost:8081" -NoNewWindow -RedirectStandardError $tunnelLog
        Start-Sleep -Seconds 10
        $logContent = Get-Content $tunnelLog -ErrorAction SilentlyContinue
        foreach ($line in $logContent) {
            if ($line -match "(https://[a-z0-9-]+\.trycloudflare\.com)") {
                Write-Host "  NEW PUBLIC URL: $($matches[1])" -ForegroundColor Magenta
                $matches[1] | Set-Clipboard
                break
            }
        }
    }
}
