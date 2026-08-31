# babycat-ca

Babycat의 제조사 CA 도구를 담는 저장소이다. 공개 저장소이므로 비밀과 발급 기록은 여기에 두지 않는다. Root CA의 생성, 젯슨 보드별 Device CA의 발급과 전송, 발급 대장의 유지가 이 저장소의 범위이며, 보드에서 실행되는 것은 없다. TLS 신뢰 모델과 보드 쪽 설치·기동 절차는 babycat 저장소의 `docs/ops/pki.md`가 기술한다.

## 1. 구성

|파일|역할|
|---|---|
|`provision-device.sh`|Root CA 생성(`init`), Device CA 발급·전송(`issue`)|
|`cp-rootcrt.sh`|Root CA 인증서를 mewly 앱 리소스로 복사|
|`provision/`|`--to` 없이 발급한 결과의 임시 보관처. 형상 관리에서 제외한다|

Root CA 개인키는 이 저장소에 두지 않는다. 기본 위치는 `~/.babycat-ca/`이며 `ROOT_DIR` 환경 변수로 바꿀 수 있다.

## 2. babycat 저장소와의 계약

`issue`가 만드는 파일 배치와 내용은 babycat의 gateway가 소비한다. 어느 한쪽을 바꾸면 다른 쪽을 함께 갱신해야 한다.

- 배치: `caddy/pki/authorities/local/root.{crt,key}` — 보드의 `data/caddy/` 아래에 그대로 놓이며, gateway의 `issue-cert.sh`가 이 경로의 CA로 서버 인증서에 서명한다. 파일명이 `root.*`인 것은 Caddy의 pki 배치를 따른 것이고, 내용은 Device CA다.
- 제약: Device CA 인증서의 nameConstraints는 사설 IPv4 대역(10/8, 172.16/12, 192.168/16), 127/8, `localhost`, `.local`로 한정된다. 보드 `.env`의 `HOST_IP`와 `TLS_EXTRA_HOSTS`는 이 범위 안이어야 한다.
- 클라이언트: mewly는 Root CA 인증서(`cp-rootcrt.sh`가 복사하는 `babycat_ca.crt`)만 신뢰하고, gateway가 서버 인증서와 Device CA 인증서를 체인으로 함께 보낸다.

## 3. 절차

### 3.1 Root CA 생성 — 최초 1회

```bash
./provision-device.sh init
```

`~/.babycat-ca/`에 개인키 `root.key`(권한 600)와 인증서 `root.crt`가 생성된다. 이미 있으면 거부한다.

### 3.2 mewly에 Root CA 인증서 동봉 — 최초 1회

```bash
./cp-rootcrt.sh ~/projects/mewly
```

`root.crt`가 mewly의 `android/app/src/main/res/raw/babycat_ca.crt`로 복사된다. 공개 파일이므로 mewly 저장소에 커밋해도 무방하다. Root CA를 재생성한 경우에만 다시 복사하고 앱을 재배포한다.

### 3.3 Device CA 발급과 전송 — 보드마다

보드에서 babycat의 설치 준비(clone, `.env`, 데이터 디렉터리)까지 마친 뒤 실행한다.

```bash
./provision-device.sh issue BC-2026-00000004 --to skim@172.27.1.206 --port 12966
```

시리얼 형식은 `BC-<연도 4자리>-<일련번호 8자리>`이며, 명령 하나가 발급, 보드 준비 상태 확인, 복사, 복사 결과 검증, 로컬 발급분 삭제를 순서대로 수행한다. 보드에 이미 Device CA가 있으면 중단한다(교체하려면 보드의 `data/caddy/caddy/pki`와 `data/caddy/site`를 지운 뒤 재실행).

`--to` 없이 실행하면 `provision/<시리얼>/`에 결과만 남는다. 이 경우 그 안의 `caddy` 디렉터리를 보드의 `data/caddy/` 아래로 직접 복사하고, 복사 후 `provision/<시리얼>/`을 삭제한다. Device CA 개인키는 보드 안에만 있어야 한다.

### 3.4 발급 대장

발급 대장(시리얼, 보드, 주소, 날짜)은 이 저장소에 두지 않고 수동으로 관리한다. 시리얼·호스트명·내부 주소가 공개되는 것을 막기 위함이다. 시리얼은 재사용하지 않으며, 재발급 시 새 일련번호를 쓰고 이전 기록에 사유를 남긴다. 보드에서 시리얼을 확인하는 명령: `openssl x509 -in data/caddy/caddy/pki/authorities/local/root.crt -noout -subject`

## 4. 키 보관과 사고 대응

- Root CA 개인키(`~/.babycat-ca/root.key`)는 어떤 저장소, 보드, 클라우드 동기화 폴더에도 두지 않는다. 분실하면 신규 보드의 Device CA를 발급할 수 없으므로 오프라인 매체에 백업하고 그 위치를 별도로 기록한다.
- Root CA 개인키가 유출되면 유출자가 임의의 Device CA를 만들 수 있다. 대응은 Root CA 재생성(3.1), mewly 재배포(3.2), 출고된 모든 보드의 Device CA 재발급·재전송(3.3)이며, 전 보드에 대한 조치다.
- Device CA 개인키가 유출되면 유출자가 그 보드 시리얼로 사설 대역 주소의 서버 인증서를 만들 수 있다. 영향은 같은 LAN 안으로 한정된다. 그 보드의 Device CA를 재발급하여 교체하되, 폐기 목록(CRL)을 배포하는 경로가 없으므로 유출된 Device CA는 만료(10년)까지 유효하다.
- Root CA(20년)와 Device CA(10년)의 만료 전 갱신 절차는 정하지 않았다. 이 문서의 개정 시점에 정한다.
