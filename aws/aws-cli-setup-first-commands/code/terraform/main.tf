# AWS CLI Setup and First Commands - Terraform Infrastructure
# This Terraform configuration creates the necessary infrastructure for learning AWS CLI
# including an S3 bucket with proper security configurations and IAM resources

# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
  required_version = ">= 1.5"
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Create S3 bucket for CLI tutorial with unique naming
resource "aws_s3_bucket" "cli_tutorial_bucket" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name        = "AWS CLI Tutorial Bucket"
    Purpose     = "AWS CLI Learning and Practice"
    Environment = var.environment
    Recipe      = "aws-cli-setup-first-commands"
    ManagedBy   = "Terraform"
  }
}

# Configure S3 bucket versioning for best practices
resource "aws_s3_bucket_versioning" "cli_tutorial_bucket_versioning" {
  bucket = aws_s3_bucket.cli_tutorial_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "cli_tutorial_bucket_encryption" {
  bucket = aws_s3_bucket.cli_tutorial_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket for security
resource "aws_s3_bucket_public_access_block" "cli_tutorial_bucket_pab" {
  bucket = aws_s3_bucket.cli_tutorial_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure S3 bucket lifecycle to manage costs and demonstrate best practices
resource "aws_s3_bucket_lifecycle_configuration" "cli_tutorial_bucket_lifecycle" {
  bucket = aws_s3_bucket.cli_tutorial_bucket.id

  rule {
    id     = "tutorial_cleanup"
    status = "Enabled"

    # Delete objects after 7 days to avoid costs for tutorial purposes
    expiration {
      days = 7
    }

    # Delete non-current versions after 1 day
    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    # Clean up incomplete multipart uploads after 1 day
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Create IAM policy for S3 access (for CLI tutorial users)
resource "aws_iam_policy" "cli_tutorial_s3_policy" {
  name        = "${var.iam_policy_prefix}-s3-access"
  description = "Policy for AWS CLI tutorial S3 access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning"
        ]
        Resource = aws_s3_bucket.cli_tutorial_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:GetObjectMetadata"
        ]
        Resource = "${aws_s3_bucket.cli_tutorial_bucket.arn}/*"
      }
    ]
  })

  tags = {
    Name      = "CLI Tutorial S3 Policy"
    Purpose   = "AWS CLI Learning and Practice"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Create IAM role for EC2 instances (if users want to practice from EC2)
resource "aws_iam_role" "cli_tutorial_ec2_role" {
  count = var.create_ec2_role ? 1 : 0
  name  = "${var.iam_role_prefix}-ec2-cli-tutorial"

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

  tags = {
    Name      = "CLI Tutorial EC2 Role"
    Purpose   = "AWS CLI Learning from EC2"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Attach S3 policy to EC2 role
resource "aws_iam_role_policy_attachment" "cli_tutorial_ec2_role_policy" {
  count      = var.create_ec2_role ? 1 : 0
  role       = aws_iam_role.cli_tutorial_ec2_role[0].name
  policy_arn = aws_iam_policy.cli_tutorial_s3_policy.arn
}

# Create instance profile for EC2 role
resource "aws_iam_instance_profile" "cli_tutorial_ec2_profile" {
  count = var.create_ec2_role ? 1 : 0
  name  = "${var.iam_role_prefix}-ec2-cli-tutorial-profile"
  role  = aws_iam_role.cli_tutorial_ec2_role[0].name

  tags = {
    Name      = "CLI Tutorial EC2 Instance Profile"
    Purpose   = "AWS CLI Learning from EC2"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Create sample objects in S3 bucket to demonstrate CLI operations
resource "aws_s3_object" "sample_file" {
  count  = var.create_sample_objects ? 1 : 0
  bucket = aws_s3_bucket.cli_tutorial_bucket.id
  key    = "sample-files/welcome.txt"
  content = templatefile("${path.module}/templates/welcome.txt.tpl", {
    bucket_name = aws_s3_bucket.cli_tutorial_bucket.id
    aws_region  = data.aws_region.current.name
    account_id  = data.aws_caller_identity.current.account_id
  })
  content_type = "text/plain"

  metadata = {
    purpose    = "aws-cli-tutorial"
    created-by = "terraform"
    recipe     = "aws-cli-setup-first-commands"
  }

  tags = {
    Name      = "CLI Tutorial Sample File"
    Purpose   = "AWS CLI Learning"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Create a directory structure with multiple sample files
resource "aws_s3_object" "sample_json_file" {
  count  = var.create_sample_objects ? 1 : 0
  bucket = aws_s3_bucket.cli_tutorial_bucket.id
  key    = "sample-files/config.json"
  content = jsonencode({
    tutorial = {
      name        = "AWS CLI Setup and First Commands"
      bucket_name = aws_s3_bucket.cli_tutorial_bucket.id
      region      = data.aws_region.current.name
      version     = "1.0"
    }
    commands = [
      "aws s3 ls",
      "aws s3 cp",
      "aws s3api head-bucket",
      "aws sts get-caller-identity"
    ]
  })
  content_type = "application/json"

  metadata = {
    purpose    = "aws-cli-tutorial"
    created-by = "terraform"
    file-type  = "configuration"
  }

  tags = {
    Name      = "CLI Tutorial JSON Config"
    Purpose   = "AWS CLI Learning"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Create a logs directory structure for practicing CLI commands
resource "aws_s3_object" "logs_directory" {
  count        = var.create_sample_objects ? 1 : 0
  bucket       = aws_s3_bucket.cli_tutorial_bucket.id
  key          = "logs/"
  content_type = "application/x-directory"

  tags = {
    Name      = "CLI Tutorial Logs Directory"
    Purpose   = "AWS CLI Learning"
    Recipe    = "aws-cli-setup-first-commands"
    ManagedBy = "Terraform"
  }
}

# Create CloudWatch Log Group for monitoring CLI activities (optional)
resource "aws_cloudwatch_log_group" "cli_tutorial_logs" {
  count             = var.enable_cloudwatch_logging ? 1 : 0
  name              = "/aws/cli-tutorial/${random_id.bucket_suffix.hex}"
  retention_in_days = 7

  tags = {
    Name        = "CLI Tutorial Logs"
    Purpose     = "AWS CLI Learning and Monitoring"
    Environment = var.environment
    Recipe      = "aws-cli-setup-first-commands"
    ManagedBy   = "Terraform"
  }
}

# Create template file for welcome message
resource "local_file" "welcome_template" {
  count    = var.create_sample_objects ? 1 : 0
  filename = "${path.module}/templates/welcome.txt.tpl"
  content  = <<-EOT
Welcome to the AWS CLI Tutorial!

This file was created by Terraform to help you practice AWS CLI commands.

Bucket Information:
- Bucket Name: ${"{bucket_name}"}
- AWS Region: ${"{aws_region}"}
- Account ID: ${"{account_id}"}

Practice Commands:
1. List bucket contents: aws s3 ls s3://${"{bucket_name}"}/
2. Copy this file: aws s3 cp s3://${"{bucket_name}"}/sample-files/welcome.txt ./
3. Get bucket location: aws s3api get-bucket-location --bucket ${"{bucket_name}"}
4. Check encryption: aws s3api get-bucket-encryption --bucket ${"{bucket_name}"}

Happy learning with AWS CLI!
Generated on: $(date)
EOT

  depends_on = [aws_s3_bucket.cli_tutorial_bucket]
}