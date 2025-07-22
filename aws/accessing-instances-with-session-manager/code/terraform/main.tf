# Main Terraform configuration for Session Manager secure remote access

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_suffix = random_id.suffix.hex
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "SessionManagerDemo"
  }
}

# Get default VPC if none specified
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

# Get default subnet if none specified
data "aws_subnets" "default" {
  count = var.subnet_id == null ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
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

# KMS key for encryption
resource "aws_kms_key" "session_manager" {
  count = var.enable_logging ? 1 : 0

  description             = "KMS key for Session Manager logging encryption"
  deletion_window_in_days = var.kms_key_deletion_window
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
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "session-manager-kms-key-${local.resource_suffix}"
  })
}

# KMS key alias
resource "aws_kms_alias" "session_manager" {
  count = var.enable_logging ? 1 : 0

  name          = "alias/session-manager-${local.resource_suffix}"
  target_key_id = aws_kms_key.session_manager[0].key_id
}

# S3 bucket for session logs
resource "aws_s3_bucket" "session_logs" {
  count = var.enable_logging ? 1 : 0

  bucket        = "sessionmanager-logs-${local.resource_suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "session-manager-logs-${local.resource_suffix}"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "session_logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.session_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "session_logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.session_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.session_manager[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "session_logs" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.session_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch log group for session logs
resource "aws_cloudwatch_log_group" "session_logs" {
  count = var.enable_logging ? 1 : 0

  name              = "/aws/sessionmanager/sessions-${local.resource_suffix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.session_manager[0].arn

  tags = merge(local.common_tags, {
    Name = "session-manager-logs-${local.resource_suffix}"
  })
}

# IAM role for EC2 instances to use Session Manager
resource "aws_iam_role" "session_manager_instance_role" {
  name = "SessionManagerInstanceRole-${local.resource_suffix}"

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

  tags = merge(local.common_tags, {
    Name = "session-manager-instance-role-${local.resource_suffix}"
  })
}

# Attach AWS managed policy for Session Manager
resource "aws_iam_role_policy_attachment" "session_manager_instance_core" {
  role       = aws_iam_role.session_manager_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Additional policy for CloudWatch logging if enabled
resource "aws_iam_role_policy" "session_manager_logging" {
  count = var.enable_logging ? 1 : 0

  name = "SessionManagerLogging-${local.resource_suffix}"
  role = aws_iam_role.session_manager_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = aws_cloudwatch_log_group.session_logs[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = "${aws_s3_bucket.session_logs[0].arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.session_manager[0].arn
      }
    ]
  })
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "session_manager_instance_profile" {
  name = "SessionManagerInstanceProfile-${local.resource_suffix}"
  role = aws_iam_role.session_manager_instance_role.name

  tags = merge(local.common_tags, {
    Name = "session-manager-instance-profile-${local.resource_suffix}"
  })
}

# Security group for EC2 instances (no inbound rules needed for Session Manager)
resource "aws_security_group" "session_manager_instance" {
  name        = "session-manager-instance-${local.resource_suffix}"
  description = "Security group for Session Manager instances - no inbound rules needed"
  vpc_id      = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id

  # Allow all outbound traffic for updates and SSM communication
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "session-manager-instance-sg-${local.resource_suffix}"
  })
}

# EC2 instance for Session Manager demonstration
resource "aws_instance" "session_manager_demo" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  iam_instance_profile    = aws_iam_instance_profile.session_manager_instance_profile.name
  vpc_security_group_ids  = [aws_security_group.session_manager_instance.id]
  subnet_id               = var.subnet_id != null ? var.subnet_id : data.aws_subnets.default[0].ids[0]
  disable_api_termination = false

  # User data to ensure SSM Agent is running
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    
    # Install additional useful tools
    yum install -y htop nano tree
    
    # Create a welcome message
    echo "Session Manager Demo Instance" > /etc/motd
    echo "Access this instance securely using AWS Session Manager" >> /etc/motd
    echo "No SSH keys or open ports required!" >> /etc/motd
  EOF
  )

  tags = merge(local.common_tags, var.instance_tags, {
    Name = "SessionManagerDemo-${local.resource_suffix}"
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "session-manager-demo-root-${local.resource_suffix}"
    })
  }
}

# IAM policy for users to access Session Manager
resource "aws_iam_policy" "session_manager_user_policy" {
  name        = "SessionManagerUserPolicy-${local.resource_suffix}"
  description = "Policy for users to access Session Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Purpose" = "SessionManagerTesting"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceAssociationsStatus",
          "ssm:GetConnectionStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeDocumentParameters",
          "ssm:DescribeDocument",
          "ssm:GetDocument"
        ]
        Resource = "arn:aws:ssm:*:*:document/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = "arn:aws:ssm:*:*:session/$${aws:username}-*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "session-manager-user-policy-${local.resource_suffix}"
  })
}

# Session Manager logging preferences (if logging enabled)
resource "aws_ssm_document" "session_manager_prefs" {
  count = var.enable_logging ? 1 : 0

  name          = "SSM-SessionManagerRunShell-${local.resource_suffix}"
  document_type = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences with logging"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.session_logs[0].id
      s3KeyPrefix                 = var.s3_log_prefix
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.session_logs[0].name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = aws_kms_key.session_manager[0].key_id
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile = {
        linux = "cd $HOME; pwd"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "session-manager-prefs-${local.resource_suffix}"
  })
}

# CloudTrail for Session Manager API logging (optional)
resource "aws_cloudtrail" "session_manager" {
  count = var.enable_cloudtrail_logging ? 1 : 0

  name                          = "session-manager-trail-${local.resource_suffix}"
  s3_bucket_name               = var.enable_logging ? aws_s3_bucket.session_logs[0].id : null
  s3_key_prefix               = "cloudtrail-logs/"
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging              = true
  kms_key_id                  = var.enable_logging ? aws_kms_key.session_manager[0].arn : null

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/*"]
    }

    data_resource {
      type   = "AWS::SSM::Session"
      values = ["arn:aws:ssm:*:*:session/*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "session-manager-cloudtrail-${local.resource_suffix}"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logging]
}

# S3 bucket policy for CloudTrail logging
resource "aws_s3_bucket_policy" "cloudtrail_logging" {
  count = var.enable_cloudtrail_logging && var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.session_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.session_logs[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/session-manager-trail-${local.resource_suffix}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.session_logs[0].arn}/cloudtrail-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/session-manager-trail-${local.resource_suffix}"
          }
        }
      }
    ]
  })
}