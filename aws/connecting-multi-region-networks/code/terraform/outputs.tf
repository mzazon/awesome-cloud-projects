# Output values for multi-region Transit Gateway infrastructure
# These outputs provide important information for verification and integration

#===============================================================================
# PROJECT INFORMATION
#===============================================================================

output "project_name" {
  description = "Name of the project with unique suffix"
  value       = local.name_prefix
}

output "deployment_regions" {
  description = "AWS regions where infrastructure is deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

#===============================================================================
# PRIMARY REGION OUTPUTS
#===============================================================================

output "primary_transit_gateway" {
  description = "Primary Transit Gateway information"
  value = {
    id          = aws_ec2_transit_gateway.primary.id
    arn         = aws_ec2_transit_gateway.primary.arn
    asn         = aws_ec2_transit_gateway.primary.amazon_side_asn
    description = aws_ec2_transit_gateway.primary.description
  }
}

output "primary_vpcs" {
  description = "Primary region VPC information"
  value = {
    vpc_a = {
      id         = aws_vpc.primary_vpc_a.id
      arn        = aws_vpc.primary_vpc_a.arn
      cidr_block = aws_vpc.primary_vpc_a.cidr_block
    }
    vpc_b = {
      id         = aws_vpc.primary_vpc_b.id
      arn        = aws_vpc.primary_vpc_b.arn
      cidr_block = aws_vpc.primary_vpc_b.cidr_block
    }
  }
}

output "primary_subnets" {
  description = "Primary region subnet information"
  value = {
    subnet_a = {
      id                = aws_subnet.primary_subnet_a.id
      arn               = aws_subnet.primary_subnet_a.arn
      cidr_block        = aws_subnet.primary_subnet_a.cidr_block
      availability_zone = aws_subnet.primary_subnet_a.availability_zone
    }
    subnet_b = {
      id                = aws_subnet.primary_subnet_b.id
      arn               = aws_subnet.primary_subnet_b.arn
      cidr_block        = aws_subnet.primary_subnet_b.cidr_block
      availability_zone = aws_subnet.primary_subnet_b.availability_zone
    }
  }
}

output "primary_vpc_attachments" {
  description = "Primary region VPC attachment information"
  value = {
    attachment_a = {
      id                     = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_a.id
      vpc_id                = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_a.vpc_id
      transit_gateway_id     = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_a.transit_gateway_id
    }
    attachment_b = {
      id                     = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_b.id
      vpc_id                = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_b.vpc_id
      transit_gateway_id     = aws_ec2_transit_gateway_vpc_attachment.primary_attachment_b.transit_gateway_id
    }
  }
}

output "primary_route_table" {
  description = "Primary Transit Gateway route table information"
  value = {
    id                 = aws_ec2_transit_gateway_route_table.primary.id
    transit_gateway_id = aws_ec2_transit_gateway_route_table.primary.transit_gateway_id
  }
}

#===============================================================================
# SECONDARY REGION OUTPUTS
#===============================================================================

output "secondary_transit_gateway" {
  description = "Secondary Transit Gateway information"
  value = {
    id          = aws_ec2_transit_gateway.secondary.id
    arn         = aws_ec2_transit_gateway.secondary.arn
    asn         = aws_ec2_transit_gateway.secondary.amazon_side_asn
    description = aws_ec2_transit_gateway.secondary.description
  }
}

output "secondary_vpcs" {
  description = "Secondary region VPC information"
  value = {
    vpc_a = {
      id         = aws_vpc.secondary_vpc_a.id
      arn        = aws_vpc.secondary_vpc_a.arn
      cidr_block = aws_vpc.secondary_vpc_a.cidr_block
    }
    vpc_b = {
      id         = aws_vpc.secondary_vpc_b.id
      arn        = aws_vpc.secondary_vpc_b.arn
      cidr_block = aws_vpc.secondary_vpc_b.cidr_block
    }
  }
}

output "secondary_subnets" {
  description = "Secondary region subnet information"
  value = {
    subnet_a = {
      id                = aws_subnet.secondary_subnet_a.id
      arn               = aws_subnet.secondary_subnet_a.arn
      cidr_block        = aws_subnet.secondary_subnet_a.cidr_block
      availability_zone = aws_subnet.secondary_subnet_a.availability_zone
    }
    subnet_b = {
      id                = aws_subnet.secondary_subnet_b.id
      arn               = aws_subnet.secondary_subnet_b.arn
      cidr_block        = aws_subnet.secondary_subnet_b.cidr_block
      availability_zone = aws_subnet.secondary_subnet_b.availability_zone
    }
  }
}

output "secondary_vpc_attachments" {
  description = "Secondary region VPC attachment information"
  value = {
    attachment_a = {
      id                     = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_a.id
      vpc_id                = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_a.vpc_id
      transit_gateway_id     = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_a.transit_gateway_id
    }
    attachment_b = {
      id                     = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_b.id
      vpc_id                = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_b.vpc_id
      transit_gateway_id     = aws_ec2_transit_gateway_vpc_attachment.secondary_attachment_b.transit_gateway_id
    }
  }
}

output "secondary_route_table" {
  description = "Secondary Transit Gateway route table information"
  value = {
    id                 = aws_ec2_transit_gateway_route_table.secondary.id
    transit_gateway_id = aws_ec2_transit_gateway_route_table.secondary.transit_gateway_id
  }
}

#===============================================================================
# CROSS-REGION CONNECTIVITY OUTPUTS
#===============================================================================

output "cross_region_peering" {
  description = "Cross-region peering attachment information"
  value = {
    id                          = aws_ec2_transit_gateway_peering_attachment.cross_region.id
    peer_account_id            = aws_ec2_transit_gateway_peering_attachment.cross_region.peer_account_id
    peer_region                = aws_ec2_transit_gateway_peering_attachment.cross_region.peer_region
    peer_transit_gateway_id    = aws_ec2_transit_gateway_peering_attachment.cross_region.peer_transit_gateway_id
    transit_gateway_id         = aws_ec2_transit_gateway_peering_attachment.cross_region.transit_gateway_id
  }
}

output "cross_region_routes" {
  description = "Cross-region route configuration"
  value = {
    primary_to_secondary = {
      vpc_a_route = {
        destination_cidr = aws_ec2_transit_gateway_route.primary_to_secondary_a.destination_cidr_block
        attachment_id    = aws_ec2_transit_gateway_route.primary_to_secondary_a.transit_gateway_attachment_id
      }
      vpc_b_route = {
        destination_cidr = aws_ec2_transit_gateway_route.primary_to_secondary_b.destination_cidr_block
        attachment_id    = aws_ec2_transit_gateway_route.primary_to_secondary_b.transit_gateway_attachment_id
      }
    }
    secondary_to_primary = {
      vpc_a_route = {
        destination_cidr = aws_ec2_transit_gateway_route.secondary_to_primary_a.destination_cidr_block
        attachment_id    = aws_ec2_transit_gateway_route.secondary_to_primary_a.transit_gateway_attachment_id
      }
      vpc_b_route = {
        destination_cidr = aws_ec2_transit_gateway_route.secondary_to_primary_b.destination_cidr_block
        attachment_id    = aws_ec2_transit_gateway_route.secondary_to_primary_b.transit_gateway_attachment_id
      }
    }
  }
}

#===============================================================================
# SECURITY GROUPS OUTPUTS
#===============================================================================

output "security_groups" {
  description = "Security groups for cross-region testing"
  value = var.enable_cross_region_icmp ? {
    primary_cross_region = {
      id          = aws_security_group.primary_cross_region[0].id
      arn         = aws_security_group.primary_cross_region[0].arn
      name        = aws_security_group.primary_cross_region[0].name
      description = aws_security_group.primary_cross_region[0].description
      vpc_id      = aws_security_group.primary_cross_region[0].vpc_id
    }
    secondary_cross_region = {
      id          = aws_security_group.secondary_cross_region[0].id
      arn         = aws_security_group.secondary_cross_region[0].arn
      name        = aws_security_group.secondary_cross_region[0].name
      description = aws_security_group.secondary_cross_region[0].description
      vpc_id      = aws_security_group.secondary_cross_region[0].vpc_id
    }
  } : {}
}

#===============================================================================
# MONITORING OUTPUTS
#===============================================================================

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard for monitoring"
  value = var.create_cloudwatch_dashboard ? {
    dashboard_name = aws_cloudwatch_dashboard.tgw_monitoring[0].dashboard_name
    dashboard_url  = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.tgw_monitoring[0].dashboard_name}"
  } : null
}

