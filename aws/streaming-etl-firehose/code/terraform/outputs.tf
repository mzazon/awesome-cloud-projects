# Outputs for Kinesis Data Firehose Streaming ETL Infrastructure

output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.main.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.main.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

output "lambda_function_name" {
  description = "Name of the Lambda transformation function"
  value       = aws_lambda_function.transform_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda transformation function"
  value       = aws_lambda_function.transform_function.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda transformation function"
  value       = aws_lambda_function.transform_function.invoke_arn
}

output "firehose_role_arn" {
  description = "ARN of the IAM role used by Kinesis Data Firehose"
  value       = aws_iam_role.firehose_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch log group for Lambda function"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "cloudwatch_log_group_firehose" {
  description = "CloudWatch log group for Firehose delivery stream"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.firehose_logs[0].name : null
}

output "test_commands" {
  description = "Sample commands to test the Firehose stream"
  value = {
    send_test_record = "aws firehose put-record --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.main.name} --record '{\"Data\":\"$(echo '{\"event_type\":\"page_view\",\"user_id\":\"test-user\",\"page_url\":\"https://example.com\"}' | base64)\"}'"
    list_s3_objects  = "aws s3 ls s3://${aws_s3_bucket.data_bucket.id}/processed-data/ --recursive"
    check_lambda_logs = var.enable_cloudwatch_logs ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs[0].name}" : "CloudWatch logs disabled"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring the infrastructure"
  value = var.enable_cloudwatch_logs ? {
    firehose_cloudwatch = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.firehose_logs[0].name, "/", "$252F")}"
    lambda_cloudwatch   = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs[0].name, "/", "$252F")}"
    s3_console         = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.data_bucket.id}"
    firehose_console   = "https://console.aws.amazon.com/firehose/home?region=${data.aws_region.current.name}#/details/${aws_kinesis_firehose_delivery_stream.main.name}/monitoring"
  } : {}
}

output "cost_optimization_notes" {
  description = "Information about cost optimization features"
  value = {
    s3_lifecycle_enabled = var.s3_lifecycle_enabled
    transition_to_ia_days = var.s3_lifecycle_enabled ? var.s3_transition_days : "N/A"
    parquet_format = "Enabled - reduces storage costs and improves query performance"
    compression = "GZIP compression enabled for reduced storage costs"
  }
}

output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value = {
    data_flow = "Source → Kinesis Data Firehose → Lambda Transform → S3 (Parquet)"
    processing = "Real-time streaming ETL with data transformation"
    storage_format = "Parquet with GZIP compression"
    partitioning = "Year/Month/Day/Hour partitioning for efficient querying"
    monitoring = var.enable_cloudwatch_logs ? "CloudWatch logs and metrics enabled" : "Basic monitoring only"
  }
}