# EFS File System Outputs
output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "efs_file_system_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "efs_performance_mode" {
  description = "Performance mode of the EFS file system"
  value       = aws_efs_file_system.main.performance_mode
}

output "efs_throughput_mode" {
  description = "Throughput mode of the EFS file system"
  value       = aws_efs_file_system.main.throughput_mode
}

output "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only for provisioned mode)"
  value       = aws_efs_file_system.main.provisioned_throughput_in_mibps
}

output "efs_encrypted" {
  description = "Whether the EFS file system is encrypted"
  value       = aws_efs_file_system.main.encrypted
}

output "efs_kms_key_id" {
  description = "KMS key ID used for EFS encryption"
  value       = var.efs_encrypted ? aws_kms_key.efs[0].id : null
}

# Mount Target Outputs
output "efs_mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "efs_mount_target_dns_names" {
  description = "DNS names of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].dns_name
}

output "efs_mount_target_availability_zones" {
  description = "Availability zones of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].availability_zone_name
}

output "efs_mount_target_subnets" {
  description = "Subnet IDs where mount targets are created"
  value       = aws_efs_mount_target.main[*].subnet_id
}

# Security Group Outputs
output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "efs_security_group_arn" {
  description = "ARN of the EFS security group"
  value       = aws_security_group.efs.arn
}

# CloudWatch Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (when enabled)"
  value = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=EFS-Performance-${var.project_name}-${random_id.suffix.hex}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (when enabled)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.efs[0].dashboard_name : null
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms (when enabled)"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.efs_high_throughput_utilization[0].alarm_name,
    aws_cloudwatch_metric_alarm.efs_high_client_connections[0].alarm_name,
    aws_cloudwatch_metric_alarm.efs_high_io_latency[0].alarm_name
  ] : []
}

# EC2 Test Instance Outputs (when enabled)
output "test_instance_id" {
  description = "ID of the EC2 test instance (when created)"
  value       = var.create_test_instance ? aws_instance.efs_test[0].id : null
}

output "test_instance_public_ip" {
  description = "Public IP of the EC2 test instance (when created)"
  value       = var.create_test_instance ? aws_instance.efs_test[0].public_ip : null
}

output "test_instance_private_ip" {
  description = "Private IP of the EC2 test instance (when created)"
  value       = var.create_test_instance ? aws_instance.efs_test[0].private_ip : null
}

# Mount Commands for Reference
output "efs_mount_command_linux" {
  description = "Command to mount EFS on Linux instances"
  value       = "sudo mount -t efs ${aws_efs_file_system.main.id}:/ /mnt/efs"
}

output "efs_mount_command_with_encryption" {
  description = "Command to mount EFS with encryption in transit on Linux instances"
  value       = "sudo mount -t efs -o tls ${aws_efs_file_system.main.id}:/ /mnt/efs"
}

output "efs_fstab_entry" {
  description = "Entry to add to /etc/fstab for persistent mounting"
  value       = "${aws_efs_file_system.main.id}.efs.${var.aws_region}.amazonaws.com:/ /mnt/efs efs defaults,_netdev 0 0"
}

# Network Configuration Outputs
output "vpc_id" {
  description = "VPC ID where EFS is deployed"
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "Subnet IDs used for mount targets"
  value       = local.subnet_ids
}

# Resource Naming Information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "resource_name_prefix" {
  description = "Prefix used for resource naming"
  value       = "${var.project_name}-${random_id.suffix.hex}"
}

# Cost and Performance Information
output "estimated_monthly_cost_storage" {
  description = "Estimated monthly cost for EFS storage (per GB stored)"
  value       = "Standard storage: $0.30/GB/month, IA storage: $0.025/GB/month"
}

output "estimated_monthly_cost_throughput" {
  description = "Estimated monthly cost for provisioned throughput (when applicable)"
  value       = var.efs_throughput_mode == "provisioned" ? "Provisioned throughput: $6.00 per MiB/s/month (${var.efs_provisioned_throughput} MiB/s = $${var.efs_provisioned_throughput * 6}/month)" : "No additional throughput costs for ${var.efs_throughput_mode} mode"
}

# Backup Information
output "backup_enabled" {
  description = "Whether automatic backups are enabled"
  value       = var.efs_backup_enabled
}

output "lifecycle_policy" {
  description = "Lifecycle policy for transitioning to IA storage"
  value       = var.efs_lifecycle_policy
}

# Performance Testing Commands
output "performance_test_commands" {
  description = "Commands for testing EFS performance"
  value = {
    throughput_test = "fio --name=throughput-test --directory=/mnt/efs --size=1G --time_based --runtime=60s --ramp_time=2s --ioengine=libaio --direct=1 --verify=0 --bs=1M --iodepth=64 --rw=write --group_reporting=1"
    latency_test    = "fio --name=latency-test --directory=/mnt/efs --size=100M --time_based --runtime=60s --ramp_time=2s --ioengine=libaio --direct=1 --verify=0 --bs=4K --iodepth=1 --rw=randread --group_reporting=1"
    mixed_workload  = "fio --name=mixed-workload --directory=/mnt/efs --size=500M --time_based --runtime=60s --ramp_time=2s --ioengine=libaio --direct=1 --verify=0 --bs=64K --iodepth=16 --rw=randrw --rwmixread=70 --group_reporting=1"
  }
}