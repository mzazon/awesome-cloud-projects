# Core infrastructure outputs
output "project_name" {
  description = "Name of the MLOps project"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# S3 outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for MLOps artifacts"
  value       = aws_s3_bucket.mlops_artifacts.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for MLOps artifacts"
  value       = aws_s3_bucket.mlops_artifacts.arn
}

output "training_data_s3_path" {
  description = "S3 path for training data"
  value       = "s3://${aws_s3_bucket.mlops_artifacts.id}/${var.training_data_prefix}/"
}

output "model_artifacts_s3_path" {
  description = "S3 path for model artifacts"
  value       = "s3://${aws_s3_bucket.mlops_artifacts.id}/${var.model_artifacts_prefix}/"
}

# SageMaker outputs
output "sagemaker_model_package_group_name" {
  description = "Name of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.fraud_detection.model_package_group_name
}

output "sagemaker_model_package_group_arn" {
  description = "ARN of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.fraud_detection.arn
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.name
}

# CodePipeline outputs
output "codepipeline_name" {
  description = "Name of the CodePipeline for ML deployment"
  value       = aws_codepipeline.ml_deployment_pipeline.name
}

output "codepipeline_arn" {
  description = "ARN of the CodePipeline for ML deployment"
  value       = aws_codepipeline.ml_deployment_pipeline.arn
}

output "codepipeline_console_url" {
  description = "AWS Console URL for the CodePipeline"
  value       = "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.ml_deployment_pipeline.name}/view?region=${data.aws_region.current.name}"
}

# CodeBuild outputs
output "codebuild_training_project_name" {
  description = "Name of the CodeBuild project for model training"
  value       = aws_codebuild_project.model_training.name
}

output "codebuild_training_project_arn" {
  description = "ARN of the CodeBuild project for model training"
  value       = aws_codebuild_project.model_training.arn
}

output "codebuild_testing_project_name" {
  description = "Name of the CodeBuild project for model testing"
  value       = aws_codebuild_project.model_testing.name
}

output "codebuild_testing_project_arn" {
  description = "ARN of the CodeBuild project for model testing"
  value       = aws_codebuild_project.model_testing.arn
}

# Lambda outputs
output "lambda_deployment_function_name" {
  description = "Name of the Lambda function for model deployment"
  value       = aws_lambda_function.model_deployment.function_name
}

output "lambda_deployment_function_arn" {
  description = "ARN of the Lambda function for model deployment"
  value       = aws_lambda_function.model_deployment.arn
}

# IAM role outputs
output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_service_role.arn
}

output "codepipeline_service_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_service_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# KMS outputs
output "kms_key_id" {
  description = "ID of the KMS key for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.mlops_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.mlops_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_alias.mlops_key_alias[0].name : null
}

# CloudWatch outputs
output "cloudwatch_log_group_training" {
  description = "CloudWatch log group for CodeBuild training project"
  value       = aws_cloudwatch_log_group.codebuild_training_logs.name
}

output "cloudwatch_log_group_testing" {
  description = "CloudWatch log group for CodeBuild testing project"
  value       = aws_cloudwatch_log_group.codebuild_testing_logs.name
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group for Lambda deployment function"
  value       = aws_cloudwatch_log_group.lambda_deployment_logs.name
}

# Notification outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for pipeline notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.pipeline_notifications[0].arn : null
}

# Resource naming outputs
output "name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# CLI commands for common operations
output "start_pipeline_command" {
  description = "AWS CLI command to start the pipeline execution"
  value       = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.ml_deployment_pipeline.name} --region ${data.aws_region.current.name}"
}

output "upload_source_command" {
  description = "AWS CLI command to upload source code and trigger pipeline"
  value       = "aws s3 cp your-source-code.zip s3://${aws_s3_bucket.mlops_artifacts.id}/source/ml-source-code.zip --region ${data.aws_region.current.name}"
}

output "check_pipeline_status_command" {
  description = "AWS CLI command to check pipeline execution status"
  value       = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.ml_deployment_pipeline.name} --region ${data.aws_region.current.name}"
}

output "list_model_packages_command" {
  description = "AWS CLI command to list model packages in the registry"
  value       = "aws sagemaker list-model-packages --model-package-group-name ${var.model_package_group_name} --sort-by CreationTime --sort-order Descending --region ${data.aws_region.current.name}"
}

# URLs for AWS Console access
output "sagemaker_console_url" {
  description = "AWS Console URL for SageMaker Model Registry"
  value       = "https://console.aws.amazon.com/sagemaker/home?region=${data.aws_region.current.name}#/model-packages"
}

output "codebuild_console_url" {
  description = "AWS Console URL for CodeBuild projects"
  value       = "https://console.aws.amazon.com/codesuite/codebuild/projects?region=${data.aws_region.current.name}"
}

output "s3_console_url" {
  description = "AWS Console URL for S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.mlops_artifacts.id}?region=${data.aws_region.current.name}"
}

output "cloudwatch_logs_console_url" {
  description = "AWS Console URL for CloudWatch Logs"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
}

# Configuration validation outputs
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name                    = var.project_name
    environment                     = var.environment
    region                         = data.aws_region.current.name
    encryption_enabled             = var.enable_encryption
    s3_versioning_enabled          = var.enable_s3_versioning
    detailed_monitoring_enabled    = var.enable_detailed_monitoring
    notifications_enabled          = var.notification_email != ""
    sagemaker_training_instance    = var.sagemaker_training_instance_type
    sagemaker_endpoint_instance    = var.sagemaker_endpoint_instance_type
    codebuild_compute_type        = var.codebuild_compute_type
    lambda_runtime                = var.lambda_runtime
  }
}