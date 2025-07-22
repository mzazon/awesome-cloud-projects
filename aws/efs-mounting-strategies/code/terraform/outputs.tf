# Output values for EFS mounting strategies infrastructure

# EFS File System Information
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

output "efs_file_system_mount_targets" {
  description = "Mount target information for the EFS file system"
  value = [
    for mt in aws_efs_mount_target.main : {
      id                = mt.id
      dns_name          = mt.dns_name
      mount_target_id   = mt.mount_target_id
      network_interface_id = mt.network_interface_id
      subnet_id         = mt.subnet_id
      availability_zone = mt.availability_zone_name
    }
  ]
}

# EFS Access Points Information
output "efs_access_points" {
  description = "Information about EFS access points"
  value = var.create_access_points ? {
    for k, v in aws_efs_access_point.access_points : k => {
      id       = v.id
      arn      = v.arn
      path     = v.root_directory[0].path
      uid      = v.posix_user[0].uid
      gid      = v.posix_user[0].gid
    }
  } : {}
}

# Security Group Information
output "efs_security_group_id" {
  description = "ID of the EFS mount targets security group"
  value       = aws_security_group.efs_mount_targets.id
}

output "efs_security_group_arn" {
  description = "ARN of the EFS mount targets security group"
  value       = aws_security_group.efs_mount_targets.arn
}

# Demo Instance Information (if created)
output "demo_instance_id" {
  description = "ID of the demo EC2 instance"
  value       = var.create_demo_instance ? aws_instance.demo[0].id : null
}

output "demo_instance_public_ip" {
  description = "Public IP address of the demo EC2 instance"
  value       = var.create_demo_instance ? aws_instance.demo[0].public_ip : null
}

output "demo_instance_private_ip" {
  description = "Private IP address of the demo EC2 instance"
  value       = var.create_demo_instance ? aws_instance.demo[0].private_ip : null
}

output "demo_instance_security_group_id" {
  description = "Security group ID for the demo EC2 instance"
  value       = var.create_demo_instance ? aws_security_group.demo_instance[0].id : null
}

# IAM Role Information (if demo instance is created)
output "ec2_efs_role_arn" {
  description = "ARN of the EC2 EFS IAM role"
  value       = var.create_demo_instance ? aws_iam_role.ec2_efs_role[0].arn : null
}

output "ec2_efs_instance_profile_arn" {
  description = "ARN of the EC2 EFS instance profile"
  value       = var.create_demo_instance ? aws_iam_instance_profile.ec2_efs_profile[0].arn : null
}

# Mounting Instructions
output "mounting_instructions" {
  description = "Instructions for mounting the EFS file system"
  value = {
    # Standard NFS mount command
    nfs_mount_command = "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 ${aws_efs_file_system.main.dns_name}:/ /mnt/efs"
    
    # EFS Utils mount command
    efs_utils_mount_command = "sudo mount -t efs -o tls ${aws_efs_file_system.main.id}:/ /mnt/efs"
    
    # Access point mount commands
    access_point_mount_commands = var.create_access_points ? {
      for k, v in aws_efs_access_point.access_points : k => 
        "sudo mount -t efs -o tls,accesspoint=${v.id} ${aws_efs_file_system.main.id}:/ /mnt/efs-${k}"
    } : {}
    
    # fstab entries
    fstab_entries = {
      nfs_entry = "${aws_efs_file_system.main.dns_name}:/ /mnt/efs efs defaults,_netdev,tls"
      access_point_entries = var.create_access_points ? {
        for k, v in aws_efs_access_point.access_points : k => 
          "${aws_efs_file_system.main.dns_name}:/ /mnt/efs-${k} efs defaults,_netdev,tls,accesspoint=${v.id}"
      } : {}
    }
  }
}

# VPC and Networking Information
output "vpc_id" {
  description = "ID of the VPC where resources were created"
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "List of subnet IDs where mount targets were created"
  value       = local.mount_target_subnets
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    efs_storage_gb = "0.30 per GB (Standard storage class)"
    efs_ia_storage_gb = "0.0125 per GB (Infrequent Access storage class)"
    provisioned_throughput = var.efs_throughput_mode == "provisioned" ? "${var.efs_provisioned_throughput * 6.00} (${var.efs_provisioned_throughput} MiB/s * $6.00)" : "0.00 (Bursting mode)"
    mount_targets = "${length(local.mount_target_subnets) * 0.00} (No charge for mount targets)"
    demo_instance = var.create_demo_instance ? "~8.76 (t3.micro in us-east-1)" : "0.00"
    note = "Actual costs depend on usage patterns, region, and data transfer"
  }
}

# Connection Information
output "connection_info" {
  description = "Connection information for accessing the EFS file system"
  value = {
    file_system_id = aws_efs_file_system.main.id
    region = var.aws_region
    dns_name = aws_efs_file_system.main.dns_name
    mount_targets = [
      for mt in aws_efs_mount_target.main : {
        availability_zone = mt.availability_zone_name
        subnet_id = mt.subnet_id
        ip_address = mt.ip_address
      }
    ]
    security_requirements = {
      nfs_port = "2049"
      security_group_id = aws_security_group.efs_mount_targets.id
      vpc_access_required = true
    }
  }
}

# Performance Information
output "performance_configuration" {
  description = "EFS performance configuration details"
  value = {
    performance_mode = var.efs_performance_mode
    throughput_mode = var.efs_throughput_mode
    provisioned_throughput_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null
    encryption_at_rest = var.efs_encryption
    lifecycle_policy = {
      transition_to_ia = "AFTER_30_DAYS"
      transition_to_primary_storage_class = "AFTER_1_ACCESS"
    }
    max_ops_per_second = var.efs_performance_mode == "generalPurpose" ? 7000 : 500000
    max_throughput_mibps = var.efs_performance_mode == "generalPurpose" ? 250 : 1000
  }
}