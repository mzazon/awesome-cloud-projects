# Outputs for Advanced Request Routing with VPC Lattice and ALB

#------------------------------------------------------------------------------
# VPC Lattice Outputs
#------------------------------------------------------------------------------

output "lattice_service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "lattice_service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "lattice_service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.api_gateway.id
}

output "lattice_service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.api_gateway.arn
}

output "lattice_service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.api_gateway.dns_entry[0].domain_name
}

output "lattice_service_hosted_zone_id" {
  description = "Hosted zone ID of the VPC Lattice service"
  value       = aws_vpclattice_service.api_gateway.dns_entry[0].hosted_zone_id
}

output "lattice_listener_id" {
  description = "ID of the VPC Lattice HTTP listener"
  value       = aws_vpclattice_listener.http.listener_id
}

output "lattice_target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.alb_targets.id
}

#------------------------------------------------------------------------------
# Application Load Balancer Outputs
#------------------------------------------------------------------------------

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.api_service.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.api_service.dns_name
}

output "alb_hosted_zone_id" {
  description = "Hosted zone ID of the Application Load Balancer"
  value       = aws_lb.api_service.zone_id
}

output "alb_target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.api_service.arn
}

output "alb_listener_http_arn" {
  description = "ARN of the ALB HTTP listener"
  value       = aws_lb_listener.api_service_http.arn
}

output "alb_listener_https_arn" {
  description = "ARN of the ALB HTTPS listener (if enabled)"
  value       = var.enable_https ? aws_lb_listener.api_service_https[0].arn : null
}

#------------------------------------------------------------------------------
# EC2 Instance Outputs
#------------------------------------------------------------------------------

output "ec2_instance_ids" {
  description = "IDs of the EC2 instances"
  value       = aws_instance.api_service[*].id
}

output "ec2_instance_private_ips" {
  description = "Private IP addresses of the EC2 instances"
  value       = aws_instance.api_service[*].private_ip
}

output "ec2_instance_availability_zones" {
  description = "Availability zones of the EC2 instances"
  value       = aws_instance.api_service[*].availability_zone
}

#------------------------------------------------------------------------------
# Network Infrastructure Outputs
#------------------------------------------------------------------------------

output "default_vpc_id" {
  description = "ID of the default VPC used"
  value       = local.vpc_id
}

output "target_vpc_id" {
  description = "ID of the target VPC created"
  value       = aws_vpc.target.id
}

output "target_vpc_cidr" {
  description = "CIDR block of the target VPC"
  value       = aws_vpc.target.cidr_block
}

output "target_subnet_id" {
  description = "ID of the subnet in target VPC"
  value       = aws_subnet.target.id
}

output "default_subnets" {
  description = "IDs of the default subnets used for ALB"
  value       = data.aws_subnets.default.ids
}

#------------------------------------------------------------------------------
# Security Group Outputs
#------------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "instances_security_group_id" {
  description = "ID of the instances security group"
  value       = aws_security_group.instances.id
}

#------------------------------------------------------------------------------
# Routing Rules Outputs
#------------------------------------------------------------------------------

output "routing_rules" {
  description = "Information about configured routing rules"
  value = {
    beta_header_rule_enabled = var.enable_header_routing
    api_path_rule_enabled    = var.enable_path_routing
    post_method_rule_enabled = var.enable_method_routing
    admin_block_rule_active  = true
    
    # Rule configuration details
    beta_header_name  = var.beta_header_name
    beta_header_value = var.beta_header_value
    api_path_prefix   = var.api_path_prefix
  }
}

#------------------------------------------------------------------------------
# Authentication and Security Outputs
#------------------------------------------------------------------------------

output "lattice_auth_type" {
  description = "Authentication type for VPC Lattice service"
  value       = aws_vpclattice_service.api_gateway.auth_type
}

output "lattice_auth_policy_enabled" {
  description = "Whether IAM auth policy is enabled for VPC Lattice service"
  value       = var.enable_lattice_auth_policy && var.lattice_auth_type == "AWS_IAM"
}

#------------------------------------------------------------------------------
# Testing and Validation Outputs
#------------------------------------------------------------------------------

output "test_commands" {
  description = "Commands to test the routing functionality"
  value = {
    # Test default routing
    default_path = "curl -v http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}/"
    
    # Test API v1 path routing
    api_v1_path = "curl -v http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}${var.api_path_prefix}/"
    
    # Test header-based routing
    beta_header = "curl -v -H '${var.beta_header_name}: ${var.beta_header_value}' http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}/"
    
    # Test blocked admin endpoint
    admin_block = "curl -v http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}/admin"
    
    # Test POST method routing
    post_method = "curl -v -X POST http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}/"
  }
}

#------------------------------------------------------------------------------
# Cost and Monitoring Outputs
#------------------------------------------------------------------------------

output "monitoring_endpoints" {
  description = "Endpoints for monitoring the infrastructure"
  value = {
    lattice_service_cloudwatch_namespace = "AWS/VpcLattice"
    alb_cloudwatch_namespace            = "AWS/ApplicationELB"
    ec2_cloudwatch_namespace            = "AWS/EC2"
  }
}

output "resource_summary" {
  description = "Summary of created resources for cost tracking"
  value = {
    vpc_lattice_service_network = 1
    vpc_lattice_service         = 1
    vpc_lattice_target_groups   = 1
    application_load_balancers  = 1
    alb_target_groups          = 1
    ec2_instances              = var.instance_count
    security_groups            = 2
    vpcs_created               = 1
    subnets_created            = 1
    s3_buckets_created         = var.alb_access_logs_enabled ? 1 : 0
  }
}

#------------------------------------------------------------------------------
# Connection Information
#------------------------------------------------------------------------------

output "connection_info" {
  description = "Information for connecting to the service"
  value = {
    service_endpoint = "http://${aws_vpclattice_service.api_gateway.dns_entry[0].domain_name}"
    alb_endpoint     = "http://${aws_lb.api_service.dns_name}"
    environment      = var.environment
    region          = data.aws_region.current.name
    account_id      = data.aws_caller_identity.current.account_id
  }
}