# Main Terraform configuration for IoT Device Provisioning and Certificate Management
# This file contains all the infrastructure resources needed for the solution

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  template_name   = "${var.resource_prefix}-template-${local.resource_suffix}"
  common_tags = merge(var.additional_tags, {
    Project     = "IoTProvisioning"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ============================================================================
# DynamoDB Table for Device Registry
# ============================================================================

resource "aws_dynamodb_table" "device_registry" {
  name           = "${var.resource_prefix}-device-registry-${local.resource_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "serialNumber"
  
  attribute {
    name = "serialNumber"
    type = "S"
  }
  
  attribute {
    name = "deviceType"
    type = "S"
  }
  
  global_secondary_index {
    name            = "DeviceTypeIndex"
    hash_key        = "deviceType"
    projection_type = "ALL"
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-device-registry-${local.resource_suffix}"
  })
}

# ============================================================================
# IAM Role for Lambda Pre-Provisioning Hook
# ============================================================================

# Trust policy for Lambda execution role
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Create Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.resource_prefix}-lambda-execution-role-${local.resource_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-lambda-execution-role-${local.resource_suffix}"
  })
}

# Lambda execution policy document
data "aws_iam_policy_document" "lambda_execution_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query"
    ]
    
    resources = [
      aws_dynamodb_table.device_registry.arn,
      "${aws_dynamodb_table.device_registry.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "iot:DescribeThing",
      "iot:ListThingTypes"
    ]
    
    resources = ["*"]
  }
}

# Attach policy to Lambda execution role
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name   = "${var.resource_prefix}-lambda-execution-policy-${local.resource_suffix}"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_execution_policy.json
}

# ============================================================================
# Lambda Function for Pre-Provisioning Hook
# ============================================================================

# Create Lambda function package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      device_registry_table = aws_dynamodb_table.device_registry.name
    })
    filename = "lambda_function.py"
  }
}

# Deploy Lambda function
resource "aws_lambda_function" "provisioning_hook" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.resource_prefix}-provisioning-hook-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      DEVICE_REGISTRY_TABLE = aws_dynamodb_table.device_registry.name
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-provisioning-hook-${local.resource_suffix}"
  })
}

# ============================================================================
# IAM Role for IoT Provisioning
# ============================================================================

# Trust policy for IoT service
data "aws_iam_policy_document" "iot_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Create IoT provisioning role
resource "aws_iam_role" "iot_provisioning_role" {
  name               = "${var.resource_prefix}-iot-provisioning-role-${local.resource_suffix}"
  assume_role_policy = data.aws_iam_policy_document.iot_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-iot-provisioning-role-${local.resource_suffix}"
  })
}

# IoT provisioning policy document
data "aws_iam_policy_document" "iot_provisioning_policy" {
  statement {
    effect = "Allow"
    
    actions = [
      "iot:CreateThing",
      "iot:DescribeThing",
      "iot:CreateKeysAndCertificate",
      "iot:AttachThingPrincipal",
      "iot:AttachPolicy",
      "iot:AddThingToThingGroup",
      "iot:UpdateThingShadow"
    ]
    
    resources = ["*"]
  }
  
  statement {
    effect = "Allow"
    
    actions = [
      "lambda:InvokeFunction"
    ]
    
    resources = [aws_lambda_function.provisioning_hook.arn]
  }
}

# Attach policy to IoT provisioning role
resource "aws_iam_role_policy" "iot_provisioning_policy" {
  name   = "${var.resource_prefix}-iot-provisioning-policy-${local.resource_suffix}"
  role   = aws_iam_role.iot_provisioning_role.id
  policy = data.aws_iam_policy_document.iot_provisioning_policy.json
}

# ============================================================================
# IoT Thing Groups
# ============================================================================

# Parent thing group for all provisioned devices
resource "aws_iot_thing_group" "provisioned_devices" {
  name = "${var.resource_prefix}-provisioned-devices-${local.resource_suffix}"
  
  thing_group_properties {
    thing_group_description = "Parent group for all provisioned devices"
  }
  
  tags = local.common_tags
}

# Device-type specific thing groups
resource "aws_iot_thing_group" "device_type_groups" {
  for_each = toset(var.device_types)
  
  name = "${each.value}-devices"
  
  thing_group_properties {
    thing_group_description = "${each.value} devices"
    parent_group_name      = aws_iot_thing_group.provisioned_devices.name
  }
  
  tags = merge(local.common_tags, {
    DeviceType = each.value
  })
}

# ============================================================================
# IoT Policies
# ============================================================================

# Policy for temperature sensors
resource "aws_iot_policy" "temperature_sensor_policy" {
  name = "TemperatureSensorPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/temperature-sensor-*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/sensors/temperature/*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe", "iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/config/temperature-sensor/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/config/temperature-sensor/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:GetThingShadow", "iot:UpdateThingShadow"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thing/temperature-sensor-*"
      }
    ]
  })
}

# Policy for gateway devices
resource "aws_iot_policy" "gateway_policy" {
  name = "GatewayDevicePolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/gateway-*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/gateway/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/sensors/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe", "iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/config/gateway/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/config/gateway/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/commands/*",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/commands/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["iot:GetThingShadow", "iot:UpdateThingShadow"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thing/gateway-*"
      }
    ]
  })
}

