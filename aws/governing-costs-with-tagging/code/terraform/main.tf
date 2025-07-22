# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming
  name_suffix = random_id.suffix.hex
  common_name = "${var.resource_prefix}-${local.name_suffix}"
  
  # Standard tags applied to all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostCenter  = var.default_cost_center
    Owner       = var.owner_email
    Purpose     = "TaggingStrategy"
  }
  
  # Tag taxonomy for validation
  tag_taxonomy = {
    required_tags = {
      CostCenter = {
        description = "Department or cost center for chargeback"
        values      = var.allowed_cost_centers
      }
      Environment = {
        description = "Deployment environment"
        values      = var.allowed_environments
      }
      Project = {
        description = "Project or application name"
        values      = ["*"]
      }
      Owner = {
        description = "Resource owner email"
        values      = ["*"]
      }
    }
    optional_tags = {
      Application = {
        description = "Application component"
        values      = var.allowed_applications
      }
      Backup = {
        description = "Backup requirement"
        values      = ["true", "false"]
      }
    }
  }
}

# ============================================================================
# SNS Topic for Tag Compliance Notifications
# ============================================================================

resource "aws_sns_topic" "tag_compliance" {
  name         = "${local.common_name}-compliance"
  display_name = "Tag Compliance Notifications"
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-compliance-topic"
    Description = "SNS topic for tag compliance notifications"
  })
}

resource "aws_sns_topic_subscription" "tag_compliance_email" {
  topic_arn = aws_sns_topic.tag_compliance.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS topic policy to allow Config and Lambda to publish
resource "aws_sns_topic_policy" "tag_compliance_policy" {
  arn = aws_sns_topic.tag_compliance.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConfigToPublish"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.tag_compliance.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowLambdaToPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.tag_compliance.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# S3 Bucket for AWS Config
# ============================================================================

resource "aws_s3_bucket" "config_bucket" {
  bucket        = "aws-config-${local.common_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name        = "aws-config-${local.common_name}"
    Description = "S3 bucket for AWS Config configuration snapshots and compliance reports"
  })
}

resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ============================================================================
# IAM Role for AWS Config
# ============================================================================

resource "aws_iam_role" "config_role" {
  name = "${local.common_name}-config-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-config-role"
    Description = "IAM role for AWS Config service"
  })
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# ============================================================================
# AWS Config Configuration Recorder and Delivery Channel
# ============================================================================

resource "aws_config_delivery_channel" "main" {
  name           = "${local.common_name}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.id
  
  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }
  
  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.common_name}-recorder"
  role_arn = aws_iam_role.config_role.arn
  
  recording_group {
    all_supported                 = true
    include_global_resource_types = var.include_global_resource_types
  }
  
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_config_recorder ? 1 : 0
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_configuration_recorder.main]
}

# ============================================================================
# AWS Config Rules for Tag Compliance
# ============================================================================

# Config rule for CostCenter tag
resource "aws_config_config_rule" "required_tag_costcenter" {
  name = "${local.common_name}-required-tag-costcenter"
  
  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }
  
  input_parameters = jsonencode({
    tag1Key   = "CostCenter"
    tag1Value = join(",", var.allowed_cost_centers)
  })
  
  depends_on = [aws_config_configuration_recorder.main]
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-costcenter-rule"
    Description = "Config rule to check for required CostCenter tag"
  })
}

# Config rule for Environment tag
resource "aws_config_config_rule" "required_tag_environment" {
  name = "${local.common_name}-required-tag-environment"
  
  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }
  
  input_parameters = jsonencode({
    tag1Key   = "Environment"
    tag1Value = join(",", var.allowed_environments)
  })
  
  depends_on = [aws_config_configuration_recorder.main]
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-environment-rule"
    Description = "Config rule to check for required Environment tag"
  })
}

# Config rule for Project tag
resource "aws_config_config_rule" "required_tag_project" {
  name = "${local.common_name}-required-tag-project"
  
  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }
  
  input_parameters = jsonencode({
    tag1Key = "Project"
  })
  
  depends_on = [aws_config_configuration_recorder.main]
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-project-rule"
    Description = "Config rule to check for required Project tag"
  })
}

# Config rule for Owner tag
resource "aws_config_config_rule" "required_tag_owner" {
  name = "${local.common_name}-required-tag-owner"
  
  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }
  
  input_parameters = jsonencode({
    tag1Key = "Owner"
  })
  
  depends_on = [aws_config_configuration_recorder.main]
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-owner-rule"
    Description = "Config rule to check for required Owner tag"
  })
}

# ============================================================================
# Lambda Function for Tag Remediation
# ============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.common_name}-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-lambda-role"
    Description = "IAM role for tag remediation Lambda function"
  })
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.common_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeTags",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.tag_compliance.arn
      }
    ]
  })
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/tag-remediation-lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      sns_topic_arn = aws_sns_topic.tag_compliance.arn
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "tag_remediation" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.common_name}-tag-remediation"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.tag_compliance.arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-tag-remediation"
    Description = "Lambda function for automated tag remediation"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.common_name}-tag-remediation"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-lambda-logs"
    Description = "CloudWatch logs for tag remediation Lambda"
  })
}

# ============================================================================
# Resource Groups for Tag-based Organization
# ============================================================================

# Resource group for Production environment
resource "aws_resourcegroups_group" "production_environment" {
  name = "${local.common_name}-production-env"
  
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Environment"
          Values = ["Production"]
        }
      ]
    })
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-production-group"
    Description = "Resource group for Production environment resources"
    Purpose     = "CostAllocation"
  })
}

# Resource group for Engineering cost center
resource "aws_resourcegroups_group" "engineering_costcenter" {
  name = "${local.common_name}-engineering-cc"
  
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "CostCenter"
          Values = ["Engineering"]
        }
      ]
    })
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-engineering-group"
    Description = "Resource group for Engineering cost center resources"
    Purpose     = "CostAllocation"
  })
}

# ============================================================================
# Demo Resources (Optional)
# ============================================================================

# Get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  count       = var.create_demo_resources ? 1 : 0
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

# Demo EC2 instance with comprehensive tags
resource "aws_instance" "demo_instance" {
  count         = var.create_demo_resources ? 1 : 0
  ami           = data.aws_ami.amazon_linux[0].id
  instance_type = var.demo_instance_type
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-demo-instance"
    Description = "Demo EC2 instance for testing tagging strategy"
    Application = "web"
    Backup      = "false"
  })
  
  # Ensure instance is created after Config is running
  depends_on = [aws_config_configuration_recorder_status.main]
}

# Demo S3 bucket with comprehensive tags
resource "aws_s3_bucket" "demo_bucket" {
  count         = var.create_demo_resources ? 1 : 0
  bucket        = "${local.common_name}-demo-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-demo-bucket"
    Description = "Demo S3 bucket for testing tagging strategy"
    Application = "web"
    Backup      = "true"
  })
}

# ============================================================================
# Tag Taxonomy Documentation (Local File)
# ============================================================================

# Create tag taxonomy JSON file for reference
resource "local_file" "tag_taxonomy" {
  filename = "${path.module}/tag-taxonomy.json"
  content = jsonencode({
    tag_taxonomy = local.tag_taxonomy
    cost_allocation_tags = var.cost_allocation_tags
    usage_instructions = {
      description = "This file documents the tag taxonomy for cost management"
      required_tags = "All resources must have CostCenter, Environment, Project, and Owner tags"
      validation = "AWS Config rules validate tag compliance automatically"
      remediation = "Lambda function applies default tags to non-compliant resources"
    }
  })
}