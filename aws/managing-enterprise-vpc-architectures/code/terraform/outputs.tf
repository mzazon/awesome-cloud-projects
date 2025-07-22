# Outputs for Multi-VPC Transit Gateway Architecture
# This file defines output values that are useful for verification and integration

#==============================================================================
# TRANSIT GATEWAY OUTPUTS
#==============================================================================

output "transit_gateway_id" {
  description = "ID of the main Transit Gateway"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_arn" {
  description = "ARN of the main Transit Gateway"
  value       = aws_ec2_transit_gateway.main.arn
}

output "transit_gateway_asn" {
  description = "Amazon Side ASN of the main Transit Gateway"
  value       = aws_ec2_transit_gateway.main.amazon_side_asn
}

output "dr_transit_gateway_id" {
  description = "ID of the disaster recovery Transit Gateway"
  value       = aws_ec2_transit_gateway.dr.id
}

output "dr_transit_gateway_arn" {
  description = "ARN of the disaster recovery Transit Gateway"
  value       = aws_ec2_transit_gateway.dr.arn
}

#==============================================================================
# VPC OUTPUTS
#==============================================================================

output "vpc_ids" {
  description = "Map of VPC names to their IDs"
  value = {
    production  = aws_vpc.production.id
    development = aws_vpc.development.id
    test        = aws_vpc.test.id
    shared      = aws_vpc.shared.id
    dr          = aws_vpc.dr.id
  }
}

output "vpc_cidrs" {
  description = "Map of VPC names to their CIDR blocks"
  value = {
    production  = aws_vpc.production.cidr_block
    development = aws_vpc.development.cidr_block
    test        = aws_vpc.test.cidr_block
    shared      = aws_vpc.shared.cidr_block
    dr          = aws_vpc.dr.cidr_block
  }
}

output "production_vpc" {
  description = "Production VPC details"
  value = {
    id         = aws_vpc.production.id
    arn        = aws_vpc.production.arn
    cidr_block = aws_vpc.production.cidr_block
    subnets = {
      private_a = aws_subnet.production_private_a.id
      private_b = aws_subnet.production_private_b.id
    }
  }
}

output "development_vpc" {
  description = "Development VPC details"
  value = {
    id         = aws_vpc.development.id
    arn        = aws_vpc.development.arn
    cidr_block = aws_vpc.development.cidr_block
    subnets = {
      private_a = aws_subnet.development_private_a.id
      private_b = aws_subnet.development_private_b.id
    }
  }
}

output "test_vpc" {
  description = "Test VPC details"
  value = {
    id         = aws_vpc.test.id
    arn        = aws_vpc.test.arn
    cidr_block = aws_vpc.test.cidr_block
    subnets = {
      private_a = aws_subnet.test_private_a.id
      private_b = aws_subnet.test_private_b.id
    }
  }
}

output "shared_vpc" {
  description = "Shared services VPC details"
  value = {
    id         = aws_vpc.shared.id
    arn        = aws_vpc.shared.arn
    cidr_block = aws_vpc.shared.cidr_block
    subnets = {
      private_a = aws_subnet.shared_private_a.id
      private_b = aws_subnet.shared_private_b.id
    }
  }
}

output "dr_vpc" {
  description = "Disaster recovery VPC details"
  value = {
    id         = aws_vpc.dr.id
    arn        = aws_vpc.dr.arn
    cidr_block = aws_vpc.dr.cidr_block
    subnets = {
      private_a = aws_subnet.dr_private_a.id
      private_b = aws_subnet.dr_private_b.id
    }
  }
}

#==============================================================================
# ROUTE TABLE OUTPUTS
#==============================================================================

output "transit_gateway_route_tables" {
  description = "Map of Transit Gateway route table names to their IDs"
  value = {
    production  = aws_ec2_transit_gateway_route_table.production.id
    development = aws_ec2_transit_gateway_route_table.development.id
    shared      = aws_ec2_transit_gateway_route_table.shared.id
  }
}

output "production_route_table" {
  description = "Production Transit Gateway route table details"
  value = {
    id                 = aws_ec2_transit_gateway_route_table.production.id
    arn                = aws_ec2_transit_gateway_route_table.production.arn
    transit_gateway_id = aws_ec2_transit_gateway_route_table.production.transit_gateway_id
  }
}

