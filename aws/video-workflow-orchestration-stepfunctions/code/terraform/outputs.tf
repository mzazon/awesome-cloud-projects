# Output values for video workflow orchestration infrastructure

# ===================================================================
# WORKFLOW COMPONENTS
# ===================================================================

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine for video workflow orchestration"
  value       = aws_sfn_state_machine.video_workflow.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.video_workflow.name
}

output "jobs_table_name" {
  description = "Name of the DynamoDB table for tracking video processing jobs"
  value       = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  description = "ARN of the DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for workflow notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

# ===================================================================
# STORAGE BUCKETS
# ===================================================================

output "source_bucket_name" {
  description = "Name of the S3 bucket for source video files"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for processed video outputs"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the output S3 bucket"
  value       = aws_s3_bucket.output.arn
}

output "archive_bucket_name" {
  description = "Name of the S3 bucket for archived source files"
  value       = aws_s3_bucket.archive.bucket
}

output "archive_bucket_arn" {
  description = "ARN of the archive S3 bucket"
  value       = aws_s3_bucket.archive.arn
}

# ===================================================================
# LAMBDA FUNCTIONS
# ===================================================================

output "metadata_extractor_function_name" {
  description = "Name of the metadata extraction Lambda function"
  value       = aws_lambda_function.metadata_extractor.function_name
}

output "metadata_extractor_function_arn" {
  description = "ARN of the metadata extraction Lambda function"
  value       = aws_lambda_function.metadata_extractor.arn
}

output "quality_control_function_name" {
  description = "Name of the quality control Lambda function"
  value       = aws_lambda_function.quality_control.function_name
}

output "quality_control_function_arn" {
  description = "ARN of the quality control Lambda function"
  value       = aws_lambda_function.quality_control.arn
}

output "publisher_function_name" {
  description = "Name of the publisher Lambda function"
  value       = aws_lambda_function.publisher.function_name
}

output "publisher_function_arn" {
  description = "ARN of the publisher Lambda function"
  value       = aws_lambda_function.publisher.arn
}

output "workflow_trigger_function_name" {
  description = "Name of the workflow trigger Lambda function"
  value       = aws_lambda_function.workflow_trigger.function_name
}

output "workflow_trigger_function_arn" {
  description = "ARN of the workflow trigger Lambda function"
  value       = aws_lambda_function.workflow_trigger.arn
}

# ===================================================================
# IAM ROLES
# ===================================================================

output "mediaconvert_role_arn" {
  description = "ARN of the MediaConvert service role"
  value       = aws_iam_role.mediaconvert.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions.arn
}

# ===================================================================
# API GATEWAY (CONDITIONAL)
# ===================================================================

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint for triggering workflows (if enabled)"
  value       = var.enable_api_gateway ? "https://${aws_apigatewayv2_api.workflow[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod" : null
}

output "api_gateway_id" {
  description = "ID of the API Gateway (if enabled)"
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.workflow[0].id : null
}

output "workflow_trigger_endpoint" {
  description = "Complete API endpoint for triggering video workflows (if enabled)"
  value       = var.enable_api_gateway ? "https://${aws_apigatewayv2_api.workflow[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/start-workflow" : null
}

# ===================================================================
# MONITORING
# ===================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.video_workflow[0].dashboard_name}" : null
}

output "step_functions_logs_group" {
  description = "CloudWatch Log Group for Step Functions execution logs"
  value       = aws_cloudwatch_log_group.step_functions.name
}

# ===================================================================
# CONFIGURATION VALUES
# ===================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

# ===================================================================
# USAGE EXAMPLES
# ===================================================================

output "usage_examples" {
  description = "Examples of how to use the deployed video workflow infrastructure"
  value = {
    upload_video_via_cli = "aws s3 cp your-video.mp4 s3://${aws_s3_bucket.source.bucket}/"
    trigger_via_api = var.enable_api_gateway ? "curl -X POST https://${aws_apigatewayv2_api.workflow[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/start-workflow -H 'Content-Type: application/json' -d '{\"bucket\":\"${aws_s3_bucket.source.bucket}\",\"key\":\"your-video.mp4\"}'" : "API Gateway not enabled"
    monitor_executions = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.video_workflow.arn}"
    check_job_status = "aws dynamodb scan --table-name ${aws_dynamodb_table.jobs.name} --limit 10"
    view_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.step_functions.name}"
  }
}

# ===================================================================
# COST INFORMATION
# ===================================================================

output "cost_considerations" {
  description = "Important cost considerations for the video workflow infrastructure"
  value = {
    step_functions_pricing = "Express Workflows charge per state transition and execution duration"
    mediaconvert_pricing = "Pricing varies by video duration, resolution, and output formats"
    s3_storage_costs = "Monitor storage costs across source, output, and archive buckets"
    lambda_costs = "Pay per invocation and execution time for workflow Lambda functions"
    data_transfer = "Consider data transfer costs between services and regions"
    monitoring_note = var.enable_cost_alerts ? "Cost alerts enabled with threshold of $${var.monthly_cost_threshold}" : "Cost alerts disabled - consider enabling for production"
  }
}

# ===================================================================
# NEXT STEPS
# ===================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    test_workflow = "Upload a test video file to ${aws_s3_bucket.source.bucket} to verify the workflow"
    subscribe_notifications = var.notification_email != "" ? "Check your email (${var.notification_email}) to confirm SNS subscription" : "Configure notification_email variable and redeploy to receive alerts"
    monitor_dashboard = var.enable_cloudwatch_dashboard ? "View the CloudWatch dashboard to monitor workflow performance" : "Enable CloudWatch dashboard for monitoring"
    customize_settings = "Review and adjust variables in terraform.tfvars for your specific requirements"
    production_checklist = "For production use: enable cost alerts, configure proper backup retention, and implement security scanning"
  }
}