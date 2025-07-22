# Advanced Multi-Service Monitoring Dashboards Infrastructure
# This file creates the complete monitoring infrastructure including Lambda functions,
# CloudWatch dashboards, anomaly detection, and alerting

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming conventions
  resource_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CostCenter  = var.cost_center
  }
}

# ================================
# IAM ROLES AND POLICIES
# ================================

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.resource_prefix}-lambda-role"
  
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
  
  tags = local.common_tags
}

# Attach AWS managed policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for CloudWatch and AWS service access
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ecs:DescribeServices",
          "ecs:DescribeClusters",
          "ecs:ListServices"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:GetDimensionValues"
        ]
        Resource = "*"
      }
    ]
  })
}

# ================================
# SNS TOPICS FOR ALERTS
# ================================

# SNS topic for critical alerts
resource "aws_sns_topic" "critical_alerts" {
  name = "${local.resource_prefix}-critical-alerts"
  
  tags = local.common_tags
}

# SNS topic for warning alerts
resource "aws_sns_topic" "warning_alerts" {
  name = "${local.resource_prefix}-warning-alerts"
  
  tags = local.common_tags
}

# SNS topic for info alerts
resource "aws_sns_topic" "info_alerts" {
  name = "${local.resource_prefix}-info-alerts"
  
  tags = local.common_tags
}

# Email subscription for critical alerts
resource "aws_sns_topic_subscription" "critical_email" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Additional SNS subscriptions (if configured)
resource "aws_sns_topic_subscription" "additional_subscriptions" {
  for_each = {
    for idx, sub in var.additional_sns_subscriptions : "${sub.topic}-${idx}" => sub
  }
  
  topic_arn = each.value.topic == "critical" ? aws_sns_topic.critical_alerts.arn : (
    each.value.topic == "warning" ? aws_sns_topic.warning_alerts.arn : aws_sns_topic.info_alerts.arn
  )
  protocol = each.value.protocol
  endpoint = each.value.endpoint
}

# ================================
# LAMBDA FUNCTIONS
# ================================

# Archive Lambda function code
data "archive_file" "business_metrics_zip" {
  type        = "zip"
  output_path = "/tmp/business-metrics.zip"
  source {
    content = templatefile("${path.module}/templates/business_metrics.py.tpl", {
      environment   = var.environment
      business_unit = var.business_unit
    })
    filename = "business_metrics.py"
  }
}

