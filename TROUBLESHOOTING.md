# Terraform 트러블슈팅 기록

---

## HCP Terraform + Pre-release 프로바이더 버전 충돌 문제

### 증상

CI 파이프라인에서 `terraform init -upgrade`를 실행했을 때 아래 에러가 발생함:

```
Initializing provider plugins found in the configuration...
- Finding telmate/proxmox versions matching "3.0.2-rc03"...
- Installing telmate/proxmox v3.0.2-rc03...
- Installed telmate/proxmox v3.0.2-rc03

Initializing HCP Terraform...

Initializing provider plugins found in the state...
- Reusing previous version of telmate/proxmox

│ Error: Failed to query available provider packages
│
│ Could not retrieve the list of available versions for provider
│ telmate/proxmox: locked provider registry.terraform.io/telmate/proxmox
│ 3.0.2-rc03 does not match configured version constraint ; must use
│ terraform init -upgrade to allow selection of new versions
```

- `-upgrade` 옵션을 써도 해결 안 됨
- 로컬에서는 잘 되는데 CI에서만 실패함

---

### 원인 분석

#### 핵심 원인: Terraform 버전 차이

| 환경 | Terraform 버전 | 결과 |
|------|---------------|------|
| 로컬 | 1.13.0 | 정상 동작 |
| CI (`setup-terraform@v3`, 버전 미지정) | 1.14.9 (자동 설치) | 에러 발생 |

`setup-terraform@v3`에 `terraform_version`을 지정하지 않으면 **최신 버전(1.14.9)** 을 자동으로 설치한다. 이 버전에서 HCP Terraform 클라우드 백엔드를 사용할 때 프로바이더 초기화 방식이 바뀌었다.

---

#### Terraform 1.14.x의 변경된 초기화 흐름

**1.13.0 (구버전)** — 단일 단계로 처리:
```
Initializing HCP Terraform...
Initializing provider plugins...   ← 설정 파일 + 상태 파일을 한꺼번에 처리
```

**1.14.9 (신버전)** — 두 단계로 분리:
```
Initializing provider plugins found in the configuration...  ← 1단계: .tf 파일 기준
Initializing HCP Terraform...
Initializing provider plugins found in the state...           ← 2단계: 원격 state 기준 (신규!)
```

---

#### 왜 충돌이 발생하는가?

**1단계** (설정 파일 기준):
- `providers.tf`에 `version = "3.0.2-rc03"` 명시되어 있음
- Terraform이 `3.0.2-rc03`을 다운로드하고 lock 파일에 기록 → 성공

**2단계** (state 파일 기준):
- HCP Terraform의 원격 state를 읽음
- state는 `telmate/proxmox` 프로바이더를 사용했다는 것만 기록함 (버전 제약 조건은 없음)
- 즉, 2단계에서 프로바이더의 버전 제약 조건 = **빈값 (any version)**

**여기서 Semantic Versioning 규칙 충돌 발생:**

> Pre-release 버전(`-rc03`, `-alpha`, `-beta` 등)은 빈 제약 조건이나 느슨한 제약 조건(`>= 0.0.0`)에 **매칭되지 않는다.**
> Pre-release 버전은 반드시 명시적으로 지정해야만 선택된다.

- lock 파일: `3.0.2-rc03`
- 2단계 제약 조건: 빈값 (any)
- 결과: `3.0.2-rc03`은 빈 제약 조건을 **만족하지 못함** → 에러

**`-upgrade`가 효과 없는 이유:**
`-upgrade`는 lock 파일의 버전 제약을 무시하고 새 버전을 선택할 수 있게 해주는 옵션이다. 하지만 이 문제는 lock 파일이 낡아서 생기는 게 아니라, **pre-release 버전과 빈 버전 제약 사이의 근본적인 호환성 문제**이기 때문에 `-upgrade`로는 해결할 수 없다.

**1.13.0에서는 왜 되는가:**
단일 단계로 처리하기 때문에 `.tf` 파일의 명시적 제약 조건(`= 3.0.2-rc03`)이 state 기반 초기화에도 함께 적용된다. 두 단계로 분리되는 문제 자체가 없다.

---

### 해결 방법

`terraform_version`을 state를 생성한 버전과 동일하게 고정한다.

`.github/workflows/terraform.yml`:
```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: "1.13.0"   # ← 추가
    cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
```

---

### 교훈

1. **`setup-terraform`에 버전을 명시하지 않으면 CI가 로컬과 다른 Terraform을 쓴다.** 로컬에서만 테스트하면 잡기 어렵다.
2. **Pre-release 프로바이더 버전(`-rc`, `-alpha`, `-beta`)은 HCP Terraform 클라우드 백엔드와 함께 쓸 때 버전에 민감하다.**  
   가능하면 stable 버전을 사용하는 것이 좋다. `telmate/proxmox`는 2025년 기준 stable 3.x 릴리즈가 없어 어쩔 수 없이 rc 버전을 사용 중.
3. **Terraform 버전을 올릴 때는 state를 마이그레이션하거나, CI/로컬 버전을 함께 올려야 한다.**
