# Simple Contact Form Backend Infrastructure
# This Terraform configuration creates a serverless contact form backend using:
# - AWS Lambda for processing form submissions
# - Amazon SES for sending notification emails
# - API Gateway for providing HTTP endpoint
# - IAM roles and policies for secure access

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Resource naming with environment and random suffix
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  function_name = "${local.name_prefix}-processor-${local.name_suffix}"
  api_name      = "${local.name_prefix}-api-${local.name_suffix}"
  role_name     = "${local.name_prefix}-lambda-role-${local.name_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Component   = "contact-form-backend"
  })
}

# ========================================
# IAM Role and Policies for Lambda
# ========================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution" {
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

  tags = local.common_tags
}

# Basic Lambda execution policy (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution.name
}

# Custom policy for SES permissions
resource "aws_iam_policy" "ses_send_email" {
  name        = "${local.name_prefix}-ses-policy-${local.name_suffix}"
  description = "Allow Lambda to send emails through SES"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach SES policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ses" {
  policy_arn = aws_iam_policy.ses_send_email.arn
  role       = aws_iam_role.lambda_execution.name
}

# Optional X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_xray_tracing ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.lambda_execution.name
}

# ========================================
# CloudWatch Log Group for Lambda
# ========================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ========================================
# Lambda Function Code and Deployment
# ========================================

# Create the Lambda function code
resource "local_file" "lambda_function" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    AWS Lambda handler for processing contact form submissions.
    
    Receives form data from API Gateway, validates inputs, and sends
    notification email through Amazon SES.
    """
    # Initialize SES client
    ses_client = boto3.client('ses')
    
    try:
        # Log the incoming event for debugging
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse the incoming request body
        if 'body' not in event:
            logger.error("No body found in event")
            return create_response(400, {'error': 'Invalid request format'})
            
        body = json.loads(event['body'])
        logger.info(f"Parsed body: {json.dumps(body)}")
        
        # Extract and validate form data
        name = body.get('name', '').strip()
        email = body.get('email', '').strip()
        subject = body.get('subject', 'Contact Form Submission').strip()
        message = body.get('message', '').strip()
        
        # Validate required fields
        if not name or not email or not message:
            logger.warning(f"Missing required fields: name={bool(name)}, email={bool(email)}, message={bool(message)}")
            return create_response(400, {
                'error': 'Name, email, and message are required fields'
            })
        
        # Basic email validation
        if '@' not in email or '.' not in email.split('@')[-1]:
            logger.warning(f"Invalid email format: {email}")
            return create_response(400, {
                'error': 'Please provide a valid email address'
            })
        
        # Prepare email content
        sender_email = os.environ['SENDER_EMAIL']
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
        
        email_subject = f"Contact Form: {subject}"
        email_body = f"""
New Contact Form Submission

Timestamp: {timestamp}
Name: {name}
Email: {email}
Subject: {subject}

Message:
{message}

---
This message was sent from your website contact form.
Reply directly to this email to respond to {name}.
        """.strip()
        
        # Send email using SES
        logger.info(f"Sending email from {sender_email} to {sender_email}")
        response = ses_client.send_email(
            Source=sender_email,
            Destination={
                'ToAddresses': [sender_email]
            },
            Message={
                'Subject': {
                    'Data': email_subject,
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': email_body,
                        'Charset': 'UTF-8'
                    }
                }
            },
            ReplyToAddresses=[email]  # Allow direct reply to submitter
        )
        
        logger.info(f"Email sent successfully. MessageId: {response['MessageId']}")
        
        # Return success response
        return create_response(200, {
            'message': 'Your message has been sent successfully!',
            'messageId': response['MessageId']
        })
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return create_response(400, {
            'error': 'Invalid JSON format in request body'
        })
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_response(500, {
            'error': 'An internal error occurred. Please try again later.'
        })

def create_response(status_code, body):
    """
    Create a properly formatted API Gateway response with CORS headers.
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token',
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body)
    }
EOF
}

# Create deployment package for Lambda
data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = local_file.lambda_function.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_function]
}

# Deploy Lambda function
resource "aws_lambda_function" "contact_form_processor" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  # Environment variables
  environment {
    variables = {
      SENDER_EMAIL = var.sender_email
      ENVIRONMENT  = var.environment
    }
  }

  # Optional X-Ray tracing
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Advanced logging configuration
  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_ses,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# ========================================
# API Gateway REST API
# ========================================

