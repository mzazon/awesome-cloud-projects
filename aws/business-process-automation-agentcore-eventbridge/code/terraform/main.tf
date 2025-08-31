# Data Sources for Account Information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with consistent prefix and optional suffix
  name_prefix = var.resource_name_suffix != "" ? "${var.project_name}-${var.resource_name_suffix}" : "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "business-process-automation-agentcore-eventbridge"
    },
    var.additional_tags
  )
}

# ============================================================================
# KMS Key for Encryption
# ============================================================================

resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.name_prefix} business automation encryption"
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
        Sid    = "Allow EventBridge service"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}-automation"
  target_key_id = aws_kms_key.main.key_id
}

# ============================================================================
# S3 Bucket for Document Storage
# ============================================================================

resource "aws_s3_bucket" "documents" {
  bucket = "${local.name_prefix}-documents"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-documents"
    Purpose     = "Document storage for business automation"
    DataClass   = "Sensitive"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "documents" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.documents.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  count  = var.enable_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Public Access Block
resource "aws_s3_bucket_public_access_block" "documents" {
  count  = var.enable_bucket_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Intelligent Tiering Configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "documents" {
  count  = var.s3_intelligent_tiering_enabled ? 1 : 0
  bucket = aws_s3_bucket.documents.id
  name   = "EntireBucket"

  filter {
    prefix = ""
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 125
  }
}

# S3 Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.documents.id

  rule {
    id     = "document_lifecycle"
    status = "Enabled"

    # Move objects to Intelligent-Tiering after 0 days (immediate)
    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    # Delete non-current versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Upload action schema to S3
resource "aws_s3_object" "action_schema" {
  bucket = aws_s3_bucket.documents.id
  key    = "schemas/action-schema.json"
  
  content = jsonencode({
    openAPIVersion = "3.0.0"
    info = {
      title       = "Business Process Automation API"
      version     = "1.0.0"
      description = "API for AI agent business process automation"
    }
    paths = {
      "/analyze-document" = {
        post = {
          description = "Analyze business document and trigger appropriate workflows"
          parameters = [
            {
              name        = "document_path"
              in          = "query"
              description = "S3 path to the document"
              required    = true
              schema      = { type = "string" }
            },
            {
              name        = "document_type"
              in          = "query"
              description = "Type of document (invoice, contract, compliance)"
              required    = true
              schema      = { type = "string" }
            }
          ]
          responses = {
            "200" = {
              description = "Document analysis completed"
              content = {
                "application/json" = {
                  schema = {
                    type = "object"
                    properties = {
                      recommendation   = { type = "string" }
                      confidence_score = { type = "number" }
                      extracted_data   = { type = "object" }
                      next_actions     = { type = "array" }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  })

  content_type = "application/json"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-action-schema"
  })
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM Role for Bedrock Agent
resource "aws_iam_role" "bedrock_agent" {
  name = "${local.name_prefix}-bedrock-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bedrock-agent-role"
  })
}

# IAM Policy for Bedrock Agent
resource "aws_iam_role_policy" "bedrock_agent" {
  name = "${local.name_prefix}-bedrock-agent-policy"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:Retrieve"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.agent_action.arn
      }
    ]
  })
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-execution-role"
  })
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Enhanced Lambda policy for EventBridge and S3 access
resource "aws_iam_role_policy" "lambda_enhanced" {
  name = "${local.name_prefix}-lambda-enhanced-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# X-Ray tracing policy (conditional)
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count      = var.enable_x_ray_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# EventBridge Custom Event Bus
# ============================================================================

resource "aws_cloudwatch_event_bus" "main" {
  name         = "${local.name_prefix}-events"
  kms_key_id   = var.event_bus_kms_key_id != null ? var.event_bus_kms_key_id : aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-events"
  })
}

# ============================================================================
# Lambda Functions
# ============================================================================

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "approval",
    "processing", 
    "notification",
    "agent-action"
  ])

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-logs"
  })
}

