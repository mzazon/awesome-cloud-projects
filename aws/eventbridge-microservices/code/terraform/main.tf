# Event-Driven Architecture with Amazon EventBridge
# This Terraform configuration creates a complete event-driven architecture
# demonstrating microservices communication through EventBridge

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Event bus configuration
  custom_bus_name = "${var.custom_bus_name}-${random_string.suffix.result}"
  
  # Lambda function configurations
  lambda_functions = {
    order_processor = {
      name        = "order-processor"
      description = "Processes order events and emits order processed events"
      filename    = "order_processor.py"
      handler     = "order_processor.lambda_handler"
    }
    inventory_manager = {
      name        = "inventory-manager"
      description = "Manages inventory reservations for processed orders"
      filename    = "inventory_manager.py"
      handler     = "inventory_manager.lambda_handler"
    }
    event_generator = {
      name        = "event-generator"
      description = "Generates sample order events for testing"
      filename    = "event_generator.py"
      handler     = "event_generator.lambda_handler"
    }
  }

  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "EventDrivenArchitectureDemo"
  })
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# EventBridge Custom Event Bus
#------------------------------------------------------------------------------

# Custom event bus for e-commerce domain events
# Provides domain isolation and organizational boundaries
resource "aws_cloudwatch_event_bus" "ecommerce_bus" {
  name = local.custom_bus_name

  tags = merge(local.common_tags, {
    Name = local.custom_bus_name
    Type = "CustomEventBus"
  })
}

#------------------------------------------------------------------------------
# IAM Role and Policies for Lambda Functions
#------------------------------------------------------------------------------

# Trust policy document for Lambda service
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

# Custom policy for EventBridge interactions
data "aws_iam_policy_document" "lambda_eventbridge_policy" {
  # EventBridge permissions for Lambda functions
  statement {
    effect = "Allow"
    actions = [
      "events:PutEvents",
      "events:ListRules",
      "events:DescribeRule"
    ]
    resources = ["*"]
  }

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
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${local.name_prefix}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-execution-role"
    Type = "IAMRole"
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for EventBridge interactions
resource "aws_iam_role_policy" "lambda_eventbridge_policy" {
  name   = "EventBridgeInteractionPolicy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_eventbridge_policy.json
}

#------------------------------------------------------------------------------
# Lambda Function Source Code
#------------------------------------------------------------------------------

# Order processor Lambda function code
resource "local_file" "order_processor_code" {
  content = <<EOF
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing order event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate order processing logic
        print(f"Processing order {order_id} for customer {customer_id}")
        print(f"Order total: ${total_amount}")
        
        # Emit order processed event
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'totalAmount': total_amount,
                        'status': 'processed',
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        print(f"Emitted order processed event: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order {order_id} processed successfully',
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        
        # Emit order failed event
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processing Failed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
  filename = "order_processor.py"
}

# Inventory manager Lambda function code
resource "local_file" "inventory_manager_code" {
  content = <<EOF
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing inventory event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    
    try:
        # Simulate inventory check and reservation
        print(f"Checking inventory for order {order_id}")
        
        # Simulate inventory availability (randomize for demo)
        import random
        inventory_available = random.choice([True, True, True, False])  # 75% success rate
        
        if inventory_available:
            # Emit inventory reserved event
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'reserved',
                            'reservationId': f"res-{order_id}-{int(datetime.now().timestamp())}",
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory reserved for order {order_id}',
                    'eventId': response['Entries'][0]['EventId']
                })
            }
        else:
            # Emit inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'unavailable',
                            'reason': 'Insufficient stock',
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory unavailable for order {order_id}'
                })
            }
        
    except Exception as e:
        print(f"Error managing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
  filename = "inventory_manager.py"
}

