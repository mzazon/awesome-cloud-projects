# outputs.tf - Output Values for High-Performance File Systems with Amazon FSx
#
# This file defines the output values that are returned after the infrastructure
# is successfully deployed. These outputs provide essential information for
# accessing and managing the created FSx file systems.

# =============================================================================
# General Infrastructure Outputs
# =============================================================================

output "region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "project_prefix" {
  description = "Project prefix used for resource naming"
  value       = var.project_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# =============================================================================
# Networking Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC used for FSx file systems"
  value       = var.create_vpc ? aws_vpc.main[0].id : data.aws_vpc.default[0].id
}

output "subnet_ids" {
  description = "List of subnet IDs used for FSx file systems"
  value = var.create_vpc ? [
    for subnet in aws_subnet.public : subnet.id
  ] : (length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids)
}

output "security_group_id" {
  description = "ID of the security group for FSx file systems"
  value       = aws_security_group.fsx.id
}

# =============================================================================
# Amazon FSx for Lustre Outputs
# =============================================================================

output "lustre_file_system" {
  description = "Amazon FSx for Lustre file system information"
  value = var.create_lustre_filesystem ? {
    id                    = aws_fsx_lustre_file_system.main[0].id
    arn                   = aws_fsx_lustre_file_system.main[0].arn
    dns_name              = aws_fsx_lustre_file_system.main[0].dns_name
    mount_name            = aws_fsx_lustre_file_system.main[0].mount_name
    storage_capacity      = aws_fsx_lustre_file_system.main[0].storage_capacity
    deployment_type       = aws_fsx_lustre_file_system.main[0].deployment_type
    per_unit_throughput   = aws_fsx_lustre_file_system.main[0].per_unit_storage_throughput
    data_compression_type = aws_fsx_lustre_file_system.main[0].data_compression_type
    auto_import_policy    = aws_fsx_lustre_file_system.main[0].auto_import_policy
    import_path           = aws_fsx_lustre_file_system.main[0].import_path
    export_path           = aws_fsx_lustre_file_system.main[0].export_path
    network_interface_ids = aws_fsx_lustre_file_system.main[0].network_interface_ids
    owner_id             = aws_fsx_lustre_file_system.main[0].owner_id
    vpc_id               = aws_fsx_lustre_file_system.main[0].vpc_id
    weekly_maintenance_start_time = aws_fsx_lustre_file_system.main[0].weekly_maintenance_start_time
  } : null
}

output "lustre_mount_command" {
  description = "Command to mount the Lustre file system"
  value = var.create_lustre_filesystem ? "sudo mount -t lustre ${aws_fsx_lustre_file_system.main[0].dns_name}@tcp:/${aws_fsx_lustre_file_system.main[0].mount_name} /mnt/fsx" : null
}

output "lustre_performance_info" {
  description = "Performance characteristics of the Lustre file system"
  value = var.create_lustre_filesystem ? {
    baseline_throughput_mbps = var.lustre_storage_capacity * var.lustre_per_unit_storage_throughput / 1024
    burst_throughput_mbps   = var.lustre_deployment_type == "SCRATCH_2" ? var.lustre_storage_capacity * var.lustre_per_unit_storage_throughput / 1024 * 6 : null
    iops_estimate           = var.lustre_storage_capacity * 1000  # Approximate IOPS based on capacity
    compression_enabled     = var.lustre_data_compression_type == "LZ4"
  } : null
}

# =============================================================================
# Amazon FSx for Windows File Server Outputs
# =============================================================================

output "windows_file_system" {
  description = "Amazon FSx for Windows File Server information"
  value = var.create_windows_filesystem ? {
    id                        = aws_fsx_windows_file_system.main[0].id
    arn                      = aws_fsx_windows_file_system.main[0].arn
    dns_name                 = aws_fsx_windows_file_system.main[0].dns_name
    storage_capacity         = aws_fsx_windows_file_system.main[0].storage_capacity
    deployment_type          = aws_fsx_windows_file_system.main[0].deployment_type
    throughput_capacity      = aws_fsx_windows_file_system.main[0].throughput_capacity
    network_interface_ids    = aws_fsx_windows_file_system.main[0].network_interface_ids
    owner_id                = aws_fsx_windows_file_system.main[0].owner_id
    vpc_id                  = aws_fsx_windows_file_system.main[0].vpc_id
    preferred_file_server_ip = aws_fsx_windows_file_system.main[0].preferred_file_server_ip
    remote_administration_endpoint = aws_fsx_windows_file_system.main[0].remote_administration_endpoint
    weekly_maintenance_start_time = aws_fsx_windows_file_system.main[0].weekly_maintenance_start_time
  } : null
}

