#!/usr/bin/env bash
# Keeps a BloBnot vault in sync with Google Drive (or any rclone remote).
#
# The vault lives in an ordinary local folder, so BloBnot stays fast and works
# offline; rclone bisync copies changes both ways every few minutes. (GNOME's
# own Google Drive integration shows files under internal IDs instead of their
# names, so the app cannot use it.)
#
#   blobnot-sync-setup                 set everything up, asking as it goes
#   blobnot-sync-setup --run           one sync now (what the timer runs)
#   blobnot-sync-setup --status        show the setup and the last runs
#   blobnot-sync-setup --uninstall     stop syncing (files are kept)
#
# Setup options:
#   --remote REMOTE:PATH   default gdrive:BLOB/BloknotVault
#   --local DIR            default ~/BloBnot-Vault
#   --every MINUTES        default 5
#   --no-config            do not create the rclone remote
#   --no-systemd           do not install the timer (sync once and stop)
set -euo pipefail

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/blobnot"
CONF="$CONF_DIR/sync.env"
MARK="$CONF_DIR/sync.initialized"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
MIN_RCLONE="1.58" # first release with bisync

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf 'blobnot-sync: %s\n' "$*" >&2; exit 1; }

version_ge() { # version_ge 1.66 1.58 → true
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

rclone_version() {
  rclone version 2>/dev/null | head -n1 | sed -E 's/^rclone v?([0-9]+\.[0-9]+).*/\1/'
}

need_rclone() {
  command -v rclone >/dev/null || die "rclone is not installed.
  Ubuntu/Debian:  sudo apt install rclone
  Newest version: sudo -v && curl https://rclone.org/install.sh | sudo bash"
  local v
  v="$(rclone_version)"
  version_ge "$v" "$MIN_RCLONE" ||
    die "rclone $v is too old for two-way sync (need $MIN_RCLONE or newer).
  Update: sudo -v && curl https://rclone.org/install.sh | sudo bash"
}

load_conf() {
  [ -f "$CONF" ] || die "not set up yet — run: blobnot-sync-setup"
  # shellcheck source=/dev/null
  . "$CONF"
  if [ -z "${REMOTE:-}" ] || [ -z "${LOCAL:-}" ]; then
    die "$CONF is incomplete"
  fi
}

# ---------- one sync (the timer calls this) ----------
run_sync() {
  need_rclone
  load_conf
  mkdir -p "$LOCAL"
  local args=(
    bisync "$LOCAL" "$REMOTE"
    --drive-skip-gdocs
    --exclude '.~lock*' --exclude '*.tmp' --exclude '.DS_Store'
    -v
  )
  # Newer rclone recovers from interrupted runs by itself and, when both
  # sides changed a file, keeps the newer one and renames the other as a
  # conflict copy — nothing is silently lost either way. (Ubuntu's packaged
  # rclone may be older; the plain bisync above still works there.)
  if version_ge "$(rclone_version)" "1.66"; then
    args+=(--create-empty-src-dirs --resilient --recover --conflict-resolve newer)
  fi
  if [ ! -f "$MARK" ]; then
    say "First sync: merging $LOCAL and $REMOTE…"
    # bisync needs both sides to exist; a brand-new Drive folder does not yet.
    rclone mkdir "$REMOTE"
    rclone "${args[@]}" --resync
    touch "$MARK"
  else
    if ! rclone "${args[@]}"; then
      die "sync failed. If rclone asks for --resync, run:
  rm '$MARK' && blobnot-sync-setup --run"
    fi
  fi
}

# ---------- setup ----------
install_timer() {
  local every="$1" self
  self="$(readlink -f "$0")"
  # From an AppImage the script lives on a temporary mount, so keep a copy
  # somewhere that survives for the timer to call.
  case "$self" in
    /usr/*) ;;
    *)
      mkdir -p "$HOME/.local/bin"
      if [ "$self" != "$HOME/.local/bin/blobnot-sync-setup" ]; then
        cp "$self" "$HOME/.local/bin/blobnot-sync-setup"
        chmod 0755 "$HOME/.local/bin/blobnot-sync-setup"
      fi
      self="$HOME/.local/bin/blobnot-sync-setup"
      ;;
  esac
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT_DIR/blobnot-sync.service" <<EOF
[Unit]
Description=Sync the BloBnot vault with rclone
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$self --run
EOF
  cat > "$UNIT_DIR/blobnot-sync.timer" <<EOF
[Unit]
Description=Sync the BloBnot vault every $every minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=${every}min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now blobnot-sync.timer
}

setup() {
  local remote="gdrive:BLOB/BloknotVault" local_dir="$HOME/BloBnot-Vault"
  local every=5 config=1 systemd=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --remote) remote="${2:?}"; shift 2 ;;
      --local) local_dir="${2:?}"; shift 2 ;;
      --every) every="${2:?}"; shift 2 ;;
      --no-config) config=0; shift ;;
      --no-systemd) systemd=0; shift ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
  done
  if ! [[ "$every" =~ ^[0-9]+$ ]] || [ "$every" -lt 1 ]; then
    die "--every takes whole minutes"
  fi
  need_rclone

  # A path with "name:" is a configured rclone remote; create it if missing.
  if [[ "$remote" == *:* ]] && [ "$config" = 1 ]; then
    local name="${remote%%:*}"
    if ! rclone listremotes | grep -qx "$name:"; then
      say "Connecting rclone to Google Drive as \"$name\" — a browser window will open to sign in."
      rclone config create "$name" drive scope=drive
    fi
  fi

  mkdir -p "$CONF_DIR" "$local_dir"
  local_dir="$(cd "$local_dir" && pwd)"
  cat > "$CONF" <<EOF
# BloBnot vault sync — written by blobnot-sync-setup
REMOTE="$remote"
LOCAL="$local_dir"
EOF
  rm -f "$MARK"
  run_sync

  if [ "$systemd" = 1 ]; then
    command -v systemctl >/dev/null || die "systemd not found — run with --no-systemd and sync with --run"
    install_timer "$every"
    say "Syncing every $every minutes in the background."
  fi
  say "Done. In BloBnot, open this folder as your vault:"
  echo "  $local_dir"
}

status() {
  load_conf
  echo "Remote: $REMOTE"
  echo "Local:  $LOCAL"
  if [ -f "$MARK" ]; then
    echo "Initial sync: done"
  else
    echo "Initial sync: not yet"
  fi
  if command -v systemctl >/dev/null; then
    systemctl --user list-timers blobnot-sync.timer --no-pager 2>/dev/null || true
    journalctl --user -u blobnot-sync.service -n 15 --no-pager 2>/dev/null || true
  fi
}

uninstall() {
  if command -v systemctl >/dev/null; then
    systemctl --user disable --now blobnot-sync.timer 2>/dev/null || true
  fi
  rm -f "$UNIT_DIR/blobnot-sync.service" "$UNIT_DIR/blobnot-sync.timer" "$MARK"
  if command -v systemctl >/dev/null; then
    systemctl --user daemon-reload || true
  fi
  say "Sync stopped. Your notes stay where they are."
}

case "${1:-}" in
  --run) run_sync ;;
  --status) status ;;
  --uninstall) uninstall ;;
  -h | --help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) setup "$@" ;;
esac
