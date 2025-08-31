# main.tf
# Main Terraform configuration for AWS basic secret management with Secrets Manager and Lambda
# This configuration creates a complete secret management solution with:
# - AWS Secrets Manager secret with sample database credentials
# - Lambda function that retrieves secrets using the AWS Parameters and Secrets Extension
# - IAM roles and policies following least privilege principle
# - CloudWatch logs for monitoring and debugging

# Create the Secrets Manager secret using the terraform-aws-modules/secrets-manager module
# This provides a production-ready secret configuration with proper defaults
module "secrets_manager" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.3"

  # Secret configuration
  name                    = local.secret_name
  description             = var.secret_description
  recovery_window_in_days = var.secret_recovery_window
  kms_key_id             = var.kms_key_id
  
  # Store sample database credentials as JSON
  secret_string = jsonencode(var.sample_secret_values)
  
  # Ignore external changes to secret values (e.g., rotation)
  ignore_secret_changes = true
  
  # Optional: Enable automatic rotation
  enable_rotation = var.enable_secret_rotation
  rotation_rules = var.enable_secret_rotation ? {
    automatically_after_days = var.rotation_days
  } : {}
  
  # Optional: Set rotation Lambda ARN if rotation is enabled
  # rotation_lambda_arn = var.enable_secret_rotation ? aws_lambda_function.rotation_function[0].arn : ""
  
  tags = local.common_tags
}

# Create IAM role for Lambda function execution
# This role allows Lambda to assume it and includes basic execution permissions
resource "aws_iam_role" "lambda_execution_role" {
  name = local.iam_role_name
  
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

# Attach basic Lambda execution policy for CloudWatch logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Create custom policy for Secrets Manager access
# This policy follows least privilege principle by granting access only to our specific secret
resource "aws_iam_policy" "secrets_access_policy" {
  name        = "SecretsAccess-${local.resource_suffix}"
  description = "Policy for Lambda function to access specific Secrets Manager secret"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = module.secrets_manager.secret_arn
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach the custom secrets access policy to the Lambda role
resource "aws_iam_role_policy_attachment" "secrets_access" {
  policy_arn = aws_iam_policy.secrets_access_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

# Create the Lambda function package with inline code
# This demonstrates retrieving secrets using the AWS Parameters and Secrets Extension
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      secret_name = module.secrets_manager.secret_name
    })
    filename = "lambda_function.py"
  }
}

# Create the Lambda function with the AWS Parameters and Secrets Extension layer
resource "aws_lambda_function" "secret_demo" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Add the AWS Parameters and Secrets Lambda Extension layer
  layers = [local.extensions_layer_arn]
  
  # Environment variables for the Lambda function and extension configuration
  environment {
    variables = {
      SECRET_NAME                                          = module.secrets_manager.secret_name
      PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED          = tostring(var.extension_cache_enabled)
      PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE             = tostring(var.extension_cache_size)
      PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS        = tostring(var.extension_max_connections)
      PARAMETERS_SECRETS_EXTENSION_HTTP_PORT              = tostring(var.extension_http_port)
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.secrets_access,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = local.common_tags
}

# Create CloudWatch log group for Lambda function logs
# This ensures logs are retained according to our policy and have proper permissions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# Optional: Create a Lambda function URL for easy testing (HTTP endpoint)
# Uncomment if you want to test the function via HTTPS
# resource "aws_lambda_function_url" "secret_demo_url" {
#   function_name      = aws_lambda_function.secret_demo.function_name
#   authorization_type = "NONE"  # For demo only! Use AWS_IAM for production
#   
#   cors {
#     allow_credentials = false
#     allow_origins     = ["*"]
#     allow_methods     = ["GET", "POST"]
#     allow_headers     = ["date", "keep-alive"]
#     expose_headers    = ["date", "keep-alive"]
#     max_age          = 86400
#   }
# }

# Optional: Create a CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN here if you want notifications
  
  dimensions = {
    FunctionName = aws_lambda_function.secret_demo.function_name
  }
  
  tags = local.common_tags
}

# Optional: Create a CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "25000" # 25 seconds (close to our 30-second timeout)
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [] # Add SNS topic ARN here if you want notifications
  
  dimensions = {
    FunctionName = aws_lambda_function.secret_demo.function_name
  }
  
  tags = local.common_tags
}