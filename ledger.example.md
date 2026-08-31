# Device CA 발급 대장 (예시)

`provision-device.sh issue`로 발급한 Device CA와 그것을 넣은 젯슨 보드의 대응을 기록하는 대장의 서식이다. 실제 대장은 시리얼·호스트명·내부 주소가 공개되지 않도록 이 저장소 밖(예: `~/.babycat-ca/ledger.md`)에 두고, 발급할 때마다 한 행을 추가한다.

규칙:

- 시리얼은 재사용하지 않는다. 같은 보드의 Device CA를 재발급할 때도 새 일련번호를 쓰고, 이전 행의 비고에 "재발급으로 대체"를 적는다.
- 보드에서 시리얼을 확인하는 명령: `openssl x509 -in data/caddy/caddy/pki/authorities/local/root.crt -noout -subject`

|시리얼|보드(호스트명)|주소|모듈|발급일|비고|
|---|---|---|---|---|---|
|`BC-2026-00000000`|JETSON-EXAMPLE-1|192.168.0.10|AGX Orin|2026-01-01|개발 보드|
|`BC-2026-00000001`|JETSON-EXAMPLE-2|192.168.0.11|Orin NX|2026-01-02|재발급으로 대체 → `BC-2026-00000002`|
|`BC-2026-00000002`|JETSON-EXAMPLE-2|192.168.0.11|Orin NX|2026-01-03||
