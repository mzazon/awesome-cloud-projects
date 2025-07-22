# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  common_tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
    Recipe      = "business-process-automation-step-functions"
  })
}

# ================================
# Lambda Function for Business Logic
# ================================

# Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/business_processor.py"
  content  = <<EOF
import json
import boto3
import time
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Business process automation Lambda function.
    
    This function processes business logic for workflows orchestrated by Step Functions.
    It simulates business rule validation, data processing, and decision making.
    """
    
    try:
        # Extract business process data from Step Functions input
        process_data = event.get('processData', {})
        process_type = process_data.get('type', 'unknown')
        process_id = process_data.get('processId', 'unknown')
        
        logger.info(f"Processing business request: {process_id}, type: {process_type}")
        
        # Simulate business logic processing time
        processing_time = process_data.get('processingTime', 2)
        time.sleep(min(processing_time, 5))  # Cap at 5 seconds for safety
        
        # Business rule validation
        if process_type == 'expense-approval':
            amount = process_data.get('amount', 0)
            if amount > 10000:
                approval_required = True
                risk_level = 'high'
            elif amount > 1000:
                approval_required = True
                risk_level = 'medium'
            else:
                approval_required = False
                risk_level = 'low'
        else:
            approval_required = True
            risk_level = 'medium'
        
        # Generate processing result
        result = {
            'processId': process_id,
            'processType': process_type,
            'status': 'processed',
            'timestamp': datetime.utcnow().isoformat(),
            'approvalRequired': approval_required,
            'riskLevel': risk_level,
            'processingDetails': {
                'processingTime': processing_time,
                'validationPassed': True,
                'businessRulesApplied': True
            },
            'result': f"Successfully processed {process_type} business process"
        }
        
        logger.info(f"Business process completed successfully: {process_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result),
            'processResult': result
        }
        
    except Exception as e:
        logger.error(f"Error processing business request: {str(e)}")
        raise Exception(f"Business processing failed: {str(e)}")
EOF
}

# Create ZIP archive for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/business_processor.zip"
  depends_on  = [local_file.lambda_source]
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"

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

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "business_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.resource_prefix}-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "business_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-processor"
  retention_in_days = 14
  tags              = local.common_tags
}

# ================================
# SQS Queue for Task Management
# ================================

# SQS queue for completed tasks and audit logging
resource "aws_sqs_queue" "task_queue" {
  name                       = "${local.resource_prefix}-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_seconds
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true

  tags = local.common_tags
}

# SQS queue policy to allow Step Functions to send messages
resource "aws_sqs_queue_policy" "task_queue_policy" {
  queue_url = aws_sqs_queue.task_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.task_queue.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ================================
# SNS Topic for Notifications
# ================================

# SNS topic for process notifications
resource "aws_sns_topic" "notifications" {
  name = "${local.resource_prefix}-notifications"
  
  # Enable server-side encryption
  kms_master_key_id = "alias/aws/sns"

  tags = local.common_tags
}

# SNS topic policy to allow Step Functions to publish
resource "aws_sns_topic_policy" "notifications_policy" {
  arn = aws_sns_topic.notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Optional email subscription for notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================
# Step Functions State Machine
# ================================

# IAM role for Step Functions execution
resource "aws_iam_role" "step_functions_role" {
  name = "${local.resource_prefix}-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Step Functions execution
resource "aws_iam_role_policy" "step_functions_policy" {
  name = "${local.resource_prefix}-stepfunctions-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.business_processor.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.task_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions_logs" {
  name              = "/aws/stepfunctions/${local.resource_prefix}-workflow"
  retention_in_days = 14
  tags              = local.common_tags
}

# Step Functions state machine definition
locals {
  state_machine_definition = jsonencode({
    Comment = "Business Process Automation Workflow"
    StartAt = "ValidateInput"
    States = {
      ValidateInput = {
        Type = "Pass"
        Parameters = {
          "processData.$"      = "$.processData"
          "validationResult"   = "Input validated successfully"
          "validationTimestamp" = "$$.State.EnteredTime"
        }
        Next = "ProcessBusinessLogic"
      }
      
      ProcessBusinessLogic = {
        Type     = "Task"
        Resource = aws_lambda_function.business_processor.arn
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ProcessingFailed"
            ResultPath  = "$.error"
          }
        ]
        Next = "CheckApprovalRequired"
      }
      
      CheckApprovalRequired = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.processResult.approvalRequired"
            BooleanEquals = true
            Next          = "HumanApprovalRequired"
          }
        ]
        Default = "SendCompletionNotification"
      }
      
      HumanApprovalRequired = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish.waitForTaskToken"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          Message = {
            "processId.$"         = "$.processResult.processId"
            "processType.$"       = "$.processResult.processType"
            "riskLevel.$"         = "$.processResult.riskLevel"
            "approvalRequired"    = "Please approve this business process"
            "approvalInstructions" = "Reply with APPROVE or REJECT to continue the workflow"
            "taskToken.$"         = "$$.Task.Token"
          }
          Subject = "Business Process Approval Required"
        }
        HeartbeatSeconds = var.heartbeat_timeout
        TimeoutSeconds   = var.human_approval_timeout
        Next             = "SendCompletionNotification"
        Catch = [
          {
            ErrorEquals = ["States.Timeout"]
            Next        = "ApprovalTimeoutNotification"
            ResultPath  = "$.error"
          }
        ]
      }
      
      ApprovalTimeoutNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          Message = {
            "processId.$" = "$.processResult.processId"
            "status"      = "timeout"
            "message"     = "Business process approval timed out"
          }
          Subject = "Business Process Approval Timeout"
        }
        Next = "ProcessingFailed"
      }
      
      SendCompletionNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          Message = {
            "processId.$"     = "$.processResult.processId"
            "processType.$"   = "$.processResult.processType"
            "status"          = "completed"
            "completionTime"  = "$$.State.EnteredTime"
            "message"         = "Business process completed successfully"
          }
          Subject = "Business Process Completed"
        }
        Next = "LogToQueue"
      }
      
      LogToQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = aws_sqs_queue.task_queue.url
          MessageBody = {
            "executionArn.$"  = "$$.Execution.Name"
            "processId.$"     = "$.processResult.processId"
            "processType.$"   = "$.processResult.processType"
            "completionTime"  = "$$.State.EnteredTime"
            "status"          = "completed"
            "auditLog"        = "Process completed successfully and logged for audit purposes"
          }
        }
        End = true
      }
      
      ProcessingFailed = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          Message = {
            "executionArn.$" = "$$.Execution.Name"
            "error"          = "Business process failed"
            "details.$"      = "$.error"
            "failureTime"    = "$$.State.EnteredTime"
          }
          Subject = "Business Process Failed"
        }
        Next = "LogFailureToQueue"
      }
      
      LogFailureToQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = aws_sqs_queue.task_queue.url
          MessageBody = {
            "executionArn.$" = "$$.Execution.Name"
            "status"         = "failed"
            "failureTime"    = "$$.State.EnteredTime"
            "error.$"        = "$.error"
            "auditLog"       = "Process failed and logged for audit purposes"
          }
        }
        End = true
      }
    }
  })
}

# Step Functions state machine
resource "aws_sfn_state_machine" "business_workflow" {
  name       = "${local.resource_prefix}-workflow"
  role_arn   = aws_iam_role.step_functions_role.arn
  definition = local.state_machine_definition
  type       = "STANDARD"

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_logs.arn}:*"
    include_execution_data = true
    level                  = var.step_functions_log_level
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.step_functions_policy,
    aws_cloudwatch_log_group.step_functions_logs
  ]
}

# ================================
# API Gateway for Human Task Callbacks
# ================================

# API Gateway REST API for human approvals
resource "aws_api_gateway_rest_api" "approval_api" {
  name        = "${local.resource_prefix}-approval-api"
  description = "API for business process approvals and task callbacks"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

# API Gateway resource for approval endpoints
resource "aws_api_gateway_resource" "approval_resource" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  parent_id   = aws_api_gateway_rest_api.approval_api.root_resource_id
  path_part   = "approval"
}

# API Gateway method for POST requests
resource "aws_api_gateway_method" "approval_post" {
  rest_api_id   = aws_api_gateway_rest_api.approval_api.id
  resource_id   = aws_api_gateway_resource.approval_resource.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

# Lambda function for handling approval callbacks
resource "local_file" "approval_lambda_source" {
  filename = "${path.module}/approval_handler.py"
  content  = <<EOF
import json
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Step Functions client
stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Handle human approval callbacks for Step Functions workflows.
    
    This function processes approval decisions from users and resumes
    paused Step Functions executions using task tokens.
    """
    
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        # Extract required parameters
        task_token = body.get('taskToken')
        approval_decision = body.get('decision', '').upper()
        approver = body.get('approver', 'unknown')
        comments = body.get('comments', '')
        
        if not task_token:
            raise ValueError("Missing required parameter: taskToken")
        
        if approval_decision not in ['APPROVE', 'REJECT']:
            raise ValueError("Decision must be either 'APPROVE' or 'REJECT'")
        
        # Prepare the result to send back to Step Functions
        result = {
            'approved': approval_decision == 'APPROVE',
            'approver': approver,
            'comments': comments,
            'timestamp': context.aws_request_id,
            'decision': approval_decision
        }
        
        if approval_decision == 'APPROVE':
            # Send task success
            stepfunctions.send_task_success(
                taskToken=task_token,
                output=json.dumps(result)
            )
            logger.info(f"Process approved by {approver}")
            message = "Approval successful. Workflow will continue."
        else:
            # Send task failure for rejection
            stepfunctions.send_task_failure(
                taskToken=task_token,
                error='ApprovalRejected',
                cause=f'Process rejected by {approver}: {comments}'
            )
            logger.info(f"Process rejected by {approver}")
            message = "Process rejected. Workflow will terminate."
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': message,
                'decision': approval_decision,
                'approver': approver
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing approval: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process approval'
            })
        }
