# Main Terraform configuration for IoT Security implementation
# This configuration implements comprehensive IoT security using AWS IoT Core,
# Device Defender, and CloudWatch monitoring with certificate-based authentication

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  unique_suffix = random_id.suffix.hex
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "iot-security-device-certificates-policies"
  })
}

# ===============================================================================
# IoT Core Configuration
# ===============================================================================

# Create IoT Thing Type for categorizing industrial sensors
resource "aws_iot_thing_type" "industrial_sensor" {
  name        = var.thing_type_name
  description = "Industrial IoT sensors with security controls"

  properties {
    thing_type_description = "Industrial sensors for manufacturing environments"
    searchable_attributes  = ["location", "deviceType", "firmwareVersion"]
  }

  tags = local.common_tags
}

# Create IoT Thing Group for organizing devices
resource "aws_iot_thing_group" "industrial_sensors" {
  name = "IndustrialSensors"

  properties {
    thing_group_description = "Industrial sensor devices"
    attribute_payload {
      attributes = {
        "deviceType" = "industrial-sensor"
        "managed"    = "terraform"
      }
    }
  }

  tags = local.common_tags
}

# ===============================================================================
# IoT Security Policies
# ===============================================================================

# Restrictive IoT policy for sensor devices with least privilege access
resource "aws_iot_policy" "restrictive_sensor_policy" {
  name = "RestrictiveSensorPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iot:Connect"
        Resource = "arn:aws:iot:*:*:client/$${iot:Connection.Thing.ThingName}"
        Condition = {
          Bool = {
            "iot:Connection.Thing.IsAttached" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = [
          "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/telemetry",
          "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/status"
        ]
      },
      {
        Effect = "Allow"
        Action = "iot:Subscribe"
        Resource = [
          "arn:aws:iot:*:*:topicfilter/sensors/$${iot:Connection.Thing.ThingName}/commands",
          "arn:aws:iot:*:*:topicfilter/sensors/$${iot:Connection.Thing.ThingName}/config"
        ]
      },
      {
        Effect = "Allow"
        Action = "iot:Receive"
        Resource = [
          "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/commands",
          "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/config"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iot:UpdateThingShadow",
          "iot:GetThingShadow"
        ]
        Resource = "arn:aws:iot:*:*:thing/$${iot:Connection.Thing.ThingName}"
      }
    ]
  })

  tags = local.common_tags
}

