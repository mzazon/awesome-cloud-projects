# ==============================================================================
# Amazon GuardDuty Threat Detection Infrastructure
# ==============================================================================
# This Terraform configuration implements a comprehensive threat detection
# system using Amazon GuardDuty with automated alerting and monitoring.

# Data sources for account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# GuardDuty Configuration
# ==============================================================================

# Enable GuardDuty detector for threat monitoring
resource "aws_guardduty_detector" "main" {
  enable = true
  
  # Configure finding publishing frequency
  finding_publishing_frequency = var.finding_publishing_frequency
  
  # Enable malware protection for EC2 instances and container workloads
  malware_protection {
    scan_ec2_instance_with_findings {
      ebs_volumes = true
    }
  }

  # Enable Kubernetes audit logs monitoring
  kubernetes {
    audit_logs {
      enable = var.enable_kubernetes_protection
    }
  }

  # Enable S3 protection for data access monitoring
  s3_protection {
    enable = var.enable_s3_protection
  }

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-detector"
    Service     = "GuardDuty"
    Environment = var.environment
  })
}

# ==============================================================================
# S3 Bucket for GuardDuty Findings Export
# ==============================================================================

# S3 bucket for storing GuardDuty findings
resource "aws_s3_bucket" "guardduty_findings" {
  bucket = "${var.resource_prefix}-guardduty-findings-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-findings"
    Purpose     = "GuardDuty Findings Storage"
    Environment = var.environment
  })
}

# Configure bucket versioning for findings retention
resource "aws_s3_bucket_versioning" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for findings security
resource "aws_s3_bucket_server_side_encryption_configuration" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to findings bucket for security
resource "aws_s3_bucket_public_access_block" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for findings retention management
resource "aws_s3_bucket_lifecycle_configuration" "guardduty_findings" {
  count  = var.enable_findings_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.guardduty_findings.id

  rule {
    id     = "guardduty_findings_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after retention period
    expiration {
      days = var.findings_retention_days
    }
  }
}

# IAM policy for GuardDuty S3 access
data "aws_iam_policy_document" "guardduty_s3_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["guardduty.amazonaws.com"]
    }
    
    actions = [
      "s3:PutObject",
      "s3:GetBucketLocation"
    ]
    
    resources = [
      aws_s3_bucket.guardduty_findings.arn,
      "${aws_s3_bucket.guardduty_findings.arn}/*"
    ]
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Apply IAM policy to S3 bucket
resource "aws_s3_bucket_policy" "guardduty_findings" {
  bucket = aws_s3_bucket.guardduty_findings.id
  policy = data.aws_iam_policy_document.guardduty_s3_policy.json
}

# Configure GuardDuty publishing destination to S3
resource "aws_guardduty_publishing_destination" "s3" {
  count           = var.enable_s3_export ? 1 : 0
  detector_id     = aws_guardduty_detector.main.id
  destination_arn = aws_s3_bucket.guardduty_findings.arn
  
  depends_on = [aws_s3_bucket_policy.guardduty_findings]
}

# ==============================================================================
# SNS Topic for Threat Notifications
# ==============================================================================

# SNS topic for GuardDuty alerts
resource "aws_sns_topic" "guardduty_alerts" {
  name = "${var.resource_prefix}-guardduty-alerts-${random_id.suffix.hex}"

  # Enable message encryption in transit
  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.sns[0].id : null

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-alerts"
    Purpose     = "GuardDuty Threat Notifications"
    Environment = var.environment
  })
}

# KMS key for SNS topic encryption (optional)
resource "aws_kms_key" "sns" {
  count       = var.enable_sns_encryption ? 1 : 0
  description = "KMS key for GuardDuty SNS topic encryption"

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-sns-key"
    Purpose     = "SNS Encryption"
    Environment = var.environment
  })
}

# KMS key alias for easier management
resource "aws_kms_alias" "sns" {
  count         = var.enable_sns_encryption ? 1 : 0
  name          = "alias/${var.resource_prefix}-guardduty-sns-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.sns[0].key_id
}

# Email subscription to SNS topic (if email provided)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# EventBridge Configuration
# ==============================================================================

# EventBridge rule to capture GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.resource_prefix}-guardduty-findings"
  description = "Route GuardDuty findings to SNS for alerting"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = var.alert_severity_levels
    }
  })

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-eventbridge-rule"
    Purpose     = "GuardDuty Event Routing"
    Environment = var.environment
  })
}

