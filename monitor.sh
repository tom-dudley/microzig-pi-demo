#!/bin/bash
# Wait for USB modem and output its contents with timestamps

LOGFILE="monitor.log"

echo "Waiting for USB modem... (logging to $LOGFILE)"

while true; do
    # Use cu.* instead of tty.* - cu doesn't wait for DCD
    MODEM=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
    if [ -n "$MODEM" ]; then
        echo "[$(date '+%H:%M:%S')] Found: $MODEM" | tee -a "$LOGFILE"
        echo "[$(date '+%H:%M:%S')] --- Output ---" | tee -a "$LOGFILE"
        stty -f "$MODEM" 115200 raw
        cat "$MODEM" | while IFS= read -r line; do
            echo "[$(date '+%H:%M:%S')] $line" | tee -a "$LOGFILE"
        done
        echo "[$(date '+%H:%M:%S')] --- Disconnected ---" | tee -a "$LOGFILE"
        echo "Waiting for USB modem..."
    fi
    sleep 0.1
done
