# Battery Monitor Script - Notifies when battery > 90% and plugged in
Add-Type -AssemblyName System.Windows.Forms

function Show-BatteryNotification {
    param([string]$Message)
    
    $notification = New-Object System.Windows.Forms.NotifyIcon
    $notification.Icon = [System.Drawing.SystemIcons]::Information
    $notification.BalloonTipTitle = "Battery Alert"
    $notification.BalloonTipText = $Message
    $notification.BalloonTipIcon = "Info"
    $notification.Visible = $true
    $notification.ShowBalloonTip(5000)
    
    # Clean up after showing
    Start-Sleep -Seconds 6
    $notification.Dispose()
}

function Get-BatteryStatus {
    $battery = Get-CimInstance -ClassName Win32_Battery
    $powerLineStatus = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus).PowerOnline
    
    return @{
        Percent = $battery.EstimatedChargeRemaining
        IsPluggedIn = ($battery.BatteryStatus -eq 2) -or $powerLineStatus
    }
}

# Main monitoring loop
Write-Host "Battery monitor started. Press Ctrl+C to stop."
Write-Host "Monitoring for battery > 90% while plugged in..."

$lastNotificationTime = 0
$notificationCooldown = 300 # 5 minutes between notifications

try {
    while ($true) {
        $status = Get-BatteryStatus
        $currentTime = [int][double]::Parse((Get-Date -UFormat %s))
        
        Write-Host "Battery: $($status.Percent)% | Plugged In: $($status.IsPluggedIn)"
        
        if ($status.Percent -gt 90 -and $status.IsPluggedIn) {
            if ($currentTime - $lastNotificationTime -gt $notificationCooldown) {
                $message = "Battery is $($status.Percent)% and still plugged in. Consider unplugging to preserve battery health."
                Show-BatteryNotification -Message $message
                Write-Host "NOTIFICATION SENT: $message"
                $lastNotificationTime = $currentTime
            }
        }
        
        Start-Sleep -Seconds 30 # Check every 30 seconds
    }
}
catch {
    Write-Host "Battery monitor stopped."
}
