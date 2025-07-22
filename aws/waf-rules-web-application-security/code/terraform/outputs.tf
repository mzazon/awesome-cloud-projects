# Outputs for AWS WAF Web Application Security

# WAF Web ACL Information
output "waf_web_acl_id" {
  description = "The ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.webapp_security.id
}

output "waf_web_acl_arn" {
  description = "The ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.webapp_security.arn
}

output "waf_web_acl_name" {
  description = "The name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.webapp_security.name
}

output "waf_web_acl_capacity" {
  description = "The capacity units consumed by the WAF Web ACL"
  value       = aws_wafv2_web_acl.webapp_security.capacity
}

# IP Set Information
output "ip_set_id" {
  description = "The ID of the IP Set for blocked IPs"
  value       = var.enable_ip_blocking ? aws_wafv2_ip_set.blocked_ips[0].id : null
}

output "ip_set_arn" {
  description = "The ARN of the IP Set for blocked IPs"
  value       = var.enable_ip_blocking ? aws_wafv2_ip_set.blocked_ips[0].arn : null
}

output "ip_set_name" {
  description = "The name of the IP Set for blocked IPs"
  value       = var.enable_ip_blocking ? aws_wafv2_ip_set.blocked_ips[0].name : null
}

# Regex Pattern Set Information
output "regex_pattern_set_id" {
  description = "The ID of the Regex Pattern Set for custom threat detection"
  value       = var.enable_custom_patterns ? aws_wafv2_regex_pattern_set.suspicious_patterns[0].id : null
}

output "regex_pattern_set_arn" {
  description = "The ARN of the Regex Pattern Set for custom threat detection"
  value       = var.enable_custom_patterns ? aws_wafv2_regex_pattern_set.suspicious_patterns[0].arn : null
}

output "regex_pattern_set_name" {
  description = "The name of the Regex Pattern Set for custom threat detection"
  value       = var.enable_custom_patterns ? aws_wafv2_regex_pattern_set.suspicious_patterns[0].name : null
}

# CloudWatch Log Group Information
output "waf_log_group_name" {
  description = "The name of the CloudWatch Log Group for WAF logs"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "waf_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group for WAF logs"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].arn : null
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "The ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.waf_security_alerts.arn
}

output "sns_topic_name" {
  description = "The name of the SNS topic for security alerts"
  value       = aws_sns_topic.waf_security_alerts.name
}

# CloudWatch Alarm Information
output "cloudwatch_alarm_name" {
  description = "The name of the CloudWatch alarm for blocked requests"
  value       = aws_cloudwatch_metric_alarm.high_blocked_requests.alarm_name
}

output "cloudwatch_alarm_arn" {
  description = "The ARN of the CloudWatch alarm for blocked requests"
  value       = aws_cloudwatch_metric_alarm.high_blocked_requests.arn
}

# CloudWatch Dashboard Information
output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard for WAF monitoring"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.waf_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "The URL of the CloudWatch dashboard for WAF monitoring"
  value       = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.waf_monitoring[0].dashboard_name}" : null
}

# WAF Rules Summary
output "waf_rules_summary" {
  description = "Summary of enabled WAF rules"
  value = {
    common_rule_set       = "enabled"
    known_bad_inputs      = "enabled"
    sqli_rule_set        = "enabled"
    bot_control          = var.enable_bot_control ? "enabled" : "disabled"
    rate_limiting        = var.enable_rate_limiting ? "enabled" : "disabled"
    geo_blocking         = var.enable_geo_blocking ? "enabled" : "disabled"
    ip_blocking          = var.enable_ip_blocking ? "enabled" : "disabled"
    custom_patterns      = var.enable_custom_patterns ? "enabled" : "disabled"
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of WAF configuration"
  value = {
    waf_name              = aws_wafv2_web_acl.webapp_security.name
    scope                 = "CLOUDFRONT"
    rate_limit_threshold  = var.rate_limit_threshold
    blocked_countries     = var.blocked_countries
    blocked_ip_count      = length(var.blocked_ip_addresses)
    logging_enabled       = var.enable_waf_logging
    dashboard_created     = var.create_dashboard
    email_notifications   = var.sns_email_endpoint != "" ? "configured" : "not configured"
  }
}

# CloudFront Association Instructions
output "cloudfront_association_instructions" {
  description = "Instructions for associating WAF with CloudFront distribution"
  value = {
    web_acl_arn = aws_wafv2_web_acl.webapp_security.arn
    cli_command = "aws cloudfront update-distribution --id YOUR_DISTRIBUTION_ID --distribution-config 'WebACLId=${aws_wafv2_web_acl.webapp_security.arn}'"
    console_url = "https://console.aws.amazon.com/cloudfront/v3/home#/distributions"
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring WAF activity"
  value = {
    waf_console     = "https://console.aws.amazon.com/wafv2/homev2/web-acl/${aws_wafv2_web_acl.webapp_security.name}/${aws_wafv2_web_acl.webapp_security.id}/overview?region=${data.aws_region.current.name}"
    cloudwatch_logs = var.enable_waf_logging ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.waf_logs[0].name, "/", "$252F")}" : null
    cloudwatch_metrics = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS$252FWAFV2"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for WAF management"
  value = {
    regular_review    = "Review WAF logs and metrics weekly to identify attack patterns"
    rule_tuning      = "Monitor false positives and adjust rules as needed"
    ip_set_updates   = "Update blocked IP sets based on threat intelligence"
    rate_limit_tuning = "Adjust rate limiting thresholds based on legitimate traffic patterns"
    geo_blocking_review = "Review and update blocked countries list based on business requirements"
    bot_monitoring   = "Monitor bot control metrics to ensure legitimate bots are not blocked"
  }
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing WAF costs"
  value = {
    log_retention   = "Adjust log retention period based on compliance requirements"
    rule_efficiency = "Use most specific rules first to reduce processing time"
    bot_control     = "Bot Control rules have additional costs - enable only if needed"
    sampling        = "Use sampling for allowed requests to reduce log volume"
    monitoring      = "Monitor request volumes and adjust rules to minimize costs"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step_1 = "Associate WAF with your CloudFront distribution or Application Load Balancer"
    step_2 = "Configure SNS email subscription if not provided during deployment"
    step_3 = "Test WAF rules with controlled traffic to validate configuration"
    step_4 = "Set up additional monitoring and alerting based on your requirements"
    step_5 = "Review and customize rule priorities based on your application needs"
    step_6 = "Implement automated IP set updates based on threat intelligence feeds"
  }
}