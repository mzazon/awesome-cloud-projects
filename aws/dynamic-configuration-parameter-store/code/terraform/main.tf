# ===================================
# Dynamic Configuration with Parameter Store
# ===================================
#
# This Terraform configuration creates a serverless configuration management system
# using AWS Systems Manager Parameter Store, Lambda functions, and EventBridge.
# The solution provides real-time configuration updates with intelligent caching
# and comprehensive monitoring capabilities.

# ===================================
# DATA SOURCES
# ===================================

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# ===================================
# LOCAL VALUES
# ===================================

locals {
  # Parameters and Secrets Extension layer ARNs by region
  # https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html
  extension_layer_arns = {
    us-east-1      = "arn:aws:lambda:us-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    us-east-2      = "arn:aws:lambda:us-east-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    us-west-1      = "arn:aws:lambda:us-west-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    us-west-2      = "arn:aws:lambda:us-west-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    eu-west-1      = "arn:aws:lambda:eu-west-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    eu-west-2      = "arn:aws:lambda:eu-west-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    eu-west-3      = "arn:aws:lambda:eu-west-3:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    eu-central-1   = "arn:aws:lambda:eu-central-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    eu-north-1     = "arn:aws:lambda:eu-north-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ap-northeast-1 = "arn:aws:lambda:ap-northeast-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ap-northeast-2 = "arn:aws:lambda:ap-northeast-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ap-southeast-1 = "arn:aws:lambda:ap-southeast-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ap-southeast-2 = "arn:aws:lambda:ap-southeast-2:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ap-south-1     = "arn:aws:lambda:ap-south-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    ca-central-1   = "arn:aws:lambda:ca-central-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
    sa-east-1      = "arn:aws:lambda:sa-east-1:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
  }
  
  # Select the appropriate layer ARN for the current region
  extension_layer_arn = lookup(local.extension_layer_arns, data.aws_region.current.name, 
    "arn:aws:lambda:${data.aws_region.current.name}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:11"
  )
  
  # Generate unique resource names with random suffix
  resource_suffix = random_id.suffix.hex
  
  # Common tags to apply to all resources
  common_tags = merge(var.tags, {
    Name        = "${var.function_name}-${local.resource_suffix}"
    ManagedBy   = "terraform"
    CreatedDate = timestamp()
  })
}

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# ===================================
# PARAMETER STORE PARAMETERS
# ===================================

# Database host configuration
resource "aws_ssm_parameter" "database_host" {
  name        = "${var.parameter_prefix}/database/host"
  description = "Database host endpoint for application configuration"
  type        = "String"
  value       = var.database_host
  
  tags = merge(local.common_tags, {
    ParameterType = "Configuration"
    Category      = "Database"
  })
}

# Database port configuration
resource "aws_ssm_parameter" "database_port" {
  name        = "${var.parameter_prefix}/database/port"
  description = "Database port number for application configuration"
  type        = "String"
  value       = var.database_port
  
  tags = merge(local.common_tags, {
    ParameterType = "Configuration"
    Category      = "Database"
  })
}

# Database password (encrypted)
resource "aws_ssm_parameter" "database_password" {
  name        = "${var.parameter_prefix}/database/password"
  description = "Database password (encrypted) for application configuration"
  type        = "SecureString"
  value       = var.database_password
  
  tags = merge(local.common_tags, {
    ParameterType = "Secret"
    Category      = "Database"
  })
}

# API timeout configuration
resource "aws_ssm_parameter" "api_timeout" {
  name        = "${var.parameter_prefix}/api/timeout"
  description = "API timeout in seconds for application configuration"
  type        = "String"
  value       = var.api_timeout
  
  tags = merge(local.common_tags, {
    ParameterType = "Configuration"
    Category      = "API"
  })
}

# Feature flag for new UI
resource "aws_ssm_parameter" "feature_new_ui" {
  name        = "${var.parameter_prefix}/features/new-ui"
  description = "Feature flag for new UI functionality"
  type        = "String"
  value       = var.feature_new_ui
  
  tags = merge(local.common_tags, {
    ParameterType = "FeatureFlag"
    Category      = "UI"
  })
}

