# Outputs for AWS Storage Gateway hybrid cloud storage infrastructure

# Gateway Information
output "gateway_name" {
  description = "Name of the Storage Gateway"
  value       = local.gateway_name_unique
}

output "gateway_instance_id" {
  description = "EC2 instance ID of the Storage Gateway"
  value       = aws_instance.storage_gateway.id
}

output "gateway_public_ip" {
  description = "Public IP address of the Storage Gateway"
  value       = aws_instance.storage_gateway.public_ip
}

output "gateway_private_ip" {
  description = "Private IP address of the Storage Gateway"
  value       = aws_instance.storage_gateway.private_ip
}

output "gateway_security_group_id" {
  description = "Security group ID for the Storage Gateway"
  value       = aws_security_group.storage_gateway.id
}

# S3 Storage Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Storage Gateway"
  value       = aws_s3_bucket.storage_gateway.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Storage Gateway"
  value       = aws_s3_bucket.storage_gateway.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.storage_gateway.region
}

# KMS Key Information
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.storage_gateway.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.storage_gateway.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.storage_gateway.name
}

# IAM Role Information
output "storage_gateway_role_arn" {
  description = "ARN of the IAM role for Storage Gateway"
  value       = aws_iam_role.storage_gateway.arn
}

output "storage_gateway_role_name" {
  description = "Name of the IAM role for Storage Gateway"
  value       = aws_iam_role.storage_gateway.name
}

# Cache Storage Information
output "cache_volume_id" {
  description = "ID of the EBS volume used for cache storage"
  value       = aws_ebs_volume.cache.id
}

