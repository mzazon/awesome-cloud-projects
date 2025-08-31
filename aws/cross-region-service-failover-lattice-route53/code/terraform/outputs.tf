# Infrastructure Outputs for Cross-Region Service Failover
# These outputs provide key information about the deployed infrastructure
# for validation, testing, and integration with other systems

# ============================================================================
# General Configuration Outputs
# ============================================================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.current_account_id
}

output "deployment_regions" {
  description = "AWS regions where infrastructure is deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }
}

# ============================================================================
# VPC and Networking Outputs
# ============================================================================

output "vpc_ids" {
  description = "VPC IDs for both regions"
  value = {
    primary   = var.create_vpc_resources ? aws_vpc.primary[0].id : var.existing_primary_vpc_id
    secondary = var.create_vpc_resources ? aws_vpc.secondary[0].id : var.existing_secondary_vpc_id
  }
}

output "vpc_cidr_blocks" {
  description = "CIDR blocks for VPCs in both regions"
  value = {
    primary   = var.primary_vpc_cidr
    secondary = var.secondary_vpc_cidr
  }
}

output "subnet_ids" {
  description = "Subnet IDs for both regions"
  value = {
    primary   = var.create_vpc_resources ? aws_subnet.primary[*].id : var.existing_primary_subnet_ids
    secondary = var.create_vpc_resources ? aws_subnet.secondary[*].id : var.existing_secondary_subnet_ids
  }
}

