# main.tf
# Main Terraform configuration for AWS AppSync and DynamoDB Streams real-time data synchronization

# Data sources for account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix for uniqueness
  table_name          = var.dynamodb_table_name != "" ? var.dynamodb_table_name : "${local.name_prefix}-data-${random_string.suffix.result}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${local.name_prefix}-stream-processor-${random_string.suffix.result}"
  appsync_api_name    = var.appsync_api_name != "" ? var.appsync_api_name : "${local.name_prefix}-api-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# ============================================================================
# DynamoDB Table with Streams
# ============================================================================

resource "aws_dynamodb_table" "realtime_data" {
  name           = local.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  
  # Enable DynamoDB Streams for real-time change capture
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  attribute {
    name = "id"
    type = "S"
  }
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption for data at rest
  server_side_encryption {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = local.table_name
    Type = "DynamoDB"
  })
}

# ============================================================================
# Lambda Function for DynamoDB Stream Processing
# ============================================================================

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
appsync_client = boto3.client('appsync')

def lambda_handler(event, context):
    """
    Process DynamoDB stream events and trigger AppSync mutations
    for real-time data synchronization across connected clients.
    
    This function receives DynamoDB stream events and can be extended
    to publish real-time notifications through AppSync GraphQL subscriptions.
    """
    
    logger.info(f"Processing {len(event['Records'])} DynamoDB stream records")
    
    processed_records = 0
    
    try:
        for record in event['Records']:
            event_name = record['eventName']
            
            # Process INSERT, MODIFY, and REMOVE events
            if event_name in ['INSERT', 'MODIFY', 'REMOVE']:
                # Extract item data from stream record
                item_data = {}
                
                if 'NewImage' in record['dynamodb']:
                    item_data['newImage'] = record['dynamodb']['NewImage']
                
                if 'OldImage' in record['dynamodb']:
                    item_data['oldImage'] = record['dynamodb']['OldImage']
                
                # Get item ID for tracking
                item_id = 'unknown'
                if 'NewImage' in record['dynamodb'] and 'id' in record['dynamodb']['NewImage']:
                    item_id = record['dynamodb']['NewImage']['id']['S']
                elif 'OldImage' in record['dynamodb'] and 'id' in record['dynamodb']['OldImage']:
                    item_id = record['dynamodb']['OldImage']['id']['S']
                
                # Create change event for processing
                change_event = {
                    'eventType': event_name,
                    'itemId': item_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    'dynamodbRecord': record['dynamodb']
                }
                
                logger.info(f"Processing {event_name} event for item {item_id}")
                
                # Here you would typically trigger an AppSync mutation
                # to notify subscribed clients about the data change
                # For demonstration, we're logging the event
                
                # Example AppSync mutation trigger (commented out):
                # mutation_response = trigger_appsync_mutation(
                #     event_name, item_id, item_data
                # )
                
                processed_records += 1
                
            else:
                logger.warning(f"Unhandled event type: {event_name}")
    
    except Exception as e:
        logger.error(f"Error processing DynamoDB stream events: {str(e)}")
        raise
    
    logger.info(f"Successfully processed {processed_records} records")
    
    return {
        'statusCode': 200,
        'processedRecords': processed_records,
        'totalRecords': len(event['Records'])
    }

def trigger_appsync_mutation(event_type, item_id, item_data):
    """
    Trigger AppSync GraphQL mutation for real-time notifications.
    This function would be implemented to send mutations to AppSync
    that trigger subscriptions for connected clients.
    """
    # Implementation would depend on your specific AppSync schema
    # and mutation requirements
    pass
EOF
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.lambda_function_name}-execution-role"
  
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
    Name = "${local.lambda_function_name}-execution-role"
    Type = "IAM-Role"
  })
}

# IAM policy for Lambda function - Basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda function - DynamoDB streams
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_streams" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

