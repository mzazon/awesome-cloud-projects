# AWS AppSync Real-time Data Synchronization Infrastructure
# This Terraform configuration creates a complete real-time task management system
# using AWS AppSync, DynamoDB, and associated resources for collaborative applications

# Data source for current AWS region and account
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  # Common resource naming convention
  name_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "AppSync Tutorial"
    },
    var.additional_tags
  )
}

# CloudWatch Log Group for AppSync API logging
resource "aws_cloudwatch_log_group" "appsync_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/appsync/apis/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# DynamoDB table for task storage with streams enabled for real-time updates
resource "aws_dynamodb_table" "tasks" {
  name             = "${local.name_prefix}-tasks"
  billing_mode     = "PROVISIONED"
  read_capacity    = var.dynamodb_read_capacity
  write_capacity   = var.dynamodb_write_capacity
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  # Primary key attribute
  attribute {
    name = "id"
    type = "S"
  }
  
  # GSI attributes for querying by status
  attribute {
    name = "status"
    type = "S"
  }
  
  attribute {
    name = "createdAt"
    type = "S"
  }
  
  # Global Secondary Index for querying tasks by status
  global_secondary_index {
    name            = "status-createdAt-index"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
    read_capacity   = var.gsi_read_capacity
    write_capacity  = var.gsi_write_capacity
  }
  
  # Enable point-in-time recovery for production workloads
  point_in_time_recovery {
    enabled = var.environment == "prod" ? true : false
  }
  
  tags = local.common_tags
}

# IAM role for AppSync to access DynamoDB
resource "aws_iam_role" "appsync_dynamodb_role" {
  name = "${local.name_prefix}-appsync-role"
  
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
  
  tags = local.common_tags
}

# IAM policy for AppSync to access DynamoDB table and index
resource "aws_iam_role_policy" "appsync_dynamodb_policy" {
  name = "DynamoDBAccess"
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
          aws_dynamodb_table.tasks.arn,
          "${aws_dynamodb_table.tasks.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs policy for AppSync (if logging is enabled)
resource "aws_iam_role_policy" "appsync_logs_policy" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name = "CloudWatchLogsAccess"
  role = aws_iam_role.appsync_dynamodb_role.id
  
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
      }
    ]
  })
}

# GraphQL schema for the task management system
resource "aws_appsync_graphql_api" "tasks_api" {
  name                = local.name_prefix
  authentication_type = var.authentication_type
  
  # GraphQL schema definition with real-time subscriptions
  schema = file("${path.module}/schema.graphql")
  
  # CloudWatch logging configuration
  dynamic "log_config" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_logs_role_arn = aws_iam_role.appsync_dynamodb_role.arn
      field_log_level          = "ALL"
    }
  }
  
  # X-Ray tracing configuration
  xray_enabled = var.enable_xray_tracing
  
  tags = local.common_tags
}

# Create the GraphQL schema file locally
resource "local_file" "graphql_schema" {
  filename = "${path.module}/schema.graphql"
  content  = <<-EOT
type Task {
    id: ID!
    title: String!
    description: String
    status: TaskStatus!
    priority: Priority!
    assignedTo: String
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime!
    version: Int!
}

enum TaskStatus {
    TODO
    IN_PROGRESS
    COMPLETED
    ARCHIVED
}

enum Priority {
    LOW
    MEDIUM
    HIGH
    URGENT
}

input CreateTaskInput {
    title: String!
    description: String
    priority: Priority!
    assignedTo: String
}

input UpdateTaskInput {
    id: ID!
    title: String
    description: String
    status: TaskStatus
    priority: Priority
    assignedTo: String
    version: Int!
}

type Query {
    getTask(id: ID!): Task
    listTasks(status: TaskStatus, limit: Int, nextToken: String): TaskConnection
    listTasksByStatus(status: TaskStatus!, limit: Int, nextToken: String): TaskConnection
}

type Mutation {
    createTask(input: CreateTaskInput!): Task
    updateTask(input: UpdateTaskInput!): Task
    deleteTask(id: ID!, version: Int!): Task
}

type Subscription {
    onTaskCreated: Task
        @aws_subscribe(mutations: ["createTask"])
    onTaskUpdated: Task
        @aws_subscribe(mutations: ["updateTask"])
    onTaskDeleted: Task
        @aws_subscribe(mutations: ["deleteTask"])
}

type TaskConnection {
    items: [Task]
    nextToken: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}
EOT
}

# API Key for testing (if API_KEY authentication is used)
resource "aws_appsync_api_key" "tasks_api_key" {
  count = var.authentication_type == "API_KEY" ? 1 : 0
  
  api_id      = aws_appsync_graphql_api.tasks_api.id
  description = "API key for real-time tasks API testing"
  expires     = timeadd(timestamp(), "${var.api_key_expires_in_days * 24}h")
}

