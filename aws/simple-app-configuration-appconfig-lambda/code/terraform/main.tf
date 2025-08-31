# =============================================================================
# Simple Application Configuration with AppConfig and Lambda
# 
# This Terraform configuration creates:
# - AppConfig Application with Environment and Configuration Profile
# - Lambda Function that retrieves configuration from AppConfig
# - IAM roles and policies for secure access
# - Configuration data stored as hosted configuration
# =============================================================================

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Local values for consistent naming and configuration
locals {
  app_name               = "${var.app_name_prefix}-${random_string.suffix.result}"
  lambda_function_name   = "${var.lambda_function_prefix}-${random_string.suffix.result}"
  lambda_role_name       = "${var.lambda_role_prefix}-${random_string.suffix.result}"
  deployment_strategy_name = "immediate-deployment-${random_string.suffix.result}"
  
  # Default configuration data as JSON
  default_config = jsonencode({
    database = {
      max_connections = var.database_max_connections
      timeout_seconds = var.database_timeout_seconds
      retry_attempts  = var.database_retry_attempts
    }
    features = {
      enable_logging = var.features_enable_logging
      enable_metrics = var.features_enable_metrics
      debug_mode     = var.features_debug_mode
    }
    api = {
      rate_limit = var.api_rate_limit
      cache_ttl  = var.api_cache_ttl
    }
  })

  common_tags = {
    Environment = var.environment
    Project     = "Simple AppConfig Demo"
    ManagedBy   = "Terraform"
    Recipe      = "simple-app-configuration-appconfig-lambda"
  }
}

# =============================================================================
# Data Sources
# =============================================================================

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# IAM policy document for Lambda execution role trust relationship
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy document for AppConfig access permissions
data "aws_iam_policy_document" "appconfig_access" {
  statement {
    effect = "Allow"
    
    actions = [
      "appconfig:StartConfigurationSession",
      "appconfig:GetLatestConfiguration"
    ]
    
    resources = ["*"]
  }
}

# Package Lambda function source code
data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content  = file("${path.module}/../lambda/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# =============================================================================
# AppConfig Resources
# =============================================================================

# AppConfig Application - Logical container for configuration data
resource "aws_appconfig_application" "main" {
  name        = local.app_name
  description = "Simple configuration management demo application"
  
  tags = merge(local.common_tags, {
    Name = local.app_name
    Type = "AppConfig Application"
  })
}

# AppConfig Environment - Represents deployment environment (dev, staging, prod)
resource "aws_appconfig_environment" "dev" {
  name           = var.environment_name
  description    = "${var.environment_name} environment for configuration testing"
  application_id = aws_appconfig_application.main.id
  
  # Optional monitoring configuration
  dynamic "monitor" {
    for_each = var.enable_cloudwatch_alarms ? [1] : []
    content {
      alarm_arn      = aws_cloudwatch_metric_alarm.config_errors[0].arn
      alarm_role_arn = aws_iam_role.appconfig_alarm_role[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.app_name}-${var.environment_name}"
    Type = "AppConfig Environment"
  })
}

# AppConfig Configuration Profile - Defines configuration structure and source
resource "aws_appconfig_configuration_profile" "app_settings" {
  application_id = aws_appconfig_application.main.id
  name          = "app-settings"
  description   = "Application settings configuration profile"
  location_uri  = "hosted"
  type          = "AWS.Freeform"
  
  # Optional JSON Schema validator
  dynamic "validator" {
    for_each = var.enable_json_validation ? [1] : []
    content {
      type    = "JSON_SCHEMA"
      content = jsonencode({
        "$schema" = "http://json-schema.org/draft-07/schema#"
        type     = "object"
        properties = {
          database = {
            type = "object"
            properties = {
              max_connections = { type = "integer", minimum = 1, maximum = 1000 }
              timeout_seconds = { type = "integer", minimum = 1, maximum = 300 }
              retry_attempts  = { type = "integer", minimum = 0, maximum = 10 }
            }
            required = ["max_connections", "timeout_seconds", "retry_attempts"]
          }
          features = {
            type = "object"
            properties = {
              enable_logging = { type = "boolean" }
              enable_metrics = { type = "boolean" }
              debug_mode     = { type = "boolean" }
            }
            required = ["enable_logging", "enable_metrics", "debug_mode"]
          }
          api = {
            type = "object"
            properties = {
              rate_limit = { type = "integer", minimum = 1, maximum = 10000 }
              cache_ttl  = { type = "integer", minimum = 0, maximum = 3600 }
            }
            required = ["rate_limit", "cache_ttl"]
          }
        }
        required = ["database", "features", "api"]
      })
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.app_name}-app-settings"
    Type = "AppConfig Configuration Profile"
  })
}

