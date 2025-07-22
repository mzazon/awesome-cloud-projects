output "s3_bucket_name" {
  description = "Name of the S3 bucket for fraud detection data"
  value       = aws_s3_bucket.fraud_detection.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for fraud detection data"
  value       = aws_s3_bucket.fraud_detection.arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis stream for transaction processing"
  value       = aws_kinesis_stream.fraud_transactions.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream for transaction processing"
  value       = aws_kinesis_stream.fraud_transactions.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for fraud decisions"
  value       = aws_dynamodb_table.fraud_decisions.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for fraud decisions"
  value       = aws_dynamodb_table.fraud_decisions.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for fraud alerts"
  value       = aws_sns_topic.fraud_alerts.arn
}

output "fraud_detector_role_arn" {
  description = "ARN of the IAM role for Amazon Fraud Detector"
  value       = aws_iam_role.fraud_detector_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

output "event_enrichment_lambda_function_name" {
  description = "Name of the event enrichment Lambda function"
  value       = aws_lambda_function.event_enrichment.function_name
}

output "event_enrichment_lambda_function_arn" {
  description = "ARN of the event enrichment Lambda function"
  value       = aws_lambda_function.event_enrichment.arn
}

output "fraud_processor_lambda_function_name" {
  description = "Name of the fraud detection processor Lambda function"
  value       = aws_lambda_function.fraud_processor.function_name
}

output "fraud_processor_lambda_function_arn" {
  description = "ARN of the fraud detection processor Lambda function"
  value       = aws_lambda_function.fraud_processor.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for fraud detection monitoring"
  value       = var.enable_enhanced_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fraud_detection[0].dashboard_name}" : null
}

output "fraud_detector_config" {
  description = "Configuration values for manual Amazon Fraud Detector setup"
  value = {
    entity_type_name        = "${var.project_name}-entity-type-${random_string.suffix.result}"
    event_type_name         = "${var.project_name}-event-type-${random_string.suffix.result}"
    model_name              = "${var.project_name}-model-${random_string.suffix.result}"
    detector_name           = "${var.project_name}-detector-${random_string.suffix.result}"
    s3_bucket               = aws_s3_bucket.fraud_detection.bucket
    training_data_path      = var.fraud_model_training_data_path
    fraud_detector_role_arn = aws_iam_role.fraud_detector_role.arn
  }
}

output "resource_identifiers" {
  description = "Unique identifiers for all created resources"
  value = {
    suffix                = random_string.suffix.result
    s3_bucket            = aws_s3_bucket.fraud_detection.bucket
    kinesis_stream       = aws_kinesis_stream.fraud_transactions.name
    dynamodb_table       = aws_dynamodb_table.fraud_decisions.name
    sns_topic            = aws_sns_topic.fraud_alerts.name
    lambda_enrichment    = aws_lambda_function.event_enrichment.function_name
    lambda_processor     = aws_lambda_function.fraud_processor.function_name
    fraud_detector_role  = aws_iam_role.fraud_detector_role.name
    lambda_role          = aws_iam_role.lambda_role.name
  }
}

output "next_steps" {
  description = "Next steps for completing the fraud detection setup"
  value = {
    step_1 = "Upload training data to S3 bucket: ${aws_s3_bucket.fraud_detection.bucket}/${var.fraud_model_training_data_path}"
    step_2 = "Create Amazon Fraud Detector entity type: ${var.project_name}-entity-type-${random_string.suffix.result}"
    step_3 = "Create Amazon Fraud Detector event type: ${var.project_name}-event-type-${random_string.suffix.result}"
    step_4 = "Create and train Transaction Fraud Insights model: ${var.project_name}-model-${random_string.suffix.result}"
    step_5 = "Create fraud detection rules and outcomes"
    step_6 = "Create and activate detector: ${var.project_name}-detector-${random_string.suffix.result}"
    step_7 = "Test the fraud detection pipeline by sending sample transactions to Kinesis stream"
    step_8 = "Configure email subscription for SNS topic: ${aws_sns_topic.fraud_alerts.arn}"
  }
}

output "aws_cli_commands" {
  description = "AWS CLI commands for manual fraud detector setup"
  value = {
    create_entity_type = "aws frauddetector create-entity-type --name ${var.project_name}-entity-type-${random_string.suffix.result} --description 'Customer entity for fraud detection'"
    create_event_type = "aws frauddetector create-event-type --name ${var.project_name}-event-type-${random_string.suffix.result} --description 'Transaction event type for fraud detection' --entity-types ${var.project_name}-entity-type-${random_string.suffix.result}"
    create_model = "aws frauddetector create-model --model-id ${var.project_name}-model-${random_string.suffix.result} --model-type TRANSACTION_FRAUD_INSIGHTS --event-type-name ${var.project_name}-event-type-${random_string.suffix.result}"
    create_detector = "aws frauddetector create-detector --detector-id ${var.project_name}-detector-${random_string.suffix.result} --event-type-name ${var.project_name}-event-type-${random_string.suffix.result}"
  }
}

output "monitoring_and_alerting" {
  description = "Monitoring and alerting resources"
  value = {
    cloudwatch_dashboard = var.enable_enhanced_monitoring ? aws_cloudwatch_dashboard.fraud_detection[0].dashboard_name : null
    sns_topic_arn       = aws_sns_topic.fraud_alerts.arn
    log_groups = {
      event_enrichment = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.event_enrichment_logs[0].name : null
      fraud_processor  = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.fraud_processor_logs[0].name : null
    }
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    kinesis_shards = "Monitor Kinesis stream utilization and adjust shard count based on actual throughput requirements"
    dynamodb_capacity = "Consider switching to on-demand billing for DynamoDB if usage is unpredictable"
    lambda_memory = "Monitor Lambda function memory usage and adjust memory allocation to optimize cost and performance"
    log_retention = "Adjust CloudWatch log retention period based on compliance requirements"
    sns_filtering = "Use SNS message filtering to reduce unnecessary notifications and costs"
  }
}