# ======================================================================
# AWS Batch Processing Workloads - Terraform Outputs
# 
# This file defines all output values that will be displayed after
# Terraform deployment completes. Outputs are organized by functional
# area and include both resource identifiers and helpful commands.
# ======================================================================

# ======================================================================
# COMPUTE ENVIRONMENT OUTPUTS
# ======================================================================

output "compute_environment_name" {
  description = "Name of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.main.compute_environment_name
}

output "compute_environment_arn" {
  description = "ARN of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.main.arn
}

output "compute_environment_status" {
  description = "Status of the AWS Batch compute environment"
  value       = aws_batch_compute_environment.main.status
}

output "compute_environment_type" {
  description = "Type of the AWS Batch compute environment"
  value       = var.compute_environment_type
}

output "compute_environment_ecs_cluster_arn" {
  description = "ARN of the underlying ECS cluster for the compute environment"
  value       = aws_batch_compute_environment.main.ecs_cluster_arn
}

# ======================================================================
# JOB QUEUE OUTPUTS
# ======================================================================

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

# ======================================================================
# JOB DEFINITION OUTPUTS
# ======================================================================

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

output "job_definition_type" {
  description = "Type of the AWS Batch job definition"
  value       = aws_batch_job_definition.main.type
}

# ======================================================================
# ECR REPOSITORY OUTPUTS
# ======================================================================

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_repo[0].repository_url : null
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_repo[0].arn : null
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_repo[0].name : null
}

output "ecr_registry_id" {
  description = "Registry ID where the ECR repository was created"
  value       = var.create_ecr_repository ? aws_ecr_repository.batch_repo[0].registry_id : null
}

# ======================================================================
# IAM ROLE OUTPUTS
# ======================================================================

output "batch_service_role_name" {
  description = "Name of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.name
}

output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.arn
}

output "ecs_instance_role_name" {
  description = "Name of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.name
}

output "ecs_instance_role_arn" {
  description = "ARN of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "ecs_instance_profile_name" {
  description = "Name of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.name
}

output "ecs_instance_profile_arn" {
  description = "ARN of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

# ======================================================================
# SECURITY GROUP OUTPUTS
# ======================================================================

output "security_group_id" {
  description = "ID of the security group for Batch compute environment"
  value       = aws_security_group.batch_compute.id
}

output "security_group_arn" {
  description = "ARN of the security group for Batch compute environment"
  value       = aws_security_group.batch_compute.arn
}

output "security_group_name" {
  description = "Name of the security group for Batch compute environment"
  value       = aws_security_group.batch_compute.name
}

# ======================================================================
# CLOUDWATCH LOGGING OUTPUTS
# ======================================================================

output "log_group_name" {
  description = "Name of the CloudWatch log group for batch jobs"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for batch jobs"
  value       = aws_cloudwatch_log_group.batch_jobs.arn
}

output "log_group_retention_in_days" {
  description = "Retention period in days for the CloudWatch log group"
  value       = aws_cloudwatch_log_group.batch_jobs.retention_in_days
}

# KMS Key outputs (if enabled)
output "kms_key_id" {
  description = "ID of the KMS key used for log encryption"
  value       = var.enable_log_encryption ? aws_kms_key.batch_logs[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for log encryption"
  value       = var.enable_log_encryption ? aws_kms_key.batch_logs[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for log encryption"
  value       = var.enable_log_encryption ? aws_kms_alias.batch_logs[0].name : null
}

# ======================================================================
# MONITORING AND ALERTING OUTPUTS
# ======================================================================

# SNS Topic Outputs (if created)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for batch alerts"
  value       = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? aws_sns_topic.batch_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for batch alerts"
  value       = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? aws_sns_topic.batch_alerts[0].name : null
}

# CloudWatch Alarm Outputs (if created)
output "failed_jobs_alarm_name" {
  description = "Name of the CloudWatch alarm for failed jobs"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.failed_jobs[0].alarm_name : null
}

output "failed_jobs_alarm_arn" {
  description = "ARN of the CloudWatch alarm for failed jobs"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.failed_jobs[0].arn : null
}

output "queue_utilization_alarm_name" {
  description = "Name of the CloudWatch alarm for queue utilization"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.queue_utilization[0].alarm_name : null
}

output "queue_utilization_alarm_arn" {
  description = "ARN of the CloudWatch alarm for queue utilization"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.queue_utilization[0].arn : null
}

output "compute_environment_issues_alarm_name" {
  description = "Name of the CloudWatch alarm for compute environment issues"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.compute_environment_issues[0].alarm_name : null
}

output "compute_environment_issues_alarm_arn" {
  description = "ARN of the CloudWatch alarm for compute environment issues"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.compute_environment_issues[0].arn : null
}

# CloudWatch Dashboard Output (if created)
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.batch_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.batch_dashboard[0].dashboard_name}" : null
}

