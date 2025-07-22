# Outputs for Multi-Region VPC Peering with Complex Routing Scenarios
# This file defines all output values that provide information about the deployed infrastructure

#===============================================================================
# PROJECT AND DEPLOYMENT INFORMATION
#===============================================================================

output "project_name" {
  description = "Name of the deployed project"
  value       = var.project_name
}

output "deployment_identifier" {
  description = "Unique identifier for this deployment"
  value       = local.name_prefix
}

output "deployment_regions" {
  description = "All AWS regions used in this deployment"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    eu        = var.eu_region
    apac      = var.apac_region
  }
}

#===============================================================================
# VPC INFORMATION
#===============================================================================

output "vpc_ids" {
  description = "IDs of all created VPCs organized by region and purpose"
  value = {
    primary_region = {
      hub_vpc  = aws_vpc.hub_vpc.id
      prod_vpc = aws_vpc.prod_vpc.id
      dev_vpc  = aws_vpc.dev_vpc.id
    }
    secondary_region = {
      dr_hub_vpc  = aws_vpc.dr_hub_vpc.id
      dr_prod_vpc = aws_vpc.dr_prod_vpc.id
    }
    eu_region = {
      eu_hub_vpc  = aws_vpc.eu_hub_vpc.id
      eu_prod_vpc = aws_vpc.eu_prod_vpc.id
    }
    apac_region = {
      apac_vpc = aws_vpc.apac_vpc.id
    }
  }
}

output "vpc_cidr_blocks" {
  description = "CIDR blocks for all VPCs"
  value = {
    hub_vpc     = aws_vpc.hub_vpc.cidr_block
    prod_vpc    = aws_vpc.prod_vpc.cidr_block
    dev_vpc     = aws_vpc.dev_vpc.cidr_block
    dr_hub_vpc  = aws_vpc.dr_hub_vpc.cidr_block
    dr_prod_vpc = aws_vpc.dr_prod_vpc.cidr_block
    eu_hub_vpc  = aws_vpc.eu_hub_vpc.cidr_block
    eu_prod_vpc = aws_vpc.eu_prod_vpc.cidr_block
    apac_vpc    = aws_vpc.apac_vpc.cidr_block
  }
}

output "subnet_ids" {
  description = "IDs of all created subnets organized by region and purpose"
  value = {
    primary_region = {
      hub_subnet  = aws_subnet.hub_subnet.id
      prod_subnet = aws_subnet.prod_subnet.id
      dev_subnet  = aws_subnet.dev_subnet.id
    }
    secondary_region = {
      dr_hub_subnet  = aws_subnet.dr_hub_subnet.id
      dr_prod_subnet = aws_subnet.dr_prod_subnet.id
    }
    eu_region = {
      eu_hub_subnet  = aws_subnet.eu_hub_subnet.id
      eu_prod_subnet = aws_subnet.eu_prod_subnet.id
    }
    apac_region = {
      apac_subnet = aws_subnet.apac_subnet.id
    }
  }
}

output "subnet_cidr_blocks" {
  description = "CIDR blocks for all subnets"
  value = {
    hub_subnet     = aws_subnet.hub_subnet.cidr_block
    prod_subnet    = aws_subnet.prod_subnet.cidr_block
    dev_subnet     = aws_subnet.dev_subnet.cidr_block
    dr_hub_subnet  = aws_subnet.dr_hub_subnet.cidr_block
    dr_prod_subnet = aws_subnet.dr_prod_subnet.cidr_block
    eu_hub_subnet  = aws_subnet.eu_hub_subnet.cidr_block
    eu_prod_subnet = aws_subnet.eu_prod_subnet.cidr_block
    apac_subnet    = aws_subnet.apac_subnet.cidr_block
  }
}

#===============================================================================
# VPC PEERING CONNECTION INFORMATION
#===============================================================================

