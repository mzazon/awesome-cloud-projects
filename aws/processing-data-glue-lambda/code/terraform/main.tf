# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # Resource names with random suffix for uniqueness
  bucket_name = "${var.s3_bucket_prefix}-${local.random_suffix}"
  glue_database_name = "${var.glue_database_name}_${local.random_suffix}"
  glue_job_name = "${var.glue_job_name}_${local.random_suffix}"
  glue_crawler_name = "${var.glue_crawler_name}_${local.random_suffix}"
  glue_workflow_name = "${var.glue_workflow_name}_${local.random_suffix}"
  lambda_function_name = "${var.lambda_function_name}-${local.random_suffix}"
  
  # Merged tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ==============================================================================
# S3 BUCKET AND CONFIGURATION
# ==============================================================================

# S3 bucket for ETL pipeline data storage
resource "aws_s3_bucket" "etl_bucket" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "ETL data storage"
    Component   = "Storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "etl_bucket_versioning" {
  bucket = aws_s3_bucket.etl_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "etl_bucket_encryption" {
  bucket = aws_s3_bucket.etl_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "etl_bucket_pab" {
  bucket = aws_s3_bucket.etl_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "etl_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.etl_bucket.id

  rule {
    id     = "etl_data_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access
    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier
    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Delete incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket folders
resource "aws_s3_object" "raw_data_folder" {
  bucket = aws_s3_bucket.etl_bucket.id
  key    = "raw-data/"
  tags   = local.common_tags
}

resource "aws_s3_object" "processed_data_folder" {
  bucket = aws_s3_bucket.etl_bucket.id
  key    = "processed-data/"
  tags   = local.common_tags
}

resource "aws_s3_object" "scripts_folder" {
  bucket = aws_s3_bucket.etl_bucket.id
  key    = "scripts/"
  tags   = local.common_tags
}

resource "aws_s3_object" "temp_folder" {
  bucket = aws_s3_bucket.etl_bucket.id
  key    = "temp/"
  tags   = local.common_tags
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# AWS Glue Service Role
resource "aws_iam_role" "glue_service_role" {
  name = "${local.name_prefix}-glue-role-${local.random_suffix}"

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

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-glue-role-${local.random_suffix}"
    Purpose   = "AWS Glue service role"
    Component = "IAM"
  })
}

# Attach AWS managed Glue service role policy
resource "aws_iam_role_policy_attachment" "glue_service_role_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for Glue S3 access
resource "aws_iam_policy" "glue_s3_access_policy" {
  name        = "${local.name_prefix}-glue-s3-policy-${local.random_suffix}"
  description = "Policy for Glue to access S3 bucket"

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
          aws_s3_bucket.etl_bucket.arn,
          "${aws_s3_bucket.etl_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom S3 policy to Glue role
resource "aws_iam_role_policy_attachment" "glue_s3_access_attachment" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = aws_iam_policy.glue_s3_access_policy.arn
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.random_suffix}"

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
    Name      = "${local.name_prefix}-lambda-role-${local.random_suffix}"
    Purpose   = "Lambda execution role"
    Component = "IAM"
  })
}

# Attach AWS managed Lambda basic execution role policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda to interact with Glue
resource "aws_iam_policy" "lambda_glue_access_policy" {
  name        = "${local.name_prefix}-lambda-glue-policy-${local.random_suffix}"
  description = "Policy for Lambda to interact with Glue services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:StartCrawler",
          "glue:GetCrawler",
          "glue:StartWorkflowRun",
          "glue:GetWorkflowRun"
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
          aws_s3_bucket.etl_bucket.arn,
          "${aws_s3_bucket.etl_bucket.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom Glue policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_glue_access_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_glue_access_policy.arn
}

# ==============================================================================
# AWS GLUE RESOURCES
# ==============================================================================

