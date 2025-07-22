# Resource identifiers
output "autopilot_job_name" {
  description = "Name of the SageMaker Autopilot job"
  value       = aws_sagemaker_auto_ml_job_v2.autopilot_job.auto_ml_job_name
}

output "autopilot_job_arn" {
  description = "ARN of the SageMaker Autopilot job"
  value       = aws_sagemaker_auto_ml_job_v2.autopilot_job.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data and model artifacts"
  value       = aws_s3_bucket.sagemaker_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data and model artifacts"
  value       = aws_s3_bucket.sagemaker_bucket.arn
}

output "batch_transform_bucket_name" {
  description = "Name of the S3 bucket for batch transform jobs"
  value       = aws_s3_bucket.batch_transform_bucket.id
}

# IAM Role information
output "iam_role_name" {
  description = "Name of the IAM role for SageMaker Autopilot"
  value       = var.iam_role_config.create_role ? aws_iam_role.sagemaker_autopilot_role[0].name : var.iam_role_config.role_name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for SageMaker Autopilot"
  value       = var.iam_role_config.create_role ? aws_iam_role.sagemaker_autopilot_role[0].arn : var.iam_role_config.role_arn
}

# KMS encryption information
output "kms_key_id" {
  description = "ID of the KMS key for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.sagemaker_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.sagemaker_key[0].arn : null
}

# Model deployment information
output "model_name" {
  description = "Name of the SageMaker model (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_model.autopilot_model[0].name : null
}

output "model_arn" {
  description = "ARN of the SageMaker model (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_model.autopilot_model[0].arn : null
}

output "endpoint_config_name" {
  description = "Name of the SageMaker endpoint configuration (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_endpoint_configuration.autopilot_endpoint_config[0].name : null
}

output "endpoint_config_arn" {
  description = "ARN of the SageMaker endpoint configuration (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_endpoint_configuration.autopilot_endpoint_config[0].arn : null
}

output "endpoint_name" {
  description = "Name of the SageMaker endpoint (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_endpoint.autopilot_endpoint[0].name : null
}

output "endpoint_arn" {
  description = "ARN of the SageMaker endpoint (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_sagemaker_endpoint.autopilot_endpoint[0].arn : null
}

# Autopilot job configuration
output "autopilot_job_config" {
  description = "Configuration parameters for the Autopilot job"
  value = {
    max_candidates                     = var.autopilot_job_config.max_candidates
    max_runtime_per_training_job       = var.autopilot_job_config.max_runtime_per_training_job
    max_automl_job_runtime            = var.autopilot_job_config.max_automl_job_runtime
    problem_type                      = var.autopilot_job_config.problem_type
    target_attribute_name             = var.autopilot_job_config.target_attribute_name
    completion_criteria_metric_name   = var.autopilot_job_config.completion_criteria_metric_name
  }
}

# S3 paths for data and artifacts
output "s3_input_path" {
  description = "S3 path for input data"
  value       = "s3://${aws_s3_bucket.sagemaker_bucket.id}/input/"
}

output "s3_output_path" {
  description = "S3 path for output artifacts"
  value       = "s3://${aws_s3_bucket.sagemaker_bucket.id}/output/"
}

output "s3_batch_input_path" {
  description = "S3 path for batch transform input"
  value       = "s3://${aws_s3_bucket.batch_transform_bucket.id}/input/"
}

output "s3_batch_output_path" {
  description = "S3 path for batch transform output"
  value       = "s3://${aws_s3_bucket.batch_transform_bucket.id}/output/"
}

# Sample dataset information
output "sample_dataset_s3_uri" {
  description = "S3 URI of the sample dataset (if created)"
  value       = var.create_sample_dataset ? "s3://${aws_s3_bucket.sagemaker_bucket.id}/input/${var.sample_dataset_config.filename}" : null
}

# CloudWatch log groups
output "training_log_group_name" {
  description = "Name of the CloudWatch log group for training jobs"
  value       = aws_cloudwatch_log_group.sagemaker_log_group.name
}

output "endpoint_log_group_name" {
  description = "Name of the CloudWatch log group for endpoint logs (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_cloudwatch_log_group.sagemaker_endpoint_log_group[0].name : null
}

# Monitoring information
output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for endpoint monitoring (if endpoint deployment is enabled)"
  value       = var.deploy_endpoint ? aws_cloudwatch_metric_alarm.endpoint_invocation_errors[0].alarm_name : null
}

# Commands for CLI interaction
output "cli_commands" {
  description = "Useful CLI commands for interacting with the deployed resources"
  value = {
    check_autopilot_job_status = "aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name ${aws_sagemaker_auto_ml_job_v2.autopilot_job.auto_ml_job_name}"
    list_candidates           = "aws sagemaker list-candidates-for-auto-ml-job --auto-ml-job-name ${aws_sagemaker_auto_ml_job_v2.autopilot_job.auto_ml_job_name}"
    download_artifacts        = "aws s3 sync s3://${aws_s3_bucket.sagemaker_bucket.id}/output/ ./autopilot_artifacts/"
    invoke_endpoint           = var.deploy_endpoint ? "aws sagemaker-runtime invoke-endpoint --endpoint-name ${aws_sagemaker_endpoint.autopilot_endpoint[0].name} --content-type text/csv --body fileb://test_data.csv output.json" : null
  }
}

# Resource costs estimation
output "estimated_hourly_costs" {
  description = "Estimated hourly costs for deployed resources (approximate in USD)"
  value = {
    autopilot_job_note = "Autopilot job costs vary based on data size and training time. Typical range: $5-50 per job"
    endpoint_cost      = var.deploy_endpoint ? "~$0.10-0.50 per hour for ${var.endpoint_config.instance_type}" : "No endpoint deployed"
    s3_storage_cost    = "~$0.023 per GB per month for Standard storage"
    note              = "Costs are approximate and vary by region and usage patterns"
  }
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    autopilot_job_created    = true
    s3_buckets_created      = 2
    iam_role_created        = var.iam_role_config.create_role
    kms_encryption_enabled  = var.enable_kms_encryption
    endpoint_deployed       = var.deploy_endpoint
    sample_dataset_created  = var.create_sample_dataset
    vpc_configured          = var.vpc_config.enable_vpc
    next_steps = [
      "Monitor the Autopilot job status using the AWS Console or CLI",
      "Once complete, review the generated notebooks and model leaderboard",
      "Deploy the best model to an endpoint for real-time inference",
      "Set up batch transform jobs for offline predictions",
      "Configure monitoring and alerting for production workloads"
    ]
  }
}

# Resource tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}