# Device CA issuance ledger (example)

Format of the ledger that maps each Device CA issued by `provision-device.sh issue` to the Jetson board it was shipped to. Keep the real ledger outside this repository (e.g. `~/.babycat-ca/ledger.md`) so that serials, host names, and internal addresses are not published, and add one row per issuance.

Rules:

- Never reuse a serial. When reissuing a Device CA for the same board, take a new sequence number and note "replaced by reissue" on the old row.
- To read a board's serial: `openssl x509 -in data/caddy/caddy/pki/authorities/local/root.crt -noout -subject`

|Serial|Board (hostname)|Address|Module|Issued|Note|
|---|---|---|---|---|---|
|`BC-2026-00000000`|JETSON-EXAMPLE-1|192.168.0.10|AGX Orin|2026-01-01|development board|
|`BC-2026-00000001`|JETSON-EXAMPLE-2|192.168.0.11|Orin NX|2026-01-02|replaced by reissue → `BC-2026-00000002`|
|`BC-2026-00000002`|JETSON-EXAMPLE-2|192.168.0.11|Orin NX|2026-01-03||
