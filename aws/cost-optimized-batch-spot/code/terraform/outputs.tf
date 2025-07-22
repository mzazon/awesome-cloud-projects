# Outputs for Cost-Optimized Batch Processing with AWS Batch and Spot Instances

# =============================================================================
# GENERAL INFORMATION
# =============================================================================

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.arn
}

output "instance_role_arn" {
  description = "ARN of the EC2 instance role"
  value       = aws_iam_role.instance_role.arn
}

output "instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.instance_profile.arn
}

output "job_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.job_execution_role.arn
}

output "spot_fleet_role_arn" {
  description = "ARN of the Spot Fleet role"
  value       = aws_iam_role.spot_fleet_role.arn
}

# =============================================================================
# NETWORKING
# =============================================================================

output "vpc_id" {
  description = "VPC ID used for the batch compute environment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for the batch compute environment"
  value       = local.subnet_ids
}

output "security_group_id" {
  description = "ID of the security group for batch instances"
  value       = aws_security_group.batch_security_group.id
}

output "security_group_arn" {
  description = "ARN of the security group for batch instances"
  value       = aws_security_group.batch_security_group.arn
}

# =============================================================================
# CONTAINER REGISTRY
# =============================================================================

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.batch_repository.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.batch_repository.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.batch_repository.arn
}

# =============================================================================
# AWS BATCH RESOURCES
# =============================================================================

output "compute_environment_name" {
  description = "Name of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.spot_compute_environment.compute_environment_name
}

output "compute_environment_arn" {
  description = "ARN of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.spot_compute_environment.arn
}

output "job_queue_name" {
  description = "Name of the AWS Batch job queue"
  value       = aws_batch_job_queue.job_queue.name
}

output "job_queue_arn" {
  description = "ARN of the AWS Batch job queue"
  value       = aws_batch_job_queue.job_queue.arn
}

output "job_definition_name" {
  description = "Name of the AWS Batch job definition"
  value       = aws_batch_job_definition.job_definition.name
}

output "job_definition_arn" {
  description = "ARN of the AWS Batch job definition"
  value       = aws_batch_job_definition.job_definition.arn
}

output "job_definition_revision" {
  description = "Revision number of the AWS Batch job definition"
  value       = aws_batch_job_definition.job_definition.revision
}

# =============================================================================
# CLOUDWATCH LOGS
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for batch jobs"
  value       = aws_cloudwatch_log_group.batch_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for batch jobs"
  value       = aws_cloudwatch_log_group.batch_logs.arn
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

output "failed_jobs_alarm_name" {
  description = "Name of the CloudWatch alarm for failed jobs"
  value       = aws_cloudwatch_metric_alarm.failed_jobs_alarm.alarm_name
}

output "failed_jobs_alarm_arn" {
  description = "ARN of the CloudWatch alarm for failed jobs"
  value       = aws_cloudwatch_metric_alarm.failed_jobs_alarm.arn
}

output "spot_interruption_alarm_name" {
  description = "Name of the CloudWatch alarm for Spot instance interruptions"
  value       = aws_cloudwatch_metric_alarm.spot_interruption_alarm.alarm_name
}

output "spot_interruption_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Spot instance interruptions"
  value       = aws_cloudwatch_metric_alarm.spot_interruption_alarm.arn
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

output "configuration_summary" {
  description = "Summary of the batch processing configuration"
  value = {
    compute_environment = {
      name                    = aws_batch_compute_environment.spot_compute_environment.compute_environment_name
      instance_types          = var.instance_types
      min_vcpus              = var.min_vcpus
      max_vcpus              = var.max_vcpus
      desired_vcpus          = var.desired_vcpus
      spot_bid_percentage    = var.spot_bid_percentage
      allocation_strategy    = "SPOT_CAPACITY_OPTIMIZED"
    }
    job_queue = {
      name     = aws_batch_job_queue.job_queue.name
      priority = 1
    }
    job_definition = {
      name           = aws_batch_job_definition.job_definition.name
      vcpus          = var.job_vcpus
      memory         = var.job_memory
      retry_attempts = var.retry_attempts
      timeout        = var.job_timeout_seconds
    }
    container_image = {
      repository = aws_ecr_repository.batch_repository.repository_url
      tag        = "latest"
    }
  }
}

# =============================================================================
# COST OPTIMIZATION INFORMATION
# =============================================================================

output "cost_optimization_details" {
  description = "Details about cost optimization features"
  value = {
    spot_instances = {
      enabled             = true
      bid_percentage      = var.spot_bid_percentage
      allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
      expected_savings    = "Up to 90% compared to On-Demand instances"
    }
    auto_scaling = {
      enabled       = true
      min_capacity  = var.min_vcpus
      max_capacity  = var.max_vcpus
      scale_to_zero = var.min_vcpus == 0
    }
    container_optimization = {
      ecr_lifecycle_policy = "Keep last 10 images"
      log_retention_days   = 7
    }
  }
}

# =============================================================================
# DEPLOYMENT INSTRUCTIONS
# =============================================================================

output "deployment_instructions" {
  description = "Instructions for deploying and using the batch processing environment"
  value = {
    ecr_login = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_repository.repository_url}"
    
    build_and_push_image = [
      "docker build -t ${aws_ecr_repository.batch_repository.name} .",
      "docker tag ${aws_ecr_repository.batch_repository.name}:latest ${aws_ecr_repository.batch_repository.repository_url}:latest",
      "docker push ${aws_ecr_repository.batch_repository.repository_url}:latest"
    ]
    
    submit_job = "aws batch submit-job --job-name test-job-$(date +%s) --job-queue ${aws_batch_job_queue.job_queue.name} --job-definition ${aws_batch_job_definition.job_definition.name}"
    
    monitor_jobs = "aws batch list-jobs --job-queue ${aws_batch_job_queue.job_queue.name} --job-status RUNNING"
    
    view_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.batch_logs.name}"
  }
}