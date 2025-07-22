# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC if not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

# Get default subnets if not provided
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get availability zones for the subnets
data "aws_subnet" "selected" {
  count = length(local.subnet_ids)
  id    = local.subnet_ids[count.index]
}

# Get latest Amazon Linux 2 AMI
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

# Local values for computed resources
locals {
  name_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  vpc_id      = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids  = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Limit to first 3 subnets for mount targets
  mount_target_subnets = slice(local.subnet_ids, 0, min(3, length(local.subnet_ids)))
  
  common_tags = merge(
    {
      Name        = local.name_prefix
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# Security group for EFS mount targets
resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs-sg"
  description = "Security group for EFS mount targets"
  vpc_id      = local.vpc_id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs-sg"
  })
}

# Security group for EC2 instances
resource "aws_security_group" "ec2" {
  count = var.create_ec2_instances ? 1 : 0
  
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for EFS client instances"
  vpc_id      = local.vpc_id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-sg"
  })
}

# EFS security group rules - allow NFS access from EC2 instances
resource "aws_security_group_rule" "efs_nfs_ingress" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = var.create_ec2_instances ? aws_security_group.ec2[0].id : aws_security_group.efs.id
}

# EFS security group rules - allow all outbound traffic
resource "aws_security_group_rule" "efs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.efs.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# EC2 security group rules - SSH access
resource "aws_security_group_rule" "ec2_ssh_ingress" {
  count = var.create_ec2_instances && var.enable_ssh_access ? 1 : 0
  
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2[0].id
  cidr_blocks       = var.ssh_cidr_blocks
}

# EC2 security group rules - HTTP access
resource "aws_security_group_rule" "ec2_http_ingress" {
  count = var.create_ec2_instances ? 1 : 0
  
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2[0].id
  cidr_blocks       = ["0.0.0.0/0"]
}

# EC2 security group rules - allow all outbound traffic
resource "aws_security_group_rule" "ec2_egress" {
  count = var.create_ec2_instances ? 1 : 0
  
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.ec2[0].id
  cidr_blocks       = ["0.0.0.0/0"]
}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token   = "${local.name_prefix}-token"
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode
  encrypted        = var.enable_encryption
  kms_key_id       = var.kms_key_id
  
  # Provisioned throughput (only used if throughput_mode is "provisioned")
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs"
  })
}

# EFS Mount Targets - create one per subnet/AZ
resource "aws_efs_mount_target" "main" {
  count = length(local.mount_target_subnets)
  
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = local.mount_target_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Points for application-specific access
resource "aws_efs_access_point" "main" {
  count = length(var.access_points)
  
  file_system_id = aws_efs_file_system.main.id
  
  root_directory {
    path = var.access_points[count.index].path
    
    creation_info {
      owner_uid   = var.access_points[count.index].owner_uid
      owner_gid   = var.access_points[count.index].owner_gid
      permissions = var.access_points[count.index].permissions
    }
  }
  
  posix_user {
    uid = var.access_points[count.index].posix_uid
    gid = var.access_points[count.index].posix_gid
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.access_points[count.index].name}"
  })
}

# EFS Lifecycle Policy
resource "aws_efs_lifecycle_policy" "main" {
  file_system_id = aws_efs_file_system.main.id
  
  policy = {
    transition_to_ia                    = var.transition_to_ia
    transition_to_primary_storage_class = var.transition_to_primary_storage_class
  }
}

# EFS File System Policy for access control
resource "aws_efs_file_system_policy" "main" {
  count = var.enable_file_system_policy ? 1 : 0
  
  file_system_id = aws_efs_file_system.main.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.main.arn
        Condition = var.enforce_secure_transport ? {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        } : {}
      }
    ]
  })
}

