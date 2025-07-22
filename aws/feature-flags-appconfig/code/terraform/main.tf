# AWS AppConfig Feature Flags Infrastructure
# This file creates a complete feature flag management system using AWS AppConfig
# with Lambda integration, CloudWatch monitoring, and automatic rollback capabilities

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct resource names with random suffix
  app_name_with_suffix             = "${var.app_name}-${random_id.suffix.hex}"
  lambda_function_name_with_suffix = "${var.lambda_function_name}-${random_id.suffix.hex}"
  iam_role_name                   = "lambda-appconfig-role-${random_id.suffix.hex}"
  policy_name                     = "appconfig-access-policy-${random_id.suffix.hex}"
  alarm_name                      = "lambda-error-rate-${random_id.suffix.hex}"
  deployment_strategy_name        = "${var.deployment_strategy_name}-${random_id.suffix.hex}"
  
  # AppConfig Lambda extension layer ARN by region
  appconfig_layer_arn = "arn:aws:lambda:${var.aws_region}:027255383542:layer:AWS-AppConfig-Extension:82"
  
  # Common tags
  common_tags = merge(
    {
      Project     = "feature-flags-appconfig"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "feature-flags-appconfig"
    },
    var.tags
  )
}

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# AppConfig Application
# The top-level container for feature flag configurations and environments
resource "aws_appconfig_application" "feature_flags" {
  name        = local.app_name_with_suffix
  description = "Feature flag demo application for safe deployments"

  tags = local.common_tags
}

# Service-linked role for AppConfig monitoring
# Required for AppConfig to access CloudWatch alarms for automatic rollback
resource "aws_iam_service_linked_role" "appconfig" {
  aws_service_name = "appconfig.amazonaws.com"
  description      = "Service-linked role for AppConfig monitoring"
}

# CloudWatch Alarm for monitoring Lambda function errors
# This alarm triggers automatic rollback when error rates exceed threshold
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = local.alarm_name
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "Monitor Lambda function error rate for feature flag rollback"
  alarm_actions       = []

  dimensions = {
    FunctionName = local.lambda_function_name_with_suffix
  }

  tags = local.common_tags
  
  depends_on = [aws_lambda_function.feature_flag_demo]
}

# AppConfig Environment with monitoring integration
# Represents the deployment target with automatic rollback capabilities
resource "aws_appconfig_environment" "production" {
  name           = var.environment
  description    = "Production environment with automated rollback"
  application_id = aws_appconfig_application.feature_flags.id

  monitor {
    alarm_arn      = aws_cloudwatch_metric_alarm.lambda_errors.arn
    alarm_role_arn = aws_iam_service_linked_role.appconfig.arn
  }

  tags = local.common_tags
}

# Feature Flag Configuration Profile
# Defines the structure and validation rules for feature flags
resource "aws_appconfig_configuration_profile" "feature_flags" {
  application_id = aws_appconfig_application.feature_flags.id
  name           = var.configuration_profile_name
  description    = "Feature flags for gradual rollout and A/B testing"
  location_uri   = "hosted"
  type           = "AWS.AppConfig.FeatureFlags"

  tags = local.common_tags
}

# Deployment Strategy for gradual rollout
# Controls how feature flag changes are rolled out with monitoring
resource "aws_appconfig_deployment_strategy" "gradual_rollout" {
  name                           = local.deployment_strategy_name
  description                    = "Gradual rollout over ${var.deployment_duration_minutes} minutes with monitoring"
  deployment_duration_in_minutes = var.deployment_duration_minutes
  final_bake_time_in_minutes     = var.final_bake_time_minutes
  growth_factor                  = var.growth_factor
  growth_type                    = "LINEAR"
  replicate_to                   = "NONE"

  tags = local.common_tags
}

