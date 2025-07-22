# Network Micro-Segmentation with NACLs and Advanced Security Groups
# This configuration implements a comprehensive micro-segmentation strategy
# using layered security controls for defense-in-depth

# Data source for current AWS region and caller identity
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "microseg-${random_string.suffix.result}"
  
  # Determine availability zone - use first AZ if not specified
  availability_zone = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Project     = "network-micro-segmentation"
    ManagedBy   = "terraform"
  })
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# VPC AND NETWORKING FOUNDATION
# =============================================================================

# Create VPC for micro-segmentation
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public internet access
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# =============================================================================
# SUBNET CREATION FOR EACH SECURITY ZONE
# =============================================================================

# DMZ Subnet (Internet-facing)
resource "aws_subnet" "dmz" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.dmz
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dmz-subnet"
    Zone = "dmz"
    Type = "public"
  })
}

# Web Tier Subnet
resource "aws_subnet" "web" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.web
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-subnet"
    Zone = "web"
    Type = "private"
  })
}

# Application Tier Subnet
resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.app
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-subnet"
    Zone = "app"
    Type = "private"
  })
}

# Database Tier Subnet
resource "aws_subnet" "database" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.database
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet"
    Zone = "database"
    Type = "private"
  })
}

# Management Subnet
resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.management
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-subnet"
    Zone = "management"
    Type = "private"
  })
}

# Monitoring Subnet
resource "aws_subnet" "monitoring" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.monitoring
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mon-subnet"
    Zone = "monitoring"
    Type = "private"
  })
}

# =============================================================================
# ROUTE TABLES AND ROUTING
# =============================================================================

# Route table for public subnet (DMZ)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
    Type = "public"
  })
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
    Type = "private"
  })
}

# Route table associations
resource "aws_route_table_association" "dmz" {
  subnet_id      = aws_subnet.dmz.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "web" {
  subnet_id      = aws_subnet.web.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "database" {
  subnet_id      = aws_subnet.database.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "monitoring" {
  subnet_id      = aws_subnet.monitoring.id
  route_table_id = aws_route_table.private.id
}

# =============================================================================
# NETWORK ACCESS CONTROL LISTS (NACLs)
# =============================================================================

# DMZ NACL (Internet-facing zone)
resource "aws_network_acl" "dmz" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  
  # Outbound rules
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.web
    from_port  = 80
    to_port    = 80
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.web
    from_port  = 443
    to_port    = 443
  }
  
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dmz-nacl"
    Zone = "dmz"
  })
}

# Web Tier NACL
resource "aws_network_acl" "web" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.dmz
    from_port  = 80
    to_port    = 80
  }
  
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.dmz
    from_port  = 443
    to_port    = 443
  }
  
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.management
    from_port  = 22
    to_port    = 22
  }
  
  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.monitoring
    from_port  = 161
    to_port    = 161
  }
  
  # Outbound rules
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.app
    from_port  = 8080
    to_port    = 8080
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.dmz
    from_port  = 1024
    to_port    = 65535
  }
  
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-nacl"
    Zone = "web"
  })
}

# Application Tier NACL
resource "aws_network_acl" "app" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.web
    from_port  = 8080
    to_port    = 8080
  }
  
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.management
    from_port  = 22
    to_port    = 22
  }
  
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.monitoring
    from_port  = 161
    to_port    = 161
  }
  
  # Outbound rules
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.database
    from_port  = 3306
    to_port    = 3306
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.web
    from_port  = 1024
    to_port    = 65535
  }
  
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-nacl"
    Zone = "app"
  })
}

# Database Tier NACL (Most restrictive)
resource "aws_network_acl" "database" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.app
    from_port  = 3306
    to_port    = 3306
  }
  
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.management
    from_port  = 22
    to_port    = 22
  }
  
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.monitoring
    from_port  = 161
    to_port    = 161
  }
  
  # Outbound rules
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.app
    from_port  = 1024
    to_port    = 65535
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-nacl"
    Zone = "database"
  })
}

# Management NACL
resource "aws_network_acl" "management" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules - Allow VPN/Admin access
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.management_access_cidr
    from_port  = 22
    to_port    = 22
  }
  
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.management_access_cidr
    from_port  = 443
    to_port    = 443
  }
  
  # Outbound rules - Allow access to all internal subnets
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-nacl"
    Zone = "management"
  })
}

# Monitoring NACL
resource "aws_network_acl" "monitoring" {
  vpc_id = aws_vpc.main.id
  
  # Inbound rules - Allow from management
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.subnet_cidrs.management
    from_port  = 22
    to_port    = 22
  }
  
  # Outbound rules - Allow monitoring access to all zones
  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 161
    to_port    = 161
  }
  
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mon-nacl"
    Zone = "monitoring"
  })
}

# =============================================================================
# NACL SUBNET ASSOCIATIONS
# =============================================================================

resource "aws_network_acl_association" "dmz" {
  network_acl_id = aws_network_acl.dmz.id
  subnet_id      = aws_subnet.dmz.id
}

