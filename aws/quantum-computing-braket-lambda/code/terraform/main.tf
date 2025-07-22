# Main Terraform Configuration for Quantum Computing Pipeline
# This file contains the core infrastructure for the hybrid quantum-classical computing pipeline

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent naming and configuration
locals {
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "quantum-computing"
  })
}

# S3 Buckets for Quantum Computing Pipeline
# Input bucket for quantum problem data
resource "aws_s3_bucket" "input" {
  bucket        = "${local.resource_prefix}-input"
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-input"
    Type = "input-data"
  })
}

# Output bucket for quantum results
resource "aws_s3_bucket" "output" {
  bucket        = "${local.resource_prefix}-output"
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-output"
    Type = "output-results"
  })
}

# Code bucket for quantum algorithm storage
resource "aws_s3_bucket" "code" {
  bucket        = "${local.resource_prefix}-code"
  force_destroy = var.force_destroy_buckets

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-code"
    Type = "algorithm-code"
  })
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "code" {
  bucket = aws_s3_bucket.code.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket Encryption Configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "code" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.code.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
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

resource "aws_s3_bucket_public_access_block" "code" {
  bucket = aws_s3_bucket.code.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for Lambda Functions and Braket Execution
resource "aws_iam_role" "execution_role" {
  name = "${local.resource_prefix}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "braket.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-execution-role"
  })
}

# IAM Policy for Lambda Basic Execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.execution_role.name
}

# IAM Policy for Amazon Braket Full Access
resource "aws_iam_role_policy_attachment" "braket_full_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBraketFullAccess"
  role       = aws_iam_role.execution_role.name
}

# Custom IAM Policy for S3 and CloudWatch Access
resource "aws_iam_role_policy" "quantum_pipeline_policy" {
  name = "${local.resource_prefix}-quantum-pipeline-policy"
  role = aws_iam_role.execution_role.id

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
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*",
          aws_s3_bucket.code.arn,
          "${aws_s3_bucket.code.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.resource_prefix}-*"
        ]
      }
    ]
  })
}

# Lambda Function Source Code Archives
# Data Preparation Lambda
data "archive_file" "data_preparation" {
  type        = "zip"
  output_path = "${path.module}/data_preparation.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/data_preparation.py", {
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Job Submission Lambda
data "archive_file" "job_submission" {
  type        = "zip"
  output_path = "${path.module}/job_submission.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/job_submission.py", {
      project_name     = var.project_name
      execution_role_arn = aws_iam_role.execution_role.arn
      enable_braket_qpu = var.enable_braket_qpu
    })
    filename = "index.py"
  }
}

# Job Monitoring Lambda
data "archive_file" "job_monitoring" {
  type        = "zip"
  output_path = "${path.module}/job_monitoring.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/job_monitoring.py", {
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# Post Processing Lambda
data "archive_file" "post_processing" {
  type        = "zip"
  output_path = "${path.module}/post_processing.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/post_processing.py", {
      project_name = var.project_name
    })
    filename = "index.py"
  }
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "data_preparation" {
  name              = "/aws/lambda/${local.resource_prefix}-data-preparation"
  retention_in_days = var.cloudwatch_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-data-preparation-logs"
  })
}

resource "aws_cloudwatch_log_group" "job_submission" {
  name              = "/aws/lambda/${local.resource_prefix}-job-submission"
  retention_in_days = var.cloudwatch_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-job-submission-logs"
  })
}

resource "aws_cloudwatch_log_group" "job_monitoring" {
  name              = "/aws/lambda/${local.resource_prefix}-job-monitoring"
  retention_in_days = var.cloudwatch_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-job-monitoring-logs"
  })
}

resource "aws_cloudwatch_log_group" "post_processing" {
  name              = "/aws/lambda/${local.resource_prefix}-post-processing"
  retention_in_days = var.cloudwatch_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-post-processing-logs"
  })
}

# Lambda Functions for Quantum Computing Pipeline
# Data Preparation Lambda Function
resource "aws_lambda_function" "data_preparation" {
  filename         = data.archive_file.data_preparation.output_path
  function_name    = "${local.resource_prefix}-data-preparation"
  role            = aws_iam_role.execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 256
  source_code_hash = data.archive_file.data_preparation.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      AWS_REGION   = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.data_preparation
  ]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-data-preparation"
  })
}

