# ========================================
# Amazon Polly Text-to-Speech Infrastructure
# ========================================
# This configuration creates the complete infrastructure for building
# text-to-speech applications using Amazon Polly, including S3 storage
# for audio output, IAM roles for secure access, and supporting resources.

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Amazon-Polly-TTS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "text-to-speech-applications-amazon-polly"
    }
  }
}

# ========================================
# Data Sources
# ========================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ========================================
# Random Resources for Unique Naming
# ========================================

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ========================================
# S3 Bucket for Audio Output Storage
# ========================================

# Primary S3 bucket for storing synthesized audio files
resource "aws_s3_bucket" "polly_audio_output" {
  bucket = "${var.bucket_name_prefix}-${random_string.suffix.result}"

  tags = {
    Name        = "Polly Audio Output Bucket"
    Purpose     = "Storage for Amazon Polly synthesized audio files"
    DataType    = "Audio"
    Retention   = "30-days"
  }
}

# Configure S3 bucket versioning for audio file management
resource "aws_s3_bucket_versioning" "polly_audio_versioning" {
  bucket = aws_s3_bucket.polly_audio_output.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Server-side encryption for audio files at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "polly_audio_encryption" {
  bucket = aws_s3_bucket.polly_audio_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to audio files for security
resource "aws_s3_bucket_public_access_block" "polly_audio_block_public" {
  bucket = aws_s3_bucket.polly_audio_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure lifecycle management for audio files
resource "aws_s3_bucket_lifecycle_configuration" "polly_audio_lifecycle" {
  bucket = aws_s3_bucket.polly_audio_output.id

  rule {
    id     = "audio_file_lifecycle"
    status = "Enabled"

    # Move audio files to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move audio files to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete audio files after specified retention period
    expiration {
      days = var.audio_file_retention_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ========================================
# IAM Roles and Policies for Polly Access
# ========================================

# IAM role for applications to access Amazon Polly services
resource "aws_iam_role" "polly_application_role" {
  name = "polly-application-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "Polly Application Role"
    Purpose = "Access role for text-to-speech applications"
  }
}

# IAM policy for comprehensive Amazon Polly operations
resource "aws_iam_policy" "polly_full_access_policy" {
  name        = "polly-full-access-policy-${random_string.suffix.result}"
  description = "Full access policy for Amazon Polly text-to-speech operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "polly:StartSpeechSynthesisTask",
          "polly:GetSpeechSynthesisTask",
          "polly:ListSpeechSynthesisTasks",
          "polly:DescribeVoices",
          "polly:GetLexicon",
          "polly:ListLexicons",
          "polly:PutLexicon",
          "polly:DeleteLexicon"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for S3 bucket access specific to Polly audio output
resource "aws_iam_policy" "polly_s3_access_policy" {
  name        = "polly-s3-access-policy-${random_string.suffix.result}"
  description = "S3 access policy for Amazon Polly audio output storage"

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
          aws_s3_bucket.polly_audio_output.arn,
          "${aws_s3_bucket.polly_audio_output.arn}/*"
        ]
      }
    ]
  })
}

# Attach Polly access policy to the application role
resource "aws_iam_role_policy_attachment" "polly_policy_attachment" {
  role       = aws_iam_role.polly_application_role.name
  policy_arn = aws_iam_policy.polly_full_access_policy.arn
}

# Attach S3 access policy to the application role
resource "aws_iam_role_policy_attachment" "polly_s3_policy_attachment" {
  role       = aws_iam_role.polly_application_role.name
  policy_arn = aws_iam_policy.polly_s3_access_policy.arn
}

# ========================================
# Instance Profile for EC2 Applications
# ========================================

# Instance profile for EC2 instances running Polly applications
resource "aws_iam_instance_profile" "polly_instance_profile" {
  name = "polly-instance-profile-${random_string.suffix.result}"
  role = aws_iam_role.polly_application_role.name

  tags = {
    Name    = "Polly Instance Profile"
    Purpose = "Instance profile for EC2-based text-to-speech applications"
  }
}

# ========================================
# CloudWatch Log Groups for Monitoring
# ========================================

# CloudWatch log group for Polly application logs
resource "aws_cloudwatch_log_group" "polly_application_logs" {
  name              = "/aws/polly/application-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Polly Application Logs"
    Purpose     = "Application logs for text-to-speech services"
    Environment = var.environment
  }
}

