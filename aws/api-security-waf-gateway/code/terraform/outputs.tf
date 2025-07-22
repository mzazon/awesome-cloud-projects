# Output values for the API Gateway and WAF security infrastructure

output "api_gateway_url" {
  description = "The invoke URL for the API Gateway REST API"
  value       = "https://${aws_api_gateway_rest_api.protected_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "api_gateway_test_endpoint" {
  description = "The complete URL for the test endpoint"
  value       = "https://${aws_api_gateway_rest_api.protected_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/test"
}

output "api_gateway_id" {
  description = "The ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.protected_api.id
}

output "api_gateway_name" {
  description = "The name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.protected_api.name
}

output "api_gateway_stage_name" {
  description = "The name of the API Gateway stage"
  value       = aws_api_gateway_stage.api_stage.stage_name
}

output "waf_web_acl_id" {
  description = "The ID of the AWS WAF Web ACL"
  value       = aws_wafv2_web_acl.api_protection.id
}

output "waf_web_acl_name" {
  description = "The name of the AWS WAF Web ACL"
  value       = aws_wafv2_web_acl.api_protection.name
}

output "waf_web_acl_arn" {
  description = "The ARN of the AWS WAF Web ACL"
  value       = aws_wafv2_web_acl.api_protection.arn
}

output "waf_log_group_name" {
  description = "The name of the CloudWatch log group for WAF logs"
  value       = var.enable_waf_logging ? aws_cloudwatch_log_group.waf_logs[0].name : null
}

output "api_log_group_name" {
  description = "The name of the CloudWatch log group for API Gateway logs"
  value       = aws_cloudwatch_log_group.api_logs.name
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names created for monitoring"
  value = [
    aws_cloudwatch_metric_alarm.high_blocked_requests.alarm_name,
    aws_cloudwatch_metric_alarm.api_4xx_errors.alarm_name,
    aws_cloudwatch_metric_alarm.api_high_latency.alarm_name
  ]
}

output "waf_rules_summary" {
  description = "Summary of WAF rules configured"
  value = {
    rate_limit_enabled    = true
    rate_limit_threshold  = var.rate_limit
    geo_blocking_enabled  = var.enable_geo_blocking
    blocked_countries     = var.enable_geo_blocking ? var.blocked_countries : []
    managed_rules = [
      "AWSManagedRulesCommonRuleSet",
      "AWSManagedRulesKnownBadInputsRuleSet"
    ]
  }
}

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    waf_protection_enabled = true
    rate_limiting_enabled  = true
    geo_blocking_enabled   = var.enable_geo_blocking
    logging_enabled        = var.enable_waf_logging
    managed_rules_enabled  = true
    cloudwatch_monitoring  = true
  }
}

output "testing_commands" {
  description = "Useful commands for testing the protected API"
  value = {
    test_api_endpoint = "curl -X GET '${output.api_gateway_test_endpoint.value}'"
    view_waf_logs = var.enable_waf_logging ? "aws logs describe-log-streams --log-group-name '${aws_cloudwatch_log_group.waf_logs[0].name}'" : "WAF logging not enabled"
    check_waf_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/WAFV2 --metric-name AllowedRequests --dimensions Name=WebACL,Value='${aws_wafv2_web_acl.api_protection.name}' --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum"
  }
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "api-access-waf-gateway"
  }
}

output "cost_optimization_notes" {
  description = "Information about cost optimization opportunities"
  value = {
    waf_monthly_cost = "Approximately $1.00 per Web ACL + $1.00 per rule + $0.60 per million requests"
    api_gateway_cost = "Pay per request and data transfer - no fixed monthly costs"
    cloudwatch_cost  = "Log storage costs based on retention period and volume"
    recommendations = [
      "Monitor request volume to optimize rate limiting thresholds",
      "Review blocked countries list periodically",
      "Consider shorter log retention for cost savings",
      "Use count action during rule testing to avoid blocking legitimate traffic"
    ]
  }
}