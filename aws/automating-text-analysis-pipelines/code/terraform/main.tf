# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "amazon-comprehend-nlp-pipeline"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# KMS key for encryption (optional)
resource "aws_kms_key" "comprehend_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for Comprehend NLP pipeline encryption"
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
        Sid    = "Allow Lambda service to use the key"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "comprehend_key_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-comprehend-key"
  target_key_id = aws_kms_key.comprehend_key[0].key_id
}

# S3 bucket for input data
resource "aws_s3_bucket" "input_bucket" {
  bucket        = "${local.name_prefix}-input-${local.resource_suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-input-bucket"
    Description = "S3 bucket for NLP pipeline input data"
  })
}

# S3 bucket for output/processed data
resource "aws_s3_bucket" "output_bucket" {
  bucket        = "${local.name_prefix}-output-${local.resource_suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-output-bucket"
    Description = "S3 bucket for NLP pipeline output data"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "input_bucket_versioning" {
  bucket = aws_s3_bucket.input_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_versioning" "output_bucket_versioning" {
  bucket = aws_s3_bucket.output_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "input_bucket_pab" {
  bucket = aws_s3_bucket.input_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output_bucket_pab" {
  bucket = aws_s3_bucket.output_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "input_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    id     = "transition_rule"
    status = "Enabled"

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.s3_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  dynamic "rule" {
    for_each = var.enable_s3_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent_tiering"
      status = "Enabled"

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "output_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    id     = "transition_rule"
    status = "Enabled"

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.s3_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  dynamic "rule" {
    for_each = var.enable_s3_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent_tiering"
      status = "Enabled"

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }
}

# S3 bucket notification for Lambda trigger
resource "aws_s3_bucket_notification" "input_bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id
  depends_on = [aws_lambda_permission.s3_invoke]

  lambda_function {
    lambda_function_arn = aws_lambda_function.comprehend_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".txt"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.resource_suffix}"

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
    Name        = "${local.name_prefix}-lambda-execution-role"
    Description = "IAM role for Comprehend NLP Lambda function"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "comprehend:DetectSentiment",
          "comprehend:DetectEntities",
          "comprehend:DetectKeyPhrases",
          "comprehend:DetectLanguage",
          "comprehend:DetectSyntax",
          "comprehend:DetectTargetedSentiment",
          "comprehend:StartDocumentClassificationJob",
          "comprehend:StartEntitiesDetectionJob",
          "comprehend:StartKeyPhrasesDetectionJob",
          "comprehend:StartSentimentDetectionJob",
          "comprehend:DescribeDocumentClassificationJob",
          "comprehend:DescribeEntitiesDetectionJob",
          "comprehend:DescribeKeyPhrasesDetectionJob",
          "comprehend:DescribeSentimentDetectionJob"
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
          "${aws_s3_bucket.input_bucket.arn}/*",
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input_bucket.arn,
          aws_s3_bucket.output_bucket.arn
        ]
      }
    ]
  })
}

# Add KMS permissions if encryption is enabled
resource "aws_iam_role_policy" "lambda_kms_policy" {
  count = var.enable_kms_encryption ? 1 : 0
  name  = "${local.name_prefix}-lambda-kms-policy"
  role  = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.comprehend_key[0].arn
      }
    ]
  })
}

# IAM role for Comprehend batch jobs
resource "aws_iam_role" "comprehend_service_role" {
  name = "${local.name_prefix}-comprehend-service-role-${local.resource_suffix}"

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
    Name        = "${local.name_prefix}-comprehend-service-role"
    Description = "IAM role for Comprehend batch processing jobs"
  })
}

# IAM policy for Comprehend service role
resource "aws_iam_role_policy" "comprehend_service_policy" {
  name = "${local.name_prefix}-comprehend-service-policy"
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
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-processor-${local.resource_suffix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].arn : null

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-logs"
    Description = "CloudWatch logs for Comprehend NLP Lambda function"
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      output_bucket = aws_s3_bucket.output_bucket.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "comprehend_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-processor-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency > 0 ? var.lambda_reserved_concurrency : null

  environment {
    variables = {
      INPUT_BUCKET       = aws_s3_bucket.input_bucket.bucket
      OUTPUT_BUCKET      = aws_s3_bucket.output_bucket.bucket
      LANGUAGE_CODE      = var.comprehend_language_code
      LOG_LEVEL          = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-comprehend-processor"
    Description = "Lambda function for real-time NLP processing with Amazon Comprehend"
  })
}

# Lambda permission for S3 to invoke function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.comprehend_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

# Lambda provisioned concurrency (optional)
resource "aws_lambda_provisioned_concurrency_config" "comprehend_processor_pcc" {
  count                             = var.lambda_provisioned_concurrency > 0 ? 1 : 0
  function_name                     = aws_lambda_function.comprehend_processor.function_name
  provisioned_concurrent_executions = var.lambda_provisioned_concurrency
  qualifier                         = aws_lambda_function.comprehend_processor.version
}

# SNS topic for notifications (optional)
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.name_prefix}-notifications"
  
  kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].arn : null

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-notifications"
    Description = "SNS topic for NLP pipeline notifications"
  })
}

