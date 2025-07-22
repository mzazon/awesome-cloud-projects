# =============================================================================
# DNS Security Monitoring Infrastructure
# Route 53 Resolver DNS Firewall, CloudWatch, Lambda, and SNS
# =============================================================================

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get default VPC if none specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Local values for computed resources
locals {
  suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_string.suffix.result
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id

  common_tags = {
    Project     = "dns-security-monitoring"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# SNS Topic for Security Alerts
# =============================================================================

resource "aws_sns_topic" "dns_security_alerts" {
  name         = "dns-security-alerts-${local.suffix}"
  display_name = "DNS Security Alerts"

  tags = merge(local.common_tags, {
    Name = "dns-security-alerts-${local.suffix}"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.dns_security_alerts.arn
  protocol  = "email"
  endpoint  = var.email_address
}

# =============================================================================
# Route 53 Resolver DNS Firewall
# =============================================================================

# DNS Firewall Domain List for malicious domains
resource "aws_route53_resolver_firewall_domain_list" "malicious_domains" {
  name    = "malicious-domains-${local.suffix}"
  domains = var.malicious_domains

  tags = merge(local.common_tags, {
    Name = "malicious-domains-${local.suffix}"
  })
}

# DNS Firewall Rule Group
resource "aws_route53_resolver_firewall_rule_group" "dns_security_rules" {
  name = "dns-security-rules-${local.suffix}"

  tags = merge(local.common_tags, {
    Name = "dns-security-rules-${local.suffix}"
  })
}

# DNS Firewall Rule for blocking malicious domains
resource "aws_route53_resolver_firewall_rule" "block_malicious_domains" {
  name                    = "block-malicious-domains"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.dns_security_rules.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.malicious_domains.id
  priority                = 100
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
}

# Associate DNS Firewall Rule Group with VPC
resource "aws_route53_resolver_firewall_rule_group_association" "vpc_association" {
  name                   = "vpc-dns-security-${local.suffix}"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.dns_security_rules.id
  vpc_id                 = local.vpc_id
  priority               = 101

  tags = merge(local.common_tags, {
    Name = "vpc-dns-security-${local.suffix}"
  })
}

# =============================================================================
# CloudWatch Logging for DNS Queries
# =============================================================================

# CloudWatch Log Group for DNS queries
resource "aws_cloudwatch_log_group" "dns_security_logs" {
  name              = "/aws/route53resolver/dns-security-${local.suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "dns-security-logs-${local.suffix}"
  })
}

# Route 53 Resolver Query Log Configuration
resource "aws_route53_resolver_query_log_config" "dns_security_logging" {
  name            = "dns-security-logs-${local.suffix}"
  destination_arn = aws_cloudwatch_log_group.dns_security_logs.arn

  tags = merge(local.common_tags, {
    Name = "dns-security-logs-${local.suffix}"
  })
}

# Associate Query Log Configuration with VPC
resource "aws_route53_resolver_query_log_config_association" "vpc_logging" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.dns_security_logging.id
  resource_id                  = local.vpc_id
}

# =============================================================================
# Lambda Function for Automated Threat Response
# =============================================================================

# Lambda execution role
resource "aws_iam_role" "dns_security_lambda_role" {
  name = "dns-security-lambda-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "dns-security-lambda-role-${local.suffix}"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.dns_security_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/dns-security-function.zip"
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_description = message['AlarmDescription']
        metric_name = message['Trigger']['MetricName']
        
        # Create detailed alert message
        alert_message = f"""
DNS Security Alert Triggered

Alarm: {alarm_name}
Description: {alarm_description}
Metric: {metric_name}
Timestamp: {datetime.now().isoformat()}
Account: {context.invoked_function_arn.split(':')[4]}
Region: {context.invoked_function_arn.split(':')[3]}

Recommended Actions:
1. Review DNS query logs for suspicious patterns
2. Investigate source IP addresses and instances
3. Update DNS Firewall rules if needed
4. Consider blocking additional domains or IP ranges

This alert was generated automatically by the DNS Security Monitoring system.
"""
        
        # Log the event for audit trail
        logger.info(f"DNS security event processed: {alarm_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DNS security alert processed successfully',
                'alarm': alarm_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing DNS security alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "dns-security-function.py"
  }
}

# Lambda function
resource "aws_lambda_function" "dns_security_response" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "dns-security-response-${local.suffix}"
  role            = aws_iam_role.dns_security_lambda_role.arn
  handler         = "dns-security-function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  tags = merge(local.common_tags, {
    Name = "dns-security-response-${local.suffix}"
  })
}

# SNS subscription for Lambda function
resource "aws_sns_topic_subscription" "lambda_alerts" {
  topic_arn = aws_sns_topic.dns_security_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.dns_security_response.arn
}

# Lambda permission for SNS to invoke function
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dns_security_response.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.dns_security_alerts.arn
}

# =============================================================================
# CloudWatch Alarms for DNS Threat Detection
# =============================================================================

# Alarm for high rate of blocked DNS queries
resource "aws_cloudwatch_metric_alarm" "dns_high_block_rate" {
  alarm_name          = "DNS-High-Block-Rate-${local.suffix}"
  alarm_description   = "High rate of blocked DNS queries detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueryCount"
  namespace           = "AWS/Route53Resolver"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.blocked_query_threshold
  alarm_actions       = [aws_sns_topic.dns_security_alerts.arn]

  dimensions = {
    FirewallRuleGroupId = aws_route53_resolver_firewall_rule_group.dns_security_rules.id
  }

  tags = merge(local.common_tags, {
    Name = "DNS-High-Block-Rate-${local.suffix}"
  })
}

# Alarm for unusual DNS query volume patterns
resource "aws_cloudwatch_metric_alarm" "dns_unusual_volume" {
  alarm_name          = "DNS-Unusual-Volume-${local.suffix}"
  alarm_description   = "Unusual DNS query volume detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "QueryCount"
  namespace           = "AWS/Route53Resolver"
  period              = "900"
  statistic           = "Sum"
  threshold           = var.unusual_volume_threshold
  alarm_actions       = [aws_sns_topic.dns_security_alerts.arn]

  dimensions = {
    VpcId = local.vpc_id
  }

  tags = merge(local.common_tags, {
    Name = "DNS-Unusual-Volume-${local.suffix}"
  })
}