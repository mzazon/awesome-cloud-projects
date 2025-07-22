# Outputs for Neptune Graph Database Recommendation Engine
# This file defines all output values that will be displayed after terraform apply

# ============================================================================
# Neptune Cluster Outputs
# ============================================================================

output "neptune_cluster_id" {
  description = "The Neptune cluster identifier"
  value       = aws_neptune_cluster.neptune_cluster.cluster_identifier
}

output "neptune_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the Neptune cluster"
  value       = aws_neptune_cluster.neptune_cluster.arn
}

output "neptune_cluster_endpoint" {
  description = "The Neptune cluster endpoint for write operations"
  value       = aws_neptune_cluster.neptune_cluster.endpoint
  sensitive   = false
}

output "neptune_cluster_reader_endpoint" {
  description = "The Neptune cluster reader endpoint for read operations"
  value       = aws_neptune_cluster.neptune_cluster.reader_endpoint
  sensitive   = false
}

output "neptune_cluster_port" {
  description = "The port on which Neptune accepts connections"
  value       = aws_neptune_cluster.neptune_cluster.port
}

output "neptune_cluster_resource_id" {
  description = "The Neptune cluster resource ID"
  value       = aws_neptune_cluster.neptune_cluster.cluster_resource_id
}

output "neptune_cluster_hosted_zone_id" {
  description = "The hosted zone ID of the Neptune cluster"
  value       = aws_neptune_cluster.neptune_cluster.hosted_zone_id
}

output "neptune_engine_version" {
  description = "The Neptune engine version"
  value       = aws_neptune_cluster.neptune_cluster.engine_version
}

# ============================================================================
# Neptune Instance Outputs
# ============================================================================

output "neptune_primary_instance_id" {
  description = "The Neptune primary instance identifier"
  value       = aws_neptune_cluster_instance.neptune_primary.identifier
}

output "neptune_primary_instance_arn" {
  description = "The Amazon Resource Name (ARN) of the Neptune primary instance"
  value       = aws_neptune_cluster_instance.neptune_primary.arn
}

output "neptune_primary_instance_endpoint" {
  description = "The Neptune primary instance endpoint"
  value       = aws_neptune_cluster_instance.neptune_primary.endpoint
}

output "neptune_replica_instance_ids" {
  description = "List of Neptune replica instance identifiers"
  value       = aws_neptune_cluster_instance.neptune_replicas[*].identifier
}

output "neptune_replica_instance_endpoints" {
  description = "List of Neptune replica instance endpoints"
  value       = aws_neptune_cluster_instance.neptune_replicas[*].endpoint
}

output "neptune_instance_class" {
  description = "The Neptune instance class"
  value       = var.neptune_instance_class
}

# ============================================================================
# VPC and Networking Outputs
# ============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.neptune_vpc.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.neptune_vpc.cidr_block
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.neptune_igw.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs where Neptune is deployed"
  value       = aws_subnet.neptune_private_subnets[*].id
}

output "private_subnet_cidr_blocks" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.neptune_private_subnets[*].cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs where EC2 client is deployed"
  value       = aws_subnet.neptune_public_subnets[*].id
}

output "public_subnet_cidr_blocks" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.neptune_public_subnets[*].cidr_block
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.availability_zones
}

# ============================================================================
# Security Group Outputs
# ============================================================================

output "neptune_security_group_id" {
  description = "The ID of the Neptune security group"
  value       = aws_security_group.neptune_sg.id
}

output "neptune_security_group_arn" {
  description = "The ARN of the Neptune security group"
  value       = aws_security_group.neptune_sg.arn
}

output "ec2_client_security_group_id" {
  description = "The ID of the EC2 client security group"
  value       = aws_security_group.ec2_client_sg.id
}

output "ec2_client_security_group_arn" {
  description = "The ARN of the EC2 client security group"
  value       = aws_security_group.ec2_client_sg.arn
}

# ============================================================================
# EC2 Client Instance Outputs
# ============================================================================

output "ec2_instance_id" {
  description = "The ID of the EC2 client instance"
  value       = aws_instance.neptune_client.id
}

output "ec2_instance_arn" {
  description = "The ARN of the EC2 client instance"
  value       = aws_instance.neptune_client.arn
}

output "ec2_instance_public_ip" {
  description = "The public IP address of the EC2 client instance"
  value       = aws_instance.neptune_client.public_ip
  sensitive   = false
}

output "ec2_instance_private_ip" {
  description = "The private IP address of the EC2 client instance"
  value       = aws_instance.neptune_client.private_ip
}

output "ec2_instance_public_dns" {
  description = "The public DNS name of the EC2 client instance"
  value       = aws_instance.neptune_client.public_dns
}

output "ec2_instance_private_dns" {
  description = "The private DNS name of the EC2 client instance"
  value       = aws_instance.neptune_client.private_dns
}

output "ec2_instance_type" {
  description = "The type of the EC2 instance"
  value       = aws_instance.neptune_client.instance_type
}

output "ec2_key_pair_name" {
  description = "The name of the EC2 key pair"
  value       = aws_key_pair.ec2_key_pair.key_name
}

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "s3_bucket_name" {
  description = "The name of the S3 bucket containing sample data"
  value       = aws_s3_bucket.sample_data_bucket.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.sample_data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.sample_data_bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "The regional domain name of the S3 bucket"
  value       = aws_s3_bucket.sample_data_bucket.bucket_regional_domain_name
}

