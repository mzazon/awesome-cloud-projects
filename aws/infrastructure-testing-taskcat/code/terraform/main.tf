# Main Terraform configuration for TaskCat CloudFormation testing infrastructure
# This creates the complete testing environment for automated CloudFormation validation

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for available AWS availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# S3 bucket for TaskCat artifacts and test templates
resource "aws_s3_bucket" "taskcat_artifacts" {
  bucket        = "${var.project_name}-artifacts-${random_string.suffix.result}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(var.tags, {
    Name        = "${var.project_name}-artifacts-${random_string.suffix.result}"
    Purpose     = "TaskCat testing artifacts and templates"
    Component   = "Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "taskcat_artifacts" {
  bucket = aws_s3_bucket.taskcat_artifacts.id
  versioning_configuration {
    status = var.s3_bucket_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "taskcat_artifacts" {
  bucket = aws_s3_bucket.taskcat_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "taskcat_artifacts" {
  bucket = aws_s3_bucket.taskcat_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration to manage costs
resource "aws_s3_bucket_lifecycle_configuration" "taskcat_artifacts" {
  bucket = aws_s3_bucket.taskcat_artifacts.id

  rule {
    id     = "taskcat_artifacts_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete objects after 365 days
    expiration {
      days = 365
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM role for TaskCat execution
resource "aws_iam_role" "taskcat_execution_role" {
  name = "${var.project_name}-taskcat-execution-role-${random_string.suffix.result}"
  path = var.iam_role_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudformation.amazonaws.com",
            "ec2.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-execution-role"
    Purpose   = "TaskCat CloudFormation execution role"
    Component = "IAM"
  })
}

# IAM policy for TaskCat CloudFormation operations
resource "aws_iam_role_policy" "taskcat_cloudformation_policy" {
  name = "${var.project_name}-taskcat-cloudformation-policy"
  role = aws_iam_role.taskcat_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudformation:*",
          "iam:*",
          "ec2:*",
          "s3:*",
          "rds:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "lambda:*",
          "logs:*",
          "sns:*",
          "sqs:*",
          "dynamodb:*",
          "kms:*",
          "secretsmanager:*",
          "ssm:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "taskcat_s3_policy" {
  name = "${var.project_name}-taskcat-s3-policy"
  role = aws_iam_role.taskcat_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.taskcat_artifacts.arn,
          "${aws_s3_bucket.taskcat_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Create EC2 key pair for TaskCat testing (if not provided)
resource "aws_key_pair" "taskcat_key_pair" {
  count      = var.key_pair_name == "" ? 1 : 0
  key_name   = "${var.project_name}-taskcat-key-${random_string.suffix.result}"
  public_key = tls_private_key.taskcat_key[0].public_key_openssh

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-key"
    Purpose   = "TaskCat testing key pair"
    Component = "EC2"
  })
}

# Generate private key for TaskCat testing (if key pair not provided)
resource "tls_private_key" "taskcat_key" {
  count     = var.key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "taskcat_private_key" {
  count                   = var.key_pair_name == "" ? 1 : 0
  name                    = "${var.project_name}/taskcat/private-key-${random_string.suffix.result}"
  description             = "Private key for TaskCat testing EC2 instances"
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-private-key"
    Purpose   = "TaskCat testing private key storage"
    Component = "SecretsManager"
  })
}

resource "aws_secretsmanager_secret_version" "taskcat_private_key" {
  count     = var.key_pair_name == "" ? 1 : 0
  secret_id = aws_secretsmanager_secret.taskcat_private_key[0].id
  secret_string = tls_private_key.taskcat_key[0].private_key_pem
}

# CloudWatch Log Group for TaskCat execution logs
resource "aws_cloudwatch_log_group" "taskcat_logs" {
  name              = "/aws/taskcat/${var.project_name}"
  retention_in_days = var.cloudtrail_retention_days

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-logs"
    Purpose   = "TaskCat execution and testing logs"
    Component = "CloudWatch"
  })
}

# SNS Topic for TaskCat notifications (if email provided)
resource "aws_sns_topic" "taskcat_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-taskcat-notifications-${random_string.suffix.result}"

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-notifications"
    Purpose   = "TaskCat test result notifications"
    Component = "SNS"
  })
}