output "windows_smb_share_path" {
  description = "SMB share path for Windows file system access"
  value = var.create_windows_filesystem ? "\\\\${aws_fsx_windows_file_system.main[0].dns_name}\\share" : null
}

output "windows_performance_info" {
  description = "Performance characteristics of the Windows file system"
  value = var.create_windows_filesystem ? {
    baseline_throughput_mbps = var.windows_throughput_capacity
    burst_throughput_mbps   = var.windows_throughput_capacity * 3  # Windows can burst to 3x baseline
    storage_type            = var.windows_deployment_type
    backup_enabled          = var.enable_automatic_backups
  } : null
}

# =============================================================================
# Amazon FSx for NetApp ONTAP Outputs
# =============================================================================

output "ontap_file_system" {
  description = "Amazon FSx for NetApp ONTAP file system information"
  value = var.create_ontap_filesystem ? {
    id                  = aws_fsx_ontap_file_system.main[0].id
    arn                = aws_fsx_ontap_file_system.main[0].arn
    storage_capacity    = aws_fsx_ontap_file_system.main[0].storage_capacity
    deployment_type     = aws_fsx_ontap_file_system.main[0].deployment_type
    throughput_capacity = aws_fsx_ontap_file_system.main[0].throughput_capacity
    network_interface_ids = aws_fsx_ontap_file_system.main[0].network_interface_ids
    owner_id           = aws_fsx_ontap_file_system.main[0].owner_id
    vpc_id             = aws_fsx_ontap_file_system.main[0].vpc_id
    weekly_maintenance_start_time = aws_fsx_ontap_file_system.main[0].weekly_maintenance_start_time
    endpoints = aws_fsx_ontap_file_system.main[0].endpoints
  } : null
}

output "ontap_management_endpoints" {
  description = "ONTAP management endpoints for administration"
  value = var.create_ontap_filesystem ? {
    management_dns = aws_fsx_ontap_file_system.main[0].endpoints[0].management[0].dns_name
    management_ip  = aws_fsx_ontap_file_system.main[0].endpoints[0].management[0].ip_addresses
    intercluster_dns = aws_fsx_ontap_file_system.main[0].endpoints[0].intercluster[0].dns_name
    intercluster_ip  = aws_fsx_ontap_file_system.main[0].endpoints[0].intercluster[0].ip_addresses
  } : null
}

output "ontap_svm" {
  description = "ONTAP Storage Virtual Machine information"
  value = var.create_ontap_filesystem && var.create_ontap_svm ? {
    id            = aws_fsx_ontap_storage_virtual_machine.main[0].id
    arn          = aws_fsx_ontap_storage_virtual_machine.main[0].arn
    name         = aws_fsx_ontap_storage_virtual_machine.main[0].name
    uuid         = aws_fsx_ontap_storage_virtual_machine.main[0].uuid
    endpoints    = aws_fsx_ontap_storage_virtual_machine.main[0].endpoints
    subtype      = aws_fsx_ontap_storage_virtual_machine.main[0].subtype
  } : null
}

output "ontap_volumes" {
  description = "ONTAP volume information"
  value = var.create_ontap_filesystem && var.create_ontap_svm && var.create_ontap_volumes ? {
    nfs_volume = {
      id             = aws_fsx_ontap_volume.nfs[0].id
      arn           = aws_fsx_ontap_volume.nfs[0].arn
      name          = aws_fsx_ontap_volume.nfs[0].name
      junction_path = aws_fsx_ontap_volume.nfs[0].junction_path
      size_mb       = aws_fsx_ontap_volume.nfs[0].size_in_megabytes
      security_style = aws_fsx_ontap_volume.nfs[0].security_style
      uuid          = aws_fsx_ontap_volume.nfs[0].uuid
    }
    smb_volume = {
      id             = aws_fsx_ontap_volume.smb[0].id
      arn           = aws_fsx_ontap_volume.smb[0].arn
      name          = aws_fsx_ontap_volume.smb[0].name
      junction_path = aws_fsx_ontap_volume.smb[0].junction_path
      size_mb       = aws_fsx_ontap_volume.smb[0].size_in_megabytes
      security_style = aws_fsx_ontap_volume.smb[0].security_style
      uuid          = aws_fsx_ontap_volume.smb[0].uuid
    }
  } : null
}

