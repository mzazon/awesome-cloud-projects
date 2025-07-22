# Automated Multi-Account Resource Discovery with Resource Explorer and Config
# This Terraform configuration deploys AWS Resource Explorer, Config, EventBridge,
# and Lambda to create an automated resource discovery and compliance monitoring system

terraform {
  required_version = ">= 1.5"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for consistent naming and configuration
locals {
  project_name             = "multi-account-discovery-${random_id.suffix.hex}"
  lambda_function_name     = "${local.project_name}-processor"
  config_aggregator_name   = "${local.project_name}-aggregator"
  config_bucket_name       = "aws-config-bucket-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}-${random_id.suffix.hex}"
  config_recorder_name     = "${local.project_name}-recorder"
  config_delivery_channel  = "${local.project_name}-channel"
  
  # Common tags applied to all resources
  common_tags = {
    Project             = local.project_name
    Purpose             = "MultiAccountDiscovery"
    ManagedBy          = "Terraform"
    Environment        = var.environment
    ComplianceScope    = "Organization"
    CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Data sources for account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_organizations_organization" "current" {}

# Data source for AWS Organizations accounts
data "aws_organizations_accounts" "current" {}

#============================================================================
# S3 BUCKET FOR AWS CONFIG
#============================================================================

# S3 bucket for AWS Config data storage
resource "aws_s3_bucket" "config" {
  bucket        = local.config_bucket_name
  force_destroy = var.force_destroy_bucket

  tags = merge(local.common_tags, {
    Name = "AWS Config Bucket"
    Type = "ConfigStorage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for AWS Config service access
resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

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
        Resource = aws_s3_bucket.config.arn
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
        Resource = aws_s3_bucket.config.arn
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
        Resource = "${aws_s3_bucket.config.arn}/*"
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

#============================================================================
# AWS RESOURCE EXPLORER CONFIGURATION
#============================================================================

# Resource Explorer aggregated index for multi-account search
resource "aws_resourceexplorer2_index" "main" {
  type = "AGGREGATOR"

  tags = merge(local.common_tags, {
    Name = "Organization Resource Explorer Index"
    Type = "ResourceDiscovery"
  })
}

# Resource Explorer view for organization-wide resource search
resource "aws_resourceexplorer2_view" "organization" {
  name         = "organization-view"
  default_view = true

  included_properties = [
    "lastReportedAt",
    "accountId",
    "region",
    "resourceType"
  ]

  depends_on = [aws_resourceexplorer2_index.main]

  tags = merge(local.common_tags, {
    Name = "Organization Resource View"
    Type = "ResourceDiscovery"
  })
}

#============================================================================
# AWS CONFIG CONFIGURATION
#============================================================================

# AWS Config service-linked role (automatically created if not exists)
data "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
}

# AWS Config configuration recorder
resource "aws_config_configuration_recorder" "main" {
  name     = local.config_recorder_name
  role_arn = data.aws_iam_service_linked_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
    # Record all resource types and changes
    recording_mode {
      recording_frequency                = "CONTINUOUS"
      recording_mode_override {
        description         = "Override for global resources"
        recording_frequency = "DAILY"
        resource_types      = ["AWS::IAM::Role", "AWS::IAM::Policy"]
      }
    }
  }

  depends_on = [aws_s3_bucket_policy.config]
}

# AWS Config delivery channel
resource "aws_config_delivery_channel" "main" {
  name           = local.config_delivery_channel
  s3_bucket_name = aws_s3_bucket.config.bucket

  # Deliver configuration snapshots daily
  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_s3_bucket_policy.config]
}

# Enable the AWS Config configuration recorder
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# AWS Config organizational aggregator
resource "aws_config_configuration_aggregator" "organization" {
  name = local.config_aggregator_name

  organization_aggregation_source {
    all_regions = var.all_regions
    regions     = var.all_regions ? null : var.target_regions
    role_arn    = data.aws_iam_service_linked_role.config.arn
  }

  tags = merge(local.common_tags, {
    Name = "Organization Config Aggregator"
    Type = "ComplianceMonitoring"
  })

  depends_on = [aws_config_configuration_recorder_status.main]
}

#============================================================================
# AWS CONFIG COMPLIANCE RULES
#============================================================================

# Config rule: S3 bucket public access prohibited
resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  name = "${local.project_name}-s3-bucket-public-access-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }

  tags = merge(local.common_tags, {
    Name         = "S3 Public Access Rule"
    ComplianceType = "Security"
    Severity     = "High"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Config rule: EC2 security group attached to ENI
resource "aws_config_config_rule" "ec2_security_group_attached_to_eni" {
  name = "${local.project_name}-ec2-security-group-attached-to-eni"

  source {
    owner             = "AWS"
    source_identifier = "EC2_SECURITY_GROUP_ATTACHED_TO_ENI"
  }

  tags = merge(local.common_tags, {
    Name         = "EC2 Security Group Rule"
    ComplianceType = "Security"
    Severity     = "Medium"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Config rule: Root access key check
resource "aws_config_config_rule" "root_access_key_check" {
  name = "${local.project_name}-root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCESS_KEY_CHECK"
  }

  tags = merge(local.common_tags, {
    Name         = "Root Access Key Rule"
    ComplianceType = "Security"
    Severity     = "Critical"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Config rule: EBS volumes encrypted
resource "aws_config_config_rule" "encrypted_volumes" {
  name = "${local.project_name}-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  tags = merge(local.common_tags, {
    Name         = "EBS Encryption Rule"
    ComplianceType = "Security"
    Severity     = "High"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

# Config rule: IAM password policy
resource "aws_config_config_rule" "iam_password_policy" {
  name = "${local.project_name}-iam-password-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols            = "true"
    RequireNumbers            = "true"
    MinimumPasswordLength     = "14"
    PasswordReusePrevention   = "24"
    MaxPasswordAge            = "90"
  })

  tags = merge(local.common_tags, {
    Name         = "IAM Password Policy Rule"
    ComplianceType = "Security"
    Severity     = "Medium"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

#============================================================================
# LAMBDA FUNCTION FOR AUTOMATED PROCESSING
#============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Lambda Processing Logs"
    Type = "Logging"
  })
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda" {
  name = "${local.project_name}-lambda-role"

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

  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role"
    Type = "IAMRole"
  })
}

# IAM policy for Lambda function enhanced permissions
resource "aws_iam_role_policy" "lambda" {
  name = "${local.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

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
          "config:GetComplianceDetailsByConfigRule",
          "config:GetAggregateComplianceDetailsByConfigRule",
          "config:GetComplianceSummaryByConfigRule",
          "config:GetAggregateComplianceSummary",
          "config:DescribeConfigRules",
          "config:DescribeComplianceByConfigRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "resource-explorer-2:Search",
          "resource-explorer-2:GetIndex",
          "resource-explorer-2:ListViews",
          "resource-explorer-2:GetView"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeAccount",
          "organizations:DescribeOrganization"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.notification_topic_arn != null ? var.notification_topic_arn : "*"
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create Lambda deployment package
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda_deployment.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      notification_topic_arn = var.notification_topic_arn
      organization_id       = data.aws_organizations_organization.current.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for automated resource discovery and compliance processing
resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda.output_path
  function_name    = local.lambda_function_name
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda.output_base64sha256

  description = "Multi-account resource discovery and compliance processor for ${local.project_name}"

  environment {
    variables = {
      PROJECT_NAME           = local.project_name
      CONFIG_AGGREGATOR_NAME = local.config_aggregator_name
      ORGANIZATION_ID        = data.aws_organizations_organization.current.id
      NOTIFICATION_TOPIC_ARN = var.notification_topic_arn
      LOG_LEVEL              = var.lambda_log_level
    }
  }

  # Advanced logging configuration
  logging_config {
    log_format            = "JSON"
    application_log_level = var.lambda_log_level
    system_log_level      = "WARN"
  }

  tags = merge(local.common_tags, {
    Name = "Resource Discovery Processor"
    Type = "Lambda"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda
  ]
}

#============================================================================
# EVENTBRIDGE RULES FOR AUTOMATION
#============================================================================

# EventBridge rule for AWS Config compliance change events
resource "aws_cloudwatch_event_rule" "config_compliance" {
  name        = "${local.project_name}-config-rule"
  description = "Route Config compliance violations to Lambda processor"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "Config Compliance Events"
    Type = "EventBridgeRule"
  })
}

# EventBridge rule for scheduled resource discovery
resource "aws_cloudwatch_event_rule" "discovery_schedule" {
  name                = "${local.project_name}-discovery-schedule"
  description         = "Scheduled resource discovery across accounts"
  schedule_expression = var.discovery_schedule
  state               = "ENABLED"

  tags = merge(local.common_tags, {
    Name = "Scheduled Discovery"
    Type = "EventBridgeRule"
  })
}

# EventBridge targets for Config compliance events
resource "aws_cloudwatch_event_target" "config_compliance" {
  rule      = aws_cloudwatch_event_rule.config_compliance.name
  target_id = "ConfigComplianceTarget"
  arn       = aws_lambda_function.processor.arn

  # Add retry policy for failed invocations
  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600
  }

  # Dead letter queue for failed invocations
  dead_letter_config {
    arn = var.dlq_arn != null ? var.dlq_arn : null
  }
}

# EventBridge targets for scheduled discovery
resource "aws_cloudwatch_event_target" "discovery_schedule" {
  rule      = aws_cloudwatch_event_rule.discovery_schedule.name
  target_id = "ScheduledDiscoveryTarget"
  arn       = aws_lambda_function.processor.arn

  # Add retry policy for failed invocations
  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 1800
  }
}

# Lambda permissions for EventBridge invocation
resource "aws_lambda_permission" "config_events" {
  statement_id  = "AllowExecutionFromConfigEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance.arn
}

resource "aws_lambda_permission" "discovery_schedule" {
  statement_id  = "AllowExecutionFromDiscoverySchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.discovery_schedule.arn
}

#============================================================================
# OPTIONAL: CLOUDWATCH DASHBOARD
#============================================================================

# CloudWatch Dashboard for monitoring resource discovery and compliance
resource "aws_cloudwatch_dashboard" "main" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "${local.project_name}-dashboard"

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
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = <<-EOT
            SOURCE '/aws/lambda/${local.lambda_function_name}'
            | fields @timestamp, @message
            | filter @message like /ERROR/ or @message like /WARNING/ or @message like /Non-compliant/
            | sort @timestamp desc
            | limit 20
          EOT
          region  = data.aws_region.current.name
          title   = "Recent Compliance Issues and Errors"
          view    = "table"
        }
      }
    ]
  })
}

#============================================================================
# TRUSTED ACCESS ENABLEMENT (Run this manually in Organizations management account)
#============================================================================

# Note: These resources require Organizations management account permissions
# and should be run separately or with proper cross-account roles

# Enable trusted access for Resource Explorer (requires Organizations management account)
# This must be run in the Organizations management account
# Uncomment these resources if running from the management account:
#
# resource "aws_organizations_trusted_service_access" "resource_explorer" {
#   service_principal = "resource-explorer-2.amazonaws.com"
# }
#
# resource "aws_organizations_trusted_service_access" "config" {
#   service_principal = "config.amazonaws.com"
# }