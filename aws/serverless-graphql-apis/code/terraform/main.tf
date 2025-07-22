# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Resource names
  table_name        = "${local.name_prefix}-tasks-${local.suffix}"
  api_name          = "${local.name_prefix}-api-${local.suffix}"
  lambda_name       = "${local.name_prefix}-processor-${local.suffix}"
  appsync_role_name = "${local.name_prefix}-appsync-role-${local.suffix}"
  lambda_role_name  = "${local.name_prefix}-lambda-role-${local.suffix}"
  scheduler_role_name = "${local.name_prefix}-scheduler-role-${local.suffix}"
}

# CloudWatch Log Group for AppSync
resource "aws_cloudwatch_log_group" "appsync" {
  name              = "/aws/appsync/apis/${local.api_name}"
  retention_in_days = 7
  
  tags = {
    Name = "${local.name_prefix}-appsync-logs"
  }
}

# DynamoDB table for task storage
resource "aws_dynamodb_table" "tasks" {
  name           = local.table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Conditional capacity settings for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "userId"
    type = "S"
  }

  # Global Secondary Index for querying by userId
  global_secondary_index {
    name            = "UserIdIndex"
    hash_key        = "userId"
    projection_type = "ALL"
    
    # Conditional capacity for GSI
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = {
    Name = local.table_name
  }
}

# IAM role for AppSync to access DynamoDB
resource "aws_iam_role" "appsync" {
  name = local.appsync_role_name

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

  tags = {
    Name = local.appsync_role_name
  }
}

# IAM policy for AppSync DynamoDB access
resource "aws_iam_role_policy" "appsync_dynamodb" {
  name = "DynamoDBAccess"
  role = aws_iam_role.appsync.id

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
          aws_dynamodb_table.tasks.arn,
          "${aws_dynamodb_table.tasks.arn}/index/*"
        ]
      }
    ]
  })
}

# GraphQL schema for the task management API
locals {
  graphql_schema = <<EOF
type Task {
  id: ID!
  userId: String!
  title: String!
  description: String
  dueDate: String!
  status: TaskStatus!
  reminderTime: String
  createdAt: String!
  updatedAt: String!
}

enum TaskStatus {
  PENDING
  IN_PROGRESS
  COMPLETED
  CANCELLED
}

input CreateTaskInput {
  title: String!
  description: String
  dueDate: String!
  reminderTime: String
}

input UpdateTaskInput {
  id: ID!
  title: String
  description: String
  status: TaskStatus
  dueDate: String
  reminderTime: String
}

type Query {
  getTask(id: ID!): Task
  listUserTasks(userId: String!): [Task]
}

type Mutation {
  createTask(input: CreateTaskInput!): Task
  updateTask(input: UpdateTaskInput!): Task
  deleteTask(id: ID!): Task
  sendReminder(taskId: ID!): Task
}

type Subscription {
  onTaskCreated(userId: String!): Task
    @aws_subscribe(mutations: ["createTask"])
  onTaskUpdated(userId: String!): Task
    @aws_subscribe(mutations: ["updateTask", "sendReminder"])
  onTaskDeleted(userId: String!): Task
    @aws_subscribe(mutations: ["deleteTask"])
}

schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}
EOF
}

# AppSync GraphQL API
resource "aws_appsync_graphql_api" "task_api" {
  name                = local.api_name
  authentication_type = var.graphql_authentication_type
  schema              = local.graphql_schema

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = var.graphql_log_level
  }

  tags = {
    Name = local.api_name
  }
}

# IAM role for AppSync CloudWatch logging
resource "aws_iam_role" "appsync_logs" {
  name = "${local.name_prefix}-appsync-logs-${local.suffix}"

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

  tags = {
    Name = "${local.name_prefix}-appsync-logs-${local.suffix}"
  }
}

# Attach CloudWatch logs policy to AppSync logging role
resource "aws_iam_role_policy_attachment" "appsync_logs" {
  role       = aws_iam_role.appsync_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AppSyncPushToCloudWatchLogs"
}

