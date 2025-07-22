# Data Governance Pipeline with Amazon DataZone and AWS Config
# This Terraform configuration creates an automated data governance system

# Get current AWS account and caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  random_suffix        = random_id.suffix.hex
  datazone_domain_name = var.datazone_domain_name != "" ? var.datazone_domain_name : "${var.project_name}-domain-${local.random_suffix}"
  datazone_project_name = var.datazone_project_name != "" ? var.datazone_project_name : "${var.project_name}-project-${local.random_suffix}"
  config_bucket_name   = "${var.config_bucket_prefix}-${data.aws_caller_identity.current.account_id}-${local.random_suffix}"
  lambda_function_name = "${var.project_name}-governance-processor-${local.random_suffix}"
  config_role_name     = "${var.project_name}-config-role-${local.random_suffix}"
  lambda_role_name     = "${var.project_name}-lambda-role-${local.random_suffix}"
  event_rule_name      = "${var.project_name}-governance-events-${local.random_suffix}"
  sns_topic_name       = "${var.project_name}-governance-alerts-${local.random_suffix}"
}

#---------------------------------------------------------------
# IAM Roles and Policies
#---------------------------------------------------------------

# IAM role for AWS Config service
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

  tags = merge(var.tags, {
    Name = local.config_role_name
    Type = "ConfigServiceRole"
  })
}