output "ontap_mount_commands" {
  description = "Commands to mount ONTAP volumes"
  value = var.create_ontap_filesystem && var.create_ontap_svm && var.create_ontap_volumes ? {
    nfs_mount = "sudo mount -t nfs ${aws_fsx_ontap_storage_virtual_machine.main[0].endpoints[0].nfs[0].dns_name}:/nfs /mnt/nfs"
    smb_mount = "\\\\${aws_fsx_ontap_storage_virtual_machine.main[0].endpoints[0].smb[0].dns_name}\\smb"
  } : null
}

output "ontap_performance_info" {
  description = "Performance characteristics of the ONTAP file system"
  value = var.create_ontap_filesystem ? {
    baseline_throughput_mbps = var.ontap_throughput_capacity
    burst_throughput_mbps   = var.ontap_throughput_capacity * 2  # ONTAP can burst to 2x baseline
    storage_efficiency      = var.create_ontap_volumes ? true : false
    multi_protocol_support  = var.create_ontap_volumes ? ["NFS", "SMB", "iSCSI"] : []
    deployment_type        = var.ontap_deployment_type
  } : null
}

# =============================================================================
# S3 Data Repository Outputs
# =============================================================================

output "s3_data_repository" {
  description = "S3 bucket information for Lustre data repository"
  value = var.create_lustre_filesystem && var.create_s3_data_repository ? {
    bucket_name    = aws_s3_bucket.lustre_data[0].bucket
    bucket_arn     = aws_s3_bucket.lustre_data[0].arn
    region        = aws_s3_bucket.lustre_data[0].region
    domain_name   = aws_s3_bucket.lustre_data[0].bucket_domain_name
    input_path    = "s3://${aws_s3_bucket.lustre_data[0].bucket}/input/"
    output_path   = "s3://${aws_s3_bucket.lustre_data[0].bucket}/output/"
    versioning    = "Enabled"
    encryption    = var.kms_key_id != null ? "KMS" : "AES256"
  } : null
}

# =============================================================================
# Monitoring and Alerting Outputs
# =============================================================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarms for FSx monitoring"
  value = var.create_cloudwatch_alarms ? {
    lustre_throughput = var.create_lustre_filesystem ? {
      name      = aws_cloudwatch_metric_alarm.lustre_throughput[0].alarm_name
      arn       = aws_cloudwatch_metric_alarm.lustre_throughput[0].arn
      threshold = var.alarm_threshold_lustre_throughput
    } : null
    windows_cpu = var.create_windows_filesystem ? {
      name      = aws_cloudwatch_metric_alarm.windows_cpu[0].alarm_name
      arn       = aws_cloudwatch_metric_alarm.windows_cpu[0].arn
      threshold = var.alarm_threshold_windows_cpu
    } : null
    ontap_storage = var.create_ontap_filesystem ? {
      name      = aws_cloudwatch_metric_alarm.ontap_storage[0].alarm_name
      arn       = aws_cloudwatch_metric_alarm.ontap_storage[0].arn
      threshold = var.alarm_threshold_ontap_storage
    } : null
  } : null
}

output "sns_topic" {
  description = "SNS topic for alarm notifications"
  value = var.create_cloudwatch_alarms && var.sns_notification_email != null ? {
    arn         = aws_sns_topic.alarms[0].arn
    name        = aws_sns_topic.alarms[0].name
    email       = var.sns_notification_email
  } : null
  sensitive = true
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for FSx logging"
  value = {
    lustre = var.create_lustre_filesystem ? {
      name = aws_cloudwatch_log_group.fsx_lustre[0].name
      arn  = aws_cloudwatch_log_group.fsx_lustre[0].arn
    } : null
  }
}

# =============================================================================
# Test Instance Outputs
# =============================================================================

