# VPC Lattice Service Network outputs
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

output "service_network_auth_type" {
  description = "Authentication type of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.auth_type
}

# VPC Association outputs
output "vpc_association_id" {
  description = "ID of the VPC association with service network"
  value       = aws_vpclattice_service_network_vpc_association.main.id
}

output "vpc_association_arn" {
  description = "ARN of the VPC association with service network"
  value       = aws_vpclattice_service_network_vpc_association.main.arn
}

output "associated_vpc_id" {
  description = "ID of the VPC associated with the service network"
  value       = aws_vpclattice_service_network_vpc_association.main.vpc_identifier
}

# RDS Database outputs
output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "rds_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "rds_database_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "rds_username" {
  description = "Master username for the database"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "rds_engine" {
  description = "Database engine"
  value       = aws_db_instance.main.engine
}

output "rds_engine_version" {
  description = "Database engine version"
  value       = aws_db_instance.main.engine_version
}

output "rds_security_group_id" {
  description = "Security group ID for RDS instance"
  value       = aws_security_group.rds.id
}

output "rds_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.main.name
}

# RDS Master User Secret (when managed by AWS)
output "rds_master_user_secret_arn" {
  description = "ARN of the master user secret (when managed by AWS Secrets Manager)"
  value       = var.db_manage_master_user_password ? aws_db_instance.main.master_user_secret[0].secret_arn : null
}

# Resource Configuration outputs
output "resource_configuration_id" {
  description = "ID of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.database.id
}

output "resource_configuration_arn" {
  description = "ARN of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.database.arn
}

output "resource_configuration_name" {
  description = "Name of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.database.name
}

output "resource_configuration_association_id" {
  description = "ID of the resource configuration association"
  value       = aws_vpclattice_resource_configuration_association.database.id
}

output "resource_configuration_association_arn" {
  description = "ARN of the resource configuration association"
  value       = aws_vpclattice_resource_configuration_association.database.arn
}

# AWS RAM outputs
output "ram_resource_share_arn" {
  description = "ARN of the RAM resource share"
  value       = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.main[0].arn : null
}

output "ram_resource_share_id" {
  description = "ID of the RAM resource share"
  value       = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.main[0].id : null
}

output "ram_resource_share_name" {
  description = "Name of the RAM resource share"
  value       = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.main[0].name : null
}

output "ram_resource_share_status" {
  description = "Status of the RAM resource share"
  value       = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.main[0].status : null
}

# IAM Role outputs
output "team_role_arns" {
  description = "ARNs of the team IAM roles"
  value = {
    for i, team in var.tenant_teams : team => aws_iam_role.team_roles[i].arn
  }
}

output "team_role_names" {
  description = "Names of the team IAM roles"
  value = {
    for i, team in var.tenant_teams : team => aws_iam_role.team_roles[i].name
  }
}

output "vpc_lattice_service_role_arn" {
  description = "ARN of the VPC Lattice service role"
  value       = aws_iam_role.vpc_lattice_service_role.arn
}

output "vpc_lattice_service_role_name" {
  description = "Name of the VPC Lattice service role"
  value       = aws_iam_role.vpc_lattice_service_role.name
}

# Authentication Policy outputs
output "auth_policy_resource_identifier" {
  description = "Resource identifier for the authentication policy"
  value       = aws_vpclattice_auth_policy.main.resource_identifier
}

output "allowed_teams" {
  description = "List of teams allowed access through the authentication policy"
  value       = var.tenant_teams
}

output "allowed_ip_ranges" {
  description = "List of IP ranges allowed access through the authentication policy"
  value       = var.allowed_ip_ranges
}

# CloudTrail outputs
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
}

output "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "S3 bucket ARN for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].arn : null
}

# General information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Deployment information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    service_network = {
      name      = aws_vpclattice_service_network.main.name
      id        = aws_vpclattice_service_network.main.id
      auth_type = aws_vpclattice_service_network.main.auth_type
    }
    database = {
      identifier = aws_db_instance.main.identifier
      endpoint   = aws_db_instance.main.endpoint
      engine     = aws_db_instance.main.engine
      port       = aws_db_instance.main.port
    }
    resource_share = {
      enabled = length(var.ram_share_principals) > 0
      name    = length(var.ram_share_principals) > 0 ? aws_ram_resource_share.main[0].name : null
    }
    team_roles = [
      for i, team in var.tenant_teams : {
        team = team
        role_name = aws_iam_role.team_roles[i].name
        role_arn  = aws_iam_role.team_roles[i].arn
      }
    ]
    cloudtrail = {
      enabled     = var.enable_cloudtrail
      name        = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
      bucket_name = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
    }
  }
}

# Connection information for applications
output "connection_info" {
  description = "Information needed for applications to connect to shared resources"
  value = {
    service_network_id = aws_vpclattice_service_network.main.id
    service_network_arn = aws_vpclattice_service_network.main.arn
    database_endpoint = aws_db_instance.main.endpoint
    database_port = aws_db_instance.main.port
    resource_configuration_name = aws_vpclattice_resource_configuration.database.name
    team_roles = {
      for i, team in var.tenant_teams : team => {
        role_arn = aws_iam_role.team_roles[i].arn
        external_id = "${team}-Access"
      }
    }
  }
  sensitive = false
}