# Random suffix for unique resource naming
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

locals {
  suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Resource names with optional random suffix
  bot_name               = var.bot_name != "" ? var.bot_name : "${var.project_name}-bot${local.suffix != "" ? "-${local.suffix}" : ""}"
  lambda_function_name   = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-fulfillment${local.suffix != "" ? "-${local.suffix}" : ""}"
  orders_table_name      = var.orders_table_name != "" ? var.orders_table_name : "${var.project_name}-orders${local.suffix != "" ? "-${local.suffix}" : ""}"
  products_bucket_name   = var.products_bucket_name != "" ? var.products_bucket_name : "${var.project_name}-products${local.suffix != "" ? "-${local.suffix}" : ""}"
  lex_role_name         = "${var.project_name}-lex-role${local.suffix != "" ? "-${local.suffix}" : ""}"
  lambda_role_name      = "${var.project_name}-lambda-role${local.suffix != "" ? "-${local.suffix}" : ""}"
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#-----------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#-----------------------------------------------------------------------------

# IAM role for Amazon Lex
resource "aws_iam_role" "lex_role" {
  name = local.lex_role_name

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

  tags = local.common_tags
}

# Attach basic Lex policy to the role
resource "aws_iam_role_policy_attachment" "lex_basic_policy" {
  role       = aws_iam_role.lex_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonLexFullAccess"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
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

  tags = local.common_tags
}

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda to access DynamoDB and S3
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${local.lambda_role_name}-custom-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = aws_dynamodb_table.orders_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.products_bucket.arn,
          "${aws_s3_bucket.products_bucket.arn}/*"
        ]
      }
    ]
  })
}

#-----------------------------------------------------------------------------
# DYNAMODB TABLE
#-----------------------------------------------------------------------------

# DynamoDB table for storing order information
resource "aws_dynamodb_table" "orders_table" {
  name           = local.orders_table_name
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "OrderId"

  attribute {
    name = "OrderId"
    type = "S"
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name        = local.orders_table_name
    Description = "DynamoDB table for customer orders data"
  })
}

# Add sample order data to DynamoDB table
resource "aws_dynamodb_table_item" "sample_order_1" {
  table_name = aws_dynamodb_table.orders_table.name
  hash_key   = aws_dynamodb_table.orders_table.hash_key

  item = jsonencode({
    OrderId = {
      S = "ORD123456"
    }
    Status = {
      S = "Shipped"
    }
    EstimatedDelivery = {
      S = "2024-01-15"
    }
    CustomerEmail = {
      S = "customer@example.com"
    }
  })
}

resource "aws_dynamodb_table_item" "sample_order_2" {
  table_name = aws_dynamodb_table.orders_table.name
  hash_key   = aws_dynamodb_table.orders_table.hash_key

  item = jsonencode({
    OrderId = {
      S = "ORD789012"
    }
    Status = {
      S = "Processing"
    }
    EstimatedDelivery = {
      S = "2024-01-20"
    }
    CustomerEmail = {
      S = "customer2@example.com"
    }
  })
}

#-----------------------------------------------------------------------------
# S3 BUCKET
#-----------------------------------------------------------------------------

