# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Blockchain network configuration
  network_name = "${var.network_name}-${local.name_suffix}"
  member_name  = "${var.member_name}-${local.name_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "blockchain-based-supply-chain-tracking-systems"
  }
}

# KMS Key for encryption
resource "aws_kms_key" "supply_chain" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for supply chain tracking system"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "supply_chain" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-supply-chain"
  target_key_id = aws_kms_key.supply_chain[0].key_id
}

# S3 Bucket for chaincode and data storage
resource "aws_s3_bucket" "supply_chain_data" {
  bucket = "${local.name_prefix}-data-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-bucket"
  })
}

resource "aws_s3_bucket_versioning" "supply_chain_data" {
  bucket = aws_s3_bucket.supply_chain_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "supply_chain_data" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.supply_chain_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.supply_chain[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "supply_chain_data" {
  bucket = aws_s3_bucket.supply_chain_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "supply_chain_data" {
  bucket = aws_s3_bucket.supply_chain_data.id

  rule {
    id     = "chaincode_lifecycle"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# DynamoDB Table for supply chain metadata
resource "aws_dynamodb_table" "supply_chain_metadata" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "ProductId"
  range_key      = "Timestamp"

  attribute {
    name = "ProductId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "N"
  }

  attribute {
    name = "Location"
    type = "S"
  }

  global_secondary_index {
    name               = "LocationIndex"
    hash_key           = "Location"
    range_key          = "Timestamp"
    write_capacity     = var.dynamodb_write_capacity
    read_capacity      = var.dynamodb_read_capacity
    projection_type    = "ALL"
  }

  server_side_encryption {
    enabled     = var.enable_encryption
    kms_key_arn = var.enable_encryption ? aws_kms_key.supply_chain[0].arn : null
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-metadata-table"
  })
}

# Amazon Managed Blockchain Network
resource "aws_managedblockchain_network" "supply_chain" {
  name        = local.network_name
  description = "Supply Chain Tracking Network"
  framework   = "HYPERLEDGER_FABRIC"

  framework_configuration {
    fabric_configuration {
      edition = var.network_edition
    }
  }

  voting_policy {
    approval_threshold_policy {
      threshold_percentage         = 50
      proposal_duration_in_hours   = 24
      threshold_comparator         = "GREATER_THAN"
    }
  }

  member_configuration {
    name        = local.member_name
    description = "Manufacturer member for supply chain network"

    member_fabric_configuration {
      admin_username = var.admin_username
      admin_password = var.admin_password
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-blockchain-network"
  })
}

# Blockchain Member (retrieved from network creation)
data "aws_managedblockchain_member" "manufacturer" {
  name       = local.member_name
  network_id = aws_managedblockchain_network.supply_chain.id
}

# Blockchain Node
resource "aws_managedblockchain_node" "manufacturer_node" {
  network_id = aws_managedblockchain_network.supply_chain.id
  member_id  = data.aws_managedblockchain_member.manufacturer.id

  node_configuration {
    instance_type     = var.node_instance_type
    availability_zone = "${var.aws_region}${var.node_availability_zone}"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-blockchain-node"
  })
}

# IoT Core Resources
resource "aws_iot_thing_type" "supply_chain_tracker" {
  name = var.iot_thing_type_name

  thing_type_properties {
    description = "IoT device type for supply chain tracking"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-thing-type"
  })
}

resource "aws_iot_thing" "supply_chain_tracker" {
  name           = "${local.name_prefix}-tracker-${local.name_suffix}"
  thing_type_name = aws_iot_thing_type.supply_chain_tracker.name

  attributes = {
    deviceType = "supplyChainTracker"
    version    = "1.0"
  }
}

resource "aws_iot_policy" "supply_chain_tracker" {
  name = var.iot_policy_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:Subscribe",
          "iot:Connect",
          "iot:Receive"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-iot-policy"
  })
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${local.name_prefix}-lambda-permissions"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.supply_chain_metadata.arn,
          "${aws_dynamodb_table.supply_chain_metadata.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_encryption ? [aws_kms_key.supply_chain[0].arn] : []
        Condition = var.enable_encryption ? {
          StringEquals = {
            "kms:ViaService" = "dynamodb.${var.aws_region}.amazonaws.com"
          }
        } : null
      }
    ]
  })
}

# Lambda Function Code Archive
data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.js.tpl", {
      table_name = aws_dynamodb_table.supply_chain_metadata.name
    })
    filename = "index.js"
  }
}

# Lambda Function for Processing Sensor Data
resource "aws_lambda_function" "process_supply_chain_data" {
  filename         = data.archive_file.lambda_function.output_path
  function_name    = "${local.name_prefix}-process-sensor-data"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_function.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.supply_chain_metadata.name
      AWS_REGION         = var.aws_region
    }
  }

  dynamic "kms_key_arn" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_arn = aws_kms_key.supply_chain[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-function"
  })
}