# Event generator Lambda function code
resource "local_file" "event_generator_code" {
  content = <<EOF
import json
import boto3
import os
from datetime import datetime
import random

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    # Generate sample order data
    order_id = f"ord-{int(datetime.now().timestamp())}-{random.randint(1000, 9999)}"
    customer_id = f"cust-{random.randint(1000, 9999)}"
    total_amount = round(random.uniform(25.99, 299.99), 2)
    
    # Create order event
    order_event = {
        'Source': 'ecommerce.api',
        'DetailType': 'Order Created',
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'items': [
                {
                    'productId': f'prod-{random.randint(100, 999)}',
                    'quantity': random.randint(1, 3),
                    'price': round(total_amount / random.randint(1, 3), 2)
                }
            ],
            'timestamp': datetime.utcnow().isoformat()
        }),
        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
    }
    
    try:
        response = eventbridge.put_events(Entries=[order_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order event generated successfully',
                'orderId': order_id,
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
  filename = "event_generator.py"
}

# Create ZIP files for Lambda deployment
data "archive_file" "order_processor_zip" {
  type        = "zip"
  source_file = local_file.order_processor_code.filename
  output_path = "order_processor.zip"
  depends_on  = [local_file.order_processor_code]
}

data "archive_file" "inventory_manager_zip" {
  type        = "zip"
  source_file = local_file.inventory_manager_code.filename
  output_path = "inventory_manager.zip"
  depends_on  = [local_file.inventory_manager_code]
}

data "archive_file" "event_generator_zip" {
  type        = "zip"
  source_file = local_file.event_generator_code.filename
  output_path = "event_generator.zip"
  depends_on  = [local_file.event_generator_code]
}

#------------------------------------------------------------------------------
# Lambda Functions
#------------------------------------------------------------------------------

# Order Processor Lambda Function
resource "aws_lambda_function" "order_processor" {
  filename         = data.archive_file.order_processor_zip.output_path
  function_name    = "${local.name_prefix}-order-processor"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "order_processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.order_processor_zip.output_base64sha256

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.ecommerce_bus.name
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-order-processor"
    Type        = "LambdaFunction"
    Component   = "OrderProcessing"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_eventbridge_policy,
    aws_cloudwatch_log_group.order_processor_logs
  ]
}

# Inventory Manager Lambda Function
resource "aws_lambda_function" "inventory_manager" {
  filename         = data.archive_file.inventory_manager_zip.output_path
  function_name    = "${local.name_prefix}-inventory-manager"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "inventory_manager.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.inventory_manager_zip.output_base64sha256

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.ecommerce_bus.name
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-inventory-manager"
    Type        = "LambdaFunction"
    Component   = "InventoryManagement"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_eventbridge_policy,
    aws_cloudwatch_log_group.inventory_manager_logs
  ]
}

# Event Generator Lambda Function
resource "aws_lambda_function" "event_generator" {
  filename         = data.archive_file.event_generator_zip.output_path
  function_name    = "${local.name_prefix}-event-generator"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "event_generator.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.event_generator_zip.output_base64sha256

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.ecommerce_bus.name
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-event-generator"
    Type        = "LambdaFunction"
    Component   = "EventGeneration"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_eventbridge_policy,
    aws_cloudwatch_log_group.event_generator_logs
  ]
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

# Log group for order processor Lambda
resource "aws_cloudwatch_log_group" "order_processor_logs" {
  name              = "/aws/lambda/${local.name_prefix}-order-processor"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${local.name_prefix}-order-processor"
    Type      = "CloudWatchLogGroup"
    Component = "OrderProcessing"
  })
}

# Log group for inventory manager Lambda
resource "aws_cloudwatch_log_group" "inventory_manager_logs" {
  name              = "/aws/lambda/${local.name_prefix}-inventory-manager"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${local.name_prefix}-inventory-manager"
    Type      = "CloudWatchLogGroup"
    Component = "InventoryManagement"
  })
}

# Log group for event generator Lambda
resource "aws_cloudwatch_log_group" "event_generator_logs" {
  name              = "/aws/lambda/${local.name_prefix}-event-generator"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/lambda/${local.name_prefix}-event-generator"
    Type      = "CloudWatchLogGroup"
    Component = "EventGeneration"
  })
}

# Log group for EventBridge monitoring
resource "aws_cloudwatch_log_group" "eventbridge_logs" {
  name              = "/aws/events/${local.custom_bus_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/events/${local.custom_bus_name}"
    Type      = "CloudWatchLogGroup"
    Component = "EventBridgeMonitoring"
  })
}

#------------------------------------------------------------------------------
# SQS Queue for Payment Processing
#------------------------------------------------------------------------------

# SQS queue for asynchronous payment processing
resource "aws_sqs_queue" "payment_processing" {
  name                       = "${local.name_prefix}-payment-processing"
  delay_seconds              = var.sqs_delay_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-payment-processing"
    Type      = "SQSQueue"
    Component = "PaymentProcessing"
  })
}

#------------------------------------------------------------------------------
# EventBridge Rules and Event Patterns
#------------------------------------------------------------------------------