# SNS topic subscription (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch metric alarms (optional)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.comprehend_processor.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "30000"  # 30 seconds
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.comprehend_processor.function_name
  }

  tags = local.common_tags
}

# Sample training data for custom classification (optional)
resource "aws_s3_object" "training_data" {
  count = var.enable_custom_classification ? 1 : 0
  
  bucket = aws_s3_bucket.input_bucket.bucket
  key    = "training/training-manifest.csv"
  
  content = templatefile("${path.module}/training_data.csv.tpl", {})
  
  tags = merge(local.common_tags, {
    Name        = "training-data"
    Description = "Sample training data for custom classification"
  })
}

# Create the Lambda function template file
resource "local_file" "lambda_function_template" {
  content = <<-EOT
import json
import boto3
import uuid
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda function to process text with Amazon Comprehend
    
    Supports both S3 event triggers and direct invocations.
    Performs sentiment analysis, entity detection, and key phrase extraction.
    """
    try:
        # Get text from S3 event or direct invocation
        if 'Records' in event:
            # S3 event trigger
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = event['Records'][0]['s3']['object']['key']
            
            logger.info(f"Processing S3 object: s3://{bucket}/{key}")
            
            # Get text from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            text = response['Body'].read().decode('utf-8')
            
            # Use environment variable for output bucket
            output_bucket = os.environ.get('OUTPUT_BUCKET', '${output_bucket}')
        else:
            # Direct invocation
            text = event.get('text', '')
            output_bucket = event.get('output_bucket', os.environ.get('OUTPUT_BUCKET', '${output_bucket}'))
            
            logger.info("Processing direct invocation")
        
        if not text:
            logger.error("No text provided for processing")
            return {
                'statusCode': 400, 
                'body': json.dumps({'error': 'No text provided'})
            }
        
        logger.info(f"Processing text of length: {len(text)} characters")
        
        # Detect language first
        language_response = comprehend.detect_dominant_language(Text=text[:5000])  # Limit for language detection
        language_code = language_response['Languages'][0]['LanguageCode']
        language_confidence = language_response['Languages'][0]['Score']
        
        logger.info(f"Detected language: {language_code} (confidence: {language_confidence:.2f})")
        
        # Perform sentiment analysis
        sentiment_response = comprehend.detect_sentiment(
            Text=text[:5000],  # Comprehend has text length limits
            LanguageCode=language_code
        )
        
        # Extract entities
        entities_response = comprehend.detect_entities(
            Text=text[:5000],
            LanguageCode=language_code
        )
        
        # Extract key phrases
        keyphrases_response = comprehend.detect_key_phrases(
            Text=text[:5000],
            LanguageCode=language_code
        )
        
        # Compile results
        results = {
            'timestamp': datetime.now().isoformat(),
            'text': text,
            'text_length': len(text),
            'language': {
                'code': language_code,
                'confidence': language_confidence
            },
            'sentiment': {
                'sentiment': sentiment_response['Sentiment'],
                'scores': sentiment_response['SentimentScore']
            },
            'entities': entities_response['Entities'],
            'key_phrases': keyphrases_response['KeyPhrases']
        }
        
        # Save results to S3 if output bucket provided
        if output_bucket:
            output_key = f"processed/{datetime.now().strftime('%Y/%m/%d')}/{uuid.uuid4()}.json"
            
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=json.dumps(results, indent=2, default=str),
                ContentType='application/json',
                Metadata={
                    'processed-by': 'comprehend-nlp-pipeline',
                    'sentiment': sentiment_response['Sentiment'],
                    'language': language_code
                }
            )
            
            logger.info(f"Results saved to s3://{output_bucket}/{output_key}")
            results['output_location'] = f"s3://{output_bucket}/{output_key}"
        
        logger.info(f"Processing completed successfully. Sentiment: {sentiment_response['Sentiment']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_msg = f"Error processing text: {str(e)}"
        logger.error(error_msg, exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
EOT
  filename = "${path.module}/lambda_function.py.tpl"
}

# Create the training data template file
resource "local_file" "training_data_template" {
  content = <<-EOT
complaints,The service was terrible and I want my money back.
complaints,This product broke after one day of use.
complaints,The staff was rude and unhelpful.
complaints,I am very disappointed with this purchase.
complaints,The quality is much worse than expected.
complaints,This is the worst experience I've ever had.
complaints,Complete waste of money and time.
complaints,Absolutely terrible customer service.
compliments,Excellent service and great product quality!
compliments,The staff was very helpful and professional.
compliments,I highly recommend this product to everyone.
compliments,Outstanding customer service experience.
compliments,The quality exceeded my expectations.
compliments,Amazing value for money and fast delivery.
compliments,Best purchase I've made in years.
compliments,Fantastic product and wonderful support team.
neutral,The product is okay for the price.
neutral,Average service nothing special.
neutral,The item works as described.
neutral,Standard quality as expected.
neutral,Regular customer service interaction.
neutral,Product meets basic requirements.
neutral,Acceptable quality and delivery time.
neutral,Standard experience overall.
EOT
  filename = "${path.module}/training_data.csv.tpl"
}