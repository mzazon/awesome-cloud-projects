# Outputs for AWS Database Migration Service Infrastructure
# This file defines all outputs that provide useful information after deployment

# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC created for the migration"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "subnet_ids" {
  description = "IDs of the subnets created for the migration"
  value       = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}

# DMS Outputs
output "dms_replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_id
}

output "dms_replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "dms_replication_instance_endpoint" {
  description = "Endpoint of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_private_ips
}

output "dms_subnet_group_id" {
  description = "ID of the DMS subnet group"
  value       = aws_dms_replication_subnet_group.main.id
}

output "dms_source_endpoint_id" {
  description = "ID of the DMS source endpoint"
  value       = aws_dms_endpoint.source.endpoint_id
}

output "dms_source_endpoint_arn" {
  description = "ARN of the DMS source endpoint"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "dms_target_endpoint_id" {
  description = "ID of the DMS target endpoint"
  value       = aws_dms_endpoint.target.endpoint_id
}

output "dms_target_endpoint_arn" {
  description = "ARN of the DMS target endpoint"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "dms_replication_task_id" {
  description = "ID of the DMS replication task"
  value       = aws_dms_replication_task.main.replication_task_id
}

output "dms_replication_task_arn" {
  description = "ARN of the DMS replication task"
  value       = aws_dms_replication_task.main.replication_task_arn
}

# RDS Outputs
output "rds_instance_id" {
  description = "ID of the RDS target database instance"
  value       = aws_db_instance.target.id
}

output "rds_instance_arn" {
  description = "ARN of the RDS target database instance"
  value       = aws_db_instance.target.arn
}

output "rds_instance_endpoint" {
  description = "Endpoint of the RDS target database instance"
  value       = aws_db_instance.target.endpoint
}

output "rds_instance_address" {
  description = "Address of the RDS target database instance"
  value       = aws_db_instance.target.address
}

output "rds_instance_port" {
  description = "Port of the RDS target database instance"
  value       = aws_db_instance.target.port
}

output "rds_database_name" {
  description = "Name of the RDS target database"
  value       = aws_db_instance.target.db_name
}

output "rds_username" {
  description = "Master username for the RDS target database"
  value       = aws_db_instance.target.username
}

output "rds_subnet_group_name" {
  description = "Name of the RDS subnet group"
  value       = aws_db_subnet_group.main.name
}

# Security Group Outputs
output "dms_security_group_id" {
  description = "ID of the DMS security group"
  value       = aws_security_group.dms.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# IAM Role Outputs
output "dms_vpc_role_arn" {
  description = "ARN of the DMS VPC role"
  value       = aws_iam_role.dms_vpc_role.arn
}

output "dms_cloudwatch_logs_role_arn" {
  description = "ARN of the DMS CloudWatch logs role"
  value       = aws_iam_role.dms_cloudwatch_logs_role.arn
}

output "dms_access_for_endpoint_role_arn" {
  description = "ARN of the DMS access for endpoint role"
  value       = aws_iam_role.dms_access_for_endpoint.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DMS"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DMS"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms_logs[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for DMS monitoring"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.dms_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for DMS monitoring"
  value       = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.dms_monitoring[0].dashboard_name}" : null
}

# Connection Information
output "connection_info" {
  description = "Connection information for databases and DMS components"
  value = {
    source_database = {
      engine   = var.source_db_engine
      host     = var.source_db_host
      port     = var.source_db_port
      database = var.source_db_name
      username = var.source_db_username
    }
    target_database = {
      engine   = aws_db_instance.target.engine
      host     = aws_db_instance.target.address
      port     = aws_db_instance.target.port
      database = aws_db_instance.target.db_name
      username = aws_db_instance.target.username
    }
    dms_replication_instance = {
      id       = aws_dms_replication_instance.main.replication_instance_id
      class    = aws_dms_replication_instance.main.replication_instance_class
      multi_az = aws_dms_replication_instance.main.multi_az
    }
  }
}

# Migration Task Configuration
output "migration_task_info" {
  description = "Information about the migration task configuration"
  value = {
    task_id       = aws_dms_replication_task.main.replication_task_id
    migration_type = var.migration_type
    source_endpoint = aws_dms_endpoint.source.endpoint_id
    target_endpoint = aws_dms_endpoint.target.endpoint_id
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and managing the migration"
  value = {
    dms_console = "https://${var.aws_region}.console.aws.amazon.com/dms/v2/home?region=${var.aws_region}#replicationInstances"
    rds_console = "https://${var.aws_region}.console.aws.amazon.com/rds/home?region=${var.aws_region}#database:id=${aws_db_instance.target.id}"
    cloudwatch_logs = var.enable_cloudwatch_logs ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.dms_logs[0].name, "/", "$252F")}" : null
    cloudwatch_dashboard = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.dms_monitoring[0].dashboard_name}" : null
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    message = "Cost estimation varies by usage. Key cost factors:"
    dms_replication_instance = "DMS ${var.dms_replication_instance_class} instance"
    rds_instance = "RDS ${var.rds_instance_class} instance"
    storage_costs = "DMS storage: ${var.dms_allocated_storage}GB, RDS storage: ${var.rds_allocated_storage}GB"
    note = "Review AWS pricing calculator for detailed cost estimates"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for completing the migration setup"
  value = {
    step_1 = "Update source database connection details in variables"
    step_2 = "Configure table mappings and task settings as needed"
    step_3 = "Test endpoint connectivity using AWS CLI or console"
    step_4 = "Start the DMS replication task when ready"
    step_5 = "Monitor migration progress via CloudWatch dashboard"
    step_6 = "Use AWS Schema Conversion Tool for schema conversion"
    aws_cli_test = "aws dms test-connection --replication-instance-arn ${aws_dms_replication_instance.main.replication_instance_arn} --endpoint-arn ${aws_dms_endpoint.source.endpoint_arn}"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the migration setup"
  value = {
    vpc_security = "Consider using private subnets for production deployments"
    database_security = "Enable encryption at rest and in transit"
    access_control = "Implement least privilege IAM policies"
    monitoring = "Enable VPC Flow Logs and CloudTrail for audit logging"
    secrets_management = "Use AWS Secrets Manager for database credentials"
    network_security = "Restrict security group rules to minimum required access"
  }
}