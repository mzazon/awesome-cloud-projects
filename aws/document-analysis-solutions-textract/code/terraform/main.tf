# main.tf - Main infrastructure configuration for Amazon Textract document analysis

# Data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local variables
locals {
  resource_suffix = random_string.suffix.result
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

#################
# S3 Buckets
#################

# Input bucket for documents to be processed
resource "aws_s3_bucket" "input_bucket" {
  bucket        = "${var.project_name}-input-${local.resource_suffix}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-input-${local.resource_suffix}"
    Type = "input"
  })
}

# Output bucket for processed documents
resource "aws_s3_bucket" "output_bucket" {
  bucket        = "${var.project_name}-output-${local.resource_suffix}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-output-${local.resource_suffix}"
    Type = "output"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "input_bucket_versioning" {
  bucket = aws_s3_bucket.input_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "output_bucket_versioning" {
  bucket = aws_s3_bucket.output_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block (security best practice)
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
    id     = "delete_old_objects"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "output_bucket_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    id     = "delete_old_objects"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

#################
# SNS Topic
#################

# SNS topic for notifications
resource "aws_sns_topic" "textract_notifications" {
  name = "${var.project_name}-notifications-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notifications-${local.resource_suffix}"
  })
}

# SNS topic policy to allow Lambda to publish
resource "aws_sns_topic_policy" "textract_notifications_policy" {
  arn = aws_sns_topic.textract_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.textract_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.sns_email_subscription != "" ? 1 : 0
  topic_arn = aws_sns_topic.textract_notifications.arn
  protocol  = "email"
  endpoint  = var.sns_email_subscription
}

#################
# IAM Role and Policies
#################

# IAM role for Lambda function
resource "aws_iam_role" "textract_lambda_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"

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
    Name = "${var.project_name}-lambda-role-${local.resource_suffix}"
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.textract_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach AWS managed policy for Textract access
resource "aws_iam_role_policy_attachment" "textract_full_access" {
  role       = aws_iam_role.textract_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
}

# Custom IAM policy for S3 and SNS access
resource "aws_iam_role_policy" "textract_lambda_policy" {
  name = "${var.project_name}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.textract_lambda_role.id

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
        Resource = [
          "${aws_s3_bucket.input_bucket.arn}/*",
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.textract_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-processor-${local.resource_suffix}:*"
      }
    ]
  })
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "xray_write_only_access" {
  count      = var.enable_xray_tracing ? 1 : 0
  role       = aws_iam_role.textract_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

#################
# Lambda Function
#################

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-processor-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${var.project_name}-processor-${local.resource_suffix}"
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/textract_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      feature_types = jsonencode(var.textract_feature_types)
    })
    filename = "lambda_function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "textract_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-processor-${local.resource_suffix}"
  role            = aws_iam_role.textract_lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET    = aws_s3_bucket.output_bucket.bucket
      SNS_TOPIC_ARN    = aws_sns_topic.textract_notifications.arn
      FEATURE_TYPES    = jsonencode(var.textract_feature_types)
      LOG_LEVEL        = "INFO"
    }
  }

  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.textract_lambda_policy
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-processor-${local.resource_suffix}"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

#################
# S3 Event Notification
#################

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "input_bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  dynamic "lambda_function" {
    for_each = var.allowed_file_extensions
    content {
      lambda_function_arn = aws_lambda_function.textract_processor.arn
      events              = ["s3:ObjectCreated:*"]
      filter_suffix       = lambda_function.value
    }
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

#################
# Lambda Function Template
#################

