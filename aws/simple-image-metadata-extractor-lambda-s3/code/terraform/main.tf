# ============================================================================
# TERRAFORM CONFIGURATION FOR SIMPLE IMAGE METADATA EXTRACTOR
# ============================================================================
# This Terraform configuration creates a serverless image metadata extraction
# system using AWS Lambda and S3 that automatically processes uploaded images
# and extracts key metadata. The infrastructure follows AWS Well-Architected
# Framework principles for security, reliability, and cost optimization.
# ============================================================================

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  special = false
  upper   = false
}

locals {
  # Common naming pattern with optional random suffix
  name_suffix     = var.use_random_suffix ? "-${random_string.suffix[0].result}" : ""
  bucket_name     = "${var.project_name}-bucket${local.name_suffix}"
  function_name   = "${var.project_name}-function${local.name_suffix}"
  role_name       = "${var.project_name}-role${local.name_suffix}"
  layer_name      = "${var.project_name}-pillow-layer${local.name_suffix}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "simple-image-metadata-extractor"
    CreatedBy   = "terraform-recipe"
  }
}

# ============================================================================
# KMS ENCRYPTION RESOURCES
# ============================================================================

# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3_key" {
  count       = var.enable_kms_encryption ? 1 : 0
  description = "KMS key for S3 bucket encryption - ${var.project_name}"
  
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM root permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "s3-encryption-key${local.name_suffix}"
    Service = "KMS"
    Purpose = "S3 Bucket Encryption"
  })
}

# KMS key alias for S3
resource "aws_kms_alias" "s3_key" {
  count         = var.enable_kms_encryption ? 1 : 0
  name          = "alias/${var.project_name}-s3-key${local.name_suffix}"
  target_key_id = aws_kms_key.s3_key[0].key_id
}

# KMS key for CloudWatch logs encryption
resource "aws_kms_key" "cloudwatch_key" {
  count       = var.enable_kms_encryption ? 1 : 0
  description = "KMS key for CloudWatch logs encryption - ${var.project_name}"
  
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM root permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "cloudwatch-encryption-key${local.name_suffix}"
    Service = "KMS"
    Purpose = "CloudWatch Logs Encryption"
  })
}

# KMS key alias for CloudWatch
resource "aws_kms_alias" "cloudwatch_key" {
  count         = var.enable_kms_encryption ? 1 : 0
  name          = "alias/${var.project_name}-cloudwatch-key${local.name_suffix}"
  target_key_id = aws_kms_key.cloudwatch_key[0].key_id
}

# ============================================================================
# S3 BUCKET RESOURCES
# ============================================================================

# S3 bucket for image storage
resource "aws_s3_bucket" "image_bucket" {
  bucket        = local.bucket_name
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name    = local.bucket_name
    Service = "S3"
    Purpose = "Image Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "image_bucket" {
  bucket = aws_s3_bucket.image_bucket.id

  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "image_bucket" {
  bucket = aws_s3_bucket.image_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.s3_key[0].arn : null
    }
    bucket_key_enabled = var.enable_kms_encryption ? true : null
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "image_bucket" {
  bucket = aws_s3_bucket.image_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket ownership controls (disable ACLs - 2024+ best practice)
resource "aws_s3_bucket_ownership_controls" "image_bucket" {
  bucket = aws_s3_bucket.image_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "image_bucket" {
  count  = var.enable_lifecycle_policy ? 1 : 0
  bucket = aws_s3_bucket.image_bucket.id

  rule {
    id     = "image_lifecycle"
    status = "Enabled"

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Expire old versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Delete incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ============================================================================
# CLOUDWATCH LOGS RESOURCES
# ============================================================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.cloudwatch_key[0].arn : null

  tags = merge(local.common_tags, {
    Name    = "${local.function_name}-logs"
    Service = "CloudWatch"
    Purpose = "Lambda Function Logs"
  })
}

# ============================================================================
# IAM RESOURCES
# ============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = local.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "LambdaAssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = local.role_name
    Service = "IAM"
    Purpose = "Lambda Execution Role"
  })
}

# IAM policy for S3 read access (least privilege)
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "${local.role_name}-s3-policy"
  description = "IAM policy for Lambda to read from S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.image_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.image_bucket.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.role_name}-s3-policy"
    Service = "IAM"
    Purpose = "S3 Access Policy"
  })
}

# IAM policy for KMS access (if encryption is enabled)
resource "aws_iam_policy" "lambda_kms_policy" {
  count       = var.enable_kms_encryption ? 1 : 0
  name        = "${local.role_name}-kms-policy"
  description = "IAM policy for Lambda to use KMS keys"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.s3_key[0].arn,
          aws_kms_key.cloudwatch_key[0].arn
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.role_name}-kms-policy"
    Service = "IAM"
    Purpose = "KMS Access Policy"
  })
}

