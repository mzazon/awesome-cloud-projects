# ==============================================================================
# MAIN CONFIGURATION - Customer Service Chatbots with Amazon Lex
# ==============================================================================

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = lower(random_id.suffix.hex)
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "customer-service-chatbots-amazon-lex"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# ==============================================================================
# DYNAMODB TABLE - Customer Data Storage
# ==============================================================================

resource "aws_dynamodb_table" "customer_data" {
  name           = "${var.dynamodb_table_name}-${local.name_suffix}"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "CustomerId"

  # Configure capacity only for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "CustomerId"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.dynamodb_table_name}-${local.name_suffix}"
    Type = "CustomerData"
  })
}

# Sample customer data for testing (optional)
resource "aws_dynamodb_table_item" "sample_customers" {
  count      = var.create_sample_data ? length(var.sample_customers) : 0
  table_name = aws_dynamodb_table.customer_data.name
  hash_key   = aws_dynamodb_table.customer_data.hash_key

  item = jsonencode({
    CustomerId = {
      S = var.sample_customers[count.index].customer_id
    }
    Name = {
      S = var.sample_customers[count.index].name
    }
    Email = {
      S = var.sample_customers[count.index].email
    }
    LastOrderId = {
      S = var.sample_customers[count.index].last_order_id
    }
    LastOrderStatus = {
      S = var.sample_customers[count.index].last_order_status
    }
    AccountBalance = {
      N = tostring(var.sample_customers[count.index].account_balance)
    }
  })

  depends_on = [aws_dynamodb_table.customer_data]
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for Amazon Lex service
resource "aws_iam_role" "lex_service_role" {
  name = "LexServiceRole-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lexv2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "LexServiceRole-${local.name_suffix}"
    Type = "ServiceRole"
  })
}

# Attach AWS managed policy for Lex V2
resource "aws_iam_role_policy_attachment" "lex_service_policy" {
  role       = aws_iam_role.lex_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonLexV2BotPolicy"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "LexLambdaRole-${local.name_suffix}"

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
    Name = "LexLambdaRole-${local.name_suffix}"
    Type = "ExecutionRole"
  })
}

# Attach basic execution policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for DynamoDB access
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "LexDynamoDBPolicy-${local.name_suffix}"
  description = "Policy for Lambda to access DynamoDB customer data table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.customer_data.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "LexDynamoDBPolicy-${local.name_suffix}"
    Type = "CustomPolicy"
  })
}

# Attach DynamoDB policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# ==============================================================================
# LAMBDA FUNCTION - Lex Intent Fulfillment
# ==============================================================================

# Lambda function code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Main Lambda handler for Amazon Lex V2 intent fulfillment
    Processes customer service requests and returns appropriate responses
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    slots = event['sessionState']['intent']['slots']
    
    if intent_name == 'OrderStatus':
        return handle_order_status(event, slots)
    elif intent_name == 'BillingInquiry':
        return handle_billing_inquiry(event, slots)
    elif intent_name == 'ProductInfo':
        return handle_product_info(event, slots)
    else:
        return close_intent(event, 'Fulfilled', 
                           'I can help you with order status, billing questions, or product information.')

def handle_order_status(event, slots):
    """Handle order status inquiries"""
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your order status?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            message = f"Hi {item['Name']}! Your last order {item['LastOrderId']} is currently {item['LastOrderStatus']}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving order status: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your order status. Please try again later.')

def handle_billing_inquiry(event, slots):
    """Handle billing and account balance inquiries"""
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your account balance?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            balance = float(item['AccountBalance'])
            message = f"Hi {item['Name']}! Your current account balance is ${balance:.2f}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving billing info: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your account. Please try again later.')

