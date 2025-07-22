# Core resource outputs
output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for WorkSpaces provisioning"
  value       = aws_lambda_function.workspaces_provisioner.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.workspaces_provisioner.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.workspaces_provisioner.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.workspaces_provisioner.version
}

output "lambda_function_last_modified" {
  description = "Last modified timestamp of the Lambda function"
  value       = aws_lambda_function.workspaces_provisioner.last_modified
}

# IAM outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_policy_arn" {
  description = "ARN of the custom Lambda policy"
  value       = aws_iam_policy.lambda_permissions.arn
}

# Secrets Manager outputs
output "ad_credentials_secret_arn" {
  description = "ARN of the Active Directory credentials secret"
  value       = aws_secretsmanager_secret.ad_credentials.arn
  sensitive   = true
}

output "ad_credentials_secret_name" {
  description = "Name of the Active Directory credentials secret"
  value       = aws_secretsmanager_secret.ad_credentials.name
}

# Systems Manager outputs
output "ssm_document_name" {
  description = "Name of the Systems Manager document for development environment setup"
  value       = aws_ssm_document.dev_environment_setup.name
}

output "ssm_document_arn" {
  description = "ARN of the Systems Manager document"
  value       = aws_ssm_document.dev_environment_setup.arn
}

output "ssm_document_version" {
  description = "Version of the Systems Manager document"
  value       = aws_ssm_document.dev_environment_setup.latest_version
}

# EventBridge outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for automation scheduling"
  value       = var.enable_automation_schedule ? aws_cloudwatch_event_rule.workspaces_automation[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = var.enable_automation_schedule ? aws_cloudwatch_event_rule.workspaces_automation[0].arn : null
}

output "automation_schedule" {
  description = "Schedule expression for automation"
  value       = var.automation_schedule
}

# CloudWatch outputs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

# SNS outputs
output "sns_alerts_topic_arn" {
  description = "ARN of the SNS topic for alerts and notifications"
  value       = aws_sns_topic.alerts.arn
}

output "sns_alerts_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

# SQS outputs
output "lambda_dlq_arn" {
  description = "ARN of the Lambda dead letter queue"
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "lambda_dlq_url" {
  description = "URL of the Lambda dead letter queue"
  value       = aws_sqs_queue.lambda_dlq.id
}

# WorkSpaces configuration outputs
output "workspaces_directory_id" {
  description = "Directory ID for WorkSpaces integration"
  value       = var.directory_id
}

output "workspaces_bundle_id" {
  description = "Bundle ID for WorkSpaces provisioning"
  value       = var.workspaces_bundle_id
}

output "target_users" {
  description = "List of target users for WorkSpaces provisioning"
  value       = var.target_users
}

output "workspaces_running_mode" {
  description = "Running mode for provisioned WorkSpaces"
  value       = var.workspaces_running_mode
}

output "auto_stop_timeout_minutes" {
  description = "Auto-stop timeout for WorkSpaces in AUTO_STOP mode"
  value       = var.auto_stop_timeout_minutes
}

# Development configuration outputs
output "development_tools" {
  description = "Development tools to be installed on WorkSpaces"
  value       = var.development_tools
}

output "team_configuration" {
  description = "Team-specific configuration settings"
  value       = var.team_configuration
}

# Security configuration outputs
output "user_volume_encryption_enabled" {
  description = "Whether user volume encryption is enabled"
  value       = var.enable_user_volume_encryption
}

output "root_volume_encryption_enabled" {
  description = "Whether root volume encryption is enabled"
  value       = var.enable_root_volume_encryption
}

# Testing and validation outputs
output "lambda_test_command" {
  description = "AWS CLI command to test the Lambda function"
  value = <<EOT
aws lambda invoke \
  --function-name ${aws_lambda_function.workspaces_provisioner.function_name} \
  --payload '${jsonencode({
    directory_id = var.directory_id
    bundle_id = var.workspaces_bundle_id
    target_users = var.target_users
    secret_name = aws_secretsmanager_secret.ad_credentials.name
    ssm_document = aws_ssm_document.dev_environment_setup.name
    running_mode = var.workspaces_running_mode
    auto_stop_timeout = var.auto_stop_timeout_minutes
    development_tools = var.development_tools
    team_configuration = var.team_configuration
  })}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
EOT
}

output "workspaces_list_command" {
  description = "AWS CLI command to list WorkSpaces in the directory"
  value = "aws workspaces describe-workspaces --directory-id ${var.directory_id}"
}

output "lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --order-by LastEventTime --descending"
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources manually if needed"
  value = {
    terminate_all_workspaces = "aws workspaces describe-workspaces --directory-id ${var.directory_id} --query 'Workspaces[?State==`AVAILABLE`].[WorkspaceId]' --output text | xargs -I {} aws workspaces terminate-workspaces --terminate-workspace-requests WorkspaceId={}"
    delete_secret = "aws secretsmanager delete-secret --secret-id ${aws_secretsmanager_secret.ad_credentials.name} --force-delete-without-recovery"
    delete_lambda = "aws lambda delete-function --function-name ${aws_lambda_function.workspaces_provisioner.function_name}"
  }
}

# Cost estimation
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the solution components"
  value = {
    lambda_function = "~$0.20 per million requests + $0.0000166667 per GB-second (minimal for automation)"
    secrets_manager = "~$0.40 per secret per month + $0.05 per 10,000 API calls"
    workspaces_standard = "~$25 per WorkSpace per month (AUTO_STOP mode) or ~$35 (ALWAYS_ON mode)"
    cloudwatch_logs = "~$0.50 per GB ingested + $0.03 per GB stored"
    eventbridge = "~$1.00 per million events (minimal for scheduled automation)"
    sns = "~$0.50 per million requests + delivery costs"
    systems_manager = "No additional charges for document execution"
  }
}

# Next steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = <<EOT
1. Update the Active Directory credentials in Secrets Manager:
   aws secretsmanager update-secret --secret-id ${aws_secretsmanager_secret.ad_credentials.name} --secret-string '{"username":"your-ad-username","password":"your-ad-password"}'

2. Test the Lambda function with the provided test command:
   ${join(" ", [
     "aws lambda invoke",
     "--function-name ${aws_lambda_function.workspaces_provisioner.function_name}",
     "--payload '{\"directory_id\":\"${var.directory_id}\",\"bundle_id\":\"${var.workspaces_bundle_id}\",\"target_users\":[\"testuser1\"]}}'",
     "--cli-binary-format raw-in-base64-out response.json"
   ])}

3. Subscribe to SNS alerts topic for notifications:
   aws sns subscribe --topic-arn ${aws_sns_topic.alerts.arn} --protocol email --notification-endpoint your-email@example.com

4. Monitor CloudWatch logs for Lambda execution:
   aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow

5. Customize development tools and team configurations as needed in the SSM document.

6. Set up additional IAM policies if your Active Directory requires specific permissions.
EOT
}