# Battery Monitor Script
# Runs silently in background. Alerts via Windows toast when battery >= 90% while charging.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Hide any console window immediately ──────────────────────────────────────
Add-Type -Name WinAPI -Namespace Native -MemberDefinition @"
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
"@
[Native.WinAPI]::ShowWindowAsync([Native.WinAPI]::GetConsoleWindow(), 0) | Out-Null

# ── Logging ───────────────────────────────────────────────────────────────────
$logPath = "$env:TEMP\BatteryMonitor.log"
function Write-Log([string]$msg) {
    try { Add-Content -Path $logPath -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) } catch {}
}

# ── Single-instance guard (mutex) ────────────────────────────────────────────
$mutex = New-Object System.Threading.Mutex($false, "Global\BatteryMonitorMutex")
if (-not $mutex.WaitOne(0, $false)) {
    Write-Log "Another instance already running. Exiting."
    exit
}
Write-Log "Battery Monitor started."

# ── Auto-start: add to HKCU Run key so it launches silently at every logon ───
$scriptPath = $MyInvocation.MyCommand.Path
$runKey     = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runValue   = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$scriptPath`""
try {
    Set-ItemProperty -Path $runKey -Name "BatteryMonitor" -Value $runValue -Force
    Write-Log "Run key set."
} catch {
    Write-Log "Run key failed: $($_.Exception.Message)"
}

# ── Toast notification (no tray icon, no popup, no dialog) ───────────────────
function Show-Toast([string]$title, [string]$body) {
    try {
        # Use Windows.UI.Notifications via WinRT COM bridge
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                    [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $nodes = $xml.GetElementsByTagName("text")
        $nodes.Item(0).AppendChild($xml.CreateTextNode($title)) | Out-Null
        $nodes.Item(1).AppendChild($xml.CreateTextNode($body))  | Out-Null

        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(
            "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
        ).Show($toast)

        Write-Log "Toast shown: $title | $body"
        return $true
    } catch {
        Write-Log "Toast failed: $($_.Exception.Message)"
        return $false
    }
}

# Fallback: tray balloon (still silent — no popup/dialog)
function Show-Balloon([string]$title, [string]$body) {
    try {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information
        $ni.BalloonTipTitle = $title
        $ni.BalloonTipText  = $body
        $ni.BalloonTipIcon  = "Info"
        $ni.Visible = $true
        $ni.ShowBalloonTip(6000)
        Start-Sleep -Seconds 7
        $ni.Dispose()
        Write-Log "Balloon shown: $title | $body"
    } catch {
        Write-Log "Balloon failed: $($_.Exception.Message)"
    }
}

function Show-Notification([string]$title, [string]$body) {
    if (-not (Show-Toast $title $body)) {
        Show-Balloon $title $body
    }
}

# ── Battery status ────────────────────────────────────────────────────────────
function Get-BatteryStatus {
    $percent    = 0
    $isCharging = $false

    # Primary: Win32_Battery (most reliable for charging state)
    try {
        $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($bat) {
            $percent    = [int][math]::Round(($bat | Measure-Object EstimatedChargeRemaining -Average).Average)
            # BatteryStatus 2 = Charging, 6 = Charging+High, 7 = Charging+Low, 8 = Charging+Critical
            $isCharging = ($bat | Where-Object { $_.BatteryStatus -in 2,6,7,8,9,11 }).Count -gt 0
        }
    } catch { Write-Log "Win32_Battery error: $($_.Exception.Message)" }

    # Cross-check with PowerStatus
    try {
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        $pct = [int][math]::Round($ps.BatteryLifePercent * 100)
        if ($pct -gt 0 -and $pct -le 100) { $percent = $pct }
        if ($ps.PowerLineStatus -eq "Online") { $isCharging = $true }
    } catch {}

    return @{ Percent = $percent; IsCharging = $isCharging }
}

# ── Main loop ─────────────────────────────────────────────────────────────────
$alertSentAt   = $null   # time first alert was sent for current charging session
$reminderSent  = $false

try {
    while ($true) {
        $s = Get-BatteryStatus

        if ($s.Percent -ge 90 -and $s.IsCharging) {
            if ($null -eq $alertSentAt) {
                # First alert
                Show-Notification "🔋 Unplug Charger" "Battery is at $($s.Percent)% and still charging. Please unplug."
                $alertSentAt  = Get-Date
                $reminderSent = $false
                Write-Log "Alert 1 sent at $($s.Percent)%"
            }
            elseif (-not $reminderSent -and ((Get-Date) - $alertSentAt).TotalMinutes -ge 5) {
                # Reminder after 5 minutes if still charging
                Show-Notification "🔋 Still Charging!" "Battery is at $($s.Percent)%. Unplug the charger to protect battery health."
                $reminderSent = $true
                Write-Log "Alert 2 (reminder) sent at $($s.Percent)%"
            }
        }
        else {
            # Reset when unplugged or drops below 90%
            if ($null -ne $alertSentAt) { Write-Log "Alert state reset (Percent=$($s.Percent), Charging=$($s.IsCharging))" }
            $alertSentAt  = $null
            $reminderSent = $false
        }

        Start-Sleep -Seconds 60   # check every 60 seconds
    }
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)"
    $mutex.ReleaseMutex()
}