output "vpc_peering_connections" {
  description = "IDs and status of all VPC peering connections"
  value = {
    inter_region_hub_connections = {
      hub_to_dr_hub = {
        id     = aws_vpc_peering_connection.hub_to_dr_hub.id
        status = aws_vpc_peering_connection.hub_to_dr_hub.accept_status
      }
      hub_to_eu_hub = {
        id     = aws_vpc_peering_connection.hub_to_eu_hub.id
        status = aws_vpc_peering_connection.hub_to_eu_hub.accept_status
      }
      dr_hub_to_eu_hub = {
        id     = aws_vpc_peering_connection.dr_hub_to_eu_hub.id
        status = aws_vpc_peering_connection.dr_hub_to_eu_hub.accept_status
      }
    }
    intra_region_hub_spoke_connections = {
      hub_to_prod = {
        id     = aws_vpc_peering_connection.hub_to_prod.id
        status = aws_vpc_peering_connection.hub_to_prod.accept_status
      }
      hub_to_dev = {
        id     = aws_vpc_peering_connection.hub_to_dev.id
        status = aws_vpc_peering_connection.hub_to_dev.accept_status
      }
      dr_hub_to_dr_prod = {
        id     = aws_vpc_peering_connection.dr_hub_to_dr_prod.id
        status = aws_vpc_peering_connection.dr_hub_to_dr_prod.accept_status
      }
      eu_hub_to_eu_prod = {
        id     = aws_vpc_peering_connection.eu_hub_to_eu_prod.id
        status = aws_vpc_peering_connection.eu_hub_to_eu_prod.accept_status
      }
    }
    cross_region_spoke_hub_connections = {
      apac_to_eu_hub = {
        id     = aws_vpc_peering_connection.apac_to_eu_hub.id
        status = aws_vpc_peering_connection.apac_to_eu_hub.accept_status
      }
    }
  }
}

output "peering_connection_summary" {
  description = "Summary of VPC peering connections by type"
  value = {
    total_connections        = 7
    inter_region_connections = 3
    intra_region_connections = 4
    cross_region_connections = 1
  }
}

#===============================================================================
# ROUTE TABLE INFORMATION
#===============================================================================

output "route_table_ids" {
  description = "IDs of all route tables in each VPC"
  value = {
    primary_region = {
      hub_route_table  = data.aws_route_table.hub_vpc_main.id
      prod_route_table = data.aws_route_table.prod_vpc_main.id
      dev_route_table  = data.aws_route_table.dev_vpc_main.id
    }
    secondary_region = {
      dr_hub_route_table  = data.aws_route_table.dr_hub_vpc_main.id
      dr_prod_route_table = data.aws_route_table.dr_prod_vpc_main.id
    }
    eu_region = {
      eu_hub_route_table  = data.aws_route_table.eu_hub_vpc_main.id
      eu_prod_route_table = data.aws_route_table.eu_prod_vpc_main.id
    }
    apac_region = {
      apac_route_table = data.aws_route_table.apac_vpc_main.id
    }
  }
}

output "routing_architecture" {
  description = "Description of the implemented routing architecture"
  value = {
    topology    = "hub-and-spoke with inter-region mesh"
    description = "Multi-region architecture with regional hubs providing transit routing for local spokes"
    features = [
      "Inter-region hub-to-hub connectivity",
      "Intra-region hub-and-spoke topology",
      "Cross-region spoke-to-hub for compliance routing",
      "Transit routing through regional hubs",
      "Intelligent routing with broad CIDR ranges"
    ]
  }
}

#===============================================================================
# DNS AND RESOLUTION INFORMATION
#===============================================================================

output "route53_resolver_info" {
  description = "Route 53 Resolver configuration information"
  value = var.enable_route53_resolver ? {
    resolver_rule_id     = aws_route53_resolver_rule.internal_domain[0].id
    internal_domain_name = var.internal_domain_name
    associated_vpcs = [
      aws_vpc.hub_vpc.id,
      aws_vpc.prod_vpc.id,
      aws_vpc.dev_vpc.id
    ]
    status = "enabled"
  } : {
    status = "disabled"
  }
}

#===============================================================================
# MONITORING AND LOGGING INFORMATION
#===============================================================================

output "monitoring_configuration" {
  description = "Monitoring and logging configuration details"
  value = {
    flow_logs = var.enable_flow_logs ? {
      status           = "enabled"
      log_group_name   = var.enable_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
      traffic_type     = var.flow_logs_traffic_type
      retention_days   = var.cloudwatch_log_retention_days
      iam_role_arn     = var.enable_flow_logs ? aws_iam_role.vpc_flow_logs_role[0].arn : null
    } : {
      status = "disabled"
    }
    cloudwatch_alarms = var.enable_cloudwatch_monitoring ? {
      route53_resolver_alarm = var.enable_route53_resolver ? aws_cloudwatch_metric_alarm.route53_resolver_query_failures[0].alarm_name : null
      vpc_peering_alarm      = aws_cloudwatch_metric_alarm.vpc_peering_failures[0].alarm_name
    } : {
      status = "disabled"
    }
  }
}

