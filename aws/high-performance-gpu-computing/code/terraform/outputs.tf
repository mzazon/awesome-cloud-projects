# Outputs for GPU-accelerated workloads infrastructure
# These outputs provide essential information for connecting to and managing
# the GPU instances and associated resources

# =============================================================================
# Instance Information Outputs
# =============================================================================

output "p4_instance_id" {
  description = "Instance ID of the P4 training instance"
  value       = var.enable_p4_instance ? aws_instance.p4_training[0].id : null
}

output "p4_instance_public_ip" {
  description = "Public IP address of the P4 training instance"
  value       = var.enable_p4_instance ? aws_instance.p4_training[0].public_ip : null
}

output "p4_instance_private_ip" {
  description = "Private IP address of the P4 training instance"
  value       = var.enable_p4_instance ? aws_instance.p4_training[0].private_ip : null
}

output "p4_instance_type" {
  description = "Instance type of the P4 training instance"
  value       = var.enable_p4_instance ? aws_instance.p4_training[0].instance_type : null
}

output "p4_instance_state" {
  description = "Current state of the P4 training instance"
  value       = var.enable_p4_instance ? aws_instance.p4_training[0].instance_state : null
}

output "g4_spot_instance_ids" {
  description = "Instance IDs of G4 Spot instances for inference"
  value       = var.enable_g4_instances && var.use_spot_instances ? aws_spot_instance_request.g4_inference_spot[*].spot_instance_id : []
}

output "g4_ondemand_instance_ids" {
  description = "Instance IDs of G4 On-Demand instances for inference"
  value       = var.enable_g4_instances && !var.use_spot_instances ? aws_instance.g4_inference_ondemand[*].id : []
}

output "g4_instance_public_ips" {
  description = "Public IP addresses of all G4 instances"
  value = var.enable_g4_instances ? (
    var.use_spot_instances ? 
    [for req in aws_spot_instance_request.g4_inference_spot : req.public_ip] :
    aws_instance.g4_inference_ondemand[*].public_ip
  ) : []
}

output "g4_instance_private_ips" {
  description = "Private IP addresses of all G4 instances"
  value = var.enable_g4_instances ? (
    var.use_spot_instances ? 
    [for req in aws_spot_instance_request.g4_inference_spot : req.private_ip] :
    aws_instance.g4_inference_ondemand[*].private_ip
  ) : []
}

# =============================================================================
# Network and Security Information
# =============================================================================

output "security_group_id" {
  description = "Security group ID for GPU instances"
  value       = aws_security_group.gpu_instances.id
}

output "vpc_id" {
  description = "VPC ID where GPU instances are deployed"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet ID where GPU instances are deployed"
  value       = local.subnet_id
}

output "key_pair_name" {
  description = "Name of the SSH key pair for instance access"
  value       = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_workload[0].key_name
}

output "ssh_private_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing SSH private key"
  value       = var.ssh_key_name == "" ? aws_secretsmanager_secret.ssh_private_key[0].arn : null
  sensitive   = true
}

# =============================================================================
# Storage Information
# =============================================================================

output "efs_file_system_id" {
  description = "EFS file system ID for shared storage"
  value       = var.create_efs_storage ? aws_efs_file_system.gpu_shared_storage[0].id : null
}

output "efs_file_system_dns_name" {
  description = "EFS file system DNS name for mounting"
  value       = var.create_efs_storage ? aws_efs_file_system.gpu_shared_storage[0].dns_name : null
}

output "efs_mount_target_dns_name" {
  description = "EFS mount target DNS name"
  value       = var.create_efs_storage ? aws_efs_mount_target.gpu_shared_storage[0].dns_name : null
}

# =============================================================================
# IAM and Security Information
# =============================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role for GPU instances"
  value       = aws_iam_role.gpu_instance_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile for GPU instances"
  value       = aws_iam_instance_profile.gpu_instance_profile.name
}

# =============================================================================
# Monitoring Information
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for GPU monitoring alerts"
  value       = var.enable_gpu_monitoring && var.notification_email != "" ? aws_sns_topic.gpu_monitoring_alerts[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for GPU monitoring"
  value       = var.enable_gpu_monitoring ? aws_cloudwatch_dashboard.gpu_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_gpu_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.gpu_monitoring[0].dashboard_name}" : null
}

# =============================================================================
# Cost and Resource Management
# =============================================================================

output "total_instance_count" {
  description = "Total number of GPU instances launched"
  value = (var.enable_p4_instance ? 1 : 0) + (var.enable_g4_instances ? var.g4_instance_count : 0)
}