# ======================================================================
# NETWORK CONFIGURATION OUTPUTS
# ======================================================================

output "vpc_id" {
  description = "ID of the VPC used for the Batch compute environment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for the Batch compute environment"
  value       = local.subnet_ids
}

# ======================================================================
# AWS CLI COMMANDS FOR JOB SUBMISSION
# ======================================================================

output "job_submission_examples" {
  description = "Example AWS CLI commands for submitting jobs"
  value = {
    single_job = "aws batch submit-job --job-name my-job --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name}"
    
    array_job = "aws batch submit-job --job-name my-array-job --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name} --array-properties size=5"
    
    parameterized_job = "aws batch submit-job --job-name my-param-job --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name} --parameters DATA_SIZE=2000,PROCESSING_TIME=120"

    job_with_timeout = "aws batch submit-job --job-name my-timeout-job --job-queue ${aws_batch_job_queue.main.name} --job-definition ${aws_batch_job_definition.main.name} --timeout attemptDurationSeconds=7200"
  }
}

# ======================================================================
# CONTAINER IMAGE BUILD AND PUSH INSTRUCTIONS
# ======================================================================

output "container_build_instructions" {
  description = "Instructions for building and pushing container images to ECR"
  value = var.create_ecr_repository ? {
    login_command = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_repo[0].repository_url}"
    
    build_commands = [
      "# Build your Docker image",
      "docker build -t ${local.ecr_repository_name} .",
      "",
      "# Tag the image for ECR",
      "docker tag ${local.ecr_repository_name}:latest ${aws_ecr_repository.batch_repo[0].repository_url}:latest",
      "",
      "# Push the image to ECR", 
      "docker push ${aws_ecr_repository.batch_repo[0].repository_url}:latest"
    ]
    
    repository_url = aws_ecr_repository.batch_repo[0].repository_url
    
    sample_dockerfile = [
      "FROM python:3.9-slim",
      "",
      "WORKDIR /app",
      "",
      "# Install required packages",
      "RUN pip install numpy pandas boto3",
      "",
      "# Copy processing script",
      "COPY batch_processor.py .",
      "",
      "# Run the batch processing script",
      "CMD [\"python\", \"batch_processor.py\"]"
    ]
  } : {
    note = "ECR repository creation is disabled. Set create_ecr_repository = true to enable container image storage."
  }
}

# ======================================================================
# MONITORING AND DEBUGGING INFORMATION
# ======================================================================

output "monitoring_info" {
  description = "Information for monitoring and debugging batch jobs"
  value = {
    cloudwatch_log_group = aws_cloudwatch_log_group.batch_jobs.name
    
    useful_cli_commands = {
      # Job management commands
      list_jobs              = "aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name}"
      list_running_jobs      = "aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name} --job-status RUNNING"
      list_failed_jobs       = "aws batch list-jobs --job-queue ${aws_batch_job_queue.main.name} --job-status FAILED"
      describe_job           = "aws batch describe-jobs --jobs JOB_ID"
      cancel_job             = "aws batch cancel-job --job-id JOB_ID --reason 'User requested cancellation'"
      
      # Infrastructure monitoring
      describe_compute_env   = "aws batch describe-compute-environments --compute-environments ${aws_batch_compute_environment.main.compute_environment_name}"
      describe_job_queues    = "aws batch describe-job-queues --job-queues ${aws_batch_job_queue.main.name}"
      describe_job_definitions = "aws batch describe-job-definitions --job-definition-name ${aws_batch_job_definition.main.name}"
      
      # Log monitoring
      view_logs              = "aws logs get-log-events --log-group-name ${aws_cloudwatch_log_group.batch_jobs.name} --log-stream-name LOG_STREAM_NAME"
      list_log_streams       = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.batch_jobs.name} --order-by LastEventTime --descending"
      
      # Compute environment scaling
      update_compute_env     = "aws batch update-compute-environment --compute-environment ${aws_batch_compute_environment.main.compute_environment_name} --compute-resources desiredvCpus=NEW_VALUE"
    }
    
    cloudwatch_metrics_namespace = "AWS/Batch"
    
    available_metrics = [
      "SubmittedJobs - Number of jobs submitted to the queue",
      "RunnableJobs - Number of jobs in RUNNABLE state", 
      "RunningJobs - Number of jobs in RUNNING state",
      "CompletedJobs - Number of jobs that completed successfully",
      "FailedJobs - Number of jobs that failed"
    ]

    cloudwatch_console_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();namespace=AWS/Batch"
    
    batch_console_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/batch/v2/home?region=${data.aws_region.current.name}#dashboard"
  }
}

