# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for resource names
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Convert random bytes to hex string
  random_suffix = substr(random_id.suffix.hex, 0, var.random_suffix_length)
  
  # Resource names with random suffix
  webhook_queue_name     = "${var.project_name}-queue-${local.random_suffix}"
  webhook_dlq_name       = "${var.project_name}-dlq-${local.random_suffix}"
  webhook_function_name  = "${var.project_name}-processor-${local.random_suffix}"
  webhook_api_name       = "${var.project_name}-api-${local.random_suffix}"
  webhook_table_name     = "${var.project_name}-history-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# ============================================================================
# SQS Dead Letter Queue
# ============================================================================

resource "aws_sqs_queue" "webhook_dlq" {
  name                       = local.webhook_dlq_name
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = 60

  tags = merge(local.common_tags, {
    Name = local.webhook_dlq_name
    Type = "dead-letter-queue"
  })
}

# ============================================================================
# SQS Primary Queue with DLQ Configuration
# ============================================================================

resource "aws_sqs_queue" "webhook_queue" {
  name                       = local.webhook_queue_name
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = local.webhook_queue_name
    Type = "primary-queue"
  })
}

# ============================================================================
# DynamoDB Table for Webhook History
# ============================================================================

resource "aws_dynamodb_table" "webhook_history" {
  name           = local.webhook_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "webhook_id"
  range_key      = "timestamp"

  attribute {
    name = "webhook_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name = local.webhook_table_name
    Type = "webhook-history"
  })
}

# ============================================================================
# IAM Role for API Gateway to SQS Integration
# ============================================================================

# Trust policy for API Gateway
data "aws_iam_policy_document" "api_gateway_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Policy for API Gateway to send messages to SQS
data "aws_iam_policy_document" "api_gateway_sqs_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes"
    ]
    
    resources = [aws_sqs_queue.webhook_queue.arn]
  }
}

resource "aws_iam_role" "api_gateway_sqs_role" {
  name               = "${var.project_name}-apigw-sqs-role-${local.random_suffix}"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-apigw-sqs-role-${local.random_suffix}"
    Type = "api-gateway-role"
  })
}

resource "aws_iam_role_policy" "api_gateway_sqs_policy" {
  name   = "SQSAccessPolicy"
  role   = aws_iam_role.api_gateway_sqs_role.id
  policy = data.aws_iam_policy_document.api_gateway_sqs_policy.json
}

# ============================================================================
# Lambda Function for Webhook Processing
# ============================================================================

# Create Lambda function code
data "archive_file" "webhook_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/webhook-processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      table_name = local.webhook_table_name
    })
    filename = "lambda_function.py"
  }
}

# Trust policy for Lambda
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Policy for Lambda to access DynamoDB
data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query"
    ]
    
    resources = [aws_dynamodb_table.webhook_history.arn]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.project_name}-lambda-role-${local.random_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-role-${local.random_suffix}"
    Type = "lambda-execution-role"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom DynamoDB policy
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name   = "DynamoDBAccessPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
}

resource "aws_lambda_function" "webhook_processor" {
  filename         = data.archive_file.webhook_processor_zip.output_path
  function_name    = local.webhook_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout_seconds
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.webhook_processor_zip.output_base64sha256

  environment {
    variables = {
      WEBHOOK_TABLE_NAME = aws_dynamodb_table.webhook_history.name
    }
  }

  tags = merge(local.common_tags, {
    Name = local.webhook_function_name
    Type = "webhook-processor"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
  ]
}

# ============================================================================
# Lambda Event Source Mapping for SQS
# ============================================================================

resource "aws_lambda_event_source_mapping" "sqs_lambda_trigger" {
  event_source_arn                   = aws_sqs_queue.webhook_queue.arn
  function_name                      = aws_lambda_function.webhook_processor.arn
  batch_size                         = var.sqs_batch_size
  maximum_batching_window_in_seconds = var.sqs_maximum_batching_window_in_seconds
  
  depends_on = [aws_lambda_function.webhook_processor]
}

# ============================================================================
# API Gateway REST API
# ============================================================================

resource "aws_api_gateway_rest_api" "webhook_api" {
  name        = local.webhook_api_name
  description = "Webhook processing API"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name = local.webhook_api_name
    Type = "webhook-api"
  })
}

# Create /webhooks resource
resource "aws_api_gateway_resource" "webhooks" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  parent_id   = aws_api_gateway_rest_api.webhook_api.root_resource_id
  path_part   = "webhooks"
}

