# AWS Site-to-Site VPN Infrastructure
# This Terraform configuration creates a complete VPN connection between AWS and on-premises

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Local values for resource naming and tagging
locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )
}

# VPC for the VPN demonstration
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public subnet connectivity
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnet for resources that need internet access
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet"
    Type = "Public"
  })
}

# Private subnet for resources accessible only through VPN
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet"
    Type = "Private"
  })
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

# Route table for private subnet (will receive VPN routes via propagation)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Associate private subnet with private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Customer Gateway - represents the on-premises VPN device
resource "aws_customer_gateway" "main" {
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cgw"
  })
}

# Virtual Private Gateway - AWS side of the VPN connection
resource "aws_vpn_gateway" "main" {
  vpc_id          = aws_vpc.main.id
  amazon_side_asn = var.aws_bgp_asn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vgw"
  })
}

# Site-to-Site VPN Connection
resource "aws_vpn_connection" "main" {
  customer_gateway_id   = aws_customer_gateway.main.id
  type                  = "ipsec.1"
  vpn_gateway_id        = aws_vpn_gateway.main.id
  static_routes_only    = false # Enable BGP routing
  
  # Optional: specify tunnel inside CIDR blocks
  dynamic "tunnel1_inside_cidr" {
    for_each = length(var.tunnel_inside_cidr_blocks) > 0 ? [var.tunnel_inside_cidr_blocks[0]] : []
    content {
      tunnel1_inside_cidr = tunnel1_inside_cidr.value
    }
  }
  
  dynamic "tunnel2_inside_cidr" {
    for_each = length(var.tunnel_inside_cidr_blocks) > 1 ? [var.tunnel_inside_cidr_blocks[1]] : []
    content {
      tunnel2_inside_cidr = tunnel2_inside_cidr.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpn-connection"
  })
}

# Enable route propagation from VPN Gateway to private route table
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = aws_route_table.private.id
}

# Security group for VPN-accessible resources
resource "aws_security_group" "vpn" {
  name_prefix = "${local.name_prefix}-vpn-sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPN testing and on-premises access"

  # Allow SSH from on-premises network
  ingress {
    description = "SSH from on-premises"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.on_premises_cidr]
  }

  # Allow ICMP from on-premises network
  ingress {
    description = "ICMP from on-premises"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.on_premises_cidr]
  }

  # Allow all traffic from VPC
  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
    Name = "${local.name_prefix}-vpn-sg"
  })
}

# Test EC2 instance in private subnet (optional)
resource "aws_instance" "test" {
  count                  = var.create_test_instance ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.vpn.id]

  # User data script for basic configuration
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y htop tcpdump
    echo "VPN Test Instance - ${local.name_prefix}" > /tmp/instance-info.txt
    echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)" >> /tmp/instance-info.txt
    echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" >> /tmp/instance-info.txt
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-test-instance"
  })
}

# CloudWatch Log Group for VPN logs (optional)
resource "aws_cloudwatch_log_group" "vpn" {
  count             = var.enable_vpn_logs ? 1 : 0
  name              = "/aws/vpn/${local.name_prefix}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpn-logs"
  })
}

# CloudWatch Dashboard for VPN monitoring (optional)
resource "aws_cloudwatch_dashboard" "vpn" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-vpn-monitoring"

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
            ["AWS/VPN", "VpnState", "VpnId", aws_vpn_connection.main.id],
            [".", "VpnTunnelState", "VpnId", aws_vpn_connection.main.id, "TunnelIpAddress", aws_vpn_connection.main.tunnel1_address],
            [".", "VpnTunnelState", "VpnId", aws_vpn_connection.main.id, "TunnelIpAddress", aws_vpn_connection.main.tunnel2_address]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "VPN Connection Status"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/VPN", "VpnPacketsReceived", "VpnId", aws_vpn_connection.main.id],
            [".", "VpnPacketsSent", "VpnId", aws_vpn_connection.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "VPN Traffic (Packets)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/VPN", "VpnBytesReceived", "VpnId", aws_vpn_connection.main.id],
            [".", "VpnBytesSent", "VpnId", aws_vpn_connection.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "VPN Traffic (Bytes)"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpn-dashboard"
  })
}

# CloudWatch Alarms for VPN monitoring
resource "aws_cloudwatch_metric_alarm" "vpn_tunnel_down" {
  count               = 2
  alarm_name          = "${local.name_prefix}-vpn-tunnel-${count.index + 1}-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "VpnTunnelState"
  namespace           = "AWS/VPN"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors VPN tunnel ${count.index + 1} state"
  alarm_actions       = []

  dimensions = {
    VpnId           = aws_vpn_connection.main.id
    TunnelIpAddress = count.index == 0 ? aws_vpn_connection.main.tunnel1_address : aws_vpn_connection.main.tunnel2_address
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpn-tunnel-${count.index + 1}-alarm"
  })
}