#===============================================================================
# CONNECTIVITY TESTING INFORMATION
#===============================================================================

output "connectivity_test_commands" {
  description = "Commands to test connectivity between regions"
  value = {
    vpc_peering_status_check = "aws ec2 describe-vpc-peering-connections --region ${var.primary_region} --query 'VpcPeeringConnections[*].[VpcPeeringConnectionId,Status.Code]' --output table"
    route_table_verification = {
      hub_routes  = "aws ec2 describe-route-tables --region ${var.primary_region} --route-table-ids ${data.aws_route_table.hub_vpc_main.id} --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,VpcPeeringConnectionId,State]' --output table"
      apac_routes = "aws ec2 describe-route-tables --region ${var.apac_region} --route-table-ids ${data.aws_route_table.apac_vpc_main.id} --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,VpcPeeringConnectionId,State]' --output table"
    }
    dns_resolution_test = var.enable_route53_resolver ? "aws route53resolver list-resolver-rule-associations --region ${var.primary_region} --query 'ResolverRuleAssociations[*].[VpcId,ResolverRuleId,Status]' --output table" : "Route 53 Resolver not enabled"
  }
}

#===============================================================================
# COST ESTIMATION AND OPTIMIZATION
#===============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    vpc_peering_connections = {
      total_connections = 7
      estimated_cost    = "$70-105 per month (data transfer dependent)"
    }
    route53_resolver = var.enable_route53_resolver ? {
      status         = "enabled"
      estimated_cost = "$10-30 per month (query volume dependent)"
    } : {
      status = "disabled"
      cost   = "$0"
    }
    cloudwatch_logs = var.enable_flow_logs ? {
      status         = "enabled"
      estimated_cost = "$5-50 per month (log volume dependent)"
    } : {
      status = "disabled"
      cost   = "$0"
    }
    total_estimated_monthly_cost = "$85-185 per month (excluding data transfer)"
    cost_optimization_notes = [
      "Monitor cross-region data transfer charges",
      "Consider regional traffic patterns for optimization",
      "Review VPC Flow Logs retention policies",
      "Implement cost allocation tags for tracking"
    ]
  }
}

#===============================================================================
# SECURITY AND COMPLIANCE INFORMATION
#===============================================================================

output "security_configuration" {
  description = "Security and compliance configuration details"
  value = {
    encryption = {
      vpc_peering_traffic = "Encrypted in transit by default"
      dns_queries         = "Route 53 Resolver uses encrypted queries"
    }
    network_segmentation = {
      vpc_isolation    = "Each VPC provides network isolation"
      routing_control  = "Hub-and-spoke topology provides centralized routing control"
      transit_security = "All traffic flows through designated hub VPCs"
    }
    monitoring = {
      flow_logs        = var.enable_flow_logs ? "Enabled for network monitoring" : "Disabled"
      cloudwatch_alarms = var.enable_cloudwatch_monitoring ? "Enabled for proactive monitoring" : "Disabled"
    }
    compliance_features = [
      "Data sovereignty support through regional hubs",
      "Traffic path control for regulatory compliance",
      "Comprehensive logging for audit trails",
      "Network segmentation for data classification"
    ]
  }
}

#===============================================================================
# NEXT STEPS AND RECOMMENDATIONS
#===============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate_actions = [
      "Verify all VPC peering connections are in 'active' state",
      "Test connectivity between regions using test instances",
      "Configure security groups for application-specific access",
      "Set up CloudWatch dashboards for network monitoring"
    ]
    application_deployment = [
      "Deploy test instances in each subnet for connectivity validation",
      "Configure application load balancers for multi-region access",
      "Implement DNS records for service discovery",
      "Set up monitoring for application-specific metrics"
    ]
    ongoing_maintenance = [
      "Monitor cross-region data transfer costs",
      "Review and optimize routing paths based on traffic patterns",
      "Update route tables as new VPCs are added",
      "Conduct regular disaster recovery testing"
    ]
  }
}

output "documentation_links" {
  description = "Useful documentation links for managing this infrastructure"
  value = {
    aws_vpc_peering       = "https://docs.aws.amazon.com/vpc/latest/peering/"
    route_tables          = "https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html"
    route53_resolver      = "https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html"
    vpc_flow_logs         = "https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html"
    cloudwatch_monitoring = "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/"
    multi_region_best_practices = "https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html"
  }
}