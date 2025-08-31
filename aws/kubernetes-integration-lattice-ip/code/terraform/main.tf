# main.tf - Main configuration for Kubernetes VPC Lattice integration

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get VPC Lattice managed prefix list for health checks
data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${var.aws_region}.vpc-lattice"]
  }
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed configurations
locals {
  resource_suffix = random_string.suffix.result
  common_tags = {
    Project     = "kubernetes-lattice-integration"
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "kubernetes-integration-lattice-ip"
  }
}

# ================================
# SSH Key Pair for EC2 Access
# ================================

# Create SSH key pair for EC2 instances
resource "tls_private_key" "k8s_key" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_key" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = "${var.resource_prefix}-${local.resource_suffix}"
  public_key = tls_private_key.k8s_key[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-key-${local.resource_suffix}"
  })
}

# ================================
# VPC Infrastructure for Cluster A
# ================================

# VPC A for Kubernetes cluster A
resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-vpc-a-${local.resource_suffix}"
  })
}

# Internet Gateway for VPC A
resource "aws_internet_gateway" "igw_a" {
  vpc_id = aws_vpc.vpc_a.id

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-igw-a-${local.resource_suffix}"
  })
}

# Public subnet in VPC A
resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-subnet-a-${local.resource_suffix}"
  })
}

# Route table for VPC A
resource "aws_route_table" "rt_a" {
  vpc_id = aws_vpc.vpc_a.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_a.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-rt-a-${local.resource_suffix}"
  })
}

# Associate route table with subnet A
resource "aws_route_table_association" "rta_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.rt_a.id
}

# ================================
# VPC Infrastructure for Cluster B
# ================================

# VPC B for Kubernetes cluster B
resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-vpc-b-${local.resource_suffix}"
  })
}

# Internet Gateway for VPC B
resource "aws_internet_gateway" "igw_b" {
  vpc_id = aws_vpc.vpc_b.id

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-igw-b-${local.resource_suffix}"
  })
}

# Public subnet in VPC B
resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = var.subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-subnet-b-${local.resource_suffix}"
  })
}

# Route table for VPC B
resource "aws_route_table" "rt_b" {
  vpc_id = aws_vpc.vpc_b.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_b.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-rt-b-${local.resource_suffix}"
  })
}

# Associate route table with subnet B
resource "aws_route_table_association" "rta_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.rt_b.id
}

# ================================
# Security Groups
# ================================

# Security group for Kubernetes cluster A
resource "aws_security_group" "k8s_cluster_a" {
  name_prefix = "${var.resource_prefix}-cluster-a-"
  description = "Security group for Kubernetes cluster A"
  vpc_id      = aws_vpc.vpc_a.id

  # Allow all traffic within the security group (Kubernetes communication)
  ingress {
    description = "Allow all traffic within security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # VPC Lattice health checks for frontend service
  ingress {
    description     = "VPC Lattice health checks"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-sg-cluster-a-${local.resource_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for Kubernetes cluster B
resource "aws_security_group" "k8s_cluster_b" {
  name_prefix = "${var.resource_prefix}-cluster-b-"
  description = "Security group for Kubernetes cluster B"
  vpc_id      = aws_vpc.vpc_b.id

  # Allow all traffic within the security group (Kubernetes communication)
  ingress {
    description = "Allow all traffic within security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # VPC Lattice health checks for backend service
  ingress {
    description     = "VPC Lattice health checks"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-sg-cluster-b-${local.resource_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ================================
# EC2 Instances for Kubernetes
# ================================

# User data script for Kubernetes installation
locals {
  k8s_user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    kubernetes_version = var.kubernetes_version
  }))
}

# EC2 instance for Kubernetes cluster A
resource "aws_instance" "k8s_cluster_a" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  key_name                = var.create_key_pair ? aws_key_pair.k8s_key[0].key_name : null
  subnet_id               = aws_subnet.subnet_a.id
  vpc_security_group_ids  = [aws_security_group.k8s_cluster_a.id]
  user_data               = local.k8s_user_data
  disable_api_termination = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-cluster-a-${local.resource_suffix}"
  })
}

# EC2 instance for Kubernetes cluster B
resource "aws_instance" "k8s_cluster_b" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  key_name                = var.create_key_pair ? aws_key_pair.k8s_key[0].key_name : null
  subnet_id               = aws_subnet.subnet_b.id
  vpc_security_group_ids  = [aws_security_group.k8s_cluster_b.id]
  user_data               = local.k8s_user_data
  disable_api_termination = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-cluster-b-${local.resource_suffix}"
  })
}

# ================================
# VPC Lattice Service Network
# ================================

# VPC Lattice service network
resource "aws_vpclattice_service_network" "k8s_mesh" {
  name = "${var.resource_prefix}-mesh-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-service-network-${local.resource_suffix}"
  })
}

# Associate VPC A with the service network
resource "aws_vpclattice_service_network_vpc_association" "vpc_a_association" {
  vpc_identifier             = aws_vpc.vpc_a.id
  service_network_identifier = aws_vpclattice_service_network.k8s_mesh.id
  security_group_ids         = [aws_security_group.k8s_cluster_a.id]

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-vpc-a-association-${local.resource_suffix}"
  })
}