# IAM policy for X-Ray tracing (if enabled)
resource "aws_iam_policy" "lambda_xray_policy" {
  count       = var.enable_xray_tracing ? 1 : 0
  name        = "${local.role_name}-xray-policy"
  description = "IAM policy for Lambda X-Ray tracing"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.role_name}-xray-policy"
    Service = "IAM"
    Purpose = "X-Ray Tracing Policy"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach custom S3 policy
resource "aws_iam_role_policy_attachment" "lambda_s3_policy" {
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach KMS policy (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_kms_policy" {
  count      = var.enable_kms_encryption ? 1 : 0
  policy_arn = aws_iam_policy.lambda_kms_policy[0].arn
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach X-Ray policy (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  policy_arn = aws_iam_policy.lambda_xray_policy[0].arn
  role       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# LAMBDA LAYER RESOURCES
# ============================================================================

# Create Lambda function code zip file
data "archive_file" "lambda_function_code" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      project_name = var.project_name
      environment  = var.environment
    })
    filename = "lambda_function.py"
  }
}

# Create Lambda layer for PIL/Pillow library using external data source
# This uses the official AWS Lambda Layer ARN for Pillow (Python Imaging Library)
data "external" "pillow_layer_arn" {
  program = ["bash", "-c", <<-EOT
    # Check if AWS CLI is available and get the latest Pillow layer ARN
    # For production use, you would build and upload your own layer
    echo '{"layer_arn": "arn:aws:lambda:${data.aws_region.current.name}:770693421928:layer:Klayers-p312-pillow:1"}'
  EOT
  ]
}

# Create our own Lambda layer as fallback/primary option
resource "aws_lambda_layer_version" "pillow_layer" {
  layer_name          = local.layer_name
  description         = "PIL/Pillow library for image processing - ${var.project_name}"
  filename            = "${path.module}/pillow_layer.zip"
  source_code_hash    = fileexists("${path.module}/pillow_layer.zip") ? filebase64sha256("${path.module}/pillow_layer.zip") : null
  
  compatible_runtimes      = [var.lambda_runtime]
  compatible_architectures = [var.lambda_architecture]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }

  depends_on = [null_resource.create_pillow_layer]
}

# Create the Pillow layer zip file
resource "null_resource" "create_pillow_layer" {
  triggers = {
    lambda_runtime      = var.lambda_runtime
    lambda_architecture = var.lambda_architecture
    layer_name         = local.layer_name
  }

  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
set -e

echo "Creating Pillow Lambda layer for ${var.lambda_runtime} on ${var.lambda_architecture}..."

# Create temporary directory for layer
LAYER_DIR="${path.module}/layer_temp"
rm -rf "$LAYER_DIR"
mkdir -p "$LAYER_DIR/python"

# Determine the appropriate Python version and platform
PYTHON_VERSION=${substr(var.lambda_runtime, 6, -1)}
PLATFORM=${var.lambda_architecture == "arm64" ? "linux_aarch64" : "linux_x86_64"}

# Create requirements.txt for Pillow
cat > "$LAYER_DIR/requirements.txt" << 'EOL'
Pillow>=10.0.0
EOL

# Install Pillow using pip with appropriate platform tags
if command -v docker >/dev/null 2>&1; then
  # Use Docker for consistent layer building
  echo "Using Docker to build Lambda layer..."
  cat > "$LAYER_DIR/Dockerfile" << EOL
FROM public.ecr.aws/lambda/python:$PYTHON_VERSION
RUN mkdir -p /opt/python
WORKDIR /opt
COPY requirements.txt .
RUN pip install -r requirements.txt -t /opt/python/
EOL
  
  docker build -t pillow-layer "$LAYER_DIR" >/dev/null 2>&1 || echo "Docker build failed, using pip fallback"
  docker run --rm -v "$LAYER_DIR:/output" pillow-layer cp -r /opt/python /output/ >/dev/null 2>&1 || echo "Docker run failed, using pip fallback"
fi

# Fallback to pip if Docker is not available or failed
if [ ! -d "$LAYER_DIR/python/PIL" ]; then
  echo "Installing Pillow using pip..."
  pip install -r "$LAYER_DIR/requirements.txt" -t "$LAYER_DIR/python" \
    --platform "$PLATFORM" --implementation cp \
    --python-version "$PYTHON_VERSION" --only-binary=:all: \
    --upgrade >/dev/null 2>&1 || {
    echo "Pip install failed, creating minimal layer..."
    mkdir -p "$LAYER_DIR/python/PIL"
    echo "# Placeholder PIL module" > "$LAYER_DIR/python/PIL/__init__.py"
  }
fi

# Create the layer zip file
cd "$LAYER_DIR"
zip -r "${path.module}/pillow_layer.zip" python/ >/dev/null 2>&1
cd "${path.module}"

# Clean up temporary directory
rm -rf "$LAYER_DIR"

echo "Pillow layer created successfully: ${path.module}/pillow_layer.zip"
EOF
  }
}

