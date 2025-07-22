# Cost Governance Infrastructure - Main Configuration

# Data sources for account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex
  
  # Common naming prefix
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Region      = local.region
  })
}

# S3 Buckets for Config and Cost Governance Reports
resource "aws_s3_bucket" "config_bucket" {
  bucket = "${local.name_prefix}-aws-config-${local.suffix}"
  
  tags = merge(local.common_tags, {
    Purpose = "AWS Config Configuration History"
  })
}

resource "aws_s3_bucket" "cost_governance_bucket" {
  bucket = "${local.name_prefix}-cost-governance-${local.suffix}"
  
  tags = merge(local.common_tags, {
    Purpose = "Cost Governance Reports and Data"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "cost_governance_bucket_versioning" {
  bucket = aws_s3_bucket.cost_governance_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cost_governance_bucket_encryption" {
  bucket = aws_s3_bucket.cost_governance_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "cost_governance_lifecycle" {
  bucket = aws_s3_bucket.cost_governance_bucket.id

  rule {
    id     = "cost_optimization"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# S3 Bucket policy for AWS Config
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
            "AWS:SourceAccount" = local.account_id
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
            "AWS:SourceAccount" = local.account_id
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
        Resource = "${aws_s3_bucket.config_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# IAM Role for AWS Config
resource "aws_iam_role" "config_role" {
  name = "${local.name_prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

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

  tags = local.common_tags
}

# IAM Policy for Lambda Cost Governance
resource "aws_iam_policy" "lambda_cost_governance_policy" {
  name        = "${local.name_prefix}-lambda-policy"
  description = "Policy for cost governance Lambda functions"

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
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:AddTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:StopDBInstance",
          "rds:StopDBCluster",
          "rds:DeleteDBInstance",
          "rds:AddTagsToResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:PutBucketLifecycleConfiguration",
          "s3:GetBucketLifecycleConfiguration"
        ]
        Resource = [
          aws_s3_bucket.cost_governance_bucket.arn,
          "${aws_s3_bucket.cost_governance_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          aws_sns_topic.cost_governance_alerts.arn,
          aws_sns_topic.critical_cost_actions.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.cost_governance_queue.arn,
          aws_sqs_queue.cost_governance_dlq.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "config:GetComplianceDetailsByConfigRule",
          "config:GetComplianceDetailsByResource",
          "config:PutEvaluations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_cost_governance_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cost_governance_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Topics for Notifications
resource "aws_sns_topic" "cost_governance_alerts" {
  name = "${local.name_prefix}-cost-alerts"

  tags = merge(local.common_tags, {
    Purpose = "Cost Governance Alerts"
  })
}

resource "aws_sns_topic" "critical_cost_actions" {
  name = "${local.name_prefix}-critical-actions"

  tags = merge(local.common_tags, {
    Purpose = "Critical Cost Actions"
  })
}

# SNS Topic Subscriptions
resource "aws_sns_topic_subscription" "cost_alerts_email" {
  topic_arn = aws_sns_topic.cost_governance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_subscription" "critical_actions_email" {
  topic_arn = aws_sns_topic.critical_cost_actions.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SQS Queues for Event Processing
resource "aws_sqs_queue" "cost_governance_dlq" {
  name = "${local.name_prefix}-dlq"

  tags = merge(local.common_tags, {
    Purpose = "Dead Letter Queue for Cost Governance"
  })
}

resource "aws_sqs_queue" "cost_governance_queue" {
  name                       = "${local.name_prefix}-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.cost_governance_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Purpose = "Cost Governance Event Processing"
  })
}

# Lambda Functions
# 1. Idle Instance Detector
data "archive_file" "idle_instance_detector_zip" {
  type        = "zip"
  output_path = "${path.module}/idle_instance_detector.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/idle_instance_detector.py", {
      cpu_threshold = var.cpu_utilization_threshold
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "idle_instance_detector" {
  filename         = data.archive_file.idle_instance_detector_zip.output_path
  function_name    = "${local.name_prefix}-idle-detector"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.idle_instance_detector_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.cost_governance_alerts.arn
      CPU_THRESHOLD      = var.cpu_utilization_threshold
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Idle Instance Detection"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_cost_governance_policy_attachment,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
}

# 2. Volume Cleanup Function
data "archive_file" "volume_cleanup_zip" {
  type        = "zip"
  output_path = "${path.module}/volume_cleanup.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/volume_cleanup.py", {
      age_threshold_days = var.volume_age_threshold_days
    })
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "volume_cleanup" {
  filename         = data.archive_file.volume_cleanup_zip.output_path
  function_name    = "${local.name_prefix}-volume-cleanup"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.volume_cleanup_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.cost_governance_alerts.arn
      AGE_THRESHOLD_DAYS = var.volume_age_threshold_days
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Volume Cleanup Automation"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_cost_governance_policy_attachment,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
}

# 3. Cost Reporter Function
data "archive_file" "cost_reporter_zip" {
  type        = "zip"
  output_path = "${path.module}/cost_reporter.zip"
  
  source {
    content = file("${path.module}/lambda_functions/cost_reporter.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "cost_reporter" {
  filename         = data.archive_file.cost_reporter_zip.output_path
  function_name    = "${local.name_prefix}-cost-reporter"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.cost_reporter_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = 512

  environment {
    variables = {
      SNS_TOPIC_ARN    = aws_sns_topic.cost_governance_alerts.arn
      REPORTS_BUCKET   = aws_s3_bucket.cost_governance_bucket.bucket
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Cost Governance Reporting"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_cost_governance_policy_attachment,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
}

# AWS Config Configuration Recorder
resource "aws_config_delivery_channel" "cost_governance" {
  count          = var.enable_config_recorder ? 1 : 0
  name           = "cost-governance-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
}

resource "aws_config_configuration_recorder" "cost_governance" {
  count    = var.enable_config_recorder ? 1 : 0
  name     = "cost-governance-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
    resource_types                = var.config_resource_types
  }

  depends_on = [aws_config_delivery_channel.cost_governance]
}

resource "aws_config_configuration_recorder_status" "cost_governance" {
  count      = var.enable_config_recorder ? 1 : 0
  name       = aws_config_configuration_recorder.cost_governance[0].name
  is_enabled = true
  depends_on = [aws_config_configuration_recorder.cost_governance]
}

# Config Rules for Cost Governance
resource "aws_config_config_rule" "idle_ec2_instances" {
  count = var.enable_config_recorder ? 1 : 0
  name  = "idle-ec2-instances"

  source {
    owner             = "AWS"
    source_identifier = "EC2_INSTANCE_NO_HIGH_LEVEL_FINDINGS"
  }

  input_parameters = jsonencode({
    desiredInstanceTypes = "t3.micro,t3.small,t3.medium"
  })

  depends_on = [aws_config_configuration_recorder.cost_governance]
}

resource "aws_config_config_rule" "unattached_ebs_volumes" {
  count = var.enable_config_recorder ? 1 : 0
  name  = "unattached-ebs-volumes"

  source {
    owner             = "AWS"
    source_identifier = "EBS_OPTIMIZED_INSTANCE"
  }

  depends_on = [aws_config_configuration_recorder.cost_governance]
}

resource "aws_config_config_rule" "unused_load_balancers" {
  count = var.enable_config_recorder ? 1 : 0
  name  = "unused-load-balancers"

  source {
    owner             = "AWS"
    source_identifier = "ELB_CROSS_ZONE_LOAD_BALANCING_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.cost_governance]
}

# EventBridge Rules for Automation
resource "aws_cloudwatch_event_rule" "config_compliance_changes" {
  name        = "${local.name_prefix}-config-compliance"
  description = "Trigger cost remediation on Config compliance changes"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      configRuleName = [
        "idle-ec2-instances",
        "unattached-ebs-volumes", 
        "unused-load-balancers"
      ]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
    }
  })

  tags = local.common_tags
}

# EventBridge Targets for Config Compliance
resource "aws_cloudwatch_event_target" "idle_detector_target" {
  rule      = aws_cloudwatch_event_rule.config_compliance_changes.name
  target_id = "IdleDetectorTarget"
  arn       = aws_lambda_function.idle_instance_detector.arn

  input = jsonencode({
    source = "config-compliance"
  })
}

resource "aws_cloudwatch_event_target" "volume_cleanup_target" {
  rule      = aws_cloudwatch_event_rule.config_compliance_changes.name
  target_id = "VolumeCleanupTarget"
  arn       = aws_lambda_function.volume_cleanup.arn

  input = jsonencode({
    source = "config-compliance"
  })
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_idle_detector" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.idle_instance_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance_changes.arn
}

resource "aws_lambda_permission" "allow_eventbridge_volume_cleanup" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.volume_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_compliance_changes.arn
}

# Scheduled EventBridge Rule for Weekly Scans
resource "aws_cloudwatch_event_rule" "weekly_cost_optimization_scan" {
  count               = var.enable_scheduled_scans ? 1 : 0
  name                = "${local.name_prefix}-weekly-scan"
  description         = "Weekly scan for cost optimization opportunities"
  schedule_expression = var.scan_schedule_rate

  tags = local.common_tags
}

# Scheduled EventBridge Targets
resource "aws_cloudwatch_event_target" "scheduled_idle_detector" {
  count     = var.enable_scheduled_scans ? 1 : 0
  rule      = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].name
  target_id = "ScheduledIdleDetector"
  arn       = aws_lambda_function.idle_instance_detector.arn

  input = jsonencode({
    source = "scheduled-scan"
  })
}

resource "aws_cloudwatch_event_target" "scheduled_volume_cleanup" {
  count     = var.enable_scheduled_scans ? 1 : 0
  rule      = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].name
  target_id = "ScheduledVolumeCleanup"
  arn       = aws_lambda_function.volume_cleanup.arn

  input = jsonencode({
    source = "scheduled-scan"
  })
}

resource "aws_cloudwatch_event_target" "scheduled_cost_reporter" {
  count     = var.enable_scheduled_scans ? 1 : 0
  rule      = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].name
  target_id = "ScheduledCostReporter"
  arn       = aws_lambda_function.cost_reporter.arn

  input = jsonencode({
    source = "scheduled-report"
  })
}

# Lambda permissions for scheduled EventBridge
resource "aws_lambda_permission" "allow_scheduled_idle_detector" {
  count         = var.enable_scheduled_scans ? 1 : 0
  statement_id  = "AllowScheduledExecution"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.idle_instance_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].arn
}

resource "aws_lambda_permission" "allow_scheduled_volume_cleanup" {
  count         = var.enable_scheduled_scans ? 1 : 0
  statement_id  = "AllowScheduledExecution"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.volume_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].arn
}

resource "aws_lambda_permission" "allow_scheduled_cost_reporter" {
  count         = var.enable_scheduled_scans ? 1 : 0
  statement_id  = "AllowScheduledExecution"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].arn
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "idle_detector_logs" {
  name              = "/aws/lambda/${aws_lambda_function.idle_instance_detector.function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "volume_cleanup_logs" {
  name              = "/aws/lambda/${aws_lambda_function.volume_cleanup.function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "cost_reporter_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_reporter.function_name}"
  retention_in_days = 14

  tags = local.common_tags
}