# S3 bucket for product catalog
resource "aws_s3_bucket" "products_bucket" {
  bucket        = local.products_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = local.products_bucket_name
    Description = "S3 bucket for product catalog data"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "products_bucket_versioning" {
  bucket = aws_s3_bucket.products_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "products_bucket_encryption" {
  bucket = aws_s3_bucket.products_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "products_bucket_pab" {
  bucket = aws_s3_bucket.products_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#-----------------------------------------------------------------------------
# LAMBDA FUNCTION
#-----------------------------------------------------------------------------

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lex_fulfillment.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      orders_table_name    = local.orders_table_name
      products_bucket_name = local.products_bucket_name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for Lex fulfillment
resource "aws_lambda_function" "lex_fulfillment" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      ORDERS_TABLE    = aws_dynamodb_table.orders_table.name
      PRODUCTS_BUCKET = aws_s3_bucket.products_bucket.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for Lex bot fulfillment"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_custom_policy,
    aws_cloudwatch_log_group.lambda_log_group,
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# Lambda permission for Lex to invoke the function
resource "aws_lambda_permission" "lex_invoke_lambda" {
  statement_id  = "AllowExecutionFromLex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lex_fulfillment.function_name
  principal     = "lexv2.amazonaws.com"
  source_arn    = "arn:aws:lex:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bot-alias/${aws_lexv2models_bot.customer_service_bot.id}/*"
}

#-----------------------------------------------------------------------------
# AMAZON LEX BOT
#-----------------------------------------------------------------------------

# Amazon Lex V2 Bot
resource "aws_lexv2models_bot" "customer_service_bot" {
  name        = local.bot_name
  description = var.bot_description
  role_arn    = aws_iam_role.lex_role.arn

  data_privacy {
    child_directed = false
  }

  idle_session_ttl_in_seconds = var.bot_idle_session_ttl

  tags = merge(local.common_tags, {
    Name        = local.bot_name
    Description = "Customer service chatbot"
  })
}

# Bot locale (English US)
resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id                        = aws_lexv2models_bot.customer_service_bot.id
  bot_version                   = "DRAFT"
  locale_id                     = "en_US"
  nlu_intent_confidence_threshold = var.nlu_confidence_threshold
}

# Custom slot type for product types
resource "aws_lexv2models_slot_type" "product_type" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ProductType"
  description = "Types of products available"

  slot_type_values {
    sample_value {
      value = "electronics"
    }
  }

  slot_type_values {
    sample_value {
      value = "clothing"
    }
  }

  slot_type_values {
    sample_value {
      value = "books"
    }
  }
}

# Product Information Intent
resource "aws_lexv2models_intent" "product_information" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "ProductInformation"
  description = "Intent to handle product information requests"

  sample_utterances {
    utterance = "Tell me about your products"
  }

  sample_utterances {
    utterance = "What do you sell"
  }

  sample_utterances {
    utterance = "I want to know about {ProductType}"
  }

  sample_utterances {
    utterance = "Do you have {ProductType}"
  }

  sample_utterances {
    utterance = "Show me {ProductType} products"
  }

  slot_priorities {
    priority  = 1
    slot_name = "ProductType"
  }

  fulfillment_code_hook {
    enabled = true
  }
}

# Product Type Slot for Product Information Intent
resource "aws_lexv2models_slot" "product_type_slot" {
  bot_id       = aws_lexv2models_bot.customer_service_bot.id
  bot_version  = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id    = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id    = aws_lexv2models_intent.product_information.intent_id
  name         = "ProductType"
  description  = "The type of product the customer is asking about"
  slot_type_id = aws_lexv2models_slot_type.product_type.slot_type_id

  value_elicitation_setting {
    slot_constraint = "Optional"

    prompt_specification {
      max_retries                 = 2
      allow_interrupt             = true
      message_selection_strategy  = "Random"

      message_groups {
        message {
          plain_text_message {
            value = "What type of product are you interested in?"
          }
        }
      }
    }
  }
}

# Order Status Intent
resource "aws_lexv2models_intent" "order_status" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "OrderStatus"
  description = "Intent to handle order status inquiries"

  sample_utterances {
    utterance = "Check my order status"
  }

  sample_utterances {
    utterance = "Where is my order"
  }

  sample_utterances {
    utterance = "Track order {OrderNumber}"
  }

  sample_utterances {
    utterance = "Order status for {OrderNumber}"
  }

  sample_utterances {
    utterance = "What's the status of order {OrderNumber}"
  }

  slot_priorities {
    priority  = 1
    slot_name = "OrderNumber"
  }

  fulfillment_code_hook {
    enabled = true
  }
}

# Order Number Slot for Order Status Intent
resource "aws_lexv2models_slot" "order_number_slot" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  intent_id   = aws_lexv2models_intent.order_status.intent_id
  name        = "OrderNumber"
  description = "The customer's order number"
  slot_type_id = "AMAZON.AlphaNumeric"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries                = 2
      allow_interrupt            = true
      message_selection_strategy = "Random"

      message_groups {
        message {
          plain_text_message {
            value = "Please provide your order number."
          }
        }
      }
    }
  }
}

# Support Request Intent
resource "aws_lexv2models_intent" "support_request" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  bot_version = aws_lexv2models_bot_locale.en_us.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "SupportRequest"
  description = "Intent to handle complex support requests"

  sample_utterances {
    utterance = "I need help"
  }

  sample_utterances {
    utterance = "Speak to customer service"
  }

  sample_utterances {
    utterance = "I have a problem"
  }

  sample_utterances {
    utterance = "Connect me to support"
  }

  sample_utterances {
    utterance = "I need technical assistance"
  }

  fulfillment_code_hook {
    enabled = true
  }
}

# Bot Version (after building the locale)
resource "aws_lexv2models_bot_version" "v1" {
  bot_id      = aws_lexv2models_bot.customer_service_bot.id
  description = "Production version of customer service bot"

  bot_version_locale_specification {
    locale_id                        = aws_lexv2models_bot_locale.en_us.locale_id
    source_bot_version              = "DRAFT"
  }

  depends_on = [
    aws_lexv2models_intent.product_information,
    aws_lexv2models_intent.order_status,
    aws_lexv2models_intent.support_request,
    aws_lexv2models_slot.product_type_slot,
    aws_lexv2models_slot.order_number_slot,
    aws_lexv2models_slot_type.product_type
  ]
}

# Bot Alias for production
resource "aws_lexv2models_bot_alias" "production" {
  bot_id          = aws_lexv2models_bot.customer_service_bot.id
  bot_alias_name  = "production"
  description     = "Production alias for customer service bot"
  bot_version     = aws_lexv2models_bot_version.v1.bot_version

  bot_alias_locale_settings {
    locale_id = aws_lexv2models_bot_locale.en_us.locale_id
    enabled   = true

    code_hook_specification {
      lambda_code_hook {
        lambda_arn                = aws_lambda_function.lex_fulfillment.arn
        code_hook_interface_version = "1.0"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name        = "production"
    Description = "Production alias for customer service bot"
  })
}