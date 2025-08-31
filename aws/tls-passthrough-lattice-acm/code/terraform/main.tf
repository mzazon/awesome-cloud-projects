# VPC Lattice TLS Passthrough Infrastructure
# This Terraform configuration deploys a complete VPC Lattice TLS passthrough solution
# with end-to-end encryption, load balancing, and certificate management

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get the latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Extract base domain from custom domain for Route 53 hosted zone
locals {
  base_domain = join(".", slice(split(".", var.custom_domain_name), 1, length(split(".", var.custom_domain_name))))
  name_prefix = "tls-passthrough-${random_id.suffix.hex}"
  
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Recipe      = "tls-passthrough-lattice-acm"
  })
}

#
# VPC and Networking Infrastructure
#

# Create VPC for target instances
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Create internet gateway for external connectivity
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Create subnet for target instances
resource "aws_subnet" "targets" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-targets-subnet"
  })
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create route table for internet access
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt"
  })
}

# Associate route table with subnet
resource "aws_route_table_association" "targets" {
  subnet_id      = aws_subnet.targets.id
  route_table_id = aws_route_table.main.id
}

# Security group for target instances
resource "aws_security_group" "targets" {
  name_prefix = "${local.name_prefix}-targets-"
  description = "Security group for VPC Lattice target instances"
  vpc_id      = aws_vpc.main.id
  
  # Allow HTTPS traffic from VPC Lattice service network range
  ingress {
    description = "HTTPS from VPC Lattice"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-targets-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

#
# Certificate Management
#

# Create ACM certificate if requested
resource "aws_acm_certificate" "main" {
  count = var.create_certificate ? 1 : 0
  
  domain_name               = var.certificate_domain
  subject_alternative_names = [var.custom_domain_name]
  validation_method         = "DNS"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-certificate"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Generate self-signed certificates for target instances
resource "tls_private_key" "target_cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "target_cert" {
  private_key_pem = tls_private_key.target_cert.private_key_pem
  
  subject {
    common_name  = var.custom_domain_name
    organization = "VPC Lattice Demo"
  }
  
  validity_period_hours = 8760 # 1 year
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

#
# Target EC2 Instances
#

# User data script for target instances
locals {
  user_data = base64encode(templatefile("${path.module}/user-data.tpl", {
    custom_domain   = var.custom_domain_name
    certificate_crt = tls_self_signed_cert.target_cert.cert_pem
    certificate_key = tls_private_key.target_cert.private_key_pem
  }))
}

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${local.name_prefix}-ec2-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${local.name_prefix}-ec2-"
  role        = aws_iam_role.ec2_role.name
  
  tags = local.common_tags
}

# Target EC2 instances
resource "aws_instance" "targets" {
  count = var.target_instance_count
  
  ami                    = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.targets.id
  vpc_security_group_ids = [aws_security_group.targets.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  user_data              = local.user_data
  monitoring             = var.enable_detailed_monitoring
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-${count.index + 1}"
  })
}

#
# VPC Lattice Infrastructure
#

# VPC Lattice service network
resource "aws_vpclattice_service_network" "main" {
  name      = "${local.name_prefix}-network"
  auth_type = "NONE"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service-network"
  })
}

# Associate VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = aws_vpc.main.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-association"
  })
}

# TCP target group for TLS passthrough
resource "aws_vpclattice_target_group" "main" {
  name     = "${local.name_prefix}-targets"
  type     = "INSTANCE"
  protocol = "TCP"
  port     = 443
  vpc_identifier = aws_vpc.main.id
  
  config {
    port     = 443
    protocol = "TCP"
    vpc_identifier = aws_vpc.main.id
    
    health_check {
      enabled                       = true
      protocol                      = "TCP"
      port                         = 443
      healthy_threshold_count      = 2
      unhealthy_threshold_count    = 2
      interval_seconds             = 30
      timeout_seconds              = 5
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-group"
  })
}

# Register target instances
resource "aws_vpclattice_target_group_attachment" "targets" {
  count = var.target_instance_count
  
  target_group_identifier = aws_vpclattice_target_group.main.id
  
  target {
    id   = aws_instance.targets[count.index].id
    port = 443
  }
}

# VPC Lattice service with custom domain
resource "aws_vpclattice_service" "main" {
  name               = "${local.name_prefix}-service"
  custom_domain_name = var.custom_domain_name
  certificate_arn    = var.create_certificate ? aws_acm_certificate.main[0].arn : var.certificate_arn
  auth_type          = "NONE"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service"
  })
  
  depends_on = [
    aws_acm_certificate.main
  ]
}

# Associate service with service network
resource "aws_vpclattice_service_network_service_association" "main" {
  service_identifier         = aws_vpclattice_service.main.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service-association"
  })
}

# TLS passthrough listener
resource "aws_vpclattice_listener" "main" {
  name               = "${local.name_prefix}-listener"
  protocol           = "TLS_PASSTHROUGH"
  port               = 443
  service_identifier = aws_vpclattice_service.main.id
  
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.main.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-listener"
  })
}

#
# DNS Configuration (Route 53)
#

# Create Route 53 hosted zone if requested
resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0
  
  name = local.base_domain
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hosted-zone"
  })
}

# Use existing or created hosted zone
locals {
  hosted_zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : var.route53_zone_id
}

# CNAME record pointing to VPC Lattice service
resource "aws_route53_record" "service" {
  count = local.hosted_zone_id != "" ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.custom_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [aws_vpclattice_service.main.dns_entry[0].domain_name]
}

