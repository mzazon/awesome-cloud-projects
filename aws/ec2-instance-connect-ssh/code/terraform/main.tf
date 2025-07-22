# Main Terraform Configuration for EC2 Instance Connect
# This file implements the complete infrastructure for secure SSH access using EC2 Instance Connect
# including IAM policies, EC2 instances, networking, and audit logging

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get the default VPC if not specified
data "aws_vpc" "selected" {
  id      = var.vpc_id != "" ? var.vpc_id : null
  default = var.vpc_id == "" ? true : null
}

# Data source to get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source to get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Data source to get default subnet for public instance
data "aws_subnets" "default" {
  count = var.public_subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )

  # Determine subnet to use for public instance
  public_subnet_id = var.public_subnet_id != "" ? var.public_subnet_id : (
    length(data.aws_subnets.default) > 0 ? data.aws_subnets.default[0].ids[0] : ""
  )

  # CloudTrail bucket name
  cloudtrail_bucket_name = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : "${local.name_prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

# Security Group for EC2 instances with Instance Connect access
resource "aws_security_group" "ec2_connect" {
  name_prefix = "${local.name_prefix}-sg"
  description = "Security group for EC2 Instance Connect access"
  vpc_id      = data.aws_vpc.selected.id

  # Allow SSH access from specified CIDR blocks
  ingress {
    description = "SSH access for EC2 Instance Connect"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
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
    Name = "${local.name_prefix}-security-group"
    Type = "SecurityGroup"
  })
}

# IAM Policy for EC2 Instance Connect - Basic permissions
resource "aws_iam_policy" "ec2_instance_connect" {
  name_prefix = "${local.name_prefix}-connect-policy"
  description = "IAM policy for EC2 Instance Connect access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:osuser" = "ec2-user"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeInstanceConnectEndpoints"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connect-policy"
    Type = "IAMPolicy"
  })
}

# IAM Policy for resource-specific Instance Connect access (restrictive)
resource "aws_iam_policy" "ec2_instance_connect_restrictive" {
  count = var.create_restrictive_policy ? 1 : 0

  name_prefix = "${local.name_prefix}-connect-restrictive-policy"
  description = "Resource-specific IAM policy for EC2 Instance Connect access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey"
        ]
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.public.id}"
        Condition = {
          StringEquals = {
            "ec2:osuser" = "ec2-user"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVpcs",
          "ec2:DescribeInstanceConnectEndpoints"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connect-restrictive-policy"
    Type = "IAMPolicy"
  })

  depends_on = [aws_instance.public]
}

# IAM User for testing Instance Connect (optional)
resource "aws_iam_user" "ec2_connect_user" {
  count = var.iam_user_name != "" ? 1 : 0

  name = var.iam_user_name
  path = "/"

  tags = merge(local.common_tags, {
    Name = var.iam_user_name
    Type = "IAMUser"
  })
}

# Attach basic policy to IAM user
resource "aws_iam_user_policy_attachment" "ec2_connect_basic" {
  count = var.iam_user_name != "" ? 1 : 0

  user       = aws_iam_user.ec2_connect_user[0].name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

# Create access key for IAM user (optional)
resource "aws_iam_access_key" "ec2_connect_user" {
  count = var.iam_user_name != "" ? 1 : 0

  user = aws_iam_user.ec2_connect_user[0].name
}

# Public EC2 Instance with Instance Connect support
resource "aws_instance" "public" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = local.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_connect.id]
  associate_public_ip_address = true
  monitoring                  = var.enable_detailed_monitoring

  # Instance metadata configuration for security
  metadata_options {
    http_endpoint               = var.instance_metadata_options.http_endpoint
    http_tokens                = var.instance_metadata_options.http_tokens
    http_put_response_hop_limit = var.instance_metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.instance_metadata_options.instance_metadata_tags
  }

  # User data to ensure Instance Connect is properly configured
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    
    # Ensure ec2-instance-connect is installed and configured
    yum install -y ec2-instance-connect
    
    # Start and enable the service
    systemctl start ec2-instance-connect
    systemctl enable ec2-instance-connect
    
    # Verify service status
    systemctl status ec2-instance-connect
    
    # Log successful initialization
    echo "EC2 Instance Connect initialized successfully at $(date)" >> /var/log/instance-connect-init.log
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-instance"
    Type = "PublicInstance"
  })

  # Ensure security group is created first
  depends_on = [aws_security_group.ec2_connect]
}

# Private subnet for private instance (only created if needed)
resource "aws_subnet" "private" {
  count = var.create_private_instance ? 1 : 0

  vpc_id            = data.aws_vpc.selected.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet"
    Type = "PrivateSubnet"
  })
}

# EC2 Instance Connect Endpoint for private instance access
resource "aws_ec2_instance_connect_endpoint" "private" {
  count = var.create_private_instance ? 1 : 0

  subnet_id          = aws_subnet.private[0].id
  security_group_ids = [aws_security_group.ec2_connect.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-connect-endpoint"
    Type = "InstanceConnectEndpoint"
  })

  depends_on = [aws_subnet.private]
}

# Private EC2 Instance (only created if requested)
resource "aws_instance" "private" {
  count = var.create_private_instance ? 1 : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ec2_connect.id]
  monitoring             = var.enable_detailed_monitoring

  # Instance metadata configuration for security
  metadata_options {
    http_endpoint               = var.instance_metadata_options.http_endpoint
    http_tokens                = var.instance_metadata_options.http_tokens
    http_put_response_hop_limit = var.instance_metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.instance_metadata_options.instance_metadata_tags
  }

  # User data to ensure Instance Connect is properly configured
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    
    # Ensure ec2-instance-connect is installed and configured
    yum install -y ec2-instance-connect
    
    # Start and enable the service
    systemctl start ec2-instance-connect
    systemctl enable ec2-instance-connect
    
    # Verify service status
    systemctl status ec2-instance-connect
    
    # Log successful initialization
    echo "EC2 Instance Connect initialized successfully at $(date)" >> /var/log/instance-connect-init.log
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-instance"
    Type = "PrivateInstance"
  })

  depends_on = [aws_subnet.private, aws_security_group.ec2_connect]
}

# S3 Bucket for CloudTrail logs (only created if CloudTrail is enabled)
resource "aws_s3_bucket" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket        = local.cloudtrail_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = local.cloudtrail_bucket_name
    Type = "CloudTrailBucket"
  })
}

# S3 Bucket versioning for CloudTrail bucket
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption for CloudTrail bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block for CloudTrail bucket
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.create_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

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
        Resource = aws_s3_bucket.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"
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
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# CloudTrail for audit logging (only created if enabled)
resource "aws_cloudtrail" "ec2_connect_audit" {
  count = var.create_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].bucket

  # Enable logging for all regions
  is_multi_region_trail         = true
  include_global_service_events = true

  # Enable log file validation
  enable_log_file_validation = true

  # Event selectors to capture EC2 Instance Connect events
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    # Data events for EC2 Instance Connect
    data_resource {
      type   = "AWS::EC2InstanceConnect::*"
      values = ["arn:aws:ec2-instance-connect:*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail"
    Type = "CloudTrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}