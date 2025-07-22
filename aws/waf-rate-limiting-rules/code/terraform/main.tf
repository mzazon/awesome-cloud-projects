# Main Terraform configuration for AWS WAF Rate Limiting Rules

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# CloudWatch Log Group for WAF logs
resource "aws_cloudwatch_log_group" "waf_logs" {
  count = var.enable_waf_logging ? 1 : 0
  
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "${local.web_acl_name}-logs"
    Description = "WAF logs for rate limiting and security monitoring"
  })
}

# AWS WAF Web Access Control List (ACL)
resource "aws_wafv2_web_acl" "main" {
  # Use us-east-1 provider for CloudFront scope, otherwise use default
  provider = var.waf_scope == "CLOUDFRONT" ? aws.us-east-1 : aws
  
  name        = local.web_acl_name
  description = "Web ACL for rate limiting and comprehensive security protection"
  scope       = var.waf_scope

  # Default action - allow all traffic unless explicitly blocked by rules
  default_action {
    allow {}
  }

  # Rule 1: Rate Limiting Protection
  rule {
    name     = "${local.web_acl_name}-rate-limit"
    priority = 1

    # Rate-based rule to prevent DDoS and abuse
    statement {
      rate_based_statement {
        limit              = var.rate_limit_threshold
        aggregate_key_type = "IP"
        
        # Optional: Add scope down statement to apply rate limiting only to specific paths
        # scope_down_statement {
        #   byte_match_statement {
        #     search_string = "/api/"
        #     field_to_match {
        #       uri_path {}
        #     }
        #     text_transformation {
        #       priority = 0
        #       type     = "LOWERCASE"
        #     }
        #     positional_constraint = "CONTAINS"
        #   }
        # }
      }
    }

    # Block action for rate limit violations
    action {
      block {}
    }

    # Visibility configuration for monitoring and sampling
    visibility_config {
      sampled_requests_enabled   = var.enable_sample_requests
      cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics
      metric_name                = "${local.web_acl_name}-RateLimitRule"
    }
  }

  # Rule 2: IP Reputation Protection (AWS Managed Rule)
  dynamic "rule" {
    for_each = var.enable_ip_reputation_rule ? [1] : []
    
    content {
      name     = "${local.web_acl_name}-ip-reputation"
      priority = 2

      # Override action for managed rule group
      override_action {
        none {}
      }

      # AWS IP Reputation List managed rule group
      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }

      # Visibility configuration
      visibility_config {
        sampled_requests_enabled   = var.enable_sample_requests
        cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics
        metric_name                = "${local.web_acl_name}-IPReputationRule"
      }
    }
  }

  # Rule 3: Known Bad Inputs Protection (Optional)
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs_rule ? [1] : []
    
    content {
      name     = "${local.web_acl_name}-known-bad-inputs"
      priority = 3

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
        sampled_requests_enabled   = var.enable_sample_requests
        cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics
        metric_name                = "${local.web_acl_name}-KnownBadInputsRule"
      }
    }
  }

  # Rule 4: Core Rule Set - OWASP Top 10 Protection (Optional)
  dynamic "rule" {
    for_each = var.enable_core_rule_set ? [1] : []
    
    content {
      name     = "${local.web_acl_name}-core-rule-set"
      priority = 4

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
        sampled_requests_enabled   = var.enable_sample_requests
        cloudwatch_metrics_enabled = var.enable_cloudwatch_metrics
        metric_name                = "${local.web_acl_name}-CoreRuleSetRule"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.web_acl_name
    Description = "WAF Web ACL for rate limiting and security protection"
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf_logging ? 1 : 0
  
  # Use us-east-1 provider for CloudFront scope
  provider = var.waf_scope == "CLOUDFRONT" ? aws.us-east-1 : aws

  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

  # Redact sensitive fields from logs for privacy and security
  dynamic "redacted_fields" {
    for_each = var.redacted_fields
    content {
      single_header {
        name = redacted_fields.value
      }
    }
  }

  # Logging filter to reduce log volume (optional)
  logging_filter {
    default_behavior = "KEEP"

    # Example filter: Only log blocked requests and sampled allowed requests
    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"
      
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      
      condition {
        action_condition {
          action = "ALLOW"
        }
      }
    }
  }

  depends_on = [aws_cloudwatch_log_group.waf_logs]
}

# CloudWatch Dashboard for WAF Monitoring
resource "aws_cloudwatch_dashboard" "waf_security" {
  count = var.create_cloudwatch_dashboard ? 1 : 0

  dashboard_name = local.dashboard_name

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
            ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Region", var.waf_scope == "CLOUDFRONT" ? "CloudFront" : data.aws_region.current.name, "Rule", "ALL"],
            [".", "BlockedRequests", ".", ".", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.waf_region
          period  = 300
          stat    = "Sum"
          title   = "WAF Allowed vs Blocked Requests"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Region", var.waf_scope == "CLOUDFRONT" ? "CloudFront" : data.aws_region.current.name, "Rule", "${local.web_acl_name}-rate-limit"],
            var.enable_ip_reputation_rule ? [".", ".", ".", ".", ".", ".", ".", "${local.web_acl_name}-ip-reputation"] : null,
            var.enable_known_bad_inputs_rule ? [".", ".", ".", ".", ".", ".", ".", "${local.web_acl_name}-known-bad-inputs"] : null,
            var.enable_core_rule_set ? [".", ".", ".", ".", ".", ".", ".", "${local.web_acl_name}-core-rule-set"] : null
          ]
          view   = "timeSeries"
          region = local.waf_region
          period = 300
          stat   = "Sum"
          title  = "Blocked Requests by Rule"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 6
        height = 6

        properties = {
          metrics = [
            ["AWS/WAFV2", "SampledRequests", "WebACL", aws_wafv2_web_acl.main.name, "Region", var.waf_scope == "CLOUDFRONT" ? "CloudFront" : data.aws_region.current.name, "Rule", "ALL"]
          ]
          view   = "timeSeries"
          region = local.waf_region
          period = 300
          stat   = "Sum"
          title  = "Sampled Requests"
        }
      },
      {
        type   = "log"
        x      = 6
        y      = 12
        width  = 6
        height = 6

        properties = {
          query = var.enable_waf_logging ? "SOURCE '${aws_cloudwatch_log_group.waf_logs[0].name}' | fields @timestamp, action, terminatingRuleId, httpRequest.clientIp\n| filter action = \"BLOCK\"\n| stats count() by terminatingRuleId\n| sort count desc" : ""
          region = data.aws_region.current.name
          title  = "Top Blocking Rules (Last Hour)"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = local.dashboard_name
    Description = "CloudWatch dashboard for WAF security monitoring"
  })
}

# Optional: Associate WAF with CloudFront Distribution
resource "aws_cloudfront_distribution" "waf_association" {
  count = var.cloudfront_distribution_id != "" ? 1 : 0

  # This is a data reference - in practice, you would use existing distribution
  # and update its web_acl_id property
  
  # Note: This resource is for demonstration only
  # In real scenarios, you would modify an existing CloudFront distribution
  # or use data sources to reference existing resources
  
  # web_acl_id = aws_wafv2_web_acl.main.arn

  tags = local.common_tags
}

# Optional: Associate WAF with Application Load Balancer
resource "aws_wafv2_web_acl_association" "alb" {
  count = var.application_load_balancer_arn != "" && var.waf_scope == "REGIONAL" ? 1 : 0

  resource_arn = var.application_load_balancer_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}