# IoT Device Fleet Monitoring with CloudWatch and Device Defender
# This Terraform configuration creates a comprehensive IoT device fleet monitoring system

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  # Common resource naming
  resource_prefix = "${var.fleet_name}-${random_password.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    FleetName   = var.fleet_name
    Environment = var.environment
    Project     = "IoT Fleet Monitoring"
    ManagedBy   = "Terraform"
  })
  
  # Security profile behaviors configuration
  security_behaviors = [
    {
      name   = "AuthorizationFailures"
      metric = "aws:num-authorization-failures"
      criteria = {
        comparisonOperator              = "greater-than"
        value                          = var.security_profile_behaviors.authorization_failures_threshold
        durationSeconds                = var.security_profile_behaviors.duration_seconds
        consecutiveDatapointsToAlarm   = 2
        consecutiveDatapointsToClear   = 2
      }
    },
    {
      name   = "MessageByteSize"
      metric = "aws:message-byte-size"
      criteria = {
        comparisonOperator              = "greater-than"
        value                          = var.security_profile_behaviors.message_byte_size_threshold
        consecutiveDatapointsToAlarm   = 3
        consecutiveDatapointsToClear   = 1
      }
    },
    {
      name   = "MessagesReceived"
      metric = "aws:num-messages-received"
      criteria = {
        comparisonOperator              = "greater-than"
        value                          = var.security_profile_behaviors.messages_received_threshold
        durationSeconds                = var.security_profile_behaviors.duration_seconds
        consecutiveDatapointsToAlarm   = 2
        consecutiveDatapointsToClear   = 2
      }
    },
    {
      name   = "MessagesSent"
      metric = "aws:num-messages-sent"
      criteria = {
        comparisonOperator              = "greater-than"
        value                          = var.security_profile_behaviors.messages_sent_threshold
        durationSeconds                = var.security_profile_behaviors.duration_seconds
        consecutiveDatapointsToAlarm   = 2
        consecutiveDatapointsToClear   = 2
      }
    },
    {
      name   = "ConnectionAttempts"
      metric = "aws:num-connection-attempts"
      criteria = {
        comparisonOperator              = "greater-than"
        value                          = var.security_profile_behaviors.connection_attempts_threshold
        durationSeconds                = var.security_profile_behaviors.duration_seconds
        consecutiveDatapointsToAlarm   = 2
        consecutiveDatapointsToClear   = 2
      }
    }
  ]
}

# ==========================================
# IAM ROLES AND POLICIES
# ==========================================

# IAM role for AWS IoT Device Defender
resource "aws_iam_role" "device_defender_role" {
  name = "IoTDeviceDefenderRole-${local.resource_prefix}"
  
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

# Attach Device Defender audit policy
resource "aws_iam_role_policy_attachment" "device_defender_audit_policy" {
  role       = aws_iam_role.device_defender_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit"
}

# IAM role for Lambda remediation function
resource "aws_iam_role" "lambda_remediation_role" {
  name = "IoTFleetRemediationRole-${local.resource_prefix}"
  
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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda remediation actions
resource "aws_iam_policy" "lambda_remediation_policy" {
  name        = "IoTFleetRemediationPolicy-${local.resource_prefix}"
  description = "Policy for IoT fleet remediation Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:UpdateCertificate",
          "iot:DetachThingPrincipal",
          "iot:ListThingPrincipals",
          "iot:DescribeThing",
          "iot:UpdateThing",
          "iot:ListThingsInThingGroup",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_remediation_policy_attachment" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = aws_iam_policy.lambda_remediation_policy.arn
}

# IAM role for IoT Rules Engine
resource "aws_iam_role" "iot_rules_role" {
  name = "IoTRulesRole-${local.resource_prefix}"
  
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

# Policy for IoT Rules Engine
resource "aws_iam_policy" "iot_rules_policy" {
  name        = "IoTRulesPolicy-${local.resource_prefix}"
  description = "Policy for IoT Rules Engine actions"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach IoT Rules policy
resource "aws_iam_role_policy_attachment" "iot_rules_policy_attachment" {
  role       = aws_iam_role.iot_rules_role.name
  policy_arn = aws_iam_policy.iot_rules_policy.arn
}

# ==========================================
# SNS TOPIC FOR NOTIFICATIONS
# ==========================================

# SNS topic for fleet alerts
resource "aws_sns_topic" "fleet_alerts" {
  name = "iot-fleet-alerts-${local.resource_prefix}"
  
  tags = local.common_tags
}

# SNS topic policy to allow IoT services to publish
resource "aws_sns_topic_policy" "fleet_alerts_policy" {
  arn = aws_sns_topic.fleet_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.fleet_alerts.arn
      }
    ]
  })
}

