# Cluster Information
output "cluster_name" {
  description = "Name of the ParallelCluster HPC cluster"
  value       = local.cluster_name
}

output "cluster_region" {
  description = "AWS region where the cluster is deployed"
  value       = var.aws_region
}

output "cluster_availability_zone" {
  description = "Availability zone where the cluster is deployed"
  value       = var.availability_zone
}

# Network Information
output "vpc_id" {
  description = "ID of the VPC created for the HPC cluster"
  value       = aws_vpc.hpc_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.hpc_vpc.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet for head node"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of the private subnet for compute nodes"
  value       = aws_subnet.private_subnet.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.hpc_igw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = aws_nat_gateway.hpc_nat.id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT gateway"
  value       = aws_eip.nat_eip.public_ip
}

# Security Information
output "head_node_security_group_id" {
  description = "ID of the head node security group"
  value       = aws_security_group.head_node_sg.id
}

output "compute_node_security_group_id" {
  description = "ID of the compute node security group"
  value       = aws_security_group.compute_node_sg.id
}

output "keypair_name" {
  description = "Name of the EC2 key pair for SSH access"
  value       = aws_key_pair.hpc_keypair.key_name
}

# Storage Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for HPC data storage"
  value       = aws_s3_bucket.hpc_data_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for HPC data storage"
  value       = aws_s3_bucket.hpc_data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.hpc_data_bucket.bucket_domain_name
}

# IAM Information
output "parallelcluster_instance_role_arn" {
  description = "ARN of the ParallelCluster instance role"
  value       = aws_iam_role.parallelcluster_instance_role.arn
}

output "parallelcluster_instance_profile_arn" {
  description = "ARN of the ParallelCluster instance profile"
  value       = aws_iam_instance_profile.parallelcluster_instance_profile.arn
}

# Monitoring Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.parallelcluster_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.parallelcluster_logs[0].arn : null
}

# ParallelCluster Configuration
output "parallelcluster_config_content" {
  description = "Generated ParallelCluster configuration content"
  value       = local.parallelcluster_config
  sensitive   = false
}

output "parallelcluster_config_s3_key" {
  description = "S3 key for the ParallelCluster configuration file"
  value       = aws_s3_object.parallelcluster_config.key
}

# Connection Information
output "ssh_connection_command" {
  description = "SSH command to connect to the head node (after cluster creation)"
  value       = "ssh -i ${aws_key_pair.hpc_keypair.key_name}.pem ec2-user@<HEAD_NODE_PUBLIC_IP>"
}

output "cluster_creation_command" {
  description = "Command to create the ParallelCluster"
  value = "pcluster create-cluster --cluster-name ${local.cluster_name} --cluster-configuration s3://${aws_s3_bucket.hpc_data_bucket.bucket}/${aws_s3_object.parallelcluster_config.key}"
}

output "cluster_deletion_command" {
  description = "Command to delete the ParallelCluster"
  value       = "pcluster delete-cluster --cluster-name ${local.cluster_name}"
}

# Resource Identifiers
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Costs and Optimization
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    head_node_instance_type    = var.head_node_instance_type
    compute_instance_type      = var.compute_instance_type
    max_compute_nodes         = var.max_compute_nodes
    shared_storage_size_gb    = var.shared_storage_size
    fsx_storage_capacity_gb   = var.fsx_storage_capacity
    fsx_deployment_type       = var.fsx_deployment_type
    note                      = "Actual costs depend on usage patterns and auto-scaling behavior"
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp of the Terraform deployment"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = terraform.version
}

output "aws_provider_version" {
  description = "Version of the AWS provider used"
  value       = providers.aws.version
}

# Configuration Summary
output "cluster_configuration_summary" {
  description = "Summary of cluster configuration"
  value = {
    cluster_name              = local.cluster_name
    scheduler                = var.scheduler_type
    head_node_instance_type  = var.head_node_instance_type
    compute_instance_type    = var.compute_instance_type
    min_compute_nodes        = var.min_compute_nodes
    max_compute_nodes        = var.max_compute_nodes
    efa_enabled              = var.enable_efa
    hyperthreading_disabled  = var.disable_hyperthreading
    scaledown_idletime       = var.scaledown_idletime
    shared_storage_size      = var.shared_storage_size
    fsx_storage_capacity     = var.fsx_storage_capacity
    monitoring_enabled       = var.enable_cloudwatch_monitoring
    logs_enabled             = var.enable_cloudwatch_logs
    encryption_enabled       = var.enable_ebs_encryption
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after Terraform deployment"
  value = [
    "1. Install ParallelCluster CLI: pip3 install aws-parallelcluster",
    "2. Download the private key: aws s3 cp s3://${aws_s3_bucket.hpc_data_bucket.bucket}/keys/${aws_key_pair.hpc_keypair.key_name}.pem ~/.ssh/",
    "3. Set proper permissions: chmod 600 ~/.ssh/${aws_key_pair.hpc_keypair.key_name}.pem",
    "4. Create the cluster: ${local.cluster_creation_command}",
    "5. Monitor cluster creation: pcluster describe-cluster --cluster-name ${local.cluster_name}",
    "6. Connect to head node after creation: ssh -i ~/.ssh/${aws_key_pair.hpc_keypair.key_name}.pem ec2-user@<HEAD_NODE_IP>"
  ]
}