output "cache_volume_size" {
  description = "Size of the cache volume in GB"
  value       = aws_ebs_volume.cache.size
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group (if monitoring enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.storage_gateway[0].name : "Monitoring not enabled"
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group (if monitoring enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.storage_gateway[0].arn : "Monitoring not enabled"
}

# Network Information
output "vpc_id" {
  description = "VPC ID where Storage Gateway is deployed"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet ID where Storage Gateway is deployed"
  value       = local.subnet_id
}

output "availability_zone" {
  description = "Availability zone where Storage Gateway is deployed"
  value       = aws_instance.storage_gateway.availability_zone
}

# Activation and Configuration Commands
output "activation_key_command" {
  description = "Command to retrieve the activation key from the gateway"
  value       = "curl -s 'http://${aws_instance.storage_gateway.public_ip}/?activationRegion=${data.aws_region.current.name}' | grep -o 'activationKey=[^&]*' | cut -d'=' -f2"
}

output "gateway_activation_command" {
  description = "AWS CLI command to activate the Storage Gateway"
  value = <<-EOT
    # First, get the activation key:
    ACTIVATION_KEY=$(curl -s 'http://${aws_instance.storage_gateway.public_ip}/?activationRegion=${data.aws_region.current.name}' | grep -o 'activationKey=[^&]*' | cut -d'=' -f2)
    
    # Then activate the gateway:
    aws storagegateway activate-gateway \
        --activation-key $ACTIVATION_KEY \
        --gateway-name ${local.gateway_name_unique} \
        --gateway-timezone ${var.gateway_timezone} \
        --gateway-region ${data.aws_region.current.name} \
        --gateway-type FILE_S3
  EOT
}

output "cache_configuration_command" {
  description = "AWS CLI command to configure cache storage (run after activation)"
  value = <<-EOT
    # Get the gateway ARN after activation:
    GATEWAY_ARN=$(aws storagegateway list-gateways --query 'Gateways[?GatewayName==`${local.gateway_name_unique}`].GatewayARN' --output text)
    
    # Get the disk ID for cache configuration:
    DISK_ID=$(aws storagegateway list-local-disks --gateway-arn $GATEWAY_ARN --query 'Disks[?DiskPath==`/dev/sdf`].DiskId' --output text)
    
    # Add cache storage:
    aws storagegateway add-cache --gateway-arn $GATEWAY_ARN --disk-ids $DISK_ID
  EOT
}

output "nfs_file_share_command" {
  description = "AWS CLI command to create NFS file share (run after cache configuration)"
  value = <<-EOT
    # Get the gateway ARN:
    GATEWAY_ARN=$(aws storagegateway list-gateways --query 'Gateways[?GatewayName==`${local.gateway_name_unique}`].GatewayARN' --output text)
    
    # Create NFS file share:
    aws storagegateway create-nfs-file-share \
        --client-token $(date +%s) \
        --gateway-arn $GATEWAY_ARN \
        --location-arn ${aws_s3_bucket.storage_gateway.arn} \
        --role ${aws_iam_role.storage_gateway.arn} \
        --default-storage-class ${var.default_storage_class} \
        --nfs-file-share-defaults '{"FileMode":"0644","DirectoryMode":"0755","GroupId":65534,"OwnerId":65534}' \
        --client-list ${join(" ", [for cidr in var.nfs_client_cidrs : "\"${cidr}\""])} \
        --squash RootSquash
  EOT
}

output "smb_file_share_command" {
  description = "AWS CLI command to create SMB file share (run after cache configuration)"
  value = var.enable_smb_share ? <<-EOT
    # Get the gateway ARN:
    GATEWAY_ARN=$(aws storagegateway list-gateways --query 'Gateways[?GatewayName==`${local.gateway_name_unique}`].GatewayARN' --output text)
    
    # Create SMB file share:
    aws storagegateway create-smb-file-share \
        --client-token $(date +%s) \
        --gateway-arn $GATEWAY_ARN \
        --location-arn ${aws_s3_bucket.storage_gateway.arn}/smb-share \
        --role ${aws_iam_role.storage_gateway.arn} \
        --default-storage-class ${var.default_storage_class} \
        --authentication GuestAccess
  EOT : "SMB file share creation is disabled"
}

# Mount Commands for Client Systems
output "nfs_mount_command" {
  description = "Command to mount NFS file share on client systems"
  value       = "sudo mount -t nfs ${aws_instance.storage_gateway.private_ip}:/${aws_s3_bucket.storage_gateway.id} /local/mount/point"
}

output "smb_mount_command" {
  description = "Command to mount SMB file share on client systems"
  value       = var.enable_smb_share ? "sudo mount -t cifs //${aws_instance.storage_gateway.private_ip}/${aws_s3_bucket.storage_gateway.id} /local/mount/point" : "SMB mounting is disabled"
}

# Monitoring and Management URLs
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for Storage Gateway monitoring"
  value = var.enable_cloudwatch_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=StorageGateway" : "Monitoring not enabled"
}

output "storage_gateway_console_url" {
  description = "URL to AWS Storage Gateway console"
  value       = "https://console.aws.amazon.com/storagegateway/home?region=${data.aws_region.current.name}"
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = <<-EOT
    AWS Storage Gateway Hybrid Cloud Storage Deployment Summary:
    
    ✅ Resources Created:
    - Storage Gateway EC2 Instance: ${aws_instance.storage_gateway.id}
    - S3 Bucket: ${aws_s3_bucket.storage_gateway.id}
    - KMS Key: ${aws_kms_key.storage_gateway.key_id}
    - IAM Role: ${aws_iam_role.storage_gateway.name}
    - Cache Volume: ${aws_ebs_volume.cache.id} (${var.cache_disk_size}GB)
    - Security Group: ${aws_security_group.storage_gateway.id}
    ${var.enable_cloudwatch_monitoring ? "- CloudWatch Log Group: ${aws_cloudwatch_log_group.storage_gateway[0].name}" : ""}
    
    📋 Next Steps:
    1. Wait 5-10 minutes for Storage Gateway to initialize
    2. Run the activation command provided in 'gateway_activation_command' output
    3. Configure cache storage using 'cache_configuration_command' output
    4. Create file shares using the provided commands
    5. Mount file shares on client systems using the mount commands
    
    🔗 Management URLs:
    - Storage Gateway Console: ${local.storage_gateway_console_url}
    ${var.enable_cloudwatch_monitoring ? "- CloudWatch Dashboard: ${local.cloudwatch_dashboard_url}" : ""}
    
    📊 Configuration:
    - Gateway Type: FILE_S3
    - Instance Type: ${var.gateway_instance_type}
    - Cache Size: ${var.cache_disk_size}GB
    - Default Storage Class: ${var.default_storage_class}
    - NFS Client Access: ${join(", ", var.nfs_client_cidrs)}
    - SMB Share Enabled: ${var.enable_smb_share}
    - CloudWatch Monitoring: ${var.enable_cloudwatch_monitoring}
  EOT
}

# Local values for URLs
locals {
  storage_gateway_console_url = "https://console.aws.amazon.com/storagegateway/home?region=${data.aws_region.current.name}"
  cloudwatch_dashboard_url    = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=StorageGateway"
}