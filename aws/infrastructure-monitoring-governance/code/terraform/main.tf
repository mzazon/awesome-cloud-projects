# Infrastructure Monitoring with CloudTrail, Config, and Systems Manager
# This Terraform configuration creates a comprehensive monitoring solution
# using AWS CloudTrail, Config, and Systems Manager for infrastructure governance

# Data sources for account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "infrastructure-monitoring"
  
  common_tags = {
    Project     = "Infrastructure Monitoring"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "infrastructure-monitoring-cloudtrail-config-systems-manager"
  }
  
  # Resource names with unique suffix
  bucket_name              = "${local.name_prefix}-${random_string.suffix.result}"
  sns_topic_name          = "infrastructure-alerts-${random_string.suffix.result}"
  config_role_name        = "ConfigRole-${random_string.suffix.result}"
  cloudtrail_name         = "InfrastructureTrail-${random_string.suffix.result}"
  lambda_function_name    = "InfrastructureRemediation-${random_string.suffix.result}"
  maintenance_window_name = "InfrastructureMonitoring-${random_string.suffix.result}"
  dashboard_name          = "InfrastructureMonitoring-${random_string.suffix.result}"
}

# S3 bucket for storing CloudTrail logs and Config data
resource "aws_s3_bucket" "monitoring_bucket" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Description = "Storage for CloudTrail logs and Config data"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "monitoring_bucket_versioning" {
  bucket = aws_s3_bucket.monitoring_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "monitoring_bucket_encryption" {
  bucket = aws_s3_bucket.monitoring_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "monitoring_bucket_pab" {
  bucket = aws_s3_bucket.monitoring_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.monitoring_bucket.id

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
        Resource = aws_s3_bucket.monitoring_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
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
        Resource = "${aws_s3_bucket.monitoring_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      }
    ]
  })
}

# SNS topic for notifications
resource "aws_sns_topic" "infrastructure_alerts" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "Notifications for infrastructure monitoring events"
  })
}

# SNS topic policy for Config
resource "aws_sns_topic_policy" "infrastructure_alerts_policy" {
  arn = aws_sns_topic.infrastructure_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigSNSPolicy"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.infrastructure_alerts.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM role for AWS Config
resource "aws_iam_role" "config_role" {
  name = local.config_role_name

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
    Name        = local.config_role_name
    Description = "IAM role for AWS Config service"
  })
}

# Attach AWS managed policy for Config
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ConfigRole"
}

# Custom policy for Config S3 access
resource "aws_iam_role_policy" "config_s3_policy" {
  name = "ConfigS3Policy"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.monitoring_bucket.arn
      },
      {
        Effect = "Allow"
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.monitoring_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# AWS Config Configuration Recorder
resource "aws_config_configuration_recorder" "recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_config_delivery_channel.delivery_channel]
}

# AWS Config Delivery Channel
resource "aws_config_delivery_channel" "delivery_channel" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.monitoring_bucket.bucket
  sns_topic_arn  = aws_sns_topic.infrastructure_alerts.arn
}

# AWS Config Rules for compliance monitoring
resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  name = "s3-bucket-public-access-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(local.common_tags, {
    Name        = "s3-bucket-public-access-prohibited"
    Description = "Checks if S3 buckets allow public access"
  })
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name = "encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(local.common_tags, {
    Name        = "encrypted-volumes"
    Description = "Checks if EBS volumes are encrypted"
  })
}

resource "aws_config_config_rule" "root_access_key_check" {
  name = "root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(local.common_tags, {
    Name        = "root-access-key-check"
    Description = "Checks if root access keys exist"
  })
}

resource "aws_config_config_rule" "iam_password_policy" {
  name = "iam-password-policy"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(local.common_tags, {
    Name        = "iam-password-policy"
    Description = "Checks if IAM password policy meets requirements"
  })
}

