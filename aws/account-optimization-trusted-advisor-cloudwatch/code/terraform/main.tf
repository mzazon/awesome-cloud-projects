# ==============================================================================
# AWS Trusted Advisor CloudWatch Monitoring Infrastructure
# ==============================================================================
# This Terraform configuration creates an automated monitoring system that 
# leverages AWS Trusted Advisor's built-in optimization checks with CloudWatch 
# alarms and SNS notifications to proactively alert teams when account 
# optimization opportunities arise.
#
# Resources Created:
# - SNS Topic for alert notifications
# - SNS Email subscriptions (optional)
# - CloudWatch alarms for Trusted Advisor checks
# - Common tags for resource management
# ==============================================================================

# Data source to get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Random string for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Generate consistent resource names with random suffix
  resource_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # SNS topic name for Trusted Advisor alerts
  sns_topic_name = "${local.resource_prefix}-alerts"
  
  # CloudWatch alarm names with descriptive purposes
  cost_alarm_name     = "${local.resource_prefix}-cost-optimization"
  security_alarm_name = "${local.resource_prefix}-security"
  limits_alarm_name   = "${local.resource_prefix}-service-limits"
  
  # Common tags to apply to all resources for consistent management
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "TrustedAdvisorMonitoring"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  })
}

# ==============================================================================
# SNS Topic for Trusted Advisor Alert Notifications
# ==============================================================================
# Amazon SNS provides a highly available, durable, secure, fully managed 
# pub/sub messaging service that enables you to decouple microservices, 
# distributed systems, and serverless applications.

resource "aws_sns_topic" "trusted_advisor_alerts" {
  name         = local.sns_topic_name
  display_name = "AWS Account Optimization Alerts"
  
  # Enable server-side encryption for enhanced security
  kms_master_key_id = var.sns_kms_key_id
  
  # Delivery policy for message retry configuration
  delivery_policy = jsonencode({
    "http" = {
      "defaultHealthyRetryPolicy" = {
        "minDelayTarget"     = 20
        "maxDelayTarget"     = 20
        "numRetries"         = 3
        "numMaxDelayRetries" = 0
        "numMinDelayRetries" = 0
        "numNoDelayRetries"  = 0
        "backoffFunction"    = "linear"
      }
      "disableSubscriptionOverrides" = false
    }
  })
  
  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "SNS topic for AWS Trusted Advisor optimization alerts"
  })
}

# ==============================================================================
# SNS Topic Policy for CloudWatch Alarm Publishing
# ==============================================================================
# This policy allows CloudWatch alarms to publish messages to the SNS topic

