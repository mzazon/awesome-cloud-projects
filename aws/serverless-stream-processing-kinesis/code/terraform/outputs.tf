# Output Values for Real-time Data Processing Infrastructure
# These outputs provide important resource information for verification and integration

# ============================================================================
# KINESIS STREAM OUTPUTS
# ============================================================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.data_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.data_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis stream"
  value       = aws_kinesis_stream.data_stream.shard_count
}

output "kinesis_stream_retention_period" {
  description = "Data retention period of the Kinesis stream (in hours)"
  value       = aws_kinesis_stream.data_stream.retention_period
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.data_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.data_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.data_processor.invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of Lambda function"
  value       = aws_lambda_function.data_processor.version
}

output "lambda_function_runtime" {
  description = "Runtime of the Lambda function"
  value       = aws_lambda_function.data_processor.runtime
}

output "lambda_function_memory_size" {
  description = "Memory size of the Lambda function (in MB)"
  value       = aws_lambda_function.data_processor.memory_size
}

output "lambda_function_timeout" {
  description = "Timeout of the Lambda function (in seconds)"
  value       = aws_lambda_function.data_processor.timeout
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.processed_data.bucket_domain_name
}

output "s3_bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.processed_data.region
}

# ============================================================================
# EVENT SOURCE MAPPING OUTPUTS
# ============================================================================

output "event_source_mapping_uuid" {
  description = "UUID of the event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.uuid
}

output "event_source_mapping_state" {
  description = "State of the event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.state
}

output "event_source_mapping_batch_size" {
  description = "Batch size configured for the event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.batch_size
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "aws_cli_put_record_command" {
  description = "AWS CLI command to put a test record to the Kinesis stream"
  value = "aws kinesis put-record --stream-name ${aws_kinesis_stream.data_stream.name} --data '{\"test\": \"data\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}' --partition-key test-key"
}

output "aws_cli_describe_stream_command" {
  description = "AWS CLI command to describe the Kinesis stream"
  value = "aws kinesis describe-stream --stream-name ${aws_kinesis_stream.data_stream.name}"
}

output "aws_cli_list_s3_objects_command" {
  description = "AWS CLI command to list processed data in S3"
  value = "aws s3 ls s3://${aws_s3_bucket.processed_data.bucket}/processed-data/ --recursive"
}

output "aws_cli_lambda_logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '5 minutes ago' +%s)000"
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_lambda_metrics_url" {
  description = "URL to view Lambda metrics in CloudWatch console"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FLambda;search=${aws_lambda_function.data_processor.function_name}"
}

output "cloudwatch_kinesis_metrics_url" {
  description = "URL to view Kinesis metrics in CloudWatch console"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FKinesis;search=${aws_kinesis_stream.data_stream.name}"
}

# ============================================================================
# RESOURCE SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    kinesis_stream = {
      name        = aws_kinesis_stream.data_stream.name
      arn         = aws_kinesis_stream.data_stream.arn
      shard_count = aws_kinesis_stream.data_stream.shard_count
    }
    lambda_function = {
      name    = aws_lambda_function.data_processor.function_name
      arn     = aws_lambda_function.data_processor.arn
      runtime = aws_lambda_function.data_processor.runtime
    }
    s3_bucket = {
      name = aws_s3_bucket.processed_data.bucket
      arn  = aws_s3_bucket.processed_data.arn
    }
    iam_role = {
      name = aws_iam_role.lambda_execution_role.name
      arn  = aws_iam_role.lambda_execution_role.arn
    }
    event_source_mapping = {
      uuid       = aws_lambda_event_source_mapping.kinesis_lambda_mapping.uuid
      batch_size = aws_lambda_event_source_mapping.kinesis_lambda_mapping.batch_size
    }
  }
}