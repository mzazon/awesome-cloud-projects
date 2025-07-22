# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  unique_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Owner       = var.owner
    },
    var.additional_tags
  )
}

# ==============================
# KMS Key for Encryption
# ==============================

resource "aws_kms_key" "multi_agent_key" {
  count = var.enable_resource_encryption ? 1 : 0
  
  description             = "KMS key for multi-agent AI workflow encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key-${local.unique_suffix}"
  })
}

resource "aws_kms_alias" "multi_agent_key_alias" {
  count = var.enable_resource_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-multi-agent-${local.unique_suffix}"
  target_key_id = aws_kms_key.multi_agent_key[0].key_id
}

# ==============================
# IAM Roles and Policies
# ==============================

# Trust policy for Bedrock agents
data "aws_iam_policy_document" "bedrock_agent_trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent/*"]
    }
  }
}

# Bedrock agent execution role
resource "aws_iam_role" "bedrock_agent_role" {
  name               = "${local.name_prefix}-bedrock-agent-role-${local.unique_suffix}"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_trust_policy.json
  
  tags = local.common_tags
}

# Policy for Bedrock model invocation
data "aws_iam_policy_document" "bedrock_model_policy" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.claude-*",
      "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.name}::foundation-model/amazon.titan-*"
    ]
  }
}

resource "aws_iam_role_policy" "bedrock_model_policy" {
  name   = "bedrock-model-invocation"
  role   = aws_iam_role.bedrock_agent_role.id
  policy = data.aws_iam_policy_document.bedrock_model_policy.json
}

# Policy for EventBridge and DynamoDB access
data "aws_iam_policy_document" "bedrock_services_policy" {
  statement {
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [aws_cloudwatch_event_bus.multi_agent_bus.arn]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.agent_memory.arn,
      "${aws_dynamodb_table.agent_memory.arn}/index/*"
    ]
  }
  
  # KMS permissions for encrypted resources
  dynamic "statement" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      resources = [aws_kms_key.multi_agent_key[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "bedrock_services_policy" {
  name   = "bedrock-services-access"
  role   = aws_iam_role.bedrock_agent_role.id
  policy = data.aws_iam_policy_document.bedrock_services_policy.json
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.unique_suffix}"
  
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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Enhanced Lambda policy for multi-agent coordination
data "aws_iam_policy_document" "lambda_coordinator_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.agent_memory.arn,
      "${aws_dynamodb_table.agent_memory.arn}/index/*"
    ]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [aws_cloudwatch_event_bus.multi_agent_bus.arn]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "bedrock-agent-runtime:InvokeAgent"
    ]
    resources = [
      aws_bedrockagent_agent.supervisor.agent_arn,
      aws_bedrockagent_agent.finance.agent_arn,
      aws_bedrockagent_agent.support.agent_arn,
      aws_bedrockagent_agent.analytics.agent_arn
    ]
  }
  
  # X-Ray permissions
  dynamic "statement" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      resources = ["*"]
    }
  }
  
  # KMS permissions
  dynamic "statement" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      resources = [aws_kms_key.multi_agent_key[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "lambda_coordinator_policy" {
  name   = "lambda-coordinator-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_coordinator_policy.json
}

# ==============================
# DynamoDB Table for Agent Memory
# ==============================

resource "aws_dynamodb_table" "agent_memory" {
  name           = "${local.name_prefix}-agent-memory-${local.unique_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "SessionId"
  range_key      = "Timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # Conditional capacity settings for provisioned billing
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "SessionId"
    type = "S"
  }
  
  attribute {
    name = "Timestamp"
    type = "N"
  }
  
  attribute {
    name = "AgentId"
    type = "S"
  }
  
  attribute {
    name = "TaskType"
    type = "S"
  }
  
  # Global secondary index for querying by agent
  global_secondary_index {
    name            = "AgentIndex"
    hash_key        = "AgentId"
    range_key       = "Timestamp"
    projection_type = "ALL"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Global secondary index for querying by task type
  global_secondary_index {
    name            = "TaskTypeIndex"
    hash_key        = "TaskType"
    range_key       = "Timestamp"
    projection_type = "ALL"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # TTL for automatic cleanup
  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  dynamic "server_side_encryption" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.multi_agent_key[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-memory-${local.unique_suffix}"
  })
}

# ==============================
# EventBridge Custom Bus and Rules
# ==============================

resource "aws_cloudwatch_event_bus" "multi_agent_bus" {
  name = "${local.name_prefix}-event-bus-${local.unique_suffix}"
  
  # KMS encryption
  dynamic "kms_key_id" {
    for_each = var.enable_eventbridge_encryption && var.enable_resource_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.multi_agent_key[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-event-bus-${local.unique_suffix}"
  })
}

# EventBridge rule for agent task routing
resource "aws_cloudwatch_event_rule" "agent_task_router" {
  name           = "agent-task-router"
  description    = "Routes tasks to specialized agents"
  event_bus_name = aws_cloudwatch_event_bus.multi_agent_bus.name
  
  event_pattern = jsonencode({
    source      = ["multi-agent.system"]
    detail-type = ["Agent Task Request"]
  })
  
  tags = local.common_tags
}

# EventBridge rule for task completion events
resource "aws_cloudwatch_event_rule" "agent_task_completed" {
  name           = "agent-task-completed"
  description    = "Handles agent task completion events"
  event_bus_name = aws_cloudwatch_event_bus.multi_agent_bus.name
  
  event_pattern = jsonencode({
    source      = ["multi-agent.coordinator"]
    detail-type = ["Agent Task Completed", "Agent Task Failed"]
  })
  
  tags = local.common_tags
}

# Dead Letter Queue for failed events
resource "aws_sqs_queue" "event_dlq" {
  name = "${local.name_prefix}-event-dlq-${local.unique_suffix}"
  
  message_retention_seconds = var.event_retention_days * 24 * 60 * 60
  visibility_timeout_seconds = 60
  
  # KMS encryption
  dynamic "kms_master_key_id" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      kms_master_key_id = aws_kms_key.multi_agent_key[0].key_id
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-event-dlq-${local.unique_suffix}"
  })
}

