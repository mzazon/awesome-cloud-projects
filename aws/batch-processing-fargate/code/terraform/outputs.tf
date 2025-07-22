# ==============================================================================
# COMPUTE ENVIRONMENT OUTPUTS
# ==============================================================================

output "compute_environment_name" {
  description = "Name of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.fargate.compute_environment_name
}

output "compute_environment_arn" {
  description = "ARN of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.fargate.arn
}

output "compute_environment_status" {
  description = "Status of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.fargate.status
}

# ==============================================================================
# JOB QUEUE OUTPUTS
# ==============================================================================

output "job_queue_name" {
  description = "Name of the AWS Batch job queue"
  value       = aws_batch_job_queue.main.name
}

output "job_queue_arn" {
  description = "ARN of the AWS Batch job queue"
  value       = aws_batch_job_queue.main.arn
}

output "job_queue_state" {
  description = "State of the AWS Batch job queue"
  value       = aws_batch_job_queue.main.state
}

output "job_queue_priority" {
  description = "Priority of the AWS Batch job queue"
  value       = aws_batch_job_queue.main.priority
}

# ==============================================================================
# JOB DEFINITION OUTPUTS
# ==============================================================================

output "job_definition_name" {
  description = "Name of the AWS Batch job definition"
  value       = aws_batch_job_definition.main.name
}

output "job_definition_arn" {
  description = "ARN of the AWS Batch job definition"
  value       = aws_batch_job_definition.main.arn
}

output "job_definition_revision" {
  description = "Revision of the AWS Batch job definition"
  value       = aws_batch_job_definition.main.revision
}

output "custom_job_definition_name" {
  description = "Name of the custom AWS Batch job definition (if ECR repository is created)"
  value       = var.create_ecr_repository ? aws_batch_job_definition.custom_container[0].name : null
}

output "custom_job_definition_arn" {
  description = "ARN of the custom AWS Batch job definition (if ECR repository is created)"
  value       = var.create_ecr_repository ? aws_batch_job_definition.custom_container[0].arn : null
}

# ==============================================================================
# IAM ROLE OUTPUTS
# ==============================================================================

output "batch_execution_role_name" {
  description = "Name of the AWS Batch execution role"
  value       = aws_iam_role.batch_execution_role.name
}

output "batch_execution_role_arn" {
  description = "ARN of the AWS Batch execution role"
  value       = aws_iam_role.batch_execution_role.arn
}

output "batch_service_role_name" {
  description = "Name of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.name
}

output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.arn
}

# ==============================================================================
# ECR REPOSITORY OUTPUTS
# ==============================================================================

output "ecr_repository_url" {
  description = "URL of the ECR repository (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_processing[0].repository_url : null
}

output "ecr_repository_name" {
  description = "Name of the ECR repository (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_processing[0].name : null
}

output "ecr_registry_id" {
  description = "Registry ID of the ECR repository (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_processing[0].registry_id : null
}

# ==============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ==============================================================================

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.batch_jobs.arn
}

output "log_retention_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.batch_jobs.retention_in_days
}

# ==============================================================================
# NETWORKING OUTPUTS
# ==============================================================================

output "vpc_id" {
  description = "VPC ID used for the batch environment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for Fargate tasks"
  value       = local.subnet_ids
}

output "security_group_id" {
  description = "Security group ID for batch tasks (if created)"
  value       = var.create_security_group ? aws_security_group.batch_fargate[0].id : null
}

output "security_group_arn" {
  description = "Security group ARN for batch tasks (if created)"
  value       = var.create_security_group ? aws_security_group.batch_fargate[0].arn : null
}

# ==============================================================================
# CONTAINER CONFIGURATION OUTPUTS
# ==============================================================================

output "container_image_uri" {
  description = "Container image URI used in job definitions"
  value       = local.container_image_uri
}

output "job_vcpu" {
  description = "vCPU allocation for batch jobs"
  value       = var.job_vcpu
}

output "job_memory" {
  description = "Memory allocation for batch jobs (MB)"
  value       = var.job_memory
}

# ==============================================================================
# DEPLOYMENT INFORMATION
# ==============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.name_suffix
}

output "resource_name_prefix" {
  description = "Prefix used for all resource names"
  value       = local.name_prefix
}

# ==============================================================================
# COMMAND EXAMPLES
# ==============================================================================

output "sample_job_submission_command" {
  description = "AWS CLI command to submit a sample job"
  value = "aws batch submit-job --job-name test-job-$(date +%s) --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name}"
}

output "job_monitoring_command" {
  description = "AWS CLI command to monitor job status"
  value = "aws batch describe-jobs --jobs <JOB_ID>"
}

output "log_viewing_command" {
  description = "AWS CLI command to view job logs"
  value = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.batch_jobs.name} --order-by LastEventTime --descending"
}

output "ecr_login_command" {
  description = "AWS CLI command to login to ECR (if repository is created)"
  value = var.create_ecr_repository ? "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_processing[0].repository_url}" : null
}