# DynamoDB data source for AppSync
resource "aws_appsync_datasource" "tasks_datasource" {
  api_id           = aws_appsync_graphql_api.tasks_api.id
  name             = "TasksDataSource"
  service_role_arn = aws_iam_role.appsync_dynamodb_role.arn
  type             = "AMAZON_DYNAMODB"
  
  dynamodb_config {
    table_name = aws_dynamodb_table.tasks.name
    region     = data.aws_region.current.name
  }
}

# Query resolver for getTask
resource "aws_appsync_resolver" "get_task" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "getTask"
  type        = "Query"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
{
    "version": "2018-05-29",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOT
}

# Query resolver for listTasks
resource "aws_appsync_resolver" "list_tasks" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "listTasks"
  type        = "Query"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
{
    "version": "2018-05-29",
    "operation": "Scan",
    "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
    "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
}
EOT
}

# Query resolver for listTasksByStatus using GSI
resource "aws_appsync_resolver" "list_tasks_by_status" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "listTasksByStatus"
  type        = "Query"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
{
    "version": "2018-05-29",
    "operation": "Query",
    "index": "status-createdAt-index",
    "query": {
        "expression": "#status = :status",
        "expressionNames": {
            "#status": "status"
        },
        "expressionValues": {
            ":status": $util.dynamodb.toDynamoDBJson($ctx.args.status)
        }
    },
    "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
    "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end,
    "scanIndexForward": false
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
}
EOT
}

# Mutation resolver for createTask
resource "aws_appsync_resolver" "create_task" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "createTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
#set($id = $util.autoId())
#set($createdAt = $util.time.nowISO8601())
{
    "version": "2018-05-29",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($id)
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
        "status": $util.dynamodb.toDynamoDBJson("TODO"),
        "priority": $util.dynamodb.toDynamoDBJson($ctx.args.input.priority),
        "assignedTo": $util.dynamodb.toDynamoDBJson($ctx.args.input.assignedTo),
        "createdAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "updatedAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "version": $util.dynamodb.toDynamoDBJson(1)
    }
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOT
}

# Mutation resolver for updateTask with optimistic locking
resource "aws_appsync_resolver" "update_task" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "updateTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
#set($updatedAt = $util.time.nowISO8601())
#set($updateExpression = "SET #updatedAt = :updatedAt, #version = #version + :incr")
#set($expressionNames = {
    "#updatedAt": "updatedAt",
    "#version": "version"
})
#set($expressionValues = {
    ":updatedAt": $util.dynamodb.toDynamoDBJson($updatedAt),
    ":incr": $util.dynamodb.toDynamoDBJson(1),
    ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
})

## Add optional fields to update expression
#if($ctx.args.input.title)
    #set($updateExpression = "$updateExpression, title = :title")
    $util.qr($expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
#end
#if($ctx.args.input.description)
    #set($updateExpression = "$updateExpression, description = :description")
    $util.qr($expressionValues.put(":description", $util.dynamodb.toDynamoDBJson($ctx.args.input.description)))
#end
#if($ctx.args.input.status)
    #set($updateExpression = "$updateExpression, #status = :status")
    $util.qr($expressionNames.put("#status", "status"))
    $util.qr($expressionValues.put(":status", $util.dynamodb.toDynamoDBJson($ctx.args.input.status)))
#end
#if($ctx.args.input.priority)
    #set($updateExpression = "$updateExpression, priority = :priority")
    $util.qr($expressionValues.put(":priority", $util.dynamodb.toDynamoDBJson($ctx.args.input.priority)))
#end
#if($ctx.args.input.assignedTo)
    #set($updateExpression = "$updateExpression, assignedTo = :assignedTo")
    $util.qr($expressionValues.put(":assignedTo", $util.dynamodb.toDynamoDBJson($ctx.args.input.assignedTo)))
#end

{
    "version": "2018-05-29",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
    },
    "update": {
        "expression": "$updateExpression",
        "expressionNames": $util.toJson($expressionNames),
        "expressionValues": $util.toJson($expressionValues)
    },
    "condition": {
        "expression": "#version = :expectedVersion",
        "expressionNames": {
            "#version": "version"
        },
        "expressionValues": {
            ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
        }
    }
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOT
}

# Mutation resolver for deleteTask with version check
resource "aws_appsync_resolver" "delete_task" {
  api_id      = aws_appsync_graphql_api.tasks_api.id
  field       = "deleteTask"
  type        = "Mutation"
  data_source = aws_appsync_datasource.tasks_datasource.name
  
  request_template = <<-EOT
{
    "version": "2018-05-29",
    "operation": "DeleteItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    },
    "condition": {
        "expression": "#version = :expectedVersion",
        "expressionNames": {
            "#version": "version"
        },
        "expressionValues": {
            ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.version)
        }
    }
}
EOT
  
  response_template = <<-EOT
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOT
}