# ==============================
# Lambda Function for Coordination
# ==============================

# Lambda function code
data "archive_file" "coordinator_lambda" {
  type        = "zip"
  output_path = "${path.module}/coordinator-lambda.zip"
  
  source {
    content = templatefile("${path.module}/coordinator_lambda.py.tpl", {
      event_bus_name      = aws_cloudwatch_event_bus.multi_agent_bus.name
      memory_table_name   = aws_dynamodb_table.agent_memory.name
      supervisor_agent_id = aws_bedrockagent_agent.supervisor.agent_id
      finance_agent_id    = aws_bedrockagent_agent.finance.agent_id
      support_agent_id    = aws_bedrockagent_agent.support.agent_id
      analytics_agent_id  = aws_bedrockagent_agent.analytics.agent_id
    })
    filename = "index.py"
  }
}

# Workflow coordinator Lambda function
resource "aws_lambda_function" "workflow_coordinator" {
  filename         = data.archive_file.coordinator_lambda.output_path
  function_name    = "${local.name_prefix}-coordinator-${local.unique_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.coordinator_timeout
  memory_size     = var.coordinator_memory_size
  architectures   = ["x86_64"]
  
  source_code_hash = data.archive_file.coordinator_lambda.output_base64sha256
  
  environment {
    variables = {
      EVENT_BUS_NAME      = aws_cloudwatch_event_bus.multi_agent_bus.name
      MEMORY_TABLE_NAME   = aws_dynamodb_table.agent_memory.name
      SUPERVISOR_AGENT_ID = aws_bedrockagent_agent.supervisor.agent_id
      FINANCE_AGENT_ID    = aws_bedrockagent_agent.finance.agent_id
      SUPPORT_AGENT_ID    = aws_bedrockagent_agent.support.agent_id
      ANALYTICS_AGENT_ID  = aws_bedrockagent_agent.analytics.agent_id
      LOG_LEVEL          = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }
  
  # X-Ray tracing configuration
  dynamic "tracing_config" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }
  
  # KMS encryption
  dynamic "kms_key_arn" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      kms_key_arn = aws_kms_key.multi_agent_key[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-coordinator-${local.unique_suffix}"
  })
  
  depends_on = [
    aws_cloudwatch_log_group.coordinator_logs
  ]
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_coordinator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.agent_task_router.arn
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule           = aws_cloudwatch_event_rule.agent_task_router.name
  event_bus_name = aws_cloudwatch_event_bus.multi_agent_bus.name
  target_id      = "CoordinatorLambdaTarget"
  arn           = aws_lambda_function.workflow_coordinator.arn
  
  # Dead letter queue configuration
  dead_letter_config {
    arn = aws_sqs_queue.event_dlq.arn
  }
  
  # Retry policy
  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 1800
  }
}

