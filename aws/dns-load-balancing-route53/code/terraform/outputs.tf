# ===================================================================
# Route 53 Outputs
# ===================================================================

output "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "hosted_zone_name_servers" {
  description = "Name servers for the hosted zone"
  value       = aws_route53_zone.main.name_servers
}

output "domain_name" {
  description = "Primary domain name"
  value       = var.domain_name
}

output "subdomain_endpoints" {
  description = "Map of subdomain endpoints for different routing policies"
  value = {
    main        = local.full_domain
    latency     = var.enable_routing_policies.latency ? "latency.${local.full_domain}" : null
    geo         = var.enable_routing_policies.geolocation ? "geo.${local.full_domain}" : null
    failover    = var.enable_routing_policies.failover ? "failover.${local.full_domain}" : null
    multivalue  = var.enable_routing_policies.multivalue ? "multivalue.${local.full_domain}" : null
  }
}

# ===================================================================
# Load Balancer Outputs
# ===================================================================

output "load_balancers" {
  description = "Application Load Balancer details for all regions"
  value = {
    primary = {
      arn      = aws_lb.primary.arn
      dns_name = aws_lb.primary.dns_name
      zone_id  = aws_lb.primary.zone_id
      region   = var.primary_region
    }
    secondary = {
      arn      = aws_lb.secondary.arn
      dns_name = aws_lb.secondary.dns_name
      zone_id  = aws_lb.secondary.zone_id
      region   = var.secondary_region
    }
    tertiary = {
      arn      = aws_lb.tertiary.arn
      dns_name = aws_lb.tertiary.dns_name
      zone_id  = aws_lb.tertiary.zone_id
      region   = var.tertiary_region
    }
  }
}

output "target_groups" {
  description = "Target group details for all regions"
  value = {
    primary = {
      arn    = aws_lb_target_group.primary.arn
      name   = aws_lb_target_group.primary.name
      region = var.primary_region
    }
    secondary = {
      arn    = aws_lb_target_group.secondary.arn
      name   = aws_lb_target_group.secondary.name
      region = var.secondary_region
    }
    tertiary = {
      arn    = aws_lb_target_group.tertiary.arn
      name   = aws_lb_target_group.tertiary.name
      region = var.tertiary_region
    }
  }
}

# ===================================================================
# Health Check Outputs
# ===================================================================

output "health_checks" {
  description = "Route 53 health check details for all regions"
  value = {
    primary = {
      id       = aws_route53_health_check.primary.id
      fqdn     = aws_route53_health_check.primary.fqdn
      region   = var.primary_region
    }
    secondary = {
      id       = aws_route53_health_check.secondary.id
      fqdn     = aws_route53_health_check.secondary.fqdn
      region   = var.secondary_region
    }
    tertiary = {
      id       = aws_route53_health_check.tertiary.id
      fqdn     = aws_route53_health_check.tertiary.fqdn
      region   = var.tertiary_region
    }
  }
}

# ===================================================================
# Network Infrastructure Outputs
# ===================================================================

output "vpc_details" {
  description = "VPC details for all regions"
  value = {
    primary = {
      vpc_id           = module.primary_vpc.vpc_id
      public_subnets   = module.primary_vpc.public_subnets
      region           = var.primary_region
      cidr_block       = module.primary_vpc.vpc_cidr_block
    }
    secondary = {
      vpc_id           = module.secondary_vpc.vpc_id
      public_subnets   = module.secondary_vpc.public_subnets
      region           = var.secondary_region
      cidr_block       = module.secondary_vpc.vpc_cidr_block
    }
    tertiary = {
      vpc_id           = module.tertiary_vpc.vpc_id
      public_subnets   = module.tertiary_vpc.public_subnets
      region           = var.tertiary_region
      cidr_block       = module.tertiary_vpc.vpc_cidr_block
    }
  }
}

output "security_groups" {
  description = "Security group details for all regions"
  value = {
    primary = {
      id     = aws_security_group.primary_alb.id
      name   = aws_security_group.primary_alb.name
      region = var.primary_region
    }
    secondary = {
      id     = aws_security_group.secondary_alb.id
      name   = aws_security_group.secondary_alb.name
      region = var.secondary_region
    }
    tertiary = {
      id     = aws_security_group.tertiary_alb.id
      name   = aws_security_group.tertiary_alb.name
      region = var.tertiary_region
    }
  }
}

# ===================================================================
# Monitoring and Notifications Outputs
# ===================================================================

output "sns_topic" {
  description = "SNS topic details for health check notifications"
  value = var.enable_health_check_notifications ? {
    arn  = aws_sns_topic.health_check_alerts[0].arn
    name = aws_sns_topic.health_check_alerts[0].name
  } : null
}

# ===================================================================
# Routing Policy Status Outputs
# ===================================================================

output "enabled_routing_policies" {
  description = "Map of enabled Route 53 routing policies"
  value = var.enable_routing_policies
}

output "weighted_routing_distribution" {
  description = "Traffic distribution weights for weighted routing"
  value = var.weighted_routing
}

# ===================================================================
# Deployment Information Outputs
# ===================================================================

output "deployment_info" {
  description = "General deployment information"
  value = {
    environment   = var.environment
    random_suffix = local.random_suffix
    regions = {
      primary   = var.primary_region
      secondary = var.secondary_region
      tertiary  = var.tertiary_region
    }
    vpc_cidr                    = var.vpc_cidr
    health_check_path          = var.health_check_path
    health_check_interval      = var.health_check_interval
    failure_threshold          = var.failure_threshold
    dns_ttl                    = var.dns_ttl
  }
}

# ===================================================================
# Testing and Validation Outputs
# ===================================================================

output "dns_test_commands" {
  description = "DNS testing commands for validation"
  value = {
    weighted_routing = var.enable_routing_policies.weighted ? "dig +short ${local.full_domain} @8.8.8.8" : null
    latency_routing  = var.enable_routing_policies.latency ? "dig +short latency.${local.full_domain} @8.8.8.8" : null
    geo_routing      = var.enable_routing_policies.geolocation ? "dig +short geo.${local.full_domain} @8.8.8.8" : null
    failover_routing = var.enable_routing_policies.failover ? "dig +short failover.${local.full_domain} @8.8.8.8" : null
    multivalue_routing = var.enable_routing_policies.multivalue ? "dig +short multivalue.${local.full_domain} @8.8.8.8" : null
  }
}

output "health_check_urls" {
  description = "Health check URLs for testing endpoint health"
  value = {
    primary   = "http://${aws_lb.primary.dns_name}${var.health_check_path}"
    secondary = "http://${aws_lb.secondary.dns_name}${var.health_check_path}"
    tertiary  = "http://${aws_lb.tertiary.dns_name}${var.health_check_path}"
  }
}

# ===================================================================
# Next Steps Output
# ===================================================================

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Update your domain registrar's name servers to: ${join(", ", aws_route53_zone.main.name_servers)}",
    "2. Deploy your application instances to the target groups in each region",
    "3. Configure health check endpoints (${var.health_check_path}) on your applications",
    "4. Test DNS resolution using the provided test commands",
    var.enable_health_check_notifications && var.notification_email != "" ? "5. Confirm the SNS subscription in your email" : "5. Configure SNS notifications if desired",
    "6. Monitor health check status in the Route 53 console",
    "7. Adjust weighted routing values as needed for your traffic patterns"
  ]
}