terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1" 
    }
  }
}

provider "proxmox" {
  # 💡 변수를 통하지 않고 직접 값을 박아 넣습니다.
  pm_api_url          = "https://100.78.176.123:8006/api2/json"
  pm_api_token_id     = "terraform-prov@pve!Terraform" 
  
  pm_api_token_secret = var.proxmox_api_token_secret 
  pm_tls_insecure     = true 
}