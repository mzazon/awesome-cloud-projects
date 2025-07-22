# Output values for AWS WAF Rate Limiting Infrastructure

# WAF Web ACL Information
output "web_acl_id" {
  description = "The ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_arn" {
  description = "The ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_name" {
  description = "The name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.name
}

output "web_acl_scope" {
  description = "The scope of the WAF Web ACL (CLOUDFRONT or REGIONAL)"
  value       = aws_wafv2_web_acl.main.scope
}

output "web_acl_capacity" {
  description = "The web ACL capacity units (WCU) currently being used by this web ACL"
  value       = aws_wafv2_web_acl.main.capacity
}

# Rate Limiting Configuration
output "rate_limit_threshold" {
  description = "The configured rate limit threshold (requests per 5 minutes)"
  value       = var.rate_limit_threshold
}

output "rate_limit_rule_name" {
  description = "The name of the rate limiting rule"
  value       = "${local.web_acl_name}-rate-limit"
}

# CloudWatch Logging Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for WAF logs"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for WAF logs"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

output "waf_logging_enabled" {
  description = "Whether WAF logging is enabled"
  value       = var.enable_waf_logging
}

# CloudWatch Dashboard Information
output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for WAF monitoring"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.waf_security[0].dashboard_name : null
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.waf_security[0].dashboard_name}" : null
}

# Security Rules Configuration
output "enabled_managed_rules" {
  description = "List of enabled AWS managed rule groups"
  value = compact([
    var.enable_ip_reputation_rule ? "AWSManagedRulesAmazonIpReputationList" : "",
    var.enable_known_bad_inputs_rule ? "AWSManagedRulesKnownBadInputsRuleSet" : "",
    var.enable_core_rule_set ? "AWSManagedRulesCommonRuleSet" : ""
  ])
}

output "ip_reputation_rule_enabled" {
  description = "Whether IP reputation rule is enabled"
  value       = var.enable_ip_reputation_rule
}

output "known_bad_inputs_rule_enabled" {
  description = "Whether known bad inputs rule is enabled"
  value       = var.enable_known_bad_inputs_rule
}

output "core_rule_set_enabled" {
  description = "Whether Core Rule Set (OWASP Top 10) is enabled"
  value       = var.enable_core_rule_set
}

# Association Information
output "alb_association_created" {
  description = "Whether ALB association was created"
  value       = var.application_load_balancer_arn != "" && var.waf_scope == "REGIONAL"
}

output "cloudfront_association_available" {
  description = "Whether CloudFront association is available (scope must be CLOUDFRONT)"
  value       = var.waf_scope == "CLOUDFRONT"
}

# Monitoring and Metrics
output "cloudwatch_metrics_enabled" {
  description = "Whether CloudWatch metrics are enabled for WAF rules"
  value       = var.enable_cloudwatch_metrics
}

output "sample_requests_enabled" {
  description = "Whether sample request capturing is enabled"
  value       = var.enable_sample_requests
}

output "metric_names" {
  description = "CloudWatch metric names for WAF rules"
  value = {
    rate_limit_rule     = "${local.web_acl_name}-RateLimitRule"
    ip_reputation_rule  = var.enable_ip_reputation_rule ? "${local.web_acl_name}-IPReputationRule" : null
    known_bad_inputs    = var.enable_known_bad_inputs_rule ? "${local.web_acl_name}-KnownBadInputsRule" : null
    core_rule_set       = var.enable_core_rule_set ? "${local.web_acl_name}-CoreRuleSetRule" : null
  }
}

# Environment and Tagging
output "environment" {
  description = "Environment name used for resource tagging"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for WAF resources"
  value = {
    web_acl                    = "$1.00 per Web ACL"
    rate_limit_rule           = "$0.60 per rule"
    ip_reputation_rule        = var.enable_ip_reputation_rule ? "$0.60 per rule" : "$0.00"
    known_bad_inputs_rule     = var.enable_known_bad_inputs_rule ? "$0.60 per rule" : "$0.00"
    core_rule_set_rule        = var.enable_core_rule_set ? "$0.60 per rule" : "$0.00"
    request_processing        = "$0.60 per million web requests"
    cloudwatch_logs           = var.enable_waf_logging ? "Variable based on log volume and retention" : "$0.00"
    cloudwatch_dashboard      = var.create_cloudwatch_dashboard ? "$3.00 per dashboard per month" : "$0.00"
    note                      = "Actual costs depend on traffic volume and usage patterns"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the WAF deployment"
  value = {
    check_web_acl = "aws wafv2 get-web-acl --scope ${aws_wafv2_web_acl.main.scope} --id ${aws_wafv2_web_acl.main.id} --region ${local.waf_region}"
    list_rules    = "aws wafv2 get-web-acl --scope ${aws_wafv2_web_acl.main.scope} --id ${aws_wafv2_web_acl.main.id} --region ${local.waf_region} --query 'WebACL.Rules[*].{Name:Name,Priority:Priority}' --output table"
    check_logging = var.enable_waf_logging ? "aws wafv2 get-logging-configuration --resource-arn ${aws_wafv2_web_acl.main.arn} --region ${local.waf_region}" : "Logging not enabled"
    view_metrics  = "aws cloudwatch get-metric-statistics --namespace AWS/WAFV2 --metric-name BlockedRequests --dimensions Name=WebACL,Value=${aws_wafv2_web_acl.main.name} Name=Region,Value=${var.waf_scope == "CLOUDFRONT" ? "CloudFront" : data.aws_region.current.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum --region ${local.waf_region}"
  }
}

# Integration Examples
output "integration_examples" {
  description = "Examples for integrating WAF with other services"
  value = {
    cloudfront_integration = "To associate with CloudFront: Update distribution config to include WebACLId: ${aws_wafv2_web_acl.main.arn}"
    alb_integration       = var.waf_scope == "REGIONAL" ? "ALB association available - provide ALB ARN in variable 'application_load_balancer_arn'" : "Change scope to REGIONAL for ALB integration"
    api_gateway_integration = var.waf_scope == "REGIONAL" ? "Use aws_wafv2_web_acl_association resource with API Gateway stage ARN" : "Change scope to REGIONAL for API Gateway integration"
  }
}