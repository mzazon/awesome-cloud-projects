# AWS Video Workflow Orchestration with Step Functions
# This Terraform configuration creates a comprehensive video processing pipeline
# using AWS Step Functions, MediaConvert, Lambda, and supporting services

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get MediaConvert endpoint for the region
data "aws_mediaconvert_presets" "example" {}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result
  
  # Resource names
  source_bucket_name   = "${local.name_prefix}-source-${local.suffix}"
  output_bucket_name   = "${local.name_prefix}-output-${local.suffix}"
  archive_bucket_name  = "${local.name_prefix}-archive-${local.suffix}"
  jobs_table_name      = "${local.name_prefix}-jobs-${local.suffix}"
  sns_topic_name       = "${local.name_prefix}-notifications-${local.suffix}"
  workflow_name        = "${local.name_prefix}-workflow-${local.suffix}"
  
  # Common tags
  common_tags = {
    Name        = local.name_prefix
    Environment = var.environment
    Project     = var.project_name
    Recipe      = "automated-video-workflow-orchestration-step-functions"
  }
}

# ===================================================================
# S3 BUCKETS FOR VIDEO PROCESSING PIPELINE
# ===================================================================

# Source bucket for input videos
resource "aws_s3_bucket" "source" {
  bucket        = local.source_bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Purpose = "Video source files"
  })
}

# Source bucket versioning configuration
resource "aws_s3_bucket_versioning" "source" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Source bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Source bucket public access block
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output bucket for processed videos
resource "aws_s3_bucket" "output" {
  bucket        = local.output_bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Purpose = "Processed video outputs"
  })
}

# Output bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Output bucket public access block
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Archive bucket for source file retention
resource "aws_s3_bucket" "archive" {
  bucket        = local.archive_bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Purpose = "Archived source files"
  })
}

# Archive bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Archive bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  
  rule {
    id     = "archive_lifecycle"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# ===================================================================
# DYNAMODB TABLE FOR JOB TRACKING
# ===================================================================

resource "aws_dynamodb_table" "jobs" {
  name           = local.jobs_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "JobId"
  
  # Only set read/write capacity for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? 10 : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? 10 : null
  
  attribute {
    name = "JobId"
    type = "S"
  }
  
  attribute {
    name = "CreatedAt"
    type = "S"
  }
  
  # Global Secondary Index for querying by creation time
  global_secondary_index {
    name     = "CreatedAtIndex"
    hash_key = "CreatedAt"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
    
    projection_type = "ALL"
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Video job tracking"
  })
}

# ===================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ===================================================================

