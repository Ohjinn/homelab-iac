resource "proxmox_vm_qemu" "home_assistant" {
  name        = "ha-core-01"
  target_node = "pve"
  vmid        = 301
  
  # HASSOS 템플릿 (미리 이미지를 임포트해두어야 합니다)
  clone = "hassos-template"

  agent   = 1
  cores   = 2
  memory  = 2048
  balloon = 1024

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "32G"
  }

  # 전동커튼용 Zigbee 동글을 위한 USB 패스스루 설정 (필요 시)
  # usb {
  #   host = "0000:0000" # 실제 동글의 ID로 수정
  # }
}