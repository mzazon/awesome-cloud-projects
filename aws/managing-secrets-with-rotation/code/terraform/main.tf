# AWS Secrets Manager Infrastructure
# This file contains the main infrastructure resources for the secrets management solution

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result
  
  secret_name              = var.secret_name != "" ? var.secret_name : "${local.name_prefix}-db-credentials-${local.suffix}"
  lambda_function_name     = "${local.name_prefix}-rotation-${local.suffix}"
  iam_role_name           = "${local.name_prefix}-rotation-role-${local.suffix}"
  kms_key_alias           = "alias/${local.name_prefix}-key-${local.suffix}"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      Application = "SecretsManager"
    },
    var.additional_tags
  )
}

# KMS Key for encrypting secrets
resource "aws_kms_key" "secrets_manager" {
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

# KMS Key Alias for easier reference
resource "aws_kms_alias" "secrets_manager" {
  name          = local.kms_key_alias
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# Generate random password for initial secret
resource "random_password" "db_password" {
  length  = var.password_length
  special = true
  
  # Exclude problematic characters for database passwords
  override_special = "!#$%&*+-=?^_`|~"
}

# AWS Secrets Manager Secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = local.secret_name
  description = "Database credentials for ${var.project_name} application"
  kms_key_id  = aws_kms_key.secrets_manager.arn
  
  # Enable automatic rotation if specified
  replica {
    region     = data.aws_region.current.name
    kms_key_id = aws_kms_key.secrets_manager.arn
  }
  
  tags = merge(local.common_tags, {
    Name        = local.secret_name
    SecretType  = "Database"
    Application = var.project_name
  })
}

# Secret version with database credentials
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  
  secret_string = jsonencode({
    engine   = var.database_config.engine
    host     = var.database_config.host
    username = var.database_config.username
    password = random_password.db_password.result
    dbname   = var.database_config.dbname
    port     = var.database_config.port
  })
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IAM Role for Lambda rotation function
resource "aws_iam_role" "lambda_rotation" {
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
  
  tags = merge(local.common_tags, {
    Name = local.iam_role_name
  })
}

# IAM Policy for Lambda rotation function
resource "aws_iam_role_policy" "lambda_rotation" {
  name = "${local.iam_role_name}-policy"
  role = aws_iam_role.lambda_rotation.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:GetRandomPassword"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.secrets_manager.arn
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create Lambda deployment package
data "archive_file" "lambda_rotation" {
  type        = "zip"
  output_path = "${path.module}/lambda_rotation.zip"
  
  source {
    content = templatefile("${path.module}/lambda_rotation.py.tpl", {
      secret_name = local.secret_name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for secret rotation
resource "aws_lambda_function" "rotation" {
  filename         = data.archive_file.lambda_rotation.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_rotation.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_rotation.output_base64sha256
  
  description = "Lambda function for rotating Secrets Manager secrets"
  
  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_rotation
  ]
}

# Grant Secrets Manager permission to invoke Lambda
resource "aws_lambda_permission" "secrets_manager_invoke" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

# Configure automatic rotation (conditional)
resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  count = var.enable_rotation ? 1 : 0
  
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  
  rotation_rules {
    automatically_after_days = 7
  }
  
  depends_on = [aws_lambda_permission.secrets_manager_invoke]
}

# Resource-based policy for cross-account access (conditional)
resource "aws_secretsmanager_secret_policy" "cross_account" {
  count = length(var.cross_account_principals) > 0 ? 1 : 0
  
  secret_arn = aws_secretsmanager_secret.db_credentials.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.cross_account_principals
        }
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*"
        Condition = {
          StringEquals = {
            "secretsmanager:ResourceTag/Environment" = var.environment
          }
        }
      }
    ]
  })
  
  block_public_policy = true
}

# CloudWatch Dashboard for monitoring (conditional)
resource "aws_cloudwatch_dashboard" "secrets_manager" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-secrets-manager-${local.suffix}"
  
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
            ["AWS/SecretsManager", "RotationSucceeded", "SecretName", local.secret_name],
            ["AWS/SecretsManager", "RotationFailed", "SecretName", local.secret_name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Secret Rotation Status"
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
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Rotation Function Metrics"
        }
      }
    ]
  })
}

# CloudWatch Alarm for rotation failures (conditional)
resource "aws_cloudwatch_metric_alarm" "rotation_failure" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-rotation-failure-${local.suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RotationFailed"
  namespace           = "AWS/SecretsManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors secret rotation failures"
  alarm_actions       = [] # Add SNS topic ARN if needed
  
  dimensions = {
    SecretName = local.secret_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rotation-failure-alarm"
  })
}

# CloudWatch Alarm for Lambda errors (conditional)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [] # Add SNS topic ARN if needed
  
  dimensions = {
    FunctionName = local.lambda_function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors-alarm"
  })
}