resource "aws_sns_topic" "notifications" {
  name = local.sns_topic_name
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"
  
  tags = merge(local.common_tags, {
    Purpose = "Workflow notifications"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "notifications" {
  arn = aws_sns_topic.notifications.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription if notification email is provided
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===================================================================
# IAM ROLES AND POLICIES
# ===================================================================

# MediaConvert service role
resource "aws_iam_role" "mediaconvert" {
  name = "${local.name_prefix}-mediaconvert-role-${local.suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "mediaconvert.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = local.common_tags
}

# MediaConvert role policy
resource "aws_iam_role_policy" "mediaconvert" {
  name = "MediaConvertPolicy"
  role = aws_iam_role.mediaconvert.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*",
          aws_s3_bucket.archive.arn,
          "${aws_s3_bucket.archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda" {
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
  
  tags = local.common_tags
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda role custom policy
resource "aws_iam_role_policy" "lambda" {
  name = "LambdaWorkflowPolicy"
  role = aws_iam_role.lambda.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:HeadObject"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*",
          aws_s3_bucket.archive.arn,
          "${aws_s3_bucket.archive.arn}/*"
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
          aws_dynamodb_table.jobs.arn,
          "${aws_dynamodb_table.jobs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.video_workflow.arn
      }
    ]
  })
}

# Step Functions execution role
resource "aws_iam_role" "step_functions" {
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
  
  tags = local.common_tags
}

# Step Functions role policy
resource "aws_iam_role_policy" "step_functions" {
  name = "StepFunctionsWorkflowPolicy"
  role = aws_iam_role.step_functions.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.metadata_extractor.arn,
          aws_lambda_function.quality_control.arn,
          aws_lambda_function.publisher.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "mediaconvert:CreateJob",
          "mediaconvert:GetJob",
          "mediaconvert:ListJobs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.mediaconvert.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.jobs.arn,
          "${aws_dynamodb_table.jobs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:CopyObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*",
          aws_s3_bucket.archive.arn,
          "${aws_s3_bucket.archive.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===================================================================
# LAMBDA FUNCTIONS FOR WORKFLOW TASKS
# ===================================================================

# Lambda function code archives
data "archive_file" "metadata_extractor" {
  type        = "zip"
  output_path = "${path.module}/metadata_extractor.zip"
  
  source {
    content  = file("${path.module}/../lambda/metadata_extractor.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "quality_control" {
  type        = "zip"
  output_path = "${path.module}/quality_control.zip"
  
  source {
    content  = file("${path.module}/../lambda/quality_control.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "publisher" {
  type        = "zip"
  output_path = "${path.module}/publisher.zip"
  
  source {
    content  = file("${path.module}/../lambda/publisher.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "workflow_trigger" {
  type        = "zip"
  output_path = "${path.module}/workflow_trigger.zip"
  
  source {
    content  = file("${path.module}/../lambda/workflow_trigger.py")
    filename = "lambda_function.py"
  }
}

# Metadata extraction Lambda function
resource "aws_lambda_function" "metadata_extractor" {
  filename         = data.archive_file.metadata_extractor.output_path
  function_name    = "${local.name_prefix}-metadata-extractor-${local.suffix}"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.metadata_extractor.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE = aws_dynamodb_table.jobs.name
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Video metadata extraction"
  })
}

# Quality control Lambda function
resource "aws_lambda_function" "quality_control" {
  filename         = data.archive_file.quality_control.output_path
  function_name    = "${local.name_prefix}-quality-control-${local.suffix}"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.quality_control.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE        = aws_dynamodb_table.jobs.name
      QUALITY_THRESHOLD = tostring(var.quality_threshold)
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Video quality control validation"
  })
}

# Publisher Lambda function
resource "aws_lambda_function" "publisher" {
  filename         = data.archive_file.publisher.output_path
  function_name    = "${local.name_prefix}-publisher-${local.suffix}"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.publisher.output_base64sha256
  
  environment {
    variables = {
      JOBS_TABLE    = aws_dynamodb_table.jobs.name
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Video content publishing"
  })
}

# Workflow trigger Lambda function
resource "aws_lambda_function" "workflow_trigger" {
  filename         = data.archive_file.workflow_trigger.output_path
  function_name    = "${local.name_prefix}-workflow-trigger-${local.suffix}"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 256
  source_code_hash = data.archive_file.workflow_trigger.output_base64sha256
  
  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.video_workflow.arn
    }
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Workflow triggering"
  })
}

# ===================================================================
# STEP FUNCTIONS STATE MACHINE
# ===================================================================

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.workflow_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# Step Functions state machine definition
locals {
  state_machine_definition = jsonencode({
    Comment = "Comprehensive video processing workflow with quality control"
    StartAt = "InitializeJob"
    States = {
      InitializeJob = {
        Type = "Pass"
        Parameters = {
          "jobId.$"       = "$.jobId"
          "bucket.$"      = "$.bucket"
          "key.$"         = "$.key"
          outputBucket    = aws_s3_bucket.output.bucket
          archiveBucket   = aws_s3_bucket.archive.bucket
          "timestamp.$"   = "$$.State.EnteredTime"
        }
        Next = "RecordJobStart"
      }
      
      RecordJobStart = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.jobs.name
          Item = {
            JobId = {
              "S.$" = "$.jobId"
            }
            SourceBucket = {
              "S.$" = "$.bucket"
            }
            SourceKey = {
              "S.$" = "$.key"
            }
            CreatedAt = {
              "S.$" = "$.timestamp"
            }
            JobStatus = {
              S = "STARTED"
            }
          }
        }
        Next = "ParallelProcessing"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }
      
      ParallelProcessing = {
        Type = "Parallel"
        Next = "ProcessingComplete"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleProcessingFailure"
            ResultPath  = "$.error"
          }
        ]
        Branches = [
          {
            StartAt = "ExtractMetadata"
            States = {
              ExtractMetadata = {
                Type     = "Task"
                Resource = aws_lambda_function.metadata_extractor.arn
                Parameters = {
                  "bucket.$" = "$.bucket"
                  "key.$"    = "$.key"
                  "jobId.$"  = "$.jobId"
                }
                End = true
                Retry = [
                  {
                    ErrorEquals     = ["States.TaskFailed"]
                    IntervalSeconds = 5
                    MaxAttempts     = 2
                  }
                ]
              }
            }
          },
          {
            StartAt = "TranscodeVideo"
            States = {
              TranscodeVideo = {
                Type     = "Task"
                Resource = "arn:aws:states:::mediaconvert:createJob.sync"
                Parameters = {
                  Role = aws_iam_role.mediaconvert.arn
                  Settings = {
                    OutputGroups = [
                      {
                        Name = "MP4_Output"
                        OutputGroupSettings = {
                          Type = "FILE_GROUP_SETTINGS"
                          FileGroupSettings = {
                            "Destination.$" = "States.Format('s3://${aws_s3_bucket.output.bucket}/mp4/{}/', $.jobId)"
                          }
                        }
                        Outputs = [
                          {
                            NameModifier = "_1080p"
                            ContainerSettings = {
                              Container = "MP4"
                            }
                            VideoDescription = {
                              Width  = 1920
                              Height = 1080
                              CodecSettings = {
                                Codec = "H_264"
                                H264Settings = {
                                  RateControlMode = "QVBR"
                                  QvbrSettings = {
                                    QvbrQualityLevel = 8
                                  }
                                  MaxBitrate = 5000000
                                }
                              }
                            }
                            AudioDescriptions = [
                              {
                                CodecSettings = {
                                  Codec = "AAC"
                                  AacSettings = {
                                    Bitrate    = 128000
                                    CodingMode = "CODING_MODE_2_0"
                                    SampleRate = 48000
                                  }
                                }
                              }
                            ]
                          }
                        ]
                      }
                    ]
                    Inputs = [
                      {
                        "FileInput.$" = "States.Format('s3://{}/{}', $.bucket, $.key)"
                        AudioSelectors = {
                          "Audio Selector 1" = {
                            Tracks          = [1]
                            DefaultSelection = "DEFAULT"
                          }
                        }
                        VideoSelector = {
                          ColorSpace = "FOLLOW"
                        }
                        TimecodeSource = "EMBEDDED"
                      }
                    ]
                  }
                  StatusUpdateInterval = "SECONDS_60"
                  UserMetadata = {
                    "WorkflowJobId.$" = "$.jobId"
                    "SourceFile.$"    = "$.key"
                  }
                }
                End = true
                Retry = [
                  {
                    ErrorEquals     = ["States.TaskFailed"]
                    IntervalSeconds = 30
                    MaxAttempts     = 2
                    BackoffRate     = 2.0
                  }
                ]
              }
            }
          }
        ]
      }
      
      ProcessingComplete = {
        Type = "Pass"
        Parameters = {
          "jobId.$"           = "$[0].jobId"
          "metadata.$"        = "$[0].metadata"
          "mediaConvertJob.$" = "$[1].Job"
          outputs = [
            {
              format         = "mp4"
              bucket         = aws_s3_bucket.output.bucket
              "key.$"        = "States.Format('mp4/{}/output_1080p.mp4', $[0].jobId)"
            }
          ]
        }
        Next = "QualityControl"
      }
      
      QualityControl = {
        Type     = "Task"
        Resource = aws_lambda_function.quality_control.arn
        Parameters = {
          "jobId.$"    = "$.jobId"
          "outputs.$"  = "$.outputs"
          "metadata.$" = "$.metadata"
        }
        Next = "QualityDecision"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 10
            MaxAttempts     = 2
          }
        ]
      }
      
      QualityDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.passed"
            BooleanEquals = true
            Next         = "PublishContent"
          }
        ]
        Default = "QualityControlFailed"
      }
      
      PublishContent = {
        Type     = "Task"
        Resource = aws_lambda_function.publisher.arn
        Parameters = {
          "jobId.$"         = "$.jobId"
          "outputs.$"       = "$.outputs"
          "qualityResults.$" = "$.qualityResults"
          qualityPassed     = true
        }
        Next = "WorkflowSuccess"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 5
            MaxAttempts     = 2
          }
        ]
      }
      
      WorkflowSuccess = {
        Type = "Pass"
        Result = {
          status  = "SUCCESS"
          message = "Video processing workflow completed successfully"
        }
        End = true
      }
      
      QualityControlFailed = {
        Type     = "Task"
        Resource = aws_lambda_function.publisher.arn
        Parameters = {
          "jobId.$"         = "$.jobId"
          "outputs.$"       = "$.outputs"
          "qualityResults.$" = "$.qualityResults"
          qualityPassed     = false
        }
        Next = "WorkflowFailure"
      }
      
      HandleProcessingFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.jobs.name
          Key = {
            JobId = {
              "S.$" = "$.jobId"
            }
          }
          UpdateExpression = "SET JobStatus = :status, ErrorDetails = :error, FailedAt = :timestamp"
          ExpressionAttributeValues = {
            ":status" = {
              S = "FAILED_PROCESSING"
            }
            ":error" = {
              "S.$" = "$.error.Cause"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        Next = "WorkflowFailure"
      }
      
      WorkflowFailure = {
        Type  = "Fail"
        Cause = "Video processing workflow failed"
      }
    }
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "video_workflow" {
  name       = local.workflow_name
  role_arn   = aws_iam_role.step_functions.arn
  definition = local.state_machine_definition
  type       = var.step_functions_type
  
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
  
  tags = merge(local.common_tags, {
    Purpose = "Video workflow orchestration"
  })
}

