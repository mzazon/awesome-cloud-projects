# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      CreatedBy   = "terraform-automl-forecasting"
    },
    var.additional_tags
  )
}

# KMS Key for encryption
resource "aws_kms_key" "forecasting_key" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for AutoML forecasting resources"
  deletion_window_in_days = var.kms_key_deletion_window
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key-${local.name_suffix}"
  })
}

resource "aws_kms_alias" "forecasting_key_alias" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-forecasting-${local.name_suffix}"
  target_key_id = aws_kms_key.forecasting_key[0].key_id
}

# S3 Bucket for storing training data and model artifacts
resource "aws_s3_bucket" "forecasting_bucket" {
  bucket        = "${local.name_prefix}-bucket-${local.name_suffix}"
  force_destroy = var.s3_bucket_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bucket-${local.name_suffix}"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "forecasting_bucket_versioning" {
  bucket = aws_s3_bucket.forecasting_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "forecasting_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.forecasting_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.forecasting_key[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "forecasting_bucket_pab" {
  bucket = aws_s3_bucket.forecasting_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy
resource "aws_s3_bucket_policy" "forecasting_bucket_policy" {
  bucket = aws_s3_bucket.forecasting_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.forecasting_bucket.arn,
          "${aws_s3_bucket.forecasting_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# IAM Role for SageMaker
resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${local.name_prefix}-sagemaker-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for SageMaker
resource "aws_iam_role_policy_attachment" "sagemaker_execution_role_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Custom IAM policy for S3 access
resource "aws_iam_policy" "sagemaker_s3_policy" {
  name        = "${local.name_prefix}-sagemaker-s3-policy-${local.name_suffix}"
  description = "Custom S3 policy for SageMaker AutoML forecasting"

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
          aws_s3_bucket.forecasting_bucket.arn,
          "${aws_s3_bucket.forecasting_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.forecasting_key[0].arn] : []
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_s3_policy_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_s3_policy.arn
}

# SageMaker Model Package Group for versioning
resource "aws_sagemaker_model_package_group" "forecasting_model_group" {
  model_package_group_name        = "${local.name_prefix}-model-group-${local.name_suffix}"
  model_package_group_description = "Model package group for AutoML forecasting models"

  tags = local.common_tags
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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

  tags = local.common_tags
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom Lambda policy for SageMaker access
resource "aws_iam_policy" "lambda_sagemaker_policy" {
  name        = "${local.name_prefix}-lambda-sagemaker-policy-${local.name_suffix}"
  description = "Policy for Lambda to invoke SageMaker endpoints"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint"
        ]
        Resource = "arn:aws:sagemaker:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:endpoint/${local.name_prefix}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.forecasting_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sagemaker_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_sagemaker_policy.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.name_prefix}-forecast-api-${local.name_suffix}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.forecasting_key[0].arn : null

  tags = local.common_tags
}

# Lambda function for forecast API
resource "aws_lambda_function" "forecast_api" {
  filename         = "forecast_api.zip"
  function_name    = "${local.name_prefix}-forecast-api-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SAGEMAKER_ENDPOINT_NAME = "${local.name_prefix}-endpoint-${local.name_suffix}"
      S3_BUCKET_NAME          = aws_s3_bucket.forecasting_bucket.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_sagemaker_policy_attachment,
    aws_cloudwatch_log_group.lambda_log_group,
  ]

  tags = local.common_tags
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "forecast_api.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      # Template variables if needed
    })
    filename = "lambda_function.py"
  }
}

