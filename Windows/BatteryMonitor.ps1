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
 
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runName = "BatteryMonitor"
$runValue = "c:\Programming\BatteryMonitor\Windows\BatteryMonitorStartup.bat"
$existing = $null
try { $existing = (Get-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue).$runName } catch {}
if (-not $existing -or $existing -ne $runValue) { New-ItemProperty -Path $runKey -Name $runName -Value $runValue -PropertyType String -Force | Out-Null }

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
    try {
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        $percent = [math]::Round($ps.BatteryLifePercent * 100)
        $isPluggedIn = ($ps.PowerLineStatus.ToString() -eq "Online")
        return @{
            Percent = $percent
            IsPluggedIn = $isPluggedIn
        }
    }
    catch {
        try {
            $battery = Get-CimInstance -ClassName Win32_Battery
            return @{
                Percent = $battery.EstimatedChargeRemaining
                IsPluggedIn = ($battery.BatteryStatus -eq 2)
            }
        }
        catch {
            return @{
                Percent = 0
                IsPluggedIn = $false
            }
        }
    }
}

# Main monitoring loop - runs silently
$lastNotificationTime = 0
$notificationCooldown = 300 # 5 minutes between notifications

try {
    while ($true) {
        $status = Get-BatteryStatus
        $currentTime = [int][double]::Parse((Get-Date -UFormat %s))
        
        if ($status.Percent -ge 90 -and $status.IsPluggedIn) {
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