# ===================================================================
# API GATEWAY FOR WORKFLOW TRIGGERING (OPTIONAL)
# ===================================================================

# API Gateway for workflow triggering
resource "aws_apigatewayv2_api" "workflow" {
  count         = var.enable_api_gateway ? 1 : 0
  name          = "${local.name_prefix}-workflow-api-${local.suffix}"
  protocol_type = "HTTP"
  description   = "Video processing workflow API"
  
  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["*"]
    allow_origins     = ["*"]
  }
  
  tags = local.common_tags
}

# API Gateway integration with trigger Lambda
resource "aws_apigatewayv2_integration" "workflow_trigger" {
  count                = var.enable_api_gateway ? 1 : 0
  api_id               = aws_apigatewayv2_api.workflow[0].id
  integration_type     = "AWS_PROXY"
  integration_uri      = aws_lambda_function.workflow_trigger.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway route
resource "aws_apigatewayv2_route" "start_workflow" {
  count     = var.enable_api_gateway ? 1 : 0
  api_id    = aws_apigatewayv2_api.workflow[0].id
  route_key = "POST /start-workflow"
  target    = "integrations/${aws_apigatewayv2_integration.workflow_trigger[0].id}"
}

# API Gateway deployment
resource "aws_apigatewayv2_deployment" "workflow" {
  count   = var.enable_api_gateway ? 1 : 0
  api_id  = aws_apigatewayv2_api.workflow[0].id
  
  depends_on = [aws_apigatewayv2_route.start_workflow]
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "prod" {
  count       = var.enable_api_gateway ? 1 : 0
  api_id      = aws_apigatewayv2_api.workflow[0].id
  deployment_id = aws_apigatewayv2_deployment.workflow[0].id
  name        = "prod"
  
  tags = local.common_tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count         = var.enable_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_trigger.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.workflow[0].execution_arn}/*/*"
}

# ===================================================================
# S3 EVENT TRIGGERS (OPTIONAL)
# ===================================================================

# Lambda permission for S3 to invoke trigger function
resource "aws_lambda_permission" "s3_trigger" {
  count         = var.enable_s3_triggers ? 1 : 0
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "source_notification" {
  count  = var.enable_s3_triggers ? 1 : 0
  bucket = aws_s3_bucket.source.id
  
  # Create Lambda configurations for each video file extension
  dynamic "lambda_function" {
    for_each = var.video_file_extensions
    content {
      id                    = "VideoWorkflowTrigger${upper(lambda_function.value)}"
      lambda_function_arn   = aws_lambda_function.workflow_trigger.arn
      events                = ["s3:ObjectCreated:*"]
      filter_suffix         = ".${lambda_function.value}"
    }
  }
  
  depends_on = [aws_lambda_permission.s3_trigger]
}

# ===================================================================
# CLOUDWATCH MONITORING (OPTIONAL)
# ===================================================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "video_workflow" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.name_prefix}-monitoring-${local.suffix}"
  
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
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", aws_sfn_state_machine.video_workflow.arn],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsStarted", ".", "."]
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
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/MediaConvert", "JobsCompleted"],
            [".", "JobsErrored"],
            [".", "JobsSubmitted"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "MediaConvert Jobs"
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.metadata_extractor.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Functions Performance"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.step_functions.name}'\n| fields @timestamp, type, execution_arn\n| filter type = \"ExecutionStarted\" or type = \"ExecutionSucceeded\" or type = \"ExecutionFailed\"\n| sort @timestamp desc\n| limit 100"
          region = data.aws_region.current.name
          title  = "Recent Workflow Executions"
          view   = "table"
        }
      }
    ]
  })
}

# ===================================================================
# COST MONITORING (OPTIONAL)
# ===================================================================

# Budget for cost monitoring
resource "aws_budgets_budget" "video_workflow" {
  count        = var.enable_cost_alerts ? 1 : 0
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_cost_threshold)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filters = {
    Service = [
      "AWS Step Functions",
      "AWS Lambda",
      "Amazon Simple Storage Service",
      "Amazon DynamoDB",
      "AWS Elemental MediaConvert",
      "Amazon Simple Notification Service"
    ]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
  }
}