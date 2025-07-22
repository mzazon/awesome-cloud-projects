output "webhook_api_endpoint" {
  description = "The webhook API endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.webhook_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/webhooks"
}

output "webhook_api_id" {
  description = "The ID of the webhook API Gateway"
  value       = aws_api_gateway_rest_api.webhook_api.id
}

output "webhook_api_name" {
  description = "The name of the webhook API Gateway"
  value       = aws_api_gateway_rest_api.webhook_api.name
}

output "primary_queue_url" {
  description = "The URL of the primary SQS queue"
  value       = aws_sqs_queue.webhook_queue.url
}

output "primary_queue_arn" {
  description = "The ARN of the primary SQS queue"
  value       = aws_sqs_queue.webhook_queue.arn
}

output "primary_queue_name" {
  description = "The name of the primary SQS queue"
  value       = aws_sqs_queue.webhook_queue.name
}

output "dead_letter_queue_url" {
  description = "The URL of the dead letter queue"
  value       = aws_sqs_queue.webhook_dlq.url
}

output "dead_letter_queue_arn" {
  description = "The ARN of the dead letter queue"
  value       = aws_sqs_queue.webhook_dlq.arn
}

output "dead_letter_queue_name" {
  description = "The name of the dead letter queue"
  value       = aws_sqs_queue.webhook_dlq.name
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.webhook_processor.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.webhook_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.webhook_processor.invoke_arn
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.webhook_history.name
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  value       = aws_dynamodb_table.webhook_history.arn
}

output "api_gateway_execution_role_arn" {
  description = "The ARN of the API Gateway execution role"
  value       = aws_iam_role.api_gateway_sqs_role.arn
}

output "lambda_execution_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_dlq_alarm_name" {
  description = "The name of the CloudWatch DLQ alarm (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.dlq_messages_alarm[0].alarm_name : null
}

output "cloudwatch_lambda_errors_alarm_name" {
  description = "The name of the CloudWatch Lambda errors alarm (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors_alarm[0].alarm_name : null
}

output "random_suffix" {
  description = "The random suffix used for resource names"
  value       = local.random_suffix
}

output "resource_names" {
  description = "Map of all resource names created"
  value = {
    webhook_queue_name    = local.webhook_queue_name
    webhook_dlq_name      = local.webhook_dlq_name
    webhook_function_name = local.webhook_function_name
    webhook_api_name      = local.webhook_api_name
    webhook_table_name    = local.webhook_table_name
  }
}

output "test_commands" {
  description = "Commands to test the webhook system"
  value = {
    test_webhook = "curl -X POST ${aws_api_gateway_rest_api.webhook_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/webhooks -H 'Content-Type: application/json' -d '{\"type\": \"test\", \"message\": \"Hello from webhook\"}'"
    check_queue  = "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.webhook_queue.url} --attribute-names ApproximateNumberOfMessages --region ${data.aws_region.current.name}"
    check_table  = "aws dynamodb scan --table-name ${aws_dynamodb_table.webhook_history.name} --limit 5 --region ${data.aws_region.current.name}"
  }
}

output "monitoring_dashboard_url" {
  description = "CloudWatch dashboard URL for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.project_name}-${local.random_suffix}"
}

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    region              = data.aws_region.current.name
    account_id          = data.aws_caller_identity.current.account_id
    environment         = var.environment
    project_name        = var.project_name
    terraform_workspace = terraform.workspace
    deployment_time     = timestamp()
  }
}