# Create API Gateway REST API
resource "aws_api_gateway_rest_api" "contact_form_api" {
  name        = local.api_name
  description = "REST API for serverless contact form backend"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# Create /contact resource
resource "aws_api_gateway_resource" "contact" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  parent_id   = aws_api_gateway_rest_api.contact_form_api.root_resource_id
  path_part   = "contact"
}

# ========================================
# API Gateway Methods and Integration
# ========================================

# POST method for form submissions
resource "aws_api_gateway_method" "contact_post" {
  rest_api_id   = aws_api_gateway_rest_api.contact_form_api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.body_validator.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.contact_form_model.name
  }
}

# OPTIONS method for CORS preflight
resource "aws_api_gateway_method" "contact_options" {
  rest_api_id   = aws_api_gateway_rest_api.contact_form_api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Lambda integration for POST method
resource "aws_api_gateway_integration" "contact_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.contact_form_processor.invoke_arn
}

# Mock integration for OPTIONS method (CORS)
resource "aws_api_gateway_integration" "contact_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method

  type = "MOCK"
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# OPTIONS method response
resource "aws_api_gateway_method_response" "contact_options_response" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# OPTIONS integration response with CORS headers
resource "aws_api_gateway_integration_response" "contact_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method
  status_code = aws_api_gateway_method_response.contact_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = join(",", [for origin in var.cors_allow_origins : "'${origin}'"])
  }
}

# ========================================
# API Gateway Request Validation
# ========================================

# Request validator for POST body
resource "aws_api_gateway_request_validator" "body_validator" {
  name                        = "${local.name_prefix}-validator"
  rest_api_id                = aws_api_gateway_rest_api.contact_form_api.id
  validate_request_body      = true
  validate_request_parameters = false
}

# JSON schema model for contact form validation
resource "aws_api_gateway_model" "contact_form_model" {
  rest_api_id  = aws_api_gateway_rest_api.contact_form_api.id
  name         = "ContactForm"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Contact Form Schema"
    type      = "object"
    required  = ["name", "email", "message"]
    properties = {
      name = {
        type      = "string"
        minLength = 1
        maxLength = 100
      }
      email = {
        type    = "string"
        pattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
      }
      subject = {
        type      = "string"
        maxLength = 200
      }
      message = {
        type      = "string"
        minLength = 1
        maxLength = 5000
      }
    }
  })
}

# ========================================
# API Gateway Deployment and Stage
# ========================================

# API Gateway deployment
resource "aws_api_gateway_deployment" "contact_form_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id

  triggers = {
    # Redeploy when any of these resources change
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.contact.id,
      aws_api_gateway_method.contact_post.id,
      aws_api_gateway_method.contact_options.id,
      aws_api_gateway_integration.contact_post_integration.id,
      aws_api_gateway_integration.contact_options_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.contact_post,
    aws_api_gateway_method.contact_options,
    aws_api_gateway_integration.contact_post_integration,
    aws_api_gateway_integration.contact_options_integration,
    aws_api_gateway_integration_response.contact_options_integration_response
  ]
}

# API Gateway stage
resource "aws_api_gateway_stage" "contact_form_api_stage" {
  deployment_id = aws_api_gateway_deployment.contact_form_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.contact_form_api.id
  stage_name    = var.api_stage_name

  # Enable throttling
  throttle_settings {
    rate_limit  = var.rate_limit
    burst_limit = var.burst_limit
  }

  # Enable detailed CloudWatch metrics
  xray_tracing_enabled = var.enable_xray_tracing

  tags = local.common_tags
}

# ========================================
# API Gateway Logging (Optional)
# ========================================

# CloudWatch log group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_logging ? 1 : 0
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.contact_form_api.id}/${var.api_stage_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# API Gateway method settings for logging
resource "aws_api_gateway_method_settings" "contact_form_api_settings" {
  count       = var.enable_api_logging ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.contact_form_api.id
  stage_name  = aws_api_gateway_stage.contact_form_api_stage.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }
}

# ========================================
# Lambda Permission for API Gateway
# ========================================

# Grant API Gateway permission to invoke Lambda function
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form_processor.function_name
  principal     = "apigateway.amazonaws.com"

  # More restrictive source ARN for better security
  source_arn = "${aws_api_gateway_rest_api.contact_form_api.execution_arn}/*/*"
}

# ========================================
# SES Email Identity (Optional)
# ========================================

# Email identity verification (requires manual confirmation)
resource "aws_ses_email_identity" "sender" {
  email = var.sender_email

  tags = local.common_tags
}

# Configuration set for SES (optional, for tracking)
resource "aws_ses_configuration_set" "contact_form" {
  name = "${local.name_prefix}-config-set"

  delivery_options {
    tls_policy = "Require"
  }

  tags = local.common_tags
}