# CloudTrail
resource "aws_cloudtrail" "infrastructure_trail" {
  name           = local.cloudtrail_name
  s3_bucket_name = aws_s3_bucket.monitoring_bucket.bucket

  include_global_service_events = true
  is_multi_region_trail        = true
  enable_log_file_validation   = true

  tags = merge(local.common_tags, {
    Name        = local.cloudtrail_name
    Description = "CloudTrail for infrastructure monitoring"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_bucket_policy]
}

# IAM role for Lambda remediation function
resource "aws_iam_role" "lambda_execution_role" {
  count = var.enable_automated_remediation ? 1 : 0
  name  = "lambda-execution-role-${random_string.suffix.result}"

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
    Name        = "lambda-execution-role-${random_string.suffix.result}"
    Description = "Execution role for remediation Lambda function"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_remediation_policy" {
  count = var.enable_automated_remediation ? 1 : 0
  name  = "LambdaRemediationPolicy"
  role  = aws_iam_role.lambda_execution_role[0].id

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
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "config:GetComplianceDetailsByConfigRule",
          "config:GetComplianceDetailsByResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutPublicAccessBlock",
          "s3:GetPublicAccessBlock"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach basic execution role policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count      = var.enable_automated_remediation ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role[0].name
}

# Lambda function for automated remediation
resource "aws_lambda_function" "remediation_function" {
  count         = var.enable_automated_remediation ? 1 : 0
  filename      = "remediation-lambda.zip"
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_execution_role[0].arn
  handler       = "remediation-lambda.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Automated remediation for compliance violations"
  })
}

# Archive file for Lambda function
data "archive_file" "lambda_zip" {
  count       = var.enable_automated_remediation ? 1 : 0
  type        = "zip"
  output_path = "remediation-lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/remediation-lambda.py", {
      # Template variables can be added here if needed
    })
    filename = "remediation-lambda.py"
  }
}

# Systems Manager Maintenance Window
resource "aws_ssm_maintenance_window" "infrastructure_monitoring" {
  name              = local.maintenance_window_name
  description       = "Automated infrastructure monitoring tasks"
  duration          = 4
  cutoff            = 1
  schedule          = "cron(0 02 ? * SUN *)"
  schedule_timezone = "UTC"

  allow_unassociated_targets = true

  tags = merge(local.common_tags, {
    Name        = local.maintenance_window_name
    Description = "Maintenance window for infrastructure monitoring"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "infrastructure_monitoring" {
  dashboard_name = local.dashboard_name

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
            ["AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "s3-bucket-public-access-prohibited"],
            [".", ".", ".", "encrypted-volumes"],
            [".", ".", ".", "root-access-key-check"],
            [".", ".", ".", "iam-password-policy"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Config Rule Compliance"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/events/rule/config-rule-compliance-change'\n| fields @timestamp, detail.newEvaluationResult.evaluationResultIdentifier.evaluationResultQualifier.resourceId, detail.newEvaluationResult.complianceType\n| filter detail.newEvaluationResult.complianceType = \"NON_COMPLIANT\"\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Recent Non-Compliant Resources"
          view   = "table"
        }
      }
    ]
  })

  depends_on = [
    aws_config_config_rule.s3_bucket_public_access_prohibited,
    aws_config_config_rule.encrypted_volumes,
    aws_config_config_rule.root_access_key_check,
    aws_config_config_rule.iam_password_policy
  ]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_automated_remediation ? 1 : 0
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Description = "Log group for remediation Lambda function"
  })
}

# EventBridge rule for Config compliance changes (if automated remediation is enabled)
resource "aws_cloudwatch_event_rule" "config_compliance_change" {
  count       = var.enable_automated_remediation ? 1 : 0
  name        = "config-compliance-change-${random_string.suffix.result}"
  description = "Capture Config compliance state changes"

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
    Name        = "config-compliance-change-${random_string.suffix.result}"
    Description = "EventBridge rule for Config compliance changes"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count     = var.enable_automated_remediation ? 1 : 0
  rule      = aws_cloudwatch_event_rule.config_compliance_change[0].name
  target_id = "RemediationLambdaTarget"
  arn       = aws_lambda_function.remediation_function[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_automated_remediation ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_function[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance_change[0].arn
}