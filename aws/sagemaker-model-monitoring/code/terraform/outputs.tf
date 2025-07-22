# Core infrastructure outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket used for model monitoring artifacts"
  value       = aws_s3_bucket.model_monitor_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for model monitoring artifacts"
  value       = aws_s3_bucket.model_monitor_bucket.arn
}

# SageMaker outputs
output "sagemaker_model_name" {
  description = "Name of the SageMaker model"
  value       = aws_sagemaker_model.demo_model.name
}

output "sagemaker_model_arn" {
  description = "ARN of the SageMaker model"
  value       = aws_sagemaker_model.demo_model.arn
}

output "sagemaker_endpoint_name" {
  description = "Name of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.demo_endpoint.name
}

output "sagemaker_endpoint_arn" {
  description = "ARN of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.demo_endpoint.arn
}

output "sagemaker_endpoint_config_name" {
  description = "Name of the SageMaker endpoint configuration"
  value       = aws_sagemaker_endpoint_configuration.demo_endpoint_config.name
}

output "sagemaker_endpoint_config_arn" {
  description = "ARN of the SageMaker endpoint configuration"
  value       = aws_sagemaker_endpoint_configuration.demo_endpoint_config.arn
}

# Monitoring schedule outputs
output "data_quality_monitoring_schedule_name" {
  description = "Name of the data quality monitoring schedule"
  value       = aws_sagemaker_monitoring_schedule.data_quality_schedule.monitoring_schedule_name
}

output "data_quality_monitoring_schedule_arn" {
  description = "ARN of the data quality monitoring schedule"
  value       = aws_sagemaker_monitoring_schedule.data_quality_schedule.arn
}

output "model_quality_monitoring_schedule_name" {
  description = "Name of the model quality monitoring schedule (if enabled)"
  value       = var.enable_model_quality_monitoring ? aws_sagemaker_monitoring_schedule.model_quality_schedule[0].monitoring_schedule_name : null
}

output "model_quality_monitoring_schedule_arn" {
  description = "ARN of the model quality monitoring schedule (if enabled)"
  value       = var.enable_model_quality_monitoring ? aws_sagemaker_monitoring_schedule.model_quality_schedule[0].arn : null
}

# Job definition outputs
output "data_quality_job_definition_name" {
  description = "Name of the data quality job definition"
  value       = aws_sagemaker_data_quality_job_definition.data_quality_job_def.name
}

output "data_quality_job_definition_arn" {
  description = "ARN of the data quality job definition"
  value       = aws_sagemaker_data_quality_job_definition.data_quality_job_def.arn
}

output "model_quality_job_definition_name" {
  description = "Name of the model quality job definition (if enabled)"
  value       = var.enable_model_quality_monitoring ? aws_sagemaker_model_quality_job_definition.model_quality_job_def[0].name : null
}

output "model_quality_job_definition_arn" {
  description = "ARN of the model quality job definition (if enabled)"
  value       = var.enable_model_quality_monitoring ? aws_sagemaker_model_quality_job_definition.model_quality_job_def[0].arn : null
}

# Baseline processing job outputs
output "baseline_processing_job_name" {
  description = "Name of the baseline statistics processing job"
  value       = aws_sagemaker_processing_job.baseline_job.processing_job_name
}

output "baseline_processing_job_arn" {
  description = "ARN of the baseline statistics processing job"
  value       = aws_sagemaker_processing_job.baseline_job.arn
}

# IAM role outputs
output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_model_monitor_role.name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_model_monitor_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for alert handling"
  value       = aws_lambda_function.model_monitor_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for alert handling"
  value       = aws_lambda_function.model_monitor_handler.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.model_monitor_handler.invoke_arn
}

# SNS topic outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.model_monitor_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.model_monitor_alerts.arn
}

# CloudWatch alarm outputs
output "constraint_violations_alarm_name" {
  description = "Name of the constraint violations CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.constraint_violations.alarm_name
}

output "constraint_violations_alarm_arn" {
  description = "ARN of the constraint violations CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.constraint_violations.arn
}

