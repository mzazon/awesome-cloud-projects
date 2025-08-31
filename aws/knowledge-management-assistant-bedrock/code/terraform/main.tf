# =============================================================================
# Knowledge Management Assistant with Bedrock Agents - Main Terraform Configuration
# =============================================================================
# This Terraform configuration deploys a complete knowledge management solution
# using Amazon Bedrock Agents, Knowledge Bases, S3, Lambda, and API Gateway.
# =============================================================================

terraform {
  required_version = ">= 1.0"
}

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# S3 Bucket for Document Storage
# =============================================================================

# S3 bucket for storing enterprise documents
resource "aws_s3_bucket" "knowledge_docs" {
  bucket = "${var.bucket_prefix}-${random_string.suffix.result}"

  tags = merge(var.common_tags, {
    Name        = "Knowledge Documents Bucket"
    Component   = "Storage"
    Description = "S3 bucket for enterprise knowledge documents"
  })
}

# Enable versioning for document history
resource "aws_s3_bucket_versioning" "knowledge_docs" {
  bucket = aws_s3_bucket.knowledge_docs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for security
resource "aws_s3_bucket_server_side_encryption_configuration" "knowledge_docs" {
  bucket = aws_s3_bucket.knowledge_docs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for security
resource "aws_s3_bucket_public_access_block" "knowledge_docs" {
  bucket = aws_s3_bucket.knowledge_docs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample documents for demonstration
resource "aws_s3_object" "company_policies" {
  bucket = aws_s3_bucket.knowledge_docs.id
  key    = "documents/company-policies.txt"
  content = <<EOF
COMPANY POLICIES AND PROCEDURES

Remote Work Policy:
All employees are eligible for remote work arrangements with manager approval. Remote workers must maintain regular communication during business hours and attend quarterly in-person meetings.

Expense Reimbursement:
Business expenses must be submitted within 30 days with receipts. Meal expenses are capped at $75 per day for domestic travel and $100 for international travel.

Time Off Policy:
Employees accrue 2.5 days of PTO per month. Requests must be submitted 2 weeks in advance for planned time off.
EOF

  tags = merge(var.common_tags, {
    Name        = "Company Policies Document"
    Component   = "Sample Data"
    Description = "Sample enterprise policy document"
  })
}

resource "aws_s3_object" "technical_guide" {
  bucket = aws_s3_bucket.knowledge_docs.id
  key    = "documents/technical-guide.txt"
  content = <<EOF
TECHNICAL OPERATIONS GUIDE

Database Backup Procedures:
Daily automated backups run at 2 AM EST. Manual backups can be initiated through the admin console. Retention period is 30 days for automated backups.

Incident Response:
Priority 1: Response within 15 minutes
Priority 2: Response within 2 hours
Priority 3: Response within 24 hours

System Maintenance Windows:
Scheduled maintenance occurs first Sunday of each month from 2-6 AM EST.
EOF

  tags = merge(var.common_tags, {
    Name        = "Technical Guide Document"
    Component   = "Sample Data"
    Description = "Sample technical operations document"
  })
}

# =============================================================================
# IAM Roles and Policies
# =============================================================================

# IAM role for Bedrock Agent with minimal required permissions
resource "aws_iam_role" "bedrock_agent_role" {
  name = "BedrockAgentRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
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

  tags = merge(var.common_tags, {
    Name        = "Bedrock Agent Role"
    Component   = "IAM"
    Description = "IAM role for Bedrock Agent operations"
  })
}

# Policy for S3 access with least privilege
resource "aws_iam_policy" "bedrock_s3_access" {
  name        = "BedrockS3Access-${random_string.suffix.result}"
  description = "Minimal S3 access policy for Bedrock Agent"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.knowledge_docs.arn,
          "${aws_s3_bucket.knowledge_docs.arn}/*"
        ]
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "Bedrock S3 Access Policy"
    Component   = "IAM"
    Description = "S3 access policy for Bedrock Agent"
  })
}

# Policy for Bedrock operations
resource "aws_iam_policy" "bedrock_minimal_access" {
  name        = "BedrockMinimalAccess-${random_string.suffix.result}"
  description = "Minimal Bedrock access policy for Agent operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "Bedrock Minimal Access Policy"
    Component   = "IAM"
    Description = "Minimal Bedrock access policy for Agent"
  })
}

# Policy for OpenSearch Serverless access
resource "aws_iam_policy" "opensearch_access" {
  name        = "OpenSearchServerlessAccess-${random_string.suffix.result}"
  description = "OpenSearch Serverless access policy for Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = aws_opensearchserverless_collection.knowledge_base.arn
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "OpenSearch Access Policy"
    Component   = "IAM"
    Description = "OpenSearch Serverless access policy"
  })
}