# EventBridge target to route findings to SNS
resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.guardduty_alerts.arn

  # Transform the event to include more readable information
  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      region      = "$.detail.region"
      account     = "$.detail.accountId"
      time        = "$.detail.updatedAt"
      title       = "$.detail.title"
      description = "$.detail.description"
    }

    input_template = jsonencode({
      alert_type  = "GuardDuty Finding"
      severity    = "<severity>"
      finding_type = "<type>"
      region      = "<region>"
      account_id  = "<account>"
      timestamp   = "<time>"
      title       = "<title>"
      description = "<description>"
      console_url = "https://console.aws.amazon.com/guardduty/home?region=<region>#/findings"
    })
  }
}

# IAM policy for EventBridge to publish to SNS
data "aws_iam_policy_document" "eventbridge_sns_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    
    actions = [
      "sns:Publish"
    ]
    
    resources = [aws_sns_topic.guardduty_alerts.arn]
  }
}

# Apply policy to SNS topic for EventBridge access
resource "aws_sns_topic_policy" "guardduty_alerts" {
  arn    = aws_sns_topic.guardduty_alerts.arn
  policy = data.aws_iam_policy_document.eventbridge_sns_policy.json
}

# ==============================================================================
# CloudWatch Dashboard for Security Monitoring
# ==============================================================================

# Comprehensive security monitoring dashboard
resource "aws_cloudwatch_dashboard" "guardduty_monitoring" {
  dashboard_name = "${var.resource_prefix}-guardduty-security-monitoring"

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
            ["AWS/GuardDuty", "FindingCount", "DetectorId", aws_guardduty_detector.main.id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "GuardDuty Findings Count"
          view   = "timeSeries"
          annotations = {
            horizontal = [
              {
                label = "High Alert Threshold"
                value = var.high_finding_threshold
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
            ["AWS/GuardDuty", "FindingCount", "DetectorId", aws_guardduty_detector.main.id, "FindingType", "Trojan:EC2/DNSDataExfiltration"],
            [".", ".", ".", ".", ".", "Backdoor:EC2/XORDDOS"],
            [".", ".", ".", ".", ".", "CryptoCurrency:EC2/BitcoinTool.B!DNS"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Critical Threat Types"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/guardduty/findings' | fields @timestamp, severity, type, title\n| filter severity >= ${var.dashboard_severity_filter}\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "Recent High-Severity Findings"
        }
      }
    ]
  })
}

# ==============================================================================
# CloudWatch Alarms for Proactive Monitoring
# ==============================================================================

# Alarm for high number of findings
resource "aws_cloudwatch_metric_alarm" "high_findings" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.resource_prefix}-guardduty-high-findings"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FindingCount"
  namespace           = "AWS/GuardDuty"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.high_finding_threshold
  alarm_description   = "GuardDuty has detected an unusually high number of findings"
  alarm_actions       = [aws_sns_topic.guardduty_alerts.arn]

  dimensions = {
    DetectorId = aws_guardduty_detector.main.id
  }

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-guardduty-high-findings-alarm"
    Purpose     = "GuardDuty Monitoring"
    Environment = var.environment
  })
}

# ==============================================================================
# Optional: Custom Threat Intelligence Set
# ==============================================================================

# Custom threat intelligence set (if enabled and file provided)
resource "aws_guardduty_threatintelset" "custom" {
  count       = var.enable_custom_threat_intel && var.threat_intel_set_location != "" ? 1 : 0
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = var.threat_intel_set_format
  location    = var.threat_intel_set_location
  name        = "${var.resource_prefix}-custom-threat-intel"

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-custom-threat-intel"
    Purpose     = "Custom Threat Intelligence"
    Environment = var.environment
  })
}

# ==============================================================================
# Optional: IP Set for Trusted IPs
# ==============================================================================

# Trusted IP set to reduce false positives (if enabled and file provided)
resource "aws_guardduty_ipset" "trusted" {
  count       = var.enable_trusted_ip_set && var.trusted_ip_set_location != "" ? 1 : 0
  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = var.trusted_ip_set_location
  name        = "${var.resource_prefix}-trusted-ips"

  tags = merge(var.tags, {
    Name        = "${var.resource_prefix}-trusted-ip-set"
    Purpose     = "Trusted IP Whitelist"
    Environment = var.environment
  })
}