output "monitoring_job_failures_alarm_name" {
  description = "Name of the monitoring job failures CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.monitoring_job_failures.alarm_name
}

output "monitoring_job_failures_alarm_arn" {
  description = "ARN of the monitoring job failures CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.monitoring_job_failures.arn
}

# CloudWatch dashboard outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.model_monitor_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.model_monitor_dashboard[0].dashboard_name}" : null
}

# S3 URI outputs for monitoring artifacts
output "baseline_data_s3_uri" {
  description = "S3 URI for baseline data"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/baseline-data/"
}

output "captured_data_s3_uri" {
  description = "S3 URI for captured inference data"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/captured-data/"
}

output "monitoring_results_s3_uri" {
  description = "S3 URI for monitoring results"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/"
}

output "statistics_s3_uri" {
  description = "S3 URI for baseline statistics"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/statistics/"
}

output "constraints_s3_uri" {
  description = "S3 URI for baseline constraints"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/constraints/"
}

output "data_quality_results_s3_uri" {
  description = "S3 URI for data quality monitoring results"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/data-quality/"
}

output "model_quality_results_s3_uri" {
  description = "S3 URI for model quality monitoring results"
  value       = "s3://${aws_s3_bucket.model_monitor_bucket.bucket}/monitoring-results/model-quality/"
}

# Deployment information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "deployment_environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the deployed model monitoring infrastructure"
  value = <<-EOT
    Model Monitoring Infrastructure Deployed Successfully!
    
    Key Resources:
    - SageMaker Endpoint: ${aws_sagemaker_endpoint.demo_endpoint.name}
    - S3 Bucket: ${aws_s3_bucket.model_monitor_bucket.bucket}
    - SNS Topic: ${aws_sns_topic.model_monitor_alerts.name}
    - Lambda Function: ${aws_lambda_function.model_monitor_handler.function_name}
    
    Next Steps:
    1. Send test requests to the endpoint to generate captured data
    2. Wait for the baseline job to complete: ${aws_sagemaker_processing_job.baseline_job.processing_job_name}
    3. Monitor the data quality schedule: ${aws_sagemaker_monitoring_schedule.data_quality_schedule.monitoring_schedule_name}
    4. Check CloudWatch alarms and dashboard for monitoring status
    
    Test Endpoint:
    aws sagemaker-runtime invoke-endpoint \\
        --endpoint-name ${aws_sagemaker_endpoint.demo_endpoint.name} \\
        --content-type application/json \\
        --body '{"instances": [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]}' \\
        response.json
    
    Monitor Results:
    - S3 Bucket: https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.model_monitor_bucket.bucket}
    - SageMaker Console: https://console.aws.amazon.com/sagemaker/
    - CloudWatch Console: https://console.aws.amazon.com/cloudwatch/
  EOT
}

# Email subscription output
output "email_subscription_confirmation" {
  description = "Email subscription status (if email notifications are enabled)"
  value = var.enable_email_notifications && var.notification_email != "" ? "Email subscription created for ${var.notification_email}. Please check your email and confirm the subscription." : "Email notifications are disabled"
}

# Cost estimation outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = <<-EOT
    Estimated Monthly Costs (US East 1, approximate):
    
    SageMaker Endpoint (${var.model_instance_type}):
    - Instance: ~$35-50/month (24/7 running)
    - Data Capture: Minimal storage costs
    
    Monitoring Jobs:
    - Data Quality (hourly): ~$20-40/month
    - Model Quality (daily): ~$5-10/month
    - Baseline Job: One-time ~$1-2
    
    S3 Storage:
    - Monitoring artifacts: ~$1-5/month
    
    Lambda:
    - Alert processing: <$1/month
    
    CloudWatch:
    - Metrics and logs: ~$2-5/month
    - Dashboard: ~$3/month
    
    SNS:
    - Notifications: <$1/month
    
    Total Estimated: $70-120/month
    
    Note: Costs vary by usage patterns and region. 
    Monitor AWS Cost Explorer for actual usage.
  EOT
}