# Glue database
resource "aws_glue_catalog_database" "etl_database" {
  name        = local.glue_database_name
  description = "Database for ETL pipeline catalog"

  tags = merge(local.common_tags, {
    Name      = local.glue_database_name
    Purpose   = "Data catalog"
    Component = "Glue"
  })
}

# Glue crawler
resource "aws_glue_crawler" "etl_crawler" {
  name          = local.glue_crawler_name
  database_name = aws_glue_catalog_database.etl_database.name
  role          = aws_iam_role.glue_service_role.arn
  description   = "Crawler for discovering raw data schema"

  s3_target {
    path = "s3://${aws_s3_bucket.etl_bucket.bucket}/raw-data/"
  }

  # Optional: Schedule the crawler
  schedule = var.crawler_schedule

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name      = local.glue_crawler_name
    Purpose   = "Schema discovery"
    Component = "Glue"
  })
}

# Glue ETL script content
locals {
  glue_script_content = file("${path.module}/scripts/glue_etl_script.py")
}

# Upload Glue ETL script to S3
resource "aws_s3_object" "glue_etl_script" {
  bucket  = aws_s3_bucket.etl_bucket.id
  key     = "scripts/glue_etl_script.py"
  content = local.glue_script_content
  
  tags = merge(local.common_tags, {
    Name      = "glue_etl_script.py"
    Purpose   = "ETL transformation logic"
    Component = "Glue"
  })
}

# Glue ETL job
resource "aws_glue_job" "etl_job" {
  name         = local.glue_job_name
  description  = "ETL job for processing sales and customer data"
  role_arn     = aws_iam_role.glue_service_role.arn
  glue_version = var.glue_job_glue_version
  max_retries  = var.glue_job_max_retries
  timeout      = var.glue_job_timeout

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.etl_bucket.bucket}/scripts/glue_etl_script.py"
    python_version  = "3"
  }

  worker_type       = var.glue_job_worker_type
  number_of_workers = var.glue_job_number_of_workers

  default_arguments = {
    "--database_name"                        = aws_glue_catalog_database.etl_database.name
    "--table_prefix"                         = "raw_data"
    "--output_path"                          = "s3://${aws_s3_bucket.etl_bucket.bucket}/processed-data"
    "--TempDir"                              = "s3://${aws_s3_bucket.etl_bucket.bucket}/temp/"
    "--enable-metrics"                       = ""
    "--enable-continuous-cloudwatch-log"    = var.enable_cloudwatch_logs ? "true" : "false"
    "--job-language"                         = "python"
    "--enable-glue-datacatalog"              = ""
    "--enable-spark-ui"                      = "true"
    "--spark-event-logs-path"                = "s3://${aws_s3_bucket.etl_bucket.bucket}/spark-logs/"
  }

  tags = merge(local.common_tags, {
    Name      = local.glue_job_name
    Purpose   = "Data transformation"
    Component = "Glue"
  })

  depends_on = [
    aws_s3_object.glue_etl_script,
    aws_iam_role_policy_attachment.glue_service_role_policy,
    aws_iam_role_policy_attachment.glue_s3_access_attachment
  ]
}

# ==============================================================================
# LAMBDA FUNCTION
# ==============================================================================

# Lambda function code
locals {
  lambda_function_code = file("${path.module}/scripts/lambda_function.py")
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local.lambda_function_code
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "etl_orchestrator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  description      = "ETL pipeline orchestrator function"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      GLUE_JOB_NAME     = aws_glue_job.etl_job.name
      GLUE_DATABASE     = aws_glue_catalog_database.etl_database.name
      S3_BUCKET         = aws_s3_bucket.etl_bucket.bucket
      OUTPUT_PATH       = "s3://${aws_s3_bucket.etl_bucket.bucket}/processed-data"
    }
  }

  tags = merge(local.common_tags, {
    Name      = local.lambda_function_name
    Purpose   = "ETL orchestration"
    Component = "Lambda"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_glue_access_attachment
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.etl_orchestrator.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${aws_lambda_function.etl_orchestrator.function_name}"
    Purpose   = "Lambda function logs"
    Component = "CloudWatch"
  })
}

