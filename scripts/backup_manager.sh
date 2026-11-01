
#!/bin/bash

BASE="$HOME/backup-recovery-server"
BACKUP="$BASE/backups"
LOG="$BASE/logs/backup.log"
FULL_SCRIPT="$BASE/scripts/full_backup.sh"
INC_SCRIPT="$BASE/scripts/incremental_backup.sh"

mkdir -p "$BACKUP" "$BASE/logs" "$BASE/restore"
touch "$LOG"

while true; do
    echo
    echo "======================================"
    echo " CENTRALIZED BACKUP & RECOVERY SERVER"
    echo "======================================"
    echo "1. Create Full Backup"
    echo "2. Create Incremental Backup"
    echo "3. View Available Backups"
    echo "4. Verify Backup Integrity"
    echo "5. Restore Full Backup"
    echo "6. View Activity Logs"
    echo "7. Schedule Daily Backup"
    echo "8. Exit"
    echo "======================================"

    read -r -p "Enter your choice (1-8): " choice

    case "$choice" in
        1)
            bash "$FULL_SCRIPT"
            ;;
        2)
            bash "$INC_SCRIPT"
            ;;
        3)
            echo "Available backup archives:"
            find "$BACKUP" -maxdepth 1 -type f \
                \( -name 'full_*.tar.gz' -o -name 'incremental_*.tar.gz' \) \
                -printf '%f (%s bytes)\n'
            ;;
        4)
            read -r -p "Enter backup filename: " name
            if [[ "$name" == */* || -z "$name" ]]; then
                echo "Error: Enter a filename only."
            elif [[ ! "$name" =~ ^(full|incremental)_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]]; then
                echo "Error: Invalid backup filename."
            elif [[ ! -f "$BACKUP/$name.sha256" ]]; then
                echo "Error: Checksum file not found."
            else
                (cd "$BACKUP" && sha256sum -c "$name.sha256")
            fi
            ;;
        5)
            echo "Available full backups:"
            find "$BACKUP" -maxdepth 1 -type f \
                -name 'full_*.tar.gz' -printf '%f\n'
            read -r -p "Enter full backup filename: " name

            if [[ "$name" == */* || ! "$name" =~ ^full_[0-9]{8}_[0-9]{6}\.tar\.gz$ ]] ||
               [[ ! -f "$BACKUP/$name" || ! -f "$BACKUP/$name.sha256" ]]; then
                echo "Error: Valid full backup not found."
            elif (cd "$BACKUP" && sha256sum -c "$name.sha256") &&
                 tar -tzf "$BACKUP/$name" >/dev/null 2>&1; then
                destination="$BASE/restore/recovered_$(date +%Y%m%d_%H%M%S)"
                mkdir -p "$destination"
                if tar -xzf "$BACKUP/$name" -C "$destination"; then
                    echo "Recovery completed successfully."
                    echo "Recovered files: $destination"
                    echo "$(date): Restored $name to $destination" >> "$LOG"
                else
                    echo "Error: Recovery failed."
                    rmdir "$destination" 2>/dev/null
                fi
            else
                echo "Error: Backup verification or archive test failed."
            fi
            ;;
        6)
            echo "Recent activity:"
            tail -n 20 "$LOG"
            ;;
        7)
            if ! command -v crontab >/dev/null 2>&1; then
                echo "Cron tools are not installed."
                echo "Run: sudo apt update && sudo apt install cron"
            elif crontab -l 2>/dev/null |
                grep -Fq "$FULL_SCRIPT"; then
                echo "A daily full backup is already scheduled."
            else
                (crontab -l 2>/dev/null
                 echo "0 20 * * * $FULL_SCRIPT") | crontab -
                if [ $? -eq 0 ]; then
                    echo "Daily full backup scheduled for 8:00 PM."
                else
                    echo "Error: Could not schedule backup."
                fi
            fi
            ;;
        8)
            echo "Thank you for using the Backup & Recovery Server."
            break
            ;;
        *)
            echo "Invalid choice! Please enter a number from 1 to 8."
            echo "$(date): Invalid menu choice: $choice" >> "$LOG"
            ;;
    esac
done