# SNS email subscription for notifications
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.fleet_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS subscription for Lambda function
resource "aws_sns_topic_subscription" "lambda_notification" {
  topic_arn = aws_sns_topic.fleet_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.remediation_function.arn
}

# ==========================================
# LAMBDA FUNCTION FOR AUTOMATED REMEDIATION
# ==========================================

# Lambda function code
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing IoT security violations
    """
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    process_security_violation(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed security violation')
        }
    
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_security_violation(message):
    """
    Process Device Defender security violation with intelligent remediation
    """
    
    violation_type = message.get('violationEventType', 'unknown')
    thing_name = message.get('thingName', 'unknown')
    behavior_name = message.get('behavior', {}).get('name', 'unknown')
    violation_id = message.get('violationId', 'unknown')
    
    logger.info(f"Processing violation: {violation_type} for {thing_name}, behavior: {behavior_name}")
    
    # Send custom metric to CloudWatch
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'SecurityViolations',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'ViolationType',
                        'Value': violation_type
                    },
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    },
                    {
                        'Name': 'ThingName',
                        'Value': thing_name
                    }
                ]
            }
        ]
    )
    
    # Implement remediation logic based on violation type
    if violation_type == 'in-alarm':
        handle_security_alarm(thing_name, behavior_name, violation_id)
    elif violation_type == 'alarm-cleared':
        handle_alarm_cleared(thing_name, behavior_name, violation_id)
    elif violation_type == 'alarm-invalidated':
        handle_alarm_invalidated(thing_name, behavior_name, violation_id)

def handle_security_alarm(thing_name, behavior_name, violation_id):
    """
    Handle security alarm with appropriate remediation based on behavior type
    """
    
    remediation_actions = []
    
    if behavior_name == 'AuthorizationFailures':
        # For repeated authorization failures, consider device isolation
        logger.warning(f"Authorization failures detected for {thing_name}")
        remediation_actions.append("Monitor device for potential compromise")
        
        # Get device details for assessment
        try:
            device_info = iot_client.describe_thing(thingName=thing_name)
            logger.info(f"Device info: {device_info}")
            
            # In production, you might temporarily disable the certificate
            # certificates = iot_client.list_thing_principals(thingName=thing_name)
            # for cert in certificates['principals']:
            #     iot_client.update_certificate(certificateId=cert_id, newStatus='INACTIVE')
            
        except Exception as e:
            logger.error(f"Error getting device info: {str(e)}")
            
    elif behavior_name == 'MessageByteSize':
        # Large message size might indicate data exfiltration
        logger.warning(f"Unusual message size detected for {thing_name}")
        remediation_actions.append("Investigate potential data exfiltration")
        
    elif behavior_name in ['MessagesReceived', 'MessagesSent']:
        # Unusual message volume might indicate compromised device
        logger.warning(f"Unusual message volume detected for {thing_name}")
        remediation_actions.append("Review device communication patterns")
        
    elif behavior_name == 'ConnectionAttempts':
        # Multiple connection attempts might indicate brute force attack
        logger.warning(f"Multiple connection attempts detected for {thing_name}")
        remediation_actions.append("Review connection source and patterns")
    
    # Log remediation actions
    logger.info(f"Remediation actions for {thing_name}: {remediation_actions}")
    
    # Send remediation metric
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'RemediationActions',
                'Value': len(remediation_actions),
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    },
                    {
                        'Name': 'ThingName',
                        'Value': thing_name
                    }
                ]
            }
        ]
    )

def handle_alarm_cleared(thing_name, behavior_name, violation_id):
    """
    Handle alarm cleared event - device behavior returned to normal
    """
    logger.info(f"Alarm cleared for {thing_name}, behavior: {behavior_name}")
    
    # Send metric indicating alarm cleared
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'SecurityAlarmsCleared',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    },
                    {
                        'Name': 'ThingName',
                        'Value': thing_name
                    }
                ]
            }
        ]
    )

def handle_alarm_invalidated(thing_name, behavior_name, violation_id):
    """
    Handle alarm invalidated event - alarm was false positive
    """
    logger.info(f"Alarm invalidated for {thing_name}, behavior: {behavior_name}")
    
    # Send metric indicating false positive
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'SecurityAlarmsFalsePositive',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    }
                ]
            }
        ]
    )
EOF
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function for automated remediation
resource "aws_lambda_function" "remediation_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "iot-fleet-remediation-${local.resource_prefix}"
  role            = aws_iam_role.lambda_remediation_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_function_config.runtime
  timeout         = var.lambda_function_config.timeout
  memory_size     = var.lambda_function_config.memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  description = "Automated remediation for IoT fleet security violations"
  
  environment {
    variables = {
      FLEET_NAME = var.fleet_name
      ENVIRONMENT = var.environment
    }
  }
  
  tags = local.common_tags
}

# Permission for SNS to invoke Lambda
resource "aws_lambda_permission" "sns_invoke_lambda" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_function.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.fleet_alerts.arn
}

# ==========================================
# CLOUDWATCH LOG GROUPS
# ==========================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.remediation_function.function_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# CloudWatch log group for IoT fleet monitoring
resource "aws_cloudwatch_log_group" "iot_fleet_logs" {
  name              = "/aws/iot/fleet-monitoring"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ==========================================
# IOT DEVICE DEFENDER CONFIGURATION
# ==========================================

# Enable Device Defender audit configuration
resource "aws_iot_account_audit_configuration" "fleet_audit" {
  account_id = data.aws_caller_identity.current.account_id
  role_arn   = aws_iam_role.device_defender_role.arn
  
  audit_check_configurations = {
    authenticated_cognito_role_overly_permissive_check = {
      enabled = true
    }
    ca_certificate_expiring_check = {
      enabled = true
    }
    conflicting_client_ids_check = {
      enabled = true
    }
    device_certificate_expiring_check = {
      enabled = true
    }
    device_certificate_shared_check = {
      enabled = true
    }
    iot_policy_overly_permissive_check = {
      enabled = true
    }
    logging_disabled_check = {
      enabled = true
    }
    revoked_ca_certificate_still_active_check = {
      enabled = true
    }
    revoked_device_certificate_still_active_check = {
      enabled = true
    }
  }
  
  audit_notification_target_configurations = {
    sns = {
      enabled    = true
      target_arn = aws_sns_topic.fleet_alerts.arn
      role_arn   = aws_iam_role.device_defender_role.arn
    }
  }
}

# Create IoT Device Defender Security Profile
resource "aws_iot_security_profile" "fleet_security_profile" {
  name        = "fleet-security-profile-${local.resource_prefix}"
  description = "Comprehensive security monitoring for IoT device fleet"
  
  # Define security behaviors
  dynamic "behaviors" {
    for_each = local.security_behaviors
    content {
      name   = behaviors.value.name
      metric = behaviors.value.metric
      
      criteria {
        comparison_operator               = behaviors.value.criteria.comparisonOperator
        value {
          count = behaviors.value.criteria.value
        }
        duration_seconds                 = try(behaviors.value.criteria.durationSeconds, null)
        consecutive_datapoints_to_alarm  = behaviors.value.criteria.consecutiveDatapointsToAlarm
        consecutive_datapoints_to_clear  = behaviors.value.criteria.consecutiveDatapointsToClear
      }
    }
  }
  
  # Alert targets
  alert_targets = {
    sns = {
      alert_target_arn = aws_sns_topic.fleet_alerts.arn
      role_arn        = aws_iam_role.device_defender_role.arn
    }
  }
  
  tags = local.common_tags
}

# Scheduled audit for compliance monitoring
resource "aws_iot_scheduled_audit" "daily_fleet_audit" {
  count = var.enable_scheduled_audit ? 1 : 0
  
  scheduled_audit_name = "DailyFleetAudit-${local.resource_prefix}"
  frequency           = var.audit_frequency
  
  target_check_names = [
    "CA_CERTIFICATE_EXPIRING_CHECK",
    "DEVICE_CERTIFICATE_EXPIRING_CHECK",
    "DEVICE_CERTIFICATE_SHARED_CHECK",
    "IOT_POLICY_OVERLY_PERMISSIVE_CHECK",
    "LOGGING_DISABLED_CHECK",
    "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK",
    "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK"
  ]
  
  tags = local.common_tags
}

# ==========================================
# IOT THING GROUP AND DEVICES
# ==========================================

# Create IoT Thing Group for fleet management
resource "aws_iot_thing_group" "fleet_group" {
  name = local.resource_prefix
  
  thing_group_properties {
    thing_group_description = "IoT device fleet for monitoring demonstration"
    
    attribute_payload {
      attributes = {
        Environment = var.environment
        FleetName   = var.fleet_name
        ManagedBy   = "Terraform"
      }
    }
  }
  
  tags = local.common_tags
}

# Create test IoT devices
resource "aws_iot_thing" "test_devices" {
  count = var.device_count
  
  name = "device-${local.resource_prefix}-${count.index + 1}"
  
  attributes = {
    deviceType = "sensor"
    location   = "facility-${count.index + 1}"
    firmware   = "v1.2.3"
    environment = var.environment
  }
  
  tags = local.common_tags
}

# Add devices to thing group
resource "aws_iot_thing_group_membership" "device_membership" {
  count = var.device_count
  
  thing_name       = aws_iot_thing.test_devices[count.index].name
  thing_group_name = aws_iot_thing_group.fleet_group.name
}

# Attach security profile to thing group
resource "aws_iot_security_profile_target" "fleet_security_target" {
  security_profile_name = aws_iot_security_profile.fleet_security_profile.name
  security_profile_target_arn = aws_iot_thing_group.fleet_group.arn
}

# ==========================================
# IOT RULES FOR MONITORING
# ==========================================

# IoT Rule for device connection monitoring
resource "aws_iot_topic_rule" "device_connection_monitoring" {
  name        = "DeviceConnectionMonitoring${replace(local.resource_prefix, "-", "")}"
  description = "Monitor device connection events"
  enabled     = true
  sql         = "SELECT * FROM \"$$aws/events/presence/connected/+\" WHERE eventType = \"connected\" OR eventType = \"disconnected\""
  sql_version = "2016-03-23"
  
  cloudwatch_metric {
    metric_name      = "DeviceConnectionEvents"
    metric_namespace = "AWS/IoT/FleetMonitoring"
    metric_timestamp = "$${timestamp()}"
    metric_unit      = "Count"
    metric_value     = "1"
    role_arn         = aws_iam_role.iot_rules_role.arn
  }
  
  cloudwatch_logs {
    log_group_name = aws_cloudwatch_log_group.iot_fleet_logs.name
    role_arn       = aws_iam_role.iot_rules_role.arn
  }
  
  tags = local.common_tags
}

# IoT Rule for message volume monitoring
resource "aws_iot_topic_rule" "message_volume_monitoring" {
  name        = "MessageVolumeMonitoring${replace(local.resource_prefix, "-", "")}"
  description = "Monitor message volume from devices"
  enabled     = true
  sql         = "SELECT clientId, timestamp, topic FROM \"device/+/data\""
  sql_version = "2016-03-23"
  
  cloudwatch_metric {
    metric_name      = "MessageVolume"
    metric_namespace = "AWS/IoT/FleetMonitoring"
    metric_timestamp = "$${timestamp()}"
    metric_unit      = "Count"
    metric_value     = "1"
    role_arn         = aws_iam_role.iot_rules_role.arn
  }
  
  tags = local.common_tags
}

# ==========================================
# CLOUDWATCH ALARMS
# ==========================================

# CloudWatch alarm for high security violations
resource "aws_cloudwatch_metric_alarm" "high_security_violations" {
  alarm_name          = "IoT-Fleet-High-Security-Violations-${local.resource_prefix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SecurityViolations"
  namespace           = "AWS/IoT/FleetMonitoring"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_thresholds.security_violations_threshold
  alarm_description   = "High number of security violations detected"
  
  dimensions = {
    FleetName = var.fleet_name
  }
  
  alarm_actions = [aws_sns_topic.fleet_alerts.arn]
  
  tags = local.common_tags
}

# CloudWatch alarm for device connectivity issues
resource "aws_cloudwatch_metric_alarm" "low_connectivity" {
  alarm_name          = "IoT-Fleet-Low-Connectivity-${local.resource_prefix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConnectedDevices"
  namespace           = "AWS/IoT"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_thresholds.low_connectivity_threshold
  alarm_description   = "Low device connectivity detected"
  treat_missing_data  = "notBreaching"
  
  alarm_actions = [aws_sns_topic.fleet_alerts.arn]
  
  tags = local.common_tags
}

# CloudWatch alarm for message processing errors
resource "aws_cloudwatch_metric_alarm" "message_processing_errors" {
  alarm_name          = "IoT-Fleet-Message-Processing-Errors-${local.resource_prefix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RuleMessageProcessingErrors"
  namespace           = "AWS/IoT"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_thresholds.processing_errors_threshold
  alarm_description   = "High message processing error rate"
  
  alarm_actions = [aws_sns_topic.fleet_alerts.arn]
  
  tags = local.common_tags
}

# ==========================================
# CLOUDWATCH DASHBOARD
# ==========================================

# Custom CloudWatch Dashboard for fleet monitoring
resource "aws_cloudwatch_dashboard" "fleet_dashboard" {
  dashboard_name = "IoT-Fleet-Dashboard-${local.resource_prefix}"
  
  dashboard_body = jsonencode({
    widgets = concat(
      var.dashboard_widgets.enable_device_overview ? [
        {
          type   = "metric"
          x      = 0
          y      = 0
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/IoT", "ConnectedDevices", { stat = "Average" }],
              [".", "MessagesSent", { stat = "Sum" }],
              [".", "MessagesReceived", { stat = "Sum" }]
            ]
            period = 300
            stat   = "Average"
            region = data.aws_region.current.name
            title  = "IoT Fleet Overview"
            yAxis = {
              left = {
                min = 0
              }
            }
          }
        }
      ] : [],
      var.dashboard_widgets.enable_security_violations ? [
        {
          type   = "metric"
          x      = 12
          y      = 0
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/IoT/FleetMonitoring", "SecurityViolations", "FleetName", var.fleet_name],
              [".", "SecurityAlarmsCleared", ".", "."]
            ]
            period = 300
            stat   = "Sum"
            region = data.aws_region.current.name
            title  = "Security Violations"
            yAxis = {
              left = {
                min = 0
              }
            }
          }
        }
      ] : [],
      var.dashboard_widgets.enable_message_processing ? [
        {
          type   = "metric"
          x      = 0
          y      = 6
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/IoT", "RuleMessageProcessingErrors", { stat = "Sum" }],
              [".", "RuleMessageProcessingSuccess", { stat = "Sum" }]
            ]
            period = 300
            stat   = "Sum"
            region = data.aws_region.current.name
            title  = "Message Processing"
            yAxis = {
              left = {
                min = 0
              }
            }
          }
        }
      ] : [],
      var.dashboard_widgets.enable_violation_logs ? [
        {
          type   = "log"
          x      = 12
          y      = 6
          width  = 12
          height = 6
          properties = {
            query  = "SOURCE '/aws/lambda/${aws_lambda_function.remediation_function.function_name}' | fields @timestamp, @message\n| filter @message like /violation/\n| sort @timestamp desc\n| limit 20"
            region = data.aws_region.current.name
            title  = "Security Violation Logs"
            view   = "table"
          }
        }
      ] : []
    )
  })
  
  depends_on = [
    aws_lambda_function.remediation_function,
    aws_cloudwatch_log_group.lambda_logs
  ]
}