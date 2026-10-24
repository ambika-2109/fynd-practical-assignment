data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "free-tier-eligible"
    values = ["true"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Upstream OS, Docker, and Wazuh package registries use changing public IPs; egress is restricted to HTTP/HTTPS.
#trivy:ignore:AVD-AWS-0104:exp:2027-10-24
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app"
  description = "WireGuard public endpoint; application is reachable only through the VPN."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Encrypted WireGuard tunnel"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = [var.operator_ip_cidr]
  }

  ingress {
    description = "VPN-forwarded application traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "HTTP package repositories"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS package registries and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.42.0.2/32"]
  }

  egress {
    description = "TCP DNS fallback to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.2/32"]
  }

  egress {
    description = "WireGuard client traffic to Wazuh services inside the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.0/16"]
  }

  egress {
    description = "Wazuh Indexer access inside the VPC"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.0/16"]
  }

  egress {
    description = "Wazuh agent enrollment and event traffic inside the VPC"
    from_port   = 1514
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.0/16"]
  }

  egress {
    description = "Wazuh agent events inside the VPC"
    from_port   = 1514
    to_port     = 1514
    protocol    = "udp"
    cidr_blocks = ["10.42.0.0/16"]
  }

  tags = { Name = "${var.name_prefix}-app" }
}

# Wazuh bootstrap pulls OS/container packages from upstream repositories; restrict internet egress to HTTP/HTTPS.
#trivy:ignore:AVD-AWS-0104:exp:2027-10-24
resource "aws_security_group" "wazuh" {
  name        = "${var.name_prefix}-wazuh"
  description = "Wazuh access is permitted only from the VPN gateway instance."
  vpc_id      = aws_vpc.lab.id

  dynamic "ingress" {
    for_each = [443, 9200, 1514, 1515]
    content {
      description     = "VPN gateway to Wazuh port ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.app.id]
    }
  }

  ingress {
    description     = "Wazuh agent events over TCP"
    from_port       = 1514
    to_port         = 1514
    protocol        = "udp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "HTTP package repositories"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS package registries and AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.42.0.2/32"]
  }

  egress {
    description = "TCP DNS fallback to the VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.42.0.2/32"]
  }

  tags = { Name = "${var.name_prefix}-wazuh" }
}

resource "aws_iam_role" "ssm" {
  name = "${var.name_prefix}-ssm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_ssm_parameter" "wireguard_server_key" {
  name        = "/${var.name_prefix}/wireguard/server-private-key"
  description = "WireGuard server private key for the lab gateway."
  type        = "SecureString"
  value       = var.wireguard_server_private_key
}

resource "aws_ssm_parameter" "indexer_password" {
  name        = "/${var.name_prefix}/wazuh/indexer-password"
  description = "Wazuh Indexer administrator password."
  type        = "SecureString"
  value       = var.indexer_password
}

resource "aws_ssm_parameter" "wazuh_api_password" {
  name        = "/${var.name_prefix}/wazuh/api-password"
  description = "Wazuh API/dashboard service password."
  type        = "SecureString"
  value       = var.wazuh_api_password
}

resource "aws_iam_role_policy" "lab_secrets" {
  name = "${var.name_prefix}-read-lab-secrets"
  role = aws_iam_role.ssm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:GetParameter"]
      Resource = [
        aws_ssm_parameter.wireguard_server_key.arn,
        aws_ssm_parameter.indexer_password.arn,
        aws_ssm_parameter.wazuh_api_password.arn,
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name_prefix}-ssm"
  role = aws_iam_role.ssm.name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.app_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/app-bootstrap.sh.tftpl", {
    client_public_key    = var.wireguard_client_public_key
    wazuh_manager_ip     = aws_instance.wazuh.private_ip
    server_key_parameter = aws_ssm_parameter.wireguard_server_key.name
    aws_region           = var.aws_region
    wazuh_version        = var.wazuh_version
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required"
  }

  depends_on = [aws_route_table_association.public, aws_iam_role_policy_attachment.ssm, aws_iam_role_policy.lab_secrets]
  tags       = { Name = "${var.name_prefix}-app" }

  # Pin the running app to its current AMI/bootstrap until a deliberate replacement is reviewed.
  # To intentionally rerun app bootstrap: terraform apply -replace=aws_instance.app
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_instance" "wazuh" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.wazuh_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.wazuh.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/wazuh-bootstrap.sh.tftpl", {
    indexer_password_parameter = aws_ssm_parameter.indexer_password.name
    api_password_parameter     = aws_ssm_parameter.wazuh_api_password.name
    aws_region                 = var.aws_region
    wazuh_version              = var.wazuh_version
  })

  root_block_device {
    volume_size           = 80
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }


  metadata_options {
    http_tokens = "required"
  }

  depends_on = [aws_route_table_association.public, aws_iam_role_policy_attachment.ssm, aws_iam_role_policy.lab_secrets]
  tags       = { Name = "${var.name_prefix}-wazuh" }

  # Pin Wazuh to its current AMI/bootstrap until a deliberate replacement is reviewed.
  # Replacement deletes this instance's root disk and Wazuh Docker volumes unless they are snapshotted.
  # To intentionally rerun Wazuh bootstrap: terraform apply -replace=aws_instance.wazuh
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