output "test_instance" {
  description = "Test EC2 instance information"
  value = var.create_test_instances ? {
    id                = aws_instance.linux_test[0].id
    arn              = aws_instance.linux_test[0].arn
    public_ip        = aws_instance.linux_test[0].public_ip
    private_ip       = aws_instance.linux_test[0].private_ip
    public_dns       = aws_instance.linux_test[0].public_dns
    private_dns      = aws_instance.linux_test[0].private_dns
    instance_type    = aws_instance.linux_test[0].instance_type
    availability_zone = aws_instance.linux_test[0].availability_zone
    key_name         = aws_instance.linux_test[0].key_name
  } : null
}

output "test_instance_connection" {
  description = "SSH connection information for test instance"
  value = var.create_test_instances ? {
    ssh_command = "ssh -i ~/.ssh/${var.test_instance_key_name}.pem ec2-user@${aws_instance.linux_test[0].public_dns}"
    test_scripts = [
      "/home/ec2-user/test_lustre.sh - Test Lustre performance",
      "/home/ec2-user/fsx_info.sh - Display FSx information"
    ]
  } : null
}

# =============================================================================
# Security and IAM Outputs
# =============================================================================

output "iam_roles" {
  description = "IAM roles created for FSx services"
  value = {
    fsx_service_role = var.create_lustre_filesystem && var.create_s3_data_repository ? {
      name = aws_iam_role.fsx_service[0].name
      arn  = aws_iam_role.fsx_service[0].arn
    } : null
    ec2_fsx_role = var.create_test_instances ? {
      name = aws_iam_role.ec2_fsx_access[0].name
      arn  = aws_iam_role.ec2_fsx_access[0].arn
    } : null
  }
}

# =============================================================================
# Cost Estimation Outputs
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for FSx file systems (USD)"
  value = {
    lustre = var.create_lustre_filesystem ? {
      storage_gb_month = var.lustre_storage_capacity
      throughput_mb_s  = var.lustre_per_unit_storage_throughput
      estimated_usd    = var.lustre_storage_capacity * 0.125 + (var.lustre_storage_capacity * var.lustre_per_unit_storage_throughput / 1024) * 0.013
    } : null
    windows = var.create_windows_filesystem ? {
      storage_gb_month     = var.windows_storage_capacity
      throughput_capacity  = var.windows_throughput_capacity
      estimated_usd       = var.windows_storage_capacity * 0.130 + var.windows_throughput_capacity * 2.20
    } : null
    ontap = var.create_ontap_filesystem ? {
      storage_gb_month     = var.ontap_storage_capacity
      throughput_capacity  = var.ontap_throughput_capacity
      estimated_usd       = var.ontap_storage_capacity * 0.163 + var.ontap_throughput_capacity * 1.31
    } : null
    s3_repository = var.create_lustre_filesystem && var.create_s3_data_repository ? {
      note = "S3 costs depend on data stored and requests - minimal for empty bucket"
    } : null
    test_instance = var.create_test_instances ? {
      instance_type = var.test_instance_type
      note         = "t3.medium ~$30/month if running 24/7"
    } : null
  }
}

# =============================================================================
# Quick Start Outputs
# =============================================================================

output "quick_start_guide" {
  description = "Quick start commands and information"
  value = {
    lustre_ready = var.create_lustre_filesystem
    windows_ready = var.create_windows_filesystem
    ontap_ready = var.create_ontap_filesystem
    monitoring_enabled = var.create_cloudwatch_alarms
    test_instance_available = var.create_test_instances
    
    next_steps = [
      var.create_test_instances ? "SSH to test instance: ${var.create_test_instances ? "ssh -i ~/.ssh/${var.test_instance_key_name}.pem ec2-user@${aws_instance.linux_test[0].public_dns}" : "N/A"}" : null,
      var.create_lustre_filesystem ? "Mount Lustre: ${var.create_lustre_filesystem ? "sudo mount -t lustre ${aws_fsx_lustre_file_system.main[0].dns_name}@tcp:/${aws_fsx_lustre_file_system.main[0].mount_name} /mnt/fsx" : "N/A"}" : null,
      var.create_cloudwatch_alarms ? "View CloudWatch alarms in AWS Console" : null,
      "Monitor file system performance in FSx Console"
    ]
  }
}