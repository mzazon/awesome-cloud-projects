# AWS WAF Web Application Security Infrastructure

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# CloudWatch Log Group for WAF logs
resource "aws_cloudwatch_log_group" "waf_logs" {
  count             = var.enable_waf_logging ? 1 : 0
  name              = "/aws/wafv2/${var.waf_name_prefix}-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "WAF-Logs-${var.waf_name_prefix}-${random_string.suffix.result}"
    Description = "Log group for WAF security events"
  }
}

# IP Set for blocking specific IP addresses
resource "aws_wafv2_ip_set" "blocked_ips" {
  count              = var.enable_ip_blocking ? 1 : 0
  name               = "blocked-ips-${random_string.suffix.result}"
  description        = "IP addresses to block"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.blocked_ip_addresses

  tags = {
    Name        = "Blocked-IPs-${random_string.suffix.result}"
    Description = "IP set for blocking malicious IP addresses"
  }
}

# Regex Pattern Set for custom threat detection
resource "aws_wafv2_regex_pattern_set" "suspicious_patterns" {
  count       = var.enable_custom_patterns ? 1 : 0
  name        = "suspicious-patterns-${random_string.suffix.result}"
  description = "Patterns for detecting common attack signatures"
  scope       = "CLOUDFRONT"

  dynamic "regular_expression" {
    for_each = var.custom_regex_patterns
    content {
      regex_string = regular_expression.value
    }
  }

  tags = {
    Name        = "Suspicious-Patterns-${random_string.suffix.result}"
    Description = "Regex patterns for custom threat detection"
  }
}

# WAF Web ACL with comprehensive security rules
resource "aws_wafv2_web_acl" "webapp_security" {
  name  = "${var.waf_name_prefix}-${random_string.suffix.result}"
  scope = "CLOUDFRONT"
  
  description = "Comprehensive WAF for web application security"

  default_action {
    allow {}
  }

  # AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Known Bad Inputs Rule Set
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - SQL Injection Rule Set
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules - Bot Control Rule Set (conditional)
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []
    content {
      name     = "AWSManagedRulesBotControlRuleSet"
      priority = 4

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "BotControlMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rate Limiting Rule (conditional)
  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []
    content {
      name     = "RateLimitRule"
      priority = var.enable_bot_control ? 5 : 4

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit_threshold
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "RateLimitMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Geographic Blocking Rule (conditional)
  dynamic "rule" {
    for_each = var.enable_geo_blocking ? [1] : []
    content {
      name     = "BlockHighRiskCountries"
      priority = local.geo_blocking_priority

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "GeoBlockMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # IP Blocking Rule (conditional)
  dynamic "rule" {
    for_each = var.enable_ip_blocking ? [1] : []
    content {
      name     = "BlockMaliciousIPs"
      priority = local.ip_blocking_priority

      action {
        block {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.blocked_ips[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IPBlockMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Custom Regex Pattern Matching Rule (conditional)
  dynamic "rule" {
    for_each = var.enable_custom_patterns ? [1] : []
    content {
      name     = "CustomThreatDetection"
      priority = local.custom_patterns_priority

      action {
        block {}
      }

      statement {
        regex_pattern_set_reference_statement {
          arn = aws_wafv2_regex_pattern_set.suspicious_patterns[0].arn
          field_to_match {
            body {
              oversize_handling = "CONTINUE"
            }
          }
          text_transformation {
            priority = 1
            type     = "URL_DECODE"
          }
          text_transformation {
            priority = 2
            type     = "HTML_ENTITY_DECODE"
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "CustomThreatMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.waf_name_prefix}Metric"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.waf_name_prefix}-${random_string.suffix.result}"
    Description = "Comprehensive WAF for web application security"
  }
}

# Local values for dynamic rule priorities
locals {
  base_priority = var.enable_bot_control ? 5 : 4
  geo_blocking_priority = local.base_priority + (var.enable_rate_limiting ? 1 : 0)
  ip_blocking_priority = local.geo_blocking_priority + (var.enable_geo_blocking ? 1 : 0)
  custom_patterns_priority = local.ip_blocking_priority + (var.enable_ip_blocking ? 1 : 0)
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  count                   = var.enable_waf_logging ? 1 : 0
  resource_arn           = aws_wafv2_web_acl.webapp_security.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

  logging_filter {
    default_behavior = "KEEP"

    filter {
      behavior = "KEEP"
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      requirement = "MEETS_ANY"
    }
  }
}

# SNS Topic for Security Alerts
resource "aws_sns_topic" "waf_security_alerts" {
  name         = "waf-security-alerts-${random_string.suffix.result}"
  display_name = "WAF Security Alerts"

  tags = {
    Name        = "WAF-Security-Alerts-${random_string.suffix.result}"
    Description = "SNS topic for WAF security alerts"
  }
}

# SNS Topic Subscription (conditional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.sns_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.waf_security_alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# CloudWatch Alarm for Blocked Requests
resource "aws_cloudwatch_metric_alarm" "high_blocked_requests" {
  alarm_name          = "waf-high-blocked-requests-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "High number of blocked requests detected"
  alarm_actions       = [aws_sns_topic.waf_security_alerts.arn]

  dimensions = {
    WebACL = aws_wafv2_web_acl.webapp_security.name
    Region = data.aws_region.current.name
  }

  tags = {
    Name        = "WAF-High-Blocked-Requests-${random_string.suffix.result}"
    Description = "Alarm for high blocked request volume"
  }
}

# CloudWatch Dashboard for WAF Monitoring
resource "aws_cloudwatch_dashboard" "waf_monitoring" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "WAF-Security-Dashboard-${random_string.suffix.result}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.webapp_security.name, "Region", data.aws_region.current.name],
            [".", "BlockedRequests", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "WAF Request Statistics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", aws_wafv2_web_acl.webapp_security.name, "Region", data.aws_region.current.name, "Rule", "CommonRuleSetMetric"],
            ["...", "KnownBadInputsMetric"],
            ["...", "SQLiRuleSetMetric"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Blocked Requests by Rule"
          period  = 300
        }
      }
    ]
  })
}

# CloudFront Distribution Association (optional)
data "aws_cloudfront_distribution" "existing" {
  count = var.cloudfront_distribution_id != "" ? 1 : 0
  id    = var.cloudfront_distribution_id
}

# Note: CloudFront distribution updates with WAF association require manual intervention
# or a separate process due to Terraform limitations with CloudFront distribution updates