# IAM role for EC2 instances to access EFS
resource "aws_iam_role" "ec2_efs_role" {
  count = var.create_ec2_instances ? 1 : 0
  
  name = "${local.name_prefix}-ec2-efs-role"
  
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
resource "aws_iam_role_policy" "ec2_efs_policy" {
  count = var.create_ec2_instances ? 1 : 0
  
  name = "${local.name_prefix}-ec2-efs-policy"
  role = aws_iam_role.ec2_efs_role[0].id
  
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
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# IAM instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_efs_profile" {
  count = var.create_ec2_instances ? 1 : 0
  
  name = "${local.name_prefix}-ec2-efs-profile"
  role = aws_iam_role.ec2_efs_role[0].name
  
  tags = local.common_tags
}

# User data script for EC2 instances
locals {
  user_data = var.create_ec2_instances ? base64encode(templatefile("${path.module}/user_data.sh", {
    efs_id           = aws_efs_file_system.main.id
    access_point_ids = aws_efs_access_point.main[*].id
    access_point_names = [for ap in var.access_points : ap.name]
    log_group_name   = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.efs[0].name : ""
  })) : ""
}

# Create user data script file
resource "local_file" "user_data_script" {
  count = var.create_ec2_instances ? 1 : 0
  
  filename = "${path.module}/user_data.sh"
  content = templatefile("${path.module}/user_data.tpl", {
    efs_id           = aws_efs_file_system.main.id
    access_point_ids = aws_efs_access_point.main[*].id
    access_point_names = [for ap in var.access_points : ap.name]
    log_group_name   = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.efs[0].name : ""
  })
}

# EC2 instances for testing EFS
resource "aws_instance" "efs_client" {
  count = var.create_ec2_instances ? min(2, length(local.mount_target_subnets)) : 0
  
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  key_name                = var.key_pair_name
  subnet_id               = local.mount_target_subnets[count.index]
  vpc_security_group_ids  = [aws_security_group.ec2[0].id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_efs_profile[0].name
  user_data               = local.user_data
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-instance-${count.index + 1}"
  })
  
  depends_on = [
    aws_efs_mount_target.main,
    aws_efs_access_point.main
  ]
}

# CloudWatch Log Group for EFS
resource "aws_cloudwatch_log_group" "efs" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  name              = "/aws/efs/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = local.common_tags
}

# CloudWatch Log Group for EC2 instances
resource "aws_cloudwatch_log_group" "ec2" {
  count = var.enable_cloudwatch_monitoring && var.create_ec2_instances ? 1 : 0
  
  name              = "/aws/ec2/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = local.common_tags
}

# CloudWatch Dashboard for EFS monitoring
resource "aws_cloudwatch_dashboard" "efs" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  
  dashboard_name = "EFS-${local.name_prefix}"
  
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
            ["AWS/EFS", "TotalIOBytes", "FileSystemId", aws_efs_file_system.main.id],
            [".", "DataReadIOBytes", ".", "."],
            [".", "DataWriteIOBytes", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "EFS Data Transfer"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EFS", "ClientConnections", "FileSystemId", aws_efs_file_system.main.id],
            [".", "TotalIOTime", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "EFS Performance"
        }
      }
    ]
  })
}

# AWS Backup Vault
resource "aws_backup_vault" "efs" {
  count = var.enable_backup ? 1 : 0
  
  name        = "${local.name_prefix}-backup-vault"
  kms_key_arn = var.kms_key_id
  
  tags = local.common_tags
}

# AWS Backup Plan
resource "aws_backup_plan" "efs" {
  count = var.enable_backup ? 1 : 0
  
  name = "${local.name_prefix}-backup-plan"
  
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.efs[0].name
    schedule          = var.backup_schedule
    start_window      = var.backup_start_window_minutes
    
    lifecycle {
      delete_after = var.backup_retention_days
    }
    
    recovery_point_tags = merge(local.common_tags, {
      BackupPlan = "${local.name_prefix}-backup-plan"
    })
  }
  
  tags = local.common_tags
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup_role" {
  count = var.enable_backup ? 1 : 0
  
  name = "${local.name_prefix}-backup-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach AWS managed policy for EFS backup
resource "aws_iam_role_policy_attachment" "backup_policy" {
  count = var.enable_backup ? 1 : 0
  
  role       = aws_iam_role.backup_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# AWS Backup Selection
resource "aws_backup_selection" "efs" {
  count = var.enable_backup ? 1 : 0
  
  iam_role_arn = aws_iam_role.backup_role[0].arn
  name         = "${local.name_prefix}-backup-selection"
  plan_id      = aws_backup_plan.efs[0].id
  
  resources = [
    aws_efs_file_system.main.arn
  ]
  
  depends_on = [
    aws_iam_role_policy_attachment.backup_policy
  ]
}