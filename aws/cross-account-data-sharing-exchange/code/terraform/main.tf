# AWS Data Exchange Cross-Account Data Sharing Infrastructure
# This Terraform configuration creates a complete AWS Data Exchange solution
# for secure cross-account data sharing with automated updates and monitoring

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ============================================================================
# S3 BUCKET RESOURCES
# ============================================================================

# S3 bucket for data provider (source data storage)
resource "aws_s3_bucket" "provider" {
  bucket = local.provider_bucket_name
  tags = merge(local.common_tags, {
    Name = "Data Exchange Provider Bucket"
    Role = "data-provider"
  })
}

# Enable versioning on provider bucket for data consistency
resource "aws_s3_bucket_versioning" "provider" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.provider.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Provider bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "provider" {
  bucket = aws_s3_bucket.provider.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access on provider bucket
resource "aws_s3_bucket_public_access_block" "provider" {
  bucket = aws_s3_bucket.provider.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for data subscriber (destination data storage)
resource "aws_s3_bucket" "subscriber" {
  bucket = local.subscriber_bucket_name
  tags = merge(local.common_tags, {
    Name = "Data Exchange Subscriber Bucket"
    Role = "data-subscriber"
  })
}

# Enable versioning on subscriber bucket
resource "aws_s3_bucket_versioning" "subscriber" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.subscriber.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Subscriber bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "subscriber" {
  bucket = aws_s3_bucket.subscriber.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access on subscriber bucket
resource "aws_s3_bucket_public_access_block" "subscriber" {
  bucket = aws_s3_bucket.subscriber.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample data files to provider bucket
resource "aws_s3_object" "sample_data" {
  for_each = var.sample_data_enabled ? local.sample_data : {}

  bucket  = aws_s3_bucket.provider.id
  key     = each.key
  content = each.value

  tags = merge(local.common_tags, {
    Name = "Sample Data - ${each.key}"
    Type = "sample-data"
  })
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for AWS Data Exchange service operations
resource "aws_iam_role" "data_exchange_provider" {
  name = "DataExchangeProviderRole-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dataexchange.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Data Exchange Provider Role"
    Role = "data-exchange-service"
  })
}

# Attach AWS managed policy for Data Exchange provider operations
resource "aws_iam_role_policy_attachment" "data_exchange_provider" {
  role       = aws_iam_role.data_exchange_provider.name
  policy_arn = "arn:aws:iam::aws:policy/AWSDataExchangeProviderFullAccess"
}

# Additional policy for S3 bucket access
resource "aws_iam_role_policy" "data_exchange_s3_access" {
  name = "DataExchangeS3Access-${local.random_suffix}"
  role = aws_iam_role.data_exchange_provider.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.provider.arn,
          "${aws_s3_bucket.provider.arn}/*",
          aws_s3_bucket.subscriber.arn,
          "${aws_s3_bucket.subscriber.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution" {
  name = "DataExchangeLambdaRole-${local.random_suffix}"

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
    Name = "Data Exchange Lambda Execution Role"
    Role = "lambda-execution"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda policy for Data Exchange and SNS operations
resource "aws_iam_role_policy" "lambda_data_exchange" {
  name = "LambdaDataExchangePolicy-${local.random_suffix}"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dataexchange:*",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
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

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

# SNS topic for Data Exchange notifications
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "data-exchange-notifications-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Name = "Data Exchange Notifications"
    Type = "notification"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# LAMBDA FUNCTIONS
# ============================================================================

# Archive for notification Lambda function
data "archive_file" "notification_lambda" {
  type        = "zip"
  output_path = "/tmp/notification-lambda-${local.random_suffix}.zip"

  source {
    content = templatefile("${path.module}/lambda/notification_handler.py", {
      sns_topic_arn = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : ""
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for Data Exchange event notifications
resource "aws_lambda_function" "notification_handler" {
  filename         = data.archive_file.notification_lambda.output_path
  function_name    = "DataExchangeNotificationHandler-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.notification_lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : ""
    }
  }

  tags = merge(local.common_tags, {
    Name = "Data Exchange Notification Handler"
    Type = "notification-lambda"
  })

  depends_on = [aws_cloudwatch_log_group.notification_lambda]
}

# Archive for auto-update Lambda function
data "archive_file" "update_lambda" {
  type        = "zip"
  output_path = "/tmp/update-lambda-${local.random_suffix}.zip"

  source {
    content  = file("${path.module}/lambda/auto_update.py")
    filename = "lambda_function.py"
  }
}

# Lambda function for automated data updates
resource "aws_lambda_function" "auto_update" {
  filename         = data.archive_file.update_lambda.output_path
  function_name    = "DataExchangeAutoUpdate-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.update_lambda.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "Data Exchange Auto Update"
    Type = "update-lambda"
  })

  depends_on = [aws_cloudwatch_log_group.update_lambda]
}

# ============================================================================
# AWS DATA EXCHANGE RESOURCES
# ============================================================================

# Data Exchange dataset
resource "aws_dataexchange_data_set" "main" {
  asset_type  = "S3_SNAPSHOT"
  description = "Enterprise customer analytics data for cross-account sharing"
  name        = local.dataset_name

  tags = merge(local.common_tags, {
    Name = "Enterprise Analytics Dataset"
    Type = "data-exchange-dataset"
  })
}

# Data Exchange revision
resource "aws_dataexchange_revision" "initial" {
  data_set_id = aws_dataexchange_data_set.main.id
  comment     = "Initial data revision with customer analytics - created by Terraform"

  tags = merge(local.common_tags, {
    Name = "Initial Revision"
    Type = "data-exchange-revision"
  })
}

# ============================================================================
# EVENTBRIDGE RULES AND TARGETS
# ============================================================================

# EventBridge rule for Data Exchange events
resource "aws_cloudwatch_event_rule" "data_exchange_events" {
  name        = "DataExchangeEventRule-${local.random_suffix}"
  description = "Captures Data Exchange events for notifications"

  event_pattern = jsonencode({
    source      = ["aws.dataexchange"]
    detail-type = ["Data Exchange Asset Import State Change"]
  })

  tags = merge(local.common_tags, {
    Name = "Data Exchange Event Rule"
    Type = "eventbridge-rule"
  })
}

# EventBridge target for Data Exchange events
resource "aws_cloudwatch_event_target" "data_exchange_events" {
  rule      = aws_cloudwatch_event_rule.data_exchange_events.name
  target_id = "DataExchangeNotificationTarget"
  arn       = aws_lambda_function.notification_handler.arn
}

# Permission for EventBridge to invoke notification Lambda
resource "aws_lambda_permission" "allow_eventbridge_notification" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_exchange_events.arn
}

# EventBridge rule for scheduled data updates
resource "aws_cloudwatch_event_rule" "scheduled_update" {
  name                = "DataExchangeAutoUpdateSchedule-${local.random_suffix}"
  description         = "Triggers automated data updates for Data Exchange"
  schedule_expression = var.schedule_expression

  tags = merge(local.common_tags, {
    Name = "Data Exchange Auto Update Schedule"
    Type = "eventbridge-schedule"
  })
}

# EventBridge target for scheduled updates
resource "aws_cloudwatch_event_target" "scheduled_update" {
  rule      = aws_cloudwatch_event_rule.scheduled_update.name
  target_id = "DataExchangeUpdateTarget"
  arn       = aws_lambda_function.auto_update.arn

  input = jsonencode({
    dataset_id   = aws_dataexchange_data_set.main.id
    bucket_name  = aws_s3_bucket.provider.id
  })
}

# Permission for EventBridge to invoke update Lambda
resource "aws_lambda_permission" "allow_eventbridge_update" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_update.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_update.arn
}

# ============================================================================
# CLOUDWATCH RESOURCES
# ============================================================================

# CloudWatch log group for Data Exchange operations
resource "aws_cloudwatch_log_group" "data_exchange_operations" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/dataexchange/operations-${local.random_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Data Exchange Operations Logs"
    Type = "cloudwatch-logs"
  })
}

# CloudWatch log group for notification Lambda
resource "aws_cloudwatch_log_group" "notification_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.notification_handler.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Notification Lambda Logs"
    Type = "lambda-logs"
  })
}

