# Main Terraform configuration for Video Content Analysis with AWS Elemental MediaAnalyzer

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  resource_suffix = lower(random_id.suffix.hex)
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

# =============================================================================
# S3 BUCKETS
# =============================================================================

# S3 bucket for source videos
resource "aws_s3_bucket" "source_bucket" {
  bucket = "${var.project_name}-source-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-source-${local.resource_suffix}"
    Type = "Source"
  })
}

# S3 bucket for analysis results
resource "aws_s3_bucket" "results_bucket" {
  bucket = "${var.project_name}-results-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-results-${local.resource_suffix}"
    Type = "Results"
  })
}

# S3 bucket for temporary files
resource "aws_s3_bucket" "temp_bucket" {
  bucket = "${var.project_name}-temp-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-temp-${local.resource_suffix}"
    Type = "Temporary"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "results_bucket_versioning" {
  bucket = aws_s3_bucket.results_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "source_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.results_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "temp_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.temp_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "source_bucket_pab" {
  bucket = aws_s3_bucket.source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "results_bucket_pab" {
  bucket = aws_s3_bucket.results_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "temp_bucket_pab" {
  bucket = aws_s3_bucket.temp_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "results_bucket_lifecycle" {
  bucket = aws_s3_bucket.results_bucket.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    dynamic "expiration" {
      for_each = var.s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_lifecycle_expiration_days
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "temp_bucket_lifecycle" {
  bucket = aws_s3_bucket.temp_bucket.id

  rule {
    id     = "delete_temp_files"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

# S3 bucket policy for secure transport
resource "aws_s3_bucket_policy" "source_bucket_policy" {
  bucket = aws_s3_bucket.source_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# =============================================================================
# DYNAMODB TABLE
# =============================================================================

# DynamoDB table for storing analysis results
resource "aws_dynamodb_table" "analysis_table" {
  name           = "${var.project_name}-analysis-results-${local.resource_suffix}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "VideoId"
  range_key      = "Timestamp"

  attribute {
    name = "VideoId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  attribute {
    name = "JobStatus"
    type = "S"
  }

  # Global Secondary Index for querying by job status
  global_secondary_index {
    name               = "JobStatusIndex"
    hash_key           = "JobStatus"
    range_key          = "Timestamp"
    write_capacity     = 5
    read_capacity      = 5
    projection_type    = "ALL"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-analysis-results-${local.resource_suffix}"
  })
}

# =============================================================================
# SNS AND SQS
# =============================================================================

# SNS topic for job notifications
resource "aws_sns_topic" "analysis_notifications" {
  name = "${var.project_name}-notifications-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notifications-${local.resource_suffix}"
  })
}

# SQS queue for processing notifications
resource "aws_sqs_queue" "analysis_queue" {
  name = "${var.project_name}-queue-${local.resource_suffix}"

  # Message retention period (14 days)
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-queue-${local.resource_suffix}"
  })
}

# SQS queue policy to allow SNS to send messages
resource "aws_sqs_queue_policy" "analysis_queue_policy" {
  queue_url = aws_sqs_queue.analysis_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.analysis_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.analysis_notifications.arn
          }
        }
      }
    ]
  })
}

# SNS topic subscription to SQS queue
resource "aws_sns_topic_subscription" "analysis_queue_subscription" {
  topic_arn = aws_sns_topic.analysis_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.analysis_queue.arn
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"

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
    Name = "${var.project_name}-lambda-role-${local.resource_suffix}"
  })
}

# IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:StartMediaAnalysisJob",
          "rekognition:GetMediaAnalysisJob",
          "rekognition:StartContentModeration",
          "rekognition:GetContentModeration",
          "rekognition:StartSegmentDetection",
          "rekognition:GetSegmentDetection",
          "rekognition:StartTextDetection",
          "rekognition:GetTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.source_bucket.arn}/*",
          "${aws_s3_bucket.results_bucket.arn}/*",
          "${aws_s3_bucket.temp_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.analysis_table.arn,
          "${aws_dynamodb_table.analysis_table.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.analysis_notifications.arn
      }
    ]
  })
}

# Attach basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-step-functions-role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-step-functions-role-${local.resource_suffix}"
  })
}

