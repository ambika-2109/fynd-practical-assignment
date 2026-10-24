output "app_public_ip" {
  description = "Public IP of the WireGuard gateway (UDP listener only)."
  value       = aws_instance.app.public_ip
}

output "app_private_ip" {
  description = "VPN-only Juice Shop / WAF URL host."
  value       = aws_instance.app.private_ip
}

output "wazuh_private_ip" {
  description = "VPN-only Wazuh dashboard and Indexer address."
  value       = aws_instance.wazuh.private_ip
}

output "vpc_cidr" {
  value = aws_vpc.lab.cidr_block
}