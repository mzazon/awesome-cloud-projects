# =============================================================================
# AWS Batch Multi-Node Parallel Jobs - Outputs
# Essential resource identifiers and connection information
# =============================================================================

# -----------------------------------------------------------------------------
# Network Infrastructure Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT gateways"
  value       = aws_nat_gateway.main[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "batch_compute_security_group_id" {
  description = "ID of the security group for Batch compute nodes"
  value       = aws_security_group.batch_compute.id
}

output "efs_security_group_id" {
  description = "ID of the security group for EFS"
  value       = aws_security_group.efs.id
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

# -----------------------------------------------------------------------------
# Storage Outputs
# -----------------------------------------------------------------------------

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.shared_storage.id
}

output "efs_file_system_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.shared_storage.dns_name
}

output "efs_mount_target_ids" {
  description = "List of IDs of the EFS mount targets"
  value       = aws_efs_mount_target.shared_storage[*].id
}

output "efs_mount_target_dns_names" {
  description = "List of DNS names of the EFS mount targets"
  value       = aws_efs_mount_target.shared_storage[*].dns_name
}

# -----------------------------------------------------------------------------
# Container Registry Outputs
# -----------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.batch_app.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.batch_app.name
}

output "ecr_repository_registry_id" {
  description = "Registry ID of the ECR repository"
  value       = aws_ecr_repository.batch_app.registry_id
}

# -----------------------------------------------------------------------------
# IAM Role Outputs
# -----------------------------------------------------------------------------

output "batch_service_role_arn" {
  description = "ARN of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.arn
}

output "batch_service_role_name" {
  description = "Name of the AWS Batch service role"
  value       = aws_iam_role.batch_service_role.name
}

output "ecs_instance_role_arn" {
  description = "ARN of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "ecs_instance_role_name" {
  description = "Name of the ECS instance role"
  value       = aws_iam_role.ecs_instance_role.name
}

output "ecs_instance_profile_arn" {
  description = "ARN of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

output "ecs_instance_profile_name" {
  description = "Name of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.name
}

output "job_execution_role_arn" {
  description = "ARN of the job execution role"
  value       = aws_iam_role.job_execution_role.arn
}

output "job_execution_role_name" {
  description = "Name of the job execution role"
  value       = aws_iam_role.job_execution_role.name
}

# -----------------------------------------------------------------------------
# Placement Group Outputs
# -----------------------------------------------------------------------------

output "placement_group_id" {
  description = "ID of the placement group for enhanced networking"
  value       = aws_placement_group.hpc_cluster.id
}

output "placement_group_name" {
  description = "Name of the placement group for enhanced networking"
  value       = aws_placement_group.hpc_cluster.name
}

# -----------------------------------------------------------------------------
# AWS Batch Outputs
# -----------------------------------------------------------------------------

output "batch_compute_environment_arn" {
  description = "ARN of the Batch compute environment"
  value       = aws_batch_compute_environment.multi_node.arn
}

output "batch_compute_environment_name" {
  description = "Name of the Batch compute environment"
  value       = aws_batch_compute_environment.multi_node.compute_environment_name
}

output "batch_job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.scientific_queue.arn
}

output "batch_job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.scientific_queue.name
}

output "batch_job_definition_arn" {
  description = "ARN of the basic MPI job definition"
  value       = aws_batch_job_definition.mpi_job.arn
}

output "batch_job_definition_name" {
  description = "Name of the basic MPI job definition"
  value       = aws_batch_job_definition.mpi_job.name
}

output "batch_parameterized_job_definition_arn" {
  description = "ARN of the parameterized MPI job definition"
  value       = aws_batch_job_definition.parameterized_mpi_job.arn
}

output "batch_parameterized_job_definition_name" {
  description = "Name of the parameterized MPI job definition"
  value       = aws_batch_job_definition.parameterized_mpi_job.name
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Batch jobs"
  value       = aws_cloudwatch_log_group.batch_jobs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.batch_monitoring.dashboard_name}"
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for failed jobs"
  value       = aws_cloudwatch_metric_alarm.failed_jobs.alarm_name
}

# -----------------------------------------------------------------------------
# VPC Endpoints Outputs (Conditional)
# -----------------------------------------------------------------------------

output "vpc_endpoint_ecr_api_id" {
  description = "ID of the ECR API VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ID of the ECR Docker registry VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

# -----------------------------------------------------------------------------
# Resource Information Outputs
# -----------------------------------------------------------------------------

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

# -----------------------------------------------------------------------------
# Convenience Outputs for Users
# -----------------------------------------------------------------------------

output "job_submission_command_basic" {
  description = "AWS CLI command to submit a basic multi-node job"
  value = join(" ", [
    "aws batch submit-job",
    "--job-name \"scientific-job-$(date +%s)\"",
    "--job-queue ${aws_batch_job_queue.scientific_queue.name}",
    "--job-definition ${aws_batch_job_definition.mpi_job.name}"
  ])
}

output "job_submission_command_parameterized" {
  description = "AWS CLI command to submit a parameterized multi-node job"
  value = join(" ", [
    "aws batch submit-job",
    "--job-name \"parameterized-job-$(date +%s)\"",
    "--job-queue ${aws_batch_job_queue.scientific_queue.name}",
    "--job-definition ${aws_batch_job_definition.parameterized_mpi_job.name}",
    "--parameters inputDataPath=/mnt/efs/input,outputDataPath=/mnt/efs/output,computeIntensity=high"
  ])
}

output "ecr_login_command" {
  description = "AWS CLI command to authenticate Docker with ECR"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_app.repository_url}"
}