# Custom IAM policy for AppSync access (for future use)
resource "aws_iam_role_policy" "lambda_appsync_access" {
  name = "${local.lambda_function_name}-appsync-access"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appsync:GraphQL",
          "appsync:GetGraphqlApi",
          "appsync:ListGraphqlApis"
        ]
        Resource = "${aws_appsync_graphql_api.main.arn}/*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      TABLE_NAME      = aws_dynamodb_table.realtime_data.name
      APPSYNC_API_URL = aws_appsync_graphql_api.main.uris["GRAPHQL"]
      AWS_REGION      = data.aws_region.current.name
    }
  }
  
  # Enable dead letter queue for error handling
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
    Type = "Lambda"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_dynamodb_streams,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_logs_retention_in_days
  
  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Type = "CloudWatch-LogGroup"
  })
}

# Dead Letter Queue for Lambda error handling
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.lambda_function_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  
  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-dlq"
    Type = "SQS"
  })
}

# Event Source Mapping for DynamoDB Streams
resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn                   = aws_dynamodb_table.realtime_data.stream_arn
  function_name                      = aws_lambda_function.stream_processor.arn
  starting_position                  = "LATEST"
  batch_size                         = var.stream_batch_size
  maximum_batching_window_in_seconds = var.stream_maximum_batching_window_in_seconds
  parallelization_factor             = 1
  
  # Error handling configuration
  maximum_retry_attempts = 3
  maximum_record_age_in_seconds = 86400 # 24 hours
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_dynamodb_streams
  ]
}

# ============================================================================
# AWS AppSync GraphQL API
# ============================================================================

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "main" {
  name                = local.appsync_api_name
  authentication_type = var.appsync_authentication_type
  
  # GraphQL schema for real-time data synchronization
  schema = <<EOF
type DataItem {
    id: ID!
    title: String!
    content: String!
    timestamp: String!
    version: Int!
}

type Query {
    getDataItem(id: ID!): DataItem
    listDataItems: [DataItem]
}

type Mutation {
    createDataItem(input: CreateDataItemInput!): DataItem
    updateDataItem(input: UpdateDataItemInput!): DataItem
    deleteDataItem(id: ID!): DataItem
}

type Subscription {
    onDataItemCreated: DataItem
        @aws_subscribe(mutations: ["createDataItem"])
    onDataItemUpdated: DataItem
        @aws_subscribe(mutations: ["updateDataItem"])
    onDataItemDeleted: DataItem
        @aws_subscribe(mutations: ["deleteDataItem"])
}

input CreateDataItemInput {
    title: String!
    content: String!
}

input UpdateDataItemInput {
    id: ID!
    title: String
    content: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}
EOF
  
  # Enable CloudWatch logging if specified
  dynamic "log_config" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_logs_role_arn = aws_iam_role.appsync_logs_role[0].arn
      field_log_level          = "ERROR"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.appsync_api_name
    Type = "AppSync"
  })
}

# AppSync API Key for authentication
resource "aws_appsync_api_key" "main" {
  count       = var.appsync_authentication_type == "API_KEY" ? 1 : 0
  api_id      = aws_appsync_graphql_api.main.id
  description = var.api_key_description
  expires     = timeadd(timestamp(), "${var.api_key_expires}s")
}

# CloudWatch Logs role for AppSync (conditional)
resource "aws_iam_role" "appsync_logs_role" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${local.appsync_api_name}-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.appsync_api_name}-logs-role"
    Type = "IAM-Role"
  })
}

# CloudWatch Logs policy for AppSync
resource "aws_iam_role_policy" "appsync_logs_policy" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "${local.appsync_api_name}-logs-policy"
  role  = aws_iam_role.appsync_logs_role[0].id
  
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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ============================================================================
# AppSync Data Source and Resolvers
# ============================================================================

# IAM role for AppSync DynamoDB data source
resource "aws_iam_role" "appsync_dynamodb_role" {
  name = "${local.appsync_api_name}-dynamodb-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.appsync_api_name}-dynamodb-role"
    Type = "IAM-Role"
  })
}

