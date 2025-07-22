# Lambda Monitoring Module for Multi-Region Aurora DSQL Application
# This module creates CloudWatch alarms and dashboards for Lambda functions

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# =============================================================================
# CLOUDWATCH ALARMS FOR LAMBDA FUNCTION
# =============================================================================

# Lambda function error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${var.function_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function error rate"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  tags = var.tags
}

# Lambda function duration alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "10000"  # 10 seconds
  alarm_description   = "This metric monitors Lambda function duration"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  tags = var.tags
}

# Lambda function throttles alarm
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function throttles"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  tags = var.tags
}

# Lambda function concurrent executions alarm
resource "aws_cloudwatch_metric_alarm" "lambda_concurrent_executions" {
  alarm_name          = "${var.function_name}-concurrent-executions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "100"
  alarm_description   = "This metric monitors Lambda function concurrent executions"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  
  dimensions = {
    FunctionName = var.function_name
  }
  
  tags = var.tags
}

# Lambda function invocation count (for anomaly detection)
resource "aws_cloudwatch_metric_alarm" "lambda_invocation_anomaly" {
  alarm_name                = "${var.function_name}-invocation-anomaly"
  comparison_operator       = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods        = "3"
  threshold_metric_id       = "ad1"
  alarm_description         = "This metric monitors Lambda function invocation anomalies"
  insufficient_data_actions = []
  alarm_actions             = var.alarm_actions
  ok_actions               = var.ok_actions
  
  metric_query {
    id          = "m1"
    return_data = "true"
    
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = "300"
      stat        = "Sum"
      
      dimensions = {
        FunctionName = var.function_name
      }
    }
  }
  
  metric_query {
    id = "ad1"
    
    anomaly_detector {
      metric_math_anomaly_detector {
        metric_data_queries {
          id = "m1"
          
          metric_stat {
            metric {
              metric_name = "Invocations"
              namespace   = "AWS/Lambda"
              
              dimensions = {
                FunctionName = var.function_name
              }
            }
            period = 300
            stat   = "Sum"
          }
        }
      }
    }
  }
  
  tags = var.tags
}

# =============================================================================
# CLOUDWATCH DASHBOARD
# =============================================================================

resource "aws_cloudwatch_dashboard" "lambda_dashboard" {
  dashboard_name = "${var.function_name}-dashboard-${var.region}"
  
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
            ["AWS/Lambda", "Invocations", "FunctionName", var.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.region
          title  = "Lambda Function Metrics"
          view   = "timeSeries"
          stacked = false
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
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", var.function_name],
            [".", "ProvisionedConcurrencyInvocations", ".", "."],
            [".", "ProvisionedConcurrencySpilloverInvocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "Lambda Concurrency Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/lambda/${var.function_name}'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region  = var.region
          title   = "Recent Lambda Function Logs"
        }
      }
    ]
  })
  
  tags = var.tags
}