# Lambda function for approval processing
resource "aws_lambda_function" "approval" {
  filename         = data.archive_file.approval_lambda.output_path
  function_name    = "${local.name_prefix}-approval"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "approval-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.approval_lambda.output_base64sha256

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.main.name
      PROJECT_NAME   = local.name_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-approval"
  })
}

# Lambda function for document processing
resource "aws_lambda_function" "processing" {
  filename         = data.archive_file.processing_lambda.output_path
  function_name    = "${local.name_prefix}-processing"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "processing-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.processing_lambda.output_base64sha256

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.main.name
      PROJECT_NAME   = local.name_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing"
  })
}

# Lambda function for notifications
resource "aws_lambda_function" "notification" {
  filename         = data.archive_file.notification_lambda.output_path
  function_name    = "${local.name_prefix}-notification"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "notification-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.notification_lambda.output_base64sha256

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.main.name
      PROJECT_NAME   = local.name_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notification"
  })
}

# Lambda function for agent actions
resource "aws_lambda_function" "agent_action" {
  filename         = data.archive_file.agent_action_lambda.output_path
  function_name    = "${local.name_prefix}-agent-action"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "agent-action-handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.agent_action_lambda.output_base64sha256

  dynamic "tracing_config" {
    for_each = var.enable_x_ray_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.main.name
      PROJECT_NAME   = local.name_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-action"
  })
}