# Attach policies to Bedrock Agent role
resource "aws_iam_role_policy_attachment" "bedrock_s3" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_minimal" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_minimal_access.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_opensearch" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.opensearch_access.arn
}

# =============================================================================
# OpenSearch Serverless Collection
# =============================================================================

# Security policy for OpenSearch Serverless collection
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "kb-encryption-policy-${random_string.suffix.result}"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource = [
          "collection/kb-collection-${random_string.suffix.result}"
        ]
      }
    ]
    AWSOwnedKey = true
  })
}

# Network policy for OpenSearch Serverless collection
resource "aws_opensearchserverless_security_policy" "network" {
  name = "kb-network-policy-${random_string.suffix.result}"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/kb-collection-${random_string.suffix.result}"
          ]
        },
        {
          ResourceType = "dashboard"
          Resource = [
            "collection/kb-collection-${random_string.suffix.result}"
          ]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

# Data access policy for OpenSearch Serverless collection
resource "aws_opensearchserverless_access_policy" "data_access" {
  name = "kb-data-policy-${random_string.suffix.result}"
  type = "data"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource = [
            "collection/kb-collection-${random_string.suffix.result}"
          ]
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource = [
            "index/kb-collection-${random_string.suffix.result}/*"
          ]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ]
      Principal = [
        aws_iam_role.bedrock_agent_role.arn,
        data.aws_caller_identity.current.arn
      ]
    }
  ])
}

# OpenSearch Serverless collection for vector storage
resource "aws_opensearchserverless_collection" "knowledge_base" {
  name = "kb-collection-${random_string.suffix.result}"
  type = "VECTORSEARCH"
  description = "Vector collection for Bedrock Knowledge Base"

  tags = merge(var.common_tags, {
    Name        = "Knowledge Base Vector Collection"
    Component   = "Vector Storage"
    Description = "OpenSearch Serverless collection for knowledge embeddings"
  })

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.data_access
  ]
}

# =============================================================================
# Bedrock Knowledge Base and Agent
# =============================================================================

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "enterprise_kb" {
  name     = "${var.knowledge_base_name}-${random_string.suffix.result}"
  role_arn = aws_iam_role.bedrock_agent_role.arn
  description = "Enterprise knowledge base for company policies and procedures"

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.knowledge_base.arn
      vector_index_name = "knowledge-index"
      field_mapping {
        vector_field   = "vector"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = merge(var.common_tags, {
    Name        = "Enterprise Knowledge Base"
    Component   = "AI Processing"
    Description = "Bedrock Knowledge Base for enterprise documents"
  })

  depends_on = [
    aws_iam_role_policy_attachment.bedrock_s3,
    aws_iam_role_policy_attachment.bedrock_minimal,
    aws_iam_role_policy_attachment.bedrock_opensearch
  ]
}

# Bedrock Knowledge Base Data Source
resource "aws_bedrockagent_data_source" "s3_documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.enterprise_kb.id
  name              = "s3-document-source"
  description       = "S3 data source for enterprise documents"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.knowledge_docs.arn
      inclusion_prefixes = ["documents/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }

  depends_on = [
    aws_s3_object.company_policies,
    aws_s3_object.technical_guide
  ]
}

# Bedrock Agent
resource "aws_bedrockagent_agent" "knowledge_assistant" {
  agent_name                  = "${var.agent_name}-${random_string.suffix.result}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  description                 = "Enterprise knowledge management assistant powered by Claude 3.5 Sonnet"
  foundation_model            = var.foundation_model
  idle_session_ttl_in_seconds = 1800

  instruction = var.agent_instruction

  tags = merge(var.common_tags, {
    Name        = "Knowledge Management Agent"
    Component   = "AI Processing"
    Description = "Bedrock Agent for knowledge management"
  })
}

# Associate Knowledge Base with Agent
resource "aws_bedrockagent_agent_knowledge_base_association" "kb_association" {
  agent_id               = aws_bedrockagent_agent.knowledge_assistant.id
  description            = "Enterprise knowledge base association"
  knowledge_base_id      = aws_bedrockagent_knowledge_base.enterprise_kb.id
  knowledge_base_state   = "ENABLED"
}

# Prepare Agent (creates version and alias)
resource "aws_bedrockagent_agent_alias" "knowledge_assistant_alias" {
  agent_alias_name = "prod"
  agent_id         = aws_bedrockagent_agent.knowledge_assistant.id
  description      = "Production alias for knowledge management agent"

  depends_on = [
    aws_bedrockagent_agent_knowledge_base_association.kb_association
  ]
}

# =============================================================================
# Lambda Function for API Integration
# =============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_bedrock_role" {
  name = "LambdaBedrockRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "Lambda Bedrock Role"
    Component   = "IAM"
    Description = "IAM role for Lambda function"
  })
}

