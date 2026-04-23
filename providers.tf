terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc3" # 최신 안정 버전 권장
    }
  }
}

provider "proxmox" {
  pm_api_url          = "https://192.168.0.200:8006/api2/json" # Proxmox 서버 IP
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true # 홈랩이므로 Self-signed 인증서 허용
}