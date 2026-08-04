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
│  │  ┌─────────────────────────┐  ┌──────────────┐ │   │
│  │  │ GitHub Runner (LXC .101)│  │ DNS (LXC .102)│ │   │
│  │  └─────────────────────────┘  └──────────────┘ │   │
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
| Hub (guestroom) | 192.168.0.254 | LAN switch for Mac, desktop |
| Proxmox VE | 192.168.0.200 | Hypervisor |
| k3s-master-01 | 192.168.0.151 | Kubernetes control plane |
| GitHub Runner (LXC) | 192.168.0.101 | CI self-hosted runner |
| Home Assistant | 192.168.0.111 | Smart home controller |
| Internal DNS (LXC) | 192.168.0.102 | dnsmasq — local records + upstream forwarding |

**IP Allocation:**
- `192.168.0.10–99` — DHCP
- `192.168.0.100–149` — Service servers
- `192.168.0.150–199` — k3s nodes
- `192.168.0.200` — Proxmox (physical machine)
- `192.168.0.250–254` — Network equipment

**Proxmox VMID Convention:**

| Range | Role |
|---|---|
| `1XX` | Core infra / non-cluster (`101` GitHub Runner, `102` Internal DNS) |
| `2XX` | k3s cluster (`20X` masters, `21X` workers) |
| `3XX` | Smart home / IoT (e.g. `301` HAOS) |
| `9XX` | OS templates (`90X` Linux, `91X` special OS) |

---

## Managed Resources

### VMs (Proxmox QEMU)
| Name | VMID | IP | OS | Role |
|---|---|---|---|---|
| k3s-master-01 | 151 | 192.168.0.151 | Rocky Linux 9 | Kubernetes master |
| ha-core-01 | 111 | 192.168.0.111 | Home Assistant OS | Smart home |

### LXC Containers
| Name | VMID | IP | Role |
|---|---|---|---|
| github-runner-01 | 101 | 192.168.0.101 | GitHub Actions self-hosted runner |
| dns-01 | 102 | 192.168.0.102 | Internal DNS (dnsmasq) |

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

## LXC Bootstrap

LXC containers do not support cloud-init, so each one is provisioned by a
role-specific script after `terraform apply` creates it.

| Container | Script | Role |
|---|---|---|
| `github-runner-01` (101) | `bootstrap-runner.sh` | GitHub Actions runner, container builds |
| `dns-01` (102) | `bootstrap-dns.sh` | Internal DNS for the home network |

### github-runner-01

After the LXC is created via `terraform apply`, SSH into the runner and run:

```bash
# packages only
bash bootstrap-runner.sh

# packages + register a runner for a repo
bash bootstrap-runner.sh https://github.com/Ohjinn/homelab-iac <REGISTRATION_TOKEN>
```

This installs:

| | |
|---|---|
| Base packages | `unzip`, `nodejs`, `curl`, `wget`, `git` |
| Container tooling | `docker.io`, `docker-buildx` — workflows build images on this runner |
| Runner | downloads `actions-runner`, registers it, installs the systemd service |

Terraform itself is not installed on the runner. The workflow pulls its own pinned
version via `hashicorp/setup-terraform`, so a system-wide copy would only be a
second place to keep the version in sync.

The registration token is short-lived (about an hour) so it cannot be committed.
Get one from the repo's **Settings → Actions → Runners → New self-hosted runner**.

Run the script again with a different repo URL to add another runner; each repo
gets its own directory (`actions-runner-<repo>`) and its own systemd service, so a
single LXC can serve several repositories.

### dns-01

The router (ipTIME) can only forward DNS - it cannot hold custom local records -
so internal names live here instead.

```bash
bash bootstrap-dns.sh
```

This installs dnsmasq, serves the records listed in the script, and forwards
everything else upstream. After running it, point the router's DHCP DNS server
at `192.168.0.102` so LAN clients use it.

Names defined here are deliberately absent from public DNS. Adding a Cloudflare
record for one of them would expose the service through the tunnel; keeping them
internal-only means they resolve at home and nowhere else.