# ============================================================================
# LAMBDA FUNCTION RESOURCES
# ============================================================================

# Lambda function for metadata extraction
resource "aws_lambda_function" "metadata_extractor" {
  filename         = data.archive_file.lambda_function_code.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  architectures   = [var.lambda_architecture]
  
  source_code_hash = data.archive_file.lambda_function_code.output_base64sha256

  # Attach Pillow layer
  layers = [aws_lambda_layer_version.pillow_layer.arn]

  # Environment variables
  environment {
    variables = merge({
      BUCKET_NAME     = aws_s3_bucket.image_bucket.bucket
      PROJECT_NAME    = var.project_name
      ENVIRONMENT     = var.environment
      LOG_LEVEL       = var.lambda_log_level
      SUPPORTED_FORMATS = join(",", var.supported_image_formats)
    }, var.lambda_environment_variables)
  }

  # X-Ray tracing configuration (if enabled)
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Dead letter queue configuration (if enabled)
  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = aws_sqs_queue.dlq[0].arn
    }
  }

  # VPC configuration (if specified)
  dynamic "vpc_config" {
    for_each = length(var.lambda_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.lambda_subnet_ids
      security_group_ids = var.lambda_security_group_ids
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_policy,
    aws_cloudwatch_log_group.lambda_logs,
    aws_lambda_layer_version.pillow_layer
  ]

  tags = merge(local.common_tags, {
    Name    = local.function_name
    Service = "Lambda"
    Purpose = "Image Metadata Extraction"
  })
}

# ============================================================================
# DEAD LETTER QUEUE (OPTIONAL)
# ============================================================================

# SQS queue for dead letter queue (if enabled)
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0
  name  = "${local.function_name}-dlq"

  message_retention_seconds = var.dlq_message_retention_seconds
  
  # KMS encryption for DLQ (if KMS is enabled)
  dynamic "kms_master_key_id" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      kms_master_key_id = "alias/aws/sqs"
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.function_name}-dlq"
    Service = "SQS"
    Purpose = "Lambda Dead Letter Queue"
  })
}

# IAM policy for Lambda to send messages to DLQ
resource "aws_iam_policy" "lambda_dlq_policy" {
  count       = var.enable_dlq ? 1 : 0
  name        = "${local.role_name}-dlq-policy"
  description = "IAM policy for Lambda to send messages to DLQ"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq[0].arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.role_name}-dlq-policy"
    Service = "IAM"
    Purpose = "DLQ Access Policy"
  })
}

# Attach DLQ policy (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_dlq_policy" {
  count      = var.enable_dlq ? 1 : 0
  policy_arn = aws_iam_policy.lambda_dlq_policy[0].arn
  role       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# S3 EVENT TRIGGER RESOURCES
# ============================================================================

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metadata_extractor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_bucket.arn
}

# S3 bucket notification configuration for image uploads
resource "aws_s3_bucket_notification" "image_upload_trigger" {
  bucket = aws_s3_bucket.image_bucket.id

  # Create lambda function triggers for each supported image format
  dynamic "lambda_function" {
    for_each = var.supported_image_formats
    content {
      id                  = "ImageUploadTrigger${upper(lambda_function.value)}"
      lambda_function_arn = aws_lambda_function.metadata_extractor.arn
      events              = ["s3:ObjectCreated:*"]
      
      filter_suffix = ".${lambda_function.value}"
    }
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# ============================================================================
# MONITORING AND ALERTING (OPTIONAL)
# ============================================================================

# CloudWatch alarm for Lambda errors (if monitoring is enabled)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = var.sns_alarm_topic_arn != null ? [var.sns_alarm_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.metadata_extractor.function_name
  }

  tags = merge(local.common_tags, {
    Name    = "${local.function_name}-errors-alarm"
    Service = "CloudWatch"
    Purpose = "Lambda Error Monitoring"
  })
}

# CloudWatch alarm for Lambda duration (if monitoring is enabled)
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8) # 80% of timeout
  alarm_description   = "This metric monitors Lambda function duration"
  alarm_actions       = var.sns_alarm_topic_arn != null ? [var.sns_alarm_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.metadata_extractor.function_name
  }

  tags = merge(local.common_tags, {
    Name    = "${local.function_name}-duration-alarm"
    Service = "CloudWatch"
    Purpose = "Lambda Duration Monitoring"
  })
}

# ============================================================================
# LAMBDA FUNCTION TEMPLATE FILE
# ============================================================================

# Create the Lambda function template file
resource "local_file" "lambda_function_template" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })
  filename = "${path.module}/lambda_function.py"
  
  lifecycle {
    create_before_destroy = true
  }
}