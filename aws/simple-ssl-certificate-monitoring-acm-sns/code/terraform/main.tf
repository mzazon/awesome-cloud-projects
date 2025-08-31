# ==============================================================================
# Terraform Configuration for SSL Certificate Monitoring with ACM and SNS
# ==============================================================================
# This configuration creates AWS infrastructure to monitor SSL certificate
# expiration using AWS Certificate Manager, CloudWatch, and SNS notifications.
#
# Resources created:
# - SNS Topic for certificate alerts
# - Email subscription to SNS topic
# - CloudWatch alarms for certificate expiration monitoring
# - Data source to fetch existing ACM certificates
# ==============================================================================

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Fetch existing ACM certificates to monitor
data "aws_acm_certificate" "existing_certificates" {
  count    = var.monitor_existing_certificates ? 1 : 0
  domain   = var.certificate_domain_name
  statuses = ["ISSUED"]
}

# ==============================================================================
# SNS Topic and Subscription
# ==============================================================================

# SNS topic for SSL certificate expiration alerts
resource "aws_sns_topic" "ssl_cert_alerts" {
  name         = "${var.sns_topic_name}-${random_id.suffix.hex}"
  display_name = "SSL Certificate Expiration Alerts"

  # Enable server-side encryption for the SNS topic
  kms_master_key_id = "alias/aws/sns"

  tags = merge(var.tags, {
    Name        = "${var.sns_topic_name}-${random_id.suffix.hex}"
    Purpose     = "SSL Certificate Monitoring"
    Component   = "Notification"
    Environment = var.environment
  })
}

# SNS topic policy to allow CloudWatch to publish messages
resource "aws_sns_topic_policy" "ssl_cert_alerts_policy" {
  arn = aws_sns_topic.ssl_cert_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ssl-cert-monitoring-policy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ssl_cert_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic for certificate alerts
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.ssl_cert_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# CloudWatch Alarms for Certificate Monitoring
# ==============================================================================

# CloudWatch alarm for monitoring existing certificate expiration
resource "aws_cloudwatch_metric_alarm" "certificate_expiration" {
  count = var.monitor_existing_certificates && var.certificate_domain_name != "" ? 1 : 0

  alarm_name          = "SSL-Certificate-Expiring-${var.certificate_domain_name}-${random_id.suffix.hex}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = var.alarm_period
  statistic           = "Minimum"
  threshold           = var.expiration_threshold_days
  alarm_description   = "This metric monitors SSL certificate expiration for ${var.certificate_domain_name}"
  alarm_actions       = [aws_sns_topic.ssl_cert_alerts.arn]
  ok_actions          = var.send_ok_notifications ? [aws_sns_topic.ssl_cert_alerts.arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    CertificateArn = data.aws_acm_certificate.existing_certificates[0].arn
  }

  tags = merge(var.tags, {
    Name         = "SSL-Certificate-Expiring-${var.certificate_domain_name}-${random_id.suffix.hex}"
    Purpose      = "SSL Certificate Monitoring"
    Component    = "Alarm"
    Environment  = var.environment
    Domain       = var.certificate_domain_name
  })

  depends_on = [aws_sns_topic_policy.ssl_cert_alerts_policy]
}

# CloudWatch alarms for monitoring certificates specified by ARN
resource "aws_cloudwatch_metric_alarm" "certificate_expiration_by_arn" {
  count = length(var.certificate_arns)

  alarm_name          = "SSL-Certificate-Expiring-${substr(replace(var.certificate_arns[count.index], "/.*certificate\\//", ""), 0, 8)}-${random_id.suffix.hex}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = var.alarm_period
  statistic           = "Minimum"
  threshold           = var.expiration_threshold_days
  alarm_description   = "This metric monitors SSL certificate expiration for certificate ${var.certificate_arns[count.index]}"
  alarm_actions       = [aws_sns_topic.ssl_cert_alerts.arn]
  ok_actions          = var.send_ok_notifications ? [aws_sns_topic.ssl_cert_alerts.arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    CertificateArn = var.certificate_arns[count.index]
  }

  tags = merge(var.tags, {
    Name         = "SSL-Certificate-Expiring-${substr(replace(var.certificate_arns[count.index], "/.*certificate\\//", ""), 0, 8)}-${random_id.suffix.hex}"
    Purpose      = "SSL Certificate Monitoring"
    Component    = "Alarm"
    Environment  = var.environment
    CertificateId = substr(replace(var.certificate_arns[count.index], "/.*certificate\\//", ""), 0, 8)
  })

  depends_on = [aws_sns_topic_policy.ssl_cert_alerts_policy]
}

# ==============================================================================
# Optional: Create Test Certificate for Demo Purposes
# ==============================================================================

# ACM certificate for testing (only created if create_test_certificate is true)
resource "aws_acm_certificate" "test_certificate" {
  count = var.create_test_certificate ? 1 : 0

  domain_name       = var.test_certificate_domain
  validation_method = "DNS"

  subject_alternative_names = var.test_certificate_sans

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "Test SSL Certificate"
    Purpose     = "SSL Certificate Monitoring Demo"
    Component   = "Certificate"
    Environment = var.environment
    Domain      = var.test_certificate_domain
  })
}

