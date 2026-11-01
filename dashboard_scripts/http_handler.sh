#!/usr/bin/env bash
# Handles ONE HTTP request (spawned by socat). Fixed allowlist of operations only.
BASE="${BASE:-$HOME/backup-recovery-server}"; PORT="${PORT:-8765}"
B="$BASE/backups"; L="$BASE/logs"; W="$BASE/dashboard"; R="$BASE/restore"
S="$BASE/.run/verify.status"; OPS="$L/dashboard_ops.log"; TAG="# backup-recovery-dashboard"
shopt -s nullglob
esc(){ printf '%s' "$1" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\t/ /g;s/\r//g;s/\n/\\n/g'; }
send(){ local n; n=$(printf '%s' "$3" | wc -c)
 printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n%s' "$1" "$2" "$n" "$3"; }
json(){ send "${2:-200 OK}" "application/json" "$1"; }
fail(){ json "{\"ok\":false,\"message\":\"$(esc "$1")\"}" "${2:-200 OK}"; }
log(){ echo "$(date '+%F %T') | $1" >> "$OPS"; }
btype(){ case "${1,,}" in *full*) echo Full;; *incr*) echo Incremental;; *) echo Unknown;; esac; }
valid(){ [[ $F =~ ^[A-Za-z0-9._-]+\.tar\.gz$ && $F != *..* ]] || { fail "Invalid backup filename - rejected"; return 1; }
 [[ -f $B/$F ]] || { fail "Backup archive missing: $F"; return 1; }; }

read -r -t 10 line; line=${line%$'\r'}; read -r M T _ <<<"$line"
H=""; TK=""
while read -r -t 10 h; do h=${h%$'\r'}; [[ -z $h ]] && break
 case "${h%%:*}" in [Hh]ost) H=${h#*: };; [Xx]-[Tt]oken) TK=${h#*: };; esac; done
[[ $H == "127.0.0.1:$PORT" || $H == "localhost:$PORT" ]] || { fail "Bad Host header" "403 Forbidden"; exit; }
P=${T%%\?*}; Q=""; [[ $T == *\?* ]] && Q=${T#*\?}
F=""; [[ $Q =~ (^|\&)file=([^\&]*) ]] && F=${BASH_REMATCH[2]}
CONFIRM=""; [[ $Q =~ (^|\&)confirm=yes($|\&) ]] && CONFIRM=yes

case "$P" in
 /|/index.html) send "200 OK" "text/html; charset=utf-8" "$(cat "$W/index.html")"; exit;;
 /style.css) send "200 OK" "text/css" "$(cat "$W/style.css")"; exit;;
 /app.js) send "200 OK" "application/javascript" "$(cat "$W/app.js")"; exit;;
esac
[[ $P == /api/* ]] || { fail "Not found" "404 Not Found"; exit; }
[[ -n $DASH_TOKEN && $TK == "$DASH_TOKEN" ]] || { fail "Unauthorized" "401 Unauthorized"; exit; }
post(){ [[ $M == POST ]] || { fail "POST required" "405 Method Not Allowed"; return 1; }; }

run_backup(){ local sc="$BASE/scripts/$2" out rc ok=false
 [[ -f $sc ]] || { fail "Script missing: scripts/$2"; return; }
 out=$(cd "$BASE" && timeout 300 bash "$sc" </dev/null 2>&1); rc=$?
 ((rc==124)) && out+=$'\nTimed out after 300s'
 ((rc==0)) && ok=true
 log "BACKUP | $1 | $($ok && echo SUCCESS || echo "FAILED (rc=$rc)")"
 json "{\"ok\":$ok,\"message\":\"$1 backup $($ok && echo completed || echo FAILED)\",\"output\":\"$(esc "$out")\"}"; }

case "$P" in
/api/status)
 nf=0; ni=0; fs=("$B"/*.tar.gz)
 for f in "${fs[@]}"; do case $(btype "${f##*/}") in Full) ((nf++));; Incremental) ((ni++));; esac; done
 last=$(ls -t "$B"/*.tar.gz 2>/dev/null | head -1); lt=""; [[ -n $last ]] && lt=$(stat -c %y "$last" | cut -c1-19)
 ls_=$(grep 'BACKUP' "$OPS" 2>/dev/null | tail -1 | awk -F' \\| ' '{print $4}'); rec=$(tail -n 8 "$OPS" 2>/dev/null)
 json "{\"ok\":true,\"full\":$nf,\"incr\":$ni,\"total\":${#fs[@]},\"latest_time\":\"$(esc "$lt")\",\"latest_status\":\"$(esc "$ls_")\",\"recent\":\"$(esc "$rec")\"}";;
/api/history)
 rows=""; mapfile -t fs < <(ls -t "$B"/*.tar.gz 2>/dev/null)
 for f in "${fs[@]}"; do n=${f##*/}
  v=$(awk -F'|' -v n="$n" '$1==n{r=$2}END{print r}' "$S" 2>/dev/null)
  rows+="{\"name\":\"$(esc "$n")\",\"type\":\"$(btype "$n")\",\"size\":$(stat -c %s "$f"),\"time\":\"$(stat -c %y "$f" | cut -c1-19)\",\"verified\":\"$v\"},"
 done; json "{\"ok\":true,\"items\":[${rows%,}]}";;
/api/logs)
 lf="$L/backup.log"; [[ -f $lf ]] || for x in "$L"/*.log; do [[ $x != */dashboard_ops.log && $x != */cron.log ]] && { lf=$x; break; }; done
 [[ -f $lf ]] || { fail "No log file found in logs/"; exit; }
 json "{\"ok\":true,\"file\":\"${lf##*/}\",\"text\":\"$(esc "$(tail -n 60 "$lf")")\"}";;
