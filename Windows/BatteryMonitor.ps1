# Battery Monitor Script - Notifies when battery > 90% and plugged in
# Runs silently in background
Add-Type -AssemblyName System.Windows.Forms

# Hide console window
$showWindowAsync = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@ -Name "Win32ShowWindowAsync" -PassThru

$consoleHandle = Get-Process -Id $PID | Select-Object -ExpandProperty MainWindowHandle
$showWindowAsync::ShowWindowAsync($consoleHandle, 0) | Out-Null

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

# Main monitoring loop - runs silently
$lastNotificationTime = 0
$notificationCooldown = 300 # 5 minutes between notifications

try {
    while ($true) {
        $status = Get-BatteryStatus
        $currentTime = [int][double]::Parse((Get-Date -UFormat %s))
        
        if ($status.Percent -gt 90 -and $status.IsPluggedIn) {
            if ($currentTime - $lastNotificationTime -gt $notificationCooldown) {
                $message = "Battery is $($status.Percent)% and still plugged in. Consider unplugging to preserve battery health."
                Show-BatteryNotification -Message $message
                $lastNotificationTime = $currentTime
            }
        }
        
        Start-Sleep -Seconds 30 # Check every 30 seconds
    }
}
catch {
    # Silent error handling
}
