# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming
  resource_suffix    = random_id.suffix.hex
  api_name          = "${var.project_name}-${local.resource_suffix}"
  lambda_name       = "${var.project_name}-handler-${local.resource_suffix}"
  authorizer_name   = "${var.project_name}-authorizer-${local.resource_suffix}"
  
  # Domain configuration
  full_domain_name  = "${var.api_subdomain}.${var.domain_name}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# Route 53 hosted zone lookup (if provided)
data "aws_route53_zone" "main" {
  count = var.route53_hosted_zone_id != "" ? 1 : 0
  zone_id = var.route53_hosted_zone_id
}

#============================================================================
# SSL/TLS Certificate Management
#============================================================================

# Request SSL certificate from AWS Certificate Manager
resource "aws_acm_certificate" "api_cert" {
  domain_name               = local.full_domain_name
  subject_alternative_names = ["*.${local.full_domain_name}"]
  validation_method         = var.certificate_validation_method
  
  options {
    certificate_transparency_logging_preference = var.certificate_transparency_logging ? "ENABLED" : "DISABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-certificate"
  })
}

# DNS validation for ACM certificate (if using DNS validation and hosted zone provided)
resource "aws_route53_record" "cert_validation" {
  count = var.certificate_validation_method == "DNS" && var.route53_hosted_zone_id != "" ? 1 : 0
  
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_hosted_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "api_cert" {
  count = var.certificate_validation_method == "DNS" && var.route53_hosted_zone_id != "" ? 1 : 0
  
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation[0] : record.fqdn]

  timeouts {
    create = "10m"
  }
}

#============================================================================
# IAM Roles and Policies
#============================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.api_name}-lambda-role"

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
    Name = "${local.api_name}-lambda-role"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# API Gateway CloudWatch role (for API Gateway logging)
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  count = var.enable_api_gateway_logging ? 1 : 0
  name  = "${local.api_name}-apigateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-apigateway-cloudwatch-role"
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  count      = var.enable_api_gateway_logging ? 1 : 0
  role       = aws_iam_role.api_gateway_cloudwatch_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

#============================================================================
# CloudWatch Log Groups
#============================================================================

# Lambda function log group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.lambda_name}-logs"
  })
}

# Authorizer function log group
resource "aws_cloudwatch_log_group" "authorizer_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.authorizer_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.authorizer_name}-logs"
  })
}

# API Gateway log group
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-logs"
  })
}

# API Gateway account settings
resource "aws_api_gateway_account" "main" {
  count               = var.enable_api_gateway_logging ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role[0].arn
}

#============================================================================
# Lambda Functions
#============================================================================

# Create ZIP archive for main Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda-function.zip"
  
  source {
    content = <<EOF
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Sample API responses
    if path == '/pets' and http_method == 'GET':
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'pets': [
                    {'id': 1, 'name': 'Buddy', 'type': 'dog'},
                    {'id': 2, 'name': 'Whiskers', 'type': 'cat'}
                ]
            })
        }
    elif path == '/pets' and http_method == 'POST':
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Pet created successfully',
                'id': 3
            })
        }
    else:
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Not Found'
            })
        }
EOF
    filename = "lambda-function.py"
  }
}

# Main Lambda function
resource "aws_lambda_function" "petstore_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda-function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(local.common_tags, {
    Name = local.lambda_name
  })
}

# Create ZIP archive for authorizer function
data "archive_file" "authorizer_zip" {
  type        = "zip"
  output_path = "authorizer-function.zip"
  
  source {
    content = <<EOF
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Authorizer Event: {json.dumps(event)}")
    
    # Extract the authorization token
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    # Simple token validation (in production, use proper JWT validation)
    if token == 'Bearer valid-token':
        effect = 'Allow'
        principal_id = 'user123'
    else:
        effect = 'Deny'
        principal_id = 'anonymous'
    
    # Generate policy document
    policy_document = {
        'Version': '2012-10-17',
        'Statement': [
            {
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': method_arn
            }
        ]
    }
    
    return {
        'principalId': principal_id,
        'policyDocument': policy_document,
        'context': {
            'userId': principal_id,
            'userRole': 'user'
        }
    }
EOF
    filename = "authorizer-function.py"
  }
}

