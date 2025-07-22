# Main Terraform configuration for serverless medical image processing

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Resource naming convention
  datastore_name     = var.datastore_name != "" ? var.datastore_name : "${var.project_name}-${local.suffix}"
  input_bucket_name  = "${var.project_name}-dicom-input-${local.suffix}"
  output_bucket_name = "${var.project_name}-dicom-output-${local.suffix}"
  state_machine_name = "${var.project_name}-processor-${local.suffix}"
}

# Data source to get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###########################################
# KMS Key for Encryption (HIPAA Compliance)
###########################################

resource "aws_kms_key" "medical_imaging" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for medical imaging pipeline encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda and HealthImaging access"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "medical-imaging.amazonaws.com",
            "s3.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kms-key"
  })
}

resource "aws_kms_alias" "medical_imaging" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-medical-imaging"
  target_key_id = aws_kms_key.medical_imaging[0].key_id
}

###########################################
# S3 Buckets for DICOM Storage
###########################################

# Input bucket for DICOM files
resource "aws_s3_bucket" "input" {
  bucket        = local.input_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "DICOM Input Bucket"
    Type = "Input"
  })
}

# Output bucket for processed results
resource "aws_s3_bucket" "output" {
  bucket        = local.output_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "DICOM Output Bucket"
    Type = "Output"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "input" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.input.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.output.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block (HIPAA compliance)
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "input" {
  count  = var.enable_s3_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_days * 2
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "output" {
  count  = var.enable_s3_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_days * 2
      storage_class = "GLACIER"
    }
  }
}

###########################################
# AWS HealthImaging Data Store
###########################################

resource "aws_medicalimaging_datastore" "main" {
  datastore_name = local.datastore_name

  tags = merge(local.common_tags, {
    Name = "Medical Imaging Data Store"
  })
}

###########################################
# IAM Roles and Policies
###########################################

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.suffix}"

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

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution",
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
    ]
  })
}

# Add KMS permissions if encryption is enabled
resource "aws_iam_role_policy" "lambda_kms_policy" {
  count = var.enable_kms_encryption ? 1 : 0
  name  = "${var.project_name}-lambda-kms-policy"
  role  = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant"
        ]
        Resource = aws_kms_key.medical_imaging[0].arn
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Add X-Ray tracing policy if enabled
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_x_ray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

###########################################
# Lambda Functions
###########################################

# Create Lambda function source code archives
data "archive_file" "start_import_zip" {
  type        = "zip"
  output_path = "${path.module}/start_import.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/start_import.py", {
      datastore_id = aws_medicalimaging_datastore.main.datastore_id
      output_bucket = aws_s3_bucket.output.bucket
      lambda_role_arn = aws_iam_role.lambda_role.arn
    })
    filename = "start_import.py"
  }
}

data "archive_file" "process_metadata_zip" {
  type        = "zip"
  output_path = "${path.module}/process_metadata.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/process_metadata.py", {
      output_bucket = aws_s3_bucket.output.bucket
    })
    filename = "process_metadata.py"
  }
}

data "archive_file" "analyze_image_zip" {
  type        = "zip"
  output_path = "${path.module}/analyze_image.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/analyze_image.py", {
      output_bucket = aws_s3_bucket.output.bucket
    })
    filename = "analyze_image.py"
  }
}