resource "aws_sns_topic_policy" "trusted_advisor_alerts_policy" {
  arn = aws_sns_topic.trusted_advisor_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "trusted-advisor-alerts-policy"
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
        Resource = aws_sns_topic.trusted_advisor_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ==============================================================================
# Email Subscriptions to SNS Topic (Optional)
# ==============================================================================
# Email subscriptions provide immediate notification delivery with built-in 
# unsubscribe protection and delivery confirmation.

resource "aws_sns_topic_subscription" "email_notifications" {
  count = length(var.notification_emails)
  
  topic_arn = aws_sns_topic.trusted_advisor_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
  
  # Note: Email subscriptions require manual confirmation
  # Recipients will receive a confirmation email that must be clicked
}

# ==============================================================================
# CloudWatch Alarm for Cost Optimization Monitoring
# ==============================================================================
# This alarm monitors the "Low Utilization Amazon EC2 Instances" check from 
# Trusted Advisor, which identifies EC2 instances with low CPU utilization 
# that could be downsized or terminated to reduce costs.

resource "aws_cloudwatch_metric_alarm" "cost_optimization" {
  alarm_name        = local.cost_alarm_name
  alarm_description = "Alert when Trusted Advisor identifies cost optimization opportunities for EC2 instances"
  
  # Metric configuration for Trusted Advisor YellowResources
  metric_name = "YellowResources"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  # Alarm evaluation settings
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.cost_optimization_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  
  # Missing data treatment - important for Trusted Advisor metrics
  treat_missing_data = "notBreaching"
  
  # Alarm actions - publish to SNS when alarm state changes
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  # Trusted Advisor check-specific dimension
  dimensions = {
    CheckName = "Low Utilization Amazon EC2 Instances"
  }
  
  tags = merge(local.common_tags, {
    Name        = local.cost_alarm_name
    AlarmType   = "CostOptimization"
    Description = "Monitors EC2 instance utilization for cost optimization opportunities"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}

# ==============================================================================
# CloudWatch Alarm for Security Monitoring
# ==============================================================================
# This alarm monitors the "Security Groups - Specific Ports Unrestricted" 
# check, which identifies security groups that allow unrestricted access 
# to specific ports.

resource "aws_cloudwatch_metric_alarm" "security_monitoring" {
  alarm_name        = local.security_alarm_name
  alarm_description = "Alert when Trusted Advisor identifies security recommendations for unrestricted ports"
  
  # Metric configuration for Trusted Advisor RedResources (critical issues)
  metric_name = "RedResources"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  # Alarm evaluation settings
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.security_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  
  # Missing data treatment
  treat_missing_data = "notBreaching"
  
  # Alarm actions
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  # Security check dimension
  dimensions = {
    CheckName = "Security Groups - Specific Ports Unrestricted"
  }
  
  tags = merge(local.common_tags, {
    Name        = local.security_alarm_name
    AlarmType   = "Security"
    Description = "Monitors security groups for unrestricted port access"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}

# ==============================================================================
# CloudWatch Alarm for Service Limits Monitoring
# ==============================================================================
# This alarm monitors AWS service quotas to prevent service disruptions 
# caused by reaching capacity constraints and enables proactive quota 
# increase requests when approaching thresholds.

resource "aws_cloudwatch_metric_alarm" "service_limits" {
  alarm_name        = local.limits_alarm_name
  alarm_description = "Alert when service usage approaches limits for EC2 On-Demand instances"
  
  # Metric configuration for Service Limit Usage
  metric_name = "ServiceLimitUsage"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  # Alarm evaluation settings
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.service_limits_threshold
  comparison_operator = "GreaterThanThreshold"
  
  # Missing data treatment
  treat_missing_data = "notBreaching"
  
  # Alarm actions
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  # Service limit dimensions for EC2 On-Demand instances
  dimensions = {
    ServiceName  = "EC2"
    ServiceLimit = "Running On-Demand EC2 Instances"
    Region       = data.aws_region.current.name
  }
  
  tags = merge(local.common_tags, {
    Name        = local.limits_alarm_name
    AlarmType   = "ServiceLimits"
    Description = "Monitors EC2 On-Demand instance usage against service quotas"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}

# ==============================================================================
# Optional: Additional Trusted Advisor Checks
# ==============================================================================
# These additional alarms can be enabled through variables to monitor 
# other important Trusted Advisor checks for comprehensive coverage.

# IAM Access Key Rotation Check
resource "aws_cloudwatch_metric_alarm" "iam_key_rotation" {
  count = var.enable_iam_key_rotation_alarm ? 1 : 0
  
  alarm_name        = "${local.resource_prefix}-iam-key-rotation"
  alarm_description = "Alert when IAM access keys require rotation"
  
  metric_name = "YellowResources"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  
  treat_missing_data = "notBreaching"
  
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  dimensions = {
    CheckName = "IAM Access Key Rotation"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-iam-key-rotation"
    AlarmType   = "IAM"
    Description = "Monitors IAM access key rotation compliance"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}

# RDS Security Group Access Risk Check
resource "aws_cloudwatch_metric_alarm" "rds_security" {
  count = var.enable_rds_security_alarm ? 1 : 0
  
  alarm_name        = "${local.resource_prefix}-rds-security"
  alarm_description = "Alert when RDS security groups have access risks"
  
  metric_name = "RedResources"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  
  treat_missing_data = "notBreaching"
  
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  dimensions = {
    CheckName = "Amazon RDS Security Group Access Risk"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-rds-security"
    AlarmType   = "RDSSecurity"
    Description = "Monitors RDS security group access risks"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}

# S3 Bucket Permissions Check
resource "aws_cloudwatch_metric_alarm" "s3_permissions" {
  count = var.enable_s3_permissions_alarm ? 1 : 0
  
  alarm_name        = "${local.resource_prefix}-s3-permissions"
  alarm_description = "Alert when S3 buckets have permission issues"
  
  metric_name = "YellowResources"
  namespace   = "AWS/TrustedAdvisor"
  statistic   = "Average"
  
  period              = var.alarm_evaluation_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  
  treat_missing_data = "notBreaching"
  
  alarm_actions = [aws_sns_topic.trusted_advisor_alerts.arn]
  ok_actions    = var.send_ok_notifications ? [aws_sns_topic.trusted_advisor_alerts.arn] : []
  
  dimensions = {
    CheckName = "Amazon S3 Bucket Permissions"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-s3-permissions"
    AlarmType   = "S3Security"
    Description = "Monitors S3 bucket permission configurations"
  })
  
  depends_on = [aws_sns_topic_policy.trusted_advisor_alerts_policy]
}