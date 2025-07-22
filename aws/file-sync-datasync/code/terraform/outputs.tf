# -----------------------------------------------------------------------------
# VPC and Network Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC created for DataSync and EFS resources"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_id" {
  description = "ID of the private subnet created for EFS mount targets"
  value       = aws_subnet.private.id
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = aws_subnet.private.cidr_block
}

output "security_group_id" {
  description = "ID of the security group for EFS access"
  value       = aws_security_group.efs.id
}

output "availability_zone" {
  description = "Availability zone used for subnet placement"
  value       = aws_subnet.private.availability_zone
}

# -----------------------------------------------------------------------------
# EFS Outputs
# -----------------------------------------------------------------------------

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_mount_target_id" {
  description = "ID of the EFS mount target"
  value       = aws_efs_mount_target.main.id
}

output "efs_mount_target_dns_name" {
  description = "DNS name of the EFS mount target"
  value       = aws_efs_mount_target.main.dns_name
}

output "efs_mount_target_ip_address" {
  description = "IP address of the EFS mount target"
  value       = aws_efs_mount_target.main.ip_address
}

output "efs_performance_mode" {
  description = "Performance mode of the EFS file system"
  value       = aws_efs_file_system.main.performance_mode
}

output "efs_throughput_mode" {
  description = "Throughput mode of the EFS file system"
  value       = aws_efs_file_system.main.throughput_mode
}

# -----------------------------------------------------------------------------
# S3 Outputs
# -----------------------------------------------------------------------------

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = var.create_source_bucket ? aws_s3_bucket.source[0].id : local.source_bucket_name
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = var.create_source_bucket ? aws_s3_bucket.source[0].arn : "arn:aws:s3:::${local.source_bucket_name}"
}

output "source_bucket_domain_name" {
  description = "Domain name of the source S3 bucket"
  value       = var.create_source_bucket ? aws_s3_bucket.source[0].bucket_domain_name : "${local.source_bucket_name}.s3.amazonaws.com"
}

output "sample_files_created" {
  description = "List of sample files created in the source bucket"
  value       = var.create_source_bucket && var.create_sample_data ? [for file in aws_s3_object.sample_files : file.key] : []
}

# -----------------------------------------------------------------------------
# IAM Outputs
# -----------------------------------------------------------------------------

output "datasync_role_arn" {
  description = "ARN of the IAM role for DataSync"
  value       = aws_iam_role.datasync.arn
}

output "datasync_role_name" {
  description = "Name of the IAM role for DataSync"
  value       = aws_iam_role.datasync.name
}

# -----------------------------------------------------------------------------
# DataSync Outputs
# -----------------------------------------------------------------------------

output "datasync_s3_location_arn" {
  description = "ARN of the DataSync S3 location"
  value       = aws_datasync_location_s3.source.arn
}

output "datasync_efs_location_arn" {
  description = "ARN of the DataSync EFS location"
  value       = aws_datasync_location_efs.target.arn
}

output "datasync_task_arn" {
  description = "ARN of the DataSync task"
  value       = aws_datasync_task.main.arn
}

output "datasync_task_name" {
  description = "Name of the DataSync task"
  value       = aws_datasync_task.main.name
}

# -----------------------------------------------------------------------------
# Monitoring and Logging Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DataSync (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.datasync[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DataSync (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.datasync[0].arn : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for DataSync notifications (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.datasync_notifications[0].arn : null
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for DataSync task failures (if enabled)"
  value       = var.enable_sns_notifications ? aws_cloudwatch_metric_alarm.datasync_task_failure[0].alarm_name : null
}

# -----------------------------------------------------------------------------
# Connection and Usage Information
# -----------------------------------------------------------------------------

output "efs_mount_command" {
  description = "Command to mount the EFS file system from an EC2 instance"
  value = "sudo mount -t efs -o tls ${aws_efs_file_system.main.id}:/ /mnt/efs"
}

output "efs_mount_helper_command" {
  description = "Alternative mount command using EFS mount helper"
  value = "echo '${aws_efs_file_system.main.id}.efs.${data.aws_region.current.name}.amazonaws.com:/ /mnt/efs efs defaults,_netdev' >> /etc/fstab && mount -a"
}

output "datasync_start_task_command" {
  description = "AWS CLI command to start the DataSync task execution"
  value = "aws datasync start-task-execution --task-arn ${aws_datasync_task.main.arn}"
}

# -----------------------------------------------------------------------------
# Resource Summary
# -----------------------------------------------------------------------------

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id                    = aws_vpc.main.id
    efs_file_system_id       = aws_efs_file_system.main.id
    source_bucket_name       = var.create_source_bucket ? aws_s3_bucket.source[0].id : local.source_bucket_name
    datasync_task_arn        = aws_datasync_task.main.arn
    datasync_role_arn        = aws_iam_role.datasync.arn
    cloudwatch_logs_enabled  = var.enable_cloudwatch_logs
    sns_notifications_enabled = var.enable_sns_notifications
    sample_data_created      = var.create_source_bucket && var.create_sample_data
  }
}

# -----------------------------------------------------------------------------
# Cost Estimation Information
# -----------------------------------------------------------------------------

output "cost_estimation_info" {
  description = "Information for estimating costs of deployed resources"
  value = {
    efs_storage_cost_per_gb_month        = "Standard: $0.30, IA: $0.25"
    efs_throughput_cost_provisioned      = var.efs_throughput_mode == "provisioned" ? "$6.00 per provisioned MiB/s per month" : "N/A"
    datasync_cost_per_gb_transferred     = "$0.0125 per GB transferred"
    s3_storage_cost_standard_per_gb      = "$0.023 per GB per month"
    cloudwatch_logs_cost_per_gb_ingested = "$0.50 per GB ingested"
    sns_cost_per_notification           = "$0.50 per 1 million notifications"
  }
}

# -----------------------------------------------------------------------------
# Next Steps Information
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Suggested next steps after deployment"
  value = [
    "1. Verify EFS file system is available: aws efs describe-file-systems --file-system-id ${aws_efs_file_system.main.id}",
    "2. Check DataSync task status: aws datasync describe-task --task-arn ${aws_datasync_task.main.arn}",
    "3. Start DataSync task execution: aws datasync start-task-execution --task-arn ${aws_datasync_task.main.arn}",
    "4. Monitor task progress: aws datasync describe-task-execution --task-execution-arn <execution-arn>",
    "5. Mount EFS from EC2 instance: sudo mount -t efs ${aws_efs_file_system.main.id}:/ /mnt/efs",
    var.enable_cloudwatch_logs ? "6. View DataSync logs: aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.datasync[0].name}" : "6. Enable CloudWatch logs for detailed monitoring",
    var.enable_sns_notifications ? "7. Confirm email subscription for notifications" : "7. Consider enabling SNS notifications for task status updates"
  ]
}