# CloudWatch alarm for the test certificate (if created)
resource "aws_cloudwatch_metric_alarm" "test_certificate_expiration" {
  count = var.create_test_certificate ? 1 : 0

  alarm_name          = "SSL-Test-Certificate-Expiring-${random_id.suffix.hex}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = var.alarm_period
  statistic           = "Minimum"
  threshold           = var.expiration_threshold_days
  alarm_description   = "This metric monitors test SSL certificate expiration for ${var.test_certificate_domain}"
  alarm_actions       = [aws_sns_topic.ssl_cert_alerts.arn]
  ok_actions          = var.send_ok_notifications ? [aws_sns_topic.ssl_cert_alerts.arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    CertificateArn = aws_acm_certificate.test_certificate[0].arn
  }

  tags = merge(var.tags, {
    Name         = "SSL-Test-Certificate-Expiring-${random_id.suffix.hex}"
    Purpose      = "SSL Certificate Monitoring"
    Component    = "Alarm"
    Environment  = var.environment
    Domain       = var.test_certificate_domain
  })

  depends_on = [
    aws_sns_topic_policy.ssl_cert_alerts_policy,
    aws_acm_certificate.test_certificate
  ]
}

# ==============================================================================
# CloudWatch Dashboard (Optional)
# ==============================================================================

# CloudWatch dashboard for certificate monitoring overview
resource "aws_cloudwatch_dashboard" "ssl_certificate_monitoring" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "SSL-Certificate-Monitoring-${random_id.suffix.hex}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = concat(
            var.monitor_existing_certificates && var.certificate_domain_name != "" ? [
              ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", data.aws_acm_certificate.existing_certificates[0].arn]
            ] : [],
            [for arn in var.certificate_arns : ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", arn]],
            var.create_test_certificate ? [
              ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", aws_acm_certificate.test_certificate[0].arn]
            ] : []
          )
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "SSL Certificate Days to Expiry"
          period  = 86400
          yAxis = {
            left = {
              min = 0
              max = 365
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 4

        properties = {
          metrics = concat(
            var.monitor_existing_certificates && var.certificate_domain_name != "" ? [
              ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", data.aws_acm_certificate.existing_certificates[0].arn]
            ] : [],
            [for arn in var.certificate_arns : ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", arn]],
            var.create_test_certificate ? [
              ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", aws_acm_certificate.test_certificate[0].arn]
            ] : []
          )
          view    = "singleValue"
          region  = data.aws_region.current.name
          title   = "Current Days to Expiry"
          period  = 86400
        }
      }
    ]
  })
}