# ============================================================================
# General Outputs
# ============================================================================

output "project_id" {
  description = "Generated project ID for resource naming"
  value       = local.project_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# VPC Outputs
# ============================================================================

output "production_vpc" {
  description = "Production VPC details"
  value = {
    id         = aws_vpc.production.id
    cidr_block = aws_vpc.production.cidr_block
    arn        = aws_vpc.production.arn
  }
}

output "development_vpc" {
  description = "Development VPC details"
  value = {
    id         = aws_vpc.development.id
    cidr_block = aws_vpc.development.cidr_block
    arn        = aws_vpc.development.arn
  }
}

output "shared_services_vpc" {
  description = "Shared Services VPC details"
  value = {
    id         = aws_vpc.shared_services.id
    cidr_block = aws_vpc.shared_services.cidr_block
    arn        = aws_vpc.shared_services.arn
  }
}

# ============================================================================
# Transit Gateway Outputs
# ============================================================================

output "transit_gateway" {
  description = "Transit Gateway details"
  value = {
    id                = aws_ec2_transit_gateway.main.id
    arn               = aws_ec2_transit_gateway.main.arn
    amazon_side_asn   = aws_ec2_transit_gateway.main.amazon_side_asn
    default_route_table_id = aws_ec2_transit_gateway.main.default_route_table_id
  }
}

output "transit_gateway_vpc_attachments" {
  description = "Transit Gateway VPC attachment details"
  value = {
    production = {
      id     = aws_ec2_transit_gateway_vpc_attachment.production.id
      vpc_id = aws_ec2_transit_gateway_vpc_attachment.production.vpc_id
    }
    development = {
      id     = aws_ec2_transit_gateway_vpc_attachment.development.id
      vpc_id = aws_ec2_transit_gateway_vpc_attachment.development.vpc_id
    }
    shared_services = {
      id     = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
      vpc_id = aws_ec2_transit_gateway_vpc_attachment.shared_services.vpc_id
    }
  }
}

# ============================================================================
# Direct Connect Outputs
# ============================================================================

output "direct_connect_gateway" {
  description = "Direct Connect Gateway details"
  value = {
    id              = aws_dx_gateway.main.id
    name            = aws_dx_gateway.main.name
    amazon_side_asn = aws_dx_gateway.main.amazon_side_asn
  }
}

output "direct_connect_gateway_association" {
  description = "Direct Connect Gateway association with Transit Gateway"
  value = {
    id                       = aws_dx_gateway_association.main.id
    dx_gateway_id           = aws_dx_gateway_association.main.dx_gateway_id
    associated_gateway_id   = aws_dx_gateway_association.main.associated_gateway_id
    association_state       = aws_dx_gateway_association.main.association_state
  }
}

output "transit_virtual_interface" {
  description = "Transit Virtual Interface details (if created)"
  value = var.dx_connection_id != "" ? {
    id              = aws_dx_transit_virtual_interface.main[0].id
    name            = aws_dx_transit_virtual_interface.main[0].name
    vlan            = aws_dx_transit_virtual_interface.main[0].vlan
    customer_address = aws_dx_transit_virtual_interface.main[0].customer_address
    amazon_address  = aws_dx_transit_virtual_interface.main[0].amazon_address
    bgp_asn         = aws_dx_transit_virtual_interface.main[0].bgp_asn
  } : null
}

# ============================================================================
# DNS Resolution Outputs
# ============================================================================

output "route53_resolver_endpoints" {
  description = "Route 53 Resolver endpoint details"
  value = var.dns_resolver_endpoints ? {
    inbound = {
      id         = aws_route53_resolver_endpoint.inbound[0].id
      name       = aws_route53_resolver_endpoint.inbound[0].name
      ip_address = aws_route53_resolver_endpoint.inbound[0].ip_address[0].ip
    }
    outbound = {
      id         = aws_route53_resolver_endpoint.outbound[0].id
      name       = aws_route53_resolver_endpoint.outbound[0].name
      ip_address = aws_route53_resolver_endpoint.outbound[0].ip_address[0].ip
    }
  } : null
}

# ============================================================================
# Security Outputs
# ============================================================================

output "security_groups" {
  description = "Security group details"
  value = var.dns_resolver_endpoints ? {
    resolver_endpoints = {
      id   = aws_security_group.resolver_endpoints[0].id
      name = aws_security_group.resolver_endpoints[0].name
      arn  = aws_security_group.resolver_endpoints[0].arn
    }
  } : null
}

output "network_acls" {
  description = "Network ACL details"
  value = var.enable_nacl_rules ? {
    shared_services = {
      id = aws_network_acl.shared_services[0].id
    }
  } : null
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard details"
  value = var.enable_cloudwatch_monitoring ? {
    dashboard_name = aws_cloudwatch_dashboard.dx_monitoring[0].dashboard_name
    dashboard_url  = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.dx_monitoring[0].dashboard_name}"
  } : null
}

