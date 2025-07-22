# Main Terraform configuration for Computer Vision Solutions with Amazon Rekognition
# This file creates the core infrastructure components

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names
  bucket_name        = "${var.s3_bucket_prefix}-${random_id.suffix.hex}"
  collection_name    = var.face_collection_name != "" ? var.face_collection_name : "face-collection-${random_id.suffix.hex}"
  function_name      = "${var.project_name}-processor-${random_id.suffix.hex}"
  api_name          = "${var.project_name}-api-${random_id.suffix.hex}"
  dynamodb_table    = "${var.project_name}-results-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(var.common_tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  })
}

# S3 Bucket for storing images and analysis results
resource "aws_s3_bucket" "image_storage" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Image storage for computer vision analysis"
    Component   = "Storage"
  })
}

# S3 Bucket versioning configuration
resource "aws_s3_bucket_versioning" "image_storage_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.image_storage.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "image_storage_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.image_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "image_storage_pab" {
  bucket = aws_s3_bucket.image_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "image_storage_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.image_storage.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_days * 2
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 Bucket notification configuration for Lambda trigger
resource "aws_s3_bucket_notification" "image_upload_notification" {
  bucket = aws_s3_bucket.image_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "images/"
    filter_suffix       = ".jpg"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "images/"
    filter_suffix       = ".png"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "images/"
    filter_suffix       = ".jpeg"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# Rekognition Face Collection for face recognition
resource "aws_rekognition_collection" "face_collection" {
  collection_id = local.collection_name

  tags = merge(local.common_tags, {
    Name      = local.collection_name
    Purpose   = "Face recognition collection for computer vision"
    Component = "AI/ML"
  })
}

# DynamoDB table for storing analysis results
resource "aws_dynamodb_table" "analysis_results" {
  count          = var.enable_dynamodb ? 1 : 0
  name           = local.dynamodb_table
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "image_id"
  range_key      = "analysis_type"

  attribute {
    name = "image_id"
    type = "S"
  }

  attribute {
    name = "analysis_type"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name     = "timestamp-index"
    hash_key = "analysis_type"
    range_key = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name      = local.dynamodb_table
    Purpose   = "Store computer vision analysis results"
    Component = "Database"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${random_id.suffix.hex}"

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
    Name      = "${var.project_name}-lambda-role-${random_id.suffix.hex}"
    Purpose   = "Lambda execution role for computer vision processing"
    Component = "Security"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${var.project_name}-lambda-policy-${random_id.suffix.hex}"
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
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.image_storage.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectFaces",
          "rekognition:DetectLabels",
          "rekognition:DetectText",
          "rekognition:DetectModerationLabels",
          "rekognition:IndexFaces",
          "rekognition:SearchFaces",
          "rekognition:SearchFacesByImage",
          "rekognition:ListFaces",
          "rekognition:DeleteFaces"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:CreateCollection",
          "rekognition:DeleteCollection",
          "rekognition:DescribeCollection",
          "rekognition:ListCollections"
        ]
        Resource = aws_rekognition_collection.face_collection.collection_arn
      }
    ]
  })
}

# Additional IAM policy for DynamoDB access (if enabled)
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  count = var.enable_dynamodb ? 1 : 0
  name  = "${var.project_name}-lambda-dynamodb-policy-${random_id.suffix.hex}"
  role  = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.analysis_results[0].arn
      }
    ]
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${local.function_name}"
    Purpose   = "Lambda function logs for computer vision processing"
    Component = "Monitoring"
  })
}

# Lambda function for image processing
resource "aws_lambda_function" "image_processor" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Lambda deployment package (inline code for demonstration)
  filename         = "lambda_function.zip"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME           = aws_s3_bucket.image_storage.bucket
      COLLECTION_NAME       = aws_rekognition_collection.face_collection.collection_id
      DYNAMODB_TABLE        = var.enable_dynamodb ? aws_dynamodb_table.analysis_results[0].name : ""
      ENABLE_FACE_DETECTION = "true"
      ENABLE_OBJECT_DETECTION = "true"
      ENABLE_TEXT_DETECTION = "true"
      ENABLE_MODERATION    = "true"
      MIN_CONFIDENCE       = "75"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name      = local.function_name
    Purpose   = "Process images with Amazon Rekognition"
    Component = "Compute"
  })
}

