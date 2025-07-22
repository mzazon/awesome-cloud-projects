# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# S3 BUCKET FOR LAMBDA DEPLOYMENT PACKAGES
# ==============================================================================

# S3 bucket for storing Lambda deployment packages
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "${local.name_prefix}-lambda-artifacts-${local.suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-artifacts-${local.suffix}"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================================================
# SNS TOPIC FOR MEDIA ALERTS
# ==============================================================================

# SNS topic for media workflow alerts
resource "aws_sns_topic" "media_alerts" {
  name = "${local.name_prefix}-media-alerts-${local.suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-media-alerts-${local.suffix}"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "media_alerts" {
  arn = aws_sns_topic.media_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.media_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS email subscription
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.media_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.suffix}"

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
    Name = "${local.name_prefix}-lambda-role-${local.suffix}"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for MediaConnect and CloudWatch access
resource "aws_iam_role_policy" "lambda_media_policy" {
  name = "MediaConnectAccess"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediaconnect:DescribeFlow",
          "mediaconnect:ListFlows",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${local.name_prefix}-stepfunctions-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stepfunctions-role-${local.suffix}"
  })
}

# Policy for Step Functions to invoke Lambda functions
resource "aws_iam_role_policy" "step_functions_execution_policy" {
  name = "StepFunctionsExecutionPolicy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  name = "${local.name_prefix}-eventbridge-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eventbridge-role-${local.suffix}"
  })
}

# Policy for EventBridge to invoke Step Functions
resource "aws_iam_role_policy" "eventbridge_stepfunctions_policy" {
  name = "InvokeStepFunctions"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "states:StartExecution"
        Resource = aws_sfn_state_machine.media_workflow.arn
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTIONS
# ==============================================================================

# Create Lambda deployment package for stream monitor
data "archive_file" "stream_monitor_zip" {
  type        = "zip"
  output_path = "/tmp/stream-monitor.zip"
  
  source {
    content = templatefile("${path.module}/lambda/stream-monitor.py", {
      sns_topic_arn = aws_sns_topic.media_alerts.arn
    })
    filename = "stream-monitor.py"
  }
}

# Upload stream monitor Lambda package to S3
resource "aws_s3_object" "stream_monitor_zip" {
  bucket = aws_s3_bucket.lambda_artifacts.bucket
  key    = "stream-monitor.zip"
  source = data.archive_file.stream_monitor_zip.output_path
  etag   = data.archive_file.stream_monitor_zip.output_md5
}

# Stream monitor Lambda function
resource "aws_lambda_function" "stream_monitor" {
  function_name = "${local.name_prefix}-stream-monitor-${local.suffix}"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = aws_s3_object.stream_monitor_zip.key
  handler       = "stream-monitor.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_execution_role.arn
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.media_alerts.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.stream_monitor_logs,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stream-monitor-${local.suffix}"
  })
}

# Create Lambda deployment package for alert handler
data "archive_file" "alert_handler_zip" {
  type        = "zip"
  output_path = "/tmp/alert-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/alert-handler.py", {
      sns_topic_arn = aws_sns_topic.media_alerts.arn
    })
    filename = "alert-handler.py"
  }
}

# Upload alert handler Lambda package to S3
resource "aws_s3_object" "alert_handler_zip" {
  bucket = aws_s3_bucket.lambda_artifacts.bucket
  key    = "alert-handler.zip"
  source = data.archive_file.alert_handler_zip.output_path
  etag   = data.archive_file.alert_handler_zip.output_md5
}

# Alert handler Lambda function
resource "aws_lambda_function" "alert_handler" {
  function_name = "${local.name_prefix}-alert-handler-${local.suffix}"
  s3_bucket     = aws_s3_bucket.lambda_artifacts.bucket
  s3_key        = aws_s3_object.alert_handler_zip.key
  handler       = "alert-handler.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_execution_role.arn
  timeout       = 30
  memory_size   = 128

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.media_alerts.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.alert_handler_logs,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alert-handler-${local.suffix}"
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "stream_monitor_logs" {
  name              = "/aws/lambda/${local.name_prefix}-stream-monitor-${local.suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stream-monitor-logs"
  })
}

resource "aws_cloudwatch_log_group" "alert_handler_logs" {
  name              = "/aws/lambda/${local.name_prefix}-alert-handler-${local.suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alert-handler-logs"
  })
}

# ==============================================================================
# STEP FUNCTIONS STATE MACHINE
# ==============================================================================