output "sample_data_files" {
  description = "List of sample data files uploaded to S3"
  value = [
    aws_s3_object.sample_users.key,
    aws_s3_object.sample_products.key,
    aws_s3_object.sample_purchases.key
  ]
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "ec2_iam_role_name" {
  description = "The name of the IAM role attached to the EC2 instance"
  value       = aws_iam_role.ec2_neptune_client_role.name
}

output "ec2_iam_role_arn" {
  description = "The ARN of the IAM role attached to the EC2 instance"
  value       = aws_iam_role.ec2_neptune_client_role.arn
}

output "ec2_instance_profile_name" {
  description = "The name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_neptune_client_profile.name
}

output "ec2_instance_profile_arn" {
  description = "The ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_neptune_client_profile.arn
}

# ============================================================================
# Connection Information Outputs
# ============================================================================

output "gremlin_websocket_endpoint" {
  description = "The WebSocket endpoint for Gremlin connections to Neptune"
  value       = "wss://${aws_neptune_cluster.neptune_cluster.endpoint}:${aws_neptune_cluster.neptune_cluster.port}/gremlin"
  sensitive   = false
}

output "sparql_endpoint" {
  description = "The HTTP endpoint for SPARQL queries to Neptune"
  value       = "https://${aws_neptune_cluster.neptune_cluster.endpoint}:${aws_neptune_cluster.neptune_cluster.port}/sparql"
  sensitive   = false
}

output "neptune_bulk_loader_endpoint" {
  description = "The HTTP endpoint for Neptune bulk loader"
  value       = "https://${aws_neptune_cluster.neptune_cluster.endpoint}:${aws_neptune_cluster.neptune_cluster.port}/loader"
  sensitive   = false
}

# ============================================================================
# SSH Connection Information
# ============================================================================

output "ssh_connection_command" {
  description = "SSH command to connect to the EC2 client instance"
  value       = var.environment != "prod" ? "ssh -i ${local.key_pair_name}.pem ec2-user@${aws_instance.neptune_client.public_ip}" : "Use AWS Systems Manager Session Manager to connect to the instance"
  sensitive   = false
}

output "ssh_tunnel_command" {
  description = "SSH tunnel command for accessing Neptune through the EC2 instance"
  value = var.environment != "prod" ? "ssh -i ${local.key_pair_name}.pem -L 8182:${aws_neptune_cluster.neptune_cluster.endpoint}:8182 ec2-user@${aws_instance.neptune_client.public_ip}" : "Use AWS Systems Manager for secure access"
  sensitive = false
}

# ============================================================================
# CloudWatch Log Groups
# ============================================================================

output "cloudwatch_log_group_names" {
  description = "List of CloudWatch log group names for Neptune"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.neptune_audit_log[*].name : []
}

output "cloudwatch_log_group_arns" {
  description = "List of CloudWatch log group ARNs for Neptune"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.neptune_audit_log[*].arn : []
}

# ============================================================================
# Cost and Resource Information
# ============================================================================

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    neptune_cluster = "~$${(var.neptune_replica_count + 1) * (var.neptune_instance_class == "db.r5.large" ? 168 : 336)}"
    ec2_instance   = "~$${var.ec2_instance_type == "t3.medium" ? 30 : 60}"
    storage        = "~$10-50 (depends on usage)"
    data_transfer  = "~$5-20 (depends on usage)"
    total          = "~$${(var.neptune_replica_count + 1) * (var.neptune_instance_class == "db.r5.large" ? 168 : 336) + (var.ec2_instance_type == "t3.medium" ? 30 : 60) + 35}-${(var.neptune_replica_count + 1) * (var.neptune_instance_class == "db.r5.large" ? 168 : 336) + (var.ec2_instance_type == "t3.medium" ? 30 : 60) + 115}"
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    neptune_cluster   = "${aws_neptune_cluster.neptune_cluster.cluster_identifier} (${var.neptune_replica_count + 1} instances)"
    vpc              = aws_vpc.neptune_vpc.id
    subnets          = "${length(aws_subnet.neptune_private_subnets)} private, ${length(aws_subnet.neptune_public_subnets)} public"
    security_groups  = "2 (Neptune + EC2)"
    ec2_instance     = "${aws_instance.neptune_client.instance_type} in ${aws_instance.neptune_client.availability_zone}"
    s3_bucket        = aws_s3_bucket.sample_data_bucket.id
    key_pair         = aws_key_pair.ec2_key_pair.key_name
  }
}

# ============================================================================
# Quick Start Information
# ============================================================================

output "quick_start_guide" {
  description = "Quick start commands and information"
  value = {
    step_1 = "Connect to EC2: ${var.environment != "prod" ? "ssh -i ${local.key_pair_name}.pem ec2-user@${aws_instance.neptune_client.public_ip}" : "Use AWS Systems Manager"}"
    step_2 = "Load environment: source /home/ec2-user/neptune-config/neptune-env.sh"
    step_3 = "Test connection: python3 /home/ec2-user/neptune-config/test-connection.py"
    step_4 = "Neptune endpoints available as environment variables: NEPTUNE_ENDPOINT, NEPTUNE_READ_ENDPOINT"
    step_5 = "Sample data available in S3: ${aws_s3_bucket.sample_data_bucket.id}"
  }
}

# ============================================================================
# Troubleshooting Information
# ============================================================================

output "troubleshooting_info" {
  description = "Troubleshooting information and common issues"
  value = {
    neptune_not_accessible = "Ensure EC2 instance is in the same VPC and security groups allow port 8182"
    connection_timeout     = "Check VPC routing tables and security group rules"
    authentication_issues  = "Verify IAM role has Neptune access permissions"
    data_loading_fails    = "Check S3 bucket permissions and Neptune bulk loader endpoint"
    logs_location         = var.enable_cloudwatch_logs ? "CloudWatch logs: /aws/neptune/${local.cluster_identifier}/audit" : "CloudWatch logs disabled"
  }
}