# Battery Monitor Script
# Runs silently in background and alerts when battery is >= 90% while charging.
try { Add-Type -AssemblyName System.Windows.Forms } catch {}

$logPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "BatteryMonitor.log")
function Write-Log {
    param([string]$Message)
    try {
        Add-Content -Path $logPath -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message)
    } catch {}
}

# Hide console window
try {
$showWindowAsync = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
"@ -Name "Win32ShowWindowAsync" -PassThru
$consoleHandle = Get-Process -Id $PID | Select-Object -ExpandProperty MainWindowHandle
$showWindowAsync::ShowWindowAsync($consoleHandle, 0) | Out-Null
} catch {}
 
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runName = "BatteryMonitor"
$scriptPath = $MyInvocation.MyCommand.Path
$escapedScriptPath = $scriptPath.Replace('"', '""')
$runValue = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escapedScriptPath"""
$existing = $null
try { $existing = (Get-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue).$runName } catch {}
if (-not $existing -or $existing -ne $runValue) { New-ItemProperty -Path $runKey -Name $runName -Value $runValue -PropertyType String -Force | Out-Null }
Write-Log "Startup Run key ensured."

# Also ensure startup via scheduled task for better reliability at sign-in.
try {
    $taskName = "BatteryMonitor"
    $taskAction = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    schtasks /Create /TN $taskName /SC ONLOGON /TR $taskAction /F | Out-Null
    Write-Log "Scheduled task ensured."
} catch {
    Write-Log ("Scheduled task setup failed: {0}" -f $_.Exception.Message)
}

$mutex = New-Object System.Threading.Mutex($false,"BatteryMonitorMutex")
if (-not $mutex.WaitOne(0,$false)) { exit }
Write-Log "Monitor started."

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

function Show-Notification {
    param([string]$Message)

    # 1) Try a direct Windows session message (very visible).
    try {
        & msg.exe * /TIME:8 "$Message" | Out-Null
        Write-Log "MSG notification shown: $Message"
        return
    } catch {
        Write-Log ("MSG notification failed: {0}" -f $_.Exception.Message)
    }

    # 2) Try a popup dialog.
    try {
        $wshell = New-Object -ComObject WScript.Shell
        $null = $wshell.Popup($Message, 8, "Battery Alert", 64)
        Write-Log "Popup notification shown: $Message"
        return
    }
    catch {
        Write-Log ("Popup notification failed: {0}" -f $_.Exception.Message)
    }

    # 3) Last fallback: tray balloon.
    try {
        Show-BatteryNotification -Message $Message
        Write-Log "Tray balloon notification shown: $Message"
    } catch {
        Write-Log ("All notification methods failed: {0}" -f $_.Exception.Message)
    }
}

function Get-BatteryStatus {
    $percent = 0
    $isPluggedIn = $false
    $debug = @()

    try {
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        $p = [math]::Round($ps.BatteryLifePercent * 100)
        if ($p -ge 0) { $percent = [int]$p }
        $line = $ps.PowerLineStatus.ToString()
        if ($line -eq "Online") { $isPluggedIn = $true }
        $debug += "Forms:Percent=$percent,Line=$line"
    } catch {
        $debug += ("FormsErr={0}" -f $_.Exception.Message)
    }

    try {
        $batteries = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop
        if ($batteries) {
            $avg = [math]::Round((($batteries | Measure-Object -Property EstimatedChargeRemaining -Average).Average))
            if ($avg -ge 0) { $percent = [int]$avg }
            $statuses = @($batteries | ForEach-Object { [int]$_.BatteryStatus })
            # Charging/plugged statuses in Win32_Battery docs.
            if ($statuses | Where-Object { $_ -in 2,3,6,7,8,9,11 }) { $isPluggedIn = $true }
            $debug += ("Win32:Percent={0},Status={1}" -f $percent, ($statuses -join ","))
        }
    } catch {
        $debug += ("Win32Err={0}" -f $_.Exception.Message)
    }

    try {
        $wmiStatus = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
        if ($wmiStatus) {
            if (@($wmiStatus | Where-Object { $_.PowerOnline }).Count -gt 0) { $isPluggedIn = $true }
            $debug += ("WMI:PowerOnline={0}" -f ((@($wmiStatus | ForEach-Object { $_.PowerOnline }) -join ",")))
        }
    } catch {
        $debug += ("WmiErr={0}" -f $_.Exception.Message)
    }

    return @{
        Percent = $percent
        IsPluggedIn = $isPluggedIn
        Debug = ($debug -join " | ")
    }
}

# Main monitoring loop - runs silently
$firstAlertSent = $false
$secondAlertSent = $false
$firstAlertTime = $null
$lastSeenState = ""

try {
    while ($true) {
        $status = Get-BatteryStatus
        $state = "P=$($status.Percent);C=$($status.IsPluggedIn);D=$($status.Debug)"
        if ($state -ne $lastSeenState) {
            Write-Log "State changed: $state"
            $lastSeenState = $state
        }

        if ($status.Percent -ge 90 -and $status.IsPluggedIn) {
            if (-not $firstAlertSent) {
                $message = "Battery is $($status.Percent)% and still charging. Please unplug the charger."
                Show-Notification -Message $message
                $firstAlertSent = $true
                $secondAlertSent = $false
                $firstAlertTime = Get-Date
                Write-Log ("First alert sent at {0}%" -f $status.Percent)
            }
            elseif (-not $secondAlertSent -and $firstAlertTime -and (((Get-Date) - $firstAlertTime).TotalSeconds -ge 120)) {
                $message = "Battery is still charging at $($status.Percent)% after 2 minutes. Please unplug now."
                Show-Notification -Message $message
                $secondAlertSent = $true
                Write-Log ("Second alert sent at {0}%" -f $status.Percent)
            }
        }
        else {
            # Reset when charger is unplugged or battery drops below threshold.
            if ($firstAlertSent -or $secondAlertSent) {
                Write-Log "Alert state reset."
            }
            $firstAlertSent = $false
            $secondAlertSent = $false
            $firstAlertTime = $null
        }

        Start-Sleep -Seconds 30 # Check every 30 seconds
    }
}
catch {
    Write-Log ("Fatal loop error: {0}" -f $_.Exception.Message)
}
