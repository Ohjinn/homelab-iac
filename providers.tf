terraform {
  # HCP Terraform 클라우드를 백엔드로 사용합니다.
  cloud {
    organization = "hojin-lab"

    workspaces {
      name = "proxmox-homelab"
    }
  }

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc03"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true # 개발 환경용

  pm_minimum_permission_check = false
}
