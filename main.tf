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
  memory = 10240

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

  lifecycle {
    ignore_changes = [
      password,
      ssh_public_keys,
    ]
  }
}

# 내부 DNS (LXC 기반)
#
# 집 안 이름 해석을 담당한다. 공유기(ipTIME)는 로컬 레코드를 직접 넣을 수
# 없어 순수 포워더로만 동작하므로, 레코드를 들고 있을 주체가 따로 필요하다.
# 러너와 합치지 않는 이유는 역할 분리이기도 하고, 러너 LXC가 메모리 1GB에
# 컨테이너 빌드까지 돌려서 빌드 중에 집 전체 DNS가 눌릴 수 있기 때문이다.
#
# 생성 후 bootstrap-dns.sh 로 dnsmasq 를 설치한다.
resource "proxmox_lxc" "dns" {
  target_node = var.target_node
  hostname    = "dns-01"
  vmid        = 102
  ostemplate  = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  # LXC 콘솔 로그인용. 러너와 같은 시크릿을 재사용해 새 GitHub Secret 을
  # 늘리지 않는다. 실제 접속은 SSH 공개키로 한다.
  password     = var.runner_password
  unprivileged = true

  ssh_public_keys = var.ssh_public_key

  # dnsmasq 는 매우 가볍다. 캐시까지 포함해도 이 정도면 충분하다.
  cores  = 1
  memory = 512

  # 집 인터넷이 여기에 걸리므로 호스트 재부팅 후 반드시 자동 기동되어야 한다.
  onboot = true
  start  = true

  rootfs {
    storage = "local-lvm"
    size    = "4G"
  }
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "192.168.0.102/24"
    gw     = "192.168.0.1"
  }

  # 이 컨테이너가 집의 리졸버라 자기 자신을 상위로 둘 수 없다.
  # 업스트림을 직접 바라본다.
  nameserver = "8.8.8.8"

  lifecycle {
    ignore_changes = [
      password,
      ssh_public_keys,
    ]
  }
}