# Create Lambda function template file
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
textract = boto3.client('textract')
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing documents with Amazon Textract
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Dictionary with processing results
    """
    try:
        # Parse S3 event
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        object_key = s3_event['object']['key']
        
        logger.info(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Validate file extension
        if not is_valid_file_extension(object_key):
            logger.warning(f"Skipping file with unsupported extension: {object_key}")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'File extension not supported'})
            }
        
        # Get feature types from environment
        feature_types = json.loads(os.environ.get('FEATURE_TYPES', '${feature_types}'))
        
        # Analyze document with Textract
        response = analyze_document(bucket_name, object_key, feature_types)
        
        # Extract and structure data
        extracted_data = extract_structured_data(response, object_key)
        
        # Save results to output bucket
        output_location = save_results(extracted_data, object_key)
        
        # Send success notification
        send_notification(
            f"Document processed successfully: {object_key}",
            "Textract Processing Complete",
            success=True
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'output_location': output_location,
                'document': object_key
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        
        # Send error notification
        send_notification(
            f"Error processing {object_key}: {str(e)}",
            "Textract Processing Error",
            success=False
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'document': object_key
            })
        }

def is_valid_file_extension(filename: str) -> bool:
    """Check if file has a valid extension for Textract processing"""
    valid_extensions = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff']
    return any(filename.lower().endswith(ext) for ext in valid_extensions)

def analyze_document(bucket_name: str, object_key: str, feature_types: List[str]) -> Dict[str, Any]:
    """
    Analyze document using Amazon Textract
    
    Args:
        bucket_name: S3 bucket name
        object_key: S3 object key
        feature_types: List of Textract feature types
        
    Returns:
        Textract analysis response
    """
    try:
        # Prepare analyze request
        analyze_request = {
            'Document': {
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            'FeatureTypes': feature_types
        }
        
        # Add queries if QUERIES is in feature types
        if 'QUERIES' in feature_types:
            analyze_request['QueriesConfig'] = {
                'Queries': [
                    {'Text': 'What is the document type?'},
                    {'Text': 'What is the total amount?'},
                    {'Text': 'What is the date?'},
                    {'Text': 'What is the invoice number?'},
                    {'Text': 'Who is the customer?'}
                ]
            }
        
        # Call Textract
        response = textract.analyze_document(**analyze_request)
        logger.info(f"Textract analysis completed for {object_key}")
        
        return response
        
    except Exception as e:
        logger.error(f"Error in Textract analysis: {str(e)}")
        raise

def extract_structured_data(response: Dict[str, Any], object_key: str) -> Dict[str, Any]:
    """
    Extract and structure data from Textract response
    
    Args:
        response: Textract analyze_document response
        object_key: Original document key
        
    Returns:
        Structured data dictionary
    """
    extracted_data = {
        'document_name': object_key,
        'processed_at': datetime.now().isoformat(),
        'document_metadata': response.get('DocumentMetadata', {}),
        'blocks': response.get('Blocks', []),
        'analysis_summary': {
            'total_blocks': len(response.get('Blocks', [])),
            'text_blocks': len([b for b in response.get('Blocks', []) if b.get('BlockType') == 'LINE']),
            'table_blocks': len([b for b in response.get('Blocks', []) if b.get('BlockType') == 'TABLE']),
            'form_blocks': len([b for b in response.get('Blocks', []) if b.get('BlockType') == 'KEY_VALUE_SET'])
        }
    }
    
    # Extract key-value pairs if available
    key_value_pairs = extract_key_value_pairs(response.get('Blocks', []))
    if key_value_pairs:
        extracted_data['key_value_pairs'] = key_value_pairs
    
    # Extract tables if available
    tables = extract_tables(response.get('Blocks', []))
    if tables:
        extracted_data['tables'] = tables
    
    # Extract query results if available
    query_results = extract_query_results(response.get('Blocks', []))
    if query_results:
        extracted_data['query_results'] = query_results
    
    return extracted_data

def extract_key_value_pairs(blocks: List[Dict[str, Any]]) -> Dict[str, str]:
    """Extract form key-value pairs from Textract blocks"""
    key_map = {}
    value_map = {}
    block_map = {block['Id']: block for block in blocks}
    
    for block in blocks:
        if block.get('BlockType') == 'KEY_VALUE_SET':
            if 'KEY' in block.get('EntityTypes', []):
                key_map[block['Id']] = block
            elif 'VALUE' in block.get('EntityTypes', []):
                value_map[block['Id']] = block
    
    key_value_pairs = {}
    for key_id, key_block in key_map.items():
        value_block = find_value_block(key_block, value_map)
        key_text = get_text_from_block(key_block, block_map)
        value_text = get_text_from_block(value_block, block_map) if value_block else ""
        
        if key_text:
            key_value_pairs[key_text] = value_text
    
    return key_value_pairs

def extract_tables(blocks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Extract table data from Textract blocks"""
    tables = []
    block_map = {block['Id']: block for block in blocks}
    
    for block in blocks:
        if block.get('BlockType') == 'TABLE':
            table_data = {
                'table_id': block['Id'],
                'confidence': block.get('Confidence', 0),
                'rows': []
            }
            
            # Extract table cells
            cells = get_table_cells(block, block_map)
            rows = organize_cells_into_rows(cells, block_map)
            table_data['rows'] = rows
            
            tables.append(table_data)
    
    return tables

