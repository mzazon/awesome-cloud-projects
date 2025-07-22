# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  random_suffix = random_id.suffix.hex
  
  # Generate bucket names if not provided
  content_bucket_name  = var.content_bucket_name != "" ? var.content_bucket_name : "${var.project_name}-content-${local.random_suffix}"
  approved_bucket_name = var.approved_bucket_name != "" ? var.approved_bucket_name : "${var.project_name}-approved-${local.random_suffix}"
  rejected_bucket_name = var.rejected_bucket_name != "" ? var.rejected_bucket_name : "${var.project_name}-rejected-${local.random_suffix}"
  
  # EventBridge custom bus name
  custom_bus_name = "${var.project_name}-bus"
  
  # SNS topic name
  sns_topic_name = "${var.project_name}-notifications"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# =====================================================
# S3 BUCKETS FOR CONTENT STORAGE
# =====================================================

# S3 bucket for content uploads
resource "aws_s3_bucket" "content_bucket" {
  bucket = local.content_bucket_name
  tags   = local.common_tags
}

# S3 bucket for approved content
resource "aws_s3_bucket" "approved_bucket" {
  bucket = local.approved_bucket_name
  tags   = local.common_tags
}

# S3 bucket for rejected content
resource "aws_s3_bucket" "rejected_bucket" {
  bucket = local.rejected_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "content_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.content_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "approved_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.approved_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "rejected_versioning" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.rejected_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "content_encryption" {
  bucket = aws_s3_bucket.content_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "approved_encryption" {
  bucket = aws_s3_bucket.approved_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rejected_encryption" {
  bucket = aws_s3_bucket.rejected_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "content_lifecycle" {
  count  = var.s3_object_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.content_bucket.id

  rule {
    id     = "content_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_object_expiration_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "approved_lifecycle" {
  count  = var.s3_object_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.approved_bucket.id

  rule {
    id     = "approved_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_object_expiration_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "rejected_lifecycle" {
  count  = var.s3_object_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.rejected_bucket.id

  rule {
    id     = "rejected_expiration"
    status = "Enabled"

    expiration {
      days = var.s3_object_expiration_days
    }
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "content_pab" {
  bucket = aws_s3_bucket.content_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "approved_pab" {
  bucket = aws_s3_bucket.approved_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "rejected_pab" {
  bucket = aws_s3_bucket.rejected_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =====================================================
# SNS TOPIC FOR NOTIFICATIONS
# =====================================================

# SNS topic for content moderation notifications
resource "aws_sns_topic" "moderation_notifications" {
  name = local.sns_topic_name
  tags = local.common_tags
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.moderation_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =====================================================
# EVENTBRIDGE CUSTOM BUS
# =====================================================

# Custom EventBridge bus for content moderation events
resource "aws_cloudwatch_event_bus" "content_moderation_bus" {
  name = local.custom_bus_name
  tags = local.common_tags
}

# =====================================================
# BEDROCK GUARDRAILS
# =====================================================

# Bedrock Guardrail for enhanced content filtering
resource "aws_bedrock_guardrail" "content_moderation_guardrail" {
  count                     = var.enable_guardrails ? 1 : 0
  name                      = "${var.project_name}-guardrail"
  description               = "Guardrail for content moderation to prevent harmful content"
  blocked_input_messaging   = "This content violates our content policy."
  blocked_outputs_messaging = "I cannot provide that type of content."
  
  content_policy_config {
    filters_config {
      input_strength  = var.guardrail_filters.sexual_filter_strength
      output_strength = var.guardrail_filters.sexual_filter_strength
      type            = "SEXUAL"
    }
    
    filters_config {
      input_strength  = var.guardrail_filters.violence_filter_strength
      output_strength = var.guardrail_filters.violence_filter_strength
      type            = "VIOLENCE"
    }
    
    filters_config {
      input_strength  = var.guardrail_filters.hate_filter_strength
      output_strength = var.guardrail_filters.hate_filter_strength
      type            = "HATE"
    }
    
    filters_config {
      input_strength  = var.guardrail_filters.insults_filter_strength
      output_strength = var.guardrail_filters.insults_filter_strength
      type            = "INSULTS"
    }
    
    filters_config {
      input_strength  = var.guardrail_filters.misconduct_filter_strength
      output_strength = var.guardrail_filters.misconduct_filter_strength
      type            = "MISCONDUCT"
    }
  }
  
  topic_policy_config {
    topics_config {
      name       = "IllegalActivities"
      definition = "Content promoting or instructing illegal activities"
      examples   = ["How to make illegal substances", "Tax evasion strategies"]
      type       = "DENY"
    }
  }
  
  sensitive_information_policy_config {
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "EMAIL"
    }
    
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "PHONE"
    }
    
    pii_entities_config {
      action = "BLOCK"
      type   = "CREDIT_DEBIT_CARD_NUMBER"
    }
  }
  
  tags = local.common_tags
}

# =====================================================
# IAM ROLES AND POLICIES
# =====================================================

# IAM role for Lambda functions
resource "aws_iam_role" "content_analysis_lambda_role" {
  name = "${var.project_name}-content-analysis-role"
  
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

# IAM policy for content analysis Lambda
resource "aws_iam_role_policy" "content_analysis_policy" {
  name = "${var.project_name}-content-analysis-policy"
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
        Resource = "arn:aws:bedrock:${local.region}::foundation-model/anthropic.*"
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
        Resource = aws_cloudwatch_event_bus.content_moderation_bus.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:CopyObject"
        ]
        Resource = [
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

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.content_analysis_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# =====================================================
# LAMBDA FUNCTIONS
# =====================================================

# Archive Lambda function code
data "archive_file" "content_analysis_lambda" {
  type        = "zip"
  output_path = "${path.module}/content_analysis_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/content_analysis.py", {
      sns_topic_arn = aws_sns_topic.moderation_notifications.arn
      custom_bus_name = local.custom_bus_name
    })
    filename = "index.py"
  }
}

# Content Analysis Lambda Function
resource "aws_lambda_function" "content_analysis_function" {
  filename         = data.archive_file.content_analysis_lambda.output_path
  function_name    = "${var.project_name}-content-analysis"
  role            = aws_iam_role.content_analysis_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.content_analysis_memory_size
  source_code_hash = data.archive_file.content_analysis_lambda.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.moderation_notifications.arn
      CUSTOM_BUS_NAME   = local.custom_bus_name
      BEDROCK_MODEL_ID  = var.bedrock_model_id
      APPROVED_BUCKET   = aws_s3_bucket.approved_bucket.id
      REJECTED_BUCKET   = aws_s3_bucket.rejected_bucket.id
      GUARDRAIL_ID      = var.enable_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].guardrail_id : ""
    }
  }
  
  tags = local.common_tags
}

# Workflow Lambda functions (approved, rejected, review)
resource "aws_lambda_function" "workflow_functions" {
  for_each = toset(["approved", "rejected", "review"])
  
  filename         = data.archive_file.workflow_lambda[each.key].output_path
  function_name    = "${var.project_name}-${each.key}-handler"
  role            = aws_iam_role.content_analysis_lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = var.workflow_memory_size
  source_code_hash = data.archive_file.workflow_lambda[each.key].output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.moderation_notifications.arn
      APPROVED_BUCKET = aws_s3_bucket.approved_bucket.id
      REJECTED_BUCKET = aws_s3_bucket.rejected_bucket.id
      WORKFLOW_TYPE   = each.key
    }
  }
  
  tags = local.common_tags
}

# Archive workflow Lambda functions
data "archive_file" "workflow_lambda" {
  for_each = toset(["approved", "rejected", "review"])
  
  type        = "zip"
  output_path = "${path.module}/${each.key}_handler_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/workflow_handler.py", {
      workflow_type = each.key
      sns_topic_arn = aws_sns_topic.moderation_notifications.arn
      approved_bucket = aws_s3_bucket.approved_bucket.id
      rejected_bucket = aws_s3_bucket.rejected_bucket.id
    })
    filename = "index.py"
  }
}

# =====================================================
# S3 EVENT NOTIFICATIONS
# =====================================================

# Lambda permission for S3 to invoke content analysis function
resource "aws_lambda_permission" "s3_invoke_content_analysis" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.content_analysis_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.content_bucket.arn
}

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "content_bucket_notification" {
  bucket = aws_s3_bucket.content_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.content_analysis_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.s3_invoke_content_analysis]
}

