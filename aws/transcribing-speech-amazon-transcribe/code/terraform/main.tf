# Amazon Transcribe Speech Recognition Infrastructure

# Data source for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Resource naming
  suffix = random_password.suffix.result
  bucket_name = "${var.project_name}-${var.environment}-${local.suffix}"
  vocabulary_name = "${var.project_name}-vocab-${local.suffix}"
  vocabulary_filter_name = "${var.project_name}-filter-${local.suffix}"
  language_model_name = "${var.project_name}-lm-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Suffix      = local.suffix
  })
}

# ============================================================================
# S3 BUCKET FOR AUDIO FILES AND TRANSCRIPTION OUTPUTS
# ============================================================================

# S3 bucket for storing audio files and transcription outputs
resource "aws_s3_bucket" "transcribe_bucket" {
  bucket = local.bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Audio files and transcription outputs"
    Component   = "storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "transcribe_bucket_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.transcribe_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "transcribe_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.transcribe_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "transcribe_bucket_pab" {
  bucket = aws_s3_bucket.transcribe_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "transcribe_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.transcribe_bucket.id

  rule {
    id     = "audio_files_lifecycle"
    status = "Enabled"

    filter {
      prefix = "audio-input/"
    }

    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_expiration_days
    }
  }

  rule {
    id     = "transcription_outputs_lifecycle"
    status = "Enabled"

    filter {
      prefix = "transcription-output/"
    }

    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.s3_expiration_days
    }
  }
}

# S3 bucket notification for Lambda triggers
resource "aws_s3_bucket_notification" "transcribe_bucket_notification" {
  bucket = aws_s3_bucket.transcribe_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "audio-input/"
    filter_suffix       = ".mp3"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "audio-input/"
    filter_suffix       = ".wav"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "audio-input/"
    filter_suffix       = ".flac"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.transcribe_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "audio-input/"
    filter_suffix       = ".mp4"
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# Create folder structure with empty objects
resource "aws_s3_object" "audio_input_folder" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "audio-input/"
  
  tags = merge(local.common_tags, {
    Name      = "audio-input-folder"
    Component = "storage"
  })
}

resource "aws_s3_object" "transcription_output_folder" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "transcription-output/"
  
  tags = merge(local.common_tags, {
    Name      = "transcription-output-folder"
    Component = "storage"
  })
}

resource "aws_s3_object" "custom_vocabulary_folder" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "custom-vocabulary/"
  
  tags = merge(local.common_tags, {
    Name      = "custom-vocabulary-folder"
    Component = "storage"
  })
}

resource "aws_s3_object" "training_data_folder" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "training-data/"
  
  tags = merge(local.common_tags, {
    Name      = "training-data-folder"
    Component = "storage"
  })
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for Amazon Transcribe service
resource "aws_iam_role" "transcribe_service_role" {
  name = "${var.project_name}-transcribe-service-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transcribe.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-transcribe-service-role-${local.suffix}"
    Component = "iam"
  })
}

# IAM policy for Transcribe S3 access
resource "aws_iam_role_policy" "transcribe_s3_policy" {
  name = "TranscribeS3Access"
  role = aws_iam_role.transcribe_service_role.id

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
          aws_s3_bucket.transcribe_bucket.arn,
          "${aws_s3_bucket.transcribe_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role-${local.suffix}"

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
    Name      = "${var.project_name}-lambda-execution-role-${local.suffix}"
    Component = "iam"
  })
}

# IAM policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda Transcribe access
resource "aws_iam_role_policy" "lambda_transcribe_policy" {
  name = "LambdaTranscribeAccess"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "transcribe:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.transcribe_bucket.arn,
          "${aws_s3_bucket.transcribe_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM policy for Lambda X-Ray tracing (if enabled)
resource "aws_iam_role_policy_attachment" "lambda_xray_policy" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# AMAZON TRANSCRIBE CUSTOM VOCABULARIES AND FILTERS
# ============================================================================

# Upload custom vocabulary to S3
resource "aws_s3_object" "custom_vocabulary_file" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "custom-vocabulary/custom-vocabulary.txt"
  content = join("\n", var.custom_vocabulary_terms)

  tags = merge(local.common_tags, {
    Name      = "custom-vocabulary-file"
    Component = "transcribe"
  })
}

