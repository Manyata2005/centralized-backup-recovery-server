#!/bin/bash

SOURCE="$HOME/backup-recovery-server/source_data"
BACKUP="$HOME/backup-recovery-server/backups"
LOG="$HOME/backup-recovery-server/logs/backup.log"

mkdir -p "$BACKUP"

echo "Starting full backup..."

if [ ! -d "$SOURCE" ] || [ -z "$(find "$SOURCE" -type f -print -quit)" ]; then
    echo "Error: Source folder is missing or empty."
    exit 1
fi

FILE="$BACKUP/full_$(date +%Y%m%d_%H%M%S).tar.gz"

if tar -czf "$FILE" -C "$SOURCE" .; then
    sha256sum "$FILE" > "$FILE.sha256"
    echo "$(date): Full backup successful - $FILE" >> "$LOG"
    echo "Backup completed successfully!"
    echo "Backup saved at: $FILE"
    echo "Checksum file created."
else
    echo "Error: Backup failed."
    rm -f "$FILE"
    echo "$(date): Full backup failed" >> "$LOG"
    exit 1
fi
