# Main Terraform configuration for URL Shortener service

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Merged tags
  common_tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

# ========================================
# DynamoDB Table for URL Storage
# ========================================

resource "aws_dynamodb_table" "url_storage" {
  name           = "${local.name_prefix}-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "short_id"
  
  # On-demand billing eliminates capacity planning
  # For PROVISIONED mode, you would add read_capacity and write_capacity
  
  attribute {
    name = "short_id"
    type = "S"
  }
  
  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }
  
  # Point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }
  
  # TTL for automatic URL expiration
  ttl {
    attribute_name = "expires_at_timestamp"
    enabled        = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-table-${local.name_suffix}"
  })
}

# ========================================
# Lambda Function Package
# ========================================

# Create Lambda function code as a local file
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOF
import json
import boto3
import base64
import hashlib
import uuid
import logging
import os
from datetime import datetime, timedelta
from urllib.parse import urlparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Main Lambda handler for URL shortener operations"""
    
    try:
        # Extract HTTP method and path
        http_method = event['httpMethod']
        path = event['path']
        
        # Route requests based on method and path
        if http_method == 'POST' and path == '/shorten':
            return create_short_url(event)
        elif http_method == 'GET' and path.startswith('/'):
            return redirect_to_long_url(event)
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_short_url(event):
    """Create a new short URL mapping"""
    
    try:
        # Parse request body
        if event.get('isBase64Encoded', False):
            body = base64.b64decode(event['body']).decode('utf-8')
        else:
            body = event['body']
        
        request_data = json.loads(body)
        original_url = request_data.get('url')
        
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'URL is required'})
            }
        
        # Validate URL format
        parsed_url = urlparse(original_url)
        if not parsed_url.scheme or not parsed_url.netloc:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short ID
        short_id = generate_short_id(original_url)
        
        # Create expiration time
        expiration_days = int(os.environ.get('URL_EXPIRATION_DAYS', '30'))
        expiration_time = datetime.utcnow() + timedelta(days=expiration_days)
        expiration_timestamp = int(expiration_time.timestamp())
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'short_id': short_id,
                'original_url': original_url,
                'created_at': datetime.utcnow().isoformat(),
                'expires_at': expiration_time.isoformat(),
                'expires_at_timestamp': expiration_timestamp,
                'click_count': 0,
                'is_active': True
            }
        )
        
        # Return success response
        api_url = os.environ.get('API_URL', 'https://your-domain.com')
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'short_id': short_id,
                'short_url': f"{api_url}/{short_id}",
                'original_url': original_url,
                'expires_at': expiration_time.isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating short URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not create short URL'})
        }

def redirect_to_long_url(event):
    """Redirect to original URL using short ID"""
    
    try:
        # Extract short ID from path
        short_id = event['path'][1:]  # Remove leading slash
        
        if not short_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short ID is required'})
            }
        
        # Retrieve from DynamoDB
        response = table.get_item(Key={'short_id': short_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL not found'})
            }
        
        item = response['Item']
        
        # Check if URL is still active
        if not item.get('is_active', True):
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has been disabled'})
            }
        
        # Check expiration
        expires_at = datetime.fromisoformat(item['expires_at'])
        if datetime.utcnow() > expires_at:
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has expired'})
            }
        
        # Increment click count
        table.update_item(
            Key={'short_id': short_id},
            UpdateExpression='SET click_count = click_count + :inc',
            ExpressionAttributeValues={':inc': 1}
        )
        
        # Return redirect response
        return {
            'statusCode': 302,
            'headers': {
                'Location': item['original_url'],
                'Access-Control-Allow-Origin': '*'
            },
            'body': ''
        }
        
    except Exception as e:
        logger.error(f"Error redirecting URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not redirect to URL'})
        }

def generate_short_id(url):
    """Generate a short ID from URL using hash"""
    
    # Create a hash of the URL with timestamp for uniqueness
    hash_input = f"{url}{datetime.utcnow().isoformat()}{uuid.uuid4().hex[:8]}"
    hash_object = hashlib.sha256(hash_input.encode())
    hash_hex = hash_object.hexdigest()
    
    # Convert to base62 for URL-safe short ID
    short_id = base62_encode(int(hash_hex[:16], 16))[:8]
    
    return short_id

def base62_encode(num):
    """Encode number to base62 string"""
    
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if num == 0:
        return alphabet[0]
    
    result = []
    while num:
        result.append(alphabet[num % 62])
        num //= 62
    
    return ''.join(reversed(result))
EOF
}

# Create deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_code]
}

# ========================================
# IAM Role and Policies for Lambda
# ========================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
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
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for DynamoDB access
resource "aws_iam_policy" "dynamodb_access" {
  name        = "${local.name_prefix}-dynamodb-policy-${local.name_suffix}"
  description = "IAM policy for DynamoDB access from Lambda"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.url_storage.arn
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach DynamoDB policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

# ========================================
# CloudWatch Log Group
# ========================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-logs-${local.name_suffix}"
  })
}

# ========================================
# Lambda Function
# ========================================

resource "aws_lambda_function" "url_shortener" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "URL Shortener Service Function"
  
  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.url_storage.name
      URL_EXPIRATION_DAYS  = var.url_expiration_days
      API_URL             = "https://${aws_apigatewayv2_api.url_shortener.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod"
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_dynamodb_access
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-function-${local.name_suffix}"
  })
}

# ========================================
# API Gateway HTTP API
# ========================================

resource "aws_apigatewayv2_api" "url_shortener" {
  name          = "${local.name_prefix}-api-${local.name_suffix}"
  protocol_type = "HTTP"
  description   = "URL Shortener API"
  
  # CORS configuration
  dynamic "cors_configuration" {
    for_each = var.enable_cors ? [1] : []
    content {
      allow_credentials = false
      allow_methods     = var.cors_allowed_methods
      allow_origins     = var.cors_allowed_origins
      allow_headers     = var.cors_allowed_headers
      max_age          = 300
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-${local.name_suffix}"
  })
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.url_shortener.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.url_shortener.invoke_arn
  payload_format_version = "1.0"
  
  depends_on = [aws_lambda_function.url_shortener]
}

# Routes for URL shortening (POST /shorten)
resource "aws_apigatewayv2_route" "shorten_url" {
  api_id    = aws_apigatewayv2_api.url_shortener.id
  route_key = "POST /shorten"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Routes for URL redirection (GET /{proxy+})
resource "aws_apigatewayv2_route" "redirect_url" {
  api_id    = aws_apigatewayv2_api.url_shortener.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.url_shortener.id
  name        = "prod"
  description = "Production stage"
  auto_deploy = true
  
  # Enable access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      requestLength  = "$context.requestLength"
      ip             = "$context.identity.sourceIp"
      userAgent      = "$context.identity.userAgent"
    })
  }
  
  tags = local.common_tags
  
  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.name_prefix}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-logs-${local.name_suffix}"
  })
}

# ========================================
# Lambda Permission for API Gateway
# ========================================

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url_shortener.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.url_shortener.execution_arn}/*/*/*"
}

# ========================================
# CloudWatch Dashboard (Optional)
# ========================================

resource "aws_cloudwatch_dashboard" "url_shortener" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.url_shortener.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.url_storage.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "DynamoDB Table Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          metrics = [
            ["AWS/ApiGatewayV2", "Count", "ApiId", aws_apigatewayv2_api.url_shortener.id],
            [".", "IntegrationLatency", ".", "."],
            [".", "Latency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "API Gateway Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
  
  tags = local.common_tags
}