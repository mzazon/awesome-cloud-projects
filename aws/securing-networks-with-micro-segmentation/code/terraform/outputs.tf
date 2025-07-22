# Outputs for Network Micro-Segmentation Infrastructure

# =============================================================================
# VPC AND NETWORKING OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "availability_zone" {
  description = "Availability zone used for subnets"
  value       = local.availability_zone
}

# =============================================================================
# SUBNET OUTPUTS
# =============================================================================

output "subnet_ids" {
  description = "Map of subnet IDs for each security zone"
  value = {
    dmz        = aws_subnet.dmz.id
    web        = aws_subnet.web.id
    app        = aws_subnet.app.id
    database   = aws_subnet.database.id
    management = aws_subnet.management.id
    monitoring = aws_subnet.monitoring.id
  }
}

output "subnet_cidrs" {
  description = "Map of subnet CIDR blocks for each security zone"
  value = {
    dmz        = aws_subnet.dmz.cidr_block
    web        = aws_subnet.web.cidr_block
    app        = aws_subnet.app.cidr_block
    database   = aws_subnet.database.cidr_block
    management = aws_subnet.management.cidr_block
    monitoring = aws_subnet.monitoring.cidr_block
  }
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [aws_subnet.dmz.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value = [
    aws_subnet.web.id,
    aws_subnet.app.id,
    aws_subnet.database.id,
    aws_subnet.management.id,
    aws_subnet.monitoring.id
  ]
}

# =============================================================================
# ROUTE TABLE OUTPUTS
# =============================================================================

output "route_table_ids" {
  description = "Route table IDs"
  value = {
    public  = aws_route_table.public.id
    private = aws_route_table.private.id
  }
}

# =============================================================================
# NETWORK ACL OUTPUTS
# =============================================================================

output "network_acl_ids" {
  description = "Map of Network ACL IDs for each security zone"
  value = {
    dmz        = aws_network_acl.dmz.id
    web        = aws_network_acl.web.id
    app        = aws_network_acl.app.id
    database   = aws_network_acl.database.id
    management = aws_network_acl.management.id
    monitoring = aws_network_acl.monitoring.id
  }
}

# =============================================================================
# SECURITY GROUP OUTPUTS
# =============================================================================

output "security_group_ids" {
  description = "Map of Security Group IDs for each tier"
  value = {
    dmz_alb      = aws_security_group.dmz_alb.id
    web_tier     = aws_security_group.web_tier.id
    app_tier     = aws_security_group.app_tier.id
    database     = aws_security_group.database_tier.id
    management   = aws_security_group.management.id
  }
}

output "security_group_arns" {
  description = "Map of Security Group ARNs for each tier"
  value = {
    dmz_alb      = aws_security_group.dmz_alb.arn
    web_tier     = aws_security_group.web_tier.arn
    app_tier     = aws_security_group.app_tier.arn
    database     = aws_security_group.database_tier.arn
    management   = aws_security_group.management.arn
  }
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "vpc_flow_logs_id" {
  description = "ID of the VPC Flow Logs"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vpc_flow_logs[0].id : null
}

output "flow_logs_log_group_name" {
  description = "Name of the CloudWatch Log Group for VPC Flow Logs"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for VPC Flow Logs"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}

output "rejected_traffic_alarm_name" {
  description = "Name of the CloudWatch alarm for rejected traffic"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.rejected_traffic[0].alarm_name : null
}

output "rejected_traffic_alarm_arn" {
  description = "ARN of the CloudWatch alarm for rejected traffic"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.rejected_traffic[0].arn : null
}

# =============================================================================
# KEY PAIR OUTPUTS
# =============================================================================

output "key_pair_name" {
  description = "Name of the EC2 key pair"
  value       = var.create_key_pair ? aws_key_pair.main[0].key_name : null
}

output "key_pair_fingerprint" {
  description = "Fingerprint of the EC2 key pair"
  value       = var.create_key_pair ? aws_key_pair.main[0].fingerprint : null
}

output "private_key_path" {
  description = "Path to the private key file"
  value       = var.create_key_pair ? local_file.private_key[0].filename : null
  sensitive   = true
}

# =============================================================================
# RESOURCE NAMING OUTPUTS
# =============================================================================

output "name_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# =============================================================================
# DEPLOYMENT INFORMATION
# =============================================================================

output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    vpc_id             = aws_vpc.main.id
    vpc_cidr           = aws_vpc.main.cidr_block
    availability_zone  = local.availability_zone
    environment        = var.environment
    flow_logs_enabled  = var.enable_vpc_flow_logs
    alarms_enabled     = var.enable_cloudwatch_alarms
    key_pair_created   = var.create_key_pair
    subnet_count       = 6
    nacl_count         = 6
    security_group_count = 5
  }
}

# =============================================================================
# NEXT STEPS INFORMATION
# =============================================================================

output "next_steps" {
  description = "Next steps for implementing the micro-segmentation architecture"
  value = {
    validation_commands = [
      "aws ec2 describe-vpcs --vpc-ids ${aws_vpc.main.id}",
      "aws ec2 describe-subnets --filters Name=vpc-id,Values=${aws_vpc.main.id}",
      "aws ec2 describe-network-acls --filters Name=vpc-id,Values=${aws_vpc.main.id}",
      "aws ec2 describe-security-groups --filters Name=vpc-id,Values=${aws_vpc.main.id}",
      var.enable_vpc_flow_logs ? "aws ec2 describe-flow-logs --filter Name=resource-id,Values=${aws_vpc.main.id}" : null
    ]
    
    deployment_verification = [
      "Verify NACL rules are properly configured for each subnet",
      "Test security group rules using source group references",
      "Validate VPC Flow Logs are capturing traffic data",
      "Check CloudWatch alarms are configured for monitoring",
      "Review network connectivity between security zones"
    ]
    
    security_considerations = [
      "Regularly audit NACL and security group rules",
      "Monitor VPC Flow Logs for suspicious activity",
      "Implement automated responses to security events",
      "Review and update security group rules as needed",
      "Ensure proper key management for EC2 instances"
    ]
  }
}

# =============================================================================
# COST OPTIMIZATION OUTPUTS
# =============================================================================

output "cost_optimization_notes" {
  description = "Notes for cost optimization"
  value = {
    vpc_resources = "VPC, subnets, route tables, NACLs, and security groups have no ongoing costs"
    flow_logs = var.enable_vpc_flow_logs ? "VPC Flow Logs incur charges for CloudWatch Logs storage and data processing" : "VPC Flow Logs are disabled"
    cloudwatch_alarms = var.enable_cloudwatch_alarms ? "CloudWatch alarms incur minimal charges per alarm per month" : "CloudWatch alarms are disabled"
    key_pair = var.create_key_pair ? "EC2 key pairs have no charges" : "No key pair created"
    estimated_monthly_cost = "Estimated $5-15/month for Flow Logs and monitoring (depends on traffic volume)"
  }
}