# IAM policy for Step Functions
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-step-functions-policy-${local.resource_suffix}"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.analysis_notifications.arn
      }
    ]
  })
}

# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================

# Lambda function for video analysis initialization
resource "aws_lambda_function" "init_function" {
  filename         = data.archive_file.init_function_zip.output_path
  function_name    = "${var.project_name}-init-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.init_function_zip.output_base64sha256

  environment {
    variables = {
      ANALYSIS_TABLE = aws_dynamodb_table.analysis_table.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-init-${local.resource_suffix}"
  })
}

# Lambda function for content moderation
resource "aws_lambda_function" "moderation_function" {
  filename         = data.archive_file.moderation_function_zip.output_path
  function_name    = "${var.project_name}-moderation-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.moderation_function_zip.output_base64sha256

  environment {
    variables = {
      ANALYSIS_TABLE        = aws_dynamodb_table.analysis_table.name
      SNS_TOPIC_ARN        = aws_sns_topic.analysis_notifications.arn
      REKOGNITION_ROLE_ARN = aws_iam_role.lambda_role.arn
      MIN_CONFIDENCE       = var.rekognition_min_confidence
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-moderation-${local.resource_suffix}"
  })
}

# Lambda function for segment detection
resource "aws_lambda_function" "segment_function" {
  filename         = data.archive_file.segment_function_zip.output_path
  function_name    = "${var.project_name}-segment-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.segment_function_zip.output_base64sha256

  environment {
    variables = {
      ANALYSIS_TABLE        = aws_dynamodb_table.analysis_table.name
      SNS_TOPIC_ARN        = aws_sns_topic.analysis_notifications.arn
      REKOGNITION_ROLE_ARN = aws_iam_role.lambda_role.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-segment-${local.resource_suffix}"
  })
}

# Lambda function for results aggregation
resource "aws_lambda_function" "aggregation_function" {
  filename         = data.archive_file.aggregation_function_zip.output_path
  function_name    = "${var.project_name}-aggregation-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.aggregation_lambda_timeout
  memory_size     = var.aggregation_lambda_memory_size
  source_code_hash = data.archive_file.aggregation_function_zip.output_base64sha256

  environment {
    variables = {
      ANALYSIS_TABLE  = aws_dynamodb_table.analysis_table.name
      RESULTS_BUCKET  = aws_s3_bucket.results_bucket.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-aggregation-${local.resource_suffix}"
  })
}

# Lambda function for S3 event trigger
resource "aws_lambda_function" "trigger_function" {
  filename         = data.archive_file.trigger_function_zip.output_path
  function_name    = "${var.project_name}-trigger-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.trigger_function_zip.output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.video_analysis_workflow.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-trigger-${local.resource_suffix}"
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "init_function_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.init_function.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-init-logs-${local.resource_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "moderation_function_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.moderation_function.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-moderation-logs-${local.resource_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "segment_function_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.segment_function.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-segment-logs-${local.resource_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "aggregation_function_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.aggregation_function.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-aggregation-logs-${local.resource_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "trigger_function_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.trigger_function.function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-trigger-logs-${local.resource_suffix}"
  })
}

# =============================================================================
# STEP FUNCTIONS STATE MACHINE
# =============================================================================

# Step Functions state machine for video analysis workflow
resource "aws_sfn_state_machine" "video_analysis_workflow" {
  name     = "${var.project_name}-workflow-${local.resource_suffix}"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Video Content Analysis Workflow"
    StartAt = "InitializeAnalysis"
    States = {
      InitializeAnalysis = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.init_function.function_name
          "Payload.$"  = "$"
        }
        Next = "ParallelAnalysis"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
      }
      ParallelAnalysis = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "ContentModeration"
            States = {
              ContentModeration = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.moderation_function.function_name
                  "Payload.$"  = "$.Payload.body"
                }
                End = true
              }
            }
          },
          {
            StartAt = "SegmentDetection"
            States = {
              SegmentDetection = {
                Type     = "Task"
                Resource = "arn:aws:states:::lambda:invoke"
                Parameters = {
                  FunctionName = aws_lambda_function.segment_function.function_name
                  "Payload.$"  = "$.Payload.body"
                }
                End = true
              }
            }
          }
        ]
        Next = "WaitForCompletion"
      }
      WaitForCompletion = {
        Type    = "Wait"
        Seconds = 60
        Next    = "AggregateResults"
      }
      AggregateResults = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.aggregation_function.function_name
          Payload = {
            "jobId.$"           = "$[0].Payload.body.jobId"
            "videoId.$"         = "$[0].Payload.body.videoId"
            "moderationJobId.$" = "$[0].Payload.body.moderationJobId"
            "segmentJobId.$"    = "$[1].Payload.body.segmentJobId"
          }
        }
        Next = "NotifyCompletion"
      }
      NotifyCompletion = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.analysis_notifications.arn
          Message = {
            "jobId.$"           = "$.Payload.body.jobId"
            "videoId.$"         = "$.Payload.body.videoId"
            "status.$"          = "$.Payload.body.status"
            "resultsLocation.$" = "$.Payload.body.resultsLocation"
          }
        }
        End = true
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-workflow-${local.resource_suffix}"
  })
}

