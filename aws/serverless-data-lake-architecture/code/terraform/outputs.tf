# ===== S3 BUCKET OUTPUTS =====

output "s3_bucket_raw_name" {
  description = "Name of the S3 bucket for raw data"
  value       = aws_s3_bucket.raw_data.id
}

output "s3_bucket_raw_arn" {
  description = "ARN of the S3 bucket for raw data"
  value       = aws_s3_bucket.raw_data.arn
}

output "s3_bucket_processed_name" {
  description = "Name of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.id
}

output "s3_bucket_processed_arn" {
  description = "ARN of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.arn
}

output "s3_bucket_quarantine_name" {
  description = "Name of the S3 bucket for quarantine data"
  value       = aws_s3_bucket.quarantine_data.id
}

output "s3_bucket_quarantine_arn" {
  description = "ARN of the S3 bucket for quarantine data"
  value       = aws_s3_bucket.quarantine_data.arn
}

# ===== DYNAMODB OUTPUTS =====

output "dynamodb_metadata_table_name" {
  description = "Name of the DynamoDB metadata table"
  value       = aws_dynamodb_table.metadata.name
}

output "dynamodb_metadata_table_arn" {
  description = "ARN of the DynamoDB metadata table"
  value       = aws_dynamodb_table.metadata.arn
}

output "dynamodb_metadata_table_stream_arn" {
  description = "ARN of the DynamoDB metadata table stream"
  value       = aws_dynamodb_table.metadata.stream_arn
}

# ===== LAMBDA OUTPUTS =====

output "lambda_layer_arn" {
  description = "ARN of the shared Lambda layer"
  value       = aws_lambda_layer_version.shared_layer.arn
}

output "lambda_layer_version" {
  description = "Version of the shared Lambda layer"
  value       = aws_lambda_layer_version.shared_layer.version
}

output "lambda_data_ingestion_function_name" {
  description = "Name of the data ingestion Lambda function"
  value       = aws_lambda_function.data_ingestion.function_name
}

output "lambda_data_ingestion_function_arn" {
  description = "ARN of the data ingestion Lambda function"
  value       = aws_lambda_function.data_ingestion.arn
}

output "lambda_data_validation_function_name" {
  description = "Name of the data validation Lambda function"
  value       = aws_lambda_function.data_validation.function_name
}

output "lambda_data_validation_function_arn" {
  description = "ARN of the data validation Lambda function"
  value       = aws_lambda_function.data_validation.arn
}

output "lambda_quality_monitoring_function_name" {
  description = "Name of the quality monitoring Lambda function"
  value       = aws_lambda_function.quality_monitoring.function_name
}

output "lambda_quality_monitoring_function_arn" {
  description = "ARN of the quality monitoring Lambda function"
  value       = aws_lambda_function.quality_monitoring.arn
}

# ===== IAM OUTPUTS =====

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "glue_service_role_name" {
  description = "Name of the Glue service role"
  value       = aws_iam_role.glue_role.name
}

output "glue_service_role_arn" {
  description = "ARN of the Glue service role"
  value       = aws_iam_role.glue_role.arn
}

# ===== EVENTBRIDGE OUTPUTS =====

output "eventbridge_custom_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.custom_bus.name
}

output "eventbridge_custom_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.custom_bus.arn
}

output "eventbridge_ingestion_rule_name" {
  description = "Name of the data ingestion EventBridge rule"
  value       = aws_cloudwatch_event_rule.data_ingestion_rule.name
}

output "eventbridge_validation_rule_name" {
  description = "Name of the data validation EventBridge rule"
  value       = aws_cloudwatch_event_rule.data_validation_rule.name
}

output "eventbridge_quality_rule_name" {
  description = "Name of the data quality EventBridge rule"
  value       = aws_cloudwatch_event_rule.data_quality_rule.name
}

# ===== GLUE OUTPUTS =====

output "glue_catalog_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.data_catalog.name
}

output "glue_crawler_name" {
  description = "Name of the Glue crawler"
  value       = aws_glue_crawler.data_crawler.name
}

# ===== CLOUDWATCH OUTPUTS =====

output "cloudwatch_log_group_ingestion" {
  description = "CloudWatch log group for data ingestion function"
  value       = aws_cloudwatch_log_group.data_ingestion_logs.name
}

output "cloudwatch_log_group_validation" {
  description = "CloudWatch log group for data validation function"
  value       = aws_cloudwatch_log_group.data_validation_logs.name
}

output "cloudwatch_log_group_quality" {
  description = "CloudWatch log group for quality monitoring function"
  value       = aws_cloudwatch_log_group.quality_monitoring_logs.name
}

# ===== DEPLOYMENT INFORMATION =====

output "deployment_info" {
  description = "Summary of deployed infrastructure"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    aws_region        = var.aws_region
    random_suffix     = local.random_suffix
    deployment_time   = timestamp()
  }
}

# ===== TESTING COMMANDS =====

output "testing_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    upload_test_data = "aws s3 cp test-data.json s3://${aws_s3_bucket.raw_data.id}/input/test-data.json"
    check_processed_data = "aws s3 ls s3://${aws_s3_bucket.processed_data.id}/validated/ --recursive"
    check_quarantine_data = "aws s3 ls s3://${aws_s3_bucket.quarantine_data.id}/quarantine/ --recursive"
    query_metadata = "aws dynamodb scan --table-name ${aws_dynamodb_table.metadata.name} --max-items 5"
    view_logs_ingestion = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${aws_lambda_function.data_ingestion.function_name}'"
    check_crawler_status = "aws glue get-crawler --name ${aws_glue_crawler.data_crawler.name}"
  }
}

# ===== MONITORING ENDPOINTS =====

output "monitoring_info" {
  description = "Information for monitoring the data lake"
  value = {
    cloudwatch_namespace = "DataLake/Quality"
    metrics_to_monitor = [
      "ValidationSuccessRate",
      "AverageQualityScore", 
      "ProcessedRecords"
    ]
    log_groups = [
      aws_cloudwatch_log_group.data_ingestion_logs.name,
      aws_cloudwatch_log_group.data_validation_logs.name,
      aws_cloudwatch_log_group.quality_monitoring_logs.name
    ]
  }
}