# =============================================================================
# Terraform Configuration for AWS WorkSpaces Infrastructure
# Creates a complete virtual desktop infrastructure with WorkSpaces, Simple AD,
# VPC networking, and CloudWatch monitoring
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Common tags applied to all resources
  common_tags = {
    Project     = "workforce-productivity-workspaces"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "virtual-desktop-infrastructure"
  }

  # Naming convention for resources
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get the latest WorkSpaces bundle for Windows Standard
data "aws_workspaces_bundle" "standard_windows" {
  bundle_id = var.workspace_bundle_id != "" ? var.workspace_bundle_id : null
  name      = var.workspace_bundle_id != "" ? null : "Standard with Windows 10 (Server 2019 based)"
}

# -----------------------------------------------------------------------------
# VPC and Networking Resources
# -----------------------------------------------------------------------------

# Create VPC for WorkSpaces
resource "aws_vpc" "workspaces_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public internet access
resource "aws_internet_gateway" "workspaces_igw" {
  vpc_id = aws_vpc.workspaces_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnet for NAT Gateway
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.workspaces_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet"
    Type = "Public"
  })
}

# Private subnet 1 for WorkSpaces
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.workspaces_vpc.id
  cidr_block        = var.private_subnet_1_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-1"
    Type = "Private"
  })
}

# Private subnet 2 for WorkSpaces (different AZ for high availability)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.workspaces_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-2"
    Type = "Private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip"
  })

  depends_on = [aws_internet_gateway.workspaces_igw]
}

# NAT Gateway for outbound internet access from private subnets
resource "aws_nat_gateway" "workspaces_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gateway"
  })

  depends_on = [aws_internet_gateway.workspaces_igw]
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.workspaces_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.workspaces_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

# Route table for private subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.workspaces_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.workspaces_nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Associate private subnet 1 with private route table
resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

# Associate private subnet 2 with private route table
resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# -----------------------------------------------------------------------------
# Directory Service (Simple AD)
# -----------------------------------------------------------------------------

# Create Simple AD directory for WorkSpaces authentication
resource "aws_directory_service_directory" "workspaces_directory" {
  name        = var.directory_name
  password    = var.directory_password
  size        = var.directory_size
  type        = "SimpleAD"
  description = "Simple AD directory for WorkSpaces authentication"

  vpc_settings {
    vpc_id     = aws_vpc.workspaces_vpc.id
    subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-simple-ad"
  })
}

# -----------------------------------------------------------------------------
# WorkSpaces Resources
# -----------------------------------------------------------------------------

# Register the directory with WorkSpaces
resource "aws_workspaces_directory" "workspaces_directory" {
  directory_id = aws_directory_service_directory.workspaces_directory.id
  subnet_ids   = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  # Optional features
  self_service_permissions {
    change_compute_type                 = var.self_service_permissions.change_compute_type
    increase_volume_size               = var.self_service_permissions.increase_volume_size
    rebuild_workspace                  = var.self_service_permissions.rebuild_workspace
    restart_workspace                  = var.self_service_permissions.restart_workspace
    switch_running_mode                = var.self_service_permissions.switch_running_mode
  }

  workspace_access_properties {
    device_type_android    = var.workspace_access_properties.device_type_android
    device_type_chromeos   = var.workspace_access_properties.device_type_chromeos
    device_type_ios        = var.workspace_access_properties.device_type_ios
    device_type_linux      = var.workspace_access_properties.device_type_linux
    device_type_osx        = var.workspace_access_properties.device_type_osx
    device_type_web        = var.workspace_access_properties.device_type_web
    device_type_windows    = var.workspace_access_properties.device_type_windows
    device_type_zeroclient = var.workspace_access_properties.device_type_zeroclient
  }

  workspace_creation_properties {
    custom_security_group_id            = aws_security_group.workspaces_sg.id
    default_ou                          = var.workspace_creation_properties.default_ou
    enable_internet_access              = var.workspace_creation_properties.enable_internet_access
    enable_maintenance_mode             = var.workspace_creation_properties.enable_maintenance_mode
    user_enabled_as_local_administrator = var.workspace_creation_properties.user_enabled_as_local_administrator
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-directory"
  })

  depends_on = [aws_directory_service_directory.workspaces_directory]
}

