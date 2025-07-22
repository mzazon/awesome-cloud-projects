# Outputs for the URL Shortener service

output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = aws_apigatewayv2_stage.prod.invoke_url
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.url_shortener.id
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.url_shortener.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.url_shortener.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.url_storage.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.url_storage.arn
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.url_shortener[0].dashboard_name}" : null
}

output "sample_create_url_command" {
  description = "Sample curl command to create a short URL"
  value = <<-EOT
    curl -X POST ${aws_apigatewayv2_stage.prod.invoke_url}/shorten \
      -H "Content-Type: application/json" \
      -d '{"url": "https://docs.aws.amazon.com/lambda/latest/dg/welcome.html"}'
  EOT
}

output "sample_redirect_url" {
  description = "Sample redirect URL format (replace {short_id} with actual short ID)"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/{short_id}"
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    api_gateway = {
      name = aws_apigatewayv2_api.url_shortener.name
      url  = aws_apigatewayv2_stage.prod.invoke_url
    }
    lambda_function = {
      name    = aws_lambda_function.url_shortener.function_name
      runtime = aws_lambda_function.url_shortener.runtime
      timeout = aws_lambda_function.url_shortener.timeout
      memory  = aws_lambda_function.url_shortener.memory_size
    }
    dynamodb_table = {
      name         = aws_dynamodb_table.url_storage.name
      billing_mode = aws_dynamodb_table.url_storage.billing_mode
    }
    monitoring = {
      log_group        = aws_cloudwatch_log_group.lambda_logs.name
      dashboard_exists = var.enable_cloudwatch_dashboard
    }
  }
}