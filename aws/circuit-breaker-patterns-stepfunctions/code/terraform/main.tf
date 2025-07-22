# Circuit Breaker Pattern Implementation with AWS Step Functions
# This module implements a comprehensive circuit breaker pattern using
# Step Functions, Lambda, DynamoDB, and CloudWatch

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Resource names with unique suffixes
  circuit_breaker_table     = "${local.name_prefix}-state-${local.name_suffix}"
  downstream_function       = "${local.name_prefix}-downstream-${local.name_suffix}"
  fallback_function        = "${local.name_prefix}-fallback-${local.name_suffix}"
  health_check_function    = "${local.name_prefix}-health-check-${local.name_suffix}"
  state_machine_name       = "${local.name_prefix}-circuit-breaker-${local.name_suffix}"
  
  # Common tags to apply to all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "CircuitBreakerPattern"
  })
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# DynamoDB Table for Circuit Breaker State Management
#------------------------------------------------------------------------------

# DynamoDB table to store circuit breaker states for multiple services
resource "aws_dynamodb_table" "circuit_breaker_state" {
  name           = local.circuit_breaker_table
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "ServiceName"

  attribute {
    name = "ServiceName"
    type = "S"
  }

  # Enable point-in-time recovery for production workloads
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = local.circuit_breaker_table
    Type = "StateStore"
  })
}

#------------------------------------------------------------------------------
# IAM Roles and Policies
#------------------------------------------------------------------------------

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role-${local.name_suffix}"

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

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom policy for DynamoDB access from Lambda
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.name_prefix}-lambda-dynamodb-${local.name_suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.circuit_breaker_state.arn
      }
    ]
  })
}

# IAM role for Step Functions
resource "aws_iam_role" "step_functions_execution_role" {
  name = "${local.name_prefix}-stepfunctions-role-${local.name_suffix}"

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

# Custom policy for Step Functions to access Lambda and DynamoDB
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.name_prefix}-stepfunctions-policy-${local.name_suffix}"
  role = aws_iam_role.step_functions_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.downstream_service.arn,
          aws_lambda_function.fallback_service.arn,
          aws_lambda_function.health_check.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.circuit_breaker_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Functions
#------------------------------------------------------------------------------

# Archive for downstream service Lambda function
data "archive_file" "downstream_service_zip" {
  type        = "zip"
  output_path = "/tmp/downstream-service.zip"
  
  source {
    content = <<EOF
import json
import random
import time
import os

def lambda_handler(event, context):
    """
    Simulates a downstream service with configurable failure rate and latency.
    Used to test circuit breaker behavior under various conditions.
    """
    # Get configuration from environment variables
    failure_rate = float(os.environ.get('FAILURE_RATE', '0.3'))
    latency_ms = int(os.environ.get('LATENCY_MS', '100'))
    
    # Simulate service latency
    time.sleep(latency_ms / 1000)
    
    # Simulate failures based on configured rate
    if random.random() < failure_rate:
        raise Exception("Service temporarily unavailable")
    
    # Return successful response
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Service response successful',
            'timestamp': context.aws_request_id,
            'service': 'downstream-service'
        })
    }
EOF
    filename = "downstream-service.py"
  }
}

# Downstream service Lambda function
resource "aws_lambda_function" "downstream_service" {
  filename         = data.archive_file.downstream_service_zip.output_path
  function_name    = local.downstream_function
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "downstream-service.lambda_handler"
  source_code_hash = data.archive_file.downstream_service_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      FAILURE_RATE = tostring(var.downstream_service_failure_rate)
      LATENCY_MS   = tostring(var.downstream_service_latency_ms)
    }
  }

  tags = merge(local.common_tags, {
    Name = local.downstream_function
    Type = "DownstreamService"
  })
}

# Archive for fallback service Lambda function
data "archive_file" "fallback_service_zip" {
  type        = "zip"
  output_path = "/tmp/fallback-service.zip"
  
  source {
    content = <<EOF
import json
from datetime import datetime

def lambda_handler(event, context):
    """
    Provides fallback response when primary service is unavailable.
    Returns degraded but functional response to maintain user experience.
    """
    # Create fallback response with original request context
    fallback_data = {
        'message': 'Fallback service response',
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'fallback-service',
        'original_request': event.get('original_request', {}),
        'fallback_reason': 'Circuit breaker is open',
        'service_status': 'degraded'
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(fallback_data)
    }
EOF
    filename = "fallback-service.py"
  }
}