# Job Submission Lambda Function
resource "aws_lambda_function" "job_submission" {
  filename         = data.archive_file.job_submission.output_path
  function_name    = "${local.resource_prefix}-job-submission"
  role            = aws_iam_role.execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.job_submission.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      EXECUTION_ROLE_ARN   = aws_iam_role.execution_role.arn
      ENABLE_BRAKET_QPU    = var.enable_braket_qpu
      BRAKET_DEVICE_TYPE   = var.braket_device_type
      OPTIMIZATION_ITERATIONS = var.optimization_iterations
      LEARNING_RATE        = var.learning_rate
      AWS_REGION           = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.braket_full_access,
    aws_cloudwatch_log_group.job_submission
  ]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-job-submission"
  })
}

# Job Monitoring Lambda Function
resource "aws_lambda_function" "job_monitoring" {
  filename         = data.archive_file.job_monitoring.output_path
  function_name    = "${local.resource_prefix}-job-monitoring"
  role            = aws_iam_role.execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = 256
  source_code_hash = data.archive_file.job_monitoring.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      AWS_REGION   = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.braket_full_access,
    aws_cloudwatch_log_group.job_monitoring
  ]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-job-monitoring"
  })
}

# Post Processing Lambda Function
resource "aws_lambda_function" "post_processing" {
  filename         = data.archive_file.post_processing.output_path
  function_name    = "${local.resource_prefix}-post-processing"
  role            = aws_iam_role.execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.quantum_algorithm_timeout
  memory_size     = 1024
  source_code_hash = data.archive_file.post_processing.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      AWS_REGION   = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.post_processing
  ]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-post-processing"
  })
}

# CloudWatch Dashboard for Quantum Pipeline Monitoring
resource "aws_cloudwatch_dashboard" "quantum_pipeline" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${local.resource_prefix}-quantum-pipeline"

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
            ["QuantumPipeline", "JobsSubmitted", "DeviceType", "simulator"],
            [".", ".", ".", "qpu"],
            [".", "ProblemsProcessed", "ProblemType", "optimization"],
            [".", ".", ".", "chemistry"]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "Quantum Pipeline Activity"
          period   = 300
          stat     = "Sum"
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
            ["QuantumPipeline", "OptimizationEfficiency"],
            [".", "FinalCost"],
            [".", "ConvergenceRate"]
          ]
          view     = "timeSeries"
          stacked  = false
          region   = data.aws_region.current.name
          title    = "Optimization Performance"
          period   = 300
          stat     = "Average"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query = join("\n", [
            "SOURCE '${aws_cloudwatch_log_group.data_preparation.name}'",
            "SOURCE '${aws_cloudwatch_log_group.job_submission.name}'",
            "SOURCE '${aws_cloudwatch_log_group.job_monitoring.name}'",
            "SOURCE '${aws_cloudwatch_log_group.post_processing.name}'",
            "fields @timestamp, @message",
            "filter @message like /quantum/",
            "sort @timestamp desc",
            "limit 100"
          ])
          region = data.aws_region.current.name
          title  = "Quantum Pipeline Logs"
          view   = "table"
        }
      }
    ]
  })
}

# CloudWatch Alarms for Monitoring
resource "aws_cloudwatch_metric_alarm" "job_failure_rate" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.resource_prefix}-job-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "JobStatusUpdate"
  namespace           = "QuantumPipeline"
  period              = "900"
  statistic           = "Sum"
  threshold           = var.alarm_threshold_job_failures
  alarm_description   = "This metric monitors quantum job failure rate"
  alarm_actions       = []

  dimensions = {
    JobStatus = "FAILED"
  }

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-job-failure-rate"
  })
}

resource "aws_cloudwatch_metric_alarm" "low_efficiency" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.resource_prefix}-low-efficiency"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "OptimizationEfficiency"
  namespace           = "QuantumPipeline"
  period              = "600"
  statistic           = "Average"
  threshold           = var.alarm_threshold_low_efficiency
  alarm_description   = "This metric monitors quantum optimization efficiency"
  alarm_actions       = []

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-low-efficiency"
  })
}

# S3 Object for Quantum Algorithm Code Upload
resource "aws_s3_object" "quantum_algorithm_code" {
  bucket = aws_s3_bucket.code.id
  key    = "quantum-code/quantum_optimization.py"
  
  content = templatefile("${path.module}/quantum_code/quantum_optimization.py", {
    project_name = var.project_name
  })
  
  content_type = "text/x-python"
  
  tags = merge(local.common_tags, {
    Name = "quantum-optimization-code"
  })
}

resource "aws_s3_object" "quantum_requirements" {
  bucket = aws_s3_bucket.code.id
  key    = "quantum-code/requirements.txt"
  
  content = file("${path.module}/quantum_code/requirements.txt")
  
  content_type = "text/plain"
  
  tags = merge(local.common_tags, {
    Name = "quantum-requirements"
  })
}