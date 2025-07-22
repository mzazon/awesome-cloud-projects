# Outputs for Hybrid Identity Management with AWS Directory Service

#================================================================================
# NETWORKING OUTPUTS
#================================================================================

output "vpc_id" {
  description = "ID of the VPC created for hybrid identity infrastructure"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IPs of the NAT gateways"
  value       = aws_eip.nat[*].public_ip
}

#================================================================================
# DIRECTORY SERVICE OUTPUTS
#================================================================================

output "directory_id" {
  description = "ID of the AWS Managed Microsoft AD directory"
  value       = aws_directory_service_directory.main.id
}

output "directory_name" {
  description = "Fully qualified domain name of the directory"
  value       = aws_directory_service_directory.main.name
}

output "directory_short_name" {
  description = "Short name of the directory"
  value       = aws_directory_service_directory.main.short_name
}

output "directory_dns_ip_addresses" {
  description = "DNS IP addresses of the directory service"
  value       = aws_directory_service_directory.main.dns_ip_addresses
  sensitive   = false
}

output "directory_security_group_id" {
  description = "ID of the directory service security group"
  value       = aws_security_group.directory_service.id
}

output "directory_admin_password" {
  description = "Password for directory administrator account"
  value       = local.directory_password
  sensitive   = true
}

output "trust_relationship_id" {
  description = "ID of the trust relationship (if created)"
  value       = var.enable_on_premises_trust ? aws_directory_service_trust.on_premises[0].id : null
}

output "trust_relationship_state" {
  description = "State of the trust relationship (if created)"
  value       = var.enable_on_premises_trust ? aws_directory_service_trust.on_premises[0].trust_state : null
}

#================================================================================
# WORKSPACES OUTPUTS
#================================================================================

output "workspaces_directory_id" {
  description = "ID of the WorkSpaces directory registration"
  value       = var.enable_workspaces ? aws_workspaces_directory.main[0].id : null
}

output "workspaces_directory_alias" {
  description = "Alias of the WorkSpaces directory"
  value       = var.enable_workspaces ? aws_workspaces_directory.main[0].alias : null
}

output "workspaces_registration_code" {
  description = "Registration code for WorkSpaces directory"
  value       = var.enable_workspaces ? aws_workspaces_directory.main[0].registration_code : null
}

output "workspaces_security_group_id" {
  description = "ID of the WorkSpaces security group"
  value       = var.enable_workspaces ? aws_security_group.workspaces[0].id : null
}

output "test_workspaces" {
  description = "Information about created test WorkSpaces"
  value = var.create_test_users && var.enable_workspaces ? {
    for k, v in aws_workspaces_workspace.test_users : k => {
      workspace_id    = v.id
      username       = v.user_name
      computer_name  = v.computer_name
      ip_address     = v.ip_address
      state          = v.state
    }
  } : {}
}

#================================================================================
# RDS OUTPUTS
#================================================================================

output "rds_instance_id" {
  description = "ID of the RDS SQL Server instance"
  value       = var.enable_rds ? aws_db_instance.main[0].id : null
}

output "rds_endpoint" {
  description = "Endpoint address of the RDS instance"
  value       = var.enable_rds ? aws_db_instance.main[0].endpoint : null
}

output "rds_port" {
  description = "Port of the RDS instance"
  value       = var.enable_rds ? aws_db_instance.main[0].port : null
}

output "rds_domain_membership" {
  description = "Domain membership information for RDS instance"
  value = var.enable_rds ? {
    domain = aws_db_instance.main[0].domain
    fqdn   = aws_db_instance.main[0].domain_fqdn
    iam_role = aws_db_instance.main[0].domain_iam_role_name
  } : null
}

output "rds_admin_username" {
  description = "Administrator username for RDS instance"
  value       = var.enable_rds ? aws_db_instance.main[0].username : null
}

output "rds_admin_password" {
  description = "Administrator password for RDS instance"
  value       = var.enable_rds ? random_password.rds_password[0].result : null
  sensitive   = true
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = var.enable_rds ? aws_security_group.rds[0].id : null
}

output "rds_subnet_group_name" {
  description = "Name of the RDS DB subnet group"
  value       = var.enable_rds ? aws_db_subnet_group.main[0].name : null
}

#================================================================================
# IAM OUTPUTS
#================================================================================

output "rds_directory_service_role_arn" {
  description = "ARN of the IAM role for RDS Directory Service integration"
  value       = var.enable_rds ? aws_iam_role.rds_directory_service[0].arn : null
}

