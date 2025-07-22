# =============================================================================
# Outputs for DNS Security Monitoring Infrastructure
# =============================================================================

output "vpc_id" {
  description = "VPC ID where DNS firewall is deployed"
  value       = local.vpc_id
}

output "dns_firewall_rule_group_id" {
  description = "DNS Firewall Rule Group ID"
  value       = aws_route53_resolver_firewall_rule_group.dns_security_rules.id
}

output "dns_firewall_rule_group_arn" {
  description = "DNS Firewall Rule Group ARN"
  value       = aws_route53_resolver_firewall_rule_group.dns_security_rules.arn
}

output "dns_firewall_domain_list_id" {
  description = "DNS Firewall Domain List ID"
  value       = aws_route53_resolver_firewall_domain_list.malicious_domains.id
}

output "dns_firewall_domain_list_arn" {
  description = "DNS Firewall Domain List ARN"
  value       = aws_route53_resolver_firewall_domain_list.malicious_domains.arn
}

output "firewall_vpc_association_id" {
  description = "DNS Firewall VPC Association ID"
  value       = aws_route53_resolver_firewall_rule_group_association.vpc_association.id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for DNS queries"
  value       = aws_cloudwatch_log_group.dns_security_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch Log Group ARN for DNS queries"
  value       = aws_cloudwatch_log_group.dns_security_logs.arn
}

output "query_log_config_id" {
  description = "Route 53 Resolver Query Log Configuration ID"
  value       = aws_route53_resolver_query_log_config.dns_security_logging.id
}

output "query_log_config_arn" {
  description = "Route 53 Resolver Query Log Configuration ARN"
  value       = aws_route53_resolver_query_log_config.dns_security_logging.arn
}

output "lambda_function_name" {
  description = "Lambda function name for DNS security response"
  value       = aws_lambda_function.dns_security_response.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN for DNS security response"
  value       = aws_lambda_function.dns_security_response.arn
}

output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.dns_security_lambda_role.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for DNS security alerts"
  value       = aws_sns_topic.dns_security_alerts.arn
}

output "sns_topic_name" {
  description = "SNS topic name for DNS security alerts"
  value       = aws_sns_topic.dns_security_alerts.name
}

output "cloudwatch_alarm_high_block_rate" {
  description = "CloudWatch alarm name for high DNS block rate"
  value       = aws_cloudwatch_metric_alarm.dns_high_block_rate.alarm_name
}

output "cloudwatch_alarm_unusual_volume" {
  description = "CloudWatch alarm name for unusual DNS volume"
  value       = aws_cloudwatch_metric_alarm.dns_unusual_volume.alarm_name
}

output "malicious_domains_blocked" {
  description = "List of malicious domains configured for blocking"
  value       = var.malicious_domains
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# =============================================================================
# Validation and Testing Outputs
# =============================================================================

output "validation_commands" {
  description = "Commands to validate the DNS security deployment"
  value = {
    check_firewall_status = "aws route53resolver get-firewall-rule-group --firewall-rule-group-id ${aws_route53_resolver_firewall_rule_group.dns_security_rules.id}"
    check_vpc_association = "aws route53resolver list-firewall-rule-group-associations --query \"FirewallRuleGroupAssociations[?VpcId=='${local.vpc_id}'].{Id:Id,Status:Status}\""
    check_alarm_status = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.dns_high_block_rate.alarm_name}"
    test_sns_topic = "aws sns publish --topic-arn ${aws_sns_topic.dns_security_alerts.arn} --message \"Test DNS security alert notification\""
    view_recent_logs = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.dns_security_logs.name} --start-time $(date -d '1 hour ago' +%s)000 --filter-pattern BLOCK"
  }
}

output "cleanup_reminders" {
  description = "Important notes for cleanup and cost management"
  value = {
    email_subscription = "Remember to confirm the email subscription to receive DNS security alerts"
    cost_monitoring = "Monitor Route 53 Resolver DNS Firewall costs based on VPC associations and query volume"
    log_retention = "CloudWatch logs are retained for ${var.log_retention_days} days and will be automatically deleted"
    firewall_rules = "DNS Firewall rules are charged per VPC association and query volume - review pricing documentation"
  }
}