# Associate VPC B with the service network
resource "aws_vpclattice_service_network_vpc_association" "vpc_b_association" {
  vpc_identifier             = aws_vpc.vpc_b.id
  service_network_identifier = aws_vpclattice_service_network.k8s_mesh.id
  security_group_ids         = [aws_security_group.k8s_cluster_b.id]

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-vpc-b-association-${local.resource_suffix}"
  })
}

# ================================
# VPC Lattice Target Groups
# ================================

# Target group for frontend service (VPC A)
resource "aws_vpclattice_target_group" "frontend" {
  name = "${var.resource_prefix}-frontend-tg-${local.resource_suffix}"
  type = "IP"

  config {
    port           = 8080
    protocol       = "HTTP"
    vpc_identifier = aws_vpc.vpc_a.id
    
    health_check {
      enabled                       = true
      health_check_interval_seconds = var.health_check_interval
      health_check_timeout_seconds  = var.health_check_timeout
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 3
      path                         = "/health"
      port                         = 8080
      protocol                     = "HTTP"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-frontend-target-group-${local.resource_suffix}"
  })
}

# Target group for backend service (VPC B)
resource "aws_vpclattice_target_group" "backend" {
  name = "${var.resource_prefix}-backend-tg-${local.resource_suffix}"
  type = "IP"

  config {
    port           = 9090
    protocol       = "HTTP"
    vpc_identifier = aws_vpc.vpc_b.id
    
    health_check {
      enabled                       = true
      health_check_interval_seconds = var.health_check_interval
      health_check_timeout_seconds  = var.health_check_timeout
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 3
      path                         = "/health"
      port                         = 9090
      protocol                     = "HTTP"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-backend-target-group-${local.resource_suffix}"
  })
}

# Register EC2 instance A as target (simulating pod IP)
resource "aws_vpclattice_target_group_attachment" "frontend_target" {
  target_group_identifier = aws_vpclattice_target_group.frontend.id

  target {
    id   = aws_instance.k8s_cluster_a.private_ip
    port = 8080
  }
}

# Register EC2 instance B as target (simulating pod IP)
resource "aws_vpclattice_target_group_attachment" "backend_target" {
  target_group_identifier = aws_vpclattice_target_group.backend.id

  target {
    id   = aws_instance.k8s_cluster_b.private_ip
    port = 9090
  }
}

# ================================
# VPC Lattice Services
# ================================

# Frontend service
resource "aws_vpclattice_service" "frontend" {
  name = "${var.resource_prefix}-frontend-svc-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-frontend-service-${local.resource_suffix}"
  })
}

# Backend service
resource "aws_vpclattice_service" "backend" {
  name = "${var.resource_prefix}-backend-svc-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-backend-service-${local.resource_suffix}"
  })
}

# ================================
# VPC Lattice Listeners
# ================================

# Listener for frontend service
resource "aws_vpclattice_listener" "frontend" {
  name               = "frontend-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.frontend.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.frontend.id
        weight                  = 100
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-frontend-listener-${local.resource_suffix}"
  })
}

# Listener for backend service
resource "aws_vpclattice_listener" "backend" {
  name               = "backend-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.backend.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.backend.id
        weight                  = 100
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-backend-listener-${local.resource_suffix}"
  })
}

# ================================
# Service Network Associations
# ================================

# Associate frontend service with service network
resource "aws_vpclattice_service_network_service_association" "frontend" {
  service_identifier         = aws_vpclattice_service.frontend.id
  service_network_identifier = aws_vpclattice_service_network.k8s_mesh.id

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-frontend-service-association-${local.resource_suffix}"
  })
}

# Associate backend service with service network
resource "aws_vpclattice_service_network_service_association" "backend" {
  service_identifier         = aws_vpclattice_service.backend.id
  service_network_identifier = aws_vpclattice_service_network.k8s_mesh.id

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-backend-service-association-${local.resource_suffix}"
  })
}

# ================================
# CloudWatch Monitoring (Optional)
# ================================

# CloudWatch log group for VPC Lattice access logs
resource "aws_cloudwatch_log_group" "vpc_lattice" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/vpc-lattice/${aws_vpclattice_service_network.k8s_mesh.name}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-vpc-lattice-logs-${local.resource_suffix}"
  })
}

# VPC Lattice access log subscription
resource "aws_vpclattice_access_log_subscription" "k8s_mesh" {
  count                      = var.enable_monitoring ? 1 : 0
  service_network_identifier = aws_vpclattice_service_network.k8s_mesh.id
  destination_arn           = aws_cloudwatch_log_group.vpc_lattice[0].arn

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-access-logs-${local.resource_suffix}"
  })
}

# CloudWatch dashboard for service mesh monitoring
resource "aws_cloudwatch_dashboard" "vpc_lattice" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${var.resource_prefix}-lattice-dashboard-${local.resource_suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/VPCLattice", "ActiveConnectionCount", "ServiceNetwork", aws_vpclattice_service_network.k8s_mesh.id],
            ["AWS/VPCLattice", "NewConnectionCount", "ServiceNetwork", aws_vpclattice_service_network.k8s_mesh.id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "VPC Lattice Service Network Connections"
          period  = 300
        }
      }
    ]
  })
}