# Initial Feature Flag Configuration
# Defines the actual feature flags with their states and attributes
resource "aws_appconfig_hosted_configuration_version" "feature_flags" {
  application_id           = aws_appconfig_application.feature_flags.id
  configuration_profile_id = aws_appconfig_configuration_profile.feature_flags.configuration_profile_id
  content_type             = "application/json"

  content = jsonencode({
    flags = {
      "new-checkout-flow" = {
        name    = "new-checkout-flow"
        enabled = var.initial_feature_flags.new_checkout_flow.enabled
        attributes = {
          "rollout-percentage" = {
            constraints = {
              type     = "number"
              required = true
            }
          }
          "target-audience" = {
            constraints = {
              type     = "string"
              required = false
            }
          }
        }
      }
      "enhanced-search" = {
        name    = "enhanced-search"
        enabled = var.initial_feature_flags.enhanced_search.enabled
        attributes = {
          "search-algorithm" = {
            constraints = {
              type     = "string"
              required = true
            }
          }
          "cache-ttl" = {
            constraints = {
              type     = "number"
              required = false
            }
          }
        }
      }
      "premium-features" = {
        name    = "premium-features"
        enabled = var.initial_feature_flags.premium_features.enabled
        attributes = {
          "feature-list" = {
            constraints = {
              type     = "string"
              required = false
            }
          }
        }
      }
    }
    attributes = {
      "rollout-percentage" = {
        number = var.initial_feature_flags.new_checkout_flow.rollout_percentage
      }
      "target-audience" = {
        string = var.initial_feature_flags.new_checkout_flow.target_audience
      }
      "search-algorithm" = {
        string = var.initial_feature_flags.enhanced_search.search_algorithm
      }
      "cache-ttl" = {
        number = var.initial_feature_flags.enhanced_search.cache_ttl
      }
      "feature-list" = {
        string = var.initial_feature_flags.premium_features.feature_list
      }
    }
  })

  description = "Initial feature flag configuration"
}

# IAM Trust Policy for Lambda
# Defines which service can assume the Lambda execution role
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

# IAM Policy for AppConfig Access
# Defines permissions needed for Lambda to retrieve feature flag configurations
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

# IAM Role for Lambda Function
# Provides necessary permissions for Lambda to access AppConfig and CloudWatch
resource "aws_iam_role" "lambda_execution" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = local.common_tags
}

# Attach basic Lambda execution policy for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for AppConfig access
resource "aws_iam_policy" "appconfig_access" {
  name        = local.policy_name
  description = "Allow Lambda function to access AppConfig"
  policy      = data.aws_iam_policy_document.appconfig_access.json

  tags = local.common_tags
}

# Attach AppConfig access policy to Lambda role
resource "aws_iam_role_policy_attachment" "appconfig_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.appconfig_access.arn
}

# Create deployment package for Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      app_id     = aws_appconfig_application.feature_flags.id
      env_id     = aws_appconfig_environment.production.environment_id
      profile_id = aws_appconfig_configuration_profile.feature_flags.configuration_profile_id
    })
    filename = "lambda_function.py"
  }
}

# Lambda Function with AppConfig Integration
# Demonstrates how applications retrieve and use feature flag configurations
resource "aws_lambda_function" "feature_flag_demo" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name_with_suffix
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # AppConfig Lambda extension layer for efficient configuration retrieval
  layers = [local.appconfig_layer_arn]

  environment {
    variables = {
      APP_ID     = aws_appconfig_application.feature_flags.id
      ENV_ID     = aws_appconfig_environment.production.environment_id
      PROFILE_ID = aws_appconfig_configuration_profile.feature_flags.configuration_profile_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.appconfig_access,
  ]

  tags = local.common_tags
}

# Optional: Automatic deployment of initial configuration
# Deploys the feature flag configuration using the gradual rollout strategy
resource "aws_appconfig_deployment" "initial_deployment" {
  count = var.enable_auto_deployment ? 1 : 0

  application_id           = aws_appconfig_application.feature_flags.id
  configuration_profile_id = aws_appconfig_configuration_profile.feature_flags.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.feature_flags.version_number
  deployment_strategy_id   = aws_appconfig_deployment_strategy.gradual_rollout.id
  environment_id          = aws_appconfig_environment.production.environment_id
  description             = "Initial deployment of feature flags via Terraform"

  tags = local.common_tags
  
  depends_on = [
    aws_lambda_function.feature_flag_demo,
    aws_cloudwatch_metric_alarm.lambda_errors
  ]
}