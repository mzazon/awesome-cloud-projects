# AWS Storage Gateway Hybrid Cloud Storage Infrastructure

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for AWS account information and availability zones
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Data source for subnets in the VPC
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Local values for computed resources
locals {
  vpc_id              = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id           = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.available.ids[0]
  s3_bucket_name      = var.s3_bucket_name != "" ? var.s3_bucket_name : "storage-gateway-bucket-${random_id.suffix.hex}"
  gateway_name_unique = "${var.gateway_name}-${random_id.suffix.hex}"
  kms_key_alias       = "alias/storage-gateway-key-${random_id.suffix.hex}"
}

# Get the latest AWS Storage Gateway AMI
data "aws_ami" "storage_gateway" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["aws-storage-gateway-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# KMS Key for S3 bucket encryption
resource "aws_kms_key" "storage_gateway" {
  description             = "KMS key for Storage Gateway S3 bucket encryption"
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
        Sid    = "Allow Storage Gateway Service"
        Effect = "Allow"
        Principal = {
          Service = "storagegateway.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "storage-gateway-kms-key"
  }
}

# KMS Key Alias
resource "aws_kms_alias" "storage_gateway" {
  name          = local.kms_key_alias
  target_key_id = aws_kms_key.storage_gateway.key_id
}

# S3 Bucket for Storage Gateway
resource "aws_s3_bucket" "storage_gateway" {
  bucket = local.s3_bucket_name

  tags = {
    Name        = "Storage Gateway Bucket"
    Environment = var.environment
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "storage_gateway" {
  bucket = aws_s3_bucket.storage_gateway.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "storage_gateway" {
  bucket = aws_s3_bucket.storage_gateway.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.storage_gateway.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "storage_gateway" {
  bucket = aws_s3_bucket.storage_gateway.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for Storage Gateway
resource "aws_iam_role" "storage_gateway" {
  name = "StorageGatewayRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "storagegateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Storage Gateway Service Role"
  }
}

# Attach the AWS managed policy for Storage Gateway
resource "aws_iam_role_policy_attachment" "storage_gateway" {
  role       = aws_iam_role.storage_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/StorageGatewayServiceRole"
}

# Additional IAM policy for S3 access
resource "aws_iam_role_policy" "storage_gateway_s3" {
  name = "StorageGatewayS3Access-${random_id.suffix.hex}"
  role = aws_iam_role.storage_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.storage_gateway.arn,
          "${aws_s3_bucket.storage_gateway.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.storage_gateway.arn
      }
    ]
  })
}

# Security Group for Storage Gateway
resource "aws_security_group" "storage_gateway" {
  name        = "storage-gateway-sg-${random_id.suffix.hex}"
  description = "Security group for AWS Storage Gateway"
  vpc_id      = local.vpc_id

  # HTTP access for activation
  ingress {
    description = "HTTP for gateway activation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  # HTTPS access for management
  ingress {
    description = "HTTPS for gateway management"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  # NFS access
  ingress {
    description = "NFS access"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = var.nfs_client_cidrs
  }

  # SMB access
  ingress {
    description = "SMB access"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = var.nfs_client_cidrs
  }

  # iSCSI access (for Volume Gateway)
  ingress {
    description = "iSCSI access"
    from_port   = 3260
    to_port     = 3260
    protocol    = "tcp"
    cidr_blocks = var.nfs_client_cidrs
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "storage-gateway-security-group"
  }
}

# EC2 Instance for Storage Gateway
resource "aws_instance" "storage_gateway" {
  ami                     = data.aws_ami.storage_gateway.id
  instance_type           = var.gateway_instance_type
  subnet_id               = local.subnet_id
  vpc_security_group_ids  = [aws_security_group.storage_gateway.id]
  disable_api_termination = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 80
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = aws_kms_key.storage_gateway.arn
  }

  tags = {
    Name = local.gateway_name_unique
  }

  # Wait for the instance to be ready before proceeding
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Storage Gateway instance user data
    # The gateway will automatically start and be ready for activation
    EOF
  )
}

# Additional EBS volume for cache storage
resource "aws_ebs_volume" "cache" {
  availability_zone = aws_instance.storage_gateway.availability_zone
  size              = var.cache_disk_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.storage_gateway.arn

  tags = {
    Name = "storage-gateway-cache-${random_id.suffix.hex}"
  }
}

# Attach cache volume to Storage Gateway instance
resource "aws_volume_attachment" "cache" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cache.id
  instance_id = aws_instance.storage_gateway.id
}

# CloudWatch Log Group for Storage Gateway (if monitoring enabled)
resource "aws_cloudwatch_log_group" "storage_gateway" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/storagegateway/${local.gateway_name_unique}"
  retention_in_days = 14

  tags = {
    Name = "Storage Gateway Logs"
  }
}

# S3 Bucket Notification Configuration (optional)
resource "aws_s3_bucket_notification" "storage_gateway" {
  bucket = aws_s3_bucket.storage_gateway.id

  cloudwatch_configuration {
    cloudwatch_configuration {
      log_group_name = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.storage_gateway[0].name : null
    }
    events = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix = "storage-gateway/"
  }

  depends_on = [aws_cloudwatch_log_group.storage_gateway]
}

# Note: Storage Gateway activation and file share creation
# These resources require the gateway to be running and accessible
# They would typically be created via AWS CLI or custom provider after instance startup

# Output important values for manual configuration steps
output "gateway_activation_command" {
  description = "Command to get activation key for Storage Gateway"
  value = "curl -s 'http://${aws_instance.storage_gateway.public_ip}/?activationRegion=${data.aws_region.current.name}' | grep -o 'activationKey=[^&]*' | cut -d'=' -f2"
}

output "manual_steps" {
  description = "Manual steps required after Terraform deployment"
  value = <<-EOT
    After Terraform deployment completes:
    
    1. Wait 5-10 minutes for Storage Gateway to fully initialize
    2. Get activation key: ${local.gateway_activation_command}
    3. Activate gateway: aws storagegateway activate-gateway --activation-key <KEY> --gateway-name ${local.gateway_name_unique} --gateway-timezone ${var.gateway_timezone} --gateway-region ${data.aws_region.current.name} --gateway-type FILE_S3
    4. Configure cache storage: aws storagegateway add-cache --gateway-arn <GATEWAY_ARN> --disk-ids <DISK_ID>
    5. Create file shares using the provided outputs
  EOT
}

locals {
  gateway_activation_command = "curl -s 'http://${aws_instance.storage_gateway.public_ip}/?activationRegion=${data.aws_region.current.name}' | grep -o 'activationKey=[^&]*' | cut -d'=' -f2"
}