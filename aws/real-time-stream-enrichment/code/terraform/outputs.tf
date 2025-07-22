# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for enriched data storage"
  value       = aws_s3_bucket.enriched_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for enriched data storage"
  value       = aws_s3_bucket.enriched_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.enriched_data.bucket_domain_name
}

# Kinesis Data Stream Outputs
output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.raw_events.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.raw_events.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis Data Stream"
  value       = aws_kinesis_stream.raw_events.shard_count
}

# Kinesis Data Firehose Outputs
output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.s3_delivery.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.s3_delivery.arn
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB reference data table"
  value       = aws_dynamodb_table.reference_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB reference data table"
  value       = aws_dynamodb_table.reference_data.arn
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the enrichment Lambda function"
  value       = aws_lambda_function.enrichment.function_name
}

output "lambda_function_arn" {
  description = "ARN of the enrichment Lambda function"
  value       = aws_lambda_function.enrichment.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the enrichment Lambda function"
  value       = aws_lambda_function.enrichment.invoke_arn
}

# EventBridge Pipes Outputs
output "eventbridge_pipe_name" {
  description = "Name of the EventBridge Pipe"
  value       = aws_pipes_pipe.enrichment_pipe.name
}

output "eventbridge_pipe_arn" {
  description = "ARN of the EventBridge Pipe"
  value       = aws_pipes_pipe.enrichment_pipe.arn
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "firehose_delivery_role_arn" {
  description = "ARN of the Firehose delivery role"
  value       = aws_iam_role.firehose_delivery_role.arn
}

output "pipes_execution_role_arn" {
  description = "ARN of the EventBridge Pipes execution role"
  value       = aws_iam_role.pipes_execution_role.arn
}

# CloudWatch Log Group Outputs
output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].arn : null
}

# Random ID Output
output "random_id" {
  description = "Random ID used for resource naming"
  value       = random_id.bucket_suffix.hex
}

# Resource Names for CLI Testing
output "test_commands" {
  description = "Example CLI commands for testing the pipeline"
  value = {
    put_record_command = "aws kinesis put-record --stream-name ${aws_kinesis_stream.raw_events.name} --data $(echo '{\"eventId\":\"test-001\",\"productId\":\"PROD-001\",\"quantity\":5,\"timestamp\":\"${timestamp()}\"}' | base64) --partition-key \"PROD-001\""
    list_s3_objects    = "aws s3 ls s3://${aws_s3_bucket.enriched_data.id}/${var.s3_data_prefix}/ --recursive"
    check_lambda_logs  = var.enable_cloudwatch_logs ? "aws logs tail ${aws_cloudwatch_log_group.lambda_logs[0].name} --follow" : "CloudWatch logs not enabled"
  }
}

# Architecture Summary
output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value = {
    data_flow = [
      "1. Events sent to Kinesis Data Stream: ${aws_kinesis_stream.raw_events.name}",
      "2. EventBridge Pipe: ${aws_pipes_pipe.enrichment_pipe.name} processes events",
      "3. Lambda function: ${aws_lambda_function.enrichment.function_name} enriches data using DynamoDB",
      "4. Enriched data delivered to S3: ${aws_s3_bucket.enriched_data.id}",
      "5. Reference data stored in DynamoDB: ${aws_dynamodb_table.reference_data.name}"
    ]
    endpoints = {
      kinesis_stream  = aws_kinesis_stream.raw_events.name
      s3_bucket      = aws_s3_bucket.enriched_data.id
      dynamodb_table = aws_dynamodb_table.reference_data.name
      lambda_function = aws_lambda_function.enrichment.function_name
    }
  }
}

# Cost Estimation Information
output "cost_considerations" {
  description = "Key cost factors for the deployed resources"
  value = {
    primary_costs = [
      "Kinesis Data Stream: ${var.kinesis_stream_mode} mode",
      "Kinesis Data Firehose: Pay per GB delivered",
      "Lambda: Pay per invocation and duration",
      "DynamoDB: ${var.dynamodb_billing_mode} billing mode",
      "S3: Storage and requests"
    ]
    cost_optimization_tips = [
      "Monitor Kinesis shard utilization",
      "Use S3 Intelligent Tiering for long-term storage",
      "Set appropriate Lambda memory allocation",
      "Consider DynamoDB Auto Scaling for variable workloads",
      "Use CloudWatch metrics to optimize buffer settings"
    ]
  }
}