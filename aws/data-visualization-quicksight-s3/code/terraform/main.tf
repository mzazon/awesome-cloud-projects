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
  random_suffix = random_id.suffix.hex
  
  # S3 bucket names (must be globally unique)
  raw_bucket_name = "${local.name_prefix}-raw-data-${local.random_suffix}"
  processed_bucket_name = "${local.name_prefix}-processed-data-${local.random_suffix}"
  athena_results_bucket_name = "${local.name_prefix}-athena-results-${local.random_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "data-visualization-pipelines-quicksight-s3"
  }
}

# =============================================================================
# KMS Key for Encryption (if enabled)
# =============================================================================

resource "aws_kms_key" "main" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for ${var.project_name} data visualization pipeline"
  deletion_window_in_days = 7
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
        Sid    = "Allow Glue Service"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Athena Service"
        Effect = "Allow"
        Principal = {
          Service = "athena.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-key"
  target_key_id = aws_kms_key.main[0].key_id
}

# =============================================================================
# S3 Buckets
# =============================================================================

# Raw data bucket
resource "aws_s3_bucket" "raw_data" {
  bucket = local.raw_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-raw-data"
    Purpose = "Store raw data files for processing"
  })
}

# Processed data bucket
resource "aws_s3_bucket" "processed_data" {
  bucket = local.processed_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processed-data"
    Purpose = "Store processed and transformed data"
  })
}

# Athena query results bucket
resource "aws_s3_bucket" "athena_results" {
  bucket = local.athena_results_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-athena-results"
    Purpose = "Store Athena query results"
  })
}

# S3 bucket configurations
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  count = var.s3_lifecycle_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.raw_data.id
  
  rule {
    id     = "lifecycle_rule"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = var.s3_lifecycle_expiration_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "processed_data" {
  count = var.s3_lifecycle_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.processed_data.id
  
  rule {
    id     = "lifecycle_rule"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = var.s3_lifecycle_expiration_days
    }
  }
}

# S3 Intelligent Tiering (if enabled)
resource "aws_s3_bucket_intelligent_tiering_configuration" "raw_data" {
  count = var.enable_intelligent_tiering ? 1 : 0
  
  bucket = aws_s3_bucket.raw_data.id
  name   = "intelligent_tiering"
  status = "Enabled"
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "processed_data" {
  count = var.enable_intelligent_tiering ? 1 : 0
  
  bucket = aws_s3_bucket.processed_data.id
  name   = "intelligent_tiering"
  status = "Enabled"
}

# Block public access for all buckets
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Sample Data Upload (if enabled)
# =============================================================================

resource "aws_s3_object" "sample_data" {
  for_each = var.upload_sample_data ? var.sample_data_files : {}
  
  bucket  = aws_s3_bucket.raw_data.id
  key     = each.value.key
  content = each.value.content
  
  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name = "sample-data-${each.key}"
    Type = "SampleData"
  })
}

# =============================================================================
# IAM Roles and Policies
# =============================================================================

# Glue service role
resource "aws_iam_role" "glue_role" {
  name = "${local.name_prefix}-glue-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach AWS managed Glue service role policy
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom S3 access policy for Glue
resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${local.name_prefix}-glue-s3-policy"
  role = aws_iam_role.glue_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.main[0].arn] : []
      }
    ]
  })
}

# Lambda execution role
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

# Attach AWS managed Lambda basic execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom Lambda policy for Glue operations
resource "aws_iam_role_policy" "lambda_glue_policy" {
  name = "${local.name_prefix}-lambda-glue-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartCrawler",
          "glue:GetCrawler",
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# Glue Data Catalog
# =============================================================================

# Glue database
resource "aws_glue_catalog_database" "main" {
  name        = "${local.name_prefix}-database"
  description = "Database for data visualization pipeline"
  
  tags = local.common_tags
}

# Glue crawler for raw data
resource "aws_glue_crawler" "raw_data" {
  database_name = aws_glue_catalog_database.main.name
  name          = "${local.name_prefix}-raw-crawler"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler for raw sales data"
  
  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.bucket}/sales-data/"
  }
  
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
  
  # Optional: Schedule the crawler
  schedule = var.glue_crawler_schedule
  
  tags = local.common_tags
}

