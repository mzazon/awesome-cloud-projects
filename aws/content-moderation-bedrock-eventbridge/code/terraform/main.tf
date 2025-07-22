# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_id.suffix.hex
  
  # S3 bucket names (must be globally unique)
  content_bucket_name  = "${local.name_prefix}-content-${local.random_suffix}"
  approved_bucket_name = "${local.name_prefix}-approved-${local.random_suffix}"
  rejected_bucket_name = "${local.name_prefix}-rejected-${local.random_suffix}"
  
  # EventBridge bus name
  custom_bus_name = "${local.name_prefix}-moderation-bus"
  
  # SNS topic name
  sns_topic_name = "${local.name_prefix}-notifications"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "building-intelligent-content-moderation-amazon-bedrock-eventbridge"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# S3 BUCKETS FOR CONTENT STORAGE
# ============================================================================

# S3 bucket for incoming content uploads
resource "aws_s3_bucket" "content_bucket" {
  bucket = local.content_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.content_bucket_name
    Purpose     = "ContentUpload"
    Description = "Storage for incoming content awaiting moderation"
  })
}

# S3 bucket for approved content
resource "aws_s3_bucket" "approved_bucket" {
  bucket = local.approved_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.approved_bucket_name
    Purpose     = "ApprovedContent"
    Description = "Storage for content approved by moderation system"
  })
}

# S3 bucket for rejected content
resource "aws_s3_bucket" "rejected_bucket" {
  bucket = local.rejected_bucket_name
  
  tags = merge(local.common_tags, {
    Name        = local.rejected_bucket_name
    Purpose     = "RejectedContent"
    Description = "Storage for content rejected or flagged for review"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "content_bucket_versioning" {
  bucket = aws_s3_bucket.content_bucket.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "approved_bucket_versioning" {
  bucket = aws_s3_bucket.approved_bucket.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "rejected_bucket_versioning" {
  bucket = aws_s3_bucket.rejected_bucket.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "content_bucket_encryption" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.content_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "approved_bucket_encryption" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.approved_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rejected_bucket_encryption" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.rejected_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "content_bucket_pab" {
  bucket = aws_s3_bucket.content_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "approved_bucket_pab" {
  bucket = aws_s3_bucket.approved_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "rejected_bucket_pab" {
  bucket = aws_s3_bucket.rejected_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ============================================================================

# SNS topic for moderation notifications
resource "aws_sns_topic" "moderation_notifications" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Purpose     = "ModerationNotifications"
    Description = "SNS topic for content moderation decision notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.moderation_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# EVENTBRIDGE CUSTOM BUS AND RULES
# ============================================================================

# Custom EventBridge bus for content moderation events
resource "aws_cloudwatch_event_bus" "moderation_bus" {
  name = local.custom_bus_name
  
  tags = merge(local.common_tags, {
    Name        = local.custom_bus_name
    Purpose     = "ModerationEvents"
    Description = "Custom event bus for content moderation workflows"
  })
}

# EventBridge rules for routing moderation decisions
resource "aws_cloudwatch_event_rule" "approved_content_rule" {
  name           = "${local.name_prefix}-approved-content-rule"
  description    = "Route approved content events to processing Lambda"
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  
  event_pattern = jsonencode({
    source      = ["content.moderation"]
    detail-type = ["Content Approved"]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-approved-content-rule"
    Purpose     = "ApprovedContentRouting"
    Description = "EventBridge rule for approved content workflow"
  })
}

resource "aws_cloudwatch_event_rule" "rejected_content_rule" {
  name           = "${local.name_prefix}-rejected-content-rule"
  description    = "Route rejected content events to processing Lambda"
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  
  event_pattern = jsonencode({
    source      = ["content.moderation"]
    detail-type = ["Content Rejected"]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-rejected-content-rule"
    Purpose     = "RejectedContentRouting"
    Description = "EventBridge rule for rejected content workflow"
  })
}

resource "aws_cloudwatch_event_rule" "review_content_rule" {
  name           = "${local.name_prefix}-review-content-rule"
  description    = "Route review content events to processing Lambda"
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  
  event_pattern = jsonencode({
    source      = ["content.moderation"]
    detail-type = ["Content Review"]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-review-content-rule"
    Purpose     = "ReviewContentRouting"
    Description = "EventBridge rule for content requiring human review"
  })
}

# ============================================================================
# IAM ROLES AND POLICIES FOR LAMBDA FUNCTIONS
# ============================================================================

# IAM role for content analysis Lambda function
resource "aws_iam_role" "content_analysis_lambda_role" {
  name = "${local.name_prefix}-content-analysis-role"
  
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
    Name        = "${local.name_prefix}-content-analysis-role"
    Purpose     = "LambdaExecution"
    Description = "IAM role for content analysis Lambda function"
  })
}

# IAM policy for content analysis Lambda function
resource "aws_iam_role_policy" "content_analysis_lambda_policy" {
  name = "${local.name_prefix}-content-analysis-policy"
  role = aws_iam_role.content_analysis_lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.content_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.moderation_bus.arn
      }
    ]
  })
}

# Attach basic execution role to content analysis Lambda
resource "aws_iam_role_policy_attachment" "content_analysis_basic_execution" {
  role       = aws_iam_role.content_analysis_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM role for workflow Lambda functions
resource "aws_iam_role" "workflow_lambda_role" {
  name = "${local.name_prefix}-workflow-role"
  
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
    Name        = "${local.name_prefix}-workflow-role"
    Purpose     = "LambdaExecution"
    Description = "IAM role for workflow Lambda functions"
  })
}

# IAM policy for workflow Lambda functions
resource "aws_iam_role_policy" "workflow_lambda_policy" {
  name = "${local.name_prefix}-workflow-policy"
  role = aws_iam_role.workflow_lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:CopyObject"
        ]
        Resource = [
          "${aws_s3_bucket.content_bucket.arn}/*",
          "${aws_s3_bucket.approved_bucket.arn}/*",
          "${aws_s3_bucket.rejected_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.moderation_notifications.arn
      }
    ]
  })
}