# AppConfig Hosted Configuration Version - Contains the actual configuration data
resource "aws_appconfig_hosted_configuration_version" "initial" {
  application_id           = aws_appconfig_application.main.id
  configuration_profile_id = aws_appconfig_configuration_profile.app_settings.configuration_profile_id
  content_type            = "application/json"
  content                 = local.default_config
  description             = "Initial configuration version"
}

# AppConfig Deployment Strategy - Defines how configuration is deployed
resource "aws_appconfig_deployment_strategy" "immediate" {
  name                           = local.deployment_strategy_name
  description                   = "Immediate deployment strategy for testing"
  deployment_duration_in_minutes = var.deployment_duration_minutes
  final_bake_time_in_minutes    = var.final_bake_time_minutes
  growth_factor                 = var.growth_factor
  growth_type                   = var.growth_type
  replicate_to                  = "NONE"

  tags = merge(local.common_tags, {
    Name = local.deployment_strategy_name
    Type = "AppConfig Deployment Strategy"
  })
}

# AppConfig Deployment - Activates the configuration
resource "aws_appconfig_deployment" "initial" {
  application_id           = aws_appconfig_application.main.id
  environment_id          = aws_appconfig_environment.dev.environment_id
  deployment_strategy_id  = aws_appconfig_deployment_strategy.immediate.id
  configuration_profile_id = aws_appconfig_configuration_profile.app_settings.configuration_profile_id
  configuration_version   = aws_appconfig_hosted_configuration_version.initial.version_number
  description            = "Initial configuration deployment"

  tags = merge(local.common_tags, {
    Name = "${local.app_name}-initial-deployment"
    Type = "AppConfig Deployment"
  })
}

# =============================================================================
# IAM Resources
# =============================================================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution" {
  name               = local.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for AppConfig Lambda function"

  tags = merge(local.common_tags, {
    Name = local.lambda_role_name
    Type = "Lambda Execution Role"
  })
}

# Custom IAM policy for AppConfig access
resource "aws_iam_policy" "appconfig_access" {
  name        = "AppConfigLambdaPolicy-${random_string.suffix.result}"
  description = "IAM policy for Lambda to access AppConfig"
  policy      = data.aws_iam_policy_document.appconfig_access.json

  tags = merge(local.common_tags, {
    Name = "AppConfigLambdaPolicy-${random_string.suffix.result}"
    Type = "IAM Policy"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom AppConfig access policy
resource "aws_iam_role_policy_attachment" "lambda_appconfig_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.appconfig_access.arn
}

# Optional: IAM role for AppConfig CloudWatch alarm monitoring
resource "aws_iam_role" "appconfig_alarm_role" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  name = "appconfig-alarm-role-${random_string.suffix.result}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appconfig.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "appconfig-alarm-role-${random_string.suffix.result}"
    Type = "AppConfig Alarm Role"
  })
}

# =============================================================================
# CloudWatch Resources
# =============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Type = "CloudWatch Log Group"
  })
}

# Optional: CloudWatch alarm for monitoring configuration errors
resource "aws_cloudwatch_metric_alarm" "config_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "appconfig-config-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.config_demo.function_name
  }

  tags = merge(local.common_tags, {
    Name = "appconfig-config-errors-${random_string.suffix.result}"
    Type = "CloudWatch Alarm"
  })
}

# =============================================================================
# Lambda Resources
# =============================================================================

# Lambda function that retrieves configuration from AppConfig
resource "aws_lambda_function" "config_demo" {
  filename         = data.archive_file.lambda_function.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  description     = "Lambda function to demonstrate AppConfig integration"

  # Environment variables for AppConfig integration
  environment {
    variables = {
      APPCONFIG_APPLICATION_ID           = aws_appconfig_application.main.id
      APPCONFIG_ENVIRONMENT_ID          = aws_appconfig_environment.dev.environment_id
      APPCONFIG_CONFIGURATION_PROFILE_ID = aws_appconfig_configuration_profile.app_settings.configuration_profile_id
      LOG_LEVEL                         = var.log_level
    }
  }

  # AppConfig Lambda Extension Layer - provides local HTTP endpoint for configuration retrieval
  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:027255383542:layer:AWS-AppConfig-Extension:207"
  ]

  # Advanced logging configuration
  logging_config {
    log_format            = var.lambda_log_format
    application_log_level = var.lambda_app_log_level
    system_log_level      = var.lambda_system_log_level
  }

  # Ensure dependencies are ready before Lambda creation
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_appconfig_access,
    aws_cloudwatch_log_group.lambda_logs,
    aws_appconfig_deployment.initial
  ]

  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "Lambda Function"
  })
}

# Lambda function URL for easy testing (optional)
resource "aws_lambda_function_url" "config_demo_url" {
  count = var.create_function_url ? 1 : 0
  
  function_name      = aws_lambda_function.config_demo.function_name
  authorization_type = "NONE"  # For demo purposes only - use AUTH for production
  
  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["date", "keep-alive"]
    expose_headers    = ["date", "keep-alive"]
    max_age          = 86400
  }
}