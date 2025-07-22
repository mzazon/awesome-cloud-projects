# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  random_suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Construct security profile target ARN based on configuration
  security_profile_target_arn = var.security_profile_target == "all-registered-things" ? (
    "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:all/registered-things"
  ) : (
    "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thinggroup/${var.thing_group_name}"
  )
}

# SNS Topic for security alerts
resource "aws_sns_topic" "iot_security_alerts" {
  name = "iot-security-alerts-${local.random_suffix}"
  
  tags = {
    Name        = "IoT Security Alerts Topic"
    Description = "SNS topic for AWS IoT Device Defender security alerts"
  }
}

# SNS Topic Policy for IoT Device Defender access
resource "aws_sns_topic_policy" "iot_security_alerts_policy" {
  arn = aws_sns_topic.iot_security_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowIoTDeviceDefenderPublish"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.iot_security_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.iot_security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for AWS IoT Device Defender
resource "aws_iam_role" "device_defender_role" {
  name = "IoTDeviceDefenderRole-${local.random_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = {
    Name        = "IoT Device Defender Service Role"
    Description = "Service role for AWS IoT Device Defender operations"
  }
}

# Attach AWS managed policy for Device Defender audit operations
resource "aws_iam_role_policy_attachment" "device_defender_audit_policy" {
  role       = aws_iam_role.device_defender_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit"
}

# Additional IAM policy for SNS publishing
resource "aws_iam_role_policy" "device_defender_sns_policy" {
  name = "DeviceDefenderSNSPolicy-${local.random_suffix}"
  role = aws_iam_role.device_defender_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.iot_security_alerts.arn
      }
    ]
  })
}

