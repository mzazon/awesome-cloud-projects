# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for computed names and configurations
locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  random_suffix = random_id.suffix.hex
  
  # Resource names with random suffix
  test_user_name    = "${var.test_user_name}-${local.random_suffix}"
  mfa_policy_name   = "${var.mfa_policy_name}-${local.random_suffix}"
  admin_group_name  = "${var.admin_group_name}-${local.random_suffix}"
  s3_bucket_name    = "${var.s3_bucket_name}-${local.random_suffix}-${local.account_id}"
  cloudtrail_name   = "${var.cloudtrail_name}-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = "MFA-Implementation"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Multi-Factor-Authentication-Demo"
  })
}

# Create test IAM user
resource "aws_iam_user" "test_user" {
  name          = local.test_user_name
  path          = "/"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "Test User for MFA Demo"
    Type = "TestUser"
  })
}

# Create login profile for test user
resource "aws_iam_user_login_profile" "test_user_profile" {
  user                    = aws_iam_user.test_user.name
  password                = var.temporary_password
  password_reset_required = var.force_password_reset
  password_length         = 20

  lifecycle {
    ignore_changes = [password]
  }
}

# Create IAM group for MFA administrators
resource "aws_iam_group" "mfa_admins" {
  name = local.admin_group_name
  path = "/"
}

# Add test user to MFA administrators group
resource "aws_iam_group_membership" "mfa_admins_membership" {
  name = "${local.admin_group_name}-membership"
  
  users = [
    aws_iam_user.test_user.name
  ]
  
  group = aws_iam_group.mfa_admins.name
}

# Create comprehensive MFA enforcement policy
resource "aws_iam_policy" "mfa_enforcement" {
  name        = local.mfa_policy_name
  path        = "/"
  description = "Enforce MFA for all AWS access while allowing MFA device management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowViewAccountInfo"
        Effect = "Allow"
        Action = [
          "iam:GetAccountPasswordPolicy",
          "iam:ListVirtualMFADevices",
          "iam:GetUser",
          "iam:ListUsers"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowManageOwnPasswords"
        Effect = "Allow"
        Action = [
          "iam:ChangePassword",
          "iam:GetUser"
        ]
        Resource = "arn:aws:iam::*:user/$${aws:username}"
      },
      {
        Sid    = "AllowManageOwnMFA"
        Effect = "Allow"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:DeactivateMFADevice",
          "iam:ListMFADevices",
          "iam:ResyncMFADevice"
        ]
        Resource = [
          "arn:aws:iam::*:mfa/$${aws:username}",
          "arn:aws:iam::*:user/$${aws:username}"
        ]
      },
      {
        Sid    = "DenyAllExceptUnlessMFAAuthenticated"
        Effect = "Deny"
        NotAction = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:GetUser",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:ResyncMFADevice",
          "sts:GetSessionToken",
          "iam:ChangePassword",
          "iam:GetAccountPasswordPolicy"
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      },
      {
        Sid    = "AllowFullAccessWithMFA"
        Effect = "Allow"
        Action = "*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "MFA Enforcement Policy"
    Type = "SecurityPolicy"
  })
}

# Attach MFA enforcement policy to the admin group
resource "aws_iam_group_policy_attachment" "mfa_enforcement_attachment" {
  group      = aws_iam_group.mfa_admins.name
  policy_arn = aws_iam_policy.mfa_enforcement.arn
}

# Create virtual MFA device for test user
resource "aws_iam_virtual_mfa_device" "test_user_mfa" {
  virtual_mfa_device_name = local.test_user_name
  path                    = "/"

  tags = merge(local.common_tags, {
    Name = "Virtual MFA Device for ${local.test_user_name}"
    Type = "MFADevice"
    User = local.test_user_name
  })
}

# S3 bucket for CloudTrail logs (conditional)
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name = "CloudTrail Logs Bucket"
    Type = "AuditLogs"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs_versioning" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs_encryption" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs_pab" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.cloudtrail_name}"
          }
        }
      }
    ]
  })
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  count             = var.enable_cloudtrail ? 1 : 0
  name              = "/aws/cloudtrail/${local.cloudtrail_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "CloudTrail Log Group"
    Type = "AuditLogs"
  })
}