# Lambda function source code template
resource "local_file" "lambda_function_template" {
  content = <<-EOT
import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to provide real-time forecasting API
    """
    try:
        # Parse request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        item_id = body.get('item_id')
        forecast_horizon = int(body.get('forecast_horizon', ${var.forecast_horizon}))
        
        if not item_id:
            logger.error("Missing item_id in request")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'item_id is required'})
            }
        
        # Initialize SageMaker runtime
        runtime = boto3.client('sagemaker-runtime')
        
        # Get endpoint name from environment
        endpoint_name = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
        
        if not endpoint_name:
            logger.error("SAGEMAKER_ENDPOINT_NAME environment variable not set")
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Endpoint not configured'})
            }
        
        # Prepare inference request with mock data (in production, fetch real historical data)
        inference_data = {
            'instances': [
                {
                    'start': '2023-01-01',
                    'target': [100 + i * 0.1 for i in range(365)],  # Mock historical data
                    'item_id': item_id
                }
            ],
            'configuration': {
                'num_samples': 100,
                'output_types': ['mean', 'quantiles'],
                'quantiles': ${jsonencode(var.forecast_quantiles)}
            }
        }
        
        logger.info(f"Making prediction for item_id: {item_id}")
        
        # Make prediction
        response = runtime.invoke_endpoint(
            EndpointName=endpoint_name,
            ContentType='application/json',
            Body=json.dumps(inference_data)
        )
        
        # Parse response
        result = json.loads(response['Body'].read().decode())
        
        # Format response
        forecast_response = {
            'item_id': item_id,
            'forecast_horizon': forecast_horizon,
            'forecast': result.get('predictions', [{}])[0],
            'generated_at': datetime.now().isoformat(),
            'model_type': 'SageMaker AutoML',
            'confidence_intervals': True,
            'quantiles': ${jsonencode(var.forecast_quantiles)}
        }
        
        logger.info(f"Successfully generated forecast for item_id: {item_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
            },
            'body': json.dumps(forecast_response)
        }
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error'
            })
        }
EOT
  filename = "${path.module}/lambda_function.py.tpl"
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "forecast_api" {
  name        = "${local.name_prefix}-forecast-api-${local.name_suffix}"
  description = "API Gateway for AutoML forecasting service"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway Resource
resource "aws_api_gateway_resource" "forecast_resource" {
  rest_api_id = aws_api_gateway_rest_api.forecast_api.id
  parent_id   = aws_api_gateway_rest_api.forecast_api.root_resource_id
  path_part   = "forecast"
}

# API Gateway Method
resource "aws_api_gateway_method" "forecast_method" {
  rest_api_id   = aws_api_gateway_rest_api.forecast_api.id
  resource_id   = aws_api_gateway_resource.forecast_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration
resource "aws_api_gateway_integration" "forecast_integration" {
  rest_api_id = aws_api_gateway_rest_api.forecast_api.id
  resource_id = aws_api_gateway_resource.forecast_resource.id
  http_method = aws_api_gateway_method.forecast_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.forecast_api.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.forecast_api.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.forecast_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "forecast_deployment" {
  depends_on = [
    aws_api_gateway_method.forecast_method,
    aws_api_gateway_integration.forecast_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.forecast_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.forecast_resource.id,
      aws_api_gateway_method.forecast_method.id,
      aws_api_gateway_integration.forecast_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "forecast_stage" {
  deployment_id = aws_api_gateway_deployment.forecast_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.forecast_api.id
  stage_name    = var.api_gateway_stage_name

  access_log_settings {
    destination_arn = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].arn : null
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      caller        = "$context.identity.caller"
      user          = "$context.identity.user"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      resourcePath  = "$context.resourcePath"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = local.common_tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${local.name_prefix}-forecast-api-${local.name_suffix}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.forecasting_key[0].arn : null

  tags = local.common_tags
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "forecasting_dashboard" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-dashboard-${local.name_suffix}"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.forecast_api.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Metrics"
          period  = 300
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
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.forecast_api.name],
            [".", "Latency", ".", "."],
            [".", "4XXError", ".", "."],
            [".", "5XXError", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "API Gateway Metrics"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.forecast_api.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-api-gateway-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.forecast_api.name
  }

  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  count = var.enable_monitoring ? 1 : 0
  name  = "${local.name_prefix}-alerts-${local.name_suffix}"

  tags = local.common_tags
}

# Sample data generation script (stored in S3)
resource "aws_s3_object" "sample_data_script" {
  count  = var.generate_sample_data ? 1 : 0
  bucket = aws_s3_bucket.forecasting_bucket.bucket
  key    = "scripts/generate_sample_data.py"
  
  content = templatefile("${path.module}/generate_sample_data.py.tpl", {
    num_items = var.sample_data_items
    num_days  = var.sample_data_days
  })

  tags = local.common_tags
}

# Sample data generation script template
resource "local_file" "sample_data_script_template" {
  count = var.generate_sample_data ? 1 : 0
  
  content = <<-EOT
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import boto3

def generate_sample_data():
    """Generate sample e-commerce sales data for AutoML training"""
    
    # Set random seed for reproducibility
    np.random.seed(42)
    random.seed(42)
    
    # Configuration
    num_items = ${var.sample_data_items}
    num_days = ${var.sample_data_days}
    
    # Generate date range
    start_date = datetime(2021, 1, 1)
    end_date = start_date + timedelta(days=num_days)
    dates = pd.date_range(start=start_date, end=end_date, freq='D')
    
    # Define product categories
    categories = ['electronics', 'clothing', 'home', 'sports', 'books']
    regions = ['North', 'South', 'East', 'West', 'Central']
    
    data = []
    
    for item_idx in range(num_items):
        category = random.choice(categories)
        region = random.choice(regions)
        item_id = f"{category}_item_{item_idx:03d}_{region}"
        
        # Base demand characteristics
        base_demand = np.random.uniform(50, 150)
        seasonality_strength = np.random.uniform(0.2, 0.6)
        trend_strength = np.random.uniform(-0.01, 0.03)
        
        # Generate time series
        for i, date in enumerate(dates):
            # Seasonal patterns
            annual_season = seasonality_strength * np.sin(2 * np.pi * i / 365)
            weekly_pattern = 0.3 * np.sin(2 * np.pi * i / 7)
            
            # Trend
            trend = trend_strength * i
            
            # Random promotions
            promotion = 1 if random.random() < 0.05 else 0
            promotion_boost = 0.5 if promotion else 0
            
            # Holiday effects (simplified)
            is_holiday = 1 if date.month == 12 and date.day in [24, 25, 31] else 0
            holiday_boost = 0.8 if is_holiday else 0
            
            # Calculate demand
            demand = base_demand * (1 + annual_season + weekly_pattern + 
                                  trend + promotion_boost + holiday_boost) + np.random.normal(0, 5)
            
            demand = max(0, demand)  # Ensure non-negative
            
            data.append({
                'timestamp': date.strftime('%Y-%m-%d'),
                'target_value': round(demand, 2),
                'item_id': item_id,
                'category': category,
                'region': region,
                'promotion': promotion,
                'is_holiday': is_holiday,
                'day_of_week': date.weekday(),
                'month': date.month,
                'quarter': (date.month - 1) // 3 + 1
            })
    
    df = pd.DataFrame(data)
    df = df.sort_values(['item_id', 'timestamp'])
    
    return df

def upload_to_s3(df, bucket_name):
    """Upload dataset to S3"""
    
    # Save training dataset
    train_file = 'ecommerce_sales_data.csv'
    df.to_csv(train_file, index=False)
    
    # Upload to S3
    s3_client = boto3.client('s3')
    
    # Upload full dataset
    s3_client.upload_file(
        train_file, 
        bucket_name, 
        '${var.training_data_s3_prefix}/ecommerce_sales_data.csv'
    )
    
    # Create train/validation split for AutoML
    unique_dates = sorted(df['timestamp'].unique())
    split_date = unique_dates[int(len(unique_dates) * 0.8)]
    
    train_data = df[df['timestamp'] <= split_date]
    val_data = df[df['timestamp'] > split_date]
    
    # Save and upload training data
    train_data.to_csv('automl_train_data.csv', index=False)
    s3_client.upload_file(
        'automl_train_data.csv',
        bucket_name,
        'automl-data/train/automl_train_data.csv'
    )
    
    # Save and upload validation data
    val_data.to_csv('automl_validation_data.csv', index=False)
    s3_client.upload_file(
        'automl_validation_data.csv',
        bucket_name,
        'automl-data/validation/automl_validation_data.csv'
    )
    
    print(f"Generated and uploaded {len(df)} rows of sales data")
    print(f"Training data: {len(train_data)} rows")
    print(f"Validation data: {len(val_data)} rows")
    print(f"Date range: {df['timestamp'].min()} to {df['timestamp'].max()}")

if __name__ == "__main__":
    # Generate sample data
    df = generate_sample_data()
    
    # Upload to S3 (bucket name would be passed as environment variable)
    bucket_name = "${aws_s3_bucket.forecasting_bucket.bucket}"
    upload_to_s3(df, bucket_name)
EOT
  filename = "${path.module}/generate_sample_data.py.tpl"
}