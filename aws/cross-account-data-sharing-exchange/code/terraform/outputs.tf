# Outputs for AWS Data Exchange cross-account data sharing infrastructure

# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "provider_bucket_name" {
  description = "Name of the S3 bucket used by the data provider"
  value       = aws_s3_bucket.provider.id
}

output "provider_bucket_arn" {
  description = "ARN of the S3 bucket used by the data provider"
  value       = aws_s3_bucket.provider.arn
}

output "subscriber_bucket_name" {
  description = "Name of the S3 bucket used by the data subscriber"
  value       = aws_s3_bucket.subscriber.id
}

output "subscriber_bucket_arn" {
  description = "ARN of the S3 bucket used by the data subscriber"
  value       = aws_s3_bucket.subscriber.arn
}

output "sample_data_s3_keys" {
  description = "List of S3 keys for uploaded sample data files"
  value       = var.sample_data_enabled ? keys(local.sample_data) : []
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "data_exchange_provider_role_arn" {
  description = "ARN of the IAM role for Data Exchange provider operations"
  value       = aws_iam_role.data_exchange_provider.arn
}

output "data_exchange_provider_role_name" {
  description = "Name of the IAM role for Data Exchange provider operations"
  value       = aws_iam_role.data_exchange_provider.name
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
# AWS DATA EXCHANGE OUTPUTS
# ============================================================================

output "dataset_id" {
  description = "ID of the AWS Data Exchange dataset"
  value       = aws_dataexchange_data_set.main.id
}

output "dataset_arn" {
  description = "ARN of the AWS Data Exchange dataset"
  value       = aws_dataexchange_data_set.main.arn
}

output "dataset_name" {
  description = "Name of the AWS Data Exchange dataset"
  value       = aws_dataexchange_data_set.main.name
}

output "revision_id" {
  description = "ID of the initial Data Exchange revision"
  value       = aws_dataexchange_revision.initial.id
}

output "revision_arn" {
  description = "ARN of the initial Data Exchange revision"
  value       = aws_dataexchange_revision.initial.arn
}

# Data grant output (commented out as resource is commented in main.tf)
# output "data_grant_id" {
#   description = "ID of the cross-account data grant"
#   value       = aws_dataexchange_data_grant.cross_account.id
# }

# output "data_grant_arn" {
#   description = "ARN of the cross-account data grant"
#   value       = aws_dataexchange_data_grant.cross_account.arn
# }

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "notification_lambda_arn" {
  description = "ARN of the Data Exchange notification handler Lambda function"
  value       = aws_lambda_function.notification_handler.arn
}

output "notification_lambda_name" {
  description = "Name of the Data Exchange notification handler Lambda function"
  value       = aws_lambda_function.notification_handler.function_name
}

output "auto_update_lambda_arn" {
  description = "ARN of the Data Exchange auto-update Lambda function"
  value       = aws_lambda_function.auto_update.arn
}

output "auto_update_lambda_name" {
  description = "Name of the Data Exchange auto-update Lambda function"
  value       = aws_lambda_function.auto_update.function_name
}

output "lambda_function_arns" {
  description = "Map of all Lambda function ARNs"
  value = {
    notification_handler = aws_lambda_function.notification_handler.arn
    auto_update         = aws_lambda_function.auto_update.arn
  }
}

# ============================================================================
# SNS TOPIC OUTPUTS
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if email provided)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications (if email provided)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].name : null
}

# ============================================================================
# EVENTBRIDGE OUTPUTS
# ============================================================================

output "data_exchange_event_rule_arn" {
  description = "ARN of the EventBridge rule for Data Exchange events"
  value       = aws_cloudwatch_event_rule.data_exchange_events.arn
}

output "scheduled_update_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled updates"
  value       = aws_cloudwatch_event_rule.scheduled_update.arn
}

output "eventbridge_rule_arns" {
  description = "Map of all EventBridge rule ARNs"
  value = {
    data_exchange_events = aws_cloudwatch_event_rule.data_exchange_events.arn
    scheduled_updates   = aws_cloudwatch_event_rule.scheduled_update.arn
  }
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "cloudwatch_log_group_names" {
  description = "Names of all CloudWatch log groups created"
  value = merge(
    {
      notification_lambda = aws_cloudwatch_log_group.notification_lambda.name
      update_lambda      = aws_cloudwatch_log_group.update_lambda.name
    },
    var.enable_monitoring ? {
      data_exchange_operations = aws_cloudwatch_log_group.data_exchange_operations[0].name
    } : {}
  )
}

output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms created"
  value = var.enable_monitoring ? [
    aws_cloudwatch_metric_alarm.failed_data_grants[0].alarm_name
  ] : []
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "subscriber_account_id" {
  description = "AWS account ID of the data subscriber"
  value       = var.subscriber_account_id
}

output "data_grant_expires_at" {
  description = "Expiration date for the data grant"
  value       = var.data_grant_expires_at
}

output "schedule_expression" {
  description = "EventBridge schedule expression for automated updates"
  value       = var.schedule_expression
}

# ============================================================================
# UTILITY OUTPUTS
# ============================================================================

output "subscriber_access_script_path" {
  description = "Path to the generated subscriber access script"
  value       = "${path.module}/generated/subscriber-access-script.sh"
}

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for managing the Data Exchange resources"
  value = {
    list_datasets = "aws dataexchange list-data-sets --origin OWNED"
    get_dataset   = "aws dataexchange get-data-set --data-set-id ${aws_dataexchange_data_set.main.id}"
    list_revisions = "aws dataexchange list-revisions --data-set-id ${aws_dataexchange_data_set.main.id}"
    list_data_grants = "aws dataexchange list-data-grants"
  }
}

output "next_steps" {
  description = "Next steps for using the Data Exchange infrastructure"
  value = [
    "1. Review the created dataset in AWS Data Exchange console",
    "2. Upload additional data files to the provider S3 bucket: ${aws_s3_bucket.provider.id}",
    "3. Create assets and revisions using AWS CLI or console",
    "4. Create data grants for specific subscriber accounts",
    "5. Monitor Lambda functions and EventBridge rules for automation",
    "6. Use the subscriber access script for data consumption",
    "7. Configure SNS topic for email notifications if needed"
  ]
}

# ============================================================================
# TERRAFORM WORKSPACE OUTPUTS
# ============================================================================

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

output "deployment_timestamp" {
  description = "Timestamp when this infrastructure was deployed"
  value       = timestamp()
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}