def handle_product_info(event, slots):
    """Handle product information requests"""
    product_name = slots.get('ProductName', {}).get('value', {}).get('interpretedValue')
    
    if not product_name:
        return elicit_slot(event, 'ProductName', 
                          'What product would you like information about?')
    
    # Product information database (in production, this would query a real product database)
    product_info = {
        'laptop': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'smartphone': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'tablet': 'Our tablets are perfect for productivity and entertainment, starting at $399.',
        'computer': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'notebook': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'phone': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'mobile': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'ipad': 'Our tablets are perfect for productivity and entertainment, starting at $399.'
    }
    
    product_lower = product_name.lower()
    if product_lower in product_info:
        message = product_info[product_lower]
    else:
        message = f"I don't have specific information about {product_name}. Please contact our sales team for detailed product information."
    
    return close_intent(event, 'Fulfilled', message)

def elicit_slot(event, slot_to_elicit, message):
    """Prompt user for a required slot value"""
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_to_elicit
            },
            'intent': event['sessionState']['intent']
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, fulfillment_state, message):
    """Close the intent with final response"""
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': fulfillment_state
            }
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
EOF
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_function_code.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_function_code]
}

# Lambda function
resource "aws_lambda_function" "lex_fulfillment" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.customer_data.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.lambda_function_name}-${local.name_suffix}"
    Type = "FulfillmentFunction"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_dynamodb_access,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}-${local.name_suffix}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${var.lambda_function_name}-${local.name_suffix}"
    Type = "LogGroup"
  })
}

# ==============================================================================
# AMAZON LEX BOT CONFIGURATION
# ==============================================================================

# Amazon Lex V2 Bot
resource "aws_lexv2models_bot" "customer_service_bot" {
  name        = "${var.bot_name}-${local.name_suffix}"
  description = var.bot_description
  role_arn    = aws_iam_role.lex_service_role.arn

  data_privacy {
    child_directed = false
  }

  idle_session_ttl_in_seconds = var.bot_idle_session_ttl

  tags = merge(local.common_tags, {
    Name = "${var.bot_name}-${local.name_suffix}"
    Type = "LexBot"
  })

  depends_on = [aws_iam_role_policy_attachment.lex_service_policy]
}

# Bot Locale (English US)
resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id                        = aws_lexv2models_bot.customer_service_bot.id
  bot_version                   = "DRAFT"
  locale_id                     = "en_US"
  description                   = "English US locale for customer service bot"
  nlu_intent_confidence_threshold = var.nlu_confidence_threshold

  voice_settings {
    voice_id = var.voice_id
  }

  depends_on = [aws_lexv2models_bot.customer_service_bot]
}

# ==============================================================================
# SLOT TYPES
# ==============================================================================

# CustomerId slot type
resource "aws_lexv2models_slot_type" "customer_id" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "CustomerId"
  description = "Customer identification numbers"

  slot_type_values {
    sample_value {
      value = "12345"
    }
  }

  slot_type_values {
    sample_value {
      value = "67890"
    }
  }

  value_selection_strategy = "ORIGINAL_VALUE"

  depends_on = [aws_lexv2models_bot_locale.en_us]
}

# ProductName slot type
resource "aws_lexv2models_slot_type" "product_name" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ProductName"
  description = "Product names for inquiries"

  slot_type_values {
    sample_value {
      value = "laptop"
    }
    synonyms {
      value = "computer"
    }
    synonyms {
      value = "notebook"
    }
  }

  slot_type_values {
    sample_value {
      value = "smartphone"
    }
    synonyms {
      value = "phone"
    }
    synonyms {
      value = "mobile"
    }
  }

  slot_type_values {
    sample_value {
      value = "tablet"
    }
    synonyms {
      value = "ipad"
    }
  }

  value_selection_strategy = "TOP_RESOLUTION"

  depends_on = [aws_lexv2models_bot_locale.en_us]
}

# ==============================================================================
# INTENTS
# ==============================================================================

# OrderStatus Intent
resource "aws_lexv2models_intent" "order_status" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "OrderStatus"
  description = "Handle order status inquiries"

  sample_utterances {
    utterance = "What is my order status"
  }

  sample_utterances {
    utterance = "Check my order"
  }

  sample_utterances {
    utterance = "Where is my order"
  }

  sample_utterances {
    utterance = "Track my order {CustomerId}"
  }

  sample_utterances {
    utterance = "Order status for {CustomerId}"
  }

  sample_utterances {
    utterance = "My customer ID is {CustomerId}"
  }

  fulfillment_code_hook {
    enabled = true
  }

  depends_on = [aws_lexv2models_slot_type.customer_id]
}