# Glue crawler for processed data
resource "aws_glue_crawler" "processed_data" {
  database_name = aws_glue_catalog_database.main.name
  name          = "${local.name_prefix}-processed-crawler"
  role          = aws_iam_role.glue_role.arn
  description   = "Crawler for processed data"
  
  s3_target {
    path = "s3://${aws_s3_bucket.processed_data.bucket}/"
  }
  
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
  
  tags = local.common_tags
}

# =============================================================================
# Glue ETL Job
# =============================================================================

# ETL script stored in S3
resource "aws_s3_object" "etl_script" {
  bucket = aws_s3_bucket.processed_data.id
  key    = "scripts/sales-etl.py"
  
  content = templatefile("${path.module}/etl-script.py", {
    source_database = aws_glue_catalog_database.main.name
    target_bucket   = aws_s3_bucket.processed_data.bucket
  })
  
  content_type = "text/plain"
  
  tags = merge(local.common_tags, {
    Name = "glue-etl-script"
    Type = "ETLScript"
  })
}

# Glue ETL Job
resource "aws_glue_job" "etl_job" {
  name         = "${local.name_prefix}-etl-job"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = var.glue_version
  max_retries  = var.glue_job_max_retries
  timeout      = var.glue_job_timeout
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.processed_data.bucket}/${aws_s3_object.etl_script.key}"
    python_version  = "3"
  }
  
  default_arguments = {
    "--SOURCE_DATABASE"                     = aws_glue_catalog_database.main.name
    "--TARGET_BUCKET"                       = aws_s3_bucket.processed_data.bucket
    "--enable-metrics"                      = ""
    "--enable-continuous-cloudwatch-log"   = "true"
    "--job-language"                        = "python"
  }
  
  execution_property {
    max_concurrent_runs = 1
  }
  
  tags = local.common_tags
}

# =============================================================================
# Athena Configuration
# =============================================================================

# Athena workgroup
resource "aws_athena_workgroup" "main" {
  name        = "${local.name_prefix}-workgroup"
  description = "Workgroup for data visualization pipeline"
  
  configuration {
    enforce_workgroup_configuration    = var.athena_workgroup_force_configuration
    publish_cloudwatch_metrics_enabled = true
    
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
      
      dynamic "encryption_configuration" {
        for_each = var.athena_query_result_encryption ? [1] : []
        content {
          encryption_option = var.enable_kms_encryption ? "SSE_KMS" : "SSE_S3"
          kms_key           = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
        }
      }
    }
    
    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_cutoff
  }
  
  tags = local.common_tags
}

# =============================================================================
# Lambda Function for Automation
# =============================================================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-automation.zip"
  
  source {
    content = templatefile("${path.module}/lambda-function.js", {
      project_name = local.name_prefix
    })
    filename = "index.js"
  }
}

# Lambda function for pipeline automation
resource "aws_lambda_function" "automation" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-automation"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      PROJECT_NAME = local.name_prefix
      GLUE_DATABASE = aws_glue_catalog_database.main.name
    }
  }
  
  tags = local.common_tags
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.automation.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_data.arn
}

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "raw_data_notification" {
  bucket = aws_s3_bucket.raw_data.id
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.automation.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "sales-data/"
  }
  
  depends_on = [aws_lambda_permission.s3_invoke]
}

# =============================================================================
# CloudWatch Monitoring (if enabled)
# =============================================================================

# SNS topic for notifications (if email is provided)
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  
  name = "${local.name_prefix}-notifications"
  
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarms (if enabled)
resource "aws_cloudwatch_metric_alarm" "glue_job_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-glue-job-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Glue job failures"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    JobName = aws_glue_job.etl_job.name
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []
  
  dimensions = {
    FunctionName = aws_lambda_function.automation.function_name
  }
  
  tags = local.common_tags
}