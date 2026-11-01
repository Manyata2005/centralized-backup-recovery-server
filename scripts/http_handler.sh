
#!/usr/bin/env bash

# Centralized Backup & Recovery Server - HTTP Handler
BASE="${BASE:-$HOME/backup-recovery-server}"
PORT="${PORT:-8765}"

B="$BASE/backups"
L="$BASE/logs"
W="$BASE/dashboard"
R="$BASE/restore"
S="$BASE/.run/verify.status"
OPS="$L/dashboard_ops.log"
TAG="# backup-recovery-dashboard"

mkdir -p "$B" "$L" "$R" "$BASE/.run"

shopt -s nullglob

esc() {
    printf '%s' "$1" |
        sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\t/ /g;s/\r//g;s/\n/\\n/g'
}

send() {
    local n
    n=$(printf '%s' "$3" | wc -c)
    printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n%s' \
        "$1" "$2" "$n" "$3"
}

json() {
    send "${2:-200 OK}" "application/json" "$1"
}

fail() {
    json "{\"ok\":false,\"message\":\"$(esc "$1")\"}" "${2:-400 Bad Request}"
}

log() {
    printf '%s | %s\n' "$(date '+%F %T')" "$1" >> "$OPS"
}

btype() {
    case "${1,,}" in
        *full*) echo Full ;;
        *incr*) echo Incremental ;;
        *) echo Unknown ;;
    esac
}

valid() {
    if [[ ! "$F" =~ ^[A-Za-z0-9._-]+\.tar\.gz$ || "$F" == *..* ]]; then
        fail "Invalid backup filename - rejected"
        return 1
    fi

    if [[ ! -f "$B/$F" ]]; then
        fail "Backup archive missing: $F"
        return 1
    fi
}

# Read one HTTP request and its headers.
IFS= read -r -t 10 line || exit 1
line=${line%$'\r'}
read -r M T _ <<< "$line"

H=""
TK=""

while IFS= read -r -t 10 h; do
    h=${h%$'\r'}
    [[ -z "$h" ]] && break

    case "${h%%:*}" in
        [Hh]ost) H=$(printf '%s' "${h#*:}" | sed 's/^ *//') ;;
        [Xx]-[Tt]oken) TK=$(printf '%s' "${h#*:}" | sed 's/^ *//') ;;
    esac
done

if [[ "$H" != "127.0.0.1:$PORT" && "$H" != "localhost:$PORT" ]]; then
    fail "Bad Host header" "403 Forbidden"
    exit
fi

P=${T%%\?*}
Q=""
[[ "$T" == *\?* ]] && Q=${T#*\?}

F=""
[[ "$Q" =~ (^|&)file=([^&]*) ]] && F=${BASH_REMATCH[2]}

CONFIRM=""
[[ "$Q" =~ (^|&)confirm=yes($|&) ]] && CONFIRM=yes

# Serve the dashboard files.
case "$P" in
    /|/index.html)
        send "200 OK" "text/html; charset=utf-8" "$(cat "$W/index.html")"
        exit
        ;;
    /style.css)
        send "200 OK" "text/css; charset=utf-8" "$(cat "$W/style.css")"
        exit
        ;;
    /app.js)
        send "200 OK" "application/javascript; charset=utf-8" "$(cat "$W/app.js")"
        exit
        ;;
esac