# Policy for claim certificate
resource "aws_iot_policy" "claim_certificate_policy" {
  name = "ClaimCertificatePolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$$aws/provisioning-templates/${local.template_name}/provision/*"
      },
      {
        Effect = "Allow"
        Action = ["iot:Subscribe", "iot:Receive"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$$aws/provisioning-templates/${local.template_name}/provision/*"
        ]
      }
    ]
  })
}

# ============================================================================
# IoT Provisioning Template
# ============================================================================

resource "aws_iot_provisioning_template" "device_provisioning" {
  name        = local.template_name
  description = "Template for automated device provisioning with validation"
  enabled     = true
  
  provisioning_role_arn = aws_iam_role.iot_provisioning_role.arn
  
  pre_provisioning_hook {
    target_arn     = aws_lambda_function.provisioning_hook.arn
    payload_version = "2020-04-01"
  }
  
  template_body = jsonencode({
    Parameters = {
      SerialNumber = {
        Type = "String"
      }
      DeviceType = {
        Type = "String"
      }
      FirmwareVersion = {
        Type = "String"
      }
      Manufacturer = {
        Type = "String"
      }
      Location = {
        Type = "String"
      }
      "AWS::IoT::Certificate::Id" = {
        Type = "String"
      }
      "AWS::IoT::Certificate::Arn" = {
        Type = "String"
      }
    }
    Resources = {
      thing = {
        Type = "AWS::IoT::Thing"
        Properties = {
          ThingName = {
            Ref = "ThingName"
          }
          AttributePayload = {
            serialNumber = {
              Ref = "SerialNumber"
            }
            deviceType = {
              Ref = "DeviceType"
            }
            firmwareVersion = {
              Ref = "FirmwareVersion"
            }
            manufacturer = {
              Ref = "Manufacturer"
            }
            location = {
              Ref = "DeviceLocation"
            }
            provisioningTime = {
              Ref = "ProvisioningTime"
            }
          }
          ThingTypeName = "IoTDevice"
        }
      }
      certificate = {
        Type = "AWS::IoT::Certificate"
        Properties = {
          CertificateId = {
            Ref = "AWS::IoT::Certificate::Id"
          }
          Status = "Active"
        }
      }
      policy = {
        Type = "AWS::IoT::Policy"
        Properties = {
          PolicyName = {
            "Fn::Sub" = "$${DeviceType}Policy"
          }
        }
      }
      thingGroup = {
        Type = "AWS::IoT::ThingGroup"
        Properties = {
          ThingGroupName = {
            Ref = "ThingGroupName"
          }
        }
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name = local.template_name
  })
}

# ============================================================================
# Claim Certificate for Device Manufacturing
# ============================================================================

# Create claim certificate
resource "aws_iot_certificate" "claim_certificate" {
  active = true
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-claim-certificate-${local.resource_suffix}"
    Type = "ClaimCertificate"
  })
}

# Attach policy to claim certificate
resource "aws_iot_policy_attachment" "claim_certificate_policy_attachment" {
  policy = aws_iot_policy.claim_certificate_policy.name
  target = aws_iot_certificate.claim_certificate.arn
}

# ============================================================================
# CloudWatch Monitoring (Optional)
# ============================================================================

# CloudWatch log group for provisioning monitoring
resource "aws_cloudwatch_log_group" "provisioning_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  name              = "/aws/iot/provisioning"
  retention_in_days = 14
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-provisioning-logs-${local.resource_suffix}"
  })
}

# SNS topic for alerts (if email endpoint provided)
resource "aws_sns_topic" "provisioning_alerts" {
  count = var.enable_monitoring && var.sns_endpoint != "" ? 1 : 0
  
  name = "${var.resource_prefix}-provisioning-alerts-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-provisioning-alerts-${local.resource_suffix}"
  })
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "provisioning_alerts_email" {
  count = var.enable_monitoring && var.sns_endpoint != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.provisioning_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_endpoint
}

# CloudWatch alarm for failed provisioning attempts
resource "aws_cloudwatch_metric_alarm" "provisioning_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${var.resource_prefix}-provisioning-failures-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_threshold
  alarm_description   = "Monitor failed device provisioning attempts"
  
  dimensions = {
    FunctionName = aws_lambda_function.provisioning_hook.function_name
  }
  
  alarm_actions = var.sns_endpoint != "" ? [aws_sns_topic.provisioning_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-provisioning-failures-${local.resource_suffix}"
  })
}

# ============================================================================
# IoT Topic Rule for Audit Logging (Optional)
# ============================================================================

# IAM role for IoT topic rule
resource "aws_iam_role" "iot_topic_rule_role" {
  count = var.enable_audit_logging ? 1 : 0
  
  name = "${var.resource_prefix}-iot-topic-rule-role-${local.resource_suffix}"
  
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
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-iot-topic-rule-role-${local.resource_suffix}"
  })
}

# IAM policy for IoT topic rule
resource "aws_iam_role_policy" "iot_topic_rule_policy" {
  count = var.enable_audit_logging ? 1 : 0
  
  name = "${var.resource_prefix}-iot-topic-rule-policy-${local.resource_suffix}"
  role = aws_iam_role.iot_topic_rule_role[0].id
  
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
        Resource = var.enable_monitoring ? aws_cloudwatch_log_group.provisioning_logs[0].arn : "*"
      }
    ]
  })
}

# IoT topic rule for audit logging
resource "aws_iot_topic_rule" "provisioning_audit_rule" {
  count = var.enable_audit_logging ? 1 : 0
  
  name        = "${replace(var.resource_prefix, "-", "_")}_provisioning_audit_rule_${local.resource_suffix}"
  description = "Log all provisioning events for audit"
  enabled     = true
  sql         = "SELECT * FROM \"$$aws/events/provisioning/template/+/+\""
  sql_version = "2016-03-23"
  
  cloudwatch_logs {
    log_group_name = var.enable_monitoring ? aws_cloudwatch_log_group.provisioning_logs[0].name : "/aws/iot/provisioning"
    role_arn       = aws_iam_role.iot_topic_rule_role[0].arn
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-provisioning-audit-rule-${local.resource_suffix}"
  })
}