# Business metrics Lambda function
resource "aws_lambda_function" "business_metrics" {
  filename         = data.archive_file.business_metrics_zip.output_path
  function_name    = "${local.resource_prefix}-business-metrics"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "business_metrics.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.business_metrics_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT   = var.environment
      BUSINESS_UNIT = var.business_unit
      PROJECT_NAME  = var.project_name
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Log Group for business metrics Lambda
resource "aws_cloudwatch_log_group" "business_metrics_logs" {
  name              = "/aws/lambda/${aws_lambda_function.business_metrics.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Archive infrastructure health Lambda function code
data "archive_file" "infrastructure_health_zip" {
  type        = "zip"
  output_path = "/tmp/infrastructure-health.zip"
  source {
    content = templatefile("${path.module}/templates/infrastructure_health.py.tpl", {
      environment = var.environment
    })
    filename = "infrastructure_health.py"
  }
}

# Infrastructure health Lambda function
resource "aws_lambda_function" "infrastructure_health" {
  filename         = data.archive_file.infrastructure_health_zip.output_path
  function_name    = "${local.resource_prefix}-infrastructure-health"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "infrastructure_health.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.infrastructure_health_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Log Group for infrastructure health Lambda
resource "aws_cloudwatch_log_group" "infrastructure_health_logs" {
  name              = "/aws/lambda/${aws_lambda_function.infrastructure_health.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Archive cost monitoring Lambda function code
data "archive_file" "cost_monitoring_zip" {
  type        = "zip"
  output_path = "/tmp/cost-monitoring.zip"
  source {
    content = templatefile("${path.module}/templates/cost_monitoring.py.tpl", {
      environment = var.environment
    })
    filename = "cost_monitoring.py"
  }
}

# Cost monitoring Lambda function
resource "aws_lambda_function" "cost_monitoring" {
  filename         = data.archive_file.cost_monitoring_zip.output_path
  function_name    = "${local.resource_prefix}-cost-monitoring"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "cost_monitoring.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.cost_monitoring_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT  = var.environment
      PROJECT_NAME = var.project_name
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Log Group for cost monitoring Lambda
resource "aws_cloudwatch_log_group" "cost_monitoring_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_monitoring.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ================================
# EVENTBRIDGE RULES AND TARGETS
# ================================

# EventBridge rule for business metrics collection
resource "aws_cloudwatch_event_rule" "business_metrics_schedule" {
  name                = "${local.resource_prefix}-business-metrics"
  description         = "Collect business metrics on schedule"
  schedule_expression = var.metric_collection_schedule
  
  tags = local.common_tags
}

# EventBridge target for business metrics
resource "aws_cloudwatch_event_target" "business_metrics_target" {
  rule      = aws_cloudwatch_event_rule.business_metrics_schedule.name
  target_id = "BusinessMetricsTarget"
  arn       = aws_lambda_function.business_metrics.arn
}

# Lambda permission for EventBridge business metrics
resource "aws_lambda_permission" "allow_eventbridge_business_metrics" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.business_metrics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.business_metrics_schedule.arn
}

# EventBridge rule for infrastructure health checks
resource "aws_cloudwatch_event_rule" "infrastructure_health_schedule" {
  name                = "${local.resource_prefix}-infrastructure-health"
  description         = "Check infrastructure health on schedule"
  schedule_expression = var.infrastructure_health_schedule
  
  tags = local.common_tags
}

# EventBridge target for infrastructure health
resource "aws_cloudwatch_event_target" "infrastructure_health_target" {
  rule      = aws_cloudwatch_event_rule.infrastructure_health_schedule.name
  target_id = "InfrastructureHealthTarget"
  arn       = aws_lambda_function.infrastructure_health.arn
}

# Lambda permission for EventBridge infrastructure health
resource "aws_lambda_permission" "allow_eventbridge_infrastructure_health" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.infrastructure_health.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.infrastructure_health_schedule.arn
}

# EventBridge rule for cost monitoring
resource "aws_cloudwatch_event_rule" "cost_monitoring_schedule" {
  name                = "${local.resource_prefix}-cost-monitoring"
  description         = "Monitor costs on schedule"
  schedule_expression = var.cost_monitoring_schedule
  
  tags = local.common_tags
}

# EventBridge target for cost monitoring
resource "aws_cloudwatch_event_target" "cost_monitoring_target" {
  rule      = aws_cloudwatch_event_rule.cost_monitoring_schedule.name
  target_id = "CostMonitoringTarget"
  arn       = aws_lambda_function.cost_monitoring.arn
}

# Lambda permission for EventBridge cost monitoring
resource "aws_lambda_permission" "allow_eventbridge_cost_monitoring" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_monitoring_schedule.arn
}

# ================================
# CLOUDWATCH ANOMALY DETECTION
# ================================

# Anomaly detector for hourly revenue
resource "aws_cloudwatch_anomaly_detector" "revenue_anomaly" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      metric_stat {
        metric {
          namespace   = "Business/Metrics"
          metric_name = "HourlyRevenue"
          dimensions = {
            Environment  = var.environment
            BusinessUnit = var.business_unit
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# Anomaly detector for API response time
resource "aws_cloudwatch_anomaly_detector" "response_time_anomaly" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      metric_stat {
        metric {
          namespace   = "Business/Metrics"
          metric_name = "APIResponseTime"
          dimensions = {
            Environment = var.environment
            Service     = "api-gateway"
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# Anomaly detector for error rate
resource "aws_cloudwatch_anomaly_detector" "error_rate_anomaly" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      metric_stat {
        metric {
          namespace   = "Business/Metrics"
          metric_name = "ErrorRate"
          dimensions = {
            Environment = var.environment
            Service     = "api-gateway"
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# Anomaly detector for infrastructure health
resource "aws_cloudwatch_anomaly_detector" "infrastructure_health_anomaly" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      metric_stat {
        metric {
          namespace   = "Infrastructure/Health"
          metric_name = "OverallInfrastructureHealth"
          dimensions = {
            Environment = var.environment
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# ================================
# CLOUDWATCH ALARMS
# ================================

# Revenue anomaly alarm
resource "aws_cloudwatch_metric_alarm" "revenue_anomaly_alarm" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-revenue-anomaly"
  comparison_operator = "LessThanLowerThreshold"
  evaluation_periods  = "2"
  threshold_metric_id = "ad1"
  alarm_description   = "Revenue anomaly detected"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]
  treat_missing_data  = "breaching"
  
  metric_query {
    id = "m1"
    metric {
      namespace   = "Business/Metrics"
      metric_name = "HourlyRevenue"
      dimensions = {
        Environment  = var.environment
        BusinessUnit = var.business_unit
      }
      period = 300
      stat   = "Average"
    }
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${var.anomaly_detection_band})"
    label       = "Revenue Anomaly Detection"
    return_data = "true"
  }
  
  tags = local.common_tags
}

# Response time anomaly alarm
resource "aws_cloudwatch_metric_alarm" "response_time_anomaly_alarm" {
  count = var.anomaly_detection_enabled ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-response-time-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = "2"
  threshold_metric_id = "ad1"
  alarm_description   = "API response time anomaly detected"
  alarm_actions       = [aws_sns_topic.warning_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  metric_query {
    id = "m1"
    metric {
      namespace   = "Business/Metrics"
      metric_name = "APIResponseTime"
      dimensions = {
        Environment = var.environment
        Service     = "api-gateway"
      }
      period = 300
      stat   = "Average"
    }
  }
  
  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${var.anomaly_detection_band})"
    label       = "Response Time Anomaly Detection"
    return_data = "true"
  }
  
  tags = local.common_tags
}

# Infrastructure health threshold alarm
resource "aws_cloudwatch_metric_alarm" "infrastructure_health_alarm" {
  alarm_name          = "${local.resource_prefix}-infrastructure-health-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "OverallInfrastructureHealth"
  namespace           = "Infrastructure/Health"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Infrastructure health score below threshold"
  alarm_actions       = [aws_sns_topic.critical_alerts.arn]
  treat_missing_data  = "breaching"
  
  dimensions = {
    Environment = var.environment
  }
  
  tags = local.common_tags
}

# ================================
# CLOUDWATCH DASHBOARDS
# ================================

# Infrastructure monitoring dashboard
resource "aws_cloudwatch_dashboard" "infrastructure_dashboard" {
  dashboard_name = "${local.resource_prefix}-Infrastructure"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Infrastructure/Health", "OverallInfrastructureHealth", "Environment", var.environment],
            ["Business/Health", "CompositeHealthScore", "Environment", var.environment]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "Overall System Health"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", var.sample_resource_config.ecs_service_name],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", var.sample_resource_config.ecs_service_name]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "ECS Service Utilization"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.sample_resource_config.rds_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.sample_resource_config.rds_instance_id],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.sample_resource_config.rds_instance_id]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Performance Metrics"
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
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", var.sample_resource_config.elasticache_cluster],
            ["AWS/ElastiCache", "CacheHits", "CacheClusterId", var.sample_resource_config.elasticache_cluster],
            ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", var.sample_resource_config.elasticache_cluster]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "ElastiCache Performance"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["Infrastructure/Health", "RDSHealthScore", "Service", "RDS", "Environment", var.environment],
            ["Infrastructure/Health", "ElastiCacheHealthScore", "Service", "ElastiCache", "Environment", var.environment],
            ["Infrastructure/Health", "ComputeHealthScore", "Service", "Compute", "Environment", var.environment]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "Service Health Scores"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Business metrics dashboard
resource "aws_cloudwatch_dashboard" "business_dashboard" {
  dashboard_name = "${local.resource_prefix}-Business"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "HourlyRevenue", "Environment", var.environment, "BusinessUnit", var.business_unit]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "Hourly Revenue"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "TransactionCount", "Environment", var.environment, "BusinessUnit", var.business_unit],
            ["Business/Metrics", "ActiveUsers", "Environment", var.environment]
          ]
          period = var.dashboard_period
          stat   = "Sum"
          region = var.aws_region
          title  = "Transaction Volume & Active Users"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "AverageOrderValue", "Environment", var.environment, "BusinessUnit", var.business_unit]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "Average Order Value"
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
            ["Business/Metrics", "APIResponseTime", "Environment", var.environment, "Service", "api-gateway"],
            ["Business/Metrics", "ErrorRate", "Environment", var.environment, "Service", "api-gateway"]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "API Performance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "NPSScore", "Environment", var.environment],
            ["Business/Metrics", "SupportTicketVolume", "Environment", var.environment]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = var.aws_region
          title  = "Customer Satisfaction Metrics"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Executive summary dashboard
resource "aws_cloudwatch_dashboard" "executive_dashboard" {
  dashboard_name = "${local.resource_prefix}-Executive"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["Business/Health", "CompositeHealthScore", "Environment", var.environment],
            ["Infrastructure/Health", "OverallInfrastructureHealth", "Environment", var.environment]
          ]
          period = 3600
          stat   = "Average"
          region = var.aws_region
          title  = "System Health Overview (Last 24 Hours)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "HourlyRevenue", "Environment", var.environment, "BusinessUnit", var.business_unit]
          ]
          period                 = 3600
          stat                   = "Sum"
          region                = var.aws_region
          title                 = "Revenue Trend (24H)"
          view                  = "singleValue"
          setPeriodToTimeRange = true
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "ActiveUsers", "Environment", var.environment]
          ]
          period                 = 3600
          stat                   = "Average"
          region                = var.aws_region
          title                 = "Active Users (24H Avg)"
          view                  = "singleValue"
          setPeriodToTimeRange = true
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "NPSScore", "Environment", var.environment]
          ]
          period                 = 3600
          stat                   = "Average"
          region                = var.aws_region
          title                 = "Customer Satisfaction (NPS)"
          view                  = "singleValue"
          setPeriodToTimeRange = true
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["Business/Metrics", "ErrorRate", "Environment", var.environment, "Service", "api-gateway"]
          ]
          period = 3600
          stat   = "Average"
          region = var.aws_region
          title  = "Error Rate Trend"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.business_metrics.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.business_metrics.function_name]
          ]
          period = 3600
          stat   = "Sum"
          region = var.aws_region
          title  = "Monitoring System Health"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Operations dashboard
resource "aws_cloudwatch_dashboard" "operations_dashboard" {
  dashboard_name = "${local.resource_prefix}-Operations"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.business_metrics_logs.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = var.aws_region
          title  = "Recent Monitoring Errors"
          view   = "table"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.business_metrics.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.business_metrics.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.business_metrics.function_name]
          ]
          period = var.dashboard_period
          stat   = "Sum"
          region = var.aws_region
          title  = "Monitoring Function Health"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesSent", "TopicName", aws_sns_topic.critical_alerts.name],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", aws_sns_topic.critical_alerts.name]
          ]
          period = var.dashboard_period
          stat   = "Sum"
          region = var.aws_region
          title  = "Alert Delivery Status"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["Cost/Management", "DailyCost", "Environment", var.environment],
            ["Cost/Management", "CostTrend", "Environment", var.environment]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
          title  = "Cost Monitoring"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# ================================
# END OF INFRASTRUCTURE DEFINITIONS
# ================================