# Time-based access policy (optional)
resource "aws_iot_policy" "time_based_access_policy" {
  count = var.enable_time_based_access ? 1 : 0
  name  = "TimeBasedAccessPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iot:Connect"
        Resource = "arn:aws:iot:*:*:client/$${iot:Connection.Thing.ThingName}"
        Condition = {
          Bool = {
            "iot:Connection.Thing.IsAttached" = "true"
          }
          DateGreaterThan = {
            "aws:CurrentTime" = var.business_hours_start
          }
          DateLessThan = {
            "aws:CurrentTime" = var.business_hours_end
          }
        }
      },
      {
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/telemetry"
        Condition = {
          StringEquals = {
            "iot:Connection.Thing.ThingTypeName" = var.thing_type_name
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Location-based access policy
resource "aws_iot_policy" "location_based_access_policy" {
  count = var.enable_location_based_access ? 1 : 0
  name  = "LocationBasedAccessPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "iot:Connect"
        Resource = "arn:aws:iot:*:*:client/$${iot:Connection.Thing.ThingName}"
        Condition = {
          Bool = {
            "iot:Connection.Thing.IsAttached" = "true"
          }
          StringEquals = {
            "iot:Connection.Thing.Attributes[location]" = var.factory_locations
          }
        }
      },
      {
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = "arn:aws:iot:*:*:topic/sensors/$${iot:Connection.Thing.ThingName}/*"
        Condition = {
          StringLike = {
            "iot:Connection.Thing.Attributes[location]" = "factory-*"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Device quarantine policy for incident response
resource "aws_iot_policy" "device_quarantine_policy" {
  name = "DeviceQuarantinePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = "*"
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# ===============================================================================
# IoT Devices and Certificates
# ===============================================================================

# Generate TLS private keys for device certificates
resource "tls_private_key" "device_keys" {
  count     = var.number_of_devices
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate certificate signing requests for each device
resource "tls_cert_request" "device_csr" {
  count           = var.number_of_devices
  private_key_pem = tls_private_key.device_keys[count.index].private_key_pem

  subject {
    common_name  = "${var.device_prefix}-${format("%03d", count.index + 1)}"
    organization = "IoT Security Demo"
  }
}

# Create IoT certificates for each device
resource "aws_iot_certificate" "device_certificates" {
  count  = var.number_of_devices
  csr    = tls_cert_request.device_csr[count.index].cert_request_pem
  active = true

  tags = merge(local.common_tags, {
    DeviceId = "${var.device_prefix}-${format("%03d", count.index + 1)}"
  })
}

# Create IoT Things (devices) with attributes
resource "aws_iot_thing" "devices" {
  count           = var.number_of_devices
  name            = "${var.device_prefix}-${format("%03d", count.index + 1)}"
  thing_type_name = aws_iot_thing_type.industrial_sensor.name

  attributes = {
    location        = var.factory_locations[count.index % length(var.factory_locations)]
    deviceType      = "temperature-sensor"
    firmwareVersion = "1.0.0"
    managedBy       = "terraform"
  }

  tags = merge(local.common_tags, {
    DeviceId = "${var.device_prefix}-${format("%03d", count.index + 1)}"
    Location = var.factory_locations[count.index % length(var.factory_locations)]
  })
}

# Attach certificates to IoT Things
resource "aws_iot_thing_principal_attachment" "device_cert_attachment" {
  count     = var.number_of_devices
  thing     = aws_iot_thing.devices[count.index].name
  principal = aws_iot_certificate.device_certificates[count.index].arn
}

# Attach security policy to certificates
resource "aws_iot_policy_attachment" "device_policy_attachment" {
  count  = var.number_of_devices
  policy = aws_iot_policy.restrictive_sensor_policy.name
  target = aws_iot_certificate.device_certificates[count.index].arn
}

# Add devices to thing group
resource "aws_iot_thing_group_membership" "device_group_membership" {
  count            = var.number_of_devices
  thing_name       = aws_iot_thing.devices[count.index].name
  thing_group_name = aws_iot_thing_group.industrial_sensors.name

  override_dynamic_group = false
}

# ===============================================================================
# AWS IoT Device Defender Security Profiles
# ===============================================================================

# Device Defender security profile for anomaly detection
resource "aws_iot_security_profile" "industrial_sensor_security" {
  count = var.enable_device_defender ? 1 : 0
  name  = "IndustrialSensorSecurity"

  description = "Security monitoring for industrial IoT sensors"

  # Excessive connections behavior
  behaviors {
    name   = "ExcessiveConnections"
    metric = "aws:num-connections"

    criteria {
      comparison_operator                = "greater-than"
      value_count                       = var.max_connections_threshold
      consecutive_datapoints_to_alarm   = 2
      consecutive_datapoints_to_clear   = 2
    }
  }

  # Unauthorized operations behavior
  behaviors {
    name   = "UnauthorizedOperations"
    metric = "aws:num-authorization-failures"

    criteria {
      comparison_operator                = "greater-than"
      value_count                       = var.authorization_failures_threshold
      duration_seconds                  = 300
      consecutive_datapoints_to_alarm   = 1
      consecutive_datapoints_to_clear   = 1
    }
  }

  # Message size anomaly behavior
  behaviors {
    name   = "MessageSizeAnomaly"
    metric = "aws:message-byte-size"

    criteria {
      comparison_operator                = "greater-than"
      value_count                       = var.message_size_threshold_bytes
      consecutive_datapoints_to_alarm   = 3
      consecutive_datapoints_to_clear   = 3
    }
  }

  # Alert targets (CloudWatch and SNS integration handled separately)
  alert_targets = {
    SNS = {
      alert_target_arn = var.enable_cloudwatch_monitoring ? aws_sns_topic.iot_security_alerts[0].arn : null
      role_arn        = var.enable_cloudwatch_monitoring ? aws_iam_role.device_defender_role[0].arn : null
    }
  }

  tags = local.common_tags
}

# Attach security profile to thing group
resource "aws_iot_security_profile_target" "thing_group_target" {
  count               = var.enable_device_defender ? 1 : 0
  security_profile_name = aws_iot_security_profile.industrial_sensor_security[0].name
  security_profile_target_arn = aws_iot_thing_group.industrial_sensors.arn
}

# ===============================================================================
# IAM Roles and Policies
# ===============================================================================

# IAM role for Device Defender
resource "aws_iam_role" "device_defender_role" {
  count = var.enable_device_defender ? 1 : 0
  name  = "${local.name_prefix}-device-defender-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Device Defender to publish to SNS
resource "aws_iam_role_policy" "device_defender_sns_policy" {
  count = var.enable_device_defender ? 1 : 0
  name  = "DeviceDefenderSNSPolicy"
  role  = aws_iam_role.device_defender_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_cloudwatch_monitoring ? aws_sns_topic.iot_security_alerts[0].arn : "*"
      }
    ]
  })
}

# IAM role for Lambda security event processor
resource "aws_iam_role" "security_processor_role" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = "${local.name_prefix}-security-processor-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda to access DynamoDB and CloudWatch Logs
resource "aws_iam_role_policy" "security_processor_policy" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = "SecurityProcessorPolicy"
  role  = aws_iam_role.security_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.iot_security_events[0].arn
      }
    ]
  })
}