# BillingInquiry Intent
resource "aws_lexv2models_intent" "billing_inquiry" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "BillingInquiry"
  description = "Handle billing and account balance inquiries"

  sample_utterances {
    utterance = "What is my account balance"
  }

  sample_utterances {
    utterance = "Check my balance"
  }

  sample_utterances {
    utterance = "How much do I owe"
  }

  sample_utterances {
    utterance = "Billing information for {CustomerId}"
  }

  sample_utterances {
    utterance = "Account balance for customer {CustomerId}"
  }

  sample_utterances {
    utterance = "My balance please"
  }

  fulfillment_code_hook {
    enabled = true
  }

  depends_on = [aws_lexv2models_slot_type.customer_id]
}

# ProductInfo Intent
resource "aws_lexv2models_intent" "product_info" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ProductInfo"
  description = "Handle product information requests"

  sample_utterances {
    utterance = "Tell me about {ProductName}"
  }

  sample_utterances {
    utterance = "Product information for {ProductName}"
  }

  sample_utterances {
    utterance = "What can you tell me about {ProductName}"
  }

  sample_utterances {
    utterance = "I want to know about {ProductName}"
  }

  sample_utterances {
    utterance = "Details about your {ProductName}"
  }

  fulfillment_code_hook {
    enabled = true
  }

  depends_on = [aws_lexv2models_slot_type.product_name]
}

# ==============================================================================
# SLOTS
# ==============================================================================

# CustomerId slot for OrderStatus intent
resource "aws_lexv2models_slot" "order_status_customer_id" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.order_status.intent_id
  name        = "CustomerId"
  description = "Customer identification number"
  slot_type_id = aws_lexv2models_slot_type.customer_id.slot_type_id

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      message_groups {
        message {
          plain_text_message {
            value = "Could you please provide your customer ID?"
          }
        }
      }
      max_retries = var.max_slot_retries
    }
  }

  depends_on = [aws_lexv2models_intent.order_status, aws_lexv2models_slot_type.customer_id]
}

# CustomerId slot for BillingInquiry intent
resource "aws_lexv2models_slot" "billing_inquiry_customer_id" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.billing_inquiry.intent_id
  name        = "CustomerId"
  description = "Customer identification number for billing"
  slot_type_id = aws_lexv2models_slot_type.customer_id.slot_type_id

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      message_groups {
        message {
          plain_text_message {
            value = "Please provide your customer ID to check your account balance."
          }
        }
      }
      max_retries = var.max_slot_retries
    }
  }

  depends_on = [aws_lexv2models_intent.billing_inquiry, aws_lexv2models_slot_type.customer_id]
}

# ProductName slot for ProductInfo intent
resource "aws_lexv2models_slot" "product_info_product_name" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.product_info.intent_id
  name        = "ProductName"
  description = "Product name for information request"
  slot_type_id = aws_lexv2models_slot_type.product_name.slot_type_id

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      message_groups {
        message {
          plain_text_message {
            value = "What product would you like information about?"
          }
        }
      }
      max_retries = var.max_slot_retries
    }
  }

  depends_on = [aws_lexv2models_intent.product_info, aws_lexv2models_slot_type.product_name]
}

# ==============================================================================
# LAMBDA PERMISSIONS
# ==============================================================================

# Grant Lex permission to invoke Lambda function
resource "aws_lambda_permission" "lex_invoke_lambda" {
  statement_id  = "lex-invoke-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lex_fulfillment.function_name
  principal     = "lexv2.amazonaws.com"
  source_arn    = "arn:aws:lex:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bot/${aws_lexv2models_bot.customer_service_bot.id}"

  depends_on = [aws_lambda_function.lex_fulfillment, aws_lexv2models_bot.customer_service_bot]
}