# ==============================================================================
# S3 EVENT NOTIFICATIONS
# ==============================================================================

# Lambda permission for S3 to invoke function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  count         = var.enable_s3_notifications ? 1 : 0
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_orchestrator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.etl_bucket.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "etl_bucket_notification" {
  count  = var.enable_s3_notifications ? 1 : 0
  bucket = aws_s3_bucket.etl_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_orchestrator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.s3_notification_prefix
    filter_suffix       = var.s3_notification_suffix
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# ==============================================================================
# GLUE WORKFLOW
# ==============================================================================

# Glue workflow
resource "aws_glue_workflow" "etl_workflow" {
  name        = local.glue_workflow_name
  description = "Serverless ETL Pipeline Workflow"

  tags = merge(local.common_tags, {
    Name      = local.glue_workflow_name
    Purpose   = "ETL orchestration"
    Component = "Glue"
  })
}

# Glue trigger for scheduled execution
resource "aws_glue_trigger" "scheduled_trigger" {
  count         = var.enable_workflow_trigger ? 1 : 0
  name          = "start-etl-trigger-${local.random_suffix}"
  description   = "Scheduled trigger for ETL workflow"
  type          = "SCHEDULED"
  schedule      = var.workflow_schedule
  workflow_name = aws_glue_workflow.etl_workflow.name

  actions {
    job_name = aws_glue_job.etl_job.name
  }

  tags = merge(local.common_tags, {
    Name      = "start-etl-trigger-${local.random_suffix}"
    Purpose   = "Scheduled ETL execution"
    Component = "Glue"
  })
}

# ==============================================================================
# SAMPLE DATA UPLOAD
# ==============================================================================

# Sample sales data
resource "aws_s3_object" "sample_sales_data" {
  bucket  = aws_s3_bucket.etl_bucket.id
  key     = "raw-data/sales_data.csv"
  content = <<EOF
order_id,customer_id,product_id,quantity,price,order_date,region
1001,C001,P001,2,29.99,2024-01-15,North
1002,C002,P002,1,49.99,2024-01-15,South
1003,C003,P001,3,29.99,2024-01-16,East
1004,C001,P003,1,19.99,2024-01-16,North
1005,C004,P002,2,49.99,2024-01-17,West
1006,C005,P001,1,29.99,2024-01-17,South
1007,C002,P003,4,19.99,2024-01-18,East
1008,C006,P004,1,99.99,2024-01-18,North
1009,C003,P004,2,99.99,2024-01-19,West
1010,C007,P002,1,49.99,2024-01-19,South
EOF

  tags = merge(local.common_tags, {
    Name      = "sales_data.csv"
    Purpose   = "Sample data for testing"
    Component = "Data"
  })
}

# Sample customer data
resource "aws_s3_object" "sample_customer_data" {
  bucket  = aws_s3_bucket.etl_bucket.id
  key     = "raw-data/customer_data.csv"
  content = <<EOF
customer_id,name,email,registration_date,status
C001,John Smith,john@example.com,2023-01-01,active
C002,Jane Doe,jane@example.com,2023-02-15,active
C003,Bob Johnson,bob@example.com,2023-03-20,inactive
C004,Alice Wilson,alice@example.com,2023-04-10,active
C005,Charlie Brown,charlie@example.com,2023-05-05,active
C006,Diana Prince,diana@example.com,2023-06-12,active
C007,Eve Adams,eve@example.com,2023-07-22,active
EOF

  tags = merge(local.common_tags, {
    Name      = "customer_data.csv"
    Purpose   = "Sample data for testing"
    Component = "Data"
  })
}

# ==============================================================================
# CLOUDWATCH MONITORING
# ==============================================================================

# CloudWatch Log Group for Glue jobs
resource "aws_cloudwatch_log_group" "glue_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws-glue/jobs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws-glue/jobs"
    Purpose   = "Glue job logs"
    Component = "CloudWatch"
  })
}