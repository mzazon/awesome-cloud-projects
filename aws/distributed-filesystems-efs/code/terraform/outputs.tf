# EFS File System outputs
output "efs_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "efs_dns_name" {
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

output "efs_encrypted" {
  description = "Whether the EFS file system is encrypted"
  value       = aws_efs_file_system.main.encrypted
}

# Mount Target outputs
output "mount_target_ids" {
  description = "List of EFS mount target IDs"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_dns_names" {
  description = "List of EFS mount target DNS names"
  value       = aws_efs_mount_target.main[*].dns_name
}

output "mount_target_network_interface_ids" {
  description = "List of EFS mount target network interface IDs"
  value       = aws_efs_mount_target.main[*].network_interface_id
}

output "mount_target_availability_zones" {
  description = "List of availability zones where mount targets are created"
  value       = [for subnet in data.aws_subnet.selected : subnet.availability_zone]
}

# Access Point outputs
output "access_point_ids" {
  description = "List of EFS access point IDs"
  value       = aws_efs_access_point.main[*].id
}

output "access_point_arns" {
  description = "List of EFS access point ARNs"
  value       = aws_efs_access_point.main[*].arn
}

output "access_point_names" {
  description = "List of EFS access point names"
  value       = [for ap in var.access_points : ap.name]
}

output "access_point_paths" {
  description = "List of EFS access point paths"
  value       = [for ap in var.access_points : ap.path]
}

# Security Group outputs
output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = var.create_ec2_instances ? aws_security_group.ec2[0].id : null
}

# EC2 Instance outputs
output "ec2_instance_ids" {
  description = "List of EC2 instance IDs"
  value       = var.create_ec2_instances ? aws_instance.efs_client[*].id : []
}

output "ec2_instance_public_ips" {
  description = "List of EC2 instance public IP addresses"
  value       = var.create_ec2_instances ? aws_instance.efs_client[*].public_ip : []
}

output "ec2_instance_private_ips" {
  description = "List of EC2 instance private IP addresses"
  value       = var.create_ec2_instances ? aws_instance.efs_client[*].private_ip : []
}

output "ec2_instance_availability_zones" {
  description = "List of availability zones where EC2 instances are created"
  value       = var.create_ec2_instances ? aws_instance.efs_client[*].availability_zone : []
}

# IAM outputs
output "ec2_iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = var.create_ec2_instances ? aws_iam_role.ec2_efs_role[0].arn : null
}

output "ec2_iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile for EC2 instances"
  value       = var.create_ec2_instances ? aws_iam_instance_profile.ec2_efs_profile[0].arn : null
}

# CloudWatch outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EFS"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.efs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for EFS"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.efs[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=EFS-${local.name_prefix}" : null
}

# Backup outputs
output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = var.enable_backup ? aws_backup_vault.efs[0].name : null
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = var.enable_backup ? aws_backup_vault.efs[0].arn : null
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = var.enable_backup ? aws_backup_plan.efs[0].id : null
}

output "backup_plan_arn" {
  description = "ARN of the AWS Backup plan"
  value       = var.enable_backup ? aws_backup_plan.efs[0].arn : null
}

# Connection information
output "mount_commands" {
  description = "Commands to mount the EFS file system"
  value = {
    main_filesystem = "sudo mount -t efs -o tls,iam ${aws_efs_file_system.main.id}:/ /mnt/efs"
    access_points = {
      for i, ap in var.access_points : ap.name => "sudo mount -t efs -o tls,iam,accesspoint=${aws_efs_access_point.main[i].id} ${aws_efs_file_system.main.id}:/ /mnt/${ap.name}"
    }
  }
}

output "fstab_entries" {
  description = "Entries to add to /etc/fstab for persistent mounting"
  value = {
    main_filesystem = "${aws_efs_file_system.main.id}:/ /mnt/efs efs defaults,_netdev,tls,iam"
    access_points = {
      for i, ap in var.access_points : ap.name => "${aws_efs_file_system.main.id}:/ /mnt/${ap.name} efs defaults,_netdev,tls,iam,accesspoint=${aws_efs_access_point.main[i].id}"
    }
  }
}

# SSH connection information
output "ssh_commands" {
  description = "SSH commands to connect to EC2 instances"
  value = var.create_ec2_instances && var.key_pair_name != null ? {
    for i, instance in aws_instance.efs_client : "instance-${i + 1}" => "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${instance.public_ip}"
  } : {}
}

# Performance testing commands
output "performance_test_commands" {
  description = "Commands to run performance tests on EC2 instances"
  value = var.create_ec2_instances ? {
    for i, instance in aws_instance.efs_client : "instance-${i + 1}" => "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${instance.public_ip} 'sudo /usr/local/bin/test-efs-performance.sh'"
  } : {}
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    efs_file_system_id    = aws_efs_file_system.main.id
    mount_targets_count   = length(aws_efs_mount_target.main)
    access_points_count   = length(aws_efs_access_point.main)
    ec2_instances_count   = var.create_ec2_instances ? length(aws_instance.efs_client) : 0
    backup_enabled        = var.enable_backup
    monitoring_enabled    = var.enable_cloudwatch_monitoring
    encryption_enabled    = var.enable_encryption
    performance_mode      = var.efs_performance_mode
    throughput_mode       = var.efs_throughput_mode
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Cost optimization features enabled"
  value = {
    lifecycle_policy = {
      transition_to_ia = var.transition_to_ia
      transition_to_primary = var.transition_to_primary_storage_class
    }
    backup_retention_days = var.enable_backup ? var.backup_retention_days : null
    throughput_mode = var.efs_throughput_mode
    performance_mode = var.efs_performance_mode
  }
}

# Validation commands
output "validation_commands" {
  description = "Commands to validate the EFS deployment"
  value = {
    check_efs_status = "aws efs describe-file-systems --file-system-id ${aws_efs_file_system.main.id} --query 'FileSystems[0].LifeCycleState' --output text"
    check_mount_targets = "aws efs describe-mount-targets --file-system-id ${aws_efs_file_system.main.id} --query 'MountTargets[*].{MountTargetId:MountTargetId,LifeCycleState:LifeCycleState,AvailabilityZone:AvailabilityZoneName}' --output table"
    check_access_points = "aws efs describe-access-points --file-system-id ${aws_efs_file_system.main.id} --query 'AccessPoints[*].{AccessPointId:AccessPointId,Name:Name,LifeCycleState:LifeCycleState}' --output table"
    list_backups = var.enable_backup ? "aws backup list-recovery-points --backup-vault-name ${aws_backup_vault.efs[0].name} --output table" : "echo 'Backup not enabled'"
  }
}