#===============================================================================
# VERIFICATION COMMANDS
#===============================================================================

output "verification_commands" {
  description = "CLI commands for verifying the deployment"
  value = {
    check_primary_tgw_status = "aws ec2 describe-transit-gateways --transit-gateway-ids ${aws_ec2_transit_gateway.primary.id} --region ${var.primary_region} --query 'TransitGateways[0].State' --output text"
    
    check_secondary_tgw_status = "aws ec2 describe-transit-gateways --transit-gateway-ids ${aws_ec2_transit_gateway.secondary.id} --region ${var.secondary_region} --query 'TransitGateways[0].State' --output text"
    
    check_peering_status = "aws ec2 describe-transit-gateway-peering-attachments --transit-gateway-attachment-ids ${aws_ec2_transit_gateway_peering_attachment.cross_region.id} --region ${var.primary_region} --query 'TransitGatewayPeeringAttachments[0].State' --output text"
    
    list_primary_routes = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway_route_table.primary.id} --filters Name=state,Values=active --region ${var.primary_region} --query 'Routes[].{Destination:DestinationCidrBlock,State:State}'"
    
    list_secondary_routes = "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${aws_ec2_transit_gateway_route_table.secondary.id} --filters Name=state,Values=active --region ${var.secondary_region} --query 'Routes[].{Destination:DestinationCidrBlock,State:State}'"
    
    get_primary_attachments = "aws ec2 describe-transit-gateway-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.primary.id} --region ${var.primary_region} --query 'TransitGatewayAttachments[].{AttachmentId:TransitGatewayAttachmentId,State:State,Type:ResourceType}'"
    
    get_secondary_attachments = "aws ec2 describe-transit-gateway-attachments --filters Name=transit-gateway-id,Values=${aws_ec2_transit_gateway.secondary.id} --region ${var.secondary_region} --query 'TransitGatewayAttachments[].{AttachmentId:TransitGatewayAttachmentId,State:State,Type:ResourceType}'"
  }
}