# Create Lambda deployment package
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name     = aws_s3_bucket.image_storage.bucket
      collection_name = aws_rekognition_collection.face_collection.collection_id
      dynamodb_table  = var.enable_dynamodb ? local.dynamodb_table : ""
    })
    filename = "lambda_function.py"
  }
}

# Lambda function template file
resource "local_file" "lambda_function_template" {
  content = <<EOF
import json
import boto3
import os
from datetime import datetime
import uuid

def lambda_handler(event, context):
    """
    Lambda function to process images with Amazon Rekognition
    Performs face detection, object detection, text detection, and content moderation
    """
    
    # Initialize AWS clients
    rekognition = boto3.client('rekognition')
    s3 = boto3.client('s3')
    
    # Initialize DynamoDB client if table is configured
    dynamodb_table = os.environ.get('DYNAMODB_TABLE')
    if dynamodb_table:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(dynamodb_table)
    
    # Get environment variables
    collection_name = os.environ.get('COLLECTION_NAME')
    min_confidence = float(os.environ.get('MIN_CONFIDENCE', '75'))
    
    # Process each record in the event
    results = []
    
    for record in event['Records']:
        # Extract S3 bucket and object information
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Generate unique image ID
        image_id = str(uuid.uuid4())
        
        print(f"Processing image: s3://{bucket}/{key}")
        
        try:
            # Comprehensive image analysis
            analysis_result = analyze_image_comprehensive(
                rekognition, bucket, key, collection_name, min_confidence
            )
            
            # Add metadata
            analysis_result['image_id'] = image_id
            analysis_result['bucket'] = bucket
            analysis_result['key'] = key
            analysis_result['timestamp'] = datetime.utcnow().isoformat()
            
            # Store results in DynamoDB if configured
            if dynamodb_table:
                store_analysis_results(table, analysis_result)
            
            # Store results in S3
            store_results_s3(s3, bucket, key, analysis_result)
            
            results.append(analysis_result)
            
        except Exception as e:
            error_result = {
                'image_id': image_id,
                'bucket': bucket,
                'key': key,
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            }
            results.append(error_result)
            print(f"Error processing {key}: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(results)} images',
            'results': results
        })
    }

def analyze_image_comprehensive(rekognition, bucket, key, collection_name, min_confidence):
    """
    Perform comprehensive image analysis using multiple Rekognition APIs
    """
    results = {
        'analyses': {}
    }
    
    # Face Detection
    try:
        face_response = rekognition.detect_faces(
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            Attributes=['ALL']
        )
        results['analyses']['faces'] = {
            'count': len(face_response['FaceDetails']),
            'details': face_response['FaceDetails']
        }
    except Exception as e:
        results['analyses']['faces'] = {'error': str(e)}
    
    # Object and Scene Detection
    try:
        label_response = rekognition.detect_labels(
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            MaxLabels=10,
            MinConfidence=min_confidence
        )
        results['analyses']['objects'] = {
            'count': len(label_response['Labels']),
            'labels': label_response['Labels']
        }
    except Exception as e:
        results['analyses']['objects'] = {'error': str(e)}
    
    # Text Detection
    try:
        text_response = rekognition.detect_text(
            Image={'S3Object': {'Bucket': bucket, 'Name': key}}
        )
        text_lines = [t for t in text_response['TextDetections'] if t['Type'] == 'LINE']
        results['analyses']['text'] = {
            'count': len(text_lines),
            'lines': text_lines
        }
    except Exception as e:
        results['analyses']['text'] = {'error': str(e)}
    
    # Content Moderation
    try:
        moderation_response = rekognition.detect_moderation_labels(
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            MinConfidence=60
        )
        results['analyses']['moderation'] = {
            'inappropriate_content': len(moderation_response['ModerationLabels']) > 0,
            'labels': moderation_response['ModerationLabels']
        }
    except Exception as e:
        results['analyses']['moderation'] = {'error': str(e)}
    
    # Face Search (if collection exists and faces were detected)
    try:
        if collection_name and results['analyses']['faces']['count'] > 0:
            search_response = rekognition.search_faces_by_image(
                CollectionId=collection_name,
                Image={'S3Object': {'Bucket': bucket, 'Name': key}},
                FaceMatchThreshold=80,
                MaxFaces=5
            )
            results['analyses']['face_matches'] = {
                'count': len(search_response['FaceMatches']),
                'matches': search_response['FaceMatches']
            }
    except Exception as e:
        results['analyses']['face_matches'] = {'error': str(e)}
    
    return results

