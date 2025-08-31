# ============================================================================
# Core Resource Outputs
# ============================================================================

output "project_name" {
  description = "The project name used for resource naming"
  value       = local.name_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# S3 Storage Outputs
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for document storage"
  value       = aws_s3_bucket.documents.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.documents.bucket_domain_name
}

output "action_schema_s3_uri" {
  description = "S3 URI of the uploaded action schema for Bedrock Agent"
  value       = "s3://${aws_s3_object.action_schema.bucket}/${aws_s3_object.action_schema.key}"
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "bedrock_agent_role_arn" {
  description = "ARN of the IAM role for Bedrock Agent"
  value       = aws_iam_role.bedrock_agent.arn
}

output "bedrock_agent_role_name" {
  description = "Name of the IAM role for Bedrock Agent"
  value       = aws_iam_role.bedrock_agent.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution.name
}

# ============================================================================
# EventBridge Outputs
# ============================================================================

output "event_bus_name" {
  description = "Name of the EventBridge custom event bus"
  value       = aws_cloudwatch_event_bus.main.name
}

output "event_bus_arn" {
  description = "ARN of the EventBridge custom event bus"
  value       = aws_cloudwatch_event_bus.main.arn
}

output "eventbridge_rules" {
  description = "EventBridge rule names and ARNs"
  value = {
    approval_rule = {
      name = aws_cloudwatch_event_rule.approval.name
      arn  = aws_cloudwatch_event_rule.approval.arn
    }
    processing_rule = {
      name = aws_cloudwatch_event_rule.processing.name
      arn  = aws_cloudwatch_event_rule.processing.arn
    }
    notification_rule = {
      name = aws_cloudwatch_event_rule.notification.name
      arn  = aws_cloudwatch_event_rule.notification.arn
    }
  }
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_functions" {
  description = "Lambda function names, ARNs, and invoke ARNs"
  value = {
    approval = {
      function_name = aws_lambda_function.approval.function_name
      arn          = aws_lambda_function.approval.arn
      invoke_arn   = aws_lambda_function.approval.invoke_arn
    }
    processing = {
      function_name = aws_lambda_function.processing.function_name
      arn          = aws_lambda_function.processing.arn
      invoke_arn   = aws_lambda_function.processing.invoke_arn
    }
    notification = {
      function_name = aws_lambda_function.notification.function_name
      arn          = aws_lambda_function.notification.arn
      invoke_arn   = aws_lambda_function.notification.invoke_arn
    }
    agent_action = {
      function_name = aws_lambda_function.agent_action.function_name
      arn          = aws_lambda_function.agent_action.arn
      invoke_arn   = aws_lambda_function.agent_action.invoke_arn
    }
  }
}

# ============================================================================
# Security Outputs
# ============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.main.arn
}

output "kms_alias_name" {
  description = "Alias name of the KMS key"
  value       = aws_kms_alias.main.name
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names for Lambda functions"
  value = {
    for name, log_group in aws_cloudwatch_log_group.lambda_logs :
    name => {
      name = log_group.name
      arn  = log_group.arn
    }
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs"
  value = merge(
    {
      for name, alarm in aws_cloudwatch_metric_alarm.lambda_errors :
      "${name}_lambda_errors" => {
        name = alarm.alarm_name
        arn  = alarm.arn
      }
    },
    {
      eventbridge_failures = {
        name = aws_cloudwatch_metric_alarm.eventbridge_failures.alarm_name
        arn  = aws_cloudwatch_metric_alarm.eventbridge_failures.arn
      }
    }
  )
}

# ============================================================================
# Bedrock Agent CLI Commands (Manual Setup Required)
# ============================================================================

output "bedrock_agent_cli_commands" {
  description = "CLI commands to complete Bedrock Agent setup (run these manually)"
  value = local.bedrock_agent_cli_commands
}

output "bedrock_agent_configuration" {
  description = "Configuration details for Bedrock Agent manual setup"
  value = {
    agent_name           = "${local.name_prefix}-agent"
    foundation_model     = var.bedrock_model_id
    agent_role_arn      = aws_iam_role.bedrock_agent.arn
    action_lambda_arn   = aws_lambda_function.agent_action.arn
    action_schema_s3_uri = "s3://${aws_s3_object.action_schema.bucket}/${aws_s3_object.action_schema.key}"
    instruction         = var.agent_instruction
  }
}

# ============================================================================
# Testing and Validation Outputs
# ============================================================================

output "test_document_upload_command" {
  description = "AWS CLI command to upload a test document"
  value = "echo 'INVOICE - TechSupplies Inc - Amount: $1,250.00 - Due: 2024-01-15' > test-invoice.txt && aws s3 cp test-invoice.txt s3://${aws_s3_bucket.documents.id}/incoming/"
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.documents.id}/"
    check_event_bus = "aws events describe-event-bus --name ${aws_cloudwatch_event_bus.main.name}"
    check_lambda_functions = "aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `${local.name_prefix}`)].FunctionName'"
    check_eventbridge_rules = "aws events list-rules --event-bus-name ${aws_cloudwatch_event_bus.main.name}"
  }
}

# ============================================================================
# Configuration Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    s3_bucket_created      = aws_s3_bucket.documents.id
    lambda_functions_count = 4
    eventbridge_rules_count = 3
    kms_encryption_enabled = true
    monitoring_enabled     = true
    
    next_steps = [
      "1. Run the Bedrock Agent CLI commands from 'bedrock_agent_cli_commands' output",
      "2. Upload test documents to S3 bucket using 'test_document_upload_command'",
      "3. Monitor CloudWatch logs for Lambda function execution",
      "4. Validate EventBridge event processing using 'validation_commands'"
    ]
    
    estimated_monthly_cost = "Approximately $10-50/month depending on usage volume and document processing frequency"
    
    cleanup_command = "terraform destroy -auto-approve"
  }
}

# ============================================================================
# Integration Points
# ============================================================================

output "integration_endpoints" {
  description = "Key integration points for external systems"
  value = {
    s3_upload_endpoint = {
      bucket_name = aws_s3_bucket.documents.id
      upload_path = "incoming/"
      description = "Upload business documents here for AI processing"
    }
    
    eventbridge_integration = {
      event_bus_name = aws_cloudwatch_event_bus.main.name
      custom_event_source = "bedrock.agent"
      description = "Subscribe to events for custom business logic integration"
    }
    
    lambda_invoke_endpoints = {
      for name, func in {
        approval     = aws_lambda_function.approval
        processing   = aws_lambda_function.processing
        notification = aws_lambda_function.notification
      } : name => {
        function_arn = func.arn
        invoke_url   = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${func.function_name}"
        description  = "Direct invoke endpoint for ${name} processing"
      }
    }
  }
}