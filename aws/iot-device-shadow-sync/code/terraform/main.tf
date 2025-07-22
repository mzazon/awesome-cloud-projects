# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Resource names with unique suffix
  thing_name                = "${var.thing_name_prefix}-${local.suffix}"
  conflict_resolver_lambda  = "shadow-conflict-resolver-${local.suffix}"
  sync_manager_lambda      = "shadow-sync-manager-${local.suffix}"
  shadow_history_table     = "shadow-sync-history-${local.suffix}"
  device_config_table      = "device-configuration-${local.suffix}"
  sync_metrics_table       = "shadow-sync-metrics-${local.suffix}"
  event_bus_name           = "shadow-sync-events-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Environment = "demo"
    Solution    = "IoTShadowSync"
  })
}

# =============================================================================
# DynamoDB Tables for Shadow Management
# =============================================================================

# Shadow history table for audit trail and conflict detection
resource "aws_dynamodb_table" "shadow_history" {
  name           = local.shadow_history_table
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "thingName"
  range_key      = "timestamp"
  
  # Configure capacity if using provisioned billing
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  # Attributes
  attribute {
    name = "thingName"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "N"
  }
  
  attribute {
    name = "shadowName"
    type = "S"
  }
  
  # Global Secondary Index for shadow name queries
  global_secondary_index {
    name               = "ShadowNameIndex"
    hash_key           = "shadowName"
    range_key          = "timestamp"
    projection_type    = "ALL"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }
  
  # Enable DynamoDB Streams for real-time processing
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name        = local.shadow_history_table
    Description = "Shadow update history and audit trail"
  })
}

# Device configuration table for conflict resolution settings
resource "aws_dynamodb_table" "device_config" {
  name           = local.device_config_table
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "thingName"
  range_key      = "configType"
  
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "thingName"
    type = "S"
  }
  
  attribute {
    name = "configType"
    type = "S"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name        = local.device_config_table
    Description = "Device-specific configuration and conflict resolution settings"
  })
}

# Sync metrics table for monitoring and analytics
resource "aws_dynamodb_table" "sync_metrics" {
  name           = local.sync_metrics_table
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "thingName"
  range_key      = "metricTimestamp"
  
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "thingName"
    type = "S"
  }
  
  attribute {
    name = "metricTimestamp"
    type = "N"
  }
  
  # TTL for automatic data cleanup (30 days)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name        = local.sync_metrics_table
    Description = "Shadow synchronization metrics and monitoring data"
  })
}

# =============================================================================
# EventBridge Custom Bus for Shadow Events
# =============================================================================

resource "aws_cloudwatch_event_bus" "shadow_sync" {
  name = local.event_bus_name
  
  tags = merge(local.common_tags, {
    Name        = local.event_bus_name
    Description = "Custom event bus for shadow synchronization events"
  })
}

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

# Log group for shadow audit trail
resource "aws_cloudwatch_log_group" "shadow_audit" {
  name              = "/aws/iot/shadow-audit"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/iot/shadow-audit"
    Description = "Audit trail for all shadow update events"
  })
}

# Log group for conflict resolver Lambda
resource "aws_cloudwatch_log_group" "conflict_resolver" {
  name              = "/aws/lambda/${local.conflict_resolver_lambda}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.conflict_resolver_lambda}"
    Description = "Logs for shadow conflict resolution Lambda function"
  })
}

# Log group for sync manager Lambda
resource "aws_cloudwatch_log_group" "sync_manager" {
  name              = "/aws/lambda/${local.sync_manager_lambda}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.sync_manager_lambda}"
    Description = "Logs for shadow sync manager Lambda function"
  })
}

# =============================================================================
# IAM Role for Lambda Functions
# =============================================================================

# Trust policy for Lambda execution
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution" {
  name               = "${local.conflict_resolver_lambda}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  
  tags = merge(local.common_tags, {
    Name        = "${local.conflict_resolver_lambda}-execution-role"
    Description = "Execution role for shadow synchronization Lambda functions"
  })
}

