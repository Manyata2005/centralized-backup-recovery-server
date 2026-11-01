#!/bin/bash

SOURCE="$HOME/backup-recovery-server/source_data"
BACKUP="$HOME/backup-recovery-server/backups"
LOG="$HOME/backup-recovery-server/logs/backup.log"
SNAPSHOT="$BACKUP/incremental.snapshot"

mkdir -p "$BACKUP"

echo "Starting incremental backup..."

if [ ! -d "$SOURCE" ] || [ -z "$(find "$SOURCE" -type f -print -quit)" ]; then
    echo "Error: Source folder is missing or empty."
    exit 1
fi

FILE="$BACKUP/incremental_$(date +%Y%m%d_%H%M%S).tar.gz"

if tar --listed-incremental="$SNAPSHOT" -czf "$FILE" -C "$SOURCE" .; then
    sha256sum "$FILE" > "$FILE.sha256"
    echo "$(date): Incremental backup successful - $FILE" >> "$LOG"
    echo "Incremental backup completed successfully!"
    echo "Backup saved at: $FILE"
else
    echo "Error: Incremental backup failed."
    rm -f "$FILE"
    echo "$(date): Incremental backup failed" >> "$LOG"
    exit 1
fi