def store_analysis_results(table, analysis_result):
    """
    Store analysis results in DynamoDB table
    """
    try:
        # Store main analysis record
        table.put_item(
            Item={
                'image_id': analysis_result['image_id'],
                'analysis_type': 'comprehensive',
                'timestamp': analysis_result['timestamp'],
                'bucket': analysis_result['bucket'],
                'key': analysis_result['key'],
                'analyses': analysis_result['analyses']
            }
        )
        
        # Store individual analysis type records for querying
        for analysis_type, analysis_data in analysis_result['analyses'].items():
            table.put_item(
                Item={
                    'image_id': analysis_result['image_id'],
                    'analysis_type': analysis_type,
                    'timestamp': analysis_result['timestamp'],
                    'bucket': analysis_result['bucket'],
                    'key': analysis_result['key'],
                    'data': analysis_data
                }
            )
    except Exception as e:
        print(f"Error storing in DynamoDB: {str(e)}")

def store_results_s3(s3, bucket, original_key, analysis_result):
    """
    Store analysis results in S3 as JSON files
    """
    try:
        # Create results key
        results_key = f"results/{analysis_result['image_id']}-analysis.json"
        
        # Store results in S3
        s3.put_object(
            Bucket=bucket,
            Key=results_key,
            Body=json.dumps(analysis_result, indent=2, default=str),
            ContentType='application/json'
        )
    except Exception as e:
        print(f"Error storing results in S3: {str(e)}")
EOF
  filename = "${path.module}/lambda_function.py.tpl"
}

# Lambda permission to allow S3 to invoke the function
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_storage.arn
}

# API Gateway for Lambda function (if enabled)
resource "aws_api_gateway_rest_api" "computer_vision_api" {
  count       = var.enable_api_gateway ? 1 : 0
  name        = local.api_name
  description = "API Gateway for Computer Vision Solutions"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name      = local.api_name
    Purpose   = "API Gateway for computer vision processing"
    Component = "API"
  })
}

# API Gateway resource
resource "aws_api_gateway_resource" "analyze_resource" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.computer_vision_api[0].id
  parent_id   = aws_api_gateway_rest_api.computer_vision_api[0].root_resource_id
  path_part   = "analyze"
}

# API Gateway method
resource "aws_api_gateway_method" "analyze_method" {
  count         = var.enable_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.computer_vision_api[0].id
  resource_id   = aws_api_gateway_resource.analyze_resource[0].id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway integration
resource "aws_api_gateway_integration" "lambda_integration" {
  count                   = var.enable_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.computer_vision_api[0].id
  resource_id             = aws_api_gateway_resource.analyze_resource[0].id
  http_method             = aws_api_gateway_method.analyze_method[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.image_processor.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "allow_api_gateway" {
  count         = var.enable_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.computer_vision_api[0].execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  count       = var.enable_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.computer_vision_api[0].id
  stage_name  = var.api_gateway_stage_name

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# SNS Topic for notifications (if enabled)
resource "aws_sns_topic" "analysis_notifications" {
  count = var.enable_sns_notifications ? 1 : 0
  name  = "${var.project_name}-notifications-${random_id.suffix.hex}"

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-notifications-${random_id.suffix.hex}"
    Purpose   = "SNS notifications for computer vision analysis"
    Component = "Messaging"
  })
}

# SNS Topic subscription
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.analysis_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# VPC Endpoint for S3 (if enabled)
resource "aws_vpc_endpoint" "s3_endpoint" {
  count           = var.enable_vpc_endpoint ? 1 : 0
  vpc_id          = var.vpc_id
  service_name    = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = var.route_table_ids

  tags = merge(local.common_tags, {
    Name      = "${var.project_name}-s3-endpoint-${random_id.suffix.hex}"
    Purpose   = "VPC endpoint for S3 access"
    Component = "Networking"
  })
}