# CloudWatch log group for update Lambda
resource "aws_cloudwatch_log_group" "update_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.auto_update.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Update Lambda Logs"
    Type = "lambda-logs"
  })
}

# CloudWatch alarm for failed data grants
resource "aws_cloudwatch_metric_alarm" "failed_data_grants" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "DataExchangeFailedGrants-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedDataGrants"
  namespace           = "AWS/DataExchange"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors failed data grants in Data Exchange"

  tags = merge(local.common_tags, {
    Name = "Failed Data Grants Alarm"
    Type = "cloudwatch-alarm"
  })
}

# Metric filter for Lambda errors
resource "aws_cloudwatch_log_metric_filter" "lambda_errors" {
  count          = var.enable_monitoring ? 1 : 0
  name           = "DataExchangeLambdaErrors-${local.random_suffix}"
  log_group_name = aws_cloudwatch_log_group.update_lambda.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "DataExchangeLambdaErrors"
    namespace = "CustomMetrics"
    value     = "1"
  }
}

# ============================================================================
# DATA GRANT (commented out due to cross-account requirement)
# ============================================================================

# Note: Data Grant creation requires the subscriber account to exist and be accessible
# This is commented out as it requires cross-account setup which may not be available during deployment
# Uncomment and configure when ready to create actual data grants

# resource "aws_dataexchange_data_grant" "cross_account" {
#   name                   = "Analytics Data Grant for Account ${var.subscriber_account_id}"
#   description           = "Cross-account data sharing grant for analytics data - managed by Terraform"
#   dataset_id            = aws_dataexchange_data_set.main.id
#   recipient_account_id  = var.subscriber_account_id
#   ends_at              = var.data_grant_expires_at
#
#   tags = merge(local.common_tags, {
#     Name = "Cross-Account Data Grant"
#     Type = "data-exchange-grant"
#     SubscriberAccount = var.subscriber_account_id
#   })
#
#   depends_on = [aws_dataexchange_revision.initial]
# }

# ============================================================================
# SUBSCRIBER ACCESS SCRIPT GENERATION
# ============================================================================

# Create directory for generated files
resource "null_resource" "create_generated_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/generated"
  }
}

# Generate subscriber access script
resource "local_file" "subscriber_script" {
  depends_on = [null_resource.create_generated_dir]
  
  content = templatefile("${path.module}/scripts/subscriber_access.sh.tpl", {
    subscriber_bucket = aws_s3_bucket.subscriber.id
    aws_region       = var.aws_region
  })
  filename = "${path.module}/generated/subscriber-access-script.sh"

  provisioner "local-exec" {
    command = "chmod +x ${path.module}/generated/subscriber-access-script.sh"
  }
}