output "sns_topic" {
  description = "SNS topic for alerts"
  value = var.enable_cloudwatch_monitoring ? {
    arn  = aws_sns_topic.dx_alerts[0].arn
    name = aws_sns_topic.dx_alerts[0].name
  } : null
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm details"
  value = var.enable_cloudwatch_monitoring ? {
    dx_connection_down = var.dx_connection_id != "" ? aws_cloudwatch_metric_alarm.dx_connection_down[0].alarm_name : null
    tgw_high_bytes     = aws_cloudwatch_metric_alarm.tgw_high_bytes[0].alarm_name
  } : null
}

# ============================================================================
# VPC Flow Logs Outputs
# ============================================================================

output "vpc_flow_logs" {
  description = "VPC Flow Logs details"
  value = var.enable_flow_logs ? {
    log_group_name = aws_cloudwatch_log_group.vpc_flow_logs[0].name
    log_group_arn  = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
    iam_role_arn   = aws_iam_role.flow_logs_role[0].arn
  } : null
}

# ============================================================================
# Configuration Outputs for On-Premises Setup
# ============================================================================

output "bgp_configuration" {
  description = "BGP configuration details for on-premises router"
  value = {
    on_premises_asn = var.on_premises_asn
    aws_asn         = var.aws_asn
    customer_address = var.customer_address
    amazon_address  = var.amazon_address
    transit_vif_vlan = var.transit_vif_vlan
  }
}

output "network_configuration" {
  description = "Network configuration details"
  value = {
    on_premises_cidr = var.on_premises_cidr
    vpc_cidrs = {
      production      = var.prod_vpc_cidr
      development     = var.dev_vpc_cidr
      shared_services = var.shared_vpc_cidr
    }
  }
}

# ============================================================================
# Testing and Validation Outputs
# ============================================================================

output "testing_commands" {
  description = "Useful commands for testing hybrid connectivity"
  value = {
    check_dx_gateway = "aws directconnect describe-direct-connect-gateways --direct-connect-gateway-id ${aws_dx_gateway.main.id}"
    check_tgw_attachments = "aws ec2 describe-transit-gateway-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.main.id}"
    check_tgw_routes = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway.main.default_route_table_id} --filters Name=state,Values=active"
    check_resolver_endpoints = var.dns_resolver_endpoints ? "aws route53resolver list-resolver-endpoints" : null
  }
}

output "next_steps" {
  description = "Next steps for completing the hybrid connectivity setup"
  value = [
    "1. Create Direct Connect connection with your provider or in AWS console",
    "2. Create Transit Virtual Interface using the DX connection ID",
    "3. Configure BGP routing on your on-premises router",
    "4. Test connectivity between VPCs and on-premises networks",
    "5. Configure DNS forwarding rules for hybrid name resolution",
    "6. Set up monitoring and alerting for connection health",
    "7. Implement security policies and access controls"
  ]
}

# ============================================================================
# Resource ARNs for Cross-Service Integration
# ============================================================================

output "resource_arns" {
  description = "ARNs of all major resources for integration with other services"
  value = {
    vpc_arns = {
      production      = aws_vpc.production.arn
      development     = aws_vpc.development.arn
      shared_services = aws_vpc.shared_services.arn
    }
    transit_gateway_arn = aws_ec2_transit_gateway.main.arn
    dx_gateway_arn      = aws_dx_gateway.main.arn
    sns_topic_arn       = var.enable_cloudwatch_monitoring ? aws_sns_topic.dx_alerts[0].arn : null
  }
}