# Attach AWS managed policy for Config service
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# Additional policy for Config role to access S3 bucket
resource "aws_iam_role_policy" "config_s3_policy" {
  name = "${local.config_role_name}-s3-policy"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Create service-linked role for DataZone (if not exists)
resource "aws_iam_service_linked_role" "datazone" {
  aws_service_name = "datazone.amazonaws.com"
  description      = "Service-linked role for Amazon DataZone"

  lifecycle {
    ignore_changes = [aws_service_name]
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = local.lambda_role_name

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

  tags = merge(var.tags, {
    Name = local.lambda_role_name
    Type = "LambdaExecutionRole"
  })
}

# Attach basic execution policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda to access governance services
resource "aws_iam_role_policy" "lambda_governance_policy" {
  name = "${local.lambda_role_name}-governance-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "datazone:Get*",
          "datazone:List*",
          "datazone:Search*",
          "datazone:UpdateAsset",
          "config:GetComplianceDetailsByConfigRule",
          "config:GetResourceConfigHistory",
          "config:GetComplianceDetailsByResource",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

#---------------------------------------------------------------
# S3 Bucket for AWS Config
#---------------------------------------------------------------

# S3 bucket for AWS Config delivery channel
resource "aws_s3_bucket" "config_bucket" {
  bucket = local.config_bucket_name

  tags = merge(var.tags, {
    Name = local.config_bucket_name
    Type = "ConfigDeliveryChannel"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for Config service access
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

  depends_on = [aws_s3_bucket_public_access_block.config_bucket_pab]
}

#---------------------------------------------------------------
# AWS Config Configuration
#---------------------------------------------------------------

# AWS Config configuration recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_iam_role_policy_attachment.config_role_policy]
}

# AWS Config delivery channel
resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

# Start the configuration recorder
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# AWS Config rules for data governance
resource "aws_config_config_rule" "governance_rules" {
  for_each = { for rule in var.config_rules : rule.name => rule }

  name        = each.value.name
  description = each.value.description

  source {
    owner             = "AWS"
    source_identifier = each.value.source_identifier
  }

  scope {
    compliance_resource_types = each.value.resource_types
  }

  depends_on = [aws_config_configuration_recorder.main]

  tags = merge(var.tags, {
    Name = each.value.name
    Type = "ConfigRule"
  })
}

#---------------------------------------------------------------
# Amazon DataZone Domain and Project
#---------------------------------------------------------------

# Amazon DataZone domain
resource "aws_datazone_domain" "main" {
  name                   = local.datazone_domain_name
  description            = "Automated data governance domain for ${var.project_name}"
  domain_execution_role  = aws_iam_service_linked_role.datazone.arn
  kms_key_identifier     = "alias/aws/datazone"

  tags = merge(var.tags, {
    Name = local.datazone_domain_name
    Type = "DataZoneDomain"
  })

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Amazon DataZone project
resource "aws_datazone_project" "main" {
  domain_identifier = aws_datazone_domain.main.id
  name              = local.datazone_project_name
  description       = "Automated data governance and compliance project"

  tags = merge(var.tags, {
    Name = local.datazone_project_name
    Type = "DataZoneProject"
  })

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

#---------------------------------------------------------------
# Lambda Function for Governance Automation
#---------------------------------------------------------------

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/governance_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      account_id = data.aws_caller_identity.current.account_id
      region     = data.aws_region.current.name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for governance automation
resource "aws_lambda_function" "governance_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Data governance automation processor for ${var.project_name}"

  environment {
    variables = {
      LOG_LEVEL      = "INFO"
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
      AWS_REGION     = data.aws_region.current.name
      SNS_TOPIC_ARN  = aws_sns_topic.governance_alerts.arn
    }
  }

  tags = merge(var.tags, {
    Name = local.lambda_function_name
    Type = "GovernanceProcessor"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_governance_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Type = "LambdaLogGroup"
  })
}

#---------------------------------------------------------------
# EventBridge Rules for Automation
#---------------------------------------------------------------

# EventBridge rule for Config compliance changes
resource "aws_cloudwatch_event_rule" "governance_events" {
  name        = local.event_rule_name
  description = "Route data governance events to Lambda processor"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT", "COMPLIANT"]
      }
      configRuleName = [for rule in var.config_rules : rule.name]
    }
  })

  tags = merge(var.tags, {
    Name = local.event_rule_name
    Type = "EventBridgeRule"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.governance_events.name
  target_id = "GovernanceLambdaTarget"
  arn       = aws_lambda_function.governance_processor.arn

  retry_policy {
    maximum_retry_attempts = 3
    maximum_event_age      = 3600
  }
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.governance_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.governance_events.arn
}

#---------------------------------------------------------------
# SNS Topic for Notifications
#---------------------------------------------------------------

# SNS topic for governance alerts
resource "aws_sns_topic" "governance_alerts" {
  name = local.sns_topic_name

  tags = merge(var.tags, {
    Name = local.sns_topic_name
    Type = "GovernanceAlerts"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "governance_alerts_policy" {
  arn = aws_sns_topic.governance_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.governance_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS email subscription (if email is provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.sns_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.governance_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

#---------------------------------------------------------------
# CloudWatch Alarms for Monitoring
#---------------------------------------------------------------

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "DataGovernanceErrors-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold.lambda_errors
  alarm_description   = "Monitor Lambda function errors in governance pipeline"
  alarm_actions       = [aws_sns_topic.governance_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.governance_processor.function_name
  }

  tags = merge(var.tags, {
    Name = "DataGovernanceErrors-${local.random_suffix}"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "DataGovernanceDuration-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_threshold.lambda_duration
  alarm_description   = "Monitor Lambda function execution duration"
  alarm_actions       = [aws_sns_topic.governance_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.governance_processor.function_name
  }

  tags = merge(var.tags, {
    Name = "DataGovernanceDuration-${local.random_suffix}"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for Config compliance ratio
resource "aws_cloudwatch_metric_alarm" "compliance_ratio" {
  alarm_name          = "DataGovernanceCompliance-${local.random_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ComplianceByConfigRule"
  namespace           = "AWS/Config"
  period              = "600"
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_threshold.compliance_ratio
  alarm_description   = "Monitor overall compliance ratio"
  alarm_actions       = [aws_sns_topic.governance_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, {
    Name = "DataGovernanceCompliance-${local.random_suffix}"
    Type = "CloudWatchAlarm"
  })
}