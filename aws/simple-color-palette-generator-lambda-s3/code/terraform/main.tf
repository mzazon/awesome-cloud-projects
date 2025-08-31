# Simple Color Palette Generator with Lambda and S3
# This Terraform configuration deploys a serverless color palette generator
# that creates random, aesthetically pleasing color combinations on demand

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  bucket_name     = "${var.project_name}-palettes-${local.resource_suffix}"
  function_name   = "${var.project_name}-${local.resource_suffix}"
  role_name       = "${var.project_name}-role-${local.resource_suffix}"

  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "simple-color-palette-generator-lambda-s3"
  })
}

# S3 Bucket for storing generated color palettes
# Provides highly durable object storage with 99.999999999% (11 9's) durability
resource "aws_s3_bucket" "palette_storage" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = "Color Palette Storage"
    Description = "Storage for generated color palette JSON files"
  })
}

# S3 Bucket versioning configuration for palette history tracking
resource "aws_s3_bucket_versioning" "palette_storage_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.palette_storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption for data security
resource "aws_s3_bucket_server_side_encryption_configuration" "palette_storage_encryption" {
  bucket = aws_s3_bucket.palette_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block for security
resource "aws_s3_bucket_public_access_block" "palette_storage_pab" {
  bucket = aws_s3_bucket.palette_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for Lambda function execution
# Follows the principle of least privilege for security
resource "aws_iam_role" "lambda_execution_role" {
  name = local.role_name

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
    Name        = "Lambda Execution Role"
    Description = "IAM role for color palette generator Lambda function"
  })
}

# Attach basic Lambda execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom IAM policy for S3 access
# Grants only necessary permissions for the specific bucket
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "${local.role_name}-s3-policy"
  description = "IAM policy for Lambda function to access S3 palette storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.palette_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.palette_storage.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "Lambda S3 Access Policy"
    Description = "Custom policy for S3 bucket access"
  })
}

# Attach S3 policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Group for Lambda function (optional)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "Lambda Log Group"
    Description = "CloudWatch logs for color palette generator function"
  })
}

# Create Lambda function deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name = aws_s3_bucket.palette_storage.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for color palette generation
# Uses proven color theory algorithms to create harmonious color combinations
resource "aws_lambda_function" "palette_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.palette_storage.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_access,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name        = "Color Palette Generator"
    Description = "Serverless function to generate color palettes using color theory"
  })
}

# Lambda Function URL for direct HTTP access
# Provides simple HTTPS endpoint without API Gateway complexity
resource "aws_lambda_function_url" "palette_generator_url" {
  function_name      = aws_lambda_function.palette_generator.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = var.cors_allowed_origins
    allow_methods     = var.cors_allowed_methods
    allow_headers     = var.cors_allowed_headers
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}

# Resource-based policy for Lambda Function URL public access
resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "AllowPublicAccess"
  action                = "lambda:InvokeFunctionUrl"
  function_name         = aws_lambda_function.palette_generator.function_name
  principal             = "*"
  function_url_auth_type = "NONE"
}

# Create the Lambda function Python code template
resource "local_file" "lambda_function_template" {
  content = <<-EOT
import json
import random
import colorsys
import boto3
import os
from datetime import datetime
import uuid

# Initialize S3 client
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # Get bucket name from environment variable
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Bucket name not configured'})
        }
    
    try:
        # Generate color palette based on requested type
        query_params = event.get('queryStringParameters') or {}
        palette_type = query_params.get('type', 'complementary')
        palette = generate_color_palette(palette_type)
        
        # Store palette in S3
        palette_id = str(uuid.uuid4())[:8]
        s3_key = f"palettes/{palette_id}.json"
        
        palette_data = {
            'id': palette_id,
            'type': palette_type,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'hex_colors': [rgb_to_hex(color) for color in palette]
        }
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(palette_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(palette_data)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def generate_color_palette(palette_type):
    """Generate color palette based on color theory"""
    base_hue = random.uniform(0, 1)
    saturation = random.uniform(0.6, 0.9)
    lightness = random.uniform(0.4, 0.8)
    
    colors = []
    
    if palette_type == 'complementary':
        # Base color and its complement
        colors.append(hsv_to_rgb(base_hue, saturation, lightness))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation, lightness))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.7, lightness * 1.2))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation * 0.7, lightness * 1.2))
        
    elif palette_type == 'analogous':
        # Colors adjacent on color wheel
        for i in range(5):
            hue = (base_hue + (i * 0.08)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
            
    elif palette_type == 'triadic':
        # Three colors evenly spaced on color wheel
        for i in range(3):
            hue = (base_hue + (i * 0.333)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
        # Add two supporting colors
        colors.append(hsv_to_rgb(base_hue, saturation * 0.5, min(lightness * 1.3, 1.0)))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.3, lightness * 0.9))
        
    else:  # Random palette
        for i in range(5):
            hue = random.uniform(0, 1)
            sat = random.uniform(0.5, 0.9)
            light = random.uniform(0.3, 0.8)
            colors.append(hsv_to_rgb(hue, sat, light))
    
    return colors

def hsv_to_rgb(h, s, v):
    """Convert HSV color to RGB"""
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return [int(r * 255), int(g * 255), int(b * 255)]

def rgb_to_hex(rgb):
    """Convert RGB to hex color code"""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"
EOT

  filename = "${path.module}/lambda_function.py.tpl"
}