# IAM role for certificate rotation Lambda
resource "aws_iam_role" "certificate_rotation_role" {
  name = "${local.name_prefix}-cert-rotation-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for certificate rotation
resource "aws_iam_role_policy" "certificate_rotation_policy" {
  name = "CertificateRotationPolicy"
  role = aws_iam_role.certificate_rotation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:ListCertificates",
          "iot:DescribeCertificate",
          "iot:CreateKeysAndCertificate",
          "iot:UpdateCertificate",
          "iot:AttachPolicy",
          "iot:DetachPolicy",
          "iot:AttachThingPrincipal",
          "iot:DetachThingPrincipal"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===============================================================================
# CloudWatch Monitoring and Alerting
# ===============================================================================

# CloudWatch Log Group for IoT security events
resource "aws_cloudwatch_log_group" "iot_security_events" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/iot/security-events"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# SNS Topic for security alerts
resource "aws_sns_topic" "iot_security_alerts" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0
  name  = "${local.name_prefix}-iot-security-alerts-${local.unique_suffix}"

  tags = local.common_tags
}

# SNS Topic subscription for email notifications (optional)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_cloudwatch_monitoring && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.iot_security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Alarm for unauthorized connections
resource "aws_cloudwatch_metric_alarm" "unauthorized_connections" {
  count               = var.enable_cloudwatch_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-iot-unauthorized-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Connect.AuthError"
  namespace           = "AWS/IoT"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.authorization_failures_threshold
  alarm_description   = "Alert on unauthorized IoT connection attempts"
  alarm_actions       = [aws_sns_topic.iot_security_alerts[0].arn]

  treat_missing_data = "notBreaching"

  tags = local.common_tags
}

# CloudWatch Dashboard for IoT security metrics
resource "aws_cloudwatch_dashboard" "iot_security_dashboard" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-iot-security-dashboard"

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
            ["AWS/IoT", "Connect.Success"],
            ["AWS/IoT", "Connect.AuthError"],
            ["AWS/IoT", "Connect.ClientError"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "IoT Connection Metrics"
          view   = "timeSeries"
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
            ["AWS/IoT", "PublishIn.Success"],
            ["AWS/IoT", "PublishIn.AuthError"],
            ["AWS/IoT", "Subscribe.Success"],
            ["AWS/IoT", "Subscribe.AuthError"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "IoT Message Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ===============================================================================
# DynamoDB Table for Security Events
# ===============================================================================

# DynamoDB table for storing IoT security events
resource "aws_dynamodb_table" "iot_security_events" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  name           = "${local.name_prefix}-iot-security-events-${local.unique_suffix}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "eventId"

  attribute {
    name = "eventId"
    type = "S"
  }

  attribute {
    name = "deviceId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  global_secondary_index {
    name     = "DeviceIndex"
    hash_key = "deviceId"
    range_key = "timestamp"
    projection_type = "ALL"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = local.common_tags
}

# ===============================================================================
# Lambda Functions
# ===============================================================================

# Archive Lambda functions for deployment
data "archive_file" "security_processor_zip" {
  count       = var.enable_cloudwatch_monitoring ? 1 : 0
  type        = "zip"
  output_path = "/tmp/security_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda/security_processor.py", {
      table_name = aws_dynamodb_table.iot_security_events[0].name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for security event processing
resource "aws_lambda_function" "security_processor" {
  count            = var.enable_cloudwatch_monitoring ? 1 : 0
  filename         = data.archive_file.security_processor_zip[0].output_path
  function_name    = "${local.name_prefix}-security-processor-${local.unique_suffix}"
  role            = aws_iam_role.security_processor_role[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.security_processor_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.iot_security_events[0].name
    }
  }

  tags = local.common_tags
}

# Archive certificate rotation Lambda
data "archive_file" "certificate_rotation_zip" {
  type        = "zip"
  output_path = "/tmp/certificate_rotation.zip"
  
  source {
    content  = file("${path.module}/lambda/certificate_rotation.py")
    filename = "lambda_function.py"
  }
}

# Lambda function for certificate rotation monitoring
resource "aws_lambda_function" "certificate_rotation" {
  filename         = data.archive_file.certificate_rotation_zip.output_path
  function_name    = "${local.name_prefix}-cert-rotation-${local.unique_suffix}"
  role            = aws_iam_role.certificate_rotation_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.certificate_rotation_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  tags = local.common_tags
}

# EventBridge rule for periodic certificate checks
resource "aws_cloudwatch_event_rule" "certificate_rotation_schedule" {
  name                = "${local.name_prefix}-cert-rotation-schedule"
  description         = "Weekly check for certificate rotation needs"
  schedule_expression = "rate(7 days)"
  state              = "ENABLED"

  tags = local.common_tags
}

# EventBridge target for certificate rotation Lambda
resource "aws_cloudwatch_event_target" "certificate_rotation_target" {
  rule      = aws_cloudwatch_event_rule.certificate_rotation_schedule.name
  target_id = "CertificateRotationTarget"
  arn       = aws_lambda_function.certificate_rotation.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge_cert_rotation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.certificate_rotation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.certificate_rotation_schedule.arn
}

# ===============================================================================
# IoT Rules Engine (Optional)
# ===============================================================================

# IoT Rule for processing security events
resource "aws_iot_topic_rule" "security_event_rule" {
  count   = var.enable_cloudwatch_monitoring ? 1 : 0
  name    = replace("${local.name_prefix}_security_event_rule_${local.unique_suffix}", "-", "_")
  enabled = true

  sql         = "SELECT * FROM '$aws/events/certificates/+/+'"
  description = "Route IoT security events to Lambda for processing"

  lambda {
    function_arn = aws_lambda_function.security_processor[0].arn
  }

  tags = local.common_tags
}

# Permission for IoT to invoke security processor Lambda
resource "aws_lambda_permission" "allow_iot_security_processor" {
  count         = var.enable_cloudwatch_monitoring ? 1 : 0
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_processor[0].function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.security_event_rule[0].arn
}

# ===============================================================================
# AWS Config Rules for Compliance (Optional)
# ===============================================================================

# Configuration recorder (required for Config rules)
resource "aws_config_configuration_recorder" "iot_compliance" {
  count    = var.enable_automated_compliance ? 1 : 0
  name     = "${local.name_prefix}-iot-compliance-recorder"
  role_arn = aws_iam_role.config_role[0].arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types               = ["AWS::IoT::Certificate", "AWS::IoT::Policy"]
  }

  depends_on = [aws_config_delivery_channel.iot_compliance]
}

# S3 bucket for Config
resource "aws_s3_bucket" "config_bucket" {
  count  = var.enable_automated_compliance ? 1 : 0
  bucket = "${local.name_prefix}-config-bucket-${local.unique_suffix}"

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  count  = var.enable_automated_compliance ? 1 : 0
  bucket = aws_s3_bucket.config_bucket[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Config delivery channel
resource "aws_config_delivery_channel" "iot_compliance" {
  count          = var.enable_automated_compliance ? 1 : 0
  name           = "${local.name_prefix}-iot-compliance-channel"
  s3_bucket_name = aws_s3_bucket.config_bucket[0].bucket
}

# IAM role for Config
resource "aws_iam_role" "config_role" {
  count = var.enable_automated_compliance ? 1 : 0
  name  = "${local.name_prefix}-config-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach Config service role policy
resource "aws_iam_role_policy_attachment" "config_role_policy" {
  count      = var.enable_automated_compliance ? 1 : 0
  role       = aws_iam_role.config_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}