def extract_query_results(blocks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Extract query results from Textract blocks"""
    query_results = []
    
    for block in blocks:
        if block.get('BlockType') == 'QUERY_RESULT':
            query_results.append({
                'query_id': block['Id'],
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
    
    return query_results

def find_value_block(key_block: Dict[str, Any], value_map: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    """Find the value block associated with a key block"""
    for relationship in key_block.get('Relationships', []):
        if relationship['Type'] == 'VALUE':
            for value_id in relationship['Ids']:
                if value_id in value_map:
                    return value_map[value_id]
    return None

def get_text_from_block(block: Dict[str, Any], block_map: Dict[str, Dict[str, Any]]) -> str:
    """Extract text from a block using its relationships"""
    if not block:
        return ""
    
    text = ""
    for relationship in block.get('Relationships', []):
        if relationship['Type'] == 'CHILD':
            for child_id in relationship['Ids']:
                child_block = block_map.get(child_id)
                if child_block and child_block.get('BlockType') == 'WORD':
                    text += child_block.get('Text', '') + ' '
    
    return text.strip()

def get_table_cells(table_block: Dict[str, Any], block_map: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Get all cells for a table"""
    cells = []
    for relationship in table_block.get('Relationships', []):
        if relationship['Type'] == 'CHILD':
            for cell_id in relationship['Ids']:
                cell_block = block_map.get(cell_id)
                if cell_block and cell_block.get('BlockType') == 'CELL':
                    cells.append(cell_block)
    return cells

def organize_cells_into_rows(cells: List[Dict[str, Any]], block_map: Dict[str, Dict[str, Any]]) -> List[List[str]]:
    """Organize cells into rows based on row and column indices"""
    rows_dict = {}
    
    for cell in cells:
        row_index = cell.get('RowIndex', 0)
        col_index = cell.get('ColumnIndex', 0)
        cell_text = get_text_from_block(cell, block_map)
        
        if row_index not in rows_dict:
            rows_dict[row_index] = {}
        
        rows_dict[row_index][col_index] = cell_text
    
    # Convert to ordered list
    ordered_rows = []
    for row_index in sorted(rows_dict.keys()):
        row_data = []
        for col_index in sorted(rows_dict[row_index].keys()):
            row_data.append(rows_dict[row_index][col_index])
        ordered_rows.append(row_data)
    
    return ordered_rows

def save_results(extracted_data: Dict[str, Any], object_key: str) -> str:
    """
    Save processing results to S3 output bucket
    
    Args:
        extracted_data: Structured data from Textract
        object_key: Original document key
        
    Returns:
        S3 URL of saved results
    """
    try:
        output_bucket = os.environ['OUTPUT_BUCKET']
        output_key = f"processed/{object_key.split('/')[-1]}.json"
        
        s3.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2, default=str),
            ContentType='application/json'
        )
        
        output_location = f"s3://{output_bucket}/{output_key}"
        logger.info(f"Results saved to: {output_location}")
        
        return output_location
        
    except Exception as e:
        logger.error(f"Error saving results: {str(e)}")
        raise

def send_notification(message: str, subject: str, success: bool = True) -> None:
    """
    Send notification via SNS
    
    Args:
        message: Notification message
        subject: Message subject
        success: Whether this is a success or error notification
    """
    try:
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject=subject
        )
        
        logger.info(f"Notification sent: {subject}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        # Don't raise here as notification failure shouldn't fail the main process
EOF
}