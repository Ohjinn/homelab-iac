terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

# [리소스 1] K3s 마스터 노드 (Rocky 9 기반)
resource "proxmox_vm_qemu" "k3s_master" {
  name        = "k3s-master-01"
  target_node = var.target_node
  vmid        = 201
  clone       = "rocky9-template"

  agent   = 1
  cores   = 2
  sockets = 1
  memory  = 4096

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "20G"
  }

  os_type = "cloud-init"
  ciuser  = var.runner_user
  sshkeys = <<EOF
${var.ssh_public_key}
EOF
}

# [리소스 2] Home Assistant 서버 (HASSOS 기반)
resource "proxmox_vm_qemu" "home_assistant" {
  name        = "ha-core-01"
  target_node = var.target_node
  vmid        = 301
  clone       = "hassos-template" # 아까 qm importdisk로 만든 템플릿 이름

  agent   = 1
  cores   = 2
  sockets = 1
  memory  = 2048

  # HASSOS는 UEFI(OVMF) 부팅이 필수입니다.
  bios = "ovmf"

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "32G"
  }
}