# CloudWatch log group for Polly synthesis task logs
resource "aws_cloudwatch_log_group" "polly_synthesis_logs" {
  name              = "/aws/polly/synthesis-tasks-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Polly Synthesis Task Logs"
    Purpose     = "Logs for batch synthesis operations"
    Environment = var.environment
  }
}

# ========================================
# SNS Topic for Synthesis Task Notifications
# ========================================

# SNS topic for Amazon Polly synthesis task notifications
resource "aws_sns_topic" "polly_synthesis_notifications" {
  name = "polly-synthesis-notifications-${random_string.suffix.result}"

  tags = {
    Name        = "Polly Synthesis Notifications"
    Purpose     = "Notifications for synthesis task completion"
    Environment = var.environment
  }
}

# SNS topic policy for Polly service to publish notifications
resource "aws_sns_topic_policy" "polly_synthesis_topic_policy" {
  arn = aws_sns_topic.polly_synthesis_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "polly.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.polly_synthesis_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ========================================
# Sample Pronunciation Lexicon
# ========================================

# Create a sample pronunciation lexicon for technical terms
resource "aws_polly_lexicon" "tech_terminology" {
  name = "tech-terminology-${random_string.suffix.result}"

  content = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<lexicon version="1.0" 
    xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
    xsi:schemaLocation="http://www.w3.org/2005/01/pronunciation-lexicon 
        http://www.w3.org/TR/2007/CR-pronunciation-lexicon-20071212/pls.xsd"
    alphabet="ipa" 
    xml:lang="en-US">
    <lexeme>
        <grapheme>AWS</grapheme>
        <alias>Amazon Web Services</alias>
    </lexeme>
    <lexeme>
        <grapheme>API</grapheme>
        <alias>Application Programming Interface</alias>
    </lexeme>
    <lexeme>
        <grapheme>SSML</grapheme>
        <alias>Speech Synthesis Markup Language</alias>
    </lexeme>
    <lexeme>
        <grapheme>TTS</grapheme>
        <alias>Text To Speech</alias>
    </lexeme>
    <lexeme>
        <grapheme>IoT</grapheme>
        <alias>Internet of Things</alias>
    </lexeme>
</lexicon>
EOF
}

# ========================================
# Optional: Lambda Function for Polly Operations
# ========================================

# Lambda function for processing text-to-speech requests
resource "aws_lambda_function" "polly_processor" {
  count = var.create_lambda_function ? 1 : 0

  filename         = "polly_processor.zip"
  function_name    = "polly-text-processor-${random_string.suffix.result}"
  role            = aws_iam_role.polly_lambda_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 512

  environment {
    variables = {
      POLLY_BUCKET_NAME = aws_s3_bucket.polly_audio_output.bucket
      SNS_TOPIC_ARN     = aws_sns_topic.polly_synthesis_notifications.arn
      LEXICON_NAME      = aws_polly_lexicon.tech_terminology.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_polly_policy,
    aws_iam_role_policy_attachment.lambda_s3_policy,
    aws_iam_role_policy_attachment.lambda_logs_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = {
    Name        = "Polly Text Processor"
    Purpose     = "Lambda function for text-to-speech processing"
    Environment = var.environment
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "polly_lambda_role" {
  count = var.create_lambda_function ? 1 : 0

  name = "polly-lambda-role-${random_string.suffix.result}"

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

  tags = {
    Name    = "Polly Lambda Role"
    Purpose = "Execution role for Polly Lambda function"
  }
}

# CloudWatch logs for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = var.create_lambda_function ? 1 : 0

  name              = "/aws/lambda/polly-text-processor-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Polly Lambda Logs"
    Purpose     = "Logs for Polly Lambda function"
    Environment = var.environment
  }
}

# Lambda basic execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count = var.create_lambda_function ? 1 : 0

  role       = aws_iam_role.polly_lambda_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Polly access policy attachment
resource "aws_iam_role_policy_attachment" "lambda_polly_policy" {
  count = var.create_lambda_function ? 1 : 0

  role       = aws_iam_role.polly_lambda_role[0].name
  policy_arn = aws_iam_policy.polly_full_access_policy.arn
}

# Lambda S3 access policy attachment
resource "aws_iam_role_policy_attachment" "lambda_s3_policy" {
  count = var.create_lambda_function ? 1 : 0

  role       = aws_iam_role.polly_lambda_role[0].name
  policy_arn = aws_iam_policy.polly_s3_access_policy.arn
}

# Lambda CloudWatch logs policy
resource "aws_iam_policy" "lambda_logs_policy" {
  count = var.create_lambda_function ? 1 : 0

  name        = "lambda-logs-policy-${random_string.suffix.result}"
  description = "Policy for Lambda function to write CloudWatch logs"

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
      }
    ]
  })
}