output "development_route_table" {
  description = "Development Transit Gateway route table details"
  value = {
    id                 = aws_ec2_transit_gateway_route_table.development.id
    arn                = aws_ec2_transit_gateway_route_table.development.arn
    transit_gateway_id = aws_ec2_transit_gateway_route_table.development.transit_gateway_id
  }
}

output "shared_route_table" {
  description = "Shared services Transit Gateway route table details"
  value = {
    id                 = aws_ec2_transit_gateway_route_table.shared.id
    arn                = aws_ec2_transit_gateway_route_table.shared.arn
    transit_gateway_id = aws_ec2_transit_gateway_route_table.shared.transit_gateway_id
  }
}

#==============================================================================
# ATTACHMENT OUTPUTS
#==============================================================================

output "transit_gateway_attachments" {
  description = "Map of VPC attachment names to their IDs"
  value = {
    production  = aws_ec2_transit_gateway_vpc_attachment.production.id
    development = aws_ec2_transit_gateway_vpc_attachment.development.id
    test        = aws_ec2_transit_gateway_vpc_attachment.test.id
    shared      = aws_ec2_transit_gateway_vpc_attachment.shared.id
    dr          = aws_ec2_transit_gateway_vpc_attachment.dr.id
  }
}

output "production_attachment" {
  description = "Production VPC attachment details"
  value = {
    id                 = aws_ec2_transit_gateway_vpc_attachment.production.id
    vpc_id             = aws_ec2_transit_gateway_vpc_attachment.production.vpc_id
    transit_gateway_id = aws_ec2_transit_gateway_vpc_attachment.production.transit_gateway_id
    subnet_ids         = aws_ec2_transit_gateway_vpc_attachment.production.subnet_ids
  }
}

output "development_attachment" {
  description = "Development VPC attachment details"
  value = {
    id                 = aws_ec2_transit_gateway_vpc_attachment.development.id
    vpc_id             = aws_ec2_transit_gateway_vpc_attachment.development.vpc_id
    transit_gateway_id = aws_ec2_transit_gateway_vpc_attachment.development.transit_gateway_id
    subnet_ids         = aws_ec2_transit_gateway_vpc_attachment.development.subnet_ids
  }
}

output "test_attachment" {
  description = "Test VPC attachment details"
  value = {
    id                 = aws_ec2_transit_gateway_vpc_attachment.test.id
    vpc_id             = aws_ec2_transit_gateway_vpc_attachment.test.vpc_id
    transit_gateway_id = aws_ec2_transit_gateway_vpc_attachment.test.transit_gateway_id
    subnet_ids         = aws_ec2_transit_gateway_vpc_attachment.test.subnet_ids
  }
}

output "shared_attachment" {
  description = "Shared services VPC attachment details"
  value = {
    id                 = aws_ec2_transit_gateway_vpc_attachment.shared.id
    vpc_id             = aws_ec2_transit_gateway_vpc_attachment.shared.vpc_id
    transit_gateway_id = aws_ec2_transit_gateway_vpc_attachment.shared.transit_gateway_id
    subnet_ids         = aws_ec2_transit_gateway_vpc_attachment.shared.subnet_ids
  }
}

output "dr_attachment" {
  description = "DR VPC attachment details"
  value = {
    id                 = aws_ec2_transit_gateway_vpc_attachment.dr.id
    vpc_id             = aws_ec2_transit_gateway_vpc_attachment.dr.vpc_id
    transit_gateway_id = aws_ec2_transit_gateway_vpc_attachment.dr.transit_gateway_id
    subnet_ids         = aws_ec2_transit_gateway_vpc_attachment.dr.subnet_ids
  }
}

#==============================================================================
# SECURITY GROUP OUTPUTS
#==============================================================================

output "security_groups" {
  description = "Map of security group names to their IDs"
  value = {
    production_tgw  = aws_security_group.production_tgw.id
    development_tgw = aws_security_group.development_tgw.id
    shared_tgw      = aws_security_group.shared_tgw.id
  }
}

output "production_security_group" {
  description = "Production security group details"
  value = {
    id          = aws_security_group.production_tgw.id
    arn         = aws_security_group.production_tgw.arn
    name        = aws_security_group.production_tgw.name
    description = aws_security_group.production_tgw.description
    vpc_id      = aws_security_group.production_tgw.vpc_id
  }
}

output "development_security_group" {
  description = "Development security group details"
  value = {
    id          = aws_security_group.development_tgw.id
    arn         = aws_security_group.development_tgw.arn
    name        = aws_security_group.development_tgw.name
    description = aws_security_group.development_tgw.description
    vpc_id      = aws_security_group.development_tgw.vpc_id
  }
}