# ==============================
# Bedrock Agents
# ==============================

# Supervisor Agent
resource "aws_bedrockagent_agent" "supervisor" {
  agent_name                  = "${var.supervisor_agent_name}-${local.unique_suffix}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  idle_session_ttl_in_seconds = var.agent_session_timeout
  foundation_model            = var.foundation_model
  description                 = "Supervisor agent for multi-agent workflow coordination"
  
  instruction = <<-EOT
    You are a supervisor agent responsible for coordinating complex business tasks across specialized agent teams. 
    
    Your responsibilities include:
    1. Analyzing incoming requests and breaking them into sub-tasks
    2. Routing tasks to appropriate specialist agents: Financial Agent (${aws_bedrockagent_agent.finance.agent_name}) for financial analysis, Support Agent (${aws_bedrockagent_agent.support.agent_name}) for customer service, Analytics Agent (${aws_bedrockagent_agent.analytics.agent_name}) for data analysis
    3. Coordinating parallel work streams and managing dependencies
    4. Synthesizing results from multiple agents into cohesive responses
    5. Ensuring quality control and consistency across agent outputs
    
    Always provide clear task delegation and maintain oversight of the overall workflow progress. 
    Use EventBridge events to coordinate with other agents and maintain context in the shared memory system.
  EOT
  
  tags = merge(local.common_tags, {
    Name = "${var.supervisor_agent_name}-${local.unique_suffix}"
    Role = "supervisor"
  })
}

# Financial Analysis Agent
resource "aws_bedrockagent_agent" "finance" {
  agent_name                  = "${var.finance_agent_name}-${local.unique_suffix}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  idle_session_ttl_in_seconds = var.agent_session_timeout
  foundation_model            = var.foundation_model
  description                 = "Specialized agent for financial analysis and reporting"
  
  instruction = <<-EOT
    You are a financial analysis specialist. Your role is to analyze financial data, create reports, calculate metrics, and provide insights on financial performance. 
    
    Key responsibilities:
    - Analyze financial statements, revenue trends, and profit margins
    - Calculate and interpret financial ratios and KPIs
    - Provide recommendations based on financial analysis
    - Create detailed financial reports and summaries
    - Ensure accuracy and compliance with financial reporting standards
    
    Always provide detailed explanations of your analysis methodology and cite relevant financial principles. 
    Focus on accuracy and present findings in a clear, business-friendly format.
  EOT
  
  tags = merge(local.common_tags, {
    Name = "${var.finance_agent_name}-${local.unique_suffix}"
    Role = "finance"
  })
}

# Customer Support Agent
resource "aws_bedrockagent_agent" "support" {
  agent_name                  = "${var.support_agent_name}-${local.unique_suffix}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  idle_session_ttl_in_seconds = var.agent_session_timeout
  foundation_model            = var.foundation_model
  description                 = "Specialized agent for customer support and service"
  
  instruction = <<-EOT
    You are a customer support specialist. Your role is to help customers resolve issues, answer questions, and provide excellent service experiences.
    
    Key responsibilities:
    - Analyze customer inquiries and support tickets
    - Provide helpful, empathetic responses to customer concerns
    - Escalate complex technical issues when appropriate
    - Follow company policies and best practices
    - Track customer satisfaction and support metrics
    
    Always maintain a helpful, empathetic tone and focus on resolving customer concerns efficiently. 
    Provide clear explanations and actionable solutions whenever possible.
  EOT
  
  tags = merge(local.common_tags, {
    Name = "${var.support_agent_name}-${local.unique_suffix}"
    Role = "support"
  })
}

# Data Analytics Agent
resource "aws_bedrockagent_agent" "analytics" {
  agent_name                  = "${var.analytics_agent_name}-${local.unique_suffix}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent_role.arn
  idle_session_ttl_in_seconds = var.agent_session_timeout
  foundation_model            = var.foundation_model
  description                 = "Specialized agent for data analysis and insights"
  
  instruction = <<-EOT
    You are a data analytics specialist. Your role is to analyze datasets, identify patterns, create visualizations concepts, and provide actionable insights.
    
    Key responsibilities:
    - Analyze datasets and identify trends and patterns
    - Perform statistical analysis and data interpretation
    - Provide business recommendations based on data insights
    - Suggest appropriate visualization approaches for data presentation
    - Validate findings and ensure analytical accuracy
    
    Focus on statistical accuracy, clear data interpretation, and practical business recommendations. 
    Always explain your analytical methodology and validate your findings with appropriate statistical measures.
  EOT
  
  tags = merge(local.common_tags, {
    Name = "${var.analytics_agent_name}-${local.unique_suffix}"
    Role = "analytics"
  })
}

