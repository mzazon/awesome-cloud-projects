# ================================================================================
# Enterprise Identity Federation with Bedrock AgentCore - Main Configuration
# ================================================================================
# This Terraform configuration deploys a comprehensive enterprise identity 
# federation system using Bedrock AgentCore for AI agent management, integrated 
# with Cognito User Pools for SAML federation with corporate identity providers.

terraform {
  required_version = ">= 1.0"
}

# ================================================================================
# Local Variables and Random Resources
# ================================================================================

locals {
  common_tags = {
    Environment          = var.environment
    Project             = "BedrockAgentCore"
    Purpose             = "Enterprise-AI-Identity"
    DeployedBy          = "Terraform"
    Recipe              = "enterprise-identity-federation-bedrock-agentcore"
  }

  # Permission mapping for different departments
  permission_mapping = {
    engineering = {
      maxAgents       = 10
      allowedActions  = ["create", "read", "update", "delete"]
      resourceAccess  = ["bedrock", "s3", "lambda"]
    }
    security = {
      maxAgents       = 5
      allowedActions  = ["create", "read", "update", "delete", "audit"]
      resourceAccess  = ["bedrock", "iam", "cloudtrail"]
    }
    general = {
      maxAgents       = 2
      allowedActions  = ["read"]
      resourceAccess  = ["bedrock"]
    }
  }
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# ================================================================================
# Data Sources
# ================================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ================================================================================
# Cognito User Pool for Enterprise Federation
# ================================================================================

# Create Cognito User Pool with enterprise security settings
resource "aws_cognito_user_pool" "enterprise_pool" {
  name = "${var.pool_name}-${random_id.suffix.hex}"

  # Enterprise-grade password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase               = true
    require_numbers                 = true
    require_symbols                 = true
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  # Multi-factor authentication configuration
  mfa_configuration = "OPTIONAL"

  # Account recovery settings
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User pool add-ons for enhanced security
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # Verification message template
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  # Lambda triggers for custom authentication logic
  lambda_config {
    pre_authentication  = aws_lambda_function.auth_handler.arn
    post_authentication = aws_lambda_function.auth_handler.arn
    custom_message      = aws_lambda_function.auth_handler.arn
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  tags = local.common_tags

  depends_on = [aws_lambda_permission.cognito_invoke]
}

# ================================================================================
# SAML Identity Provider Integration
# ================================================================================

# Configure SAML identity provider for enterprise federation
resource "aws_cognito_identity_provider" "enterprise_saml" {
  user_pool_id  = aws_cognito_user_pool.enterprise_pool.id
  provider_name = "EnterpriseSSO"
  provider_type = "SAML"

  provider_details = {
    MetadataURL                = var.idp_metadata_url
    SLORedirectBindingURI     = var.idp_slo_url
    SSORedirectBindingURI     = var.idp_sso_url
  }

  attribute_mapping = {
    email                = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
    name                 = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
    "custom:department"  = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department"
  }
}

# ================================================================================
# Lambda Function for Custom Authentication Flow
# ================================================================================

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "agent-auth-handler-${random_id.suffix.hex}-role"

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

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Additional IAM policy for Lambda to access required services
resource "aws_iam_role_policy" "lambda_additional_permissions" {
  name = "AgentAuthHandlerPolicy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPool",
          "cognito-idp:ListUsers",
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = [
          aws_cognito_user_pool.enterprise_pool.arn,
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/enterprise/agentcore/*"
        ]
      }
    ]
  })
}

# Create Lambda function archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/auth-handler.zip"
  
  source {
    content = templatefile("${path.module}/lambda/auth-handler.py", {
      permission_mapping = jsonencode(local.permission_mapping)
      authorized_domains = jsonencode(var.authorized_domains)
    })
    filename = "auth-handler.py"
  }
}

# Deploy Lambda function for authentication handling
resource "aws_lambda_function" "auth_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "agent-auth-handler-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "auth-handler.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      USER_POOL_ID        = aws_cognito_user_pool.enterprise_pool.id
      AGENTCORE_IDENTITY  = var.agentcore_identity_name
      PERMISSION_MAPPING  = jsonencode(local.permission_mapping)
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Enterprise-AI-Authentication"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_additional_permissions,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/agent-auth-handler-${random_id.suffix.hex}"
  retention_in_days = 14
  tags              = local.common_tags
}

# Grant Cognito permission to invoke Lambda
resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "CognitoInvokePermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_handler.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/*"
}

# ================================================================================
# Bedrock AgentCore Workload Identity
# ================================================================================

# Note: Bedrock AgentCore is currently in preview and resources may not be 
# available in all regions or through Terraform. This is a placeholder for 
# when the service becomes generally available.

# Create AgentCore workload identity (placeholder - service in preview)
# resource "aws_bedrock_agentcore_workload_identity" "enterprise_agent" {
#   name = "${var.agentcore_identity_name}-${random_id.suffix.hex}"
#   
#   allowed_resource_oauth2_return_urls = var.oauth_callback_urls
#   
#   tags = local.common_tags
# }

# ================================================================================
# IAM Policies and Roles for AI Agent Access Control
# ================================================================================

# IAM policy for AgentCore service access
resource "aws_iam_policy" "agentcore_access_policy" {
  name        = "AgentCoreAccessPolicy-${random_id.suffix.hex}"
  description = "Access policy for Bedrock AgentCore AI agents"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::enterprise-ai-data-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })

  tags = local.common_tags
}

# IAM role for AI agents
resource "aws_iam_role" "agentcore_execution_role" {
  name = "AgentCoreExecutionRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to AgentCore execution role
resource "aws_iam_role_policy_attachment" "agentcore_policy_attachment" {
  role       = aws_iam_role.agentcore_execution_role.name
  policy_arn = aws_iam_policy.agentcore_access_policy.arn
}

# ================================================================================
# Cognito User Pool App Client for OAuth Flows
# ================================================================================

# Create User Pool App Client for OAuth integration
resource "aws_cognito_user_pool_client" "enterprise_client" {
  name         = "AgentCore-Enterprise-Client"
  user_pool_id = aws_cognito_user_pool.enterprise_pool.id

  # Generate client secret for secure authentication
  generate_secret = true

  # Supported identity providers
  supported_identity_providers = [
    "COGNITO",
    aws_cognito_identity_provider.enterprise_saml.provider_name
  ]

  # OAuth configuration
  callback_urls                = var.oauth_callback_urls
  logout_urls                  = var.oauth_logout_urls
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_scopes         = ["openid", "email", "profile", "aws.cognito.signin.user.admin"]
  allowed_oauth_flows_user_pool_client = true

  # Authentication flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Token validity configuration
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors for enhanced security
  prevent_user_existence_errors = "ENABLED"
}

# ================================================================================
# Systems Manager Parameter Store for Configuration
# ================================================================================

# Store integration configuration in Parameter Store
resource "aws_ssm_parameter" "integration_config" {
  name        = "/enterprise/agentcore/integration-config"
  description = "Enterprise AI agent integration configuration"
  type        = "String"
  
  value = jsonencode({
    enterpriseIntegration = {
      cognitoUserPool     = aws_cognito_user_pool.enterprise_pool.id
      agentCoreIdentity   = "${var.agentcore_identity_name}-${random_id.suffix.hex}"
      authenticationFlow  = "enterprise-saml-oauth"
      permissionMapping   = local.permission_mapping
      clientId           = aws_cognito_user_pool_client.enterprise_client.id
      lambdaHandler      = aws_lambda_function.auth_handler.arn
    }
  })

  tags = merge(local.common_tags, {
    Purpose = "AgentCore-Integration"
  })
}

# ================================================================================
# CloudWatch Dashboard for Monitoring
# ================================================================================

# Create CloudWatch dashboard for monitoring authentication events
resource "aws_cloudwatch_dashboard" "enterprise_identity_dashboard" {
  dashboard_name = "Enterprise-Identity-Federation-${random_id.suffix.hex}"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.auth_handler.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Authentication Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/agent-auth-handler-${random_id.suffix.hex}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Authentication Events"
        }
      }
    ]
  })
}

# ================================================================================
# CloudTrail for Audit Logging
# ================================================================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "enterprise-identity-audit-${random_id.suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

# Configure S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

# CloudTrail for auditing authentication events
resource "aws_cloudtrail" "enterprise_identity_audit" {
  name           = "enterprise-identity-audit-${random_id.suffix.hex}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.bucket

  # Event selectors for specific resources
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::Cognito::UserPool"
      values = ["${aws_cognito_user_pool.enterprise_pool.arn}/*"]
    }

    data_resource {
      type   = "AWS::Lambda::Function"
      values = [aws_lambda_function.auth_handler.arn]
    }
  }

  # Enable insights for enhanced monitoring
  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  tags = merge(local.common_tags, {
    Purpose = "Identity-Audit"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}