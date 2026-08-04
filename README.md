# homelab-iac

Proxmox VE 위에 홈랩 VM과 LXC를 Terraform으로 프로비저닝한다.
클러스터에 올라가는 앱은 [homelab-gitops](https://github.com/Ohjinn/homelab-gitops)에서 ArgoCD가 관리한다.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                Home Network (192.168.0.0/24)             │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Control Plane — 구형 노트북               │   │
│  │         i5-8250U / 16GB RAM                      │   │
│  │                                                  │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌─────────────┐ │   │
│  │  │ Proxmox VE  │  │ k3s      │  │    HAOS     │ │   │
│  │  │ (bare metal)│  │ Master   │  │ (VM / .111) │ │   │
│  │  │    .200     │  │  .151    │  └─────────────┘ │   │
│  │  └─────────────┘  └──────────┘                  │   │
│  │  ┌─────────────────────────┐  ┌───────────────┐ │   │
│  │  │ GitHub Runner (LXC .101)│  │ DNS (LXC .102)│ │   │
│  │  └─────────────────────────┘  └───────────────┘ │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │   Worker Node (예정) — 데스크탑                   │   │
│  │   k3s Agent / Vector DB / RAG pipeline           │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │   Inference — Mac M3 (18GB)                      │   │
│  │   Ollama / local LLM API                         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Tailscale mesh VPN                                      │
│  Cloudflare Tunnel → Traefik (외부 HTTPS)                │
└─────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| 계층 | 기술 |
|---|---|
| 하이퍼바이저 | Proxmox VE (bare metal) |
| IaC | Terraform + HCP Terraform Cloud 백엔드 |
| Proxmox Provider | telmate/proxmox 3.0.2-rc03 |
| 컨테이너 오케스트레이션 | k3s |
| GitOps CD | ArgoCD |
| CI | GitHub Actions (self-hosted runner) |
| VPN | Tailscale mesh |
| 외부 접근 | Cloudflare Tunnel |
| 스마트홈 | Home Assistant OS |

---

## Network Design

| 호스트 | IP | 역할 |
|---|---|---|
| Gateway (ipTIME BE3600M) | 192.168.0.1 | 공유기 |
| Hub (게스트룸) | 192.168.0.254 | Mac·데스크탑용 스위치 |
| Proxmox VE | 192.168.0.200 | 하이퍼바이저 |
| k3s-master-01 | 192.168.0.151 | 쿠버네티스 컨트롤플레인 |
| GitHub Runner (LXC) | 192.168.0.101 | CI self-hosted runner |
| dns-01 (LXC) | 192.168.0.102 | 내부 DNS (dnsmasq) |
| Home Assistant | 192.168.0.111 | 스마트홈 |

**IP 대역**

- `192.168.0.10–99` — DHCP
- `192.168.0.100–149` — 서비스 서버
- `192.168.0.150–199` — k3s 노드
- `192.168.0.200` — Proxmox (물리 머신)
- `192.168.0.250–254` — 네트워크 장비

**VMID 규칙**

| 범위 | 역할 |
|---|---|
| `1XX` | Core 인프라 (`101` GitHub Runner, `102` 내부 DNS) |
| `2XX` | k3s 클러스터 (`20X` 마스터, `21X` 워커) |
| `3XX` | 스마트홈/IoT |
| `9XX` | OS 템플릿 (`90X` Linux, `91X` 특수 OS) |

---

## Managed Resources

**VM (Proxmox QEMU)**

| 이름 | VMID | IP | OS | 메모리 | 역할 |
|---|---|---|---|---|---|
| k3s-master-01 | 151 | 192.168.0.151 | Rocky Linux 9 | 10GB | 쿠버네티스 마스터 |
| ha-core-01 | 111 | 192.168.0.111 | Home Assistant OS | 3GB (balloon 0) | 스마트홈 |

**LXC**

| 이름 | VMID | IP | 메모리 | 역할 |
|---|---|---|---|---|
| github-runner-01 | 101 | 192.168.0.101 | 1GB | GitHub Actions runner, 이미지 빌드 |
| dns-01 | 102 | 192.168.0.102 | 512MB | 내부 DNS |

VM 메모리는 고정 점유고, LXC는 cgroup 상한이라 실제 쓰는 만큼만 잡는다.
16GB 중 VM 두 대가 13GB를 가져가므로 LXC를 늘릴 때는 남은 몫을 확인해야 한다.

---

## CI/CD Pipeline

```
main 에 push
    │
    ▼
GitHub Actions (self-hosted runner, .101)
    │
    ├── terraform init   (HCP Terraform Cloud 백엔드)
    ├── terraform plan
    └── terraform apply  (production Environment 승인 후)
```

API 토큰, 비밀번호, SSH 키는 GitHub Actions secrets에 두고 실행 시 `TF_VAR_*`로 주입한다.
`terraform.tfvars`는 `.gitignore`로 제외.

---

## LXC Bootstrap

LXC는 cloud-init을 지원하지 않는다. `terraform apply`로 컨테이너가 만들어진 뒤
역할별 스크립트를 한 번 돌려서 안을 채운다.

| 컨테이너 | 스크립트 | 역할 |
|---|---|---|
| `github-runner-01` (101) | `bootstrap-runner.sh` | GitHub Actions runner, 이미지 빌드 |
| `dns-01` (102) | `bootstrap-dns.sh` | 내부 DNS |

### github-runner-01

```bash
# 패키지만
bash bootstrap-runner.sh

# 패키지 + 특정 레포용 러너 등록
bash bootstrap-runner.sh https://github.com/Ohjinn/homelab-iac <REGISTRATION_TOKEN>
```

설치 항목

| | |
|---|---|
| 기본 패키지 | `unzip`, `nodejs`, `curl`, `wget`, `git` |
| 컨테이너 도구 | `docker.io`, `docker-buildx` — 워크플로가 여기서 이미지를 빌드한다 |
| 러너 | `actions-runner` 다운로드, 등록, systemd 서비스 설치 |

terraform은 러너에 설치하지 않는다. 워크플로가 `hashicorp/setup-terraform`으로
잡마다 직접 받아 쓰므로, 시스템에 깔아두면 버전을 두 군데서 관리하게 된다.

등록 토큰은 1시간짜리라 커밋할 수 없다. 레포의 **Settings → Actions → Runners →
New self-hosted runner**에서 발급받는다.

레포 URL을 바꿔 다시 실행하면 러너를 추가로 등록한다. 레포마다 디렉토리
(`actions-runner-<repo>`)와 systemd 서비스가 분리되므로 LXC 한 대가 여러 레포를 맡는다.

### dns-01

집 안 이름 해석을 담당한다. 공유기(ipTIME)는 로컬 레코드를 넣을 수 없고 포워딩만
하므로, 레코드를 들고 있을 곳이 따로 필요하다.

```bash
bash bootstrap-dns.sh
```

dnsmasq를 설치하고 스크립트에 정의된 레코드를 서빙한다. 나머지 질의는 업스트림으로
넘긴다. 실행 후 공유기 DHCP의 DNS 서버를 `192.168.0.102`로 지정하면 집 안 기기가
자동으로 이걸 쓴다.

레코드를 추가하려면 스크립트의 `LOCAL_RECORDS`를 고치고 다시 실행한다.

여기 정의한 이름은 공개 DNS에 등록하지 않는다. Cloudflare에 레코드를 만들면
터널을 타고 인터넷에 열리기 때문이다. 내부에만 두면 집에서만 열린다.

러너와 합치지 않은 이유는 역할 분리 때문이기도 하고, 러너 LXC가 메모리 1GB로
이미지 빌드까지 돌려서 빌드 중에 집 전체 DNS가 눌릴 수 있어서다.

---

## Local Setup

1. `terraform.tfvars.example`을 `terraform.tfvars`로 복사하고 값을 채운다
2. `terraform init`
3. `terraform plan`으로 변경 내용 확인
4. `terraform apply`

백엔드가 HCP Terraform Cloud라 무료 계정과 워크스페이스가 필요하다.

---

## Roadmap

- [ ] Tailscale exit node 구성 (해외에서 한국 IP 사용, dns-01에 얹을 예정)
- [ ] k3s 워커 노드 추가 (데스크탑)
- [ ] Prometheus + Grafana 모니터링 스택
- [ ] ArgoCD Rollouts 카나리 배포 전략
- [ ] RAG 파이프라인 (워커 노드 Vector DB → Mac M3 Ollama 추론)
- [ ] WOL 자동화: Home Assistant로 데스크탑 절전·기동

---

## Troubleshooting

[TROUBLESHOOTING.md](TROUBLESHOOTING.md) 참고.

- HCP Terraform + pre-release provider가 Terraform 1.14.x와 충돌
