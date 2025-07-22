# ==============================================================================
# Website Uptime Monitoring with Route 53 Health Checks
# ==============================================================================
# This Terraform configuration creates a comprehensive website uptime monitoring
# system using AWS Route 53 health checks, CloudWatch alarms, SNS notifications,
# and CloudWatch dashboards for visualization.

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ==============================================================================
# SNS Topic for Email Notifications
# ==============================================================================
# SNS topic provides reliable, scalable messaging for sending uptime alerts
# to multiple subscribers with configurable delivery policies

resource "aws_sns_topic" "uptime_alerts" {
  name = "${var.project_name}-uptime-alerts-${random_string.suffix.result}"

  # Enable server-side encryption for message security
  kms_master_key_id = "alias/aws/sns"

  # Configure delivery policy for reliable message delivery
  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget    = 20
        maxDelayTarget    = 20
        numRetries        = 3
        backoffFunction   = "linear"
        numNoDelayRetries = 0
        numMinDelayRetries = 0
        numMaxDelayRetries = 0
      }
      disableSubscriptionOverrides = false
    }
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-uptime-alerts-${random_string.suffix.result}"
    Purpose     = "UptimeMonitoring"
    Component   = "Notifications"
  })
}

# SNS topic policy to allow CloudWatch alarms to publish messages
resource "aws_sns_topic_policy" "uptime_alerts_policy" {
  arn = aws_sns_topic.uptime_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "uptime-alerts-policy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.uptime_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic for receiving notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.uptime_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email

  # Configure delivery policy for email notifications
  delivery_policy = jsonencode({
    healthyRetryPolicy = {
      minDelayTarget    = 20
      maxDelayTarget    = 20
      numRetries        = 3
      backoffFunction   = "linear"
    }
  })
}

# ==============================================================================
# Route 53 Health Check Configuration
# ==============================================================================
# Route 53 health checks provide global monitoring from multiple AWS edge
# locations worldwide for accurate availability assessment

resource "aws_route53_health_check" "website_uptime" {
  # Extract domain and path from the website URL
  fqdn                            = replace(replace(var.website_url, "https://", ""), "http://", "")
  port                           = var.website_url_scheme == "https" ? 443 : 80
  type                           = var.website_url_scheme == "https" ? "HTTPS" : "HTTP"
  resource_path                  = var.health_check_path
  failure_threshold              = var.failure_threshold
  request_interval               = var.request_interval
  measure_latency               = true
  enable_sni                    = var.website_url_scheme == "https"
  
  # Optional string matching for more reliable health checks
  search_string = var.search_string != "" ? var.search_string : null

  # Configure health check regions for global coverage
  regions = var.health_check_regions

  tags = merge(var.tags, {
    Name        = "${var.project_name}-health-check-${random_string.suffix.result}"
    Purpose     = "UptimeMonitoring"
    Component   = "HealthCheck"
    MonitoredURL = var.website_url
  })
}

# ==============================================================================
# CloudWatch Alarm for Health Check Failures
# ==============================================================================
# CloudWatch alarm monitors health check status and triggers notifications
# when the website becomes unavailable

resource "aws_cloudwatch_metric_alarm" "website_down" {
  alarm_name          = "${var.project_name}-website-down-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1.0
  alarm_description   = "This alarm monitors the health status of ${var.website_url}"
  alarm_actions       = [aws_sns_topic.uptime_alerts.arn]
  ok_actions          = [aws_sns_topic.uptime_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.website_uptime.id
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-website-down-alarm-${random_string.suffix.result}"
    Purpose     = "UptimeMonitoring"
    Component   = "Alarm"
    MonitoredURL = var.website_url
  })
}

# Additional alarm for monitoring health check percentage across regions
resource "aws_cloudwatch_metric_alarm" "health_check_percentage" {
  alarm_name          = "${var.project_name}-health-percentage-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HealthCheckPercentHealthy"
  namespace           = "AWS/Route53"
  period              = 300
  statistic           = "Average"
  threshold           = var.health_percentage_threshold
  alarm_description   = "This alarm monitors the percentage of healthy health checkers for ${var.website_url}"
  alarm_actions       = [aws_sns_topic.uptime_alerts.arn]
  ok_actions          = [aws_sns_topic.uptime_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.website_uptime.id
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-health-percentage-alarm-${random_string.suffix.result}"
    Purpose     = "UptimeMonitoring"
    Component   = "Alarm"
    MonitoredURL = var.website_url
  })
}

# ==============================================================================
# CloudWatch Dashboard for Visualization
# ==============================================================================
# CloudWatch dashboard provides centralized visualization of health check metrics
# for quick assessment of website performance and availability patterns

resource "aws_cloudwatch_dashboard" "uptime_monitoring" {
  dashboard_name = "${var.project_name}-uptime-dashboard-${random_string.suffix.result}"

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
            ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", aws_route53_health_check.website_uptime.id]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Website Health Status"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
          annotations = {
            horizontal = [
              {
                label = "Healthy Threshold"
                value = 1
              }
            ]
          }
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
            ["AWS/Route53", "HealthCheckPercentHealthy", "HealthCheckId", aws_route53_health_check.website_uptime.id]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Health Check Percentage Healthy"
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
                value = var.health_percentage_threshold
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Route53", "ConnectionTime", "HealthCheckId", aws_route53_health_check.website_uptime.id]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "Website Response Time (ms)"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 12
        width  = 24
        height = 4
        properties = {
          markdown = join("", [
            "## Website Uptime Monitoring Dashboard\n\n",
            "**Monitored URL:** ${var.website_url}\n\n",
            "**Health Check Configuration:**\n",
            "- Check Interval: ${var.request_interval} seconds\n",
            "- Failure Threshold: ${var.failure_threshold} failures\n",
            "- Monitoring Regions: ${length(var.health_check_regions)} regions\n\n",
            "**Alert Configuration:**\n",
            "- Evaluation Periods: ${var.alarm_evaluation_periods}\n",
            "- Health Percentage Threshold: ${var.health_percentage_threshold}%\n",
            var.notification_email != "" ? "- Email Notifications: ${var.notification_email}\n" : "",
            "\n",
            "**Legend:**\n",
            "- 🟢 Health Status = 1 (Healthy)\n",
            "- 🔴 Health Status = 0 (Unhealthy)\n",
            "- 📊 Health Percentage = % of health checkers reporting healthy"
          ])
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.project_name}-uptime-dashboard-${random_string.suffix.result}"
    Purpose     = "UptimeMonitoring"
    Component   = "Dashboard"
    MonitoredURL = var.website_url
  })
}