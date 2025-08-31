# Output values for the secure database access with VPC Lattice Resource Gateway

#######################
# Database Outputs
#######################

output "rds_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "rds_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "database_username" {
  description = "The master username for the database"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "database_password" {
  description = "The master password for the database"
  value       = var.db_password != "" ? var.db_password : random_password.db_password[0].result
  sensitive   = true
}

#######################
# VPC Lattice Outputs
#######################

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "resource_gateway_arn" {
  description = "ARN of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.main.arn
}

output "resource_gateway_id" {
  description = "ID of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.main.id
}

output "resource_configuration_arn" {
  description = "ARN of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.main.arn
}

output "resource_configuration_id" {
  description = "ID of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.main.id
}

output "lattice_dns_name" {
  description = "VPC Lattice generated DNS name for database access"
  value       = aws_vpclattice_resource_configuration.main.dns_entry[0].domain_name
  sensitive   = true
}

output "lattice_hosted_zone_id" {
  description = "VPC Lattice generated hosted zone ID"
  value       = aws_vpclattice_resource_configuration.main.dns_entry[0].hosted_zone_id
}

#######################
# Security Group Outputs
#######################

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "resource_gateway_security_group_id" {
  description = "ID of the resource gateway security group"
  value       = aws_security_group.resource_gateway.id
}

#######################
# AWS RAM Outputs
#######################

output "ram_resource_share_arn" {
  description = "ARN of the AWS RAM resource share"
  value       = aws_ram_resource_share.main.arn
}

output "ram_resource_share_id" {
  description = "ID of the AWS RAM resource share"
  value       = aws_ram_resource_share.main.id
}

output "ram_invitation_url" {
  description = "URL for the consumer account to accept the RAM invitation"
  value       = "https://console.aws.amazon.com/ram/home?region=${data.aws_region.current.name}#IncomingInvitations"
}

#######################
# Access Logs Outputs
#######################

output "access_logs_bucket_name" {
  description = "Name of the S3 bucket for VPC Lattice access logs"
  value       = var.enable_access_logs && var.access_logs_s3_bucket == "" ? aws_s3_bucket.access_logs[0].id : var.access_logs_s3_bucket
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 bucket for VPC Lattice access logs"
  value       = var.enable_access_logs && var.access_logs_s3_bucket == "" ? aws_s3_bucket.access_logs[0].arn : ""
}

#######################
# Connection Information
#######################

output "connection_instructions" {
  description = "Instructions for connecting to the shared database"
  value = {
    from_owner_account = {
      description = "Connect directly using RDS endpoint"
      host        = aws_db_instance.main.endpoint
      port        = aws_db_instance.main.port
      command     = "mysql -h ${aws_db_instance.main.endpoint} -P ${aws_db_instance.main.port} -u ${aws_db_instance.main.username} -p"
    }
    from_consumer_account = {
      description = "Connect through VPC Lattice Resource Gateway"
      host        = aws_vpclattice_resource_configuration.main.dns_entry[0].domain_name
      port        = local.actual_db_port
      command     = "mysql -h ${aws_vpclattice_resource_configuration.main.dns_entry[0].domain_name} -P ${local.actual_db_port} -u ${aws_db_instance.main.username} -p"
      note        = "Consumer account must accept RAM invitation and associate their VPC with the service network"
    }
  }
  sensitive = true
}

#######################
# Resource Inventory
#######################

output "resource_inventory" {
  description = "Complete inventory of created resources"
  value = {
    database = {
      rds_instance_id        = aws_db_instance.main.id
      rds_endpoint          = aws_db_instance.main.endpoint
      db_subnet_group_name  = aws_db_subnet_group.main.name
    }
    vpc_lattice = {
      service_network_id           = aws_vpclattice_service_network.main.id
      resource_gateway_id          = aws_vpclattice_resource_gateway.main.id
      resource_configuration_id    = aws_vpclattice_resource_configuration.main.id
      vpc_association_id          = aws_vpclattice_service_network_vpc_association.main.id
      resource_association_id     = aws_vpclattice_service_network_resource_association.main.id
    }
    security = {
      rds_security_group_id              = aws_security_group.rds.id
      resource_gateway_security_group_id = aws_security_group.resource_gateway.id
      iam_auth_policy_applied           = true
    }
    sharing = {
      ram_resource_share_id          = aws_ram_resource_share.main.id
      ram_resource_association_id    = aws_ram_resource_association.resource_config.id
      ram_principal_association_id   = aws_ram_principal_association.consumer_account.id
    }
    monitoring = {
      enhanced_monitoring_enabled    = var.enable_enhanced_monitoring
      performance_insights_enabled  = var.enable_performance_insights
      access_logs_enabled           = var.enable_access_logs
      access_logs_bucket            = var.enable_access_logs && var.access_logs_s3_bucket == "" ? aws_s3_bucket.access_logs[0].id : var.access_logs_s3_bucket
    }
  }
}

#######################
# Cost Estimation
#######################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    rds_instance = {
      description = "RDS ${var.db_instance_class} instance"
      estimated_cost = var.db_instance_class == "db.t3.micro" ? 15.00 : 50.00
    }
    vpc_lattice = {
      service_network = {
        description = "VPC Lattice Service Network (per hour)"
        estimated_cost = 0.025 * 24 * 30  # $0.025/hour
      }
      resource_gateway = {
        description = "VPC Lattice Resource Gateway (per hour)"
        estimated_cost = 0.036 * 24 * 30  # $0.036/hour
      }
      data_processing = {
        description = "Data processing (per GB, estimate 10GB/month)"
        estimated_cost = 0.0125 * 10
      }
    }
    storage = {
      rds_storage = {
        description = "RDS storage (${var.db_allocated_storage}GB GP3)"
        estimated_cost = var.db_allocated_storage * 0.115
      }
      s3_logs = {
        description = "S3 storage for access logs (estimate 1GB/month)"
        estimated_cost = var.enable_access_logs ? 0.023 : 0
      }
    }
    total_estimated = {
      description = "Total estimated monthly cost"
      estimated_cost = (var.db_instance_class == "db.t3.micro" ? 15.00 : 50.00) + 
                      (0.025 * 24 * 30) + 
                      (0.036 * 24 * 30) + 
                      (0.0125 * 10) + 
                      (var.db_allocated_storage * 0.115) + 
                      (var.enable_access_logs ? 0.023 : 0)
    }
    note = "Costs are estimates and may vary based on actual usage, region, and AWS pricing changes"
  }
}

#######################
# Next Steps
#######################

output "next_steps" {
  description = "Next steps to complete the setup"
  value = {
    step_1 = {
      description = "Consumer account accepts RAM invitation"
      action      = "Navigate to AWS RAM console in consumer account and accept the invitation"
      url         = "https://console.aws.amazon.com/ram/home?region=${data.aws_region.current.name}#IncomingInvitations"
    }
    step_2 = {
      description = "Associate consumer VPC with service network"
      action      = "Create VPC association in consumer account using Terraform or CLI"
      cli_example = "aws vpc-lattice create-service-network-vpc-association --service-network-identifier ${aws_vpclattice_service_network.main.id} --vpc-identifier <CONSUMER_VPC_ID>"
    }
    step_3 = {
      description = "Test database connectivity"
      action      = "Connect to database from consumer account using VPC Lattice DNS name"
      connection_string = "mysql -h ${aws_vpclattice_resource_configuration.main.dns_entry[0].domain_name} -P ${local.actual_db_port} -u ${aws_db_instance.main.username} -p"
    }
    step_4 = {
      description = "Monitor access logs"
      action      = var.enable_access_logs ? "Review VPC Lattice access logs in S3 bucket" : "Enable access logs for monitoring"
    }
  }
}