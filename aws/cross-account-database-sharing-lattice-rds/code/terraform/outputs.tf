# Outputs for cross-account database sharing with VPC Lattice and RDS

# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC containing the database and VPC Lattice resources"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "database_subnet_ids" {
  description = "IDs of the database subnets"
  value       = [aws_subnet.database_a.id, aws_subnet.database_b.id]
}

output "gateway_subnet_id" {
  description = "ID of the VPC Lattice gateway subnet"
  value       = aws_subnet.gateway.id
}

# RDS Database Outputs
output "rds_instance_id" {
  description = "ID of the RDS database instance"
  value       = aws_db_instance.main.identifier
}

output "rds_instance_arn" {
  description = "ARN of the RDS database instance"
  value       = aws_db_instance.main.arn
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS database address (hostname)"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS database port"
  value       = aws_db_instance.main.port
}

output "rds_engine" {
  description = "RDS database engine"
  value       = aws_db_instance.main.engine
}

output "rds_engine_version" {
  description = "RDS database engine version"
  value       = aws_db_instance.main.engine_version_actual
}

output "rds_db_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "rds_username" {
  description = "Master username for the database"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.database.id
}

# VPC Lattice Outputs
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.name
}

output "resource_gateway_id" {
  description = "ID of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.main.id
}

output "resource_gateway_arn" {
  description = "ARN of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.main.arn
}

output "resource_gateway_name" {
  description = "Name of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.main.name
}

output "resource_configuration_id" {
  description = "ID of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.main.id
}

output "resource_configuration_arn" {
  description = "ARN of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.main.arn
}

output "resource_configuration_name" {
  description = "Name of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.main.name
}

# IAM and Security Outputs
output "cross_account_role_arn" {
  description = "ARN of the cross-account IAM role for database access"
  value       = aws_iam_role.cross_account_database_access.arn
}

output "cross_account_role_name" {
  description = "Name of the cross-account IAM role"
  value       = aws_iam_role.cross_account_database_access.name
}

output "external_id" {
  description = "External ID for cross-account role assumption"
  value       = var.external_id
  sensitive   = true
}

# AWS RAM Outputs
output "resource_share_arn" {
  description = "ARN of the AWS RAM resource share"
  value       = aws_ram_resource_share.main.arn
}

output "resource_share_id" {
  description = "ID of the AWS RAM resource share"
  value       = aws_ram_resource_share.main.id
}

output "resource_share_name" {
  description = "Name of the AWS RAM resource share"
  value       = aws_ram_resource_share.main.name
}

output "consumer_account_id" {
  description = "AWS Account ID that can consume the shared database"
  value       = var.consumer_account_id
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice"
  value       = aws_cloudwatch_log_group.vpc_lattice.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC Lattice"
  value       = aws_cloudwatch_log_group.vpc_lattice.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.database_sharing.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.database_sharing.dashboard_name}"
}

# Secrets Manager Outputs (if password is randomly generated)
output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the database password"
  value       = var.create_random_password ? aws_secretsmanager_secret.db_password[0].arn : null
}

output "db_password_secret_name" {
  description = "Name of the Secrets Manager secret containing the database password"
  value       = var.create_random_password ? aws_secretsmanager_secret.db_password[0].name : null
}

# Connection Information for Consumer Account
output "connection_info" {
  description = "Connection information for the consumer account"
  value = {
    service_network_id             = aws_vpclattice_service_network.main.id
    resource_configuration_id      = aws_vpclattice_resource_configuration.main.id
    cross_account_role_arn        = aws_iam_role.cross_account_database_access.arn
    external_id                   = var.external_id
    database_port                 = aws_db_instance.main.port
    database_engine               = aws_db_instance.main.engine
    resource_share_arn            = aws_ram_resource_share.main.arn
  }
  sensitive = true
}

# Validation Outputs
output "resource_configuration_association_status" {
  description = "Status of the resource configuration association"
  value       = aws_vpclattice_resource_configuration_association.main.id
}

output "service_network_vpc_association_status" {
  description = "Status of the service network VPC association"
  value       = aws_vpclattice_service_network_vpc_association.main.id
}

output "ram_resource_association_status" {
  description = "Status of the RAM resource association"
  value       = aws_ram_resource_association.resource_configuration.id
}

output "ram_principal_association_status" {
  description = "Status of the RAM principal association"
  value       = aws_ram_principal_association.consumer_account.id
}

# Summary Output
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    vpc_id                     = aws_vpc.main.id
    rds_endpoint              = aws_db_instance.main.endpoint
    service_network_id        = aws_vpclattice_service_network.main.id
    resource_configuration_id = aws_vpclattice_resource_configuration.main.id
    cross_account_role_arn    = aws_iam_role.cross_account_database_access.arn
    resource_share_arn        = aws_ram_resource_share.main.arn
    consumer_account_id       = var.consumer_account_id
    dashboard_url             = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.database_sharing.dashboard_name}"
  }
}