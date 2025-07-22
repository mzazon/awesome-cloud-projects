# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_organizations_organization" "current" {}

# Data source for IAM Identity Center instance (if it already exists)
data "aws_ssoadmin_instances" "current" {}

locals {
  resource_suffix = random_id.suffix.hex
  account_id      = data.aws_caller_identity.current.account_id
  region_name     = data.aws_region.current.name
  
  # Use existing Identity Center instance if available, otherwise create new one
  sso_instance_arn        = try(data.aws_ssoadmin_instances.current.arns[0], aws_ssoadmin_managed_application.sso_instance[0].arn)
  sso_identity_store_id   = try(data.aws_ssoadmin_instances.current.identity_store_ids[0], aws_identitystore_user.admin_user.identity_store_id)
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "IdentityFederation"
      ManagedBy   = "Terraform"
      Recipe      = "identity-federation-aws-sso"
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 Bucket for CloudTrail Logs
# ============================================================================

resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket        = "${var.resource_prefix}-audit-logs-${local.account_id}-${local.resource_suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-audit-logs"
    Type = "CloudTrail"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      }
    ]
  })
}

# ============================================================================
# CloudTrail for Audit Logging
# ============================================================================

resource "aws_cloudtrail" "identity_federation_audit" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name                          = "${var.resource_prefix}-audit-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail_logs[0].bucket
  s3_key_prefix               = "identity-federation/"
  include_global_service_events = true
  is_multi_region_trail       = true
  enable_log_file_validation  = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.cloudtrail_logs[0].arn}/*"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-audit-trail"
    Type = "CloudTrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# ============================================================================
# CloudWatch Log Group for SSO Audit Logs
# ============================================================================

resource "aws_cloudwatch_log_group" "sso_audit_logs" {
  name              = "/aws/sso/audit-logs"
  retention_in_days = var.cloudtrail_retention_days

  tags = merge(local.common_tags, {
    Name = "SSO Audit Logs"
    Type = "CloudWatch"
  })
}

# ============================================================================
# IAM Identity Center Permission Sets
# ============================================================================

resource "aws_ssoadmin_permission_set" "permission_sets" {
  for_each = var.permission_sets

  instance_arn     = local.sso_instance_arn
  name             = "${var.resource_prefix}-${each.value.name}"
  description      = each.value.description
  session_duration = each.value.session_duration
  relay_state      = each.value.relay_state

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-${each.value.name}"
    Type = "PermissionSet"
    Role = each.key
  })
}

# Attach AWS managed policies to permission sets
resource "aws_ssoadmin_managed_policy_attachment" "managed_policies" {
  for_each = {
    for combo in flatten([
      for ps_key, ps_config in var.permission_sets : [
        for policy in ps_config.managed_policies : {
          permission_set_key = ps_key
          policy_arn        = policy
          unique_key        = "${ps_key}-${replace(policy, ":", "-")}"
        }
      ]
    ]) : combo.unique_key => combo
  }

  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.permission_sets[each.value.permission_set_key].arn
}

# Attach inline policies to permission sets
resource "aws_ssoadmin_permission_set_inline_policy" "inline_policies" {
  for_each = {
    for ps_key, ps_config in var.permission_sets : ps_key => ps_config
    if ps_config.inline_policy != ""
  }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permission_sets[each.key].arn
  inline_policy      = each.value.inline_policy
}

# ============================================================================
# Account Assignments
# ============================================================================

resource "aws_ssoadmin_account_assignment" "account_assignments" {
  for_each = var.account_assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.permission_sets[each.value.permission_set].arn

  principal_id   = each.value.principal_id
  principal_type = each.value.principal_type

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.managed_policies,
    aws_ssoadmin_permission_set_inline_policy.inline_policies
  ]
}

# ============================================================================
# SAML Applications (Optional)
# ============================================================================

resource "aws_ssoadmin_application" "saml_applications" {
  for_each = var.applications

  instance_arn  = local.sso_instance_arn
  name          = each.value.name
  description   = each.value.description
  client_token  = each.value.client_token
  status        = each.value.status

  portal_options {
    visibility = each.value.portal_visibility ? "ENABLED" : "DISABLED"
    sign_in_options {
      origin          = "IDENTITY_CENTER"
      application_url = each.value.application_url
    }
  }

  tags = merge(local.common_tags, {
    Name = each.value.name
    Type = "Application"
  })
}

# ============================================================================
# SNS Topic for Alerts (if email provided)
# ============================================================================

resource "aws_sns_topic" "identity_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? 1 : 0
  
  name = "${var.resource_prefix}-identity-alerts"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-identity-alerts"
    Type = "SNS"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.identity_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# ============================================================================
# CloudWatch Alarms for Monitoring
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "sso_sign_in_failures" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.resource_prefix}-sso-sign-in-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SignInFailures"
  namespace           = "AWS/SSO"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors SSO sign-in failures"
  insufficient_data_actions = []

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.identity_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-sso-sign-in-failures"
    Type = "CloudWatchAlarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "unusual_sign_in_activity" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.resource_prefix}-unusual-sign-in-activity"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SignInAttempts"
  namespace           = "AWS/SSO"
  period              = "900"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "This metric monitors for unusual sign-in activity patterns"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_notification_email != "" ? [aws_sns_topic.identity_alerts[0].arn] : []

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-unusual-sign-in-activity"
    Type = "CloudWatchAlarm"
  })
}

# ============================================================================
# CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "identity_federation" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "IdentityFederationDashboard"

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
            ["AWS/SSO", "SignInAttempts"],
            [".", "SignInSuccesses"],
            [".", "SignInFailures"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region_name
          title   = "Identity Center Sign-in Metrics"
          period  = 300
          stat    = "Sum"
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
            ["AWS/SSO", "ActiveSessions"],
            [".", "SessionDuration"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region_name
          title   = "Session Metrics"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 12
        height = 12

        properties = {
          query   = "SOURCE '/aws/sso/audit-logs' | fields @timestamp, eventName, sourceIPAddress, userIdentity.type | filter eventName like /SignIn/ | stats count() by sourceIPAddress | sort count desc"
          region  = local.region_name
          title   = "Sign-in Activity by IP Address"
          view    = "table"
        }
      }
    ]
  })
}

# ============================================================================
# Systems Manager Document for Disaster Recovery
# ============================================================================

resource "aws_ssm_document" "disaster_recovery_runbook" {
  count = var.enable_backup_configuration ? 1 : 0
  
  name            = "${var.resource_prefix}-disaster-recovery"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Disaster recovery procedures for Identity Federation"
    parameters = {
      BackupRegion = {
        type        = "String"
        description = "Region to restore from"
        default     = var.backup_regions[0]
      }
    }
    mainSteps = [
      {
        name   = "ValidateBackupRegion"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api     = "DescribeRegions"
        }
      },
      {
        name   = "NotifyDRInitiation"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "sns"
          Api     = "Publish"
          TopicArn = var.alarm_notification_email != "" ? aws_sns_topic.identity_alerts[0].arn : ""
          Message  = "Identity Federation disaster recovery initiated"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-disaster-recovery"
    Type = "SSMDocument"
  })
}

# ============================================================================
# Example Identity Store User (for testing - remove in production)
# ============================================================================

resource "aws_identitystore_user" "admin_user" {
  count = var.environment == "dev" ? 1 : 0
  
  identity_store_id = local.sso_identity_store_id

  display_name = "Admin User"
  user_name    = "admin.user@example.com"

  name {
    given_name  = "Admin"
    family_name = "User"
  }

  emails {
    value   = "admin.user@example.com"
    primary = true
    type    = "work"
  }
}

resource "aws_identitystore_group" "admin_group" {
  count = var.environment == "dev" ? 1 : 0
  
  identity_store_id = local.sso_identity_store_id
  display_name      = "Administrators"
  description       = "System administrators group"
}

resource "aws_identitystore_group_membership" "admin_membership" {
  count = var.environment == "dev" ? 1 : 0
  
  identity_store_id = local.sso_identity_store_id
  group_id          = aws_identitystore_group.admin_group[0].group_id
  member_id         = aws_identitystore_user.admin_user[0].user_id
}

# ============================================================================
# Time delay for resource dependencies
# ============================================================================

resource "time_sleep" "wait_for_permission_sets" {
  depends_on = [
    aws_ssoadmin_permission_set.permission_sets,
    aws_ssoadmin_managed_policy_attachment.managed_policies,
    aws_ssoadmin_permission_set_inline_policy.inline_policies
  ]

  create_duration = "30s"
}