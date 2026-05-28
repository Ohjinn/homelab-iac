# K3s 마스터 노드 (Rocky 9)
resource "proxmox_vm_qemu" "k3s_master" {
  name        = "k3s-master-01"
  target_node = var.target_node
  vmid        = 151
  clone       = "rocky9-template"

  scsihw = "virtio-scsi-pci"
  serial {
    id   = 0
    type = "socket"
  }
  vga {
    type = "serial0"
  }

  agent = 1
  cpu {
    cores   = 2
    sockets = 1
  }
  memory = 6144

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  nameserver = "8.8.8.8"

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "20"
          storage = "local-lvm"
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  os_type = "cloud-init"
  ciuser  = var.runner_user
  sshkeys = var.ssh_public_key

  ipconfig0 = "ip=192.168.0.151/24,gw=192.168.0.1"

  tags = "k3s"

}

# Home Assistant 서버 (HASSOS 기반)
resource "proxmox_vm_qemu" "home_assistant" {
  name        = "ha-core-01"
  target_node = var.target_node
  vmid        = 111
  clone       = "hassos-template" # qm importdisk로 만든 템플릿 이름

  agent = 1
  cpu {
    cores   = 2
    sockets = 1
  }
  memory  = 3072
  balloon = 0 # HASSOS는 ballooning을 지원하지 않으므로 비활성화

  # HASSOS는 UEFI(OVMF) 부팅이 필수입니다.
  bios    = "ovmf"
  machine = "q35"

  scsihw = "virtio-scsi-pci"
  boot   = "order=scsi0"

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  efidisk {
    storage = "local-lvm"
  }

  ipconfig0 = "ip=192.168.0.200/24,gw=192.168.0.1" # HA라 실제로 적용 안될
  skip_ipv6 = true

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "local-lvm"
          size    = "32G"
        }
      }
    }
  }

  tags = "home-assistant"

  lifecycle {
    ignore_changes = [
      usbs,
      # network,
    ]
  }
}

# GitHub Runner (LXC 기반)
resource "proxmox_lxc" "github_runner" {
  target_node  = var.target_node
  hostname     = "github-runner-01"
  vmid         = 101
  ostemplate   = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  password     = var.runner_password
  unprivileged = true 

  ssh_public_keys = var.ssh_public_key

  cores  = 2
  memory = 1024

  rootfs {
    storage = "local-lvm"
    size    = "10G"
  }
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.0.101/24"
    gw     = "192.168.0.1"
  }

  nameserver = "8.8.8.8"

  features {
    nesting = true
  }
}