# =====================================================
# EVENTBRIDGE RULES AND TARGETS
# =====================================================

# EventBridge rules for each decision type
resource "aws_cloudwatch_event_rule" "content_workflow_rules" {
  for_each = toset(["approved", "rejected", "review"])
  
  name           = "${each.key}-content-rule"
  description    = "Route ${each.key} content to appropriate handler"
  event_bus_name = aws_cloudwatch_event_bus.content_moderation_bus.name
  
  event_pattern = jsonencode({
    source       = ["content.moderation"]
    detail-type  = ["Content ${title(each.key)}"]
  })
  
  tags = local.common_tags
}

# EventBridge targets for workflow rules
resource "aws_cloudwatch_event_target" "workflow_targets" {
  for_each = toset(["approved", "rejected", "review"])
  
  rule           = aws_cloudwatch_event_rule.content_workflow_rules[each.key].name
  event_bus_name = aws_cloudwatch_event_bus.content_moderation_bus.name
  target_id      = "WorkflowTarget"
  arn            = aws_lambda_function.workflow_functions[each.key].arn
}

# Lambda permissions for EventBridge to invoke workflow functions
resource "aws_lambda_permission" "eventbridge_invoke_workflow" {
  for_each = toset(["approved", "rejected", "review"])
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.workflow_functions[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.content_workflow_rules[each.key].arn
}

# =====================================================
# CLOUDWATCH LOG GROUPS
# =====================================================

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "content_analysis_logs" {
  name              = "/aws/lambda/${aws_lambda_function.content_analysis_function.function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "workflow_logs" {
  for_each = toset(["approved", "rejected", "review"])
  
  name              = "/aws/lambda/${aws_lambda_function.workflow_functions[each.key].function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

# =====================================================
# LAMBDA FUNCTION SOURCE CODE FILES
# =====================================================

# Create Lambda function source files
resource "local_file" "content_analysis_lambda_source" {
  filename = "${path.module}/lambda_functions/content_analysis.py"
  content = <<-EOT
import json
import boto3
import urllib.parse
from datetime import datetime

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Prepare moderation prompt with structured output
        prompt = f"""
        Human: Please analyze the following content for policy violations. 
        Consider harmful content including hate speech, violence, harassment, 
        inappropriate sexual content, misinformation, and spam.
        
        Content to analyze:
        {content[:2000]}
        
        Respond with a JSON object containing:
        - "decision": "approved", "rejected", or "review"
        - "confidence": score from 0.0 to 1.0
        - "reason": brief explanation
        - "categories": array of policy categories if violations found
        
        Assistant: """
        
        # Invoke Bedrock Claude model
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId='${bedrock_model_id}',
            body=body,
            contentType='application/json'
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        
        # Parse AI response and handle potential JSON parsing errors
        try:
            moderation_result = json.loads(response_body['content'][0]['text'])
        except json.JSONDecodeError:
            # Fallback for unparseable responses
            moderation_result = {
                "decision": "review",
                "confidence": 0.5,
                "reason": "Unable to parse AI response",
                "categories": ["parsing_error"]
            }
        
        # Publish event to EventBridge
        event_detail = {
            'bucket': bucket,
            'key': key,
            'decision': moderation_result['decision'],
            'confidence': moderation_result['confidence'],
            'reason': moderation_result['reason'],
            'categories': moderation_result.get('categories', []),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'content.moderation',
                    'DetailType': f"Content {moderation_result['decision'].title()}",
                    'Detail': json.dumps(event_detail),
                    'EventBusName': '${custom_bus_name}'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content analyzed successfully',
                'decision': moderation_result['decision']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOT
}

resource "local_file" "workflow_lambda_source" {
  filename = "${path.module}/lambda_functions/workflow_handler.py"
  content = <<-EOT
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        workflow_type = os.environ['WORKFLOW_TYPE']
        
        # Determine target bucket based on workflow
        target_bucket = {
            'approved': os.environ['APPROVED_BUCKET'],
            'rejected': os.environ['REJECTED_BUCKET'],
            'review': os.environ['REJECTED_BUCKET']  # Review items go to rejected bucket with special prefix
        }[workflow_type]
        
        target_key = f"{workflow_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{source_key}"
        
        # Copy content to appropriate bucket with metadata
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=target_bucket,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={
                'moderation-decision': detail['decision'],
                'moderation-confidence': str(detail['confidence']),
                'moderation-reason': detail['reason'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }
        )
        
        # Send notification with comprehensive details
        message = f"""
Content Moderation Result: {detail['decision'].upper()}

File: {source_key}
Confidence: {detail['confidence']:.2f}
Reason: {detail['reason']}
Categories: {', '.join(detail.get('categories', []))}
Timestamp: {detail['timestamp']}

Target Location: s3://{target_bucket}/{target_key}
        """
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'Content {detail["decision"].title()}: {source_key}',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Content processed for {workflow_type}',
                'target_location': f's3://{target_bucket}/{target_key}'
            })
        }
        
    except Exception as e:
        print(f"Error in {workflow_type} handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOT
}

# Create lambda_functions directory structure
resource "local_file" "lambda_functions_directory" {
  filename = "${path.module}/lambda_functions/.gitkeep"
  content  = ""
}