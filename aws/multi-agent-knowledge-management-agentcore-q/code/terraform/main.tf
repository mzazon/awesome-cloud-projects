# Main Terraform configuration for Multi-Agent Knowledge Management System
# Implements enterprise-grade multi-agent architecture using AWS Bedrock AgentCore and Q Business

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming and tagging
  name_suffix = random_id.suffix.hex
  common_name = "${var.project_name}-${local.name_suffix}"
  
  # Current account and region
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Domain-specific bucket names
  bucket_names = {
    for domain, config in var.knowledge_domains :
    domain => "${domain}-kb-${local.name_suffix}"
  }
  
  # Agent function names
  agent_function_names = {
    for agent, config in var.agent_configurations :
    agent => "${agent}-agent-${local.name_suffix}"
  }
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "multi-agent-knowledge-management-agentcore-q"
    Suffix      = local.name_suffix
  }
}

#------------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#------------------------------------------------------------------------------

# IAM role for Lambda functions and Q Business
resource "aws_iam_role" "agent_execution_role" {
  name               = "AgentExecutionRole-${local.name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "qbusiness.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "AgentExecutionRole-${local.name_suffix}"
  })
}

# Attach AWS managed policies for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.agent_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach AWS managed policy for Bedrock access
resource "aws_iam_role_policy_attachment" "bedrock_full_access" {
  role       = aws_iam_role.agent_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# Custom policy for S3, DynamoDB, and Lambda invoke permissions
resource "aws_iam_policy" "agent_custom_permissions" {
  name        = "AgentCustomPermissions-${local.name_suffix}"
  description = "Custom permissions for multi-agent system operations"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 permissions for knowledge base access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ]
        Resource = [
          for bucket_name in local.bucket_names :
          "arn:aws:s3:::${bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          for bucket_name in local.bucket_names :
          "arn:aws:s3:::${bucket_name}"
        ]
      },
      # DynamoDB permissions for session management
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.agent_sessions.arn
      },
      # Lambda invoke permissions for agent coordination
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${local.region}:${local.account_id}:function:*-agent-${local.name_suffix}"
      },
      # Q Business permissions
      {
        Effect = "Allow"
        Action = [
          "qbusiness:*"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "agent_custom_permissions" {
  role       = aws_iam_role.agent_execution_role.name
  policy_arn = aws_iam_policy.agent_custom_permissions.arn
}

#------------------------------------------------------------------------------
# S3 BUCKETS FOR KNOWLEDGE BASES
#------------------------------------------------------------------------------

# S3 buckets for domain-specific knowledge storage
resource "aws_s3_bucket" "knowledge_buckets" {
  for_each = var.knowledge_domains
  bucket   = local.bucket_names[each.key]
  
  tags = merge(local.common_tags, {
    Name   = local.bucket_names[each.key]
    Domain = each.key
  })
}

# Enable versioning for knowledge buckets
resource "aws_s3_bucket_versioning" "knowledge_buckets_versioning" {
  for_each = var.enable_versioning ? var.knowledge_domains : {}
  bucket   = aws_s3_bucket.knowledge_buckets[each.key].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for knowledge buckets
resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge_buckets_encryption" {
  for_each = var.enable_encryption ? var.knowledge_domains : {}
  bucket   = aws_s3_bucket.knowledge_buckets[each.key].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for knowledge buckets
resource "aws_s3_bucket_public_access_block" "knowledge_buckets_pab" {
  for_each = var.knowledge_domains
  bucket   = aws_s3_bucket.knowledge_buckets[each.key].id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#------------------------------------------------------------------------------
# SAMPLE KNOWLEDGE DOCUMENTS
#------------------------------------------------------------------------------

# Sample finance policy document
resource "aws_s3_object" "finance_policy" {
  bucket = aws_s3_bucket.knowledge_buckets["finance"].id
  key    = "finance-policy.txt"
  content = <<-EOT
    Finance Policy Documentation:
    
    Expense Approval Process:
    - All expenses over $1000 require manager approval
    - Expenses over $5000 require director approval
    - Capital expenditures over $10000 require CFO approval
    
    Budget Management:
    - Quarterly budget reviews conducted in March, June, September, December
    - Department budget allocations updated annually in January
    - Emergency budget requests require 48-hour approval window
    
    Travel and Reimbursement:
    - Travel reimbursement requires receipts within 30 days of completion
    - International travel requires pre-approval 2 weeks in advance
    - Meal allowances: $75 domestic, $100 international per day
  EOT
  
  metadata = {
    department = "finance"
    type       = "policy"
    version    = "1.0"
  }
  
  tags = merge(local.common_tags, {
    Domain = "finance"
    Type   = "policy"
  })
}

# Sample HR handbook
resource "aws_s3_object" "hr_handbook" {
  bucket = aws_s3_bucket.knowledge_buckets["hr"].id
  key    = "hr-handbook.txt"
  content = <<-EOT
    HR Handbook and Employee Policies:
    
    Onboarding Process:
    - Employee onboarding process takes 3-5 business days
    - IT equipment setup completed on first day
    - Benefits enrollment window: 30 days from start date
    
    Performance Management:
    - Performance reviews conducted annually in Q4
    - Mid-year check-ins scheduled in Q2
    - Performance improvement plans: 90-day duration
    
    Time Off and Remote Work:
    - Vacation requests require 2 weeks advance notice for approval
    - Remote work policy allows up to 3 days per week remote work
    - Sick leave: 10 days annually, carries over up to 5 days
    - Parental leave: 12 weeks paid, additional 4 weeks unpaid
  EOT
  
  metadata = {
    department = "hr"
    type       = "handbook"
    version    = "1.0"
  }
  
  tags = merge(local.common_tags, {
    Domain = "hr"
    Type   = "handbook"
  })
}

# Sample technical guidelines
resource "aws_s3_object" "tech_guidelines" {
  bucket = aws_s3_bucket.knowledge_buckets["technical"].id
  key    = "tech-guidelines.txt"
  content = <<-EOT
    Technical Guidelines and System Procedures:
    
    Development Standards:
    - All code must pass automated testing before deployment
    - Code coverage minimum: 80% for production releases
    - Security scans required for all external-facing applications
    
    Infrastructure Management:
    - Database backups performed nightly at 2 AM UTC
    - Backup retention: 30 days local, 90 days archived
    - Disaster recovery testing: quarterly
    
    API and Security Standards:
    - API rate limits: 1000 requests per minute per client
    - Authentication required for all API endpoints
    - SSL/TLS 1.2 minimum for all communications
    - Security patching: within 48 hours for critical vulnerabilities
  EOT
  
  metadata = {
    department = "engineering"
    type       = "guidelines"
    version    = "1.0"
  }
  
  tags = merge(local.common_tags, {
    Domain = "technical"
    Type   = "guidelines"
  })
}

#------------------------------------------------------------------------------
# Q BUSINESS APPLICATION AND DATA SOURCES
#------------------------------------------------------------------------------

# Note: Q Business resources may require manual setup in some regions
# This configuration provides the Terraform structure for when fully supported

# Q Business Application (commented out due to limited Terraform support)
# Uncomment when aws_qbusiness_application resource is available in your region
/*
resource "aws_qbusiness_application" "knowledge_management" {
  display_name = var.q_business_app_name
  description  = var.q_business_app_description
  role_arn     = aws_iam_role.agent_execution_role.arn
  
  tags = local.common_tags
}
*/

#------------------------------------------------------------------------------
# DYNAMODB TABLE FOR SESSION MANAGEMENT
#------------------------------------------------------------------------------

# DynamoDB table for agent session management and context
resource "aws_dynamodb_table" "agent_sessions" {
  name           = "agent-sessions-${local.name_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "sessionId"
  range_key      = "timestamp"
  
  attribute {
    name = "sessionId"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "S"
  }
  
  # Enable TTL for automatic session cleanup
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  # Enable DynamoDB Streams for real-time session monitoring
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # Enable server-side encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled = true
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "agent-sessions-${local.name_suffix}"
  })
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTIONS FOR AGENT IMPLEMENTATIONS
#------------------------------------------------------------------------------

# Create Lambda deployment packages
data "archive_file" "supervisor_agent" {
  type        = "zip"
  output_path = "${path.module}/supervisor-agent.zip"
  source {
    content = templatefile("${path.module}/lambda_code/supervisor-agent.py", {
      random_suffix = local.name_suffix
      session_table = aws_dynamodb_table.agent_sessions.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "finance_agent" {
  type        = "zip"
  output_path = "${path.module}/finance-agent.zip"
  source {
    content = templatefile("${path.module}/lambda_code/finance-agent.py", {
      q_app_id = "placeholder" # Will be replaced with actual Q Business App ID
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "hr_agent" {
  type        = "zip"
  output_path = "${path.module}/lambda_code/hr-agent.zip"
  source {
    content = templatefile("${path.module}/lambda_code/hr-agent.py", {
      q_app_id = "placeholder" # Will be replaced with actual Q Business App ID
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "technical_agent" {
  type        = "zip"
  output_path = "${path.module}/lambda_code/technical-agent.zip"
  source {
    content = templatefile("${path.module}/lambda_code/technical-agent.py", {
      q_app_id = "placeholder" # Will be replaced with actual Q Business App ID
    })
    filename = "lambda_function.py"
  }
}

# Supervisor Agent Lambda Function
resource "aws_lambda_function" "supervisor_agent" {
  filename         = data.archive_file.supervisor_agent.output_path
  function_name    = local.agent_function_names["supervisor"]
  role            = aws_iam_role.agent_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.supervisor_agent.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.agent_configurations["supervisor"]["timeout"]
  memory_size     = var.agent_configurations["supervisor"]["memory_size"]
  
  environment {
    variables = {
      RANDOM_SUFFIX  = local.name_suffix
      SESSION_TABLE  = aws_dynamodb_table.agent_sessions.name
      PROJECT_NAME   = var.project_name
      ENVIRONMENT    = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.agent_function_names["supervisor"]
    Agent       = "supervisor"
    Description = var.agent_configurations["supervisor"]["description"]
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.agent_custom_permissions,
    aws_cloudwatch_log_group.supervisor_agent_logs
  ]
}

# Finance Agent Lambda Function
resource "aws_lambda_function" "finance_agent" {
  filename         = data.archive_file.finance_agent.output_path
  function_name    = local.agent_function_names["finance"]
  role            = aws_iam_role.agent_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.finance_agent.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.agent_configurations["finance"]["timeout"]
  memory_size     = var.agent_configurations["finance"]["memory_size"]
  
  environment {
    variables = {
      Q_APP_ID     = "placeholder" # Manual configuration required for Q Business
      DOMAIN       = "finance"
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.agent_function_names["finance"]
    Agent       = "finance"
    Description = var.agent_configurations["finance"]["description"]
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.agent_custom_permissions,
    aws_cloudwatch_log_group.finance_agent_logs
  ]
}

# HR Agent Lambda Function
resource "aws_lambda_function" "hr_agent" {
  filename         = data.archive_file.hr_agent.output_path
  function_name    = local.agent_function_names["hr"]
  role            = aws_iam_role.agent_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.hr_agent.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.agent_configurations["hr"]["timeout"]
  memory_size     = var.agent_configurations["hr"]["memory_size"]
  
  environment {
    variables = {
      Q_APP_ID     = "placeholder" # Manual configuration required for Q Business
      DOMAIN       = "hr"
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.agent_function_names["hr"]
    Agent       = "hr"
    Description = var.agent_configurations["hr"]["description"]
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.agent_custom_permissions,
    aws_cloudwatch_log_group.hr_agent_logs
  ]
}

# Technical Agent Lambda Function
resource "aws_lambda_function" "technical_agent" {
  filename         = data.archive_file.technical_agent.output_path
  function_name    = local.agent_function_names["technical"]
  role            = aws_iam_role.agent_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.technical_agent.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.agent_configurations["technical"]["timeout"]
  memory_size     = var.agent_configurations["technical"]["memory_size"]
  
  environment {
    variables = {
      Q_APP_ID     = "placeholder" # Manual configuration required for Q Business
      DOMAIN       = "technical"
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.agent_function_names["technical"]
    Agent       = "technical"
    Description = var.agent_configurations["technical"]["description"]
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.agent_custom_permissions,
    aws_cloudwatch_log_group.technical_agent_logs
  ]
}

#------------------------------------------------------------------------------
# CLOUDWATCH LOG GROUPS
#------------------------------------------------------------------------------

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "supervisor_agent_logs" {
  name              = "/aws/lambda/${local.agent_function_names["supervisor"]}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name  = "supervisor-agent-logs"
    Agent = "supervisor"
  })
}

resource "aws_cloudwatch_log_group" "finance_agent_logs" {
  name              = "/aws/lambda/${local.agent_function_names["finance"]}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name  = "finance-agent-logs"
    Agent = "finance"
  })
}

resource "aws_cloudwatch_log_group" "hr_agent_logs" {
  name              = "/aws/lambda/${local.agent_function_names["hr"]}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name  = "hr-agent-logs"
    Agent = "hr"
  })
}

resource "aws_cloudwatch_log_group" "technical_agent_logs" {
  name              = "/aws/lambda/${local.agent_function_names["technical"]}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name  = "technical-agent-logs"
    Agent = "technical"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.common_name}"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "api-gateway-logs"
  })
}

#------------------------------------------------------------------------------
# API GATEWAY FOR MULTI-AGENT ORCHESTRATION
#------------------------------------------------------------------------------

# API Gateway HTTP API for multi-agent system
resource "aws_apigatewayv2_api" "multi_agent_api" {
  name          = "${local.common_name}-api"
  protocol_type = "HTTP"
  description   = "Multi-agent knowledge management API with enterprise features"
  
  cors_configuration {
    allow_credentials = false
    allow_headers     = var.cors_allowed_headers
    allow_methods     = var.cors_allowed_methods
    allow_origins     = var.cors_allowed_origins
    max_age          = 300
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.common_name}-api"
  })
}

# Integration with supervisor Lambda function
resource "aws_apigatewayv2_integration" "supervisor_integration" {
  api_id           = aws_apigatewayv2_api.multi_agent_api.id
  integration_type = "AWS_PROXY"
  integration_method = "POST"
  integration_uri  = aws_lambda_function.supervisor_agent.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = var.lambda_timeout * 1000 - 1000 # Slightly less than Lambda timeout
}

# Route for query processing
resource "aws_apigatewayv2_route" "query_route" {
  api_id    = aws_apigatewayv2_api.multi_agent_api.id
  route_key = "POST /query"
  target    = "integrations/${aws_apigatewayv2_integration.supervisor_integration.id}"
  authorization_type = "NONE"
}

# Route for health checks
resource "aws_apigatewayv2_route" "health_route" {
  api_id    = aws_apigatewayv2_api.multi_agent_api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.supervisor_integration.id}"
  authorization_type = "NONE"
}

# Production stage with throttling and logging
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.multi_agent_api.id
  name        = "prod"
  auto_deploy = true
  description = "Production stage for multi-agent knowledge management"
  
  throttle_settings {
    burst_limit = var.api_throttle_burst_limit
    rate_limit  = var.api_throttle_rate_limit
  }
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      routeKey      = "$context.routeKey"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseLength = "$context.responseLength"
      error = {
        message = "$context.error.message"
        messageString = "$context.error.messageString"
      }
      integration = {
        status = "$context.integrationStatus"
        latency = "$context.integrationLatency"
        requestId = "$context.integration.requestId"
        error = "$context.integration.error"
      }
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "prod-stage"
  })
  
  depends_on = [aws_cloudwatch_log_group.api_gateway_logs]
}

# Grant API Gateway permission to invoke Lambda functions
resource "aws_lambda_permission" "api_gateway_supervisor" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.supervisor_agent.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.multi_agent_api.execution_arn}/*/*"
}