# AWS IoT Device Defender Account Audit Configuration
resource "aws_iot_account_audit_configuration" "device_defender_audit" {
  account_id = data.aws_caller_identity.current.account_id
  role_arn   = aws_iam_role.device_defender_role.arn
  
  # Configure audit notification targets
  audit_notification_target_configurations {
    sns {
      target_arn = aws_sns_topic.iot_security_alerts.arn
      role_arn   = aws_iam_role.device_defender_role.arn
      enabled    = true
    }
  }
  
  # Configure audit checks based on variables
  audit_check_configurations {
    authenticated_cognito_role_overly_permissive_check {
      enabled = var.audit_checks.authenticated_cognito_role_overly_permissive
    }
    ca_certificate_expiring_check {
      enabled = var.audit_checks.ca_certificate_expiring
    }
    conflicting_client_ids_check {
      enabled = var.audit_checks.conflicting_client_ids
    }
    device_certificate_expiring_check {
      enabled = var.audit_checks.device_certificate_expiring
    }
    device_certificate_shared_check {
      enabled = var.audit_checks.device_certificate_shared
    }
    iot_policy_overly_permissive_check {
      enabled = var.audit_checks.iot_policy_overly_permissive
    }
    logging_disabled_check {
      enabled = var.audit_checks.logging_disabled
    }
    revoked_ca_certificate_still_active_check {
      enabled = var.audit_checks.revoked_ca_certificate_still_active
    }
    revoked_device_certificate_still_active_check {
      enabled = var.audit_checks.revoked_device_certificate_still_active
    }
    unauthenticated_cognito_role_overly_permissive_check {
      enabled = var.audit_checks.unauthenticated_cognito_role_overly_permissive
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.device_defender_audit_policy,
    aws_iam_role_policy.device_defender_sns_policy
  ]
}

# IoT Security Profile with behavioral rules
resource "aws_iot_security_profile" "iot_security_profile" {
  name        = "IoTSecurityProfile-${local.random_suffix}"
  description = "Comprehensive IoT security monitoring profile with behavioral rules"
  
  # Behavioral monitoring rules
  behaviors {
    name   = "ExcessiveMessages"
    metric = "aws:num-messages-sent"
    
    criteria {
      comparison_operator                = "greater-than"
      value {
        count = var.security_thresholds.max_messages_per_5min
      }
      duration_seconds                   = 300
      consecutive_datapoints_to_alarm    = 1
      consecutive_datapoints_to_clear    = 1
    }
  }
  
  behaviors {
    name   = "AuthorizationFailures"
    metric = "aws:num-authorization-failures"
    
    criteria {
      comparison_operator                = "greater-than"
      value {
        count = var.security_thresholds.max_authorization_failures
      }
      duration_seconds                   = 300
      consecutive_datapoints_to_alarm    = 1
      consecutive_datapoints_to_clear    = 1
    }
  }
  
  behaviors {
    name   = "LargeMessageSize"
    metric = "aws:message-byte-size"
    
    criteria {
      comparison_operator                = "greater-than"
      value {
        count = var.security_thresholds.max_message_size_bytes
      }
      consecutive_datapoints_to_alarm    = 1
      consecutive_datapoints_to_clear    = 1
    }
  }
  
  behaviors {
    name   = "UnusualConnectionAttempts"
    metric = "aws:num-connection-attempts"
    
    criteria {
      comparison_operator                = "greater-than"
      value {
        count = var.security_thresholds.max_connection_attempts_per_5min
      }
      duration_seconds                   = 300
      consecutive_datapoints_to_alarm    = 1
      consecutive_datapoints_to_clear    = 1
    }
  }
  
  # Alert targets configuration
  alert_targets {
    sns {
      target_arn = aws_sns_topic.iot_security_alerts.arn
      role_arn   = aws_iam_role.device_defender_role.arn
    }
  }
  
  tags = {
    Name        = "IoT Security Profile"
    Description = "Rule-based behavioral monitoring for IoT devices"
  }
  
  depends_on = [
    aws_iot_account_audit_configuration.device_defender_audit
  ]
}

# ML-based security profile (if enabled)
resource "aws_iot_security_profile" "iot_ml_security_profile" {
  count = var.enable_ml_detection ? 1 : 0
  
  name        = "IoTSecurityProfile-ML-${local.random_suffix}"
  description = "Machine learning based threat detection for IoT devices"
  
  # ML-based behavioral monitoring (no explicit criteria for ML learning)
  behaviors {
    name   = "MLMessagesReceived"
    metric = "aws:num-messages-received"
  }
  
  behaviors {
    name   = "MLMessagesSent"
    metric = "aws:num-messages-sent"
  }
  
  behaviors {
    name   = "MLConnectionAttempts"
    metric = "aws:num-connection-attempts"
  }
  
  behaviors {
    name   = "MLDisconnects"
    metric = "aws:num-disconnects"
  }
  
  # Alert targets configuration
  alert_targets {
    sns {
      target_arn = aws_sns_topic.iot_security_alerts.arn
      role_arn   = aws_iam_role.device_defender_role.arn
    }
  }
  
  tags = {
    Name        = "IoT ML Security Profile"
    Description = "Machine learning based behavioral monitoring for IoT devices"
  }
  
  depends_on = [
    aws_iot_account_audit_configuration.device_defender_audit
  ]
}

# Attach security profiles to target devices
resource "aws_iot_security_profile_target" "security_profile_attachment" {
  security_profile_name = aws_iot_security_profile.iot_security_profile.name
  security_profile_target_arn = local.security_profile_target_arn
}

resource "aws_iot_security_profile_target" "ml_security_profile_attachment" {
  count = var.enable_ml_detection ? 1 : 0
  
  security_profile_name = aws_iot_security_profile.iot_ml_security_profile[0].name
  security_profile_target_arn = local.security_profile_target_arn
}

# Scheduled audit task for regular security assessments
resource "aws_iot_scheduled_audit" "weekly_security_audit" {
  scheduled_audit_name = "WeeklySecurityAudit-${local.random_suffix}"
  frequency           = var.audit_schedule.frequency
  day_of_week         = var.audit_schedule.day_of_week
  
  target_check_names = [
    "CA_CERTIFICATE_EXPIRING_CHECK",
    "DEVICE_CERTIFICATE_EXPIRING_CHECK", 
    "DEVICE_CERTIFICATE_SHARED_CHECK",
    "IOT_POLICY_OVERLY_PERMISSIVE_CHECK",
    "CONFLICTING_CLIENT_IDS_CHECK"
  ]
  
  tags = {
    Name        = "Weekly Security Audit"
    Description = "Automated weekly security audit for IoT environment"
  }
  
  depends_on = [
    aws_iot_account_audit_configuration.device_defender_audit
  ]
}

# CloudWatch Alarm for security violations
resource "aws_cloudwatch_metric_alarm" "iot_security_violations" {
  alarm_name          = "IoT-SecurityViolations-${local.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_config.evaluation_periods
  metric_name         = "Violations"
  namespace           = "AWS/IoT/DeviceDefender"
  period              = var.cloudwatch_alarm_config.period_seconds
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_config.threshold
  alarm_description   = "Alert on IoT Device Defender security violations"
  treat_missing_data  = "notBreaching"
  
  alarm_actions = [aws_sns_topic.iot_security_alerts.arn]
  ok_actions    = [aws_sns_topic.iot_security_alerts.arn]
  
  tags = {
    Name        = "IoT Security Violations Alarm"
    Description = "CloudWatch alarm for Device Defender security violations"
  }
}