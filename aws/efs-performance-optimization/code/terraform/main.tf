# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for VPC and subnet information
data "aws_vpc" "selected" {
  id      = var.vpc_id
  default = var.vpc_id == null
}

data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "availability-zone"
    values = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available.names
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Use provided subnet IDs or discover them from VPC
locals {
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : slice(data.aws_subnets.selected.ids, 0, min(2, length(data.aws_subnets.selected.ids)))
  
  common_tags = merge(
    {
      Name        = "${var.project_name}-${random_id.suffix.hex}"
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )
}

# Security Group for EFS Mount Targets
resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-efs-${random_id.suffix.hex}"
  description = "Security group for EFS mount targets"
  vpc_id      = data.aws_vpc.selected.id

  # Allow NFS traffic from within the security group
  ingress {
    description = "NFS traffic from self"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  # Allow NFS traffic from additional security groups
  dynamic "ingress" {
    for_each = var.additional_security_group_ids
    content {
      description     = "NFS traffic from additional security group"
      from_port       = 2049
      to_port         = 2049
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # Allow NFS traffic from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "NFS traffic from CIDR block"
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-efs-sg-${random_id.suffix.hex}"
  })
}

# KMS Key for EFS Encryption (if encryption is enabled)
resource "aws_kms_key" "efs" {
  count = var.efs_encrypted ? 1 : 0

  description             = "KMS key for EFS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EFS Service"
        Effect = "Allow"
        Principal = {
          Service = "elasticfilesystem.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-efs-kms-${random_id.suffix.hex}"
  })
}

resource "aws_kms_alias" "efs" {
  count = var.efs_encrypted ? 1 : 0

  name          = "alias/${var.project_name}-efs-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.efs[0].key_id
}

# Get current AWS caller identity for KMS policy
data "aws_caller_identity" "current" {}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-${random_id.suffix.hex}"

  # Performance configuration
  performance_mode = var.efs_performance_mode
  throughput_mode  = var.efs_throughput_mode

  # Provisioned throughput (only when throughput_mode is "provisioned")
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null

  # Encryption configuration
  encrypted  = var.efs_encrypted
  kms_key_id = var.efs_encrypted ? aws_kms_key.efs[0].arn : null

  # Lifecycle policy for cost optimization
  lifecycle_policy {
    transition_to_ia = var.efs_lifecycle_policy
  }

  # Enable backup if specified
  dynamic "lifecycle_policy" {
    for_each = var.efs_backup_enabled ? [1] : []
    content {
      transition_to_primary_storage_class = "AFTER_1_ACCESS"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-efs-${random_id.suffix.hex}"
  })
}

# EFS Mount Targets (one per subnet/AZ)
resource "aws_efs_mount_target" "main" {
  count = length(local.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = local.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Backup Policy (if backup is enabled)
resource "aws_efs_backup_policy" "main" {
  count = var.efs_backup_enabled ? 1 : 0

  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = "ENABLED"
  }
}

# CloudWatch Dashboard for EFS Monitoring
resource "aws_cloudwatch_dashboard" "efs" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0

  dashboard_name = "EFS-Performance-${var.project_name}-${random_id.suffix.hex}"

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
            [".", "ReadIOBytes", ".", "."],
            [".", "WriteIOBytes", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "EFS IO Throughput"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/EFS", "TotalIOTime", "FileSystemId", aws_efs_file_system.main.id],
            [".", "ReadIOTime", ".", "."],
            [".", "WriteIOTime", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EFS IO Latency (ms)"
          yAxis = {
            left = {
              min = 0
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
            ["AWS/EFS", "ClientConnections", "FileSystemId", aws_efs_file_system.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "EFS Client Connections"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EFS", "PercentIOLimit", "FileSystemId", aws_efs_file_system.main.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EFS IO Limit Utilization (%)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}

# CloudWatch Alarms for EFS Performance Monitoring
resource "aws_cloudwatch_metric_alarm" "efs_high_throughput_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "EFS-High-Throughput-Utilization-${var.project_name}-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_throughput_threshold
  alarm_description   = "This metric monitors EFS throughput utilization"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "efs_high_client_connections" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "EFS-High-Client-Connections-${var.project_name}-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ClientConnections"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_connections_threshold
  alarm_description   = "This metric monitors EFS client connections"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "efs_high_io_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "EFS-High-IO-Latency-${var.project_name}-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "TotalIOTime"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_latency_threshold
  alarm_description   = "This metric monitors EFS average IO latency"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FileSystemId = aws_efs_file_system.main.id
  }

  tags = local.common_tags
}

# Optional: EC2 Test Instance for EFS validation
data "aws_ami" "amazon_linux" {
  count = var.create_test_instance ? 1 : 0

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

# IAM role for EC2 instance (if test instance is created)
resource "aws_iam_role" "ec2_efs_role" {
  count = var.create_test_instance ? 1 : 0

  name_prefix = "${var.project_name}-ec2-efs-role-${random_id.suffix.hex}"

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

resource "aws_iam_role_policy_attachment" "ec2_efs_policy" {
  count = var.create_test_instance ? 1 : 0

  role       = aws_iam_role.ec2_efs_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientWrite"
}

resource "aws_iam_instance_profile" "ec2_efs_profile" {
  count = var.create_test_instance ? 1 : 0

  name_prefix = "${var.project_name}-ec2-efs-profile-${random_id.suffix.hex}"
  role        = aws_iam_role.ec2_efs_role[0].name

  tags = local.common_tags
}

# User data script for EC2 instance
locals {
  user_data = var.create_test_instance ? base64encode(templatefile("${path.module}/user_data.sh", {
    efs_id     = aws_efs_file_system.main.id
    aws_region = var.aws_region
  })) : null
}

# EC2 Test Instance
resource "aws_instance" "efs_test" {
  count = var.create_test_instance ? 1 : 0

  ami           = data.aws_ami.amazon_linux[0].id
  instance_type = var.test_instance_type
  key_name      = var.test_instance_key_name
  subnet_id     = local.subnet_ids[0]

  vpc_security_group_ids = [aws_security_group.efs.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_efs_profile[0].name

  user_data = local.user_data

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-efs-test-instance-${random_id.suffix.hex}"
  })

  depends_on = [aws_efs_mount_target.main]
}

# Create user data script file if test instance is enabled
resource "local_file" "user_data_script" {
  count = var.create_test_instance ? 1 : 0

  filename = "${path.module}/user_data.sh"
  content = templatefile("${path.module}/user_data.tpl", {
    efs_id     = aws_efs_file_system.main.id
    aws_region = var.aws_region
  })
}

# Template file for user data
resource "local_file" "user_data_template" {
  count = var.create_test_instance ? 1 : 0

  filename = "${path.module}/user_data.tpl"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y amazon-efs-utils

# Create mount point
mkdir -p /mnt/efs

# Mount EFS file system
echo "${efs_id}.efs.${aws_region}.amazonaws.com:/ /mnt/efs efs defaults,_netdev" >> /etc/fstab
mount -a

# Set permissions
chmod 755 /mnt/efs

# Create test file
echo "EFS mount successful at $(date)" > /mnt/efs/test-file.txt

# Install performance testing tools
yum install -y fio

# Log completion
echo "EFS setup completed successfully" >> /var/log/efs-setup.log
EOF
}