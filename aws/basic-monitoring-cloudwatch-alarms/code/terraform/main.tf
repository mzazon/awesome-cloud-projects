# =============================================================================
# AWS CloudWatch Monitoring Infrastructure
# =============================================================================
# This Terraform configuration creates a basic monitoring setup using Amazon 
# CloudWatch Alarms and SNS for notifications. It includes:
# - SNS topic for alarm notifications
# - Email subscription to the SNS topic 
# - CloudWatch alarms for CPU usage, response time, and database connections
# =============================================================================

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =============================================================================
# SNS Topic for Alarm Notifications
# =============================================================================
# Amazon SNS provides reliable, scalable messaging for delivering notifications
# This topic will be used by all CloudWatch alarms for notifications

resource "aws_sns_topic" "monitoring_alerts" {
  name = "${var.sns_topic_name}-${random_string.suffix.result}"

  # Configure message delivery policy for reliability
  delivery_policy = jsonencode({
    "http" : {
      "defaultHealthyRetryPolicy" : {
        "minDelayTarget" : 20,
        "maxDelayTarget" : 20,
        "numRetries" : 3,
        "numMaxDelayRetries" : 0,
        "numMinDelayRetries" : 0,
        "numNoDelayRetries" : 0,
        "backoffFunction" : "linear"
      },
      "disableSubscriptionOverrides" : false
    }
  })

  tags = merge(var.tags, {
    Name = "${var.sns_topic_name}-${random_string.suffix.result}"
    Type = "Monitoring"
  })
}

# =============================================================================
# SNS Topic Policy
# =============================================================================
# Allow CloudWatch to publish messages to the SNS topic

resource "aws_sns_topic_policy" "monitoring_alerts_policy" {
  arn = aws_sns_topic.monitoring_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.monitoring_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# Email Subscription to SNS Topic
# =============================================================================
# Email subscription for immediate notification delivery to operations teams
# Note: Subscription must be confirmed via email before notifications are delivered

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  depends_on = [aws_sns_topic.monitoring_alerts]
}

# =============================================================================
# CloudWatch Alarm: High CPU Utilization
# =============================================================================
# Monitors average CPU utilization across all EC2 instances
# Triggers when CPU exceeds 80% for 2 consecutive 5-minute periods

resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "HighCPUUtilization-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cpu_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  ok_actions          = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  # Enable this alarm
  alarm_actions = [aws_sns_topic.monitoring_alerts.arn]

  tags = merge(var.tags, {
    Name        = "HighCPUUtilization-${random_string.suffix.result}"
    MetricType  = "CPU"
    ServiceType = "EC2"
  })

  depends_on = [aws_sns_topic.monitoring_alerts]
}

# =============================================================================
# CloudWatch Alarm: High Response Time (ALB)
# =============================================================================
# Monitors Application Load Balancer response time
# Triggers when response time exceeds 1 second for 3 consecutive periods

resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "HighResponseTime-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.response_time_alarm_evaluation_periods
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.response_time_threshold
  alarm_description   = "This metric monitors ALB response time"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, {
    Name        = "HighResponseTime-${random_string.suffix.result}"
    MetricType  = "ResponseTime"
    ServiceType = "ELB"
  })

  depends_on = [aws_sns_topic.monitoring_alerts]
}

# =============================================================================
# CloudWatch Alarm: High Database Connections
# =============================================================================
# Monitors RDS database connection count
# Triggers when connections exceed 80 for 2 consecutive periods

resource "aws_cloudwatch_metric_alarm" "high_db_connections" {
  alarm_name          = "HighDBConnections-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.db_connections_alarm_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.db_connections_threshold
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = merge(var.tags, {
    Name        = "HighDBConnections-${random_string.suffix.result}"
    MetricType  = "DatabaseConnections"
    ServiceType = "RDS"
  })

  depends_on = [aws_sns_topic.monitoring_alerts]
}

# =============================================================================
# Optional: CloudWatch Dashboard
# =============================================================================
# Creates a dashboard to visualize all monitored metrics in one place
# Provides unified view of EC2, RDS, and ALB metrics

resource "aws_cloudwatch_dashboard" "monitoring_dashboard" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "MonitoringDashboard-${random_string.suffix.result}"

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
            ["AWS/EC2", "CPUUtilization", { "stat" : "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", { "stat" : "Average" }],
            ["AWS/RDS", "DatabaseConnections", { "stat" : "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Key Metrics Overview"
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
          annotations = {
            alarms = [
              aws_cloudwatch_metric_alarm.high_cpu_utilization.arn,
              aws_cloudwatch_metric_alarm.high_response_time.arn,
              aws_cloudwatch_metric_alarm.high_db_connections.arn
            ]
          }
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Alarm States"
          period  = 300
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "MonitoringDashboard-${random_string.suffix.result}"
    Type = "Dashboard"
  })
}