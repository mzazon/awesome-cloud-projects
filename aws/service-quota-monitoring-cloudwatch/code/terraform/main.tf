# AWS Service Quota Monitoring with CloudWatch Alarms
# This configuration creates a comprehensive service quota monitoring solution
# using AWS Service Quotas, CloudWatch, and SNS for proactive alerting

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Generate unique resource names
  sns_topic_name = "${var.sns_topic_name_prefix}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = {
    Project            = "ServiceQuotaMonitoring"
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Recipe             = "service-quota-monitoring-cloudwatch"
    NotificationEmail  = var.notification_email
    CreatedDate        = timestamp()
  }

  # SNS topic ARN for use in alarm actions
  sns_topic_arn = aws_sns_topic.quota_alerts.arn
}

#------------------------------------------------------------------------------
# SNS Topic and Subscriptions for Notifications
#------------------------------------------------------------------------------

# SNS topic for quota alert notifications
resource "aws_sns_topic" "quota_alerts" {
  name         = local.sns_topic_name
  display_name = "AWS Service Quota Alerts"

  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "SNS topic for AWS service quota utilization alerts"
  })
}

# SNS topic policy to allow CloudWatch to publish messages
resource "aws_sns_topic_policy" "quota_alerts_policy" {
  arn = aws_sns_topic.quota_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "quota-alerts-topic-policy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish",
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:Receive"
        ]
        Resource = aws_sns_topic.quota_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Primary email subscription for quota alerts
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.quota_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  depends_on = [aws_sns_topic_policy.quota_alerts_policy]
}