# Fallback service Lambda function
resource "aws_lambda_function" "fallback_service" {
  filename         = data.archive_file.fallback_service_zip.output_path
  function_name    = local.fallback_function
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "fallback-service.lambda_handler"
  source_code_hash = data.archive_file.fallback_service_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  tags = merge(local.common_tags, {
    Name = local.fallback_function
    Type = "FallbackService"
  })
}

# Archive for health check Lambda function
data "archive_file" "health_check_zip" {
  type        = "zip"
  output_path = "/tmp/health-check.zip"
  
  source {
    content = <<EOF
import json
import boto3
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Performs health checks on downstream services and manages circuit breaker recovery.
    Enables automatic transition from OPEN to CLOSED state when service recovers.
    """
    table_name = event['table_name']
    service_name = event['service_name']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get current circuit breaker state
        response = table.get_item(
            Key={'ServiceName': service_name}
        )
        
        if 'Item' not in response:
            # Initialize circuit breaker state if not exists
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat()
                }
            )
            state = 'CLOSED'
            failure_count = 0
        else:
            item = response['Item']
            state = item['State']
            failure_count = item.get('FailureCount', 0)
        
        # Simulate health check (in production, call actual service endpoint)
        health_check_success = random.random() > 0.3
        
        if health_check_success:
            # Reset circuit breaker to CLOSED on successful health check
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat()
                }
            )
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'healthy',
                    'circuit_state': 'CLOSED',
                    'previous_state': state
                })
            }
        else:
            return {
                'statusCode': 503,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'unhealthy',
                    'circuit_state': state,
                    'failure_count': failure_count
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'service_name': service_name
            })
        }
EOF
    filename = "health-check.py"
  }
}

# Health check Lambda function
resource "aws_lambda_function" "health_check" {
  filename         = data.archive_file.health_check_zip.output_path
  function_name    = local.health_check_function
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "health-check.lambda_handler"
  source_code_hash = data.archive_file.health_check_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  tags = merge(local.common_tags, {
    Name = local.health_check_function
    Type = "HealthCheck"
  })
}

#------------------------------------------------------------------------------
# Step Functions State Machine
#------------------------------------------------------------------------------

# Circuit breaker state machine definition
locals {
  circuit_breaker_definition = jsonencode({
    Comment = "Circuit Breaker Pattern Implementation with configurable failure threshold"
    StartAt = "CheckCircuitBreakerState"
    States = {
      CheckCircuitBreakerState = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Key = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
          }
        }
        ResultPath = "$.circuit_state"
        Next       = "EvaluateCircuitState"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "InitializeCircuitBreaker"
          }
        ]
      }
      
      InitializeCircuitBreaker = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Item = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
            State = {
              S = "CLOSED"
            }
            FailureCount = {
              N = "0"
            }
            LastFailureTime = {
              NULL = true
            }
            LastSuccessTime = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        Next = "CallDownstreamService"
      }
      
      EvaluateCircuitState = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.circuit_state.Item.State.S"
            StringEquals  = "OPEN"
            Next         = "CheckIfHalfOpenTime"
          },
          {
            Variable      = "$.circuit_state.Item.State.S"
            StringEquals  = "HALF_OPEN"
            Next         = "CallDownstreamService"
          },
          {
            Variable      = "$.circuit_state.Item.State.S"
            StringEquals  = "CLOSED"
            Next         = "CallDownstreamService"
          }
        ]
        Default = "CallDownstreamService"
      }
      
      CheckIfHalfOpenTime = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.health_check.function_name
          Payload = {
            table_name    = aws_dynamodb_table.circuit_breaker_state.name
            "service_name.$" = "$.service_name"
          }
        }
        ResultPath = "$.health_check_result"
        Next       = "EvaluateHealthCheck"
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }
      
      EvaluateHealthCheck = {
        Type = "Choice"
        Choices = [
          {
            Variable       = "$.health_check_result.Payload.statusCode"
            NumericEquals  = 200
            Next          = "CallDownstreamService"
          }
        ]
        Default = "CallFallbackService"
      }
      
      CallDownstreamService = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.downstream_service.function_name
          "Payload.$"  = "$.request_payload"
        }
        ResultPath = "$.service_result"
        Next       = "RecordSuccess"
        Catch = [
          {
            ErrorEquals  = ["States.ALL"]
            Next         = "RecordFailure"
            ResultPath   = "$.error"
          }
        ]
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 1
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
      }
      
      RecordSuccess = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Key = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
          }
          UpdateExpression = "SET #state = :closed_state, FailureCount = :zero, LastSuccessTime = :timestamp"
          ExpressionAttributeNames = {
            "#state" = "State"
          }
          ExpressionAttributeValues = {
            ":closed_state" = {
              S = "CLOSED"
            }
            ":zero" = {
              N = "0"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        Next = "ReturnSuccess"
      }
      
      RecordFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Key = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
          }
          UpdateExpression = "SET FailureCount = FailureCount + :inc, LastFailureTime = :timestamp"
          ExpressionAttributeValues = {
            ":inc" = {
              N = "1"
            }
            ":timestamp" = {
              "S.$" = "$$.State.EnteredTime"
            }
          }
        }
        ResultPath = "$.update_result"
        Next       = "CheckFailureThreshold"
      }
      
      CheckFailureThreshold = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Key = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
          }
        }
        ResultPath = "$.current_state"
        Next       = "EvaluateFailureCount"
      }
      
      EvaluateFailureCount = {
        Type = "Choice"
        Choices = [
          {
            Variable              = "$.current_state.Item.FailureCount.N"
            NumericGreaterThanEquals = var.circuit_breaker_failure_threshold
            Next                 = "TripCircuitBreaker"
          }
        ]
        Default = "CallFallbackService"
      }
      
      TripCircuitBreaker = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.circuit_breaker_state.name
          Key = {
            ServiceName = {
              "S.$" = "$.service_name"
            }
          }
          UpdateExpression = "SET #state = :open_state"
          ExpressionAttributeNames = {
            "#state" = "State"
          }
          ExpressionAttributeValues = {
            ":open_state" = {
              S = "OPEN"
            }
          }
        }
        Next = "CallFallbackService"
      }
      
      CallFallbackService = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.fallback_service.function_name
          Payload = {
            "original_request.$"      = "$.request_payload"
            "circuit_breaker_state.$" = "$.circuit_state.Item.State.S"
          }
        }
        ResultPath = "$.fallback_result"
        Next       = "ReturnFallback"
      }
      
      ReturnSuccess = {
        Type = "Pass"
        Parameters = {
          statusCode            = 200
          "body.$"              = "$.service_result.Payload.body"
          circuit_breaker_state = "CLOSED"
        }
        End = true
      }
      
      ReturnFallback = {
        Type = "Pass"
        Parameters = {
          statusCode            = 200
          "body.$"              = "$.fallback_result.Payload.body"
          circuit_breaker_state = "OPEN"
          fallback_used         = true
        }
        End = true
      }
    }
  })
}

# Step Functions state machine for circuit breaker
resource "aws_sfn_state_machine" "circuit_breaker" {
  name       = local.state_machine_name
  role_arn   = aws_iam_role.step_functions_execution_role.arn
  definition = local.circuit_breaker_definition
  type       = "STANDARD"

  # Enable logging for debugging and monitoring
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = merge(local.common_tags, {
    Name = local.state_machine_name
    Type = "CircuitBreakerStateMachine"
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/stepfunctions/${local.state_machine_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.state_machine_name}-logs"
    Type = "LogGroup"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Alarms (Optional)
#------------------------------------------------------------------------------

# SNS topic for circuit breaker alerts (if email provided)
resource "aws_sns_topic" "circuit_breaker_alerts" {
  count = var.enable_cloudwatch_alarms && var.sns_email_notification != "" ? 1 : 0
  name  = "${local.name_prefix}-circuit-breaker-alerts-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-circuit-breaker-alerts"
    Type = "SNSNotification"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_cloudwatch_alarms && var.sns_email_notification != "" ? 1 : 0
  topic_arn = aws_sns_topic.circuit_breaker_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_notification
}

# CloudWatch alarm for Step Functions execution failures
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-stepfunctions-failures-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Step Functions execution failures"
  alarm_actions       = var.sns_email_notification != "" ? [aws_sns_topic.circuit_breaker_alerts[0].arn] : []

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.circuit_breaker.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-stepfunctions-failures"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-errors-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors Lambda function errors across all circuit breaker functions"
  alarm_actions       = var.sns_email_notification != "" ? [aws_sns_topic.circuit_breaker_alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.downstream_service.function_name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-errors"
    Type = "CloudWatchAlarm"
  })
}