# ======================================================================
# DEPLOYMENT SUMMARY
# ======================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and key information"
  value = {
    # Core Infrastructure
    compute_environment = {
      name = aws_batch_compute_environment.main.compute_environment_name
      type = var.compute_environment_type
      min_vcpus = var.min_vcpus
      max_vcpus = var.max_vcpus
      status = aws_batch_compute_environment.main.status
    }
    
    job_queue = {
      name = aws_batch_job_queue.main.name
      priority = aws_batch_job_queue.main.priority
      state = aws_batch_job_queue.main.state
    }
    
    job_definition = {
      name = aws_batch_job_definition.main.name
      revision = aws_batch_job_definition.main.revision
      container_image = var.container_image
      vcpus = var.job_vcpus
      memory = var.job_memory
    }
    
    # Storage and Logging
    ecr_repository = var.create_ecr_repository ? aws_ecr_repository.batch_repo[0].name : "Not created"
    log_group = aws_cloudwatch_log_group.batch_jobs.name
    log_encryption_enabled = var.enable_log_encryption
    
    # Security
    security_group = aws_security_group.batch_compute.id
    service_role = aws_iam_role.batch_service_role.name
    instance_role = aws_iam_role.ecs_instance_role.name
    
    # Monitoring
    alarms_enabled = var.enable_cloudwatch_alarms
    dashboard_created = var.create_cloudwatch_dashboard
    sns_notifications = var.alarm_email_endpoint != "" ? "Enabled" : "Disabled"
    
    # Network Configuration
    vpc_id = local.vpc_id
    subnet_count = length(local.subnet_ids)
    
    # Deployment Info
    aws_region = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
    environment = var.environment
    project_name = var.project_name
  }
}

# ======================================================================
# COST OPTIMIZATION RECOMMENDATIONS
# ======================================================================

output "cost_optimization_tips" {
  description = "Recommendations for optimizing costs"
  value = [
    "💡 Use Spot instances for fault-tolerant workloads by setting compute_environment_type = 'SPOT'",
    "💡 Set min_vcpus = 0 to scale down to zero when no jobs are running",
    "💡 Use 'optimal' instance types to let AWS choose the most cost-effective instances",
    "💡 Monitor job efficiency and right-size vCPU/memory allocations",
    "💡 Implement job retry logic to handle Spot instance interruptions",
    "💡 Use CloudWatch Logs retention policies to manage log storage costs",
    "💡 Consider using Fargate for smaller, infrequent jobs to avoid EC2 overhead",
    "💡 Set up budget alerts to monitor AWS Batch spending"
  ]
}

# ======================================================================
# SECURITY RECOMMENDATIONS
# ======================================================================

output "security_recommendations" {
  description = "Security best practices and recommendations"
  value = [
    "🔒 Review and restrict IAM permissions following least privilege principle",
    "🔒 Enable VPC Flow Logs for network monitoring and security analysis",
    "🔒 Consider using private subnets with NAT Gateway for compute instances",
    "🔒 Enable GuardDuty for threat detection in your AWS account",
    "🔒 Scan container images for vulnerabilities before deployment",
    "🔒 Use secrets management (AWS Secrets Manager) for sensitive data",
    "🔒 Enable CloudTrail for API logging and compliance",
    "🔒 Implement network segmentation using security groups",
    "🔒 Consider encrypting EBS volumes on compute instances",
    "🔒 Regularly rotate access keys and review IAM policies"
  ]
}

# ======================================================================
# TROUBLESHOOTING GUIDE
# ======================================================================

output "troubleshooting_guide" {
  description = "Common issues and troubleshooting steps"
  value = {
    compute_environment_invalid = [
      "Check service role permissions and policies",
      "Verify subnet configuration and VPC settings", 
      "Ensure instance profile has necessary permissions",
      "Check security group allows outbound traffic"
    ]
    
    jobs_stuck_in_runnable = [
      "Verify compute environment capacity (max_vcpus)",
      "Check if Spot instance requests are being fulfilled",
      "Review instance type availability in selected subnets",
      "Ensure sufficient EC2 service limits"
    ]
    
    container_pull_errors = [
      "Verify ECR repository permissions",
      "Check if image exists and is accessible",
      "Ensure ECS instance role has ECR pull permissions",
      "Verify image URI format and region"
    ]
    
    job_failures = [
      "Check CloudWatch Logs for container error messages",
      "Verify resource requirements (CPU/memory)",
      "Review environment variables and parameters",
      "Check if job timeout is appropriate"
    ]
  }
}