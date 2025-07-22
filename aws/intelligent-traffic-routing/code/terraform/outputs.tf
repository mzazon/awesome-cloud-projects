# =====================================================
# CLOUDFRONT AND DNS OUTPUTS
# =====================================================

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_url" {
  description = "HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.hosted_zone_id
}

output "hosted_zone_name" {
  description = "Route53 hosted zone name"
  value       = local.domain_name
}

output "route53_name_servers" {
  description = "Route53 hosted zone name servers (for domain delegation)"
  value       = var.create_hosted_zone ? aws_route53_zone.main[0].name_servers : null
}

# =====================================================
# DNS RECORD OUTPUTS
# =====================================================

output "weighted_routing_domain" {
  description = "Domain name for weighted routing testing"
  value       = "app.${local.domain_name}"
}

output "geolocation_routing_domain" {
  description = "Domain name for geolocation routing testing"
  value       = "geo.${local.domain_name}"
}

# =====================================================
# REGIONAL INFRASTRUCTURE OUTPUTS
# =====================================================

output "primary_region_info" {
  description = "Primary region infrastructure information"
  value = {
    region           = var.primary_region
    vpc_id          = module.vpc_primary.vpc_id
    alb_arn         = module.vpc_primary.alb_arn
    alb_dns_name    = module.vpc_primary.alb_dns_name
    alb_zone_id     = module.vpc_primary.alb_zone_id
    target_group_arn = module.vpc_primary.target_group_arn
    health_check_id = aws_route53_health_check.primary.id
  }
}

output "secondary_region_info" {
  description = "Secondary region infrastructure information"
  value = {
    region           = var.secondary_region
    vpc_id          = module.vpc_secondary.vpc_id
    alb_arn         = module.vpc_secondary.alb_arn
    alb_dns_name    = module.vpc_secondary.alb_dns_name
    alb_zone_id     = module.vpc_secondary.alb_zone_id
    target_group_arn = module.vpc_secondary.target_group_arn
    health_check_id = aws_route53_health_check.secondary.id
  }
}

output "tertiary_region_info" {
  description = "Tertiary region infrastructure information"
  value = {
    region           = var.tertiary_region
    vpc_id          = module.vpc_tertiary.vpc_id
    alb_arn         = module.vpc_tertiary.alb_arn
    alb_dns_name    = module.vpc_tertiary.alb_dns_name
    alb_zone_id     = module.vpc_tertiary.alb_zone_id
    target_group_arn = module.vpc_tertiary.target_group_arn
    health_check_id = aws_route53_health_check.tertiary.id
  }
}

# =====================================================
# HEALTH CHECK OUTPUTS
# =====================================================

output "health_checks" {
  description = "Route53 health check information"
  value = {
    primary = {
      id     = aws_route53_health_check.primary.id
      fqdn   = aws_route53_health_check.primary.fqdn
      status = "Check Route53 console for current status"
    }
    secondary = {
      id     = aws_route53_health_check.secondary.id
      fqdn   = aws_route53_health_check.secondary.fqdn
      status = "Check Route53 console for current status"
    }
    tertiary = {
      id     = aws_route53_health_check.tertiary.id
      fqdn   = aws_route53_health_check.tertiary.fqdn
      status = "Check Route53 console for current status"
    }
  }
}

# =====================================================
# S3 FALLBACK OUTPUTS
# =====================================================

output "fallback_bucket_info" {
  description = "S3 fallback bucket information"
  value = var.create_fallback_bucket ? {
    bucket_name                = aws_s3_bucket.fallback[0].id
    bucket_arn                = aws_s3_bucket.fallback[0].arn
    bucket_regional_domain_name = aws_s3_bucket.fallback[0].bucket_regional_domain_name
    fallback_content_url       = "https://${aws_cloudfront_distribution.main.domain_name}/index.html"
  } : null
}

# =====================================================
# MONITORING OUTPUTS
# =====================================================

