# Healthcare Data Processing Pipelines with AWS HealthLake
# This Terraform configuration creates a complete healthcare data processing pipeline
# using AWS HealthLake, Lambda, S3, and EventBridge for FHIR-compliant data management

terraform {
  required_version = ">= 1.0"
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix for uniqueness
  datastore_name    = "${var.project_name}-fhir-datastore-${random_id.suffix.hex}"
  input_bucket      = "${var.project_name}-input-${random_id.suffix.hex}"
  output_bucket     = "${var.project_name}-output-${random_id.suffix.hex}"
  lambda_processor  = "${var.project_name}-processor-${random_id.suffix.hex}"
  lambda_analytics  = "${var.project_name}-analytics-${random_id.suffix.hex}"
  iam_role_name     = "HealthLakeServiceRole-${random_id.suffix.hex}"
  lambda_role_name  = "LambdaExecutionRole-${random_id.suffix.hex}"

  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "healthcare-data-processing-pipelines-healthlake"
  })
}

# S3 bucket for input healthcare data
resource "aws_s3_bucket" "input" {
  bucket = local.input_bucket

  tags = merge(local.common_tags, {
    Name = "HealthLake Input Bucket"
    Type = "input"
  })
}

# S3 bucket versioning for input bucket
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for input bucket
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for output analytics and logs
resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket

  tags = merge(local.common_tags, {
    Name = "HealthLake Output Bucket"
    Type = "output"
  })
}

# S3 bucket versioning for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for output bucket
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample FHIR patient data for testing
resource "aws_s3_object" "sample_patient_data" {
  bucket = aws_s3_bucket.input.id
  key    = "fhir-data/patient-sample.json"
  content = jsonencode({
    resourceType = "Patient"
    id          = "patient-001"
    active      = true
    name = [{
      use    = "usual"
      family = "Doe"
      given  = ["John"]
    }]
    telecom = [{
      system = "phone"
      value  = "(555) 123-4567"
      use    = "home"
    }]
    gender    = "male"
    birthDate = "1985-03-15"
    address = [{
      use        = "home"
      line       = ["123 Main St"]
      city       = "Anytown"
      state      = "CA"
      postalCode = "12345"
    }]
  })
  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name = "Sample FHIR Patient Data"
  })
}

# IAM trust policy document for HealthLake service
data "aws_iam_policy_document" "healthlake_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["healthlake.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy document for HealthLake S3 access
data "aws_iam_policy_document" "healthlake_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.input.arn}/*",
      "${aws_s3_bucket.output.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.input.arn,
      aws_s3_bucket.output.arn
    ]
  }
}

# IAM role for HealthLake service
resource "aws_iam_role" "healthlake_service_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.healthlake_trust.json

  tags = merge(local.common_tags, {
    Name = "HealthLake Service Role"
  })
}

# IAM policy attachment for HealthLake S3 access
resource "aws_iam_role_policy" "healthlake_s3_access" {
  name   = "HealthLakeS3Access"
  role   = aws_iam_role.healthlake_service_role.id
  policy = data.aws_iam_policy_document.healthlake_s3_policy.json
}

# HealthLake FHIR data store
resource "aws_healthlake_fhir_datastore" "main" {
  datastore_name         = local.datastore_name
  datastore_type_version = "R4"

  # Preload SYNTHEA data for testing (optional)
  preload_data_config {
    preload_data_type = "SYNTHEA"
  }

  tags = merge(local.common_tags, {
    Name = "Healthcare FHIR Data Store"
  })
}