/api/cron)
 command -v crontab >/dev/null || { fail "crontab not installed (sudo apt install cron)"; exit; }
 json "{\"ok\":true,\"entries\":\"$(esc "$(crontab -l 2>/dev/null | grep -v '^#[^ ]' | grep -v '^$')")\",\"ours\":\"$(esc "$(crontab -l 2>/dev/null | grep -F "$TAG")")\",\"service\":\"$(systemctl is-active cron 2>/dev/null)\"}";;
/api/backup_full) post && run_backup Full full_backup.sh;;
/api/backup_incr) post && run_backup Incremental incremental_backup.sh;;
/api/verify)
 post || exit; valid || exit; CS="$B/$F.sha256"; [[ -f $CS ]] || CS="$B/${F%.tar.gz}.sha256"
 [[ -f $CS ]] || { fail "Checksum file missing for $F"; exit; }
 out=$(cd "$B" && timeout 120 sha256sum -c "$CS" 2>&1); rc=$?; res=OK; ((rc)) && res=FAILED
 mkdir -p "$BASE/.run"; echo "$F|$res|$(date '+%F %T')" >> "$S"; log "VERIFY | $F | $res"
 json "{\"ok\":$((rc==0?1:0))$(:),\"message\":\"$([ $res = OK ] && echo "Checksum verified: $F" || echo "CHECKSUM MISMATCH or error: $F")\",\"output\":\"$(esc "$out")\"}" | sed 's/"ok":1/"ok":true/;s/"ok":0/"ok":false/';;
/api/restore)
 post || exit; valid || exit
 [[ $(btype "$F") == Full ]] || { fail "Only full backups can be restored"; exit; }
 [[ $CONFIRM == yes ]] || { fail "Confirmation required"; exit; }
 d="$R/restore_$(date +%Y%m%d_%H%M%S)"; mkdir -p "$d" && out=$(timeout 300 tar -xzf "$B/$F" -C "$d" 2>&1); rc=$?
 if ((rc==0)); then log "RESTORE | $F | SUCCESS -> $d"; n=$(find "$d" -type f | wc -l)
  json "{\"ok\":true,\"message\":\"Restored $n files to $(esc "$d")\",\"output\":\"$(esc "$(find "$d" -type f | head -30)")\"}"
 else log "RESTORE | $F | FAILED"; fail "Restore failed: $out"; fi;;
/api/schedule)
 post || exit; [[ $CONFIRM == yes ]] || { fail "Confirmation required"; exit; }
 command -v crontab >/dev/null || { fail "crontab not installed"; exit; }
 line="0 20 * * * $BASE/scripts/full_backup.sh >> $L/cron.log 2>&1 $TAG"
 { crontab -l 2>/dev/null | grep -vF "$TAG"; echo "$line"; } | crontab - \
  && { log "SCHEDULE | daily 20:00 | SUCCESS"; json "{\"ok\":true,\"message\":\"Daily 8:00 PM backup scheduled (no duplicates, other jobs kept)\"}"; } \
  || fail "Failed to update crontab";;
*) fail "Invalid operation" "404 Not Found";;
esac