# Create custom vocabulary
resource "aws_transcribe_vocabulary" "custom_vocabulary" {
  vocabulary_name     = local.vocabulary_name
  language_code       = var.language_code
  vocabulary_file_uri = "s3://${aws_s3_bucket.transcribe_bucket.id}/${aws_s3_object.custom_vocabulary_file.key}"

  tags = merge(local.common_tags, {
    Name      = local.vocabulary_name
    Component = "transcribe"
  })

  depends_on = [aws_s3_object.custom_vocabulary_file]
}

# Upload vocabulary filter to S3
resource "aws_s3_object" "vocabulary_filter_file" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "custom-vocabulary/vocabulary-filter.txt"
  content = join("\n", var.vocabulary_filter_terms)

  tags = merge(local.common_tags, {
    Name      = "vocabulary-filter-file"
    Component = "transcribe"
  })
}

# Create vocabulary filter
resource "aws_transcribe_vocabulary_filter" "vocabulary_filter" {
  vocabulary_filter_name     = local.vocabulary_filter_name
  language_code              = var.language_code
  vocabulary_filter_file_uri = "s3://${aws_s3_bucket.transcribe_bucket.id}/${aws_s3_object.vocabulary_filter_file.key}"

  tags = merge(local.common_tags, {
    Name      = local.vocabulary_filter_name
    Component = "transcribe"
  })

  depends_on = [aws_s3_object.vocabulary_filter_file]
}

# Upload training data for custom language model
resource "aws_s3_object" "training_data_file" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "training-data/training-data.txt"
  content = var.training_data_content

  tags = merge(local.common_tags, {
    Name      = "training-data-file"
    Component = "transcribe"
  })
}

# Create custom language model (Note: This is a long-running process)
resource "aws_transcribe_language_model" "custom_language_model" {
  language_code = var.language_code
  base_model_name = "WideBand"
  model_name = local.language_model_name

  input_data_config {
    s3_uri = "s3://${aws_s3_bucket.transcribe_bucket.id}/training-data/"
    data_access_role_arn = var.data_access_role_arn != "" ? var.data_access_role_arn : aws_iam_role.transcribe_service_role.arn
  }

  tags = merge(local.common_tags, {
    Name      = local.language_model_name
    Component = "transcribe"
  })

  depends_on = [
    aws_s3_object.training_data_file,
    aws_iam_role.transcribe_service_role
  ]
}

