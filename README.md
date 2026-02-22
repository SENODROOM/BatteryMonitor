# Battery Monitor - Cross-Platform Battery Health Monitor

A lightweight battery monitoring tool that alerts you when your laptop battery exceeds 90% while still plugged in, helping preserve battery health.

## Features

- **Cross-platform support**: Windows, Linux, and macOS
- **Smart notifications**: Alerts only when battery > 90% AND plugged in
- **Cooldown system**: 5-minute delay between notifications to prevent spam
- **Automatic startup**: Configured to run silently in background at system boot
- **Lightweight**: Minimal resource usage
- **Background execution**: Runs completely hidden without console window

## Quick Start

### Windows 🪟

1. **Run immediately**:
   ```bash
   # Double-click this file or run from command line
   BatteryMonitor.bat
   ```

2. **Install for automatic startup**:
   - Registry entry automatically configured for silent background execution
   - BatteryMonitor will launch automatically when Windows starts
   - Runs completely hidden without console window

3. **Stop monitoring**:
   - Remove from startup: `powershell -Command "Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BatteryMonitor'"`
   - Stop current process: `taskkill /f /im powershell.exe`

### Linux 🐧

1. **Install dependencies** (Ubuntu/Debian):
   ```bash
   sudo apt install upower libnotify-bin
   ```

2. **Make script executable**:
   ```bash
   chmod +x battery_monitor_linux.sh
   ```

3. **Run the monitor**:
   ```bash
   ./battery_monitor_linux.sh
   ```

4. **Install for automatic startup** (optional):
   ```bash
   # Create a systemd service
   sudo cp battery_monitor_linux.sh /usr/local/bin/
   sudo tee /etc/systemd/system/battery-monitor.service > /dev/null <<EOF
   [Unit]
   Description=Battery Health Monitor
   After=graphical-session.target

   [Service]
   Type=simple
   ExecStart=/usr/local/bin/battery_monitor_linux.sh
   Restart=always
   User=$USER

   [Install]
   WantedBy=graphical-session.target
   EOF

   sudo systemctl enable battery-monitor.service
   sudo systemctl start battery-monitor.service
   ```

### macOS 🍎

1. **Make script executable**:
   ```bash
   chmod +x battery_monitor_macos.sh
   ```

2. **Run the monitor**:
   ```bash
   ./battery_monitor_macos.sh
   ```

3. **Install for automatic startup** (optional):
   ```bash
   # Create a launch agent
   mkdir -p ~/Library/LaunchAgents
   cat > ~/Library/LaunchAgents/com.user.batterymonitor.plist <<EOF
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.user.batterymonitor</string>
       <key>ProgramArguments</key>
       <array>
           <string>$PWD/battery_monitor_macos.sh</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   EOF

   launchctl load ~/Library/LaunchAgents/com.user.batterymonitor.plist
   ```

## How It Works

- **Monitoring interval**: Checks battery status every 30 seconds
- **Notification trigger**: Battery > 90% AND plugged in
- **Notification cooldown**: 5 minutes between alerts
- **Battery health**: Helps prevent overcharging and extends battery lifespan
- **Background operation**: Runs silently in system background without user intervention

## File Structure

```
BatteryMonitor/
├── README.md                    # This file
├── Windows/
│   ├── BatteryMonitor.ps1       # PowerShell monitoring script
│   ├── BatteryMonitor.bat        # Manual launcher (visible console)
│   └── BatteryMonitorStartup.bat # Silent startup launcher
├── Linux/
│   └── battery_monitor_linux.sh  # Bash monitoring script
└── macOS/
    └── battery_monitor_macos.sh  # Bash monitoring script
```

## Troubleshooting

### Windows
- **PowerShell execution policy**: If script doesn't run, right-click PowerShell and "Run as Administrator", then run:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

### Linux
- **Missing dependencies**: Install `upower` and `libnotify-bin`
- **No notifications**: Check that your desktop environment supports `notify-send`

### macOS
- **Permissions**: Allow Terminal to send notifications in System Preferences > Security & Privacy > Notifications
- **No battery info**: Some Macs may require different battery detection methods

## Customization

You can modify these settings in any script:
- **Battery threshold**: Change `90` to your preferred percentage
- **Check interval**: Change `30` (seconds) for more/less frequent checks
- **Notification cooldown**: Change `300` (seconds) for different alert frequency

## Why 90%?

Most lithium-ion batteries benefit from avoiding full charges:
- 80-90% charging reduces battery stress
- Avoids heat buildup from overcharging
- Extends overall battery lifespan
- Maintains better long-term capacity

## Support

For issues or feature requests, check the platform-specific troubleshooting sections above.