# Lambda permission for Bedrock Agent to invoke agent action function
resource "aws_lambda_permission" "bedrock_agent_invoke" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_action.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent/*"
}

# ============================================================================
# Lambda Function Source Code Archives
# ============================================================================

# Create approval handler source code
resource "local_file" "approval_handler" {
  filename = "${path.module}/src/approval-handler.py"
  content = <<EOF
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing approval event: {json.dumps(event)}")
    
    # Extract document details from EventBridge event
    detail = event['detail']
    document_name = detail['document_name']
    confidence_score = detail['confidence_score']
    recommendation = detail['recommendation']
    
    # Simulate approval logic based on AI recommendation
    if confidence_score > 0.85 and recommendation == 'APPROVE':
        status = 'AUTO_APPROVED'
        action = 'Document automatically approved'
    else:
        status = 'PENDING_REVIEW'
        action = 'Document requires human review'
    
    # Log the decision
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'status': status,
        'action': action,
        'confidence_score': confidence_score
    }
    
    print(f"Approval result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
}

# Create processing handler source code
resource "local_file" "processing_handler" {
  filename = "${path.module}/src/processing-handler.py"
  content = <<EOF
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing automation event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    document_type = detail['document_type']
    extracted_data = detail.get('extracted_data', {})
    
    # Simulate different processing based on document type
    processing_actions = {
        'invoice': 'Initiated payment processing workflow',
        'contract': 'Routed to legal team for final review',
        'compliance': 'Submitted to regulatory reporting system',
        'default': 'Archived for future reference'
    }
    
    action = processing_actions.get(document_type, processing_actions['default'])
    
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'document_type': document_type,
        'action': action,
        'data_extracted': len(extracted_data) > 0
    }
    
    print(f"Processing result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
}

# Create notification handler source code
resource "local_file" "notification_handler" {
  filename = "${path.module}/src/notification-handler.py"
  content = <<EOF
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing notification event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    alert_type = detail['alert_type']
    message = detail['message']
    
    # Simulate notification routing
    notification_channels = {
        'high_priority': ['email', 'slack', 'sms'],
        'medium_priority': ['email', 'slack'],
        'low_priority': ['email']
    }
    
    channels = notification_channels.get(alert_type, ['email'])
    
    result = {
        'notification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'alert_type': alert_type,
        'message': message,
        'channels': channels,
        'status': 'sent'
    }
    
    print(f"Notification result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
}

# Create agent action handler source code
resource "local_file" "agent_action_handler" {
  filename = "${path.module}/src/agent-action-handler.py"
  content = <<EOF
import json
import boto3
import re
import os
from datetime import datetime

s3_client = boto3.client('s3')
events_client = boto3.client('events')

def lambda_handler(event, context):
    print(f"Agent action request: {json.dumps(event)}")
    
    # Parse agent request
    action_request = event['actionRequest']
    api_path = action_request['apiPath']
    parameters = action_request.get('parameters', [])
    
    # Extract parameters
    document_path = None
    document_type = None
    
    for param in parameters:
        if param['name'] == 'document_path':
            document_path = param['value']
        elif param['name'] == 'document_type':
            document_type = param['value']
    
    if api_path == '/analyze-document':
        result = analyze_document(document_path, document_type)
        
        # Publish event to EventBridge
        publish_event(result)
        
        return {
            'response': {
                'actionResponse': {
                    'responseBody': result
                }
            }
        }
    
    return {
        'response': {
            'actionResponse': {
                'responseBody': {'error': 'Unknown action'}
            }
        }
    }

def analyze_document(document_path, document_type):
    # Simulate document analysis with varied confidence scores
    analysis_results = {
        'invoice': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.92,
            'extracted_data': {
                'amount': 1250.00,
                'vendor': 'TechSupplies Inc',
                'due_date': '2024-01-15'
            },
            'alert_type': 'medium_priority'
        },
        'contract': {
            'recommendation': 'REVIEW',
            'confidence_score': 0.75,
            'extracted_data': {
                'contract_value': 50000.00,
                'term_length': '12 months',
                'party': 'Global Services LLC'
            },
            'alert_type': 'high_priority'
        },
        'compliance': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.88,
            'extracted_data': {
                'regulation': 'SOX',
                'compliance_score': 95,
                'review_date': '2024-01-01'
            },
            'alert_type': 'low_priority'
        }
    }
    
    return analysis_results.get(document_type, {
        'recommendation': 'REVIEW',
        'confidence_score': 0.5,
        'extracted_data': {},
        'alert_type': 'medium_priority'
    })

def publish_event(analysis_result):
    event_detail = {
        'document_name': 'sample-document.pdf',
        'document_type': 'invoice',
        'timestamp': datetime.utcnow().isoformat(),
        **analysis_result
    }
    
    event_bus_name = os.environ.get('EVENT_BUS_NAME')
    
    events_client.put_events(
        Entries=[
            {
                'Source': 'bedrock.agent',
                'DetailType': 'Document Analysis Complete',
                'Detail': json.dumps(event_detail),
                'EventBusName': event_bus_name
            }
        ]
    )
EOF
}

# Create source directory if it doesn't exist
resource "null_resource" "create_src_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/src"
  }
}

# Archive Lambda function source code
data "archive_file" "approval_lambda" {
  type        = "zip"
  source_file = local_file.approval_handler.filename
  output_path = "${path.module}/src/approval-function.zip"
  depends_on  = [local_file.approval_handler, null_resource.create_src_dir]
}

data "archive_file" "processing_lambda" {
  type        = "zip"
  source_file = local_file.processing_handler.filename
  output_path = "${path.module}/src/processing-function.zip"
  depends_on  = [local_file.processing_handler, null_resource.create_src_dir]
}

data "archive_file" "notification_lambda" {
  type        = "zip"
  source_file = local_file.notification_handler.filename
  output_path = "${path.module}/src/notification-function.zip"
  depends_on  = [local_file.notification_handler, null_resource.create_src_dir]
}

data "archive_file" "agent_action_lambda" {
  type        = "zip"
  source_file = local_file.agent_action_handler.filename
  output_path = "${path.module}/src/agent-action-function.zip"
  depends_on  = [local_file.agent_action_handler, null_resource.create_src_dir]
}

# ============================================================================
# EventBridge Rules and Targets
# ============================================================================

# EventBridge rule for high-confidence document approval
resource "aws_cloudwatch_event_rule" "approval" {
  name           = "${local.name_prefix}-approval-rule"
  description    = "Route high-confidence approvals"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["bedrock.agent"]
    detail-type = ["Document Analysis Complete"]
    detail = {
      recommendation   = ["APPROVE"]
      confidence_score = [{ numeric = [">=", 0.8] }]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-approval-rule"
  })
}

# EventBridge target for approval rule
resource "aws_cloudwatch_event_target" "approval" {
  rule           = aws_cloudwatch_event_rule.approval.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "ApprovalLambdaTarget"
  arn            = aws_lambda_function.approval.arn
}

# Lambda permission for EventBridge to invoke approval function
resource "aws_lambda_permission" "approval_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeApproval"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.approval.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.approval.arn
}

# EventBridge rule for document processing
resource "aws_cloudwatch_event_rule" "processing" {
  name           = "${local.name_prefix}-processing-rule"
  description    = "Route documents for automated processing"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["bedrock.agent"]
    detail-type = ["Document Analysis Complete"]
    detail = {
      document_type = ["invoice", "contract", "compliance"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-processing-rule"
  })
}

# EventBridge target for processing rule
resource "aws_cloudwatch_event_target" "processing" {
  rule           = aws_cloudwatch_event_rule.processing.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "ProcessingLambdaTarget"
  arn            = aws_lambda_function.processing.arn
}

# Lambda permission for EventBridge to invoke processing function
resource "aws_lambda_permission" "processing_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeProcessing"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processing.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.processing.arn
}

# EventBridge rule for alerts and notifications
resource "aws_cloudwatch_event_rule" "notification" {
  name           = "${local.name_prefix}-alert-rule"
  description    = "Route alerts and notifications"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["bedrock.agent"]
    detail-type = ["Document Analysis Complete"]
    detail = {
      alert_type = ["high_priority", "compliance_issue", "error"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alert-rule"
  })
}

# EventBridge target for notification rule
resource "aws_cloudwatch_event_target" "notification" {
  rule           = aws_cloudwatch_event_rule.notification.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "NotificationLambdaTarget"
  arn            = aws_lambda_function.notification.arn
}

# Lambda permission for EventBridge to invoke notification function
resource "aws_lambda_permission" "notification_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeNotification"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.notification.arn
}

# ============================================================================
# Bedrock Agent (Note: AWS provider doesn't fully support Bedrock Agents yet)
# ============================================================================

# Note: As of current AWS provider version, Bedrock Agent resources are not fully supported
# The following are placeholders that would be created via CLI or custom resource provider

# Output information needed for manual Bedrock Agent creation via CLI
locals {
  bedrock_agent_cli_commands = {
    create_agent = "aws bedrock-agent create-agent --agent-name ${local.name_prefix}-agent --agent-resource-role-arn ${aws_iam_role.bedrock_agent.arn} --foundation-model ${var.bedrock_model_id} --instruction '${var.agent_instruction}' --description 'AI agent for intelligent business process automation'"
    
    create_action_group = "aws bedrock-agent create-agent-action-group --agent-id $AGENT_ID --agent-version DRAFT --action-group-name DocumentProcessing --action-group-executor lambda-executor=${aws_lambda_function.agent_action.arn} --api-schema s3-location=s3Uri=${aws_s3_object.action_schema.bucket}/${aws_s3_object.action_schema.key} --description 'Action group for business document processing and workflow automation'"
    
    prepare_agent = "aws bedrock-agent prepare-agent --agent-id $AGENT_ID"
    
    create_alias = "aws bedrock-agent create-agent-alias --agent-id $AGENT_ID --agent-alias-name production --description 'Production alias for business automation agent'"
  }
}

# ============================================================================
# CloudWatch Alarms for Monitoring
# ============================================================================

# Lambda function error alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    approval     = aws_lambda_function.approval.function_name
    processing   = aws_lambda_function.processing.function_name
    notification = aws_lambda_function.notification.function_name
    agent-action = aws_lambda_function.agent_action.function_name
  }

  alarm_name          = "${local.name_prefix}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors for ${each.value}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-error-alarm"
  })
}

# EventBridge failed invocations alarm
resource "aws_cloudwatch_metric_alarm" "eventbridge_failures" {
  alarm_name          = "${local.name_prefix}-eventbridge-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors EventBridge failed invocations"
  alarm_actions       = []

  dimensions = {
    EventBusName = aws_cloudwatch_event_bus.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eventbridge-failure-alarm"
  })
}