# IAM policy for Lambda functions
data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
  
  # IoT Device Shadow permissions
  statement {
    effect = "Allow"
    actions = [
      "iot:GetThingShadow",
      "iot:UpdateThingShadow",
      "iot:DeleteThingShadow"
    ]
    resources = ["arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thing/*"]
  }
  
  # DynamoDB permissions
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.shadow_history.arn,
      "${aws_dynamodb_table.shadow_history.arn}/*",
      aws_dynamodb_table.device_config.arn,
      "${aws_dynamodb_table.device_config.arn}/*",
      aws_dynamodb_table.sync_metrics.arn,
      "${aws_dynamodb_table.sync_metrics.arn}/*"
    ]
  }
  
  # EventBridge permissions
  statement {
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [aws_cloudwatch_event_bus.shadow_sync.arn]
  }
  
  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

# Attach policy to role
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${local.conflict_resolver_lambda}-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# =============================================================================
# Lambda Function Code Archives
# =============================================================================

# Create conflict resolver Lambda function code
data "archive_file" "conflict_resolver" {
  type        = "zip"
  output_path = "${path.module}/conflict_resolver.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/conflict_resolver.py", {
      shadow_history_table = local.shadow_history_table
      device_config_table  = local.device_config_table
      sync_metrics_table   = local.sync_metrics_table
      event_bus_name       = local.event_bus_name
    })
    filename = "lambda_function.py"
  }
}

# Create sync manager Lambda function code
data "archive_file" "sync_manager" {
  type        = "zip"
  output_path = "${path.module}/sync_manager.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/sync_manager.py", {
      shadow_history_table = local.shadow_history_table
      device_config_table  = local.device_config_table
      sync_metrics_table   = local.sync_metrics_table
    })
    filename = "lambda_function.py"
  }
}

# =============================================================================
# Lambda Functions
# =============================================================================

