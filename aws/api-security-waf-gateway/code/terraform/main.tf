# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Construct unique names for resources
  web_acl_name     = "${var.project_name}-acl-${random_string.suffix.result}"
  api_name         = "${var.api_name}-${random_string.suffix.result}"
  log_group_name   = "/aws/waf/${local.web_acl_name}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "api-access-waf-gateway"
  }
}

# CloudWatch Log Group for WAF logging
resource "aws_cloudwatch_log_group" "waf_logs" {
  count             = var.enable_waf_logging ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "WAF Logs for ${local.web_acl_name}"
  })
}

# AWS WAF Web ACL for API protection
resource "aws_wafv2_web_acl" "api_protection" {
  name        = local.web_acl_name
  description = "Web ACL for API Gateway protection with rate limiting and geo-blocking"
  scope       = "REGIONAL"

  # Default action: allow requests that don't match any rules
  default_action {
    allow {}
  }

  # Rule 1: Rate limiting to prevent DDoS attacks
  rule {
    name     = "RateLimitRule"
    priority = 1

    override_action {
      none {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    action {
      block {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Geographic blocking (conditional)
  dynamic "rule" {
    for_each = var.enable_geo_blocking && length(var.blocked_countries) > 0 ? [1] : []
    
    content {
      name     = "GeoBlockRule"
      priority = 2

      override_action {
        none {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      action {
        block {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "GeoBlockRule"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 3: AWS Managed Rules - Core Rule Set (common web exploits)
  rule {
    name     = "AWSManagedRulesCoreRuleSet"
    priority = 3

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
      metric_name                = "AWSManagedRulesCoreRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 4

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
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(local.common_tags, {
    Name = local.web_acl_name
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  count                   = var.enable_waf_logging ? 1 : 0
  resource_arn            = aws_wafv2_web_acl.api_protection.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs[0].arn]

  depends_on = [aws_cloudwatch_log_group.waf_logs]
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "protected_api" {
  name        = local.api_name
  description = "Test API protected by AWS WAF"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name = local.api_name
  })
}

# API Gateway Resource for /test endpoint
resource "aws_api_gateway_resource" "test_resource" {
  rest_api_id = aws_api_gateway_rest_api.protected_api.id
  parent_id   = aws_api_gateway_rest_api.protected_api.root_resource_id
  path_part   = "test"
}

# API Gateway Method (GET)
resource "aws_api_gateway_method" "test_get" {
  rest_api_id   = aws_api_gateway_rest_api.protected_api.id
  resource_id   = aws_api_gateway_resource.test_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration (Mock)
resource "aws_api_gateway_integration" "test_integration" {
  rest_api_id = aws_api_gateway_rest_api.protected_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_get.http_method
  type        = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# API Gateway Method Response
resource "aws_api_gateway_method_response" "test_response" {
  rest_api_id = aws_api_gateway_rest_api.protected_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_get.http_method
  status_code = "200"
  
  response_models = {
    "application/json" = "Empty"
  }
}

# API Gateway Integration Response
resource "aws_api_gateway_integration_response" "test_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.protected_api.id
  resource_id = aws_api_gateway_resource.test_resource.id
  http_method = aws_api_gateway_method.test_get.http_method
  status_code = aws_api_gateway_method_response.test_response.status_code
  
  response_templates = {
    "application/json" = jsonencode({
      message   = "Hello from protected API!"
      timestamp = "$context.requestTime"
      sourceIp  = "$context.identity.sourceIp"
      userAgent = "$context.identity.userAgent"
    })
  }
  
  depends_on = [aws_api_gateway_integration.test_integration]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.protected_api.id
  
  # Force new deployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.test_resource.id,
      aws_api_gateway_method.test_get.id,
      aws_api_gateway_integration.test_integration.id,
      aws_api_gateway_integration_response.test_integration_response.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [
    aws_api_gateway_method.test_get,
    aws_api_gateway_integration.test_integration,
    aws_api_gateway_integration_response.test_integration_response,
  ]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.protected_api.id
  stage_name    = var.api_stage_name
  description   = "Production stage with WAF protection"
  
  # Enable detailed CloudWatch monitoring
  xray_tracing_enabled = var.enable_detailed_monitoring
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      error          = "$context.error.message"
      responseLength = "$context.responseLength"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.api_name}-${var.api_stage_name}"
  })
  
  depends_on = [aws_cloudwatch_log_group.api_logs]
}

# CloudWatch Log Group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "API Gateway Logs for ${local.api_name}"
  })
}

# Associate WAF Web ACL with API Gateway Stage
resource "aws_wafv2_web_acl_association" "api_waf_association" {
  resource_arn = aws_api_gateway_stage.api_stage.arn
  web_acl_arn  = aws_wafv2_web_acl.api_protection.arn
}

# CloudWatch Alarms for monitoring

# Alarm for high blocked request rate
resource "aws_cloudwatch_metric_alarm" "high_blocked_requests" {
  alarm_name          = "${local.web_acl_name}-high-blocked-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "This metric monitors blocked requests by WAF"
  alarm_actions       = []

  dimensions = {
    WebACL = local.web_acl_name
    Rule   = "ALL"
    Region = data.aws_region.current.name
  }

  tags = merge(local.common_tags, {
    Name = "WAF High Blocked Requests Alarm"
  })
}

# Alarm for API Gateway 4XX errors
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  alarm_name          = "${local.api_name}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 4XX errors from API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName   = local.api_name
    Stage     = var.api_stage_name
  }

  tags = merge(local.common_tags, {
    Name = "API Gateway 4XX Errors Alarm"
  })
}

# Alarm for API Gateway high latency
resource "aws_cloudwatch_metric_alarm" "api_high_latency" {
  alarm_name          = "${local.api_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000"
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = []

  dimensions = {
    ApiName   = local.api_name
    Stage     = var.api_stage_name
  }

  tags = merge(local.common_tags, {
    Name = "API Gateway High Latency Alarm"
  })
}