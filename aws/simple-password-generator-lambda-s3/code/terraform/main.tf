# Simple Password Generator with Lambda and S3
# Infrastructure as Code for secure serverless password generation

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix to ensure uniqueness
  resource_suffix     = lower(random_id.suffix.hex)
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-${local.resource_suffix}"
  s3_bucket_name      = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-${local.resource_suffix}"
  iam_role_name       = "${var.project_name}-lambda-role-${local.resource_suffix}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "simple-password-generator-lambda-s3"
    },
    var.additional_tags
  )
}

# ================================
# S3 BUCKET FOR PASSWORD STORAGE
# ================================

# S3 bucket for storing generated passwords with encryption and security configurations
resource "aws_s3_bucket" "password_storage" {
  bucket        = local.s3_bucket_name
  force_destroy = var.force_destroy_bucket

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-password-storage"
    Description = "Secure storage for generated passwords"
  })
}

# Enable server-side encryption for the S3 bucket using AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "password_storage" {
  bucket = aws_s3_bucket.password_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Configure versioning for password history and recovery
resource "aws_s3_bucket_versioning" "password_storage" {
  bucket = aws_s3_bucket.password_storage.id
  
  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Disabled"
  }
}

# Block all public access to ensure security
resource "aws_s3_bucket_public_access_block" "password_storage" {
  bucket = aws_s3_bucket.password_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure lifecycle policy for automatic password cleanup (if enabled)
resource "aws_s3_bucket_lifecycle_configuration" "password_storage" {
  count  = var.s3_lifecycle_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.password_storage.id

  rule {
    id     = "password_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Handle versioned objects if versioning is enabled
    dynamic "noncurrent_version_expiration" {
      for_each = var.s3_enable_versioning ? [1] : []
      content {
        noncurrent_days = var.s3_lifecycle_expiration_days
      }
    }
  }
}

# ================================
# IAM ROLE AND POLICIES
# ================================

# Trust policy allowing Lambda service to assume the role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda function execution with least privilege access
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for password generator Lambda function"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-lambda-execution-role"
    Description = "Lambda execution role with S3 and CloudWatch access"
  })
}

# Custom policy for S3 bucket access (least privilege)
data "aws_iam_policy_document" "lambda_s3_policy" {
  # Allow S3 operations on the specific bucket and its objects
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.password_storage.arn,
      "${aws_s3_bucket.password_storage.arn}/*"
    ]
  }
  
  # Allow CloudWatch Logs operations for function logging
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_function_name}*"
    ]
  }
  
  # X-Ray tracing permissions (if enabled)
  dynamic "statement" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      effect = "Allow"
      
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      
      resources = ["*"]
    }
  }
}

# Attach custom policy to Lambda execution role
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "${local.iam_role_name}-s3-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_s3_policy.json
}

# ================================
# CLOUDWATCH LOG GROUP
# ================================

# CloudWatch Log Group for Lambda function logs with retention policy
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-lambda-logs"
    Description = "CloudWatch logs for password generator Lambda function"
  })
}

# ================================
# LAMBDA FUNCTION
# ================================

# Create Lambda function source code as a zip archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<-EOF
import json
import boto3
import secrets
import string
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def validate_password_parameters(length: int, include_uppercase: bool, 
                               include_lowercase: bool, include_numbers: bool, 
                               include_symbols: bool) -> None:
    """Validate password generation parameters."""
    if length < 8 or length > 128:
        raise ValueError("Password length must be between 8 and 128 characters")
    
    if not any([include_uppercase, include_lowercase, include_numbers, include_symbols]):
        raise ValueError("At least one character type must be selected")

def build_character_set(include_uppercase: bool, include_lowercase: bool,
                       include_numbers: bool, include_symbols: bool) -> str:
    """Build character set based on parameters."""
    charset = ""
    if include_lowercase:
        charset += string.ascii_lowercase
    if include_uppercase:
        charset += string.ascii_uppercase
    if include_numbers:
        charset += string.digits
    if include_symbols:
        charset += "!@#$%^&*()_+-=[]{}|;:,.<>?"
    
    return charset