# Security Group for WorkSpaces
resource "aws_security_group" "workspaces_sg" {
  name_prefix = "${local.name_prefix}-workspaces-"
  description = "Security group for WorkSpaces instances"
  vpc_id      = aws_vpc.workspaces_vpc.id

  # Allow all outbound traffic for internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Allow inbound RDP from VPC (for management)
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow RDP from VPC"
  }

  # Allow HTTPS for WorkSpaces client connections
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS for WorkSpaces client"
  }

  # Allow WorkSpaces streaming protocol
  ingress {
    from_port   = 4172
    to_port     = 4172
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WorkSpaces streaming (TCP)"
  }

  ingress {
    from_port   = 4172
    to_port     = 4172
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WorkSpaces streaming (UDP)"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IP Access Control Group for WorkSpaces
resource "aws_workspaces_ip_group" "workspaces_ip_group" {
  name        = "${local.name_prefix}-ip-group"
  description = "IP access control group for WorkSpaces"

  # Allow access from specified IP ranges
  dynamic "rules" {
    for_each = var.allowed_ip_ranges
    content {
      source      = rules.value.cidr
      description = rules.value.description
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ip-group"
  })
}

# Associate IP group with WorkSpaces directory
resource "aws_workspaces_directory_ip_group_association" "workspaces_ip_association" {
  directory_id = aws_workspaces_directory.workspaces_directory.directory_id
  group_id     = aws_workspaces_ip_group.workspaces_ip_group.id
}

# Sample WorkSpace (optional - controlled by variable)
resource "aws_workspaces_workspace" "sample_workspace" {
  count = var.create_sample_workspace ? 1 : 0

  directory_id = aws_directory_service_directory.workspaces_directory.id
  bundle_id    = data.aws_workspaces_bundle.standard_windows.id
  user_name    = var.sample_workspace_username

  # Workspace properties
  root_volume_encryption_enabled = true
  user_volume_encryption_enabled = true
  volume_encryption_key          = var.workspace_encryption_key_id

  workspace_properties {
    compute_type_name                         = var.workspace_compute_type
    user_volume_size_gib                     = var.workspace_user_volume_size
    root_volume_size_gib                     = var.workspace_root_volume_size
    running_mode                             = var.workspace_running_mode
    running_mode_auto_stop_timeout_in_minutes = var.workspace_auto_stop_timeout
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sample-workspace"
    User = var.sample_workspace_username
  })

  depends_on = [aws_workspaces_directory.workspaces_directory]
}

# -----------------------------------------------------------------------------
# CloudWatch Monitoring
# -----------------------------------------------------------------------------

# CloudWatch Log Group for WorkSpaces
resource "aws_cloudwatch_log_group" "workspaces_log_group" {
  name              = "/aws/workspaces/${aws_directory_service_directory.workspaces_directory.id}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-logs"
  })
}

# CloudWatch Alarm for WorkSpace connection failures
resource "aws_cloudwatch_metric_alarm" "workspaces_connection_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-workspaces-connection-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConnectionAttempt"
  namespace           = "AWS/WorkSpaces"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors WorkSpace connection failures"
  alarm_actions       = var.cloudwatch_alarm_actions

  dimensions = {
    DirectoryId = aws_directory_service_directory.workspaces_directory.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connection-failures-alarm"
  })
}

# CloudWatch Alarm for WorkSpace session disconnections
resource "aws_cloudwatch_metric_alarm" "workspaces_session_disconnections" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-workspaces-session-disconnections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SessionDisconnect"
  namespace           = "AWS/WorkSpaces"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors WorkSpace session disconnections"
  alarm_actions       = var.cloudwatch_alarm_actions

  dimensions = {
    DirectoryId = aws_directory_service_directory.workspaces_directory.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-session-disconnections-alarm"
  })
}

# -----------------------------------------------------------------------------
# Optional SNS Topic for Notifications
# -----------------------------------------------------------------------------

# SNS Topic for WorkSpaces alerts (created only if no existing alarm actions provided)
resource "aws_sns_topic" "workspaces_alerts" {
  count = var.enable_cloudwatch_alarms && length(var.cloudwatch_alarm_actions) == 0 ? 1 : 0

  name = "${local.name_prefix}-workspaces-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workspaces-alerts"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "workspaces_email_alerts" {
  count = var.enable_cloudwatch_alarms && length(var.cloudwatch_alarm_actions) == 0 && var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.workspaces_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}