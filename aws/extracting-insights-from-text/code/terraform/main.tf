# main.tf - Main Terraform configuration for Amazon Comprehend NLP Solution

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Resource naming
  resource_suffix = random_id.suffix.hex
  
  # S3 bucket names
  input_bucket_name  = "${var.s3_bucket_prefix}-${local.resource_suffix}"
  output_bucket_name = "${var.s3_bucket_prefix}-output-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.common_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ===============================
# S3 Buckets for Input and Output
# ===============================

# S3 bucket for input documents
resource "aws_s3_bucket" "input_bucket" {
  bucket = local.input_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = "Comprehend Input Bucket"
    Purpose     = "Store input documents for NLP processing"
    ContentType = "Text Documents"
  })
}

# S3 bucket for output results
resource "aws_s3_bucket" "output_bucket" {
  bucket = local.output_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = "Comprehend Output Bucket"
    Purpose     = "Store NLP processing results"
    ContentType = "JSON Results"
  })
}

# S3 bucket versioning for input bucket
resource "aws_s3_bucket_versioning" "input_bucket_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.input_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket versioning for output bucket
resource "aws_s3_bucket_versioning" "output_bucket_versioning" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.output_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.input_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.output_bucket.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for input bucket
resource "aws_s3_bucket_public_access_block" "input_bucket_pab" {
  bucket = aws_s3_bucket.input_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket public access block for output bucket
resource "aws_s3_bucket_public_access_block" "output_bucket_pab" {
  bucket = aws_s3_bucket.output_bucket.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket notification for EventBridge
resource "aws_s3_bucket_notification" "bucket_notification" {
  count      = var.enable_eventbridge_processing ? 1 : 0
  bucket     = aws_s3_bucket.input_bucket.id
  eventbridge = true
  
  depends_on = [aws_s3_bucket_public_access_block.input_bucket_pab]
}

# ===============================
# IAM Roles and Policies
# ===============================

# IAM role for Amazon Comprehend service
resource "aws_iam_role" "comprehend_service_role" {
  name = "${var.project_name}-comprehend-service-role-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "comprehend.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "Comprehend Service Role"
  })
}

# IAM policy for Comprehend service role
resource "aws_iam_role_policy" "comprehend_service_policy" {
  name = "${var.project_name}-comprehend-service-policy-${local.resource_suffix}"
  role = aws_iam_role.comprehend_service_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input_bucket.arn,
          "${aws_s3_bucket.input_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role-${local.resource_suffix}"
  
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
    Name = "Lambda Execution Role"
  })
}