# ============================================================================
# LAMBDA FUNCTION FOR TRANSCRIPTION PROCESSING
# ============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-transcribe-processor-${local.suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-transcribe-processor-logs"
    Component = "lambda"
  })
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = <<-EOF
import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Process Amazon Transcribe events and results
    
    This function handles:
    - S3 events for new audio files
    - Transcription job completion events
    - Post-processing of transcription results
    """
    
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Handle S3 event (new audio file uploaded)
        if 'Records' in event and 's3' in event['Records'][0]:
            return handle_s3_event(event)
        
        # Handle direct invocation with job name
        elif 'jobName' in event:
            return handle_job_status_check(event)
        
        # Handle transcription job completion event
        elif 'detail' in event and 'TranscriptionJobName' in event['detail']:
            return handle_transcription_completion(event)
        
        else:
            logger.warning("Unknown event type")
            return {
                'statusCode': 400,
                'body': json.dumps('Unknown event type')
            }
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing event: {str(e)}')
        }

def handle_s3_event(event):
    """Handle S3 event for new audio file"""
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Only process audio files in the audio-input folder
        if not key.startswith('audio-input/'):
            continue
            
        # Extract file extension to determine media format
        file_extension = key.split('.')[-1].lower()
        media_format = file_extension if file_extension in ['mp3', 'mp4', 'wav', 'flac'] else 'mp3'
        
        # Generate unique job name
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        job_name = f"auto-transcription-{timestamp}-{os.urandom(4).hex()}"
        
        # Start transcription job
        transcribe_response = transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            LanguageCode=os.environ.get('LANGUAGE_CODE', 'en-US'),
            MediaFormat=media_format,
            Media={
                'MediaFileUri': f"s3://{bucket}/{key}"
            },
            OutputBucketName=bucket,
            OutputKey=f"transcription-output/{job_name}.json",
            Settings={
                'VocabularyName': os.environ.get('VOCABULARY_NAME'),
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': int(os.environ.get('MAX_SPEAKER_LABELS', '4')),
                'ChannelIdentification': True,
                'VocabularyFilterName': os.environ.get('VOCABULARY_FILTER_NAME'),
                'VocabularyFilterMethod': os.environ.get('VOCABULARY_FILTER_METHOD', 'mask')
            }
        )
        
        logger.info(f"Started transcription job: {job_name}")
        
    return {
        'statusCode': 200,
        'body': json.dumps('Transcription job started successfully')
    }

def handle_job_status_check(event):
    """Handle job status check"""
    
    job_name = event['jobName']
    
    response = transcribe.get_transcription_job(
        TranscriptionJobName=job_name
    )
    
    job_status = response['TranscriptionJob']['TranscriptionJobStatus']
    
    if job_status == 'COMPLETED':
        transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
        
        logger.info(f"Transcription job {job_name} completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Transcription completed',
                'jobName': job_name,
                'transcriptUri': transcript_uri,
                'status': job_status
            })
        }
    elif job_status == 'FAILED':
        failure_reason = response['TranscriptionJob'].get('FailureReason', 'Unknown error')
        
        logger.error(f"Transcription job {job_name} failed: {failure_reason}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Transcription failed',
                'jobName': job_name,
                'failureReason': failure_reason,
                'status': job_status
            })
        }
    else:
        logger.info(f"Transcription job {job_name} is in progress")
        
        return {
            'statusCode': 202,
            'body': json.dumps({
                'message': 'Transcription in progress',
                'jobName': job_name,
                'status': job_status
            })
        }

def handle_transcription_completion(event):
    """Handle transcription job completion event"""
    
    job_name = event['detail']['TranscriptionJobName']
    job_status = event['detail']['TranscriptionJobStatus']
    
    logger.info(f"Transcription job {job_name} completed with status: {job_status}")
    
    if job_status == 'COMPLETED':
        # Get job details
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
        
        # Additional post-processing can be added here
        # For example: parse transcript, extract insights, trigger downstream processes
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Transcription completed and processed',
                'jobName': job_name,
                'transcriptUri': transcript_uri
            })
        }
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Transcription job {job_name} status: {job_status}')
    }
EOF
    filename = "lambda-function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "transcribe_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-transcribe-processor-${local.suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda-function.lambda_handler"
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME                = aws_s3_bucket.transcribe_bucket.id
      VOCABULARY_NAME           = aws_transcribe_vocabulary.custom_vocabulary.vocabulary_name
      VOCABULARY_FILTER_NAME    = aws_transcribe_vocabulary_filter.vocabulary_filter.vocabulary_filter_name
      VOCABULARY_FILTER_METHOD  = var.vocabulary_filter_method
      LANGUAGE_CODE            = var.language_code
      MAX_SPEAKER_LABELS       = var.max_speaker_labels
      ENABLE_CHANNEL_ID        = var.enable_channel_identification
      ENABLE_SPEAKER_LABELS    = var.enable_speaker_labels
      ENABLE_CONTENT_REDACTION = var.enable_content_redaction
      REDACTION_OUTPUT_TYPE    = var.redaction_output_type
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_transcribe_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-transcribe-processor-${local.suffix}"
    Component = "lambda"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transcribe_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.transcribe_bucket.arn
}

# ============================================================================
# CLOUDWATCH ALARMS AND MONITORING
# ============================================================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-lambda-errors-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.transcribe_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-lambda-errors-${local.suffix}"
    Component = "monitoring"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "${var.project_name}-lambda-duration-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "${var.lambda_timeout * 1000 * 0.8}" # 80% of timeout
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.transcribe_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-lambda-duration-${local.suffix}"
    Component = "monitoring"
  })
}

# ============================================================================
# EXAMPLE TRANSCRIPTION JOBS (FOR DEMONSTRATION)
# ============================================================================

# Upload sample audio metadata file
resource "aws_s3_object" "sample_audio_metadata" {
  bucket = aws_s3_bucket.transcribe_bucket.id
  key    = "audio-input/sample-audio-metadata.txt"
  content = <<-EOF
Sample audio file for transcription testing.
This file represents a 30-second audio clip containing:
- Clear speech at normal speaking pace
- Technical terminology for custom vocabulary testing
- Multiple speakers for diarization testing

This is a metadata file. In production, replace this with actual audio files.
EOF

  tags = merge(local.common_tags, {
    Name      = "sample-audio-metadata"
    Component = "demo"
  })
}

# ============================================================================
# OUTPUTS
# ============================================================================

# Export key resource information for use by other modules or applications