output "internet_gateway_ids" {
  description = "Internet Gateway IDs for both regions"
  value = var.create_vpc_resources ? {
    primary   = aws_internet_gateway.primary[0].id
    secondary = aws_internet_gateway.secondary[0].id
  } : null
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "lambda_execution_role" {
  description = "IAM role for Lambda function execution"
  value = {
    name = aws_iam_role.lambda_execution_role.name
    arn  = aws_iam_role.lambda_execution_role.arn
  }
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_functions" {
  description = "Lambda function details for both regions"
  value = {
    primary = {
      function_name = aws_lambda_function.health_check_primary.function_name
      function_arn  = aws_lambda_function.health_check_primary.arn
      runtime       = aws_lambda_function.health_check_primary.runtime
      timeout       = aws_lambda_function.health_check_primary.timeout
      memory_size   = aws_lambda_function.health_check_primary.memory_size
      region        = var.primary_region
    }
    secondary = {
      function_name = aws_lambda_function.health_check_secondary.function_name
      function_arn  = aws_lambda_function.health_check_secondary.arn
      runtime       = aws_lambda_function.health_check_secondary.runtime
      timeout       = aws_lambda_function.health_check_secondary.timeout
      memory_size   = aws_lambda_function.health_check_secondary.memory_size
      region        = var.secondary_region
    }
  }
}

# ============================================================================
# VPC Lattice Service Network Outputs
# ============================================================================

output "service_networks" {
  description = "VPC Lattice service network details for both regions"
  value = {
    primary = {
      id        = aws_vpclattice_service_network.primary.id
      arn       = aws_vpclattice_service_network.primary.arn
      name      = aws_vpclattice_service_network.primary.name
      auth_type = aws_vpclattice_service_network.primary.auth_type
      region    = var.primary_region
    }
    secondary = {
      id        = aws_vpclattice_service_network.secondary.id
      arn       = aws_vpclattice_service_network.secondary.arn
      name      = aws_vpclattice_service_network.secondary.name
      auth_type = aws_vpclattice_service_network.secondary.auth_type
      region    = var.secondary_region
    }
  }
}

# ============================================================================
# VPC Lattice Service Outputs
# ============================================================================

output "vpclattice_services" {
  description = "VPC Lattice service details for both regions"
  value = {
    primary = {
      id        = aws_vpclattice_service.primary.id
      arn       = aws_vpclattice_service.primary.arn
      name      = aws_vpclattice_service.primary.name
      dns_name  = aws_vpclattice_service.primary.dns_entry[0].domain_name
      auth_type = aws_vpclattice_service.primary.auth_type
      status    = aws_vpclattice_service.primary.status
      region    = var.primary_region
    }
    secondary = {
      id        = aws_vpclattice_service.secondary.id
      arn       = aws_vpclattice_service.secondary.arn
      name      = aws_vpclattice_service.secondary.name
      dns_name  = aws_vpclattice_service.secondary.dns_entry[0].domain_name
      auth_type = aws_vpclattice_service.secondary.auth_type
      status    = aws_vpclattice_service.secondary.status
      region    = var.secondary_region
    }
  }
}

output "vpclattice_service_urls" {
  description = "HTTPS URLs for VPC Lattice services"
  value = {
    primary   = "https://${aws_vpclattice_service.primary.dns_entry[0].domain_name}"
    secondary = "https://${aws_vpclattice_service.secondary.dns_entry[0].domain_name}"
  }
}

# ============================================================================
# VPC Lattice Target Group Outputs
# ============================================================================

output "target_groups" {
  description = "VPC Lattice target group details for both regions"
  value = {
    primary = {
      id     = aws_vpclattice_target_group.primary.id
      arn    = aws_vpclattice_target_group.primary.arn
      name   = aws_vpclattice_target_group.primary.name
      type   = aws_vpclattice_target_group.primary.type
      status = aws_vpclattice_target_group.primary.status
      region = var.primary_region
    }
    secondary = {
      id     = aws_vpclattice_target_group.secondary.id
      arn    = aws_vpclattice_target_group.secondary.arn
      name   = aws_vpclattice_target_group.secondary.name
      type   = aws_vpclattice_target_group.secondary.type
      status = aws_vpclattice_target_group.secondary.status
      region = var.secondary_region
    }
  }
}

# ============================================================================
# Route53 Health Check Outputs
# ============================================================================

output "health_checks" {
  description = "Route53 health check details for both regions"
  value = {
    primary = {
      id                = aws_route53_health_check.primary.id
      arn               = aws_route53_health_check.primary.arn
      fqdn              = aws_route53_health_check.primary.fqdn
      type              = aws_route53_health_check.primary.type
      port              = aws_route53_health_check.primary.port
      resource_path     = aws_route53_health_check.primary.resource_path
      failure_threshold = aws_route53_health_check.primary.failure_threshold
      request_interval  = aws_route53_health_check.primary.request_interval
    }
    secondary = {
      id                = aws_route53_health_check.secondary.id
      arn               = aws_route53_health_check.secondary.arn
      fqdn              = aws_route53_health_check.secondary.fqdn
      type              = aws_route53_health_check.secondary.type
      port              = aws_route53_health_check.secondary.port
      resource_path     = aws_route53_health_check.secondary.resource_path
      failure_threshold = aws_route53_health_check.secondary.failure_threshold
      request_interval  = aws_route53_health_check.secondary.request_interval
    }
  }
}

# ============================================================================
# Route53 DNS Outputs
# ============================================================================

output "hosted_zone" {
  description = "Route53 hosted zone details"
  value = var.create_hosted_zone ? {
    id           = aws_route53_zone.main[0].zone_id
    name         = aws_route53_zone.main[0].name
    name_servers = aws_route53_zone.main[0].name_servers
    arn          = aws_route53_zone.main[0].arn
  } : {
    id = var.existing_hosted_zone_id
  }
}

output "dns_records" {
  description = "DNS failover record details"
  value = {
    domain_name = local.domain_name
    ttl         = var.dns_record_ttl
    primary = {
      name           = aws_route53_record.primary.name
      type           = aws_route53_record.primary.type
      set_identifier = aws_route53_record.primary.set_identifier
      failover_type  = aws_route53_record.primary.failover_routing_policy[0].type
      records        = aws_route53_record.primary.records
      health_check_id = aws_route53_record.primary.health_check_id
    }
    secondary = {
      name           = aws_route53_record.secondary.name
      type           = aws_route53_record.secondary.type
      set_identifier = aws_route53_record.secondary.set_identifier
      failover_type  = aws_route53_record.secondary.failover_routing_policy[0].type
      records        = aws_route53_record.secondary.records
    }
  }
}

output "application_endpoint" {
  description = "Main application endpoint for external access"
  value = {
    url         = "https://${local.domain_name}"
    domain_name = local.domain_name
    hosted_zone_id = local.hosted_zone_id
  }
}

# ============================================================================
# CloudWatch Alarm Outputs
# ============================================================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarm details for health monitoring"
  value = var.enable_cloudwatch_alarms ? {
    primary = {
      alarm_name = aws_cloudwatch_metric_alarm.primary_health_check[0].alarm_name
      arn        = aws_cloudwatch_metric_alarm.primary_health_check[0].arn
      region     = var.primary_region
    }
    secondary = {
      alarm_name = aws_cloudwatch_metric_alarm.secondary_health_check[0].alarm_name
      arn        = aws_cloudwatch_metric_alarm.secondary_health_check[0].arn
      region     = var.secondary_region
    }
  } : null
}

