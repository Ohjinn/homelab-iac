# homelab-iac

Infrastructure as Code for a self-hosted home lab running on Proxmox VE.  
Manages VM/LXC provisioning via Terraform, with GitOps-based CD through ArgoCD (in progress).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Home Network (192.168.0.0/24)        │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Control Plane — Old Laptop               │   │
│  │         i5-8250U / 16GB RAM                      │   │
│  │                                                  │   │
│  │  ┌─────────────┐  ┌──────────┐  ┌─────────────┐ │   │
│  │  │ Proxmox VE  │  │ k3s      │  │    HAOS     │ │   │
│  │  │ (bare metal)│  │ Master   │  │ (VM / .111) │ │   │
│  │  │    .200     │  │  .151    │  └─────────────┘ │   │
│  │  └─────────────┘  └──────────┘                  │   │
│  │  ┌─────────────────────────┐                    │   │
│  │  │ GitHub Runner (LXC .101)│                    │   │
│  │  └─────────────────────────┘                    │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │   Worker Node (planned) — Desktop                │   │
│  │   k3s Agent / Vector DB / RAG pipeline           │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │   Inference Engine — Mac M3 (18GB)               │   │
│  │   Ollama / local LLM API                         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Tailscale mesh VPN across all nodes                     │
│  Cloudflare Tunnel → Home Assistant (external HTTPS)     │
└─────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Hypervisor | Proxmox VE (bare metal) |
| IaC | Terraform + HCP Terraform Cloud backend |
| Proxmox Provider | telmate/proxmox 3.0.2-rc03 |
| Container Orchestration | k3s |
| GitOps CD | ArgoCD *(in progress)* |
| CI | GitHub Actions (self-hosted runner) |
| VPN | Tailscale mesh |
| External Access | Cloudflare Tunnel |
| Smart Home | Home Assistant OS |

---

## Network Design

| Host | IP | Role |
|---|---|---|
| Gateway (ipTIME BE3600M) | 192.168.0.1 | Router |
| Proxmox VE | 192.168.0.200 | Hypervisor |
| k3s-master-01 | 192.168.0.151 | Kubernetes control plane |
| GitHub Runner (LXC) | 192.168.0.101 | CI self-hosted runner |
| Home Assistant | 192.168.0.111 | Smart home controller |

**IP Allocation:**
- `192.168.0.10–99` — DHCP
- `192.168.0.100–149` — Service servers
- `192.168.0.150–199` — k3s nodes
- `192.168.0.200` — Proxmox (physical machine)
- `192.168.0.250–254` — Network equipment

**Proxmox VMID Convention:**

| Range | Role |
|---|---|
| `1XX` | Core infra / non-cluster (e.g. `101` GitHub Runner) |
| `2XX` | k3s cluster (`20X` masters, `21X` workers) |
| `3XX` | Smart home / IoT (e.g. `301` HAOS) |
| `9XX` | OS templates (`90X` Linux, `91X` special OS) |

---

## Managed Resources

### VMs (Proxmox QEMU)
| Name | VMID | IP | OS | Role |
|---|---|---|---|---|
| k3s-master-01 | 201 | 192.168.0.151 | Rocky Linux 9 | Kubernetes master |
| ha-core-01 | 301 | 192.168.0.111 | Home Assistant OS | Smart home |

### LXC Containers
| Name | VMID | IP | Role |
|---|---|---|---|
| github-runner-01 | 101 | 192.168.0.101 | GitHub Actions self-hosted runner |

---

## CI/CD Pipeline

```
Push to main
    │
    ▼
GitHub Actions (self-hosted runner on .101)
    │
    ├── terraform init   (HCP Terraform Cloud backend)
    ├── terraform plan
    └── terraform apply  (auto-approve)
```

Sensitive values (API tokens, passwords, SSH keys) are stored in GitHub Actions secrets and injected as `TF_VAR_*` environment variables at runtime. The `terraform.tfvars` file is excluded from version control via `.gitignore`.

---

## Roadmap

- [ ] Add k3s worker node (desktop machine)
- [ ] Deploy ArgoCD and configure GitOps CD pipeline
- [ ] Install Prometheus + Grafana monitoring stack
- [ ] Implement canary deployment strategy via ArgoCD Rollouts
- [ ] Build RAG pipeline (Vector DB on worker node → Ollama inference on Mac M3)
- [ ] WOL automation: wake/sleep desktop via Home Assistant based on workload schedule

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for documented issues and root cause analyses, including:
- HCP Terraform + pre-release provider version conflict with Terraform 1.14.x

---

## Local Setup

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values
2. Run `terraform init`
3. Run `terraform plan` to preview changes
4. Run `terraform apply` to apply

> **Note:** This project uses HCP Terraform Cloud as the backend. You will need a free HCP Terraform account and a workspace configured to run locally.

## Runner Bootstrap

The GitHub Actions self-hosted runner (LXC `github-runner-01`) requires manual bootstrapping after creation, as LXC containers do not support cloud-init.

After the LXC is created via `terraform apply`, SSH into the runner and run:

```bash
bash bootstrap.sh
```

This installs: `unzip`, `nodejs`, `curl`, `wget`, `git`, `terraform`