# Lambda CloudWatch logs policy attachment
resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  count = var.create_lambda_function ? 1 : 0

  role       = aws_iam_role.polly_lambda_role[0].name
  policy_arn = aws_iam_policy.lambda_logs_policy[0].arn
}

# ========================================
# CloudWatch Monitoring and Alarms
# ========================================

# CloudWatch metric filter for synthesis task failures
resource "aws_cloudwatch_metric_filter" "synthesis_failures" {
  name           = "polly-synthesis-failures-${random_string.suffix.result}"
  log_group_name = aws_cloudwatch_log_group.polly_synthesis_logs.name
  pattern        = "ERROR"

  metric_transformation {
    name      = "PollySynthesisFailures"
    namespace = "AWS/Polly/Custom"
    value     = "1"
  }
}

# CloudWatch alarm for synthesis task failures
resource "aws_cloudwatch_metric_alarm" "synthesis_failure_alarm" {
  alarm_name          = "polly-synthesis-failures-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PollySynthesisFailures"
  namespace           = "AWS/Polly/Custom"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Polly synthesis task failures"
  alarm_actions       = [aws_sns_topic.polly_synthesis_notifications.arn]

  tags = {
    Name        = "Polly Synthesis Failure Alarm"
    Purpose     = "Monitor synthesis task failures"
    Environment = var.environment
  }
}

# ========================================
# VPC Endpoints for Private Access (Optional)
# ========================================

# VPC endpoint for Amazon Polly (if VPC ID is provided)
resource "aws_vpc_endpoint" "polly_endpoint" {
  count = var.vpc_id != "" ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.polly"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.polly_endpoint_sg[0].id]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "polly:SynthesizeSpeech",
          "polly:StartSpeechSynthesisTask",
          "polly:GetSpeechSynthesisTask",
          "polly:ListSpeechSynthesisTasks",
          "polly:DescribeVoices",
          "polly:GetLexicon",
          "polly:ListLexicons",
          "polly:PutLexicon",
          "polly:DeleteLexicon"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "Polly VPC Endpoint"
    Purpose     = "Private access to Amazon Polly service"
    Environment = var.environment
  }
}

# Security group for VPC endpoint
resource "aws_security_group" "polly_endpoint_sg" {
  count = var.vpc_id != "" ? 1 : 0

  name        = "polly-endpoint-sg-${random_string.suffix.result}"
  description = "Security group for Polly VPC endpoint"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Polly VPC Endpoint Security Group"
    Purpose     = "Security group for Polly VPC endpoint"
    Environment = var.environment
  }
}