# ============================================================================
# Testing and Validation Outputs
# ============================================================================

output "validation_commands" {
  description = "Commands for testing and validating the deployment"
  value = {
    test_primary_health = "curl -k https://${aws_vpclattice_service.primary.dns_entry[0].domain_name}"
    test_secondary_health = "curl -k https://${aws_vpclattice_service.secondary.dns_entry[0].domain_name}"
    test_dns_resolution = "dig ${local.domain_name} CNAME"
    test_application_endpoint = "curl -k https://${local.domain_name}"
    check_health_status_primary = "aws route53 get-health-check --health-check-id ${aws_route53_health_check.primary.id} --query 'StatusList[0].Status'"
    check_health_status_secondary = "aws route53 get-health-check --health-check-id ${aws_route53_health_check.secondary.id} --query 'StatusList[0].Status'"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring the deployed infrastructure"
  value = {
    route53_health_checks = "https://console.aws.amazon.com/route53/healthchecks/home"
    cloudwatch_alarms_primary = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#alarmsV2:"
    cloudwatch_alarms_secondary = "https://${var.secondary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.secondary_region}#alarmsV2:"
    vpc_lattice_services = "https://console.aws.amazon.com/vpc/home#Services:"
  }
}

# ============================================================================
# Cost Estimation Outputs
# ============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for deployed resources"
  value = {
    vpc_lattice_service_networks = "~$2.00/month per service network (2 regions)"
    vpc_lattice_services = "~$0.025/hour per service + data processing charges"
    lambda_functions = "Pay per request (first 1M requests free monthly)"
    route53_health_checks = "~$0.75/month per health check (2 health checks)"
    route53_hosted_zone = "~$0.50/month per hosted zone"
    cloudwatch_alarms = "~$0.30/month per alarm (2 alarms)"
    estimated_total = "~$15-25/month for basic usage (excluding data transfer)"
    note = "Costs may vary based on usage patterns and data transfer"
  }
}

# ============================================================================
# Cleanup Information
# ============================================================================

output "cleanup_order" {
  description = "Recommended order for manually cleaning up resources if needed"
  value = [
    "1. Delete Route53 DNS records",
    "2. Delete Route53 health checks", 
    "3. Delete Route53 hosted zone (if created)",
    "4. Delete VPC Lattice service associations",
    "5. Delete VPC Lattice listeners",
    "6. Delete VPC Lattice services",
    "7. Delete VPC Lattice target group attachments",
    "8. Delete VPC Lattice target groups",
    "9. Delete VPC Lattice service network associations",
    "10. Delete VPC Lattice service networks",
    "11. Delete Lambda functions",
    "12. Delete IAM role and policies",
    "13. Delete CloudWatch alarms",
    "14. Delete VPC resources (if created)"
  ]
}

# ============================================================================
# Next Steps and Enhancement Ideas
# ============================================================================

output "enhancement_ideas" {
  description = "Suggestions for extending this infrastructure"
  value = {
    multi_region_active_active = "Implement weighted routing for active-active deployment"
    database_integration = "Add RDS with cross-region read replicas"
    monitoring_dashboard = "Create CloudWatch dashboard for centralized monitoring"
    automation = "Add SNS notifications and Lambda-based automated responses"
    security = "Implement WAF rules and enhanced IAM policies"
    testing = "Add synthetic monitoring with CloudWatch Synthetics"
  }
}