# IAM trust policy for Lambda execution
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy document for Lambda HealthLake access
data "aws_iam_policy_document" "lambda_healthlake_policy" {
  statement {
    effect = "Allow"
    actions = [
      "healthlake:DescribeFHIRDatastore",
      "healthlake:ReadResource",
      "healthlake:SearchWithGet",
      "healthlake:SearchWithPost"
    ]
    resources = [aws_healthlake_fhir_datastore.main.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.output.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json

  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom HealthLake policy to Lambda role
resource "aws_iam_role_policy" "lambda_healthlake_access" {
  name   = "LambdaHealthLakeAccess"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_healthlake_policy.json
}

# Archive Lambda processor function code
data "archive_file" "lambda_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-processor.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/processor.py", {
      datastore_endpoint = aws_healthlake_fhir_datastore.main.endpoint
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for HealthLake event processing
resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.lambda_processor_zip.output_path
  function_name    = local.lambda_processor
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_processor_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 256

  environment {
    variables = {
      DATASTORE_ENDPOINT = aws_healthlake_fhir_datastore.main.endpoint
      DATASTORE_ID      = aws_healthlake_fhir_datastore.main.datastore_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "HealthLake Event Processor"
  })

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

# Archive Lambda analytics function code
data "archive_file" "lambda_analytics_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-analytics.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/analytics.py", {
      output_bucket = aws_s3_bucket.output.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for healthcare analytics
resource "aws_lambda_function" "analytics" {
  filename         = data.archive_file.lambda_analytics_zip.output_path
  function_name    = local.lambda_analytics
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_analytics_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 256

  environment {
    variables = {
      OUTPUT_BUCKET     = aws_s3_bucket.output.id
      DATASTORE_ENDPOINT = aws_healthlake_fhir_datastore.main.endpoint
      DATASTORE_ID      = aws_healthlake_fhir_datastore.main.datastore_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "Healthcare Analytics Processor"
  })

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

# EventBridge rule for HealthLake processor events
resource "aws_cloudwatch_event_rule" "healthlake_processor" {
  name        = "HealthLakeProcessorRule"
  description = "Trigger Lambda processor for HealthLake events"

  event_pattern = jsonencode({
    source       = ["aws.healthlake"]
    detail-type = [
      "HealthLake Import Job State Change",
      "HealthLake Export Job State Change",
      "HealthLake Data Store State Change"
    ]
  })

  tags = merge(local.common_tags, {
    Name = "HealthLake Processor Rule"
  })
}

# EventBridge target for processor Lambda
resource "aws_cloudwatch_event_target" "lambda_processor" {
  rule      = aws_cloudwatch_event_rule.healthlake_processor.name
  target_id = "HealthLakeProcessorTarget"
  arn       = aws_lambda_function.processor.arn
}

# EventBridge rule for HealthLake analytics trigger
resource "aws_cloudwatch_event_rule" "healthlake_analytics" {
  name        = "HealthLakeAnalyticsRule"
  description = "Trigger Lambda analytics for completed import jobs"

  event_pattern = jsonencode({
    source       = ["aws.healthlake"]
    detail-type  = ["HealthLake Import Job State Change"]
    detail = {
      jobStatus = ["COMPLETED"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "HealthLake Analytics Rule"
  })
}

# EventBridge target for analytics Lambda
resource "aws_cloudwatch_event_target" "lambda_analytics" {
  rule      = aws_cloudwatch_event_rule.healthlake_analytics.name
  target_id = "HealthLakeAnalyticsTarget"
  arn       = aws_lambda_function.analytics.arn
}

# Lambda permission for EventBridge to invoke processor function
resource "aws_lambda_permission" "allow_eventbridge_processor" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.healthlake_processor.arn
}

# Lambda permission for EventBridge to invoke analytics function
resource "aws_lambda_permission" "allow_eventbridge_analytics" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.healthlake_analytics.arn
}

# CloudWatch Log Group for processor Lambda
resource "aws_cloudwatch_log_group" "lambda_processor_logs" {
  name              = "/aws/lambda/${aws_lambda_function.processor.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "HealthLake Processor Logs"
  })
}

# CloudWatch Log Group for analytics Lambda
resource "aws_cloudwatch_log_group" "lambda_analytics_logs" {
  name              = "/aws/lambda/${aws_lambda_function.analytics.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "Healthcare Analytics Logs"
  })
}