# IAM policy for Lambda execution role
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${var.project_name}-lambda-execution-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_execution_role.id
  
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
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "comprehend:DetectSentiment",
          "comprehend:DetectEntities",
          "comprehend:DetectKeyPhrases",
          "comprehend:DetectDominantLanguage",
          "comprehend:DetectPiiEntities",
          "comprehend:BatchDetectSentiment",
          "comprehend:BatchDetectEntities",
          "comprehend:BatchDetectKeyPhrases"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.input_bucket.arn}/*",
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach basic execution role policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ===============================
# Lambda Function for Real-time Processing
# ===============================

# Create Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/comprehend_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      input_bucket_name  = aws_s3_bucket.input_bucket.bucket
      output_bucket_name = aws_s3_bucket.output_bucket.bucket
      language_code      = var.comprehend_language_code
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for real-time Comprehend processing
resource "aws_lambda_function" "comprehend_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-comprehend-processor-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      INPUT_BUCKET_NAME  = aws_s3_bucket.input_bucket.bucket
      OUTPUT_BUCKET_NAME = aws_s3_bucket.output_bucket.bucket
      LANGUAGE_CODE      = var.comprehend_language_code
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_log_group
  ]
  
  tags = merge(local.common_tags, {
    Name = "Comprehend Processor Lambda"
  })
}

# Lambda function code template
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import os
from typing import Dict, List, Any
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for real-time Comprehend processing
    
    Args:
        event: Lambda event containing text to process
        context: Lambda context
        
    Returns:
        Dictionary with processing results
    """
    
    try:
        # Extract text from event
        text = event.get('text', '')
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No text provided in request'
                })
            }
        
        # Validate text length (Comprehend limit is 5000 UTF-8 characters)
        if len(text.encode('utf-8')) > 5000:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Text exceeds 5000 UTF-8 character limit'
                })
            }
        
        language_code = os.environ.get('LANGUAGE_CODE', 'en')
        
        # Perform sentiment analysis
        logger.info("Performing sentiment analysis")
        sentiment_response = comprehend.detect_sentiment(
            Text=text,
            LanguageCode=language_code
        )
        
        # Perform entity detection
        logger.info("Performing entity detection")
        entities_response = comprehend.detect_entities(
            Text=text,
            LanguageCode=language_code
        )
        
        # Perform key phrase extraction
        logger.info("Performing key phrase extraction")
        key_phrases_response = comprehend.detect_key_phrases(
            Text=text,
            LanguageCode=language_code
        )
        
        # Detect dominant language
        logger.info("Detecting dominant language")
        language_response = comprehend.detect_dominant_language(
            Text=text
        )
        
        # Compile results
        result = {
            'sentiment': {
                'sentiment': sentiment_response['Sentiment'],
                'scores': sentiment_response['SentimentScore']
            },
            'entities': [
                {
                    'text': entity['Text'],
                    'type': entity['Type'],
                    'score': entity['Score'],
                    'begin_offset': entity['BeginOffset'],
                    'end_offset': entity['EndOffset']
                }
                for entity in entities_response['Entities']
            ],
            'key_phrases': [
                {
                    'text': phrase['Text'],
                    'score': phrase['Score'],
                    'begin_offset': phrase['BeginOffset'],
                    'end_offset': phrase['EndOffset']
                }
                for phrase in key_phrases_response['KeyPhrases']
            ],
            'dominant_language': language_response['Languages'][0] if language_response['Languages'] else None,
            'processing_metadata': {
                'timestamp': context.aws_request_id,
                'function_name': context.function_name,
                'language_code': language_code
            }
        }
        
        logger.info(f"Processing completed successfully. Found {len(result['entities'])} entities and {len(result['key_phrases'])} key phrases")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=str),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Processing failed: {str(e)}'
            })
        }
EOF
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-comprehend-processor-${local.resource_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
  })
}

# ===============================
# EventBridge Rules for S3 Events
# ===============================

# EventBridge rule for S3 object creation
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  count       = var.enable_eventbridge_processing ? 1 : 0
  name        = "${var.project_name}-s3-object-created-${local.resource_suffix}"
  description = "Trigger Lambda when objects are created in S3 input bucket"
  
  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.input_bucket.bucket]
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "S3 Object Created Rule"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_eventbridge_processing ? 1 : 0
  rule  = aws_cloudwatch_event_rule.s3_object_created[0].name
  arn   = aws_lambda_function.comprehend_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_eventbridge_processing ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.comprehend_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_object_created[0].arn
}

# ===============================
# SNS Topic for Notifications (Optional)
# ===============================

# SNS topic for job completion notifications
resource "aws_sns_topic" "comprehend_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-comprehend-notifications-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "Comprehend Notifications Topic"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.comprehend_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===============================
# Sample Data Upload (Optional)
# ===============================

# Upload sample text files for testing
resource "aws_s3_object" "sample_files" {
  for_each = {
    "sample-positive-review.txt" = "This product is absolutely amazing! The quality exceeded my expectations and the customer service was outstanding. I would definitely recommend this to anyone looking for a reliable solution."
    "sample-negative-review.txt" = "The device stopped working after just two weeks. Very disappointed with the build quality. The support team was unhelpful and took forever to respond."
    "sample-neutral-review.txt"  = "The product is okay, nothing special. It works as described but doesn't stand out from similar products. Price is reasonable for what you get."
    "sample-support-ticket.txt"  = "Customer reporting login issues with mobile app. Error message: 'Invalid credentials' appears even with correct password. Customer using iPhone 12, iOS 15.2."
  }
  
  bucket  = aws_s3_bucket.input_bucket.bucket
  key     = "samples/${each.key}"
  content = each.value
  
  tags = merge(local.common_tags, {
    Name        = "Sample Text File"
    ContentType = "Sample Data"
  })
}

# ===============================
# Custom Entity Recognition (Optional)
# ===============================

# Custom entity recognizer training data
resource "aws_s3_object" "custom_entity_training_data" {
  count   = var.enable_custom_entity_training ? 1 : 0
  bucket  = aws_s3_bucket.input_bucket.bucket
  key     = "training/custom-entities.csv"
  content = "Text,Entities\n\"The AnyPhone Pro 12 has excellent battery life\",\"[{\"\"BeginOffset\"\":4,\"\"EndOffset\"\":19,\"\"Type\"\":\"\"PRODUCT\"\",\"\"Text\"\":\"\"AnyPhone Pro 12\"\"}]\"\n\"Customer purchased the SuperLaptop X1 last month\",\"[{\"\"BeginOffset\"\":23,\"\"EndOffset\"\":37,\"\"Type\"\":\"\"PRODUCT\"\",\"\"Text\"\":\"\"SuperLaptop X1\"\"}]\"\n\"The SmartWatch Series 5 needs software update\",\"[{\"\"BeginOffset\"\":4,\"\"EndOffset\"\":23,\"\"Type\"\":\"\"PRODUCT\"\",\"\"Text\"\":\"\"SmartWatch Series 5\"\"}]\""
  
  tags = merge(local.common_tags, {
    Name        = "Custom Entity Training Data"
    ContentType = "Training Data"
  })
}

# ===============================
# CloudWatch Dashboard (Optional)
# ===============================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "comprehend_dashboard" {
  dashboard_name = "${var.project_name}-comprehend-dashboard-${local.resource_suffix}"
  
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.comprehend_processor.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Lambda Function Metrics"
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
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.input_bucket.bucket, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = local.region
          title  = "S3 Bucket Metrics"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "Comprehend Dashboard"
  })
}