output "domain_admin_role_arn" {
  description = "ARN of the domain admin IAM role"
  value       = aws_iam_role.domain_admin.arn
}

output "domain_admin_instance_profile_arn" {
  description = "ARN of the domain admin instance profile"
  value       = aws_iam_instance_profile.domain_admin.arn
}

#================================================================================
# EC2 MANAGEMENT INSTANCE OUTPUTS
#================================================================================

output "domain_admin_instance_id" {
  description = "ID of the domain admin EC2 instance"
  value       = aws_instance.domain_admin.id
}

output "domain_admin_private_ip" {
  description = "Private IP address of the domain admin instance"
  value       = aws_instance.domain_admin.private_ip
}

output "domain_admin_security_group_id" {
  description = "ID of the domain admin security group"
  value       = aws_security_group.management.id
}

output "domain_admin_key_name" {
  description = "Name of the key pair for domain admin instance"
  value       = aws_key_pair.domain_admin.key_name
}

#================================================================================
# MONITORING AND LOGGING OUTPUTS
#================================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for directory service"
  value       = aws_cloudwatch_log_group.directory_service.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for directory service"
  value       = aws_cloudwatch_log_group.directory_service.arn
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs (if enabled)"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

#================================================================================
# CONNECTION INFORMATION
#================================================================================

output "connection_instructions" {
  description = "Instructions for connecting to and managing the hybrid identity infrastructure"
  value = {
    directory_management = {
      description = "Connect to domain admin instance via RDP to manage Active Directory"
      rdp_address = aws_instance.domain_admin.private_ip
      username    = "Administrator"
      note        = "Use EC2 Session Manager or VPN/bastion host to access private instance"
    }
    
    workspaces_access = var.enable_workspaces ? {
      description     = "Users can access WorkSpaces via web client or native applications"
      web_access_url  = "https://${var.aws_region}.console.aws.amazon.com/workspaces/home"
      registration_code = aws_workspaces_directory.main[0].registration_code
      note            = "Users must be created in Active Directory before accessing WorkSpaces"
    } : null
    
    database_connection = var.enable_rds ? {
      description = "Connect to SQL Server using Windows Authentication"
      server      = aws_db_instance.main[0].endpoint
      port        = aws_db_instance.main[0].port
      auth_method = "Windows Authentication (after domain join)"
      note        = "Applications must be domain-joined to use Windows Authentication"
    } : null
  }
}

#================================================================================
# VALIDATION OUTPUTS
#================================================================================

output "validation_commands" {
  description = "Commands to validate the hybrid identity infrastructure"
  value = {
    directory_status = "aws ds describe-directories --directory-ids ${aws_directory_service_directory.main.id}"
    
    workspaces_status = var.enable_workspaces ? 
      "aws workspaces describe-workspace-directories --directory-ids ${aws_directory_service_directory.main.id}" : 
      "WorkSpaces not enabled"
    
    rds_domain_status = var.enable_rds ? 
      "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.main[0].id} --query 'DBInstances[0].DomainMemberships'" : 
      "RDS not enabled"
    
    trust_status = var.enable_on_premises_trust ? 
      "aws ds describe-trusts --directory-id ${aws_directory_service_directory.main.id}" : 
      "Trust relationship not configured"
  }
}

#================================================================================
# COST ESTIMATION
#================================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure (USD)"
  value = {
    directory_service = "${var.directory_edition == "Standard" ? "292" : "1460"} (2 domain controllers @ ${var.directory_edition == "Standard" ? "$0.20" : "$1.00"}/hour each)"
    
    workspaces = var.enable_workspaces ? "${length(var.test_users)} WorkSpaces @ ~$25-35/month each (depending on bundle and usage)" : "Not enabled"
    
    rds_instance = var.enable_rds ? "~$150-300/month for ${var.rds_instance_class} (${var.rds_allocated_storage}GB storage)" : "Not enabled"
    
    ec2_instance = "~$30-50/month for t3.medium domain admin instance"
    
    networking = "~$45-90/month for NAT gateways (2 AZs)"
    
    storage_logs = "~$5-20/month for CloudWatch logs and S3 storage"
    
    total_estimate = "~$522-985/month (varies by usage and optional components)"
    
    note = "Costs are estimates and vary by region, usage patterns, and AWS pricing changes"
  }
}