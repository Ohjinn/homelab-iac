# [리소스 1] K3s 마스터 노드 (Rocky 9 기반)
resource "proxmox_vm_qemu" "k3s_master" {
  name        = "k3s-master-01"
  target_node = var.target_node
  vmid        = 201
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
  memory = 4096

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

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

  agent = 1
  cpu {
    cores   = 2
    sockets = 1
  }
  memory = 2048

  # HASSOS는 UEFI(OVMF) 부팅이 필수입니다.
  bios    = "ovmf"
  machine = "q35"

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }


  efidisk {
    storage = "local-lvm"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "20"
          storage = "local-lvm"
        }
      }
    }
  }
}
