# Core infrastructure outputs
output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# ECR Repository outputs
output "ecr_repository_url" {
  description = "ECR repository URL for the inference container"
  value       = aws_ecr_repository.inference_repository.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.inference_repository.arn
}

output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.inference_repository.name
}

# S3 Bucket outputs
output "s3_bucket_name" {
  description = "S3 bucket name for model artifacts"
  value       = aws_s3_bucket.model_artifacts.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.model_artifacts.arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.model_artifacts.bucket_domain_name
}

output "model_data_s3_path" {
  description = "S3 path where model artifacts should be uploaded"
  value       = "s3://${aws_s3_bucket.model_artifacts.bucket}/model.tar.gz"
}

# IAM Role outputs
output "sagemaker_execution_role_arn" {
  description = "SageMaker execution role ARN"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_execution_role_name" {
  description = "SageMaker execution role name"
  value       = aws_iam_role.sagemaker_execution_role.name
}

# KMS Key outputs (when encryption is enabled)
output "kms_key_id" {
  description = "KMS key ID for encryption"
  value       = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].key_id : var.kms_key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for encryption"
  value       = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].arn : var.kms_key_id
}

# SageMaker Model outputs
output "sagemaker_model_name" {
  description = "SageMaker model name"
  value       = aws_sagemaker_model.ml_model.name
}

output "sagemaker_model_arn" {
  description = "SageMaker model ARN"
  value       = aws_sagemaker_model.ml_model.arn
}

# SageMaker Endpoint Configuration outputs
output "endpoint_config_name" {
  description = "SageMaker endpoint configuration name"
  value       = aws_sagemaker_endpoint_configuration.ml_endpoint_config.name
}

output "endpoint_config_arn" {
  description = "SageMaker endpoint configuration ARN"
  value       = aws_sagemaker_endpoint_configuration.ml_endpoint_config.arn
}

# SageMaker Endpoint outputs
output "endpoint_name" {
  description = "SageMaker endpoint name"
  value       = aws_sagemaker_endpoint.ml_endpoint.name
}

output "endpoint_arn" {
  description = "SageMaker endpoint ARN"
  value       = aws_sagemaker_endpoint.ml_endpoint.arn
}

output "endpoint_url" {
  description = "SageMaker endpoint URL for inference"
  value       = "https://runtime.sagemaker.${data.aws_region.current.name}.amazonaws.com/endpoints/${aws_sagemaker_endpoint.ml_endpoint.name}/invocations"
}

# Auto-scaling outputs (when enabled)
output "autoscaling_target_resource_id" {
  description = "Auto-scaling target resource ID"
  value       = var.enable_auto_scaling ? aws_appautoscaling_target.sagemaker_target[0].resource_id : null
}

output "autoscaling_policy_name" {
  description = "Auto-scaling policy name"
  value       = var.enable_auto_scaling ? aws_appautoscaling_policy.sagemaker_scaling_policy[0].name : null
}

output "autoscaling_policy_arn" {
  description = "Auto-scaling policy ARN"
  value       = var.enable_auto_scaling ? aws_appautoscaling_policy.sagemaker_scaling_policy[0].arn : null
}

# CloudWatch outputs
output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for SageMaker endpoint"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.sagemaker_endpoint_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.sagemaker_endpoint_logs[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = var.enable_endpoint_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.sagemaker_dashboard[0].dashboard_name}" : null
}

# SNS outputs (when enabled)
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.sagemaker_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "SNS topic name for alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.sagemaker_alerts[0].name : null
}

# CloudWatch Alarm outputs (when monitoring is enabled)
output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs"
  value = var.enable_endpoint_monitoring ? {
    invocation_errors = {
      name = aws_cloudwatch_metric_alarm.endpoint_invocation_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.endpoint_invocation_errors[0].arn
    }
    model_errors = {
      name = aws_cloudwatch_metric_alarm.endpoint_model_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.endpoint_model_errors[0].arn
    }
    high_latency = {
      name = aws_cloudwatch_metric_alarm.endpoint_latency[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.endpoint_latency[0].arn
    }
  } : {}
}

# Docker commands for local development
output "docker_commands" {
  description = "Docker commands for building and pushing the inference container"
  value = {
    login = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.inference_repository.repository_url}"
    build = "docker build -t ${aws_ecr_repository.inference_repository.name} ."
    tag   = "docker tag ${aws_ecr_repository.inference_repository.name}:latest ${aws_ecr_repository.inference_repository.repository_url}:latest"
    push  = "docker push ${aws_ecr_repository.inference_repository.repository_url}:latest"
  }
}

# AWS CLI commands for testing the endpoint
output "test_commands" {
  description = "AWS CLI commands for testing the SageMaker endpoint"
  value = {
    describe_endpoint = "aws sagemaker describe-endpoint --endpoint-name ${aws_sagemaker_endpoint.ml_endpoint.name} --region ${data.aws_region.current.name}"
    invoke_endpoint   = "aws sagemaker-runtime invoke-endpoint --endpoint-name ${aws_sagemaker_endpoint.ml_endpoint.name} --content-type application/json --body '{\"instances\": [[5.1, 3.5, 1.4, 0.2]]}' --region ${data.aws_region.current.name} output.json"
    check_logs       = var.enable_cloudwatch_logs ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.sagemaker_endpoint_logs[0].name} --region ${data.aws_region.current.name}" : "CloudWatch logs not enabled"
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    endpoint_instance_cost = "Approximately $${var.endpoint_instance_type == "ml.t2.medium" ? "35-50" : var.endpoint_instance_type == "ml.c5.large" ? "85-120" : "varies"} per month per instance (${var.endpoint_instance_type})"
    storage_cost          = "S3 storage: ~$0.023 per GB per month"
    data_transfer_cost    = "Data transfer: $0.09 per GB for outbound data"
    cloudwatch_cost       = "CloudWatch logs: ~$0.50 per GB ingested"
    total_estimate        = "Total estimated cost: $40-150+ per month depending on usage and instance type"
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    encryption_at_rest     = var.enable_encryption
    encryption_in_transit  = true
    vpc_isolation         = var.enable_vpc_config
    iam_least_privilege   = true
    cloudwatch_monitoring = var.enable_endpoint_monitoring
    vulnerability_scanning = var.ecr_image_scan_on_push
    data_capture_enabled  = true
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Build and push your inference container to ECR: ${aws_ecr_repository.inference_repository.repository_url}",
    "2. Upload your model artifacts to: s3://${aws_s3_bucket.model_artifacts.bucket}/model.tar.gz",
    "3. Test the endpoint using the AWS CLI commands provided in the test_commands output",
    "4. Set up CloudWatch monitoring and alerting if not already enabled",
    "5. Implement A/B testing by creating additional endpoint configurations",
    "6. Consider implementing data capture and model monitoring for production workloads",
    "7. Review and optimize instance types based on actual performance requirements"
  ]
}