#!/usr/bin/env bash
# Install an always-on, always-reachable OpenCode server on a Linux host.
#
# Run this ON THE SERVER, as root:
#
#   sudo bash install.sh [options]
#
# Options:
#   --remote         also expose the server for pairing from anywhere (OpenTunnel)
#   --bind ADDR      address the server listens on (default 127.0.0.1)
#   --port N         server port (default 49374)
#   --projects DIR   directory for repositories (default /srv/projects)
#
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE=0
BIND="127.0.0.1"
PORT="49374"
PROJECTS="/srv/projects"
OC_USER="opencode"
OC_HOME="/home/${OC_USER}"
OC="/usr/local/bin/opencode"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
as_user() { su - "$OC_USER" -c "$1"; }

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --remote)   REMOTE=1 ;;
    --bind)     BIND="${2:?--bind needs a value}"; shift ;;
    --port)     PORT="${2:?--port needs a value}"; shift ;;
    --projects) PROJECTS="${2:?--projects needs a value}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"
command -v curl >/dev/null 2>&1 || die "curl is required"

# 1. dedicated unprivileged service user -------------------------------------
# The agent runs shell commands with the service user's authority, so it must
# not be root.
if id "$OC_USER" >/dev/null 2>&1; then
  say "service user '${OC_USER}' already exists"
else
  say "creating service user '${OC_USER}'"
  useradd --create-home --shell /bin/bash "$OC_USER"
fi

# 2. OpenCode ----------------------------------------------------------------
if [ -x "$OC" ]; then
  say "OpenCode is already installed at $OC"
else
  if [ ! -x "${OC_HOME}/.opencode/bin/opencode" ]; then
    say "installing OpenCode for '${OC_USER}'"
    as_user 'curl -fsSL https://opencode.ai/v2/install | bash'
  fi

  # The installer places the binary under the user's home; find it either way.
  FOUND="$(as_user 'command -v opencode' 2>/dev/null || true)"
  if [ -z "$FOUND" ]; then
    FOUND="$(find "$OC_HOME" -maxdepth 4 -type f -name opencode -perm -u+x 2>/dev/null | head -n 1 || true)"
  fi
  [ -n "$FOUND" ] || die "OpenCode installed but no binary was found under ${OC_HOME}"
  ln -sf "$FOUND" "$OC"
  say "linked ${FOUND} -> ${OC}"
fi

# 3. server config -----------------------------------------------------------
install -d -o "$OC_USER" -g "$OC_USER" "${OC_HOME}/.config/opencode"
if [ -f "${OC_HOME}/.config/opencode/opencode.jsonc" ]; then
  say "keeping existing ${OC_HOME}/.config/opencode/opencode.jsonc"
else
  sed "s#/srv/projects#${PROJECTS}#g" "${KIT_DIR}/opencode.jsonc" > /tmp/opencode-server.jsonc
  install -o "$OC_USER" -g "$OC_USER" -m 0644 /tmp/opencode-server.jsonc "${OC_HOME}/.config/opencode/opencode.jsonc"
  rm -f /tmp/opencode-server.jsonc
  say "wrote ${OC_HOME}/.config/opencode/opencode.jsonc"
fi

# 4. environment for the server process --------------------------------------
install -d -m 0755 /etc/opencode
install -m 0644 "${KIT_DIR}/env.example" /etc/opencode/env.example
if [ -f /etc/opencode/env ]; then
  say "keeping existing /etc/opencode/env"
else
  install -m 0640 -o root -g "$OC_USER" "${KIT_DIR}/env.example" /etc/opencode/env
  say "wrote /etc/opencode/env (add provider credentials there)"
fi

# 5. port + server password --------------------------------------------------
if [ -f /etc/opencode/server.env ]; then
  say "keeping existing port and password (/etc/opencode/server.env)"
else
  PW="$(openssl rand -base64 24 2>/dev/null | tr -d '\n' || true)"
  [ -n "$PW" ] || PW="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
  (umask 077 && printf 'OPENCODE_SERVER_PORT=%s\nOPENCODE_SERVER_PASSWORD=%s\n' "$PORT" "$PW" > /etc/opencode/server.env)
  say "generated a server password (see /etc/opencode/server.env)"
fi
# shellcheck source=/dev/null
. /etc/opencode/server.env

# Setting service configuration stops the service, so this runs before the
# first start.
say "applying service settings (port ${OPENCODE_SERVER_PORT})"
as_user "${OC} service set port ${OPENCODE_SERVER_PORT}"
as_user "${OC} service set password '${OPENCODE_SERVER_PASSWORD}'"
if [ "$BIND" != "127.0.0.1" ]; then
  say "server will listen on ${BIND}"
  as_user "${OC} service set hostname ${BIND}"
fi

# 6. projects directory ------------------------------------------------------
mkdir -p "$PROJECTS"
chown "${OC_USER}:${OC_USER}" "$PROJECTS"
say "projects directory: ${PROJECTS} (owner ${OC_USER})"

# 7. systemd -----------------------------------------------------------------
say "installing systemd units"
install -m 0644 "${KIT_DIR}/opencode.service"          /etc/systemd/system/opencode.service
install -m 0644 "${KIT_DIR}/opencode-ensure.service"   /etc/systemd/system/opencode-ensure.service
install -m 0644 "${KIT_DIR}/opencode-ensure.timer"     /etc/systemd/system/opencode-ensure.timer
systemctl daemon-reload
systemctl enable --now opencode.service
say "started opencode.service"

# 8. wait for health ---------------------------------------------------------
OK=0
for _ in $(seq 1 30); do
  if as_user "${OC} api get /api/info" >/dev/null 2>&1; then OK=1; break; fi
  sleep 2
done
if [ "$OK" != 1 ]; then
  warn "the server did not answer on /api/info"
  warn "check: journalctl -u opencode"
  warn "check: ${OC_HOME}/.local/share/opencode/log/opencode.log"
  exit 1
fi

# 9. optional remote pairing -------------------------------------------------
# Left off by default: it exposes the server to the internet (password-gated
# and end-to-end encrypted, but still exposed).
if [ "$REMOTE" = 1 ]; then
  say "enabling remote access (OpenTunnel)"
  as_user "${OC} pair --remote --yes" || warn "remote pairing failed; run it manually as ${OC_USER}"
fi

# 10. summary ----------------------------------------------------------------
cat <<EOF

OpenCode server is running.

  address    http://127.0.0.1:${OPENCODE_SERVER_PORT}  (on this host)
  password   /etc/opencode/server.env
  config     ${OC_HOME}/.config/opencode/opencode.jsonc
  projects   ${PROJECTS}
  env        /etc/opencode/env
  logs       ${OC_HOME}/.local/share/opencode/log/opencode.log

Pair a device (run on this host, as ${OC_USER}):

  su - ${OC_USER} -c 'opencode pair'            # same network / SSH tunnel
  su - ${OC_USER} -c 'opencode pair --remote'   # from anywhere

Then, in the first client you pair, run /connect to add a model provider.

Next steps:
  * clone your repositories into ${PROJECTS}
  * systemctl status opencode          # is it up?
  * journalctl -u opencode -f          # unit output
  * bash verify.sh                     # health check
  * systemctl enable --now opencode-ensure.timer   # self-heal every 5 min

EOF
