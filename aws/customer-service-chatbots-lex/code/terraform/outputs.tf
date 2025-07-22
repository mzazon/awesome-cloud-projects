# ==============================================================================
# OUTPUTS - Customer Service Chatbots with Amazon Lex
# ==============================================================================

# Amazon Lex Bot Outputs
output "lex_bot_id" {
  description = "ID of the Amazon Lex bot"
  value       = aws_lexv2models_bot.customer_service_bot.id
}

output "lex_bot_name" {
  description = "Name of the Amazon Lex bot"
  value       = aws_lexv2models_bot.customer_service_bot.name
}

output "lex_bot_arn" {
  description = "ARN of the Amazon Lex bot"
  value       = "arn:aws:lex:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bot/${aws_lexv2models_bot.customer_service_bot.id}"
}

output "lex_bot_alias_id" {
  description = "Test alias ID for the Amazon Lex bot"
  value       = "TSTALIASID"
}

output "lex_bot_locale_id" {
  description = "Locale ID for the Amazon Lex bot"
  value       = aws_lexv2models_bot_locale.en_us.locale_id
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

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda fulfillment function"
  value       = aws_lambda_function.lex_fulfillment.invoke_arn
}

# DynamoDB Table Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB customer data table"
  value       = aws_dynamodb_table.customer_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB customer data table"
  value       = aws_dynamodb_table.customer_data.arn
}

# IAM Role Outputs
output "lex_service_role_arn" {
  description = "ARN of the Amazon Lex service role"
  value       = aws_iam_role.lex_service_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Testing Commands
output "test_bot_commands" {
  description = "AWS CLI commands to test the bot"
  value = {
    order_status = "aws lexv2-runtime recognize-text --bot-id ${aws_lexv2models_bot.customer_service_bot.id} --bot-alias-id TSTALIASID --locale-id ${aws_lexv2models_bot_locale.en_us.locale_id} --session-id test-session-1 --text 'What is my order status for customer 12345?'"
    billing_inquiry = "aws lexv2-runtime recognize-text --bot-id ${aws_lexv2models_bot.customer_service_bot.id} --bot-alias-id TSTALIASID --locale-id ${aws_lexv2models_bot_locale.en_us.locale_id} --session-id test-session-2 --text 'Check my account balance for customer 67890'"
    product_info = "aws lexv2-runtime recognize-text --bot-id ${aws_lexv2models_bot.customer_service_bot.id} --bot-alias-id TSTALIASID --locale-id ${aws_lexv2models_bot_locale.en_us.locale_id} --session-id test-session-3 --text 'Tell me about your laptops'"
  }
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    bot_name               = aws_lexv2models_bot.customer_service_bot.name
    bot_id                = aws_lexv2models_bot.customer_service_bot.id
    lambda_function_name  = aws_lambda_function.lex_fulfillment.function_name
    dynamodb_table_name   = aws_dynamodb_table.customer_data.name
    aws_region           = data.aws_region.current.name
    sample_data_created  = var.create_sample_data
    intents_configured   = [
      "OrderStatus",
      "BillingInquiry", 
      "ProductInfo"
    ]
  }
}

# Web Integration Example
output "web_integration_example" {
  description = "Example configuration for web chat integration"
  value = {
    bot_id       = aws_lexv2models_bot.customer_service_bot.id
    bot_alias_id = "TSTALIASID"
    locale_id    = aws_lexv2models_bot_locale.en_us.locale_id
    region       = data.aws_region.current.name
    example_html = "<!-- Add to your webpage -->\n<div id=\"lex-web-ui\"></div>\n<script>\n  const lexConfig = {\n    botId: '${aws_lexv2models_bot.customer_service_bot.id}',\n    botAliasId: 'TSTALIASID',\n    localeId: '${aws_lexv2models_bot_locale.en_us.locale_id}',\n    region: '${data.aws_region.current.name}'\n  };\n</script>"
  }
}

# Cost Estimation
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the solution (approximate)"
  value = {
    note = "Costs depend on usage patterns. Estimates based on moderate usage."
    lex_requests = "Free tier: 10,000 text + 5,000 speech requests/month. After: $0.004/text, $0.0065/speech request"
    lambda_invocations = "Free tier: 1M requests/month. After: $0.20 per 1M requests + compute time"
    dynamodb = "Free tier: 25GB storage + 25 RCU/WCU. After: $0.25/GB/month + $0.25/RCU/month"
    cloudwatch_logs = "Free tier: 5GB/month. After: $0.50/GB/month"
    estimated_total = "$0-15/month for typical customer service bot usage"
  }
}