output "monitoring_info" {
  description = "Monitoring and alerting information"
  value = var.enable_cloudwatch_alarms ? {
    sns_topic_arn = aws_sns_topic.alerts[0].arn
    dashboard_url = "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Global-LoadBalancer-${random_id.suffix.hex}"
    alarms = {
      primary_health   = aws_cloudwatch_metric_alarm.health_check_primary[0].alarm_name
      secondary_health = aws_cloudwatch_metric_alarm.health_check_secondary[0].alarm_name
      tertiary_health  = aws_cloudwatch_metric_alarm.health_check_tertiary[0].alarm_name
      cloudfront_errors = aws_cloudwatch_metric_alarm.cloudfront_errors[0].alarm_name
    }
  } : null
}

# =====================================================
# PROJECT INFORMATION OUTPUTS
# =====================================================

output "project_info" {
  description = "Project configuration and identifiers"
  value = {
    project_name   = var.project_name
    project_suffix = local.project_suffix
    environment    = var.environment
    random_id      = random_id.suffix.hex
    regions = {
      primary   = var.primary_region
      secondary = var.secondary_region
      tertiary  = var.tertiary_region
    }
  }
}

# =====================================================
# TESTING OUTPUTS
# =====================================================

output "testing_commands" {
  description = "Commands to test the global load balancing setup"
  value = {
    cloudfront_test = "curl -I https://${aws_cloudfront_distribution.main.domain_name}/"
    weighted_routing_test = "nslookup app.${local.domain_name}"
    geo_routing_test = "nslookup geo.${local.domain_name}"
    health_status_check = "aws route53 get-health-check --health-check-id ${aws_route53_health_check.primary.id}"
    cloudfront_cache_invalidation = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'"
  }
}

# =====================================================
# COST ESTIMATION OUTPUTS
# =====================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the infrastructure"
  value = {
    notice = "Costs vary by region and usage. This is a rough estimate."
    estimated_monthly_cost = {
      ec2_instances = "~$${var.desired_capacity * 3 * 15}/month (${var.desired_capacity} instances per region × 3 regions × ~$15/instance)"
      load_balancers = "~$${3 * 20}/month (3 ALBs × ~$20/month each)"
      route53_health_checks = "~$${3 * 0.50 * 30}/month (3 health checks × $0.50 per health check per month)"
      cloudfront = "~$5-50/month (depends on data transfer)"
      total_estimated = "~$${var.desired_capacity * 3 * 15 + 3 * 20 + 3 * 0.50 * 30 + 25}/month (excluding data transfer)"
    }
    cost_optimization_tips = [
      "Use smaller instance types for testing (t3.micro is included in free tier)",
      "Reduce health check frequency from 30s to 30s (current) or consider 30s for production",
      "Use CloudFront PriceClass_100 for cost optimization (current setting)",
      "Monitor and delete unused resources regularly"
    ]
  }
}

# =====================================================
# NEXT STEPS OUTPUTS
# =====================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate_tasks = [
      "Wait 5-10 minutes for CloudFront distribution to deploy fully",
      "Test the CloudFront URL: https://${aws_cloudfront_distribution.main.domain_name}",
      "Verify health checks are passing in Route53 console",
      "Test DNS resolution for weighted and geo routing"
    ]
    configuration_tasks = var.create_hosted_zone ? [
      "Update your domain's name servers to: ${join(", ", aws_route53_zone.main[0].name_servers)}",
      "Configure SNS email subscription if desired: aws sns subscribe --topic-arn ${var.enable_cloudwatch_alarms ? aws_sns_topic.alerts[0].arn : "TOPIC_ARN"} --protocol email --notification-endpoint your-email@example.com"
    ] : [
      "Configure SNS email subscription if desired"
    ]
    testing_scenarios = [
      "Simulate regional failure by modifying Auto Scaling Group desired capacity to 0",
      "Test CloudFront origin failover by blocking ALB traffic",
      "Monitor CloudWatch dashboard during failure scenarios",
      "Verify fallback S3 content is served when all origins fail"
    ]
    production_considerations = [
      "Replace demo domain with your actual domain name",
      "Configure SSL/TLS certificates for custom domains",
      "Set up proper monitoring and alerting thresholds",
      "Implement backup and disaster recovery procedures",
      "Review and adjust health check intervals based on requirements"
    ]
  }
}