# Lambda function for starting DICOM import
resource "aws_lambda_function" "start_import" {
  filename         = data.archive_file.start_import_zip.output_path
  function_name    = "StartDicomImport-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "start_import.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.start_import_zip.output_base64sha256

  environment {
    variables = {
      DATASTORE_ID     = aws_medicalimaging_datastore.main.datastore_id
      OUTPUT_BUCKET    = aws_s3_bucket.output.bucket
      LAMBDA_ROLE_ARN  = aws_iam_role.lambda_role.arn
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  tags = merge(local.common_tags, {
    Name = "Start DICOM Import"
  })
}

# Lambda function for processing metadata
resource "aws_lambda_function" "process_metadata" {
  filename         = data.archive_file.process_metadata_zip.output_path
  function_name    = "ProcessDicomMetadata-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "process_metadata.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.process_metadata_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.bucket
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  tags = merge(local.common_tags, {
    Name = "Process DICOM Metadata"
  })
}

# Lambda function for image analysis
resource "aws_lambda_function" "analyze_image" {
  filename         = data.archive_file.analyze_image_zip.output_path
  function_name    = "AnalyzeMedicalImage-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "analyze_image.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size * 2  # More memory for image processing
  source_code_hash = data.archive_file.analyze_image_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.bucket
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  tags = merge(local.common_tags, {
    Name = "Analyze Medical Image"
  })
}

###########################################
# Step Functions
###########################################

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_role" {
  name = "${var.project_name}-stepfunctions-role-${local.suffix}"

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

  tags = local.common_tags
}

# Step Functions execution policy
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${var.project_name}-stepfunctions-policy"
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
          aws_lambda_function.start_import.arn,
          aws_lambda_function.process_metadata.arn,
          aws_lambda_function.analyze_image.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetDICOMImportJob"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${local.state_machine_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Step Functions Logs"
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "medical_imaging" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions_role.arn
  type     = var.step_functions_type

  definition = jsonencode({
    Comment = "Medical image processing workflow"
    StartAt = "CheckImportStatus"
    States = {
      CheckImportStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:medicalimaging:getDICOMImportJob"
        Parameters = {
          "DatastoreId.$" = "$.dataStoreId"
          "JobId.$"       = "$.jobId"
        }
        Next = "IsImportComplete"
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
      }
      IsImportComplete = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.JobStatus"
            StringEquals  = "COMPLETED"
            Next          = "ProcessImageSets"
          },
          {
            Variable      = "$.JobStatus"
            StringEquals  = "IN_PROGRESS"
            Next          = "WaitForImport"
          }
        ]
        Default = "ImportFailed"
      }
      WaitForImport = {
        Type    = "Wait"
        Seconds = 30
        Next    = "CheckImportStatus"
      }
      ProcessImageSets = {
        Type   = "Pass"
        Result = "Import completed successfully"
        End    = true
      }
      ImportFailed = {
        Type  = "Fail"
        Error = "ImportJobFailed"
        Cause = "The DICOM import job failed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Name = "Medical Image Processing State Machine"
  })
}

###########################################
# EventBridge Rules
###########################################

# EventBridge rule for import completion
resource "aws_cloudwatch_event_rule" "import_completed" {
  name        = "DicomImportCompleted-${local.suffix}"
  description = "Trigger processing when DICOM import completes"

  event_pattern = jsonencode({
    source      = ["aws.medical-imaging"]
    detail-type = ["Import Job Completed"]
    detail = {
      datastoreId = [aws_medicalimaging_datastore.main.datastore_id]
    }
  })

  tags = local.common_tags
}

# EventBridge target for metadata processing
resource "aws_cloudwatch_event_target" "metadata_processor" {
  rule      = aws_cloudwatch_event_rule.import_completed.name
  target_id = "MetadataProcessorTarget"
  arn       = aws_lambda_function.process_metadata.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_metadata.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.import_completed.arn
}

###########################################
# S3 Event Notifications
###########################################

# Lambda permission for S3 bucket notifications
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_import.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "dicom_upload" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_import.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".dcm"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

###########################################
# CloudWatch Log Groups
###########################################

# Log groups for Lambda functions
resource "aws_cloudwatch_log_group" "start_import" {
  name              = "/aws/lambda/${aws_lambda_function.start_import.function_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Start Import Lambda Logs"
  })
}

resource "aws_cloudwatch_log_group" "process_metadata" {
  name              = "/aws/lambda/${aws_lambda_function.process_metadata.function_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Process Metadata Lambda Logs"
  })
}

resource "aws_cloudwatch_log_group" "analyze_image" {
  name              = "/aws/lambda/${aws_lambda_function.analyze_image.function_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null

  tags = merge(local.common_tags, {
    Name = "Analyze Image Lambda Logs"
  })
}

###########################################
# VPC Endpoints (Optional for Enhanced Security)
###########################################

# VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints && var.vpc_id != "" ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = []  # Add route table IDs as needed

  tags = merge(local.common_tags, {
    Name = "S3 VPC Endpoint"
  })
}

# VPC Endpoint for Lambda
resource "aws_vpc_endpoint" "lambda" {
  count = var.enable_vpc_endpoints && var.vpc_id != "" && length(var.subnet_ids) > 0 ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.lambda"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = []  # Add security group IDs as needed
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Lambda VPC Endpoint"
  })
}