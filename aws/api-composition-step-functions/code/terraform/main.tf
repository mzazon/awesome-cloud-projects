# main.tf - Main infrastructure for API Composition with Step Functions and API Gateway

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Resource names with unique suffix
  orders_table_name      = "${local.name_prefix}-orders-${local.suffix}"
  audit_table_name       = "${local.name_prefix}-audit-${local.suffix}"
  user_service_name      = "${local.name_prefix}-user-service-${local.suffix}"
  inventory_service_name = "${local.name_prefix}-inventory-service-${local.suffix}"
  state_machine_name     = "${local.name_prefix}-order-workflow-${local.suffix}"
  api_gateway_name       = "${local.name_prefix}-composition-api-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Name        = "${local.name_prefix}-${local.suffix}"
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "api-composition-step-functions-api-gateway"
  })
}

# ========================================
# DynamoDB Tables
# ========================================

# Orders table for storing order data
resource "aws_dynamodb_table" "orders" {
  name           = local.orders_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Order storage"
  })
}

# Audit table for tracking order processing events
resource "aws_dynamodb_table" "audit" {
  name           = local.audit_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "auditId"

  attribute {
    name = "auditId"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Audit logging"
  })
}

# ========================================
# IAM Roles and Policies
# ========================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role-${local.suffix}"

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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Step Functions execution role
resource "aws_iam_role" "step_functions_role" {
  name = "${local.name_prefix}-step-functions-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Step Functions policy for Lambda and DynamoDB access
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.name_prefix}-step-functions-policy-${local.suffix}"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.user_service.arn,
          aws_lambda_function.inventory_service.arn
        ]
      },
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
          aws_dynamodb_table.orders.arn,
          aws_dynamodb_table.audit.arn
        ]
      },
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

# API Gateway execution role for Step Functions
resource "aws_iam_role" "api_gateway_role" {
  name = "${local.name_prefix}-api-gateway-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# API Gateway policy for Step Functions and DynamoDB access
resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${local.name_prefix}-api-gateway-policy-${local.suffix}"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = aws_sfn_state_machine.order_workflow.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.orders.arn
      },
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

# ========================================
# Lambda Functions
# ========================================

# Create deployment packages for Lambda functions
data "archive_file" "user_service_zip" {
  type        = "zip"
  output_path = "${path.module}/user_service.zip"
  
  source {
    content = <<EOF
import json
import random

def lambda_handler(event, context):
    """
    Mock user validation service
    Validates user ID and returns user information
    """
    user_id = event.get('userId', '')
    
    # Mock user validation
    if not user_id or len(user_id) < 3:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'valid': False,
                'error': 'Invalid user ID'
            })
        }
    
    # Simulate user data retrieval
    user_data = {
        'valid': True,
        'userId': user_id,
        'name': f'User {user_id}',
        'email': f'{user_id}@example.com',
        'creditLimit': random.randint(1000, 5000)
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
EOF
    filename = "user_service.py"
  }
}

data "archive_file" "inventory_service_zip" {
  type        = "zip"
  output_path = "${path.module}/inventory_service.zip"
  
  source {
    content = <<EOF
import json
import random

def lambda_handler(event, context):
    """
    Mock inventory service
    Checks product availability and returns inventory status
    """
    items = event.get('items', [])
    
    inventory_status = []
    for item in items:
        available = random.randint(0, 100)
        requested = item.get('quantity', 0)
        
        inventory_status.append({
            'productId': item.get('productId'),
            'requested': requested,
            'available': available,
            'sufficient': available >= requested,
            'price': random.randint(10, 500)
        })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'inventoryStatus': inventory_status,
            'allItemsAvailable': all(item['sufficient'] for item in inventory_status)
        })
    }
EOF
    filename = "inventory_service.py"
  }
}

# User validation service Lambda function
resource "aws_lambda_function" "user_service" {
  filename         = data.archive_file.user_service_zip.output_path
  function_name    = local.user_service_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "user_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.user_service_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "User validation service"
  })
}

# Inventory service Lambda function
resource "aws_lambda_function" "inventory_service" {
  filename         = data.archive_file.inventory_service_zip.output_path
  function_name    = local.inventory_service_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "inventory_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.inventory_service_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT_NAME = var.project_name
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Inventory management service"
  })
}

# ========================================
# CloudWatch Log Groups
# ========================================

# Log group for Step Functions (if logging enabled)
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  count             = var.enable_step_functions_logging ? 1 : 0
  name              = "/aws/stepfunctions/${local.state_machine_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# Log group for API Gateway (if logging enabled)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${local.api_gateway_name}"
  retention_in_days = 14
  
  tags = local.common_tags
}

# ========================================
# Step Functions State Machine
# ========================================