# Additional notification endpoints (if configured)
resource "aws_sns_topic_subscription" "additional_notifications" {
  for_each = {
    for idx, endpoint in var.additional_notification_endpoints :
    "${endpoint.protocol}-${idx}" => endpoint
  }

  topic_arn = aws_sns_topic.quota_alerts.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  depends_on = [aws_sns_topic_policy.quota_alerts_policy]
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for Service Quota Monitoring
#------------------------------------------------------------------------------

# CloudWatch alarms for each monitored service quota
resource "aws_cloudwatch_metric_alarm" "service_quota_alarms" {
  for_each = var.monitored_services

  # Alarm identification and configuration
  alarm_name        = each.value.alarm_name
  alarm_description = "${each.value.description} - Threshold: ${var.quota_threshold_percentage}%"
  
  # Metric configuration
  namespace   = "AWS/ServiceQuotas"
  metric_name = "ServiceQuotaUtilization"
  statistic   = "Maximum"
  
  # Evaluation configuration
  period                    = var.metric_period_seconds
  evaluation_periods        = var.alarm_evaluation_periods
  datapoints_to_alarm       = var.alarm_datapoints_to_alarm
  threshold                 = var.quota_threshold_percentage
  comparison_operator       = "GreaterThanThreshold"
  treat_missing_data        = var.treat_missing_data
  
  # Alarm actions
  alarm_actions = var.enable_alarm_actions ? [local.sns_topic_arn] : []
  ok_actions    = var.enable_alarm_actions ? [local.sns_topic_arn] : []
  
  # Metric dimensions to specify which service quota to monitor
  dimensions = {
    ServiceCode = each.value.service_code
    QuotaCode   = each.value.quota_code
  }

  # Ensure SNS topic and policy are created before alarms
  depends_on = [
    aws_sns_topic.quota_alerts,
    aws_sns_topic_policy.quota_alerts_policy
  ]

  tags = merge(local.common_tags, {
    Name         = each.value.alarm_name
    ServiceCode  = each.value.service_code
    QuotaCode    = each.value.quota_code
    QuotaName    = each.value.quota_name
    Threshold    = "${var.quota_threshold_percentage}%"
  })
}

#------------------------------------------------------------------------------
# Test Alarms (Optional - for validation purposes)
#------------------------------------------------------------------------------

# Test alarm that can be manually triggered for notification testing
resource "aws_cloudwatch_metric_alarm" "test_alarm" {
  count = var.enable_test_alarms ? 1 : 0

  alarm_name          = "Service-Quota-Test-Alarm-${random_string.suffix.result}"
  alarm_description   = "Test alarm for validating quota monitoring notifications"
  
  # Use a simple metric that we can control
  namespace           = "AWS/CloudWatch"
  metric_name         = "EstimatedCharges"
  statistic           = "Maximum"
  
  period              = 86400  # 24 hours
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0.01   # Very low threshold for easy testing
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  
  alarm_actions = var.enable_alarm_actions ? [local.sns_topic_arn] : []
  ok_actions    = var.enable_alarm_actions ? [local.sns_topic_arn] : []
  
  dimensions = {
    Currency = "USD"
  }

  depends_on = [
    aws_sns_topic.quota_alerts,
    aws_sns_topic_policy.quota_alerts_policy
  ]

  tags = merge(local.common_tags, {
    Name        = "Service-Quota-Test-Alarm-${random_string.suffix.result}"
    Purpose     = "Testing"
    Description = "Test alarm for validation purposes"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard (Optional - for visualization)
#------------------------------------------------------------------------------

# CloudWatch dashboard to visualize service quota utilization
resource "aws_cloudwatch_dashboard" "service_quotas" {
  dashboard_name = "ServiceQuotaMonitoring-${random_string.suffix.result}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# AWS Service Quota Monitoring Dashboard\n\nThis dashboard displays current service quota utilization across monitored AWS services. Alarms are configured to trigger at ${var.quota_threshold_percentage}% utilization.\n\n**Environment:** ${var.environment} | **Region:** ${data.aws_region.current.name} | **Account:** ${data.aws_caller_identity.current.account_id}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          metrics = [
            for service_key, service in var.monitored_services : [
              "AWS/ServiceQuotas",
              "ServiceQuotaUtilization",
              "ServiceCode",
              service.service_code,
              "QuotaCode",
              service.quota_code,
              {
                "label" = service.quota_name
              }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Service Quota Utilization (%)"
          period  = var.metric_period_seconds
          stat    = "Maximum"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
          annotations = {
            horizontal = [
              {
                label = "Alert Threshold"
                value = var.quota_threshold_percentage
                fill  = "above"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          metrics = [
            for service_key, service in var.monitored_services : [
              "AWS/ServiceQuotas",
              "ServiceQuotaUtilization",
              "ServiceCode",
              service.service_code,
              "QuotaCode",
              service.quota_code,
              {
                "label" = service.quota_name
              }
            ]
          ]
          view   = "singleValue"
          region = data.aws_region.current.name
          title  = "Current Quota Utilization"
          period = var.metric_period_seconds
          stat   = "Maximum"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "ServiceQuotaMonitoring-${random_string.suffix.result}"
    Description = "CloudWatch dashboard for service quota monitoring"
  })
}

#------------------------------------------------------------------------------
# IAM Role for Enhanced Monitoring (Future Enhancement)
#------------------------------------------------------------------------------

# IAM role that could be used for Lambda functions or other automation
# This is included for potential future enhancements like automated quota increases
resource "aws_iam_role" "quota_monitoring_role" {
  name = "ServiceQuotaMonitoringRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "ServiceQuotaMonitoringRole-${random_string.suffix.result}"
    Description = "IAM role for service quota monitoring automation"
  })
}

# IAM policy for the monitoring role
resource "aws_iam_role_policy" "quota_monitoring_policy" {
  name = "ServiceQuotaMonitoringPolicy"
  role = aws_iam_role.quota_monitoring_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "servicequotas:GetServiceQuota",
          "servicequotas:ListServiceQuotas",
          "servicequotas:GetRequestedServiceQuotaChange",
          "servicequotas:RequestServiceQuotaIncrease",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}