output "shared_security_group" {
  description = "Shared services security group details"
  value = {
    id          = aws_security_group.shared_tgw.id
    arn         = aws_security_group.shared_tgw.arn
    name        = aws_security_group.shared_tgw.name
    description = aws_security_group.shared_tgw.description
    vpc_id      = aws_security_group.shared_tgw.vpc_id
  }
}

#==============================================================================
# CROSS-REGION PEERING OUTPUTS
#==============================================================================

output "cross_region_peering_attachment_id" {
  description = "ID of the cross-region peering attachment (if enabled)"
  value       = var.enable_cross_region_peering ? aws_ec2_transit_gateway_peering_attachment.cross_region[0].id : null
}

output "cross_region_peering_status" {
  description = "Status of cross-region peering (if enabled)"
  value       = var.enable_cross_region_peering ? aws_ec2_transit_gateway_peering_attachment.cross_region[0].state : "disabled"
}

#==============================================================================
# NETWORKING SUMMARY OUTPUTS
#==============================================================================

output "network_architecture_summary" {
  description = "Summary of the network architecture configuration"
  value = {
    primary_region                = var.aws_region
    dr_region                    = var.dr_region
    transit_gateway_id           = aws_ec2_transit_gateway.main.id
    dr_transit_gateway_id        = aws_ec2_transit_gateway.dr.id
    cross_region_peering_enabled = var.enable_cross_region_peering
    total_vpcs                   = 5
    vpc_count_by_region = {
      primary = 4
      dr      = 1
    }
    route_tables = {
      production_isolated  = true
      development_shared   = true  # Dev and Test share the same route table
      shared_services_hub  = true
    }
    security_policies = {
      prod_dev_isolation    = true  # Blackhole route blocks direct communication
      shared_services_access = true  # All environments can access shared services
    }
  }
}

output "connectivity_matrix" {
  description = "Network connectivity matrix showing which VPCs can communicate"
  value = {
    production_to_development = false  # Blocked by blackhole route
    production_to_test       = false  # Blocked by blackhole route
    production_to_shared     = true   # Explicit route and propagation
    development_to_test      = true   # Both use same route table
    development_to_shared    = true   # Explicit route and propagation
    test_to_shared          = true   # Explicit route and propagation
    shared_to_production    = true   # Route propagation enabled
    shared_to_development   = true   # Route propagation enabled
    shared_to_test         = true   # Route propagation enabled
    primary_to_dr          = var.enable_cross_region_peering
  }
}

#==============================================================================
# COST OPTIMIZATION OUTPUTS
#==============================================================================

output "cost_optimization_info" {
  description = "Information for cost optimization and monitoring"
  value = {
    transit_gateway_hourly_cost    = "$0.05 per attachment per hour"
    data_processing_cost          = "$0.02 per GB processed"
    total_attachments             = 5  # 4 in primary + 1 in DR region
    estimated_monthly_base_cost   = "$18.00"  # 5 attachments * $0.05 * 24 * 30
    cross_region_data_transfer    = var.enable_cross_region_peering ? "Additional charges apply" : "Not applicable"
    monitoring_recommendation     = "Monitor data processing charges via CloudWatch"
  }
}

#==============================================================================
# VALIDATION OUTPUTS
#==============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_transit_gateway_status = "aws ec2 describe-transit-gateways --transit-gateway-ids ${aws_ec2_transit_gateway.main.id}"
    check_vpc_attachments       = "aws ec2 describe-transit-gateway-vpc-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.main.id}"
    check_route_tables          = "aws ec2 describe-transit-gateway-route-tables --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.main.id}"
    test_connectivity           = "# Deploy test instances and verify network connectivity between environments"
  }
}

#==============================================================================
# RESOURCE IDENTIFIERS
#==============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming (if enabled)"
  value       = var.enable_resource_suffix ? random_id.suffix[0].hex : "none"
}

output "resource_naming_pattern" {
  description = "Pattern used for resource naming"
  value = {
    prefix = local.name_prefix
    suffix = local.suffix
    example = "${local.name_prefix}example-resource${local.suffix}"
  }
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

output "deployment_regions" {
  description = "AWS regions where resources are deployed"
  value = {
    primary = var.aws_region
    dr      = var.dr_region
  }
}