# Main Terraform configuration for EFS mounting strategies

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for VPC and subnet information
data "aws_vpc" "selected" {
  id      = var.vpc_id
  default = var.vpc_id == null ? true : null
}

data "aws_subnets" "selected" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

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
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local values for computed configurations
locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # Use provided subnet IDs or fall back to default VPC subnets
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected[0].ids
  
  # Limit to first 3 subnets for mount targets
  mount_target_subnets = slice(local.subnet_ids, 0, min(length(local.subnet_ids), 3))
  
  # Common tags
  common_tags = merge(
    var.tags,
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    }
  )
}

# Create EFS file system
resource "aws_efs_file_system" "main" {
  creation_token   = local.name_prefix
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  encrypted        = var.efs_encryption
  
  # Set provisioned throughput only if mode is provisioned
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null
  
  # Enable lifecycle management for cost optimization
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-efs"
    }
  )
}

# Create security group for EFS mount targets
resource "aws_security_group" "efs_mount_targets" {
  name_prefix = "${local.name_prefix}-efs-mount-"
  description = "Security group for EFS mount targets"
  vpc_id      = data.aws_vpc.selected.id
  
  # Allow NFS traffic from VPC
  ingress {
    description = "NFS traffic from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-efs-mount-sg"
    }
  )
}

# Create EFS mount targets in multiple availability zones
resource "aws_efs_mount_target" "main" {
  count = length(local.mount_target_subnets)
  
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = local.mount_target_subnets[count.index]
  security_groups = [aws_security_group.efs_mount_targets.id]
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-efs-mount-target-${count.index + 1}"
    }
  )
}

# Create EFS access points for different use cases
resource "aws_efs_access_point" "access_points" {
  for_each = var.create_access_points ? var.access_point_configs : {}
  
  file_system_id = aws_efs_file_system.main.id
  
  posix_user {
    uid = each.value.uid
    gid = each.value.gid
  }
  
  root_directory {
    path = each.value.path
    
    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = each.value.permissions
    }
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-${each.key}-access-point"
    }
  )
}

# IAM role for EC2 instances to access EFS
resource "aws_iam_role" "ec2_efs_role" {
  count = var.create_demo_instance ? 1 : 0
  
  name_prefix = "${local.name_prefix}-ec2-efs-"
  
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

# IAM policy for EFS access
resource "aws_iam_role_policy" "efs_access" {
  count = var.create_demo_instance ? 1 : 0
  
  name_prefix = "${local.name_prefix}-efs-access-"
  role        = aws_iam_role.ec2_efs_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.main.arn
      }
    ]
  })
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_efs_profile" {
  count = var.create_demo_instance ? 1 : 0
  
  name_prefix = "${local.name_prefix}-ec2-efs-"
  role        = aws_iam_role.ec2_efs_role[0].name
  
  tags = local.common_tags
}

# Security group for demo EC2 instance
resource "aws_security_group" "demo_instance" {
  count = var.create_demo_instance ? 1 : 0
  
  name_prefix = "${local.name_prefix}-demo-instance-"
  description = "Security group for demo EC2 instance"
  vpc_id      = data.aws_vpc.selected.id
  
  # Allow SSH access from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "SSH from ${ingress.value}"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-demo-instance-sg"
    }
  )
}

# User data script for EC2 instance
locals {
  user_data = var.create_demo_instance ? base64encode(templatefile("${path.module}/user-data.sh", {
    efs_id     = aws_efs_file_system.main.id
    aws_region = var.aws_region
    access_points = var.create_access_points ? [
      for k, v in aws_efs_access_point.access_points : {
        name = k
        id   = v.id
      }
    ] : []
  })) : null
}

# Demo EC2 instance
resource "aws_instance" "demo" {
  count = var.create_demo_instance ? 1 : 0
  
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = local.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.demo_instance[0].id, aws_security_group.efs_mount_targets.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_efs_profile[0].name
  key_name               = var.key_pair_name
  user_data              = local.user_data
  
  # Wait for EFS mount targets to be available
  depends_on = [aws_efs_mount_target.main]
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-demo-instance"
    }
  )
}

# Create user data script file
resource "local_file" "user_data_script" {
  content = templatefile("${path.module}/user-data.sh.tpl", {
    efs_id     = aws_efs_file_system.main.id
    aws_region = var.aws_region
    access_points = var.create_access_points ? [
      for k, v in aws_efs_access_point.access_points : {
        name = k
        id   = v.id
      }
    ] : []
  })
  filename = "${path.module}/user-data.sh"
}

# EFS file system policy for access points
resource "aws_efs_file_system_policy" "main" {
  count = var.create_access_points ? 1 : 0
  
  file_system_id = aws_efs_file_system.main.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.main.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
    ]
  })
}