# ===================================
# IAM RESOURCES
# ===================================

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role-${local.resource_suffix}"
  
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
    ResourceType = "IAM-Role"
    Purpose      = "Lambda-Execution"
  })
}

# Custom IAM policy for Parameter Store access and CloudWatch metrics
resource "aws_iam_policy" "parameter_store_policy" {
  name        = "ParameterStoreAccessPolicy-${local.resource_suffix}"
  description = "IAM policy for Lambda to access Parameter Store and CloudWatch metrics"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_prefix}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "arn:aws:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    ResourceType = "IAM-Policy"
    Purpose      = "Parameter-Store-Access"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Attach custom Parameter Store policy
resource "aws_iam_role_policy_attachment" "parameter_store_policy" {
  policy_arn = aws_iam_policy.parameter_store_policy.arn
  role       = aws_iam_role.lambda_role.name
}

# ===================================
# LAMBDA FUNCTION
# ===================================

# Create Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      parameter_prefix = var.parameter_prefix
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for dynamic configuration management
resource "aws_lambda_function" "config_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.function_name}-${local.resource_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # AWS Parameters and Secrets Extension layer
  layers = [local.extension_layer_arn]
  
  # Environment variables for configuration
  environment {
    variables = {
      PARAMETER_PREFIX               = var.parameter_prefix
      SSM_PARAMETER_STORE_TTL       = var.parameters_extension_ttl
      PARAMETERS_SECRETS_EXTENSION_HTTP_PORT = "2773"
    }
  }
  
  # Ensure IAM role is ready before creating function
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.parameter_store_policy
  ]
  
  tags = merge(local.common_tags, {
    ResourceType = "Lambda-Function"
    Purpose      = "Configuration-Management"
  })
}

# ===================================
# EVENTBRIDGE RESOURCES
# ===================================

# EventBridge rule to capture Parameter Store change events
resource "aws_cloudwatch_event_rule" "parameter_change_rule" {
  name        = "${var.function_name}-parameter-change-${local.resource_suffix}"
  description = "Capture Parameter Store change events for configuration management"
  
  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name = [
        {
          prefix = var.parameter_prefix
        }
      ]
    }
  })
  
  tags = merge(local.common_tags, {
    ResourceType = "EventBridge-Rule"
    Purpose      = "Parameter-Change-Detection"
  })
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.parameter_change_rule.name
  target_id = "ConfigManagerLambdaTarget"
  arn       = aws_lambda_function.config_manager.arn
}

# Lambda permission to allow EventBridge to invoke the function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.parameter_change_rule.arn
}

# ===================================
# CLOUDWATCH MONITORING
# ===================================

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "ConfigManager-Errors-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "This metric monitors Lambda function errors for configuration management"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.config_manager.function_name
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch-Alarm"
    Purpose      = "Error-Monitoring"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "ConfigManager-Duration-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.duration_threshold
  alarm_description   = "This metric monitors Lambda function execution duration"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.config_manager.function_name
  }
  
  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch-Alarm"
    Purpose      = "Performance-Monitoring"
  })
}

# CloudWatch alarm for configuration retrieval failures
resource "aws_cloudwatch_metric_alarm" "config_failures" {
  alarm_name          = "ConfigManager-RetrievalFailures-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedParameterRetrievals"
  namespace           = "ConfigManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.failure_threshold
  alarm_description   = "This metric monitors configuration parameter retrieval failures"
  alarm_actions       = []
  
  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch-Alarm"
    Purpose      = "Config-Failure-Monitoring"
  })
}

# CloudWatch dashboard for comprehensive monitoring
resource "aws_cloudwatch_dashboard" "config_manager" {
  dashboard_name = "ConfigManager-${local.resource_suffix}"
  
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.config_manager.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["ConfigManager", "SuccessfulParameterRetrievals"],
            [".", "FailedParameterRetrievals"],
            [".", "ConfigurationErrors"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Configuration Management Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.config_manager.function_name}'\n| fields @timestamp, @message\n| filter @message like /Configuration loaded/\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Configuration Load Events"
          view    = "table"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    ResourceType = "CloudWatch-Dashboard"
    Purpose      = "Comprehensive-Monitoring"
  })
}