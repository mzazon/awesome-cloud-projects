# General Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "resource_name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

# Networking
output "vpc_id" {
  description = "ID of the VPC used for deployment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for the Batch compute environment"
  value       = local.subnet_ids
}

# S3 Storage
output "s3_bucket_name" {
  description = "Name of the S3 bucket for HPC data storage"
  value       = aws_s3_bucket.hpc_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for HPC data storage"
  value       = aws_s3_bucket.hpc_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.hpc_data.bucket_domain_name
}

# EFS Storage (if enabled)
output "efs_file_system_id" {
  description = "ID of the EFS file system for shared storage"
  value       = var.enable_efs ? aws_efs_file_system.hpc_shared_storage[0].id : null
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system for shared storage"
  value       = var.enable_efs ? aws_efs_file_system.hpc_shared_storage[0].arn : null
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.hpc_shared_storage[0].dns_name : null
}

output "efs_mount_targets" {
  description = "Mount target information for the EFS file system"
  value = var.enable_efs ? {
    for idx, mt in aws_efs_mount_target.hpc_shared_storage_mt : idx => {
      id                = mt.id
      subnet_id         = mt.subnet_id
      ip_address        = mt.ip_address
      dns_name          = mt.dns_name
      security_groups   = mt.security_groups
    }
  } : {}
}

# Security Groups
output "batch_compute_security_group_id" {
  description = "ID of the security group for Batch compute instances"
  value       = aws_security_group.batch_compute_sg.id
}

output "efs_security_group_id" {
  description = "ID of the security group for EFS access"
  value       = var.enable_efs ? aws_security_group.efs_sg[0].id : null
}

# IAM Resources
output "batch_service_role_arn" {
  description = "ARN of the IAM role for AWS Batch service"
  value       = aws_iam_role.batch_service_role.arn
}

output "ecs_instance_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "batch_execution_role_arn" {
  description = "ARN of the IAM role for Batch job execution"
  value       = aws_iam_role.batch_execution_role.arn
}

output "ecs_instance_profile_arn" {
  description = "ARN of the instance profile for EC2 instances"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

# AWS Batch Resources
output "batch_compute_environment_name" {
  description = "Name of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.hpc_spot_compute.compute_environment_name
}

output "batch_compute_environment_arn" {
  description = "ARN of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.hpc_spot_compute.arn
}

output "batch_compute_environment_status" {
  description = "Status of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.hpc_spot_compute.status
}

output "batch_job_queue_name" {
  description = "Name of the AWS Batch job queue"
  value       = aws_batch_job_queue.hpc_job_queue.name
}

output "batch_job_queue_arn" {
  description = "ARN of the AWS Batch job queue"
  value       = aws_batch_job_queue.hpc_job_queue.arn
}

output "batch_job_definition_name" {
  description = "Name of the AWS Batch job definition"
  value       = aws_batch_job_definition.hpc_simulation.name
}

output "batch_job_definition_arn" {
  description = "ARN of the AWS Batch job definition"
  value       = aws_batch_job_definition.hpc_simulation.arn
}

output "batch_job_definition_revision" {
  description = "Revision number of the AWS Batch job definition"
  value       = aws_batch_job_definition.hpc_simulation.revision
}

# CloudWatch Resources
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Batch jobs"
  value       = aws_cloudwatch_log_group.batch_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Batch jobs"
  value       = aws_cloudwatch_log_group.batch_logs.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_detailed_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.hpc_dashboard[0].dashboard_name}" : null
}

output "failed_jobs_alarm_name" {
  description = "Name of the CloudWatch alarm for failed jobs"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.failed_jobs_alarm[0].alarm_name : null
}

# KMS (if enabled)
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.hpc_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.hpc_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_alias.hpc_key_alias[0].name : null
}

# Configuration Summary
output "compute_configuration" {
  description = "Summary of compute environment configuration"
  value = {
    allocation_strategy = var.allocation_strategy
    max_vcpus          = var.max_vcpus
    desired_vcpus      = var.desired_vcpus
    instance_types     = var.instance_types
    spot_bid_percentage = var.spot_bid_percentage
  }
}

output "job_configuration" {
  description = "Summary of job configuration"
  value = {
    container_image    = var.container_image
    vcpus             = var.job_vcpus
    memory_mb         = var.job_memory_mb
    timeout_seconds   = var.job_timeout_seconds
    retry_attempts    = var.job_retry_attempts
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    submit_job_command = "aws batch submit-job --job-name my-hpc-job --job-queue ${aws_batch_job_queue.hpc_job_queue.name} --job-definition ${aws_batch_job_definition.hpc_simulation.name}"
    
    list_jobs_command = "aws batch list-jobs --job-queue ${aws_batch_job_queue.hpc_job_queue.name}"
    
    describe_job_command = "aws batch describe-jobs --jobs <JOB_ID>"
    
    upload_data_command = "aws s3 cp <local-file> s3://${aws_s3_bucket.hpc_data.bucket}/"
    
    download_results_command = "aws s3 cp s3://${aws_s3_bucket.hpc_data.bucket}/<results-file> <local-destination>"
    
    efs_mount_command = var.enable_efs ? "sudo mount -t efs -o tls ${aws_efs_file_system.hpc_shared_storage[0].id}:/ /mnt/efs" : "EFS not enabled"
    
    cloudwatch_logs_command = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.batch_logs.name}"
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    spot_instances_enabled = true
    spot_bid_percentage   = var.spot_bid_percentage
    auto_scaling_enabled  = true
    lifecycle_policies    = var.s3_lifecycle_enabled
    estimated_savings     = "70-90% compared to on-demand instances"
    
    cost_monitoring = {
      cloudwatch_dashboard = var.enable_detailed_monitoring ? aws_cloudwatch_dashboard.hpc_dashboard[0].dashboard_name : "Not enabled"
      cost_allocation_tags = local.common_tags
    }
  }
}