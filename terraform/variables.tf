variable "aws_region" {
  description = "AWS region for all lab resources."
  type        = string
  default     = "ap-southeast-2"
}

variable "name_prefix" {
  description = "Short unique prefix used for resource names."
  type        = string
  default     = "fynd-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}$", var.name_prefix))
    error_message = "name_prefix must be 2-19 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "operator_ip_cidr" {
  description = "Public IPv4 CIDR allowed to reach the WireGuard UDP listener. Use your current /32 where practical."
  type        = string
  validation {
    condition     = can(cidrhost(var.operator_ip_cidr, 0))
    error_message = "operator_ip_cidr must be a valid IPv4 CIDR."
  }
}

variable "wireguard_server_private_key" {
  description = "Generated WireGuard server private key; supplied by lab.sh and stored only in encrypted Terraform state/user data."
  type        = string
  sensitive   = true
}

variable "wireguard_client_public_key" {
  description = "Public key for the local WireGuard peer."
  type        = string
}

variable "indexer_password" {
  description = "Strong password for the Wazuh indexer admin account."
  type        = string
  sensitive   = true
}

variable "wazuh_api_password" {
  description = "Strong password for the Wazuh dashboard/API account."
  type        = string
  sensitive   = true
}

variable "app_instance_type" {
  description = "EC2 instance type for WireGuard, the WAF, and Juice Shop."
  type        = string
  default     = "t3.small"
}

variable "wazuh_instance_type" {
  description = "Wazuh EC2 type. m7i-flex.large (2 vCPU / 8 GiB) is Free plan eligible only for qualifying accounts created on/after 2025-07-15; it remains below Wazuh's 4-vCPU recommendation. Check account eligibility and regional quota."
  type        = string
  default     = "m7i-flex.large"
}

variable "wazuh_version" {
  description = "Wazuh version for the manager/indexer/dashboard (git tag of wazuh-docker) and the agent. The agent must not be newer than the manager."
  type        = string
  default     = "4.12.0"
}