# Custom authorizer Lambda function
resource "aws_lambda_function" "petstore_authorizer" {
  filename         = data.archive_file.authorizer_zip.output_path
  function_name    = local.authorizer_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "authorizer-function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.authorizer_zip.output_base64sha256

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.authorizer_logs,
  ]

  tags = merge(local.common_tags, {
    Name = local.authorizer_name
  })
}

#============================================================================
# API Gateway Configuration
#============================================================================

# REST API
resource "aws_api_gateway_rest_api" "petstore_api" {
  name        = local.api_name
  description = "Pet Store API with custom domain"

  endpoint_configuration {
    types = [var.api_gateway_endpoint_type]
  }

  tags = merge(local.common_tags, {
    Name = local.api_name
  })
}

# API Gateway resource for /pets
resource "aws_api_gateway_resource" "pets" {
  rest_api_id = aws_api_gateway_rest_api.petstore_api.id
  parent_id   = aws_api_gateway_rest_api.petstore_api.root_resource_id
  path_part   = "pets"
}

# Custom authorizer
resource "aws_api_gateway_authorizer" "petstore_authorizer" {
  name                   = local.authorizer_name
  rest_api_id           = aws_api_gateway_rest_api.petstore_api.id
  authorizer_uri        = aws_lambda_function.petstore_authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.lambda_execution_role.arn
  type                  = "TOKEN"
  identity_source       = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = var.authorizer_token_ttl
}

# Lambda permission for authorizer
resource "aws_lambda_permission" "authorizer_permission" {
  statement_id  = "${local.authorizer_name}-apigateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.petstore_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.petstore_api.execution_arn}/authorizers/${aws_api_gateway_authorizer.petstore_authorizer.id}"
}

# Request validator
resource "aws_api_gateway_request_validator" "petstore_validator" {
  name                        = "${local.api_name}-validator"
  rest_api_id                = aws_api_gateway_rest_api.petstore_api.id
  validate_request_body      = true
  validate_request_parameters = true
}

# API Methods - GET /pets
resource "aws_api_gateway_method" "get_pets" {
  rest_api_id   = aws_api_gateway_rest_api.petstore_api.id
  resource_id   = aws_api_gateway_resource.pets.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.petstore_authorizer.id
}

# API Methods - POST /pets
resource "aws_api_gateway_method" "post_pets" {
  rest_api_id          = aws_api_gateway_rest_api.petstore_api.id
  resource_id          = aws_api_gateway_resource.pets.id
  http_method          = "POST"
  authorization        = "CUSTOM"
  authorizer_id        = aws_api_gateway_authorizer.petstore_authorizer.id
  request_validator_id = aws_api_gateway_request_validator.petstore_validator.id
}

# Lambda integrations - GET /pets
resource "aws_api_gateway_integration" "get_pets_integration" {
  rest_api_id             = aws_api_gateway_rest_api.petstore_api.id
  resource_id             = aws_api_gateway_resource.pets.id
  http_method             = aws_api_gateway_method.get_pets.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.petstore_handler.invoke_arn
}

# Lambda integrations - POST /pets
resource "aws_api_gateway_integration" "post_pets_integration" {
  rest_api_id             = aws_api_gateway_rest_api.petstore_api.id
  resource_id             = aws_api_gateway_resource.pets.id
  http_method             = aws_api_gateway_method.post_pets.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.petstore_handler.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "${local.lambda_name}-apigateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.petstore_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.petstore_api.execution_arn}/*"
}

#============================================================================
# API Gateway Deployment and Stages
#============================================================================