EOF
}

# Create ZIP archive for approval Lambda
data "archive_file" "approval_lambda_zip" {
  type        = "zip"
  source_file = local_file.approval_lambda_source.filename
  output_path = "${path.module}/approval_handler.zip"
  depends_on  = [local_file.approval_lambda_source]
}

# IAM role for approval Lambda
resource "aws_iam_role" "approval_lambda_role" {
  name = "${local.resource_prefix}-approval-lambda-role"

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

# IAM policy for approval Lambda
resource "aws_iam_role_policy" "approval_lambda_policy" {
  name = "${local.resource_prefix}-approval-lambda-policy"
  role = aws_iam_role.approval_lambda_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Resource = "*"
      }
    ]
  })
}

# Approval Lambda function
resource "aws_lambda_function" "approval_handler" {
  filename         = data.archive_file.approval_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-approval-handler"
  role            = aws_iam_role.approval_lambda_role.arn
  handler         = "approval_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 30
  source_code_hash = data.archive_file.approval_lambda_zip.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.approval_lambda_policy,
    aws_cloudwatch_log_group.approval_lambda_logs
  ]
}

# CloudWatch Log Group for approval Lambda
resource "aws_cloudwatch_log_group" "approval_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-approval-handler"
  retention_in_days = 14
  tags              = local.common_tags
}

