#!/usr/bin/env bash
# Usage: PORT=9000 ./scripts/launch_dashboard.sh   (default port 8765)
export BASE="${BASE:-$HOME/backup-recovery-server}"; export PORT="${PORT:-8765}"
cd "$BASE" 2>/dev/null || { echo "Project dir not found: $BASE"; exit 1; }
miss=0; for c in socat tar sha256sum find crontab timeout sed ss; do command -v $c >/dev/null || { echo "Missing: $c"; miss=1; }; done
((miss)) && { echo "Run: sudo apt update && sudo apt install -y socat cron"; exit 1; }
for f in scripts/full_backup.sh scripts/incremental_backup.sh scripts/http_handler.sh dashboard/index.html; do
 [[ -f $f ]] || { echo "Missing file: $f"; exit 1; }; done
mkdir -p backups logs restore .run
ss -ltn "sport = :$PORT" | grep -q LISTEN && { echo "Port $PORT busy. Try: PORT=9000 $0"; exit 1; }
export DASH_TOKEN=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
socat TCP-LISTEN:$PORT,bind=127.0.0.1,reuseaddr,fork EXEC:"bash $BASE/scripts/http_handler.sh" &
SP=$!; trap 'kill $SP 2>/dev/null; echo "Server stopped."' EXIT; trap 'exit 0' INT TERM
sleep 1; kill -0 $SP 2>/dev/null || { echo "Server failed to start"; exit 1; }
URL="http://127.0.0.1:$PORT/#$DASH_TOKEN"
echo "Dashboard running (localhost only). Press Ctrl+C to stop."
xdg-open "$URL" >/dev/null 2>&1 || echo "Open manually: $URL"
wait $SP