output "estimated_hourly_cost_usd" {
  description = "Estimated hourly cost in USD for all GPU instances (approximate)"
  value = format("%.2f", 
    (var.enable_p4_instance && var.p4_instance_type == "p4d.24xlarge" ? 32.77 : 0) +
    (var.enable_g4_instances && var.g4_instance_type == "g4dn.xlarge" ? (var.use_spot_instances ? 0.50 : 0.526) * var.g4_instance_count : 0) +
    (var.enable_g4_instances && var.g4_instance_type == "g4dn.2xlarge" ? (var.use_spot_instances ? 0.75 : 0.752) * var.g4_instance_count : 0)
  )
}

output "spot_pricing_enabled" {
  description = "Whether Spot pricing is enabled for G4 instances"
  value       = var.use_spot_instances
}

output "spot_max_price" {
  description = "Maximum Spot price configured for G4 instances"
  value       = var.use_spot_instances ? var.spot_max_price : null
}

# =============================================================================
# Connection Information
# =============================================================================

output "ssh_connection_commands" {
  description = "SSH commands to connect to instances"
  value = {
    p4_instance = var.enable_p4_instance ? "ssh -i ~/.ssh/${local.name_prefix}-gpu-key-${local.name_suffix}.pem ubuntu@${aws_instance.p4_training[0].public_ip}" : null
    g4_instances = var.enable_g4_instances ? [
      for i, ip in (var.use_spot_instances ? 
        [for req in aws_spot_instance_request.g4_inference_spot : req.public_ip] :
        aws_instance.g4_inference_ondemand[*].public_ip
      ) : "ssh -i ~/.ssh/${local.name_prefix}-gpu-key-${local.name_suffix}.pem ubuntu@${ip}"
    ] : []
  }
}

output "systems_manager_session_commands" {
  description = "AWS Systems Manager Session Manager commands for secure access"
  value = var.enable_ssm_access ? {
    p4_instance = var.enable_p4_instance ? "aws ssm start-session --target ${aws_instance.p4_training[0].id}" : null
    g4_instances = var.enable_g4_instances ? [
      for id in (var.use_spot_instances ? 
        aws_spot_instance_request.g4_inference_spot[*].spot_instance_id :
        aws_instance.g4_inference_ondemand[*].id
      ) : "aws ssm start-session --target ${id}"
    ] : []
  } : null
}

# =============================================================================
# AMI and Configuration Information
# =============================================================================

output "deep_learning_ami_id" {
  description = "AMI ID of the Deep Learning AMI used for instances"
  value       = data.aws_ami.deep_learning.id
}

output "deep_learning_ami_name" {
  description = "Name of the Deep Learning AMI used for instances"
  value       = data.aws_ami.deep_learning.name
}

# =============================================================================
# Resource Identifiers
# =============================================================================

output "resource_name_prefix" {
  description = "Common prefix used for all resource names"
  value       = local.name_prefix
}

output "resource_name_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.name_suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# =============================================================================
# Validation Outputs
# =============================================================================

output "gpu_driver_installation_commands" {
  description = "Commands to verify GPU driver installation on instances"
  value = {
    verify_nvidia_smi = "nvidia-smi"
    verify_cuda       = "python3 -c 'import torch; print(torch.cuda.is_available())'"
    check_gpu_count   = "nvidia-smi --query-gpu=count --format=csv,noheader,nounits"
  }
}

output "monitoring_validation_commands" {
  description = "Commands to validate GPU monitoring setup"
  value = var.enable_gpu_monitoring ? {
    list_gpu_metrics = "aws cloudwatch list-metrics --namespace GPU/EC2 --region ${data.aws_region.current.name}"
    check_cloudwatch_agent = "sudo systemctl status amazon-cloudwatch-agent"
  } : null
}

# =============================================================================
# Quick Start Information
# =============================================================================

output "quick_start_guide" {
  description = "Quick start guide for using the GPU infrastructure"
  value = {
    step_1 = "Wait 10-15 minutes for GPU driver installation to complete"
    step_2 = "SSH to instances using the provided SSH commands or use Systems Manager"
    step_3 = "Verify GPU availability with 'nvidia-smi' command"
    step_4 = "Monitor GPU performance via CloudWatch dashboard"
    step_5 = "Mount EFS storage if created: sudo mount -t efs ${var.create_efs_storage ? aws_efs_file_system.gpu_shared_storage[0].id : "efs-id"}:/ /mnt/efs"
  }
}