# Lambda Permission for IoT to invoke
resource "aws_lambda_permission" "iot_invoke" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_supply_chain_data.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.supply_chain_sensor_rule.arn
}

# IoT Topic Rule for Sensor Data
resource "aws_iot_topic_rule" "supply_chain_sensor_rule" {
  name        = "${replace(local.name_prefix, "-", "_")}_sensor_rule"
  description = "Rule for processing supply chain sensor data"
  enabled     = true
  sql         = "SELECT * FROM 'supply-chain/sensor-data'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.process_supply_chain_data.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-iot-rule"
  })
}

# SNS Topic for Notifications
resource "aws_sns_topic" "supply_chain_notifications" {
  name              = var.sns_topic_name
  kms_master_key_id = var.enable_encryption ? aws_kms_key.supply_chain[0].id : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-notifications"
  })
}

# SNS Topic Subscriptions for Email Notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = length(var.notification_emails)
  topic_arn = aws_sns_topic.supply_chain_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

# EventBridge Rule for Supply Chain Events
resource "aws_cloudwatch_event_rule" "supply_chain_tracking" {
  name        = var.eventbridge_rule_name
  description = "Rule for supply chain tracking events"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["supply-chain.sensor"]
    detail-type = ["Product Location Update"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eventbridge-rule"
  })
}

# EventBridge Target - SNS Topic
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.supply_chain_tracking.name
  target_id = "SupplyChainSNSTarget"
  arn       = aws_sns_topic.supply_chain_notifications.arn
}

# SNS Topic Policy for EventBridge
resource "aws_sns_topic_policy" "supply_chain_notifications" {
  arn = aws_sns_topic.supply_chain_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.supply_chain_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "supply_chain_tracking" {
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
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.process_supply_chain_data.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Supply Chain Processing Metrics"
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.supply_chain_metadata.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "ThrottledRequests", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "DynamoDB Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.supply_chain_tracking.name],
            [".", "SuccessfulInvocations", ".", "."],
            [".", "FailedInvocations", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "EventBridge Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.supply_chain_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.process_supply_chain_data.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-error-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = [aws_sns_topic.supply_chain_notifications.arn]

  dimensions = {
    TableName = aws_dynamodb_table.supply_chain_metadata.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dynamodb-throttle-alarm"
  })
}

# Lambda Function Template
resource "local_file" "lambda_function_template" {
  content = templatefile("${path.module}/lambda_function.js.tpl", {
    table_name = aws_dynamodb_table.supply_chain_metadata.name
  })
  
  filename = "${path.module}/lambda_function.js.tpl"
}

# Create the Lambda function template file
resource "local_file" "lambda_template" {
  content = <<EOF
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();

exports.handler = async (event) => {
    console.log('Processing sensor data:', JSON.stringify(event, null, 2));
    
    try {
        // Extract sensor data from IoT event
        const sensorData = {
            productId: event.productId || event.ProductId,
            location: event.location || event.Location,
            temperature: event.temperature || event.Temperature,
            humidity: event.humidity || event.Humidity,
            timestamp: event.timestamp || Date.now()
        };

        // Validate required fields
        if (!sensorData.productId) {
            throw new Error('ProductId is required');
        }

        // Store in DynamoDB
        const putParams = {
            TableName: '${table_name}',
            Item: {
                ProductId: sensorData.productId,
                Timestamp: sensorData.timestamp,
                Location: sensorData.location || 'Unknown',
                SensorData: {
                    temperature: sensorData.temperature,
                    humidity: sensorData.humidity
                },
                ProcessedAt: new Date().toISOString()
            }
        };

        await dynamodb.put(putParams).promise();
        console.log('Data stored in DynamoDB successfully');

        // Send event to EventBridge
        const eventParams = {
            Entries: [{
                Source: 'supply-chain.sensor',
                DetailType: 'Product Location Update',
                Detail: JSON.stringify(sensorData),
                Time: new Date()
            }]
        };

        await eventbridge.putEvents(eventParams).promise();
        console.log('Event sent to EventBridge successfully');

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Sensor data processed successfully',
                productId: sensorData.productId,
                timestamp: sensorData.timestamp
            })
        };

    } catch (error) {
        console.error('Error processing sensor data:', error);
        
        // Send error event to EventBridge
        try {
            await eventbridge.putEvents({
                Entries: [{
                    Source: 'supply-chain.sensor',
                    DetailType: 'Processing Error',
                    Detail: JSON.stringify({
                        error: error.message,
                        event: event
                    }),
                    Time: new Date()
                }]
            }).promise();
        } catch (eventError) {
            console.error('Failed to send error event:', eventError);
        }

        return {
            statusCode: 500,
            body: JSON.stringify({
                message: 'Error processing sensor data',
                error: error.message
            })
        };
    }
};
EOF
  
  filename = "${path.module}/lambda_function.js.tpl"
}