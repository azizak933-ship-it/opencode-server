#!/usr/bin/env bash
# Copy this kit to a server and install it there.
#
# Run this ON YOUR WORKSTATION:
#
#   bash deploy.sh user@host [install.sh options...]
#
# Examples:
#   bash deploy.sh root@10.0.0.5
#   bash deploy.sh root@10.0.0.5 --remote
#   bash deploy.sh ubuntu@vps.example.com --projects /home/ubuntu/code
#
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"
REMOTE_DIR="/tmp/opencode-server-kit"

if [ -z "$TARGET" ]; then
  echo "usage: bash deploy.sh user@host [install.sh options...]" >&2
  exit 1
fi
shift

if [ ! -f "${HOME}/.ssh/id_ed25519" ] && [ ! -f "${HOME}/.ssh/id_rsa" ]; then
  cat >&2 <<'EOF'
No SSH key found in ~/.ssh, so this machine cannot log into the server yet.

  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
  ssh-copy-id user@host     # or paste ~/.ssh/id_ed25519.pub into the
                            # server's ~/.ssh/authorized_keys yourself

Then run this script again.
EOF
  exit 1
fi

echo "==> checking SSH to ${TARGET}"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" 'echo connected'

echo "==> copying kit to ${TARGET}:${REMOTE_DIR}"
ssh "$TARGET" "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
scp -q -r "${KIT_DIR}/." "${TARGET}:${REMOTE_DIR}/"

echo "==> running installer"
# shellcheck disable=SC2029
ssh -t "$TARGET" "sudo bash ${REMOTE_DIR}/install.sh $*"
