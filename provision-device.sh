#!/bin/sh
# Babycat manufacturer CA management — creates the Root CA and issues one
# Device CA per Jetson board. Runs on the development PC only; nothing here
# runs on a board. The procedure and key-custody rules are in README.md.
#
# Usage:
#   ./provision-device.sh init
#       Create the Root CA (once). Its certificate goes into the mewly app
#       via ./cp-rootcrt.sh; its private key never leaves ROOT_DIR.
#   ./provision-device.sh issue <serial> [--to <user@host>] [--port <ssh port>]
#       Issue a Device CA. With --to, also copy it into the board's
#       ~/projects/babycat/data/caddy/, verify the copy, delete the local
#       output. Without --to, the output stays under provision/<serial>/
#       for manual copying. Record every issuance in your own ledger; the
#       ledger is not kept in this repository.
#
# Environment variables:
#   ROOT_DIR  directory holding the Root CA (default ~/.babycat-ca).
#             Keep it outside every repository.
#   OUT_DIR   parent directory of issued output (default ./provision, gitignored)
#
# Contract with the babycat repository: the issued files land at
# caddy/pki/authorities/local/root.{crt,key} — the path and file names the
# gateway's issue-cert.sh reads — and the Device CA carries nameConstraints
# limited to private IPv4 ranges, 127/8, localhost, and .local.
set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT_DIR="${ROOT_DIR:-$HOME/.babycat-ca}"
OUT_DIR="${OUT_DIR:-$BASE_DIR/provision}"
ROOT_DAYS=7300    # Root CA, 20 years — renewal ships via a mewly update, so keep it long
DEVICE_DAYS=3650  # Device CA, 10 years — beyond the pethouse board's service life
CURVE=P-256

usage() { sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

init_root() {
  if [ -f "$ROOT_DIR/root.key" ]; then
    echo "Root CA already exists: $ROOT_DIR/root.key" >&2; exit 1
  fi
  mkdir -p "$ROOT_DIR"; chmod 700 "$ROOT_DIR"
  openssl req -x509 -new -newkey ec -pkeyopt ec_paramgen_curve:$CURVE -nodes \
    -keyout "$ROOT_DIR/root.key" -out "$ROOT_DIR/root.crt" -days "$ROOT_DAYS" \
    -subj "/O=Babycat/CN=Babycat Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
  chmod 600 "$ROOT_DIR/root.key"
  echo "Root CA created. Back up the private key and keep it outside every repository: $ROOT_DIR"
  echo "Root certificate to bundle into mewly: $ROOT_DIR/root.crt (use ./cp-rootcrt.sh)"
}

issue_device() {
  serial="${1:?serial required (e.g. BC-2026-00000001)}"; shift
  to=""; port="22"
  while [ $# -gt 0 ]; do
    case "$1" in
      --to)   to="${2:?--to requires user@host}"; shift 2 ;;
      --port) port="${2:?--port requires a number}"; shift 2 ;;
      *) echo "unknown option: $1" >&2; usage ;;
    esac
  done
  case "$serial" in
    BC-[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) echo "serial format is BC-<year>-<8-digit sequence>: $serial" >&2; exit 1 ;;
  esac
  [ -f "$ROOT_DIR/root.key" ] || { echo "Root CA not found; run init first: $ROOT_DIR" >&2; exit 1; }

  # Same layout the gateway reads (issue-cert.sh's PKI path). The file names
  # root.crt/root.key follow Caddy's pki layout; the content is the Device CA.
  dest="$OUT_DIR/$serial/caddy/pki/authorities/local"
  if [ -e "$dest/root.key" ]; then
    echo "this serial was already issued: $dest" >&2; exit 1
  fi
  mkdir -p "$dest"

  # nameConstraints keep a leaked Device CA from signing certificates for
  # addresses outside private ranges. The server certificate's SANs
  # (HOST_IP, TLS_EXTRA_HOSTS) must stay inside these ranges.
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:$CURVE -nodes \
    -keyout "$dest/root.key" -subj "/O=Babycat/CN=Babycat Device CA $serial" 2>/dev/null |
  openssl x509 -req -CA "$ROOT_DIR/root.crt" -CAkey "$ROOT_DIR/root.key" \
    -days "$DEVICE_DAYS" -set_serial "0x$(openssl rand -hex 8)" \
    -extfile /dev/fd/3 3<<EXT -out "$dest/root.crt"
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
nameConstraints = critical, permitted;IP:10.0.0.0/255.0.0.0, permitted;IP:172.16.0.0/255.240.0.0, permitted;IP:192.168.0.0/255.255.0.0, permitted;IP:127.0.0.0/255.0.0.0, permitted;DNS:localhost, permitted;DNS:.local
EXT
  chmod 600 "$dest/root.key"
  echo "Device CA issued: $dest/root.crt"

  if [ -z "$to" ]; then
    cp "$ROOT_DIR/root.crt" "$OUT_DIR/$serial/manufacturer-root.crt"
    echo "copy $OUT_DIR/$serial/caddy into the board's data/caddy/, then delete $OUT_DIR/$serial"
    echo "record the issuance in your ledger (kept outside this repository)"
    return
  fi

  # --to: copy to the board, verify, clean up, record.
  remote_base="~/projects/babycat/data/caddy"
  if ! ssh -p "$port" "$to" "[ -f ~/projects/babycat/docker-compose.yml ]"; then
    echo "board is not prepared: ~/projects/babycat missing on $to — clone babycat there first" >&2
    echo "the issued Device CA is kept under $OUT_DIR/$serial for a retry" >&2
    exit 1
  fi
  ssh -p "$port" "$to" "mkdir -p $remote_base"
  if ssh -p "$port" "$to" "[ -e $remote_base/caddy/pki/authorities/local/root.key ]"; then
    echo "the board already has a Device CA — remove $remote_base/caddy/pki (and site/) first if replacing it" >&2
    echo "the issued Device CA is kept under $OUT_DIR/$serial for a retry" >&2
    exit 1
  fi
  scp -P "$port" -r "$OUT_DIR/$serial/caddy" "$to:$remote_base/"
  echo "verifying the copy:"
  ssh -p "$port" "$to" "openssl x509 -in $remote_base/caddy/pki/authorities/local/root.crt -noout -subject"
  rm -r "$OUT_DIR/$serial"
  echo "record the issuance in your ledger (kept outside this repository)"
  echo "done — on the board, run tools/up.sh (or docker compose up -d) in ~/projects/babycat"
}

case "${1:-}" in
  init) init_root ;;
  issue) shift; issue_device "$@" ;;
  *) usage ;;
esac