# Attach basic execution role to workflow Lambda functions
resource "aws_iam_role_policy_attachment" "workflow_basic_execution" {
  role       = aws_iam_role.workflow_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# LAMBDA FUNCTIONS
# ============================================================================

# Archive for content analysis Lambda function code
data "archive_file" "content_analysis_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/content_analysis_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/content_analysis.py", {
      custom_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
      bedrock_model_id = var.bedrock_model_id
    })
    filename = "index.py"
  }
}

# Content analysis Lambda function
resource "aws_lambda_function" "content_analysis" {
  filename         = data.archive_file.content_analysis_lambda_zip.output_path
  function_name    = "${local.name_prefix}-content-analysis"
  role            = aws_iam_role.content_analysis_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.content_analysis_timeout
  memory_size     = var.content_analysis_memory
  source_code_hash = data.archive_file.content_analysis_lambda_zip.output_base64sha256
  
  environment {
    variables = {
      CUSTOM_BUS_NAME  = aws_cloudwatch_event_bus.moderation_bus.name
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-content-analysis"
    Purpose     = "ContentAnalysis"
    Description = "Lambda function for AI-powered content moderation analysis"
  })
}

# CloudWatch Log Group for content analysis Lambda
resource "aws_cloudwatch_log_group" "content_analysis_logs" {
  name              = "/aws/lambda/${aws_lambda_function.content_analysis.function_name}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-content-analysis-logs"
    Purpose     = "Logging"
    Description = "CloudWatch logs for content analysis Lambda function"
  })
}

# S3 bucket notification to trigger content analysis Lambda
resource "aws_s3_bucket_notification" "content_bucket_notification" {
  bucket = aws_s3_bucket.content_bucket.id
  
  lambda_function {
    lambda_function_arn = aws_lambda_function.content_analysis.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".txt"
  }
  
  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# Permission for S3 to invoke content analysis Lambda
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.content_analysis.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.content_bucket.arn
}

# Workflow Lambda functions for each decision type
locals {
  workflow_functions = {
    approved = {
      target_bucket = aws_s3_bucket.approved_bucket.bucket
      rule_arn     = aws_cloudwatch_event_rule.approved_content_rule.arn
    }
    rejected = {
      target_bucket = aws_s3_bucket.rejected_bucket.bucket
      rule_arn     = aws_cloudwatch_event_rule.rejected_content_rule.arn
    }
    review = {
      target_bucket = aws_s3_bucket.rejected_bucket.bucket
      rule_arn     = aws_cloudwatch_event_rule.review_content_rule.arn
    }
  }
}

# Archive for workflow Lambda functions
data "archive_file" "workflow_lambda_zip" {
  for_each = local.workflow_functions
  
  type        = "zip"
  output_path = "${path.module}/${each.key}_workflow_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/workflow_handler.py", {
      workflow_type     = each.key
      target_bucket     = each.value.target_bucket
      sns_topic_arn     = aws_sns_topic.moderation_notifications.arn
    })
    filename = "index.py"
  }
}