resource "aws_network_acl_association" "web" {
  network_acl_id = aws_network_acl.web.id
  subnet_id      = aws_subnet.web.id
}

resource "aws_network_acl_association" "app" {
  network_acl_id = aws_network_acl.app.id
  subnet_id      = aws_subnet.app.id
}

resource "aws_network_acl_association" "database" {
  network_acl_id = aws_network_acl.database.id
  subnet_id      = aws_subnet.database.id
}

resource "aws_network_acl_association" "management" {
  network_acl_id = aws_network_acl.management.id
  subnet_id      = aws_subnet.management.id
}

resource "aws_network_acl_association" "monitoring" {
  network_acl_id = aws_network_acl.monitoring.id
  subnet_id      = aws_subnet.monitoring.id
}

# =============================================================================
# SECURITY GROUPS WITH LAYERED RULES
# =============================================================================

# DMZ Security Group (Application Load Balancer)
resource "aws_security_group" "dmz_alb" {
  name_prefix = "${local.name_prefix}-dmz-alb-"
  description = "Security group for Application Load Balancer in DMZ"
  vpc_id      = aws_vpc.main.id
  
  # HTTP access from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # HTTPS access from internet
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Outbound to web tier
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dmz-alb-sg"
    Zone = "dmz"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Web Tier Security Group
resource "aws_security_group" "web_tier" {
  name_prefix = "${local.name_prefix}-web-tier-"
  description = "Security group for Web Tier instances"
  vpc_id      = aws_vpc.main.id
  
  # HTTP from DMZ ALB
  ingress {
    description     = "HTTP from DMZ ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.dmz_alb.id]
  }
  
  # HTTPS from DMZ ALB
  ingress {
    description     = "HTTPS from DMZ ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.dmz_alb.id]
  }
  
  # SSH from Management
  ingress {
    description     = "SSH from Management"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.management.id]
  }
  
  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-tier-sg"
    Zone = "web"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Application Tier Security Group
resource "aws_security_group" "app_tier" {
  name_prefix = "${local.name_prefix}-app-tier-"
  description = "Security group for Application Tier instances"
  vpc_id      = aws_vpc.main.id
  
  # Application port from Web Tier
  ingress {
    description     = "Application port from Web Tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_tier.id]
  }
  
  # SSH from Management
  ingress {
    description     = "SSH from Management"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.management.id]
  }
  
  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-tier-sg"
    Zone = "app"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Database Tier Security Group (Most restrictive)
resource "aws_security_group" "database_tier" {
  name_prefix = "${local.name_prefix}-db-tier-"
  description = "Security group for Database Tier"
  vpc_id      = aws_vpc.main.id
  
  # MySQL/MariaDB from App Tier
  ingress {
    description     = "MySQL from App Tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_tier.id]
  }
  
  # SSH from Management
  ingress {
    description     = "SSH from Management"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.management.id]
  }
  
  # Restricted outbound (HTTPS only for updates)
  egress {
    description = "HTTPS for updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-tier-sg"
    Zone = "database"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Management Security Group
resource "aws_security_group" "management" {
  name_prefix = "${local.name_prefix}-mgmt-"
  description = "Security group for Management resources"
  vpc_id      = aws_vpc.main.id
  
  # SSH from VPN/Admin networks
  ingress {
    description = "SSH from Admin networks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.management_access_cidr]
  }
  
  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-sg"
    Zone = "management"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# VPC FLOW LOGS AND MONITORING
# =============================================================================

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_logs_role" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name_prefix = "${local.name_prefix}-flow-logs-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-logs-role"
  })
}

# Attach policy to IAM role
resource "aws_iam_role_policy_attachment" "flow_logs_policy" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  role       = aws_iam_role.flow_logs_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy"
}

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name              = "/aws/vpc/${local.name_prefix}/flowlogs"
  retention_in_days = var.flow_logs_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-logs"
  })
}

# VPC Flow Logs
resource "aws_flow_log" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  iam_role_arn    = aws_iam_role.flow_logs_role[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}

# CloudWatch Alarm for Rejected Traffic
resource "aws_cloudwatch_metric_alarm" "rejected_traffic" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-rejected-traffic-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PacketsDropped"
  namespace           = "AWS/VPC"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.rejected_traffic_threshold
  alarm_description   = "This metric monitors rejected packets in VPC"
  alarm_actions       = []
  
  dimensions = {
    VpcId = aws_vpc.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rejected-traffic-alarm"
  })
}

# =============================================================================
# KEY PAIR (OPTIONAL)
# =============================================================================

# Generate key pair for EC2 instances
resource "aws_key_pair" "main" {
  count = var.create_key_pair ? 1 : 0
  
  key_name   = var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-key"
  public_key = tls_private_key.main[0].public_key_openssh
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-key-pair"
  })
}

# Generate private key
resource "tls_private_key" "main" {
  count = var.create_key_pair ? 1 : 0
  
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key to local file
resource "local_file" "private_key" {
  count = var.create_key_pair ? 1 : 0
  
  content         = tls_private_key.main[0].private_key_pem
  filename        = "${path.module}/${local.name_prefix}-key.pem"
  file_permission = "0400"
}