# Policy for Lambda Bedrock access
resource "aws_iam_policy" "lambda_bedrock_access" {
  name        = "LambdaBedrockAccess-${random_string.suffix.result}"
  description = "Bedrock access policy for Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "Lambda Bedrock Access Policy"
    Component   = "IAM"
    Description = "Bedrock access policy for Lambda"
  })
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_bedrock_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_bedrock_role.name
  policy_arn = aws_iam_policy.lambda_bedrock_access.arn
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda-deployment-${random_string.suffix.result}.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      agent_id = aws_bedrockagent_agent.knowledge_assistant.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for API integration
resource "aws_lambda_function" "bedrock_agent_proxy" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_bedrock_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = 30
  memory_size     = 256
  description     = "Knowledge Management Assistant API proxy"

  environment {
    variables = {
      AGENT_ID = aws_bedrockagent_agent.knowledge_assistant.id
    }
  }

  tags = merge(var.common_tags, {
    Name        = "Bedrock Agent Proxy"
    Component   = "API Layer"
    Description = "Lambda function for API integration"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_bedrock,
    aws_bedrockagent_agent_alias.knowledge_assistant_alias
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.bedrock_agent_proxy.function_name}"
  retention_in_days = 14

  tags = merge(var.common_tags, {
    Name        = "Lambda Logs"
    Component   = "Logging"
    Description = "CloudWatch logs for Lambda function"
  })
}

# =============================================================================
# API Gateway
# =============================================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "knowledge_management_api" {
  name        = "${var.api_name}-${random_string.suffix.result}"
  description = "Knowledge Management Assistant API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.common_tags, {
    Name        = "Knowledge Management API"
    Component   = "API Layer"
    Description = "REST API for knowledge management assistant"
  })
}

# API Gateway resource for query endpoint
resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.knowledge_management_api.id
  parent_id   = aws_api_gateway_rest_api.knowledge_management_api.root_resource_id
  path_part   = "query"
}

# OPTIONS method for CORS
resource "aws_api_gateway_method" "query_options" {
  rest_api_id   = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = aws_api_gateway_method_response.query_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# POST method for query endpoint
resource "aws_api_gateway_method" "query_post" {
  rest_api_id   = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "query_post" {
  rest_api_id             = aws_api_gateway_rest_api.knowledge_management_api.id
  resource_id             = aws_api_gateway_resource.query.id
  http_method             = aws_api_gateway_method.query_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.bedrock_agent_proxy.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bedrock_agent_proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.knowledge_management_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.knowledge_management_api.id
  description = "Production deployment of Knowledge Management API"

  depends_on = [
    aws_api_gateway_method.query_options,
    aws_api_gateway_method.query_post,
    aws_api_gateway_integration.query_options,
    aws_api_gateway_integration.query_post
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.knowledge_management_api.id
  stage_name    = "prod"
  description   = "Production stage for Knowledge Management API"

  tags = merge(var.common_tags, {
    Name        = "Production API Stage"
    Component   = "API Layer"
    Description = "Production deployment stage"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.knowledge_management_api.id}/prod"
  retention_in_days = 14

  tags = merge(var.common_tags, {
    Name        = "API Gateway Logs"
    Component   = "Logging"
    Description = "CloudWatch logs for API Gateway"
  })
}

# =============================================================================
# CloudWatch Monitoring and Alarms
# =============================================================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "lambda-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.bedrock_agent_proxy.function_name
  }

  tags = merge(var.common_tags, {
    Name        = "Lambda Error Alarm"
    Component   = "Monitoring"
    Description = "CloudWatch alarm for Lambda errors"
  })
}

# CloudWatch alarm for API Gateway 4XX errors
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  alarm_name          = "api-4xx-errors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = []

  dimensions = {
    ApiName   = aws_api_gateway_rest_api.knowledge_management_api.name
    Stage     = aws_api_gateway_stage.prod.stage_name
  }

  tags = merge(var.common_tags, {
    Name        = "API 4XX Error Alarm"
    Component   = "Monitoring"
    Description = "CloudWatch alarm for API 4XX errors"
  })
}