# Workflow Lambda functions
resource "aws_lambda_function" "workflow_handlers" {
  for_each = local.workflow_functions
  
  filename         = data.archive_file.workflow_lambda_zip[each.key].output_path
  function_name    = "${local.name_prefix}-${each.key}-handler"
  role            = aws_iam_role.workflow_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.workflow_timeout
  memory_size     = var.workflow_memory
  source_code_hash = data.archive_file.workflow_lambda_zip[each.key].output_base64sha256
  
  environment {
    variables = {
      WORKFLOW_TYPE   = each.key
      TARGET_BUCKET   = each.value.target_bucket
      SNS_TOPIC_ARN   = aws_sns_topic.moderation_notifications.arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-${each.key}-handler"
    Purpose     = "WorkflowProcessing"
    Description = "Lambda function for ${each.key} content workflow processing"
  })
}

# CloudWatch Log Groups for workflow Lambda functions
resource "aws_cloudwatch_log_group" "workflow_logs" {
  for_each = local.workflow_functions
  
  name              = "/aws/lambda/${aws_lambda_function.workflow_handlers[each.key].function_name}"
  retention_in_days = var.lambda_log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-${each.key}-handler-logs"
    Purpose     = "Logging"
    Description = "CloudWatch logs for ${each.key} workflow Lambda function"
  })
}

# EventBridge targets for workflow Lambda functions
resource "aws_cloudwatch_event_target" "workflow_targets" {
  for_each = local.workflow_functions
  
  rule           = aws_cloudwatch_event_rule.approved_content_rule.name
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  target_id      = "${each.key}-handler-target"
  arn           = aws_lambda_function.workflow_handlers[each.key].arn
  
  depends_on = [
    aws_cloudwatch_event_rule.approved_content_rule,
    aws_cloudwatch_event_rule.rejected_content_rule,
    aws_cloudwatch_event_rule.review_content_rule
  ]
}

# Correct EventBridge targets for each rule
resource "aws_cloudwatch_event_target" "approved_target" {
  rule           = aws_cloudwatch_event_rule.approved_content_rule.name
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  target_id      = "approved-handler-target"
  arn           = aws_lambda_function.workflow_handlers["approved"].arn
}

resource "aws_cloudwatch_event_target" "rejected_target" {
  rule           = aws_cloudwatch_event_rule.rejected_content_rule.name
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  target_id      = "rejected-handler-target"
  arn           = aws_lambda_function.workflow_handlers["rejected"].arn
}

resource "aws_cloudwatch_event_target" "review_target" {
  rule           = aws_cloudwatch_event_rule.review_content_rule.name
  event_bus_name = aws_cloudwatch_event_bus.moderation_bus.name
  target_id      = "review-handler-target"
  arn           = aws_lambda_function.workflow_handlers["review"].arn
}

# Permissions for EventBridge to invoke workflow Lambda functions
resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  for_each = local.workflow_functions
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_handlers[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.rule_arn
}

# ============================================================================
# BEDROCK GUARDRAILS (OPTIONAL)
# ============================================================================

# Bedrock Guardrail for enhanced content filtering
resource "aws_bedrock_guardrail" "content_moderation_guardrail" {
  count = var.enable_bedrock_guardrails ? 1 : 0
  
  name                      = "${local.name_prefix}-guardrail"
  description              = "Guardrail for content moderation to prevent harmful content"
  blocked_input_messaging  = "This content violates our content policy."
  blocked_outputs_messaging = "I cannot provide that type of content."
  
  # Content policy configuration
  content_policy_config {
    dynamic "filters_config" {
      for_each = var.guardrail_content_filters
      
      content {
        type             = filters_config.key
        input_strength   = filters_config.value.input_strength
        output_strength  = filters_config.value.output_strength
      }
    }
  }
  
  # Topic policy configuration for illegal activities
  topic_policy_config {
    topics_config {
      name       = "IllegalActivities"
      definition = "Content promoting or instructing illegal activities"
      examples   = ["How to make illegal substances", "Tax evasion strategies"]
      type       = "DENY"
    }
  }
  
  # Sensitive information policy configuration
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-guardrail"
    Purpose     = "ContentSafety"
    Description = "Bedrock guardrail for enhanced content moderation safety"
  })
}