# ==============================
# Agent Aliases for Production Use
# ==============================

# Supervisor agent production alias
resource "aws_bedrockagent_agent_alias" "supervisor_production" {
  agent_alias_name = "production"
  agent_id         = aws_bedrockagent_agent.supervisor.agent_id
  description      = "Production alias for supervisor agent"
  
  tags = local.common_tags
}

# Finance agent production alias
resource "aws_bedrockagent_agent_alias" "finance_production" {
  agent_alias_name = "production"
  agent_id         = aws_bedrockagent_agent.finance.agent_id
  description      = "Production alias for finance agent"
  
  tags = local.common_tags
}

# Support agent production alias
resource "aws_bedrockagent_agent_alias" "support_production" {
  agent_alias_name = "production"
  agent_id         = aws_bedrockagent_agent.support.agent_id
  description      = "Production alias for support agent"
  
  tags = local.common_tags
}

# Analytics agent production alias
resource "aws_bedrockagent_agent_alias" "analytics_production" {
  agent_alias_name = "production"
  agent_id         = aws_bedrockagent_agent.analytics.agent_id
  description      = "Production alias for analytics agent"
  
  tags = local.common_tags
}

# ==============================
# API Gateway for External Access
# ==============================

resource "aws_api_gateway_rest_api" "multi_agent_api" {
  name        = "${local.name_prefix}-api-${local.unique_suffix}"
  description = "API Gateway for multi-agent AI workflow system"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = local.common_tags
}

# API Gateway resource for agent invocation
resource "aws_api_gateway_resource" "agent_resource" {
  rest_api_id = aws_api_gateway_rest_api.multi_agent_api.id
  parent_id   = aws_api_gateway_rest_api.multi_agent_api.root_resource_id
  path_part   = "agents"
}

# API Gateway method
resource "aws_api_gateway_method" "agent_method" {
  rest_api_id   = aws_api_gateway_rest_api.multi_agent_api.id
  resource_id   = aws_api_gateway_resource.agent_resource.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.multi_agent_api.id
  resource_id = aws_api_gateway_resource.agent_resource.id
  http_method = aws_api_gateway_method.agent_method.http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.workflow_coordinator.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "multi_agent_api" {
  rest_api_id = aws_api_gateway_rest_api.multi_agent_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.agent_resource.id,
      aws_api_gateway_method.agent_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [aws_api_gateway_method.agent_method]
}

# API Gateway stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.multi_agent_api.id
  rest_api_id   = aws_api_gateway_rest_api.multi_agent_api.id
  stage_name    = var.environment
  
  # X-Ray tracing
  dynamic "xray_tracing_enabled" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      xray_tracing_enabled = true
    }
  }
  
  tags = local.common_tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_coordinator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.multi_agent_api.execution_arn}/*/*"
}

# ==============================
# CloudWatch Monitoring
# ==============================

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "agent_logs" {
  name              = "/aws/bedrock/agents/multi-agent-${local.unique_suffix}"
  retention_in_days = var.log_retention_days
  
  dynamic "kms_key_id" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.multi_agent_key[0].arn
    }
  }
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "coordinator_logs" {
  name              = "/aws/lambda/${aws_lambda_function.workflow_coordinator.function_name}"
  retention_in_days = var.log_retention_days
  
  dynamic "kms_key_id" {
    for_each = var.enable_resource_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.multi_agent_key[0].arn
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "multi_agent_dashboard" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-dashboard-${local.unique_suffix}"
  
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
            ["AWS/Bedrock", "InvocationCount", "AgentId", aws_bedrockagent_agent.supervisor.agent_id],
            [".", ".", ".", aws_bedrockagent_agent.finance.agent_id],
            [".", ".", ".", aws_bedrockagent_agent.support.agent_id],
            [".", ".", ".", aws_bedrockagent_agent.analytics.agent_id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Agent Invocations"
          period  = 300
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.workflow_coordinator.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Coordinator Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.agent_memory.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ItemCount", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Agent Memory Table Metrics"
          period  = 300
        }
      }
    ]
  })
  
  tags = local.common_tags
}