# Step Functions state machine for order processing workflow
resource "aws_sfn_state_machine" "order_workflow" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.step_functions_role.arn

  # State machine definition with comprehensive error handling
  definition = jsonencode({
    Comment = "Order Processing Workflow with API Composition"
    StartAt = "ValidateOrder"
    States = {
      ValidateOrder = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.user_service.function_name
          Payload = {
            "userId.$" = "$.userId"
          }
        }
        ResultPath = "$.userValidation"
        Next       = "CheckUserValid"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals  = ["States.ALL"]
            Next         = "ValidationFailed"
            ResultPath   = "$.error"
          }
        ]
      }
      CheckUserValid = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.userValidation.Payload.body"
            StringMatches = "*\"valid\":true*"
            Next          = "CheckInventory"
          }
        ]
        Default = "ValidationFailed"
      }
      CheckInventory = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.inventory_service.function_name
          Payload = {
            "items.$" = "$.items"
          }
        }
        ResultPath = "$.inventoryCheck"
        Next       = "ProcessInventoryResult"
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals  = ["States.ALL"]
            Next         = "InventoryCheckFailed"
            ResultPath   = "$.error"
          }
        ]
      }
      ProcessInventoryResult = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.inventoryCheck.Payload.body"
            StringMatches = "*\"allItemsAvailable\":true*"
            Next          = "CalculateOrderTotal"
          }
        ]
        Default = "InsufficientInventory"
      }
      CalculateOrderTotal = {
        Type = "Pass"
        Parameters = {
          "orderId.$"     = "$.orderId"
          "userId.$"      = "$.userId"
          "items.$"       = "$.items"
          "userInfo.$"    = "$.userValidation.Payload.body"
          "inventoryInfo.$" = "$.inventoryCheck.Payload.body"
          orderTotal      = 250.00
          status          = "processing"
        }
        Next = "ParallelProcessing"
      }
      ParallelProcessing = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "SaveOrder"
            States = {
              SaveOrder = {
                Type     = "Task"
                Resource = "arn:aws:states:::dynamodb:putItem"
                Parameters = {
                  TableName = aws_dynamodb_table.orders.name
                  Item = {
                    orderId = {
                      "S.$" = "$.orderId"
                    }
                    userId = {
                      "S.$" = "$.userId"
                    }
                    status = {
                      S = "processing"
                    }
                    orderTotal = {
                      N = "250.00"
                    }
                    timestamp = {
                      "S.$" = "$$.State.EnteredTime"
                    }
                  }
                }
                End = true
              }
            }
          },
          {
            StartAt = "LogAudit"
            States = {
              LogAudit = {
                Type     = "Task"
                Resource = "arn:aws:states:::dynamodb:putItem"
                Parameters = {
                  TableName = aws_dynamodb_table.audit.name
                  Item = {
                    auditId = {
                      "S.$" = "$$.Execution.Name"
                    }
                    orderId = {
                      "S.$" = "$.orderId"
                    }
                    action = {
                      S = "order_created"
                    }
                    timestamp = {
                      "S.$" = "$$.State.EnteredTime"
                    }
                  }
                }
                End = true
              }
            }
          }
        ]
        Next = "OrderProcessed"
        Catch = [
          {
            ErrorEquals  = ["States.ALL"]
            Next         = "CompensateOrder"
            ResultPath   = "$.error"
          }
        ]
      }
      CompensateOrder = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.audit.name
          Item = {
            auditId = {
              "S.$" = "$$.Execution.Name"
            }
            orderId = {
              "S.$" = "$.orderId"
            }
            action = {
              S = "order_failed"
            }
            error = {
              "S.$" = "$.error.Error"
            }
            timestamp = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        Next = "OrderFailed"
      }
      OrderProcessed = {
        Type = "Pass"
        Parameters = {
          "orderId.$" = "$.orderId"
          status      = "completed"
          message     = "Order processed successfully"
          orderTotal  = 250.00
        }
        End = true
      }
      ValidationFailed = {
        Type = "Pass"
        Parameters = {
          error       = "User validation failed"
          "orderId.$" = "$.orderId"
        }
        End = true
      }
      InventoryCheckFailed = {
        Type = "Pass"
        Parameters = {
          error       = "Inventory check failed"
          "orderId.$" = "$.orderId"
        }
        End = true
      }
      InsufficientInventory = {
        Type = "Pass"
        Parameters = {
          error       = "Insufficient inventory"
          "orderId.$" = "$.orderId"
        }
        End = true
      }
      OrderFailed = {
        Type = "Pass"
        Parameters = {
          "orderId.$" = "$.orderId"
          status      = "failed"
          message     = "Order processing failed"
        }
        End = true
      }
    }
  })

  # Configure logging if enabled
  dynamic "logging_configuration" {
    for_each = var.enable_step_functions_logging ? [1] : []
    content {
      level                  = var.step_functions_log_level
      include_execution_data = true
      log_destination        = "${aws_cloudwatch_log_group.step_functions_logs[0].arn}:*"
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Order processing workflow orchestration"
  })
}