# SNS Topic subscription for email notifications
resource "aws_sns_topic_subscription" "taskcat_email_notifications" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.taskcat_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudTrail for TaskCat operations (optional)
resource "aws_cloudtrail" "taskcat_trail" {
  count                        = var.enable_cloudtrail_logging ? 1 : 0
  name                         = "${var.project_name}-taskcat-trail-${random_string.suffix.result}"
  s3_bucket_name              = aws_s3_bucket.taskcat_artifacts.bucket
  s3_key_prefix               = "cloudtrail-logs/"
  include_global_service_events = true
  is_multi_region_trail       = true
  enable_logging              = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.taskcat_artifacts.arn}/*"]
    }

    data_resource {
      type   = "AWS::CloudFormation::Stack"
      values = ["*"]
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-trail"
    Purpose   = "TaskCat operations audit trail"
    Component = "CloudTrail"
  })
}

# Lambda function for TaskCat test automation (optional)
data "archive_file" "taskcat_lambda" {
  type        = "zip"
  output_path = "/tmp/taskcat_automation.zip"
  
  source {
    content = templatefile("${path.module}/lambda/taskcat_automation.py", {
      s3_bucket_name = aws_s3_bucket.taskcat_artifacts.bucket
      sns_topic_arn  = var.notification_email != "" ? aws_sns_topic.taskcat_notifications[0].arn : ""
      log_group_name = aws_cloudwatch_log_group.taskcat_logs.name
    })
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "taskcat_lambda_role" {
  name = "${var.project_name}-taskcat-lambda-role-${random_string.suffix.result}"
  path = var.iam_role_path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-lambda-role"
    Purpose   = "TaskCat automation Lambda execution role"
    Component = "IAM"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "taskcat_lambda_policy" {
  name = "${var.project_name}-taskcat-lambda-policy"
  role = aws_iam_role.taskcat_lambda_role.id

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
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.taskcat_artifacts.arn,
          "${aws_s3_bucket.taskcat_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.notification_email != "" ? aws_sns_topic.taskcat_notifications[0].arn : "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:DescribeStacks",
          "cloudformation:ListStacks"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for TaskCat automation
resource "aws_lambda_function" "taskcat_automation" {
  filename         = data.archive_file.taskcat_lambda.output_path
  function_name    = "${var.project_name}-taskcat-automation-${random_string.suffix.result}"
  role            = aws_iam_role.taskcat_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.taskcat_lambda.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.test_timeout_minutes * 60

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.taskcat_artifacts.bucket
      SNS_TOPIC_ARN  = var.notification_email != "" ? aws_sns_topic.taskcat_notifications[0].arn : ""
      LOG_GROUP_NAME = aws_cloudwatch_log_group.taskcat_logs.name
      PROJECT_NAME   = var.project_name
    }
  }

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-automation"
    Purpose   = "TaskCat test automation and orchestration"
    Component = "Lambda"
  })
}

# CloudWatch Event Rule for scheduled TaskCat execution (optional)
resource "aws_cloudwatch_event_rule" "taskcat_schedule" {
  name                = "${var.project_name}-taskcat-schedule-${random_string.suffix.result}"
  description         = "Schedule for automated TaskCat testing"
  schedule_expression = "rate(1 day)"  # Daily execution
  state              = "DISABLED"      # Disabled by default

  tags = merge(var.tags, {
    Name      = "${var.project_name}-taskcat-schedule"
    Purpose   = "Scheduled TaskCat test execution"
    Component = "CloudWatch"
  })
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "taskcat_lambda_target" {
  rule      = aws_cloudwatch_event_rule.taskcat_schedule.name
  target_id = "TaskCatLambdaTarget"
  arn       = aws_lambda_function.taskcat_automation.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.taskcat_automation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.taskcat_schedule.arn
}

# Local file for TaskCat configuration template
resource "local_file" "taskcat_config_template" {
  filename = "${path.module}/taskcat_config_template.yml"
  
  content = templatefile("${path.module}/templates/taskcat_config.tpl", {
    project_name       = var.project_name
    aws_regions        = var.aws_regions
    s3_bucket_name     = aws_s3_bucket.taskcat_artifacts.bucket
    vpc_cidr_blocks    = var.vpc_cidr_blocks
    key_pair_name      = var.key_pair_name != "" ? var.key_pair_name : (length(aws_key_pair.taskcat_key_pair) > 0 ? aws_key_pair.taskcat_key_pair[0].key_name : "")
    execution_role_arn = aws_iam_role.taskcat_execution_role.arn
  })
}

# Upload TaskCat configuration to S3
resource "aws_s3_object" "taskcat_config" {
  bucket = aws_s3_bucket.taskcat_artifacts.bucket
  key    = "config/.taskcat.yml"
  source = local_file.taskcat_config_template.filename
  etag   = filemd5(local_file.taskcat_config_template.filename)

  tags = merge(var.tags, {
    Name      = "taskcat-configuration"
    Purpose   = "TaskCat testing configuration file"
    Component = "Configuration"
  })

  depends_on = [local_file.taskcat_config_template]
}