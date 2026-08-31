# babycat-ca

Manufacturer CA tooling for Babycat. This repository is public, so no secret and no issuance record lives here. Its scope is creating the Root CA, issuing and shipping one Device CA per Jetson board, and the key-custody rules; nothing in it runs on a board. The TLS trust model and the board-side install/boot procedure are described in the babycat repository (`docs/ops/pki.md`).

## 1. Contents

|File|Role|
|---|---|
|`provision-device.sh`|Create the Root CA (`init`); issue and ship a Device CA (`issue`)|
|`cp-rootcrt.sh`|Copy the Root CA certificate into the mewly app resources|
|`provision/`|Holding area for output issued without `--to`. Excluded from version control|
|`ledger.example.md`|Template for the issuance ledger. The real ledger stays outside the repository (§3.4)|

The Root CA private key is never kept in this repository. Its default location is `~/.babycat-ca/`, changeable with the `ROOT_DIR` environment variable.

## 2. Contract with the babycat repository

The files `issue` produces are consumed by babycat's gateway. Changing either side requires updating the other.

- Layout: `caddy/pki/authorities/local/root.{crt,key}` — placed as-is under the board's `data/caddy/`, where the gateway's `issue-cert.sh` signs the server certificate with the CA found at that path. The file names `root.*` follow Caddy's pki layout; the content is the Device CA.
- Constraints: the Device CA certificate carries nameConstraints limited to the private IPv4 ranges (10/8, 172.16/12, 192.168/16), 127/8, `localhost`, and `.local`. The board's `HOST_IP` and `TLS_EXTRA_HOSTS` in `.env` must stay inside these ranges.
- Clients: mewly trusts only the Root CA certificate (the `babycat_ca.crt` that `cp-rootcrt.sh` copies); the gateway sends the server certificate together with the Device CA certificate as a chain.

## 3. Procedures

### 3.1 Create the Root CA — once

```bash
./provision-device.sh init
```

Creates the private key `root.key` (mode 600) and the certificate `root.crt` under `~/.babycat-ca/`. Refuses to run when they already exist.

### 3.2 Bundle the Root CA certificate into mewly — once

```bash
./cp-rootcrt.sh ~/projects/mewly
```

Copies `root.crt` to mewly's `android/app/src/main/res/raw/babycat_ca.crt`. The file is public, so committing it to the mewly repository is fine. Copy again — and redeploy the app — only when the Root CA has been recreated.

### 3.3 Issue and ship a Device CA — per board

Run after the board has finished babycat's installation steps (clone at least; `.env` and the data directories may come later).

```bash
./provision-device.sh issue BC-2026-00000004 --to skim@172.27.1.206 --port 12966
```

The serial format is `BC-<4-digit year>-<8-digit sequence>`. One command issues the Device CA, checks that the board is prepared, copies the files, verifies the copy, and deletes the local output. It stops when the board already has a Device CA (to replace one, remove the board's `data/caddy/caddy/pki` and `data/caddy/site` first, then re-run).

Without `--to`, the output stays under `provision/<serial>/`. In that case copy its `caddy` directory under the board's `data/caddy/` yourself, delete `provision/<serial>/` afterwards, and update your ledger. The Device CA private key must exist only on its board.

### 3.4 Issuance ledger

The ledger (serial, board, address, date) is not kept in this repository and is maintained by hand, so that serials, host names, and internal addresses are not published. Use the format in `ledger.example.md`. Serials are never reused; on reissue, take a new sequence number and note the reason on the old row. To read a board's serial: `openssl x509 -in data/caddy/caddy/pki/authorities/local/root.crt -noout -subject`

## 4. Key custody and incident response

- The Root CA private key (`~/.babycat-ca/root.key`) goes into no repository, no board, and no cloud-synced folder. Losing it makes issuing Device CAs for new boards impossible, so back it up on offline media and record the location separately.
- If the Root CA private key leaks, the holder can mint arbitrary Device CAs. The response is recreating the Root CA (3.1), redeploying mewly (3.2), and reissuing and reshipping the Device CA of every shipped board (3.3) — a fleet-wide action.
- If a Device CA private key leaks, the holder can forge server certificates for private-range addresses under that board's serial. The impact is limited to the same LAN. Reissue and replace that board's Device CA; there is no CRL distribution path, so the leaked Device CA stays valid until it expires (10 years).
- Renewal procedures for the Root CA (20 years) and Device CAs (10 years) before expiry are not defined yet; they will be set when this document is revised.