output "docker_build_and_push_commands" {
  description = "Commands to build and push Docker image to ECR"
  value = [
    "# Build the Docker image",
    "docker build -t ${aws_ecr_repository.batch_app.name} .",
    "",
    "# Tag the image for ECR",
    "docker tag ${aws_ecr_repository.batch_app.name}:latest ${aws_ecr_repository.batch_app.repository_url}:latest",
    "",
    "# Login to ECR",
    "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.batch_app.repository_url}",
    "",
    "# Push the image",
    "docker push ${aws_ecr_repository.batch_app.repository_url}:latest"
  ]
}

# -----------------------------------------------------------------------------
# Cost Estimation Outputs
# -----------------------------------------------------------------------------

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for key resources (in USD, excluding compute)"
  value = {
    "vpc_endpoints" = var.enable_vpc_endpoints ? "~$45 (3 interface endpoints)" : "$0 (disabled)"
    "nat_gateway"   = var.single_nat_gateway ? "~$45 (1 NAT gateway)" : "~$135 (3 NAT gateways)"
    "efs_storage"   = "~$0.30 per GB stored + $6/month base (provisioned throughput 100 MiB/s)"
    "ecr_storage"   = "~$0.10 per GB stored"
    "cloudwatch"    = "~$5-10 (logs and metrics)"
    "compute_idle"  = "$0 (Batch scales to zero when no jobs)"
    "note"          = "Actual costs depend on usage patterns, data transfer, and compute utilization"
  }
}

# -----------------------------------------------------------------------------
# Quick Start Information
# -----------------------------------------------------------------------------

output "quick_start_guide" {
  description = "Quick start steps for using the infrastructure"
  value = [
    "1. Build and push your MPI container to ECR:",
    "   ${aws_ecr_repository.batch_app.repository_url}",
    "",
    "2. Submit a test job using:",
    "   aws batch submit-job --job-name test-job --job-queue ${aws_batch_job_queue.scientific_queue.name} --job-definition ${aws_batch_job_definition.mpi_job.name}",
    "",
    "3. Monitor jobs in AWS Console:",
    "   - Batch: https://${data.aws_region.current.name}.console.aws.amazon.com/batch/",
    "   - CloudWatch: ${local.cloudwatch_console_url}",
    "",
    "4. Access shared storage via EFS:",
    "   - File System ID: ${aws_efs_file_system.shared_storage.id}",
    "   - DNS Name: ${aws_efs_file_system.shared_storage.dns_name}",
    "",
    "5. View logs in CloudWatch:",
    "   - Log Group: ${aws_cloudwatch_log_group.batch_jobs.name}"
  ]
}

# Local value for CloudWatch console URL
locals {
  cloudwatch_console_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.batch_monitoring.dashboard_name}"
}

# -----------------------------------------------------------------------------
# Security and Compliance Information
# -----------------------------------------------------------------------------

output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    "vpc_isolation"           = "All compute resources in private subnets"
    "efs_encryption"          = "EFS encrypted at rest"
    "efs_transit_encryption"  = "EFS encrypted in transit"
    "ecr_vulnerability_scan"  = "Container image vulnerability scanning enabled"
    "iam_least_privilege"     = "IAM roles follow least privilege principle"
    "security_groups"         = "Restrictive security groups for inter-service communication"
    "placement_group"         = "Cluster placement group for enhanced networking performance"
  }
}

# -----------------------------------------------------------------------------
# Troubleshooting Information
# -----------------------------------------------------------------------------

output "troubleshooting_resources" {
  description = "Key resources for troubleshooting"
  value = {
    "compute_environment_status" = "aws batch describe-compute-environments --compute-environments ${aws_batch_compute_environment.multi_node.compute_environment_name}"
    "job_queue_status"          = "aws batch describe-job-queues --job-queues ${aws_batch_job_queue.scientific_queue.name}"
    "running_jobs"              = "aws batch list-jobs --job-queue ${aws_batch_job_queue.scientific_queue.name} --job-status RUNNING"
    "failed_jobs"               = "aws batch list-jobs --job-queue ${aws_batch_job_queue.scientific_queue.name} --job-status FAILED"
    "job_logs"                  = "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.batch_jobs.name}"
    "ecs_instances"             = "aws ec2 describe-instances --filters 'Name=tag:aws:batch:compute-environment,Values=${aws_batch_compute_environment.multi_node.compute_environment_name}'"
  }
}