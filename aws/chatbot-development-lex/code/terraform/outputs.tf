# Amazon Lex Bot Outputs
output "bot_id" {
  description = "ID of the Amazon Lex bot"
  value       = aws_lexv2models_bot.customer_service_bot.id
}

output "bot_name" {
  description = "Name of the Amazon Lex bot"
  value       = aws_lexv2models_bot.customer_service_bot.name
}

output "bot_arn" {
  description = "ARN of the Amazon Lex bot"
  value       = aws_lexv2models_bot.customer_service_bot.arn
}

output "bot_alias_id" {
  description = "ID of the production bot alias"
  value       = aws_lexv2models_bot_alias.production.bot_alias_id
}

output "bot_alias_arn" {
  description = "ARN of the production bot alias"
  value       = aws_lexv2models_bot_alias.production.arn
}

output "bot_endpoint" {
  description = "Regional endpoint for the Amazon Lex bot"
  value       = "https://runtime-v2-lex.${data.aws_region.current.name}.amazonaws.com"
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda fulfillment function"
  value       = aws_lambda_function.lex_fulfillment.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda fulfillment function"
  value       = aws_lambda_function.lex_fulfillment.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda fulfillment function"
  value       = aws_lambda_function.lex_fulfillment.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

# DynamoDB Table Outputs
output "orders_table_name" {
  description = "Name of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders_table.name
}

output "orders_table_arn" {
  description = "ARN of the DynamoDB orders table"
  value       = aws_dynamodb_table.orders_table.arn
}

output "orders_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = try(aws_dynamodb_table.orders_table.stream_arn, null)
}

# S3 Bucket Outputs
output "products_bucket_name" {
  description = "Name of the S3 products bucket"
  value       = aws_s3_bucket.products_bucket.bucket
}

output "products_bucket_arn" {
  description = "ARN of the S3 products bucket"
  value       = aws_s3_bucket.products_bucket.arn
}

output "products_bucket_domain_name" {
  description = "Domain name of the S3 products bucket"
  value       = aws_s3_bucket.products_bucket.bucket_domain_name
}

# IAM Role Outputs
output "lex_role_arn" {
  description = "ARN of the Lex service role"
  value       = aws_iam_role.lex_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# Integration Information
output "integration_endpoints" {
  description = "Endpoints for integrating with external applications"
  value = {
    web_chat = "https://runtime-v2-lex.${data.aws_region.current.name}.amazonaws.com/bots/${aws_lexv2models_bot.customer_service_bot.id}/aliases/${aws_lexv2models_bot_alias.production.bot_alias_id}/users/USER_ID/conversations/CONVERSATION_ID"
    runtime_endpoint = "https://runtime-v2-lex.${data.aws_region.current.name}.amazonaws.com"
  }
}

# Testing Information
output "testing_information" {
  description = "Information for testing the chatbot"
  value = {
    test_order_ids = ["ORD123456", "ORD789012"]
    sample_utterances = [
      "Tell me about your electronics",
      "Check order status for ORD123456",
      "I need help with my account"
    ]
    aws_cli_test_command = "aws lexv2-runtime recognize-text --bot-id ${aws_lexv2models_bot.customer_service_bot.id} --bot-alias-id ${aws_lexv2models_bot_alias.production.bot_alias_id} --locale-id en_US --session-id test-session --text 'Tell me about your products'"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    bot_name               = aws_lexv2models_bot.customer_service_bot.name
    lambda_function        = aws_lambda_function.lex_fulfillment.function_name
    dynamodb_table         = aws_dynamodb_table.orders_table.name
    s3_bucket             = aws_s3_bucket.products_bucket.bucket
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for using the chatbot"
  value = [
    "Test the bot using the AWS CLI or SDK",
    "Integrate with web applications using the Lex Runtime API",
    "Configure additional channels (Slack, Facebook Messenger, etc.)",
    "Monitor performance using CloudWatch metrics",
    "Add more intents and conversation flows as needed"
  ]
}