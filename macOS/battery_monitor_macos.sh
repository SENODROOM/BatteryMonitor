#!/bin/bash

# Battery Monitor Script for macOS
# Notifies when battery > 90% and plugged in

# Get battery status
get_battery_status() {
    local battery_info=$(pmset -g batt)
    local percentage=$(echo "$battery_info" | grep -o '[0-9]*%' | grep -o '[0-9]*')
    local state=$(echo "$battery_info" | grep -o 'charging\|discharging\|charged')
    
    # Check if plugged in (charging or charged)
    local is_plugged_in=false
    if [[ "$state" == "charging" || "$state" == "charged" ]]; then
        is_plugged_in=true
    fi
    
    echo "$percentage:$is_plugged_in"
}

# Show notification
show_notification() {
    local message="$1"
    osascript -e "display notification \"$message\" with title \"Battery Alert\" subtitle \"Battery Health Monitor\""
    echo "NOTIFICATION: $message"
}

# Main monitoring loop
main() {
    echo "Battery monitor started. Press Ctrl+C to stop."
    echo "Monitoring for battery > 90% while plugged in..."
    
    local last_notification_time=0
    local notification_cooldown=300 # 5 minutes
    
    while true; do
        local status=$(get_battery_status)
        local percentage=$(echo "$status" | cut -d: -f1)
        local is_plugged_in=$(echo "$status" | cut -d: -f2)
        local current_time=$(date +%s)
        
        echo "Battery: ${percentage}% | Plugged In: $is_plugged_in"
        
        if [[ $percentage -gt 90 && $is_plugged_in == "true" ]]; then
            if [[ $((current_time - last_notification_time)) -gt $notification_cooldown ]]; then
                local message="Battery is ${percentage}% and still plugged in. Consider unplugging to preserve battery health."
                show_notification "$message"
                last_notification_time=$current_time
            fi
        fi
        
        sleep 30 # Check every 30 seconds
    done
}

main