# IAM role for CloudTrail CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch_role" {
  count = var.enable_cloudtrail ? 1 : 0
  name  = "CloudTrail-CloudWatchLogs-Role-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "CloudTrail CloudWatch Logs Role"
    Type = "ServiceRole"
  })
}

# IAM policy for CloudTrail CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_cloudwatch_policy" {
  count = var.enable_cloudtrail ? 1 : 0
  name  = "CloudTrail-CloudWatchLogs-Policy"
  role  = aws_iam_role.cloudtrail_cloudwatch_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail_logs[0].arn}:*"
      }
    ]
  })
}

# CloudTrail for audit logging
resource "aws_cloudtrail" "mfa_audit_trail" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_logs[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch_role[0].arn

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/*"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "MFA Audit Trail"
    Type = "AuditTrail"
  })

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs_policy[0]
  ]
}

# CloudWatch metric filter for MFA usage
resource "aws_cloudwatch_log_metric_filter" "mfa_usage_filter" {
  count          = var.enable_cloudtrail && var.enable_mfa_alarms ? 1 : 0
  name           = "MFAUsageFilter"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs[0].name
  pattern        = "{ ($.eventName = ConsoleLogin) && ($.responseElements.ConsoleLogin = \"Success\") && ($.additionalEventData.MFAUsed = \"Yes\") }"

  metric_transformation {
    name      = "MFALoginCount"
    namespace = "AWS/CloudTrailMetrics"
    value     = "1"
  }
}

# CloudWatch metric filter for non-MFA usage
resource "aws_cloudwatch_log_metric_filter" "non_mfa_usage_filter" {
  count          = var.enable_cloudtrail && var.enable_mfa_alarms ? 1 : 0
  name           = "NonMFAUsageFilter"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs[0].name
  pattern        = "{ ($.eventName = ConsoleLogin) && ($.responseElements.ConsoleLogin = \"Success\") && ($.additionalEventData.MFAUsed = \"No\") }"

  metric_transformation {
    name      = "NonMFALoginCount"
    namespace = "AWS/CloudTrailMetrics"
    value     = "1"
  }
}

# SNS topic for MFA alerts (conditional)
resource "aws_sns_topic" "mfa_alerts" {
  count = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  name  = "mfa-security-alerts-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Name = "MFA Security Alerts"
    Type = "AlertTopic"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "mfa_email_alerts" {
  count     = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.mfa_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for non-MFA console logins
resource "aws_cloudwatch_metric_alarm" "non_mfa_console_logins" {
  count               = var.enable_cloudtrail && var.enable_mfa_alarms ? 1 : 0
  alarm_name          = "Non-MFA-Console-Logins-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "NonMFALoginCount"
  namespace           = "AWS/CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert on console logins without MFA"
  alarm_actions       = var.enable_sns_notifications && var.notification_email != "" ? [aws_sns_topic.mfa_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "Non-MFA Console Login Alarm"
    Type = "SecurityAlarm"
  })
}

# CloudWatch Dashboard for MFA monitoring
resource "aws_cloudwatch_dashboard" "mfa_security_dashboard" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = var.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = var.enable_cloudtrail && var.enable_mfa_alarms ? [
            ["AWS/CloudTrailMetrics", "MFALoginCount"],
            [".", "NonMFALoginCount"]
          ] : []
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "MFA vs Non-MFA Logins"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query = var.enable_cloudtrail ? "SOURCE '${aws_cloudwatch_log_group.cloudtrail_logs[0].name}' | fields @timestamp, sourceIPAddress, userIdentity.type, userIdentity.userName, responseElements.ConsoleLogin\n| filter eventName = \"ConsoleLogin\"\n| filter responseElements.ConsoleLogin = \"Success\"\n| stats count() by userIdentity.userName" : "fields @timestamp\n| limit 20"
          region = local.region
          title  = "Console Logins by User"
          view   = "table"
        }
      }
    ]
  })
}

# Output the MFA device QR code data (base64 encoded)
resource "local_file" "mfa_qr_code" {
  count           = 1
  content_base64  = aws_iam_virtual_mfa_device.test_user_mfa.qr_code_png
  filename        = "${path.module}/mfa-qr-code.png"
  file_permission = "0644"
}