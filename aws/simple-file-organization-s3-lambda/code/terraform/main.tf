# Generate random suffix for globally unique S3 bucket name
resource "random_string" "bucket_suffix" {
  length  = 6
  upper   = false
  special = false
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# S3 bucket for file organization
resource "aws_s3_bucket" "file_organizer" {
  bucket = "${var.bucket_name_prefix}-${random_string.bucket_suffix.result}"

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "File Organizer Bucket"
    Description = "S3 bucket for automated file organization using Lambda"
  }
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "file_organizer" {
  bucket = aws_s3_bucket.file_organizer.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "file_organizer" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.file_organizer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "file_organizer" {
  bucket = aws_s3_bucket.file_organizer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create organization folders in S3 bucket with placeholder files
resource "aws_s3_object" "organization_folders" {
  for_each = toset(var.organization_folders)
  
  bucket       = aws_s3_bucket.file_organizer.id
  key          = "${each.value}/.gitkeep"
  content      = "${title(each.value)} files will be stored here"
  content_type = "text/plain"

  tags = {
    Name        = "${title(each.value)} Folder"
    Description = "Placeholder file for ${each.value} organization folder"
  }
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "File Organizer Lambda Logs"
    Description = "CloudWatch log group for file organization Lambda function"
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.function_name}-execution-role"

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
    Name        = "File Organizer Lambda Execution Role"
    Description = "IAM role for Lambda function execution with S3 and CloudWatch permissions"
  }
}

# IAM policy for Lambda to access S3 bucket
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.function_name}-s3-policy"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "${aws_s3_bucket.file_organizer.arn}/*"
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from urllib.parse import unquote_plus

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to automatically organize uploaded files by type.
    
    Processes S3 event notifications and moves files into appropriate folders
    based on their file extensions.
    """
    
    # Process each S3 event record
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Skip if file is already in an organized folder
        if '/' in key and key.split('/')[0] in ['images', 'documents', 'videos', 'other']:
            print(f"File {key} is already organized, skipping")
            continue
        
        # Skip .gitkeep files used for folder structure
        if key.endswith('/.gitkeep'):
            print(f"Skipping folder placeholder file: {key}")
            continue
        
        # Determine file type based on extension
        file_extension = key.lower().split('.')[-1] if '.' in key else ''
        folder = get_folder_for_extension(file_extension)
        
        # Create new key with folder structure
        new_key = f"{folder}/{key}"
        
        try:
            # Copy object to new location
            s3_client.copy_object(
                Bucket=bucket,
                CopySource={'Bucket': bucket, 'Key': key},
                Key=new_key
            )
            
            # Delete original object
            s3_client.delete_object(Bucket=bucket, Key=key)
            
            print(f"Successfully moved {key} to {new_key}")
            
        except Exception as e:
            print(f"Error moving {key}: {str(e)}")
            # Return error to trigger retry mechanism
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('File organization completed successfully')
    }

def get_folder_for_extension(extension):
    """
    Determine the appropriate folder based on file extension.
    
    Args:
        extension (str): File extension (without dot)
    
    Returns:
        str: Folder name for the file type
    """
    # Define file type mappings
    image_extensions = [
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'svg', 'webp', 
        'ico', 'psd', 'raw', 'cr2', 'nef', 'orf', 'sr2'
    ]
    
    document_extensions = [
        'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'xls', 'xlsx', 
        'ppt', 'pptx', 'csv', 'json', 'xml', 'md', 'html', 'htm',
        'pages', 'numbers', 'key', 'epub', 'mobi'
    ]
    
    video_extensions = [
        'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v',
        '3gp', 'ogv', 'ts', 'vob', 'rm', 'rmvb', 'asf'
    ]
    
    # Categorize file based on extension
    if extension in image_extensions:
        return 'images'
    elif extension in document_extensions:
        return 'documents'
    elif extension in video_extensions:
        return 'videos'
    else:
        return 'other'
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function for file organization
resource "aws_lambda_function" "file_organizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Environment variables for Lambda function
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.file_organizer.id
      LOG_LEVEL   = "INFO"
    }
  }

  # Ensure CloudWatch log group exists before Lambda function
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = {
    Name        = "File Organizer Lambda"
    Description = "Lambda function for automatic file organization in S3"
  }
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_organizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.file_organizer.arn}"
}

# S3 bucket notification configuration to trigger Lambda
resource "aws_s3_bucket_notification" "file_organizer_notification" {
  bucket = aws_s3_bucket.file_organizer.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.file_organizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}