#===============================================================================
# COST INFORMATION
#===============================================================================

output "cost_information" {
  description = "Information about the costs associated with this deployment"
  value = {
    transit_gateway_charges = "Transit Gateway charges: $36/month per TGW (2 TGWs = $72/month)"
    vpc_attachment_charges  = "VPC attachment charges: $36/month per attachment (4 attachments = $144/month)"
    peering_attachment_charges = "Peering attachment charges: $36/month per peering (1 peering = $36/month)"
    data_processing_charges = "Data processing charges: $0.02 per GB processed"
    cross_region_data_transfer = "Cross-region data transfer: $0.02 per GB transferred"
    estimated_monthly_base_cost = "$252/month (excluding data processing and transfer)"
    cost_optimization_tips = [
      "Monitor data transfer patterns to optimize costs",
      "Use CloudWatch metrics to track data processing charges",
      "Consider workload placement to minimize cross-region transfer",
      "Review attachment usage and remove unused connections"
    ]
  }
}

#===============================================================================
# NEXT STEPS
#===============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    verification = [
      "Run the verification commands above to check deployment status",
      "Access the CloudWatch dashboard to monitor Transit Gateway metrics",
      "Test cross-region connectivity using the created security groups"
    ]
    optimization = [
      "Configure additional route tables for traffic segmentation",
      "Implement Transit Gateway Policy Tables for fine-grained control",
      "Set up Flow Logs for detailed network traffic analysis",
      "Configure additional monitoring and alerting"
    ]
    scaling = [
      "Add additional VPCs as needed using VPC attachments",
      "Implement cross-account sharing using AWS Resource Access Manager",
      "Configure additional regions using the same pattern",
      "Add hybrid connectivity with Direct Connect or VPN"
    ]
  }
}