# Step Functions state machine for media workflow
resource "aws_sfn_state_machine" "media_workflow" {
  name     = "${local.name_prefix}-workflow-${local.suffix}"
  role_arn = aws_iam_role.step_functions_role.arn
  type     = var.step_functions_type

  definition = templatefile("${path.module}/stepfunctions/state-machine.json", {
    monitor_lambda_arn = aws_lambda_function.stream_monitor.arn
    alert_lambda_arn   = aws_lambda_function.alert_handler.arn
    sns_topic_arn      = aws_sns_topic.media_alerts.arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workflow-${local.suffix}"
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/stepfunctions/${local.name_prefix}-workflow-${local.suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stepfunctions-logs"
  })
}

# ==============================================================================
# MEDIACONNECT FLOW
# ==============================================================================

# MediaConnect flow for live video streaming
resource "aws_mediaconnect_flow" "live_stream" {
  name               = "${local.name_prefix}-flow-${local.suffix}"
  availability_zone  = "${data.aws_region.current.name}a"

  source {
    name             = "PrimarySource"
    description      = "Primary live stream source"
    protocol         = "rtp"
    whitelist_cidr   = var.source_whitelist_cidr
    ingest_port      = var.ingest_port
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-flow-${local.suffix}"
  })
}

# Primary output for MediaConnect flow
resource "aws_mediaconnect_flow_output" "primary_output" {
  flow_arn    = aws_mediaconnect_flow.live_stream.arn
  name        = "PrimaryOutput"
  description = "Primary stream output"
  protocol    = "rtp"
  destination = var.primary_output_destination
  port        = var.primary_output_port
}

# Backup output for MediaConnect flow
resource "aws_mediaconnect_flow_output" "backup_output" {
  flow_arn    = aws_mediaconnect_flow.live_stream.arn
  name        = "BackupOutput"
  description = "Backup stream output"
  protocol    = "rtp"
  destination = var.backup_output_destination
  port        = var.backup_output_port
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# CloudWatch alarm for packet loss
resource "aws_cloudwatch_metric_alarm" "packet_loss_alarm" {
  alarm_name          = "${local.name_prefix}-packet-loss-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SourcePacketLossPercent"
  namespace           = "AWS/MediaConnect"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.packet_loss_threshold
  alarm_description   = "This metric monitors MediaConnect packet loss"
  datapoints_to_alarm = 1

  dimensions = {
    FlowARN = aws_mediaconnect_flow.live_stream.arn
  }

  alarm_actions = [aws_sns_topic.media_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-packet-loss-alarm"
  })
}

# CloudWatch alarm for jitter
resource "aws_cloudwatch_metric_alarm" "jitter_alarm" {
  alarm_name          = "${local.name_prefix}-jitter-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SourceJitter"
  namespace           = "AWS/MediaConnect"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.jitter_threshold_ms
  alarm_description   = "This metric monitors MediaConnect jitter"
  datapoints_to_alarm = 2

  dimensions = {
    FlowARN = aws_mediaconnect_flow.live_stream.arn
  }

  alarm_actions = [aws_sns_topic.media_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jitter-alarm"
  })
}

# CloudWatch alarm to trigger Step Functions workflow
resource "aws_cloudwatch_metric_alarm" "workflow_trigger_alarm" {
  alarm_name          = "${local.name_prefix}-workflow-trigger-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SourcePacketLossPercent"
  namespace           = "AWS/MediaConnect"
  period              = "60"
  statistic           = "Average"
  threshold           = var.workflow_trigger_threshold
  alarm_description   = "Triggers media monitoring workflow"
  datapoints_to_alarm = 1

  dimensions = {
    FlowARN = aws_mediaconnect_flow.live_stream.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-workflow-trigger-alarm"
  })
}

# ==============================================================================
# EVENTBRIDGE RULE FOR AUTOMATED WORKFLOW EXECUTION
# ==============================================================================

# EventBridge rule to trigger Step Functions on alarm
resource "aws_cloudwatch_event_rule" "alarm_rule" {
  name        = "${local.name_prefix}-alarm-rule-${local.suffix}"
  description = "Triggers workflow on MediaConnect alarm"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.workflow_trigger_alarm.alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alarm-rule"
  })
}

# EventBridge target to invoke Step Functions
resource "aws_cloudwatch_event_target" "step_functions_target" {
  rule      = aws_cloudwatch_event_rule.alarm_rule.name
  target_id = "TriggerStepFunctions"
  arn       = aws_sfn_state_machine.media_workflow.arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input = jsonencode({
    flow_arn = aws_mediaconnect_flow.live_stream.arn
  })
}

# ==============================================================================
# CLOUDWATCH DASHBOARD
# ==============================================================================

# CloudWatch dashboard for media monitoring
resource "aws_cloudwatch_dashboard" "media_dashboard" {
  dashboard_name = "${local.name_prefix}-monitoring-${local.suffix}"

  dashboard_body = templatefile("${path.module}/dashboards/media-dashboard.json", {
    region   = data.aws_region.current.name
    flow_arn = aws_mediaconnect_flow.live_stream.arn
  })
}