# Rule 1: Route new orders to order processing Lambda
resource "aws_cloudwatch_event_rule" "order_processing_rule" {
  name           = "${local.name_prefix}-order-processing-rule"
  description    = "Route new orders to processing Lambda"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = ["ecommerce.api"]
    detail-type   = ["Order Created"]
    detail = {
      totalAmount = [{ numeric = [">", 0] }]
    }
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-order-processing-rule"
    Type      = "EventBridgeRule"
    Component = "OrderProcessing"
  })
}

# Rule 2: Route processed orders to inventory management
resource "aws_cloudwatch_event_rule" "inventory_check_rule" {
  name           = "${local.name_prefix}-inventory-check-rule"
  description    = "Route processed orders to inventory check"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = ["ecommerce.order"]
    detail-type   = ["Order Processed"]
    detail = {
      status = ["processed"]
    }
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-inventory-check-rule"
    Type      = "EventBridgeRule"
    Component = "InventoryManagement"
  })
}

# Rule 3: Route inventory reserved events to payment processing
resource "aws_cloudwatch_event_rule" "payment_processing_rule" {
  name           = "${local.name_prefix}-payment-processing-rule"
  description    = "Route inventory reserved events to payment"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source        = ["ecommerce.inventory"]
    detail-type   = ["Inventory Reserved"]
    detail = {
      status = ["reserved"]
    }
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-payment-processing-rule"
    Type      = "EventBridgeRule"
    Component = "PaymentProcessing"
  })
}

# Rule 4: Archive all events to CloudWatch Logs for monitoring
resource "aws_cloudwatch_event_rule" "monitoring_rule" {
  name           = "${local.name_prefix}-monitoring-rule"
  description    = "Archive all ecommerce events for monitoring"
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  state          = "ENABLED"

  event_pattern = jsonencode({
    source = [{ prefix = "ecommerce." }]
  })

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-monitoring-rule"
    Type      = "EventBridgeRule"
    Component = "Monitoring"
  })
}

#------------------------------------------------------------------------------
# EventBridge Rule Targets
#------------------------------------------------------------------------------

# Target for order processing rule -> order processor Lambda
resource "aws_cloudwatch_event_target" "order_processing_target" {
  rule           = aws_cloudwatch_event_rule.order_processing_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  target_id      = "OrderProcessorLambdaTarget"
  arn            = aws_lambda_function.order_processor.arn
}

# Target for inventory check rule -> inventory manager Lambda
resource "aws_cloudwatch_event_target" "inventory_check_target" {
  rule           = aws_cloudwatch_event_rule.inventory_check_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  target_id      = "InventoryManagerLambdaTarget"
  arn            = aws_lambda_function.inventory_manager.arn
}

# Target for payment processing rule -> SQS queue
resource "aws_cloudwatch_event_target" "payment_processing_target" {
  rule           = aws_cloudwatch_event_rule.payment_processing_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  target_id      = "PaymentProcessingSQSTarget"
  arn            = aws_sqs_queue.payment_processing.arn
}

# Target for monitoring rule -> CloudWatch Logs
resource "aws_cloudwatch_event_target" "monitoring_target" {
  rule           = aws_cloudwatch_event_rule.monitoring_rule.name
  event_bus_name = aws_cloudwatch_event_bus.ecommerce_bus.name
  target_id      = "MonitoringCloudWatchLogsTarget"
  arn            = aws_cloudwatch_log_group.eventbridge_logs.arn
}

#------------------------------------------------------------------------------
# Lambda Permissions for EventBridge
#------------------------------------------------------------------------------

# Permission for EventBridge to invoke order processor Lambda
resource "aws_lambda_permission" "allow_eventbridge_order_processor" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_processing_rule.arn
}

# Permission for EventBridge to invoke inventory manager Lambda
resource "aws_lambda_permission" "allow_eventbridge_inventory_manager" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inventory_check_rule.arn
}

#------------------------------------------------------------------------------
# SQS Queue Policy for EventBridge
#------------------------------------------------------------------------------

# IAM policy document for SQS queue to allow EventBridge access
data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.payment_processing.arn]
    
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.payment_processing_rule.arn]
    }
  }
}

# Apply the policy to the SQS queue
resource "aws_sqs_queue_policy" "payment_processing_policy" {
  queue_url = aws_sqs_queue.payment_processing.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}