def generate_secure_password(length: int, charset: str) -> str:
    """Generate cryptographically secure password."""
    return ''.join(secrets.choice(charset) for _ in range(length))

def store_password_in_s3(password_data: Dict[str, Any], password_name: str) -> str:
    """Store password data in S3 bucket."""
    s3_key = f'passwords/{password_name}.json'
    
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key=s3_key,
        Body=json.dumps(password_data, indent=2),
        ContentType='application/json',
        ServerSideEncryption='AES256',
        Metadata={
            'generator': 'lambda-password-generator',
            'created': datetime.now().isoformat()
        }
    )
    
    return s3_key

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for secure password generation.
    
    Expected event parameters:
    - length (int): Password length (8-128, default: 16)
    - include_uppercase (bool): Include uppercase letters (default: True)
    - include_lowercase (bool): Include lowercase letters (default: True)
    - include_numbers (bool): Include numbers (default: True)
    - include_symbols (bool): Include symbols (default: True)
    - name (str): Custom name for the password (optional)
    """
    try:
        # Parse request parameters from event body or direct event
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
        else:
            body = event
        
        # Extract parameters with defaults
        length = body.get('length', 16)
        include_uppercase = body.get('include_uppercase', True)
        include_lowercase = body.get('include_lowercase', True)
        include_numbers = body.get('include_numbers', True)
        include_symbols = body.get('include_symbols', True)
        password_name = body.get('name', f'password_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
        
        # Validate parameters
        validate_password_parameters(length, include_uppercase, include_lowercase, 
                                   include_numbers, include_symbols)
        
        # Build character set and generate password
        charset = build_character_set(include_uppercase, include_lowercase, 
                                    include_numbers, include_symbols)
        password = generate_secure_password(length, charset)
        
        # Create password metadata
        password_data = {
            'password': password,
            'length': length,
            'created_at': datetime.now().isoformat(),
            'parameters': {
                'include_uppercase': include_uppercase,
                'include_lowercase': include_lowercase,
                'include_numbers': include_numbers,
                'include_symbols': include_symbols
            },
            'metadata': {
                'generator': 'aws-lambda',
                'version': '1.0',
                'bucket': BUCKET_NAME
            }
        }
        
        # Store password in S3
        s3_key = store_password_in_s3(password_data, password_name)
        
        logger.info(f"Password generated and stored successfully: {s3_key}")
        
        # Return success response (without actual password for security)
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Password generated successfully',
                'password_name': password_name,
                's3_key': s3_key,
                'length': length,
                'created_at': password_data['created_at'],
                'bucket': BUCKET_NAME
            }, indent=2)
        }
        
    except ValueError as ve:
        logger.error(f"Validation error: {str(ve)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid parameters',
                'message': str(ve)
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error generating password: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate password'
            })
        }
EOF
    filename = "lambda_function.py"
  }
}

# AWS Lambda function for secure password generation
resource "aws_lambda_function" "password_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # Use source code hash to trigger updates when code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # Environment variables for Lambda function
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.password_storage.id
      ENVIRONMENT = var.environment
      LOG_LEVEL   = "INFO"
    }
  }
  
  # X-Ray tracing configuration (if enabled)
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  # Ensure dependencies are ready before function creation
  depends_on = [
    aws_iam_role_policy.lambda_s3_policy,
    aws_cloudwatch_log_group.lambda_logs,
    aws_s3_bucket.password_storage
  ]

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-lambda-function"
    Description = "Secure password generator using Python secrets module"
  })
}

# Lambda function URL for easy HTTP access (optional, can be enabled via output)
resource "aws_lambda_function_url" "password_generator" {
  function_name      = aws_lambda_function.password_generator.function_name
  authorization_type = "NONE"  # Change to "AWS_IAM" for authenticated access
  
  cors {
    allow_credentials = false
    allow_origins     = ["*"]  # Restrict to specific domains in production
    allow_methods     = ["POST"]
    allow_headers     = ["Content-Type"]
    max_age          = 86400
  }

  depends_on = [aws_lambda_function.password_generator]
}