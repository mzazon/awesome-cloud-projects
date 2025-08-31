# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  resource_suffix = var.resource_prefix != "" ? "${var.resource_prefix}-${random_string.suffix.result}" : random_string.suffix.result
  function_name   = "${var.function_name}-${local.resource_suffix}"
  iam_role_name   = "${var.iam_role_name}-${local.resource_suffix}"
  rule_name       = "${var.eventbridge_rule_name}-${local.resource_suffix}"
  
  # Convert retention rules map to JSON for Lambda environment
  retention_rules_json = jsonencode(var.retention_rules)
}

# IAM trust policy document for Lambda service
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

# IAM policy document for CloudWatch Logs management
data "aws_iam_policy_document" "lambda_logs_policy" {
  # CloudWatch Logs management permissions
  statement {
    effect = "Allow"
    
    actions = [
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy"
    ]
    
    resources = ["*"]
  }
  
  # Lambda function logging permissions
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.function_name}:*"
    ]
  }
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
  description        = "IAM role for log retention management Lambda function"

  tags = {
    Name        = local.iam_role_name
    Function    = "log-retention-management"
    Component   = "iam-role"
  }
}

# Attach custom policy to Lambda execution role
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name   = "LogRetentionPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_logs_policy.json
}

# Lambda function source code
locals {
  lambda_source_code = <<-EOF
import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

# Initialize CloudWatch Logs client
logs_client = boto3.client('logs')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def apply_retention_policy(log_group_name, retention_days):
    """Apply retention policy to a specific log group"""
    try:
        logs_client.put_retention_policy(
            logGroupName=log_group_name,
            retentionInDays=retention_days
        )
        logger.info(f"Applied {retention_days} day retention to {log_group_name}")
        return True
    except ClientError as e:
        logger.error(f"Failed to set retention for {log_group_name}: {e}")
        return False

def get_retention_days(log_group_name):
    """Determine appropriate retention period based on log group name patterns"""
    # Get retention rules from environment variable
    retention_rules_json = os.environ.get('RETENTION_RULES', '{}')
    
    try:
        retention_rules = json.loads(retention_rules_json)
    except json.JSONDecodeError:
        logger.error("Failed to parse retention rules from environment")
        retention_rules = {}
    
    # Check log group name against patterns
    for pattern, days in retention_rules.items():
        if pattern in log_group_name:
            return days
    
    # Default retention for unmatched patterns
    return int(os.environ.get('DEFAULT_RETENTION_DAYS', '30'))

def lambda_handler(event, context):
    """Main Lambda handler for log retention management"""
    try:
        processed_groups = 0
        updated_groups = 0
        errors = []
        
        # Get all log groups (paginated)
        paginator = logs_client.get_paginator('describe_log_groups')
        
        for page in paginator.paginate():
            for log_group in page['logGroups']:
                log_group_name = log_group['logGroupName']
                current_retention = log_group.get('retentionInDays')
                
                # Determine appropriate retention period
                target_retention = get_retention_days(log_group_name)
                
                processed_groups += 1
                
                # Apply retention policy if needed
                if current_retention != target_retention:
                    if apply_retention_policy(log_group_name, target_retention):
                        updated_groups += 1
                    else:
                        errors.append(log_group_name)
                else:
                    logger.info(f"Log group {log_group_name} already has correct retention: {current_retention} days")
        
        # Return summary
        result = {
            'statusCode': 200,
            'message': f'Processed {processed_groups} log groups, updated {updated_groups} retention policies',
            'processedGroups': processed_groups,
            'updatedGroups': updated_groups,
            'errors': errors
        }
        
        logger.info(json.dumps(result))
        return result
        
    except Exception as e:
        logger.error(f"Error in log retention management: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
}

# Create ZIP archive for Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local.lambda_source_code
    filename = "lambda_function.py"
  }
}

# Lambda function for log retention management
resource "aws_lambda_function" "log_retention_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Automated CloudWatch Logs retention management"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DEFAULT_RETENTION_DAYS = var.default_retention_days
      RETENTION_RULES       = local.retention_rules_json
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logs_policy,
    data.archive_file.lambda_zip
  ]

  tags = {
    Name        = local.function_name
    Function    = "log-retention-management"
    Component   = "lambda-function"
  }
}

# CloudWatch Log Group for Lambda function (explicit creation for better control)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
  
  tags = {
    Name        = "/aws/lambda/${local.function_name}"
    Function    = "log-retention-management"
    Component   = "log-group"
  }
}

# EventBridge rule for scheduled execution
resource "aws_cloudwatch_event_rule" "log_retention_schedule" {
  count = var.schedule_enabled ? 1 : 0
  
  name                = local.rule_name
  description         = "Weekly log retention policy management"
  schedule_expression = var.schedule_expression
  state              = "ENABLED"

  tags = {
    Name        = local.rule_name
    Function    = "log-retention-management"
    Component   = "eventbridge-rule"
  }
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.schedule_enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.log_retention_schedule[0].name
  target_id = "LogRetentionLambdaTarget"
  arn       = aws_lambda_function.log_retention_manager.arn
}

# Permission for EventBridge to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.schedule_enabled ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_retention_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_retention_schedule[0].arn
}

# Test log groups (optional, for demonstration purposes)
resource "aws_cloudwatch_log_group" "test_log_groups" {
  for_each = var.create_test_log_groups ? toset(var.test_log_groups) : []
  
  name = "${each.value}-${local.resource_suffix}"
  
  tags = {
    Name        = "${each.value}-${local.resource_suffix}"
    Function    = "log-retention-management"
    Component   = "test-log-group"
    TestGroup   = "true"
  }
  
  # Don't set retention_in_days here - let the Lambda function manage it
  lifecycle {
    ignore_changes = [retention_in_days]
  }
}