# Create POST method for /webhooks
resource "aws_api_gateway_method" "webhooks_post" {
  rest_api_id   = aws_api_gateway_rest_api.webhook_api.id
  resource_id   = aws_api_gateway_resource.webhooks.id
  http_method   = "POST"
  authorization = "NONE"
}

# SQS integration for POST method
resource "aws_api_gateway_integration" "webhooks_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  resource_id = aws_api_gateway_resource.webhooks.id
  http_method = aws_api_gateway_method.webhooks_post.http_method
  
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.webhook_queue.name}"
  credentials            = aws_iam_role.api_gateway_sqs_role.arn
  
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
  
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode(\"{\\\"source_ip\\\":\\\"$context.identity.sourceIp\\\",\\\"timestamp\\\":\\\"$context.requestTime\\\",\\\"body\\\":$input.json('$')}\")"
  }
}

# Method response for POST
resource "aws_api_gateway_method_response" "webhooks_post_response" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  resource_id = aws_api_gateway_resource.webhooks.id
  http_method = aws_api_gateway_method.webhooks_post.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for POST
resource "aws_api_gateway_integration_response" "webhooks_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  resource_id = aws_api_gateway_resource.webhooks.id
  http_method = aws_api_gateway_method.webhooks_post.http_method
  status_code = aws_api_gateway_method_response.webhooks_post_response.status_code
  
  response_templates = {
    "application/json" = "{\"message\": \"Webhook received and queued for processing\", \"requestId\": \"$context.requestId\"}"
  }
}

# ============================================================================
# API Gateway Deployment
# ============================================================================

resource "aws_api_gateway_deployment" "webhook_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.webhooks_post_integration,
    aws_api_gateway_integration_response.webhooks_post_integration_response,
  ]

  rest_api_id = aws_api_gateway_rest_api.webhook_api.id
  stage_name  = var.api_gateway_stage_name
  
  description = "Production deployment for webhook processing"
  
  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# CloudWatch Alarms (Optional)
# ============================================================================

# Alarm for messages in Dead Letter Queue
resource "aws_cloudwatch_metric_alarm" "dlq_messages_alarm" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-dlq-messages-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = var.cloudwatch_alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.dlq_alarm_threshold
  alarm_description   = "This metric monitors messages in the webhook dead letter queue"
  alarm_name          = "${var.project_name}-dlq-messages-${local.random_suffix}"
  
  dimensions = {
    QueueName = aws_sqs_queue.webhook_dlq.name
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-dlq-messages-${local.random_suffix}"
    Type = "cloudwatch-alarm"
  })
}

# Alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-lambda-errors-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.cloudwatch_alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.lambda_error_alarm_threshold
  alarm_description   = "This metric monitors Lambda function errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.webhook_processor.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-errors-${local.random_suffix}"
    Type = "cloudwatch-alarm"
  })
}

# ============================================================================
# Lambda Function Template File
# ============================================================================

# Create the Lambda function template
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOF
import json
import boto3
import uuid
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')

def lambda_handler(event, context):
    try:
        # Process each SQS record
        for record in event['Records']:
            # Parse the webhook payload
            webhook_body = json.loads(record['body'])
            
            # Generate unique webhook ID
            webhook_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat()
            
            # Extract webhook metadata
            source_ip = webhook_body.get('source_ip', 'unknown')
            webhook_type = webhook_body.get('body', {}).get('type', 'unknown')
            
            # Process the webhook (customize based on your needs)
            processed_data = process_webhook(webhook_body.get('body', {}))
            
            # Store in DynamoDB
            table.put_item(
                Item={
                    'webhook_id': webhook_id,
                    'timestamp': timestamp,
                    'source_ip': source_ip,
                    'webhook_type': webhook_type,
                    'raw_payload': json.dumps(webhook_body),
                    'processed_data': json.dumps(processed_data),
                    'status': 'processed'
                }
            )
            
            logger.info(f"Processed webhook {webhook_id} of type {webhook_type}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Webhooks processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        raise

def process_webhook(payload):
    """
    Customize this function based on your webhook processing needs
    """
    # Example processing logic
    processed = {
        'processed_at': datetime.utcnow().isoformat(),
        'payload_size': len(json.dumps(payload)),
        'contains_sensitive_data': check_sensitive_data(payload)
    }
    
    # Add your specific processing logic here
    return processed

def check_sensitive_data(payload):
    """
    Example function to check for sensitive data
    """
    sensitive_keys = ['credit_card', 'ssn', 'password', 'secret']
    payload_str = json.dumps(payload).lower()
    
    return any(key in payload_str for key in sensitive_keys)
EOF
}