# ========================================
# API Gateway
# ========================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "composition_api" {
  name        = local.api_gateway_name
  description = "API Composition with Step Functions and DynamoDB"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  stage_name  = var.api_gateway_stage_name

  # Ensure deployment happens after all methods are created
  depends_on = [
    aws_api_gateway_method.orders_post,
    aws_api_gateway_method.status_get,
    aws_api_gateway_integration.orders_post_integration,
    aws_api_gateway_integration.status_get_integration
  ]

  # Force new deployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_resource.order_id.id,
      aws_api_gateway_resource.status.id,
      aws_api_gateway_method.orders_post.id,
      aws_api_gateway_method.status_get.id,
      aws_api_gateway_integration.orders_post_integration.id,
      aws_api_gateway_integration.status_get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# CloudWatch log group for API Gateway stage (if logging enabled)
resource "aws_api_gateway_account" "api_gateway_account" {
  count               = var.enable_api_gateway_logging ? 1 : 0
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role[0].arn
}

# IAM role for API Gateway CloudWatch logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  count = var.enable_api_gateway_logging ? 1 : 0
  name  = "${local.name_prefix}-api-gateway-cloudwatch-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  count      = var.enable_api_gateway_logging ? 1 : 0
  role       = aws_iam_role.api_gateway_cloudwatch_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# API Gateway stage with logging configuration
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.composition_api.id
  stage_name    = var.api_gateway_stage_name

  # Enable logging if configured
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway_logs[0].arn
      format = jsonencode({
        requestId      = "$context.requestId"
        ip             = "$context.identity.sourceIp"
        caller         = "$context.identity.caller"
        user           = "$context.identity.user"
        requestTime    = "$context.requestTime"
        httpMethod     = "$context.httpMethod"
        resourcePath   = "$context.resourcePath"
        status         = "$context.status"
        protocol       = "$context.protocol"
        responseLength = "$context.responseLength"
      })
    }
  }

  tags = local.common_tags
}

# ========================================
# API Gateway Resources and Methods
# ========================================

# /orders resource
resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  parent_id   = aws_api_gateway_rest_api.composition_api.root_resource_id
  path_part   = "orders"
}

# /orders/{orderId} resource
resource "aws_api_gateway_resource" "order_id" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{orderId}"
}

# /orders/{orderId}/status resource
resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  parent_id   = aws_api_gateway_resource.order_id.id
  path_part   = "status"
}

# POST /orders method
resource "aws_api_gateway_method" "orders_post" {
  rest_api_id   = aws_api_gateway_rest_api.composition_api.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Type" = false
  }
}

# GET /orders/{orderId}/status method
resource "aws_api_gateway_method" "status_get" {
  rest_api_id   = aws_api_gateway_rest_api.composition_api.id
  resource_id   = aws_api_gateway_resource.status.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.orderId" = true
  }
}

# ========================================
# API Gateway Integrations
# ========================================

# POST /orders integration with Step Functions
resource "aws_api_gateway_integration" "orders_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method

  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials             = aws_iam_role.api_gateway_role.arn

  request_templates = {
    "application/json" = jsonencode({
      input           = "$util.escapeJavaScript($input.json('$'))"
      stateMachineArn = aws_sfn_state_machine.order_workflow.arn
    })
  }
}

# GET /orders/{orderId}/status integration with DynamoDB
resource "aws_api_gateway_integration" "status_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.status_get.http_method

  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:dynamodb:action/GetItem"
  credentials             = aws_iam_role.api_gateway_role.arn

  request_templates = {
    "application/json" = jsonencode({
      TableName = aws_dynamodb_table.orders.name
      Key = {
        orderId = {
          S = "$input.params('orderId')"
        }
      }
    })
  }
}

# ========================================
# API Gateway Method Responses
# ========================================

# POST /orders method response
resource "aws_api_gateway_method_response" "orders_post_200" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# GET status method response
resource "aws_api_gateway_method_response" "status_get_200" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.status_get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# ========================================
# API Gateway Integration Responses
# ========================================

# POST /orders integration response
resource "aws_api_gateway_integration_response" "orders_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.orders.id
  http_method = aws_api_gateway_method.orders_post.http_method
  status_code = aws_api_gateway_method_response.orders_post_200.status_code

  response_templates = {
    "application/json" = jsonencode({
      executionArn = "$input.json('$.executionArn')"
      message      = "Order processing started"
    })
  }
}

# GET status integration response
resource "aws_api_gateway_integration_response" "status_get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.composition_api.id
  resource_id = aws_api_gateway_resource.status.id
  http_method = aws_api_gateway_method.status_get.http_method
  status_code = aws_api_gateway_method_response.status_get_200.status_code

  response_templates = {
    "application/json" = jsonencode({
      orderId    = "$input.json('$.Item.orderId.S')"
      status     = "$input.json('$.Item.status.S')"
      orderTotal = "$input.json('$.Item.orderTotal.N')"
      timestamp  = "$input.json('$.Item.timestamp.S')"
    })
  }
}