# =============================================================================
# S3 EVENT NOTIFICATION
# =============================================================================

# Lambda permission for S3 to invoke trigger function
resource "aws_lambda_permission" "s3_trigger_permission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".mp4"
  }

  depends_on = [aws_lambda_permission.s3_trigger_permission]
}

# =============================================================================
# CLOUDWATCH DASHBOARD AND ALARMS
# =============================================================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "video_analysis_dashboard" {
  dashboard_name = "${var.project_name}-dashboard-${local.resource_suffix}"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.init_function.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.moderation_function.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.segment_function.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.aggregation_function.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Duration"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", aws_sfn_state_machine.video_analysis_workflow.arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.video_analysis_workflow.arn]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Step Functions Executions"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.analysis_table.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.analysis_table.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB Capacity Consumption"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.source_bucket.bucket, "StorageType", "AllStorageTypes"],
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.source_bucket.bucket, "StorageType", "StandardStorage"]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "S3 Storage Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# CloudWatch alarm for failed Step Functions executions
resource "aws_cloudwatch_metric_alarm" "step_functions_failed_executions" {
  alarm_name          = "${var.project_name}-failed-executions-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors failed Step Functions executions"
  alarm_actions       = [aws_sns_topic.analysis_notifications.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.video_analysis_workflow.arn
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-failed-executions-${local.resource_suffix}"
  })
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.analysis_notifications.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-errors-${local.resource_suffix}"
  })
}

# =============================================================================
# LAMBDA DEPLOYMENT PACKAGES
# =============================================================================

# Lambda function source code archives
data "archive_file" "init_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/init_function.zip"
  source {
    content = templatefile("${path.module}/lambda_code/init_function.py", {
      analysis_table = aws_dynamodb_table.analysis_table.name
    })
    filename = "index.py"
  }
}

data "archive_file" "moderation_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/moderation_function.zip"
  source {
    content = templatefile("${path.module}/lambda_code/moderation_function.py", {
      analysis_table        = aws_dynamodb_table.analysis_table.name
      sns_topic_arn        = aws_sns_topic.analysis_notifications.arn
      rekognition_role_arn = aws_iam_role.lambda_role.arn
      min_confidence       = var.rekognition_min_confidence
    })
    filename = "index.py"
  }
}

data "archive_file" "segment_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/segment_function.zip"
  source {
    content = templatefile("${path.module}/lambda_code/segment_function.py", {
      analysis_table        = aws_dynamodb_table.analysis_table.name
      sns_topic_arn        = aws_sns_topic.analysis_notifications.arn
      rekognition_role_arn = aws_iam_role.lambda_role.arn
    })
    filename = "index.py"
  }
}

data "archive_file" "aggregation_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/aggregation_function.zip"
  source {
    content = templatefile("${path.module}/lambda_code/aggregation_function.py", {
      analysis_table  = aws_dynamodb_table.analysis_table.name
      results_bucket  = aws_s3_bucket.results_bucket.bucket
    })
    filename = "index.py"
  }
}

data "archive_file" "trigger_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/trigger_function.zip"
  source {
    content = templatefile("${path.module}/lambda_code/trigger_function.py", {
      state_machine_arn = aws_sfn_state_machine.video_analysis_workflow.arn
    })
    filename = "index.py"
  }
}