# API deployment
resource "aws_api_gateway_deployment" "petstore_deployment" {
  rest_api_id = aws_api_gateway_rest_api.petstore_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.pets.id,
      aws_api_gateway_method.get_pets.id,
      aws_api_gateway_method.post_pets.id,
      aws_api_gateway_integration.get_pets_integration.id,
      aws_api_gateway_integration.post_pets_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.get_pets,
    aws_api_gateway_method.post_pets,
    aws_api_gateway_integration.get_pets_integration,
    aws_api_gateway_integration.post_pets_integration,
  ]
}

# Development stage
resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.petstore_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.petstore_api.id
  stage_name    = "dev"
  description   = "Development stage"

  variables = {
    environment = "development"
  }

  # Enable throttling for dev stage
  throttle_settings {
    rate_limit  = var.dev_throttle_rate_limit
    burst_limit = var.dev_throttle_burst_limit
  }

  # Enable access logging if configured
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
        ip             = "$context.identity.sourceIp"
        userAgent      = "$context.identity.userAgent"
        errorMessage   = "$context.error.message"
        errorType      = "$context.error.messageString"
      })
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-dev"
  })

  depends_on = [aws_api_gateway_account.main]
}

# Production stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.petstore_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.petstore_api.id
  stage_name    = "prod"
  description   = "Production stage"

  variables = {
    environment = "production"
  }

  # Enable throttling for prod stage
  throttle_settings {
    rate_limit  = var.api_throttle_rate_limit
    burst_limit = var.api_throttle_burst_limit
  }

  # Enable access logging if configured
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
        ip             = "$context.identity.sourceIp"
        userAgent      = "$context.identity.userAgent"
        errorMessage   = "$context.error.message"
        errorType      = "$context.error.messageString"
      })
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.api_name}-prod"
  })

  depends_on = [aws_api_gateway_account.main]
}

#============================================================================
# Custom Domain Name and Mappings
#============================================================================

# Custom domain name
resource "aws_api_gateway_domain_name" "api_domain" {
  domain_name              = local.full_domain_name
  certificate_arn          = aws_acm_certificate.api_cert.arn
  security_policy          = var.api_gateway_minimum_tls_version

  endpoint_configuration {
    types = [var.api_gateway_endpoint_type]
  }

  depends_on = [
    aws_acm_certificate_validation.api_cert
  ]

  tags = merge(local.common_tags, {
    Name = local.full_domain_name
  })
}

# Base path mapping for production (root path)
resource "aws_api_gateway_base_path_mapping" "prod_root" {
  api_id      = aws_api_gateway_rest_api.petstore_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  domain_name = aws_api_gateway_domain_name.api_domain.domain_name
}

# Base path mapping for production (v1 path)
resource "aws_api_gateway_base_path_mapping" "prod_v1" {
  api_id      = aws_api_gateway_rest_api.petstore_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  domain_name = aws_api_gateway_domain_name.api_domain.domain_name
  base_path   = "v1"
}

# Base path mapping for development
resource "aws_api_gateway_base_path_mapping" "dev" {
  api_id      = aws_api_gateway_rest_api.petstore_api.id
  stage_name  = aws_api_gateway_stage.dev.stage_name
  domain_name = aws_api_gateway_domain_name.api_domain.domain_name
  base_path   = "v1-dev"
}

#============================================================================
# DNS Configuration (Route 53)
#============================================================================

# Route 53 DNS record for custom domain (if hosted zone provided)
resource "aws_route53_record" "api_domain" {
  count   = var.route53_hosted_zone_id != "" ? 1 : 0
  zone_id = var.route53_hosted_zone_id
  name    = local.full_domain_name
  type    = "CNAME"
  ttl     = var.dns_record_ttl
  records = [
    var.api_gateway_endpoint_type == "REGIONAL" ? 
      aws_api_gateway_domain_name.api_domain.regional_domain_name :
      aws_api_gateway_domain_name.api_domain.cloudfront_domain_name
  ]
}