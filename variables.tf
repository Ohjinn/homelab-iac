# Proxmox 연결 설정
variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API 접속 주소"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API 토큰 ID"
}

variable "proxmox_api_token_secret" {
  type        = string
  description = "Proxmox API 토큰 시크릿"
  sensitive   = true
}

# 공통 자원 설정
variable "target_node" {
  type        = string
  default     = "pve"
  description = "대상 Proxmox 노드 이름"
}

variable "ssh_public_key" {
  type        = string
  description = "VM에 주입할 맥북의 SSH 공개키"
}

variable "runner_user" {
  type        = string
  default     = "runner-user"
  description = "Cloud-init으로 생성할 기본 계정"
}

variable "runner_password" {
  type        = string
  description = "runner-user 계정의 비밀번호"
  sensitive   = true
}