# Conflict resolver Lambda function
resource "aws_lambda_function" "conflict_resolver" {
  filename         = data.archive_file.conflict_resolver.output_path
  function_name    = local.conflict_resolver_lambda
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.conflict_resolver_timeout
  memory_size     = var.conflict_resolver_memory
  source_code_hash = data.archive_file.conflict_resolver.output_base64sha256
  
  environment {
    variables = {
      SHADOW_HISTORY_TABLE = local.shadow_history_table
      DEVICE_CONFIG_TABLE  = local.device_config_table
      SYNC_METRICS_TABLE   = local.sync_metrics_table
      EVENT_BUS_NAME       = local.event_bus_name
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.conflict_resolver,
    aws_iam_role_policy.lambda_policy
  ]
  
  tags = merge(local.common_tags, {
    Name        = local.conflict_resolver_lambda
    Description = "Lambda function for shadow conflict detection and resolution"
  })
}

# Sync manager Lambda function
resource "aws_lambda_function" "sync_manager" {
  filename         = data.archive_file.sync_manager.output_path
  function_name    = local.sync_manager_lambda
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.sync_manager_timeout
  memory_size     = var.sync_manager_memory
  source_code_hash = data.archive_file.sync_manager.output_base64sha256
  
  environment {
    variables = {
      SHADOW_HISTORY_TABLE = local.shadow_history_table
      DEVICE_CONFIG_TABLE  = local.device_config_table
      SYNC_METRICS_TABLE   = local.sync_metrics_table
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.sync_manager,
    aws_iam_role_policy.lambda_policy
  ]
  
  tags = merge(local.common_tags, {
    Name        = local.sync_manager_lambda
    Description = "Lambda function for shadow synchronization management"
  })
}

# =============================================================================
# IoT Core Resources
# =============================================================================

# IoT Thing Type
resource "aws_iot_thing_type" "demo_device" {
  name = var.thing_type_name
  
  thing_type_properties {
    description = "Demo device type for shadow synchronization testing"
  }
  
  tags = merge(local.common_tags, {
    Name        = var.thing_type_name
    Description = "Thing type for shadow sync demo devices"
  })
}

# Demo IoT Thing
resource "aws_iot_thing" "demo_device" {
  name           = local.thing_name
  thing_type_name = aws_iot_thing_type.demo_device.name
  
  attributes = var.device_attributes
}

# Certificate for the demo device
resource "aws_iot_certificate" "demo_device" {
  active = true
  
  tags = merge(local.common_tags, {
    Name        = "${local.thing_name}-certificate"
    Description = "X.509 certificate for demo device authentication"
  })
}

# IoT Policy for demo device
data "aws_iam_policy_document" "iot_device_policy" {
  # Allow device to connect
  statement {
    effect = "Allow"
    actions = ["iot:Connect"]
    resources = ["arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/${local.thing_name}"]
  }
  
  # Allow shadow operations
  statement {
    effect = "Allow"
    actions = [
      "iot:Publish",
      "iot:Subscribe",
      "iot:Receive"
    ]
    resources = [
      "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/$aws/things/${local.thing_name}/shadow/*",
      "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/things/${local.thing_name}/shadow/*"
    ]
  }
  
  # Allow shadow get and update
  statement {
    effect = "Allow"
    actions = [
      "iot:GetThingShadow",
      "iot:UpdateThingShadow"
    ]
    resources = ["arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:thing/${local.thing_name}"]
  }
}

resource "aws_iot_policy" "demo_device" {
  name   = "DemoDeviceSyncPolicy"
  policy = data.aws_iam_policy_document.iot_device_policy.json
  
  tags = merge(local.common_tags, {
    Name        = "DemoDeviceSyncPolicy"
    Description = "IoT policy for demo device shadow operations"
  })
}

# Attach policy to certificate
resource "aws_iot_policy_attachment" "demo_device" {
  policy = aws_iot_policy.demo_device.name
  target = aws_iot_certificate.demo_device.arn
}

# Attach certificate to thing
resource "aws_iot_thing_principal_attachment" "demo_device" {
  thing     = aws_iot_thing.demo_device.name
  principal = aws_iot_certificate.demo_device.arn
}

# =============================================================================
# IoT Rules for Shadow Processing
# =============================================================================

# IoT rule for shadow delta processing
resource "aws_iot_topic_rule" "shadow_delta_processing" {
  name        = "ShadowDeltaProcessingRule"
  description = "Process shadow delta events for conflict resolution"
  enabled     = true
  sql         = "SELECT *, thingName as thingName, shadowName as shadowName FROM \"$aws/things/+/shadow/+/update/delta\""
  sql_version = "2016-03-23"
  
  lambda {
    function_arn = aws_lambda_function.conflict_resolver.arn
  }
  
  tags = merge(local.common_tags, {
    Name        = "ShadowDeltaProcessingRule"
    Description = "IoT rule for processing shadow delta events"
  })
}

# Grant IoT permission to invoke conflict resolver Lambda
resource "aws_lambda_permission" "iot_invoke_conflict_resolver" {
  statement_id  = "iot-shadow-delta-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.conflict_resolver.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.shadow_delta_processing.arn
}

# IoT rule for shadow audit logging
resource "aws_iot_topic_rule" "shadow_audit_logging" {
  name        = "ShadowAuditLoggingRule"
  description = "Log all shadow update events for audit trail"
  enabled     = true
  sql         = "SELECT * FROM \"$aws/things/+/shadow/+/update/+\""
  sql_version = "2016-03-23"
  
  cloudwatch_logs {
    log_group_name = aws_cloudwatch_log_group.shadow_audit.name
    role_arn      = aws_iam_role.lambda_execution.arn
  }
  
  tags = merge(local.common_tags, {
    Name        = "ShadowAuditLoggingRule"
    Description = "IoT rule for audit logging of shadow updates"
  })
}

# =============================================================================
# EventBridge Rules for Automated Monitoring
# =============================================================================

# EventBridge rule for conflict notifications
resource "aws_cloudwatch_event_rule" "shadow_conflict_notifications" {
  name           = "shadow-conflict-notifications"
  description    = "Process shadow conflict events"
  event_bus_name = aws_cloudwatch_event_bus.shadow_sync.name
  
  event_pattern = jsonencode({
    source       = ["iot.shadow.sync"]
    detail-type  = ["Conflict Resolved", "Manual Review Required"]
  })
  
  tags = merge(local.common_tags, {
    Name        = "shadow-conflict-notifications"
    Description = "EventBridge rule for shadow conflict notifications"
  })
}

# EventBridge rule for periodic health checks
resource "aws_cloudwatch_event_rule" "shadow_health_check" {
  name                = "shadow-health-check-schedule"
  description         = "Periodic shadow synchronization health checks"
  schedule_expression = var.health_check_schedule
  
  tags = merge(local.common_tags, {
    Name        = "shadow-health-check-schedule"
    Description = "Scheduled rule for shadow health monitoring"
  })
}

# EventBridge target for health checks
resource "aws_cloudwatch_event_target" "health_check_lambda" {
  rule      = aws_cloudwatch_event_rule.shadow_health_check.name
  target_id = "HealthCheckLambdaTarget"
  arn       = aws_lambda_function.sync_manager.arn
  
  input = jsonencode({
    operation  = "health_report"
    thingNames = [local.thing_name]
  })
}

# Grant EventBridge permission to invoke sync manager Lambda
resource "aws_lambda_permission" "eventbridge_invoke_sync_manager" {
  statement_id  = "eventbridge-health-check-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sync_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.shadow_health_check.arn
}

# =============================================================================
# DynamoDB Items for Device Configuration
# =============================================================================

# Device conflict resolution configuration
resource "aws_dynamodb_table_item" "device_conflict_config" {
  table_name = aws_dynamodb_table.device_config.name
  hash_key   = aws_dynamodb_table.device_config.hash_key
  range_key  = aws_dynamodb_table.device_config.range_key
  
  item = jsonencode({
    thingName = {
      S = local.thing_name
    }
    configType = {
      S = "conflict_resolution"
    }
    config = {
      M = {
        strategy = {
          S = var.default_conflict_strategy
        }
        field_priorities = {
          M = {
            firmware_version = { S = "high" }
            temperature     = { S = "medium" }
            configuration   = { S = "high" }
            telemetry      = { S = "low" }
          }
        }
        auto_resolve_threshold = {
          N = tostring(var.auto_resolve_threshold)
        }
        manual_review_severity = {
          S = "high"
        }
      }
    }
    lastUpdated = {
      S = timestamp()
    }
  })
}

# Device sync preferences configuration
resource "aws_dynamodb_table_item" "device_sync_config" {
  table_name = aws_dynamodb_table.device_config.name
  hash_key   = aws_dynamodb_table.device_config.hash_key
  range_key  = aws_dynamodb_table.device_config.range_key
  
  item = jsonencode({
    thingName = {
      S = local.thing_name
    }
    configType = {
      S = "sync_preferences"
    }
    config = {
      M = {
        offline_buffer_duration = {
          N = "3600"
        }
        max_conflict_retries = {
          N = "3"
        }
        sync_frequency_seconds = {
          N = "60"
        }
        compression_enabled = {
          BOOL = true
        }
        delta_only_sync = {
          BOOL = true
        }
      }
    }
    lastUpdated = {
      S = timestamp()
    }
  })
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "shadow_monitoring" {
  dashboard_name = "IoT-Shadow-Synchronization"
  
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
            ["IoT/ShadowSync", "ConflictDetected"],
            [".", "SyncCompleted"],
            [".", "OfflineSync"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Shadow Synchronization Metrics"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.shadow_audit.name}' | fields @timestamp, @message | filter @message like /shadow/ | sort @timestamp desc | limit 50"
          region = data.aws_region.current.name
          title  = "Shadow Update Audit Trail"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.conflict_resolver.name}' | fields @timestamp, @message | filter @message like /conflict/ | sort @timestamp desc | limit 30"
          region = data.aws_region.current.name
          title  = "Conflict Resolution Events"
        }
      }
    ]
  })
}