[[ "$P" == /api/* ]] || {
    fail "Not found" "404 Not Found"
    exit
}

if [[ -z "${DASH_TOKEN:-}" || "$TK" != "$DASH_TOKEN" ]]; then
    fail "Unauthorized" "401 Unauthorized"
    exit
fi

post() {
    if [[ "$M" != POST ]]; then
        fail "POST required" "405 Method Not Allowed"
        return 1
    fi
}

run_backup() {
    local sc="$BASE/scripts/$2"
    local out rc ok=false

    if [[ ! -f "$sc" ]]; then
        fail "Script missing: scripts/$2"
        return
    fi

    out=$(cd "$BASE" && timeout 300 bash "$sc" </dev/null 2>&1)
    rc=$?

    if (( rc == 124 )); then
        out+=$'\nTimed out after 300 seconds'
    fi

    if (( rc == 0 )); then
        ok=true
        log "BACKUP | $1 | SUCCESS"
    else
        log "BACKUP | $1 | FAILED (rc=$rc)"
    fi

    json "{\"ok\":$ok,\"message\":\"$1 backup $([[ "$ok" == true ]] && echo completed || echo FAILED)\",\"output\":\"$(esc "$out")\"}"
}

case "$P" in
    /api/status)
        nf=0
        ni=0
        fs=("$B"/*.tar.gz)

        for f in "${fs[@]}"; do
            case "$(btype "${f##*/}")" in
                Full) ((nf++)) ;;
                Incremental) ((ni++)) ;;
            esac
        done

        last=$(ls -t "$B"/*.tar.gz 2>/dev/null | head -1)
        lt=""
        [[ -n "$last" ]] && lt=$(stat -c %y "$last" | cut -c1-19)

        ls_=$(grep 'BACKUP' "$OPS" 2>/dev/null | tail -1 | awk -F' \| ' '{print $3}')
        rec=$(tail -n 8 "$OPS" 2>/dev/null)

        json "{\"ok\":true,\"full\":$nf,\"incr\":$ni,\"total\":${#fs[@]},\"latest_time\":\"$(esc "$lt")\",\"latest_status\":\"$(esc "$ls_")\",\"recent\":\"$(esc "$rec")\"}"
        ;;

    /api/history)
        rows=""
        mapfile -t fs < <(ls -t "$B"/*.tar.gz 2>/dev/null)

        for f in "${fs[@]}"; do
            n=${f##*/}
            v=$(awk -F'|' -v n="$n" '$1==n {r=$2} END {print r}' "$S" 2>/dev/null)

            rows+="{\"name\":\"$(esc "$n")\",\"type\":\"$(btype "$n")\",\"size\":$(stat -c %s "$f"),\"time\":\"$(stat -c %y "$f" | cut -c1-19)\",\"verified\":\"$(esc "$v")\"},"
        done

        json "{\"ok\":true,\"items\":[${rows%,}]}"
        ;;

    /api/logs)
        lf="$L/backup.log"

        if [[ ! -f "$lf" ]]; then
            for x in "$L"/*.log; do
                [[ "$x" == */dashboard_ops.log || "$x" == */cron.log ]] && continue
                lf="$x"
                break
            done
        fi

        if [[ ! -f "$lf" ]]; then
            fail "No log file found in logs/"
            exit
        fi

        json "{\"ok\":true,\"file\":\"${lf##*/}\",\"text\":\"$(esc "$(tail -n 60 "$lf")")\"}"
        ;;

    /api/cron)
        command -v crontab >/dev/null || {
            fail "crontab is not installed"
            exit
        }

        entries=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$')
        ours=$(crontab -l 2>/dev/null | grep -F "$TAG")
        service=$(systemctl is-active cron 2>/dev/null)

        json "{\"ok\":true,\"entries\":\"$(esc "$entries")\",\"ours\":\"$(esc "$ours")\",\"service\":\"$(esc "$service")\"}"
        ;;

    /api/backup_full)
        post && run_backup Full full_backup.sh
        ;;

    /api/backup_incr)
        post && run_backup Incremental incremental_backup.sh
        ;;

    /api/verify)
        post || exit
        valid || exit

        CS="$B/$F.sha256"
        [[ -f "$CS" ]] || CS="$B/${F%.tar.gz}.sha256"

        if [[ ! -f "$CS" ]]; then
            fail "Checksum file missing for $F"
            exit
        fi

        out=$(cd "$B" && timeout 120 sha256sum -c "$CS" 2>&1)
        rc=$?

        res=OK
        ok=true
        msg="Checksum verified: $F"

        if (( rc != 0 )); then
            res=FAILED
            ok=false
            msg="Checksum mismatch or verification error: $F"
        fi

        echo "$F|$res|$(date '+%F %T')" >> "$S"
        log "VERIFY | $F | $res"

        json "{\"ok\":$ok,\"message\":\"$(esc "$msg")\",\"output\":\"$(esc "$out")\"}"
        ;;

    /api/restore)
        post || exit
        valid || exit

        if [[ "$(btype "$F")" != Full ]]; then
            fail "Only full backups can be restored"
            exit
        fi

        if [[ "$CONFIRM" != yes ]]; then
            fail "Confirmation required"
            exit
        fi

        CS="$B/$F.sha256"
        [[ -f "$CS" ]] || CS="$B/${F%.tar.gz}.sha256"

        if [[ ! -f "$CS" ]] || ! (cd "$B" && sha256sum -c "$CS" >/dev/null 2>&1); then
            fail "Backup checksum verification failed"
            exit
        fi

        d="$R/restore_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$d" || {
            fail "Could not create restore directory"
            exit
        }

        if out=$(timeout 300 tar -tzf "$B/$F" 2>&1) &&
           out=$(timeout 300 tar -xzf "$B/$F" -C "$d" 2>&1); then
            n=$(find "$d" -type f | wc -l)
            log "RESTORE | $F | SUCCESS -> $d"
            json "{\"ok\":true,\"message\":\"Restored $n files to $(esc "$d")\",\"output\":\"$(esc "$(find "$d" -type f | head -30)")\"}"
        else
            log "RESTORE | $F | FAILED"
            fail "Restore failed: $out"
        fi
        ;;

    /api/schedule)
        post || exit

        if [[ "$CONFIRM" != yes ]]; then
            fail "Confirmation required"
            exit
        fi

        command -v crontab >/dev/null || {
            fail "crontab is not installed"
            exit
        }

        line="0 20 * * * $BASE/scripts/full_backup.sh >> $L/cron.log 2>&1 $TAG"

        if { crontab -l 2>/dev/null | grep -vF "$TAG"; echo "$line"; } | crontab -; then
            log "SCHEDULE | daily 20:00 | SUCCESS"
            json "{\"ok\":true,\"message\":\"Daily 8:00 PM backup scheduled; unrelated jobs preserved\"}"
        else
            fail "Failed to update crontab"
        fi
        ;;

    *)
        fail "Invalid operation" "404 Not Found"
        ;;
esac