# IAM policy for AppSync DynamoDB access
resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name = "${local.appsync_api_name}-dynamodb-policy"
  role = aws_iam_role.appsync_dynamodb_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.realtime_data.arn,
          "${aws_dynamodb_table.realtime_data.arn}/*"
        ]
      }
    ]
  })
}

# AppSync DynamoDB data source
resource "aws_appsync_datasource" "dynamodb" {
  api_id           = aws_appsync_graphql_api.main.id
  name             = "DynamoDBDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.realtime_data.name
    region     = data.aws_region.current.name
  }
}

# Resolver for createDataItem mutation
resource "aws_appsync_resolver" "create_data_item" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "createDataItem"
  type        = "Mutation"
  data_source = aws_appsync_datasource.dynamodb.name
  
  # Request mapping template
  request_template = <<EOF
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "version": $util.dynamodb.toDynamoDBJson(1)
    }
}
EOF
  
  # Response mapping template
  response_template = "$util.toJson($ctx.result)"
}

# Resolver for updateDataItem mutation
resource "aws_appsync_resolver" "update_data_item" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "updateDataItem"
  type        = "Mutation"
  data_source = aws_appsync_datasource.dynamodb.name
  
  # Request mapping template
  request_template = <<EOF
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
    },
    "update": {
        "expression": "SET #title = :title, #content = :content, #timestamp = :timestamp, #version = #version + :one",
        "expressionNames": {
            "#title": "title",
            "#content": "content",
            "#timestamp": "timestamp",
            "#version": "version"
        },
        "expressionValues": {
            ":title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
            ":content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
            ":timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
            ":one": $util.dynamodb.toDynamoDBJson(1)
        }
    }
}
EOF
  
  # Response mapping template
  response_template = "$util.toJson($ctx.result)"
}

# Resolver for deleteDataItem mutation
resource "aws_appsync_resolver" "delete_data_item" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "deleteDataItem"
  type        = "Mutation"
  data_source = aws_appsync_datasource.dynamodb.name
  
  # Request mapping template
  request_template = <<EOF
{
    "version": "2017-02-28",
    "operation": "DeleteItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOF
  
  # Response mapping template
  response_template = "$util.toJson($ctx.result)"
}

# Resolver for getDataItem query
resource "aws_appsync_resolver" "get_data_item" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "getDataItem"
  type        = "Query"
  data_source = aws_appsync_datasource.dynamodb.name
  
  # Request mapping template
  request_template = <<EOF
{
    "version": "2017-02-28",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOF
  
  # Response mapping template
  response_template = "$util.toJson($ctx.result)"
}

# Resolver for listDataItems query
resource "aws_appsync_resolver" "list_data_items" {
  api_id      = aws_appsync_graphql_api.main.id
  field       = "listDataItems"
  type        = "Query"
  data_source = aws_appsync_datasource.dynamodb.name
  
  # Request mapping template
  request_template = <<EOF
{
    "version": "2017-02-28",
    "operation": "Scan"
}
EOF
  
  # Response mapping template
  response_template = "$util.toJson($ctx.result.items)"
}

# ============================================================================
# CloudWatch Monitoring and Alarms
# ============================================================================

# CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/appsync/apis/${aws_appsync_graphql_api.main.id}"
  retention_in_days = var.cloudwatch_logs_retention_in_days
  
  tags = merge(local.common_tags, {
    Name = "/aws/appsync/apis/${aws_appsync_graphql_api.main.id}"
    Type = "CloudWatch-LogGroup"
  })
}

# CloudWatch Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.lambda_function_name}-errors"
    Type = "CloudWatch-Alarm"
  })
}

# CloudWatch Alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttling" {
  alarm_name          = "${local.table_name}-throttling"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = []
  
  dimensions = {
    TableName = aws_dynamodb_table.realtime_data.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.table_name}-throttling"
    Type = "CloudWatch-Alarm"
  })
}