# API Gateway integration with approval Lambda
resource "aws_api_gateway_integration" "approval_integration" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  resource_id = aws_api_gateway_resource.approval_resource.id
  http_method = aws_api_gateway_method.approval_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.approval_handler.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.approval_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.approval_api.execution_arn}/*/*"
}

# API Gateway method response
resource "aws_api_gateway_method_response" "approval_response_200" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  resource_id = aws_api_gateway_resource.approval_resource.id
  http_method = aws_api_gateway_method.approval_post.http_method
  status_code = "200"

  response_headers = {
    "Access-Control-Allow-Origin" = true
  }
}

# API Gateway integration response
resource "aws_api_gateway_integration_response" "approval_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  resource_id = aws_api_gateway_resource.approval_resource.id
  http_method = aws_api_gateway_method.approval_post.http_method
  status_code = aws_api_gateway_method_response.approval_response_200.status_code

  response_headers = {
    "Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.approval_integration]
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "approval_deployment" {
  depends_on = [
    aws_api_gateway_method.approval_post,
    aws_api_gateway_integration.approval_integration,
    aws_api_gateway_integration_response.approval_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.approval_api.id
  stage_name  = var.api_gateway_stage_name

  lifecycle {
    create_before_destroy = true
  }
}

# ================================
# CloudWatch Monitoring and Alarms
# ================================

# CloudWatch alarm for Step Functions execution failures
resource "aws_cloudwatch_metric_alarm" "step_functions_failures" {
  alarm_name          = "${local.resource_prefix}-stepfunctions-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Step Functions execution failures"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.business_workflow.arn
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.business_processor.function_name
  }

  tags = local.common_tags
}