# DynamoDB data source for AppSync
resource "aws_appsync_datasource" "tasks_table" {
  api_id           = aws_appsync_graphql_api.task_api.id
  name             = "TasksDataSource"
  service_role_arn = aws_iam_role.appsync.arn
  type             = "AMAZON_DYNAMODB"

  dynamodb_config {
    table_name = aws_dynamodb_table.tasks.name
  }
}

# VTL mapping templates for resolvers
locals {
  # Create task request mapping template
  create_task_request_template = <<EOF
#set($id = $util.autoId())
{
  "version": "2017-02-28",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($id)
  },
  "attributeValues": {
    "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.userArn),
    "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
    "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
    "dueDate": $util.dynamodb.toDynamoDBJson($ctx.args.input.dueDate),
    "status": $util.dynamodb.toDynamoDBJson("PENDING"),
    "reminderTime": $util.dynamodb.toDynamoDBJson($ctx.args.input.reminderTime),
    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
  }
}
EOF

  # Get task request mapping template
  get_task_request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "GetItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
EOF

  # List user tasks request mapping template
  list_user_tasks_request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "Query",
  "index": "UserIdIndex",
  "query": {
    "expression": "userId = :userId",
    "expressionValues": {
      ":userId": $util.dynamodb.toDynamoDBJson($ctx.args.userId)
    }
  }
}
EOF

  # Update task request mapping template
  update_task_request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "UpdateItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
  },
  "update": {
    "expression": "SET #updatedAt = :updatedAt",
    "expressionNames": {
      "#updatedAt": "updatedAt"
    },
    "expressionValues": {
      ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
  }
}
#if($ctx.args.input.title)
  $util.qr($ctx.update.expression = "$ctx.update.expression, #title = :title")
  $util.qr($ctx.update.expressionNames.put("#title", "title"))
  $util.qr($ctx.update.expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
#end
#if($ctx.args.input.description)
  $util.qr($ctx.update.expression = "$ctx.update.expression, #description = :description")
  $util.qr($ctx.update.expressionNames.put("#description", "description"))
  $util.qr($ctx.update.expressionValues.put(":description", $util.dynamodb.toDynamoDBJson($ctx.args.input.description)))
#end
#if($ctx.args.input.status)
  $util.qr($ctx.update.expression = "$ctx.update.expression, #status = :status")
  $util.qr($ctx.update.expressionNames.put("#status", "status"))
  $util.qr($ctx.update.expressionValues.put(":status", $util.dynamodb.toDynamoDBJson($ctx.args.input.status)))
#end
#if($ctx.args.input.dueDate)
  $util.qr($ctx.update.expression = "$ctx.update.expression, #dueDate = :dueDate")
  $util.qr($ctx.update.expressionNames.put("#dueDate", "dueDate"))
  $util.qr($ctx.update.expressionValues.put(":dueDate", $util.dynamodb.toDynamoDBJson($ctx.args.input.dueDate)))
#end
#if($ctx.args.input.reminderTime)
  $util.qr($ctx.update.expression = "$ctx.update.expression, #reminderTime = :reminderTime")
  $util.qr($ctx.update.expressionNames.put("#reminderTime", "reminderTime"))
  $util.qr($ctx.update.expressionValues.put(":reminderTime", $util.dynamodb.toDynamoDBJson($ctx.args.input.reminderTime)))
#end
EOF

  # Delete task request mapping template
  delete_task_request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "DeleteItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
  }
}
EOF

  # Send reminder request mapping template
  send_reminder_request_template = <<EOF
{
  "version": "2017-02-28",
  "operation": "UpdateItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($ctx.args.taskId)
  },
  "update": {
    "expression": "SET #updatedAt = :updatedAt",
    "expressionNames": {
      "#updatedAt": "updatedAt"
    },
    "expressionValues": {
      ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
  }
}
EOF

  # Standard response mapping template
  response_template = <<EOF
$util.toJson($ctx.result)
EOF

  # List response mapping template
  list_response_template = <<EOF
$util.toJson($ctx.result.items)
EOF
}

# AppSync resolvers
resource "aws_appsync_resolver" "create_task" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "createTask"
  type              = "Mutation"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.create_task_request_template
  response_template = local.response_template
}

resource "aws_appsync_resolver" "get_task" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "getTask"
  type              = "Query"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.get_task_request_template
  response_template = local.response_template
}

resource "aws_appsync_resolver" "list_user_tasks" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "listUserTasks"
  type              = "Query"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.list_user_tasks_request_template
  response_template = local.list_response_template
}

resource "aws_appsync_resolver" "update_task" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "updateTask"
  type              = "Mutation"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.update_task_request_template
  response_template = local.response_template
}

resource "aws_appsync_resolver" "delete_task" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "deleteTask"
  type              = "Mutation"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.delete_task_request_template
  response_template = local.response_template
}

resource "aws_appsync_resolver" "send_reminder" {
  api_id            = aws_appsync_graphql_api.task_api.id
  field             = "sendReminder"
  type              = "Mutation"
  data_source       = aws_appsync_datasource.tasks_table.name
  request_template  = local.send_reminder_request_template
  response_template = local.response_template
}

# Lambda function for task processing
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime

appsync = boto3.client('appsync')

def lambda_handler(event, context):
    """Process scheduled task reminders from EventBridge"""
    print(f"Received event: {json.dumps(event)}")
    
    # Extract task ID from event
    task_id = event.get('taskId')
    if not task_id:
        raise ValueError("No taskId provided in event")
    
    # Prepare GraphQL mutation
    mutation = """
    mutation SendReminder($taskId: ID!) {
        sendReminder(taskId: $taskId) {
            id
            title
            status
        }
    }
    """
    
    # Execute mutation via AppSync
    try:
        response = appsync.graphql(
            apiId=os.environ['API_ID'],
            query=mutation,
            variables={'taskId': task_id}
        )
        
        print(f"Reminder sent successfully: {response}")
        return {
            'statusCode': 200,
            'body': json.dumps('Reminder sent successfully')
        }
    except Exception as e:
        print(f"Error sending reminder: {str(e)}")
        raise
EOF
    filename = "lambda_function.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda" {
  name = local.lambda_role_name

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

  tags = {
    Name = local.lambda_role_name
  }
}

# Attach basic execution role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda to invoke AppSync
resource "aws_iam_role_policy" "lambda_appsync" {
  name = "AppSyncAccess"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appsync:GraphQL"
        ]
        Resource = "${aws_appsync_graphql_api.task_api.arn}/*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "task_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      API_ID = aws_appsync_graphql_api.task_api.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = {
    Name = local.lambda_name
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-lambda-logs"
  }
}

# IAM role for EventBridge Scheduler
resource "aws_iam_role" "scheduler" {
  name = local.scheduler_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = local.scheduler_role_name
  }
}

# IAM policy for Scheduler to invoke AppSync
resource "aws_iam_role_policy" "scheduler_appsync" {
  name = "AppSyncAccess"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appsync:GraphQL"
        ]
        Resource = "${aws_appsync_graphql_api.task_api.arn}/*"
      }
    ]
  })
}

# Optional sample EventBridge schedule for testing
resource "aws_scheduler_schedule" "sample_reminder" {
  count = var.enable_sample_schedule ? 1 : 0
  
  name                = "TaskReminder-Sample-${local.suffix}"
  description         = "Sample schedule for testing task reminders"
  schedule_expression = var.sample_schedule_rate
  state               = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_appsync_graphql_api.task_api.arn
    role_arn = aws_iam_role.scheduler.arn

    appsync_parameters {
      graphql_operation = jsonencode({
        query = "mutation { sendReminder(taskId: \"sample-task-id\") { id } }"
      })
    }
  }

  tags = {
    Name = "TaskReminder-Sample-${local.suffix}"
  }
}