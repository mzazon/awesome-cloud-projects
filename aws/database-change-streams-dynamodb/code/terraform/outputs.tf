# Output values for DynamoDB Streams real-time processing infrastructure

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.user_activities.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.user_activities.arn
}

output "dynamodb_stream_arn" {
  description = "ARN of the DynamoDB stream"
  value       = aws_dynamodb_table.user_activities.stream_arn
}

output "dynamodb_stream_label" {
  description = "A timestamp, in ISO 8601 format, for this stream"
  value       = aws_dynamodb_table.user_activities.stream_label
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.stream_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.stream_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.stream_processor.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for audit logs"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for audit logs"
  value       = aws_s3_bucket.audit_logs.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.audit_logs.bucket_domain_name
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.notifications.arn
}

output "dlq_name" {
  description = "Name of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.name
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the Dead Letter Queue"
  value       = aws_sqs_queue.dlq.id
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "event_source_mapping_uuid" {
  description = "UUID of the event source mapping"
  value       = aws_lambda_event_source_mapping.dynamodb_stream.uuid
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs"
  value = {
    lambda_errors = {
      name = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
      arn  = aws_cloudwatch_metric_alarm.lambda_errors.arn
    }
    dlq_messages = {
      name = aws_cloudwatch_metric_alarm.dlq_messages.alarm_name
      arn  = aws_cloudwatch_metric_alarm.dlq_messages.arn
    }
    lambda_duration = {
      name = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
      arn  = aws_cloudwatch_metric_alarm.lambda_duration.arn
    }
    dynamodb_throttles = {
      name = aws_cloudwatch_metric_alarm.dynamodb_throttles.alarm_name
      arn  = aws_cloudwatch_metric_alarm.dynamodb_throttles.arn
    }
  }
}

# Useful commands for testing and validation
output "testing_commands" {
  description = "Useful commands for testing the infrastructure"
  value = {
    insert_test_record = "aws dynamodb put-item --table-name ${aws_dynamodb_table.user_activities.name} --item '{\"UserId\":{\"S\":\"test-user\"},\"ActivityId\":{\"S\":\"test-activity\"},\"ActivityType\":{\"S\":\"LOGIN\"},\"Timestamp\":{\"N\":\"${timestamp()}\"},\"IPAddress\":{\"S\":\"192.168.1.100\"}}'"
    
    check_lambda_logs = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '5 minutes ago' +%s)000 --filter-pattern 'Processing'"
    
    list_s3_audit_files = "aws s3 ls s3://${aws_s3_bucket.audit_logs.bucket}/audit-logs/ --recursive"
    
    check_dlq_messages = "aws sqs receive-message --queue-url ${aws_sqs_queue.dlq.id}"
    
    check_table_stream_status = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.user_activities.name} --query 'Table.StreamSpecification'"
  }
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name               = var.project_name
    environment               = var.environment
    table_name                = aws_dynamodb_table.user_activities.name
    stream_view_type          = var.stream_view_type
    lambda_runtime            = var.lambda_runtime
    lambda_memory_size        = var.lambda_memory_size
    lambda_timeout            = var.lambda_timeout
    batch_size                = var.batch_size
    maximum_retry_attempts    = var.maximum_retry_attempts
    parallelization_factor    = var.parallelization_factor
    s3_versioning_enabled     = var.enable_s3_versioning
    email_notifications       = var.enable_email_notifications
    notification_email        = var.enable_email_notifications ? var.notification_email : "Not configured"
    log_retention_days        = var.cloudwatch_log_retention_days
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for different usage levels"
  value = {
    low_usage = {
      description = "~1000 DynamoDB operations, ~100 Lambda invocations per day"
      estimated_cost = "$2-5 USD/month"
      breakdown = {
        dynamodb = "~$1.25 (5 RCU/WCU provisioned)"
        lambda = "~$0.20 (first 1M requests free)"
        s3 = "~$0.50 (first 5GB free tier)"
        sns = "~$0.20 (first 1000 notifications free)"
        cloudwatch = "~$2 (alarms and logs)"
      }
    }
    medium_usage = {
      description = "~10K DynamoDB operations, ~1K Lambda invocations per day"
      estimated_cost = "$8-15 USD/month"
      breakdown = {
        dynamodb = "~$1.25 (5 RCU/WCU provisioned)"
        lambda = "~$2 (additional invocations and compute)"
        s3 = "~$2 (storage and operations)"
        sns = "~$1 (notifications)"
        cloudwatch = "~$5 (logs and alarms)"
      }
    }
    high_usage = {
      description = "~100K DynamoDB operations, ~10K Lambda invocations per day"
      estimated_cost = "$25-50 USD/month"
      breakdown = {
        dynamodb = "~$10 (higher provisioned capacity needed)"
        lambda = "~$15 (compute and invocations)"
        s3 = "~$5 (increased storage)"
        sns = "~$2 (more notifications)"
        cloudwatch = "~$10 (extensive logging)"
      }
    }
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    dynamodb_encryption = "Server-side encryption enabled with AWS managed keys"
    dynamodb_pitr = "Point-in-time recovery enabled"
    s3_encryption = "Server-side encryption with AES256"
    s3_public_access = "Public access blocked"
    s3_versioning = var.enable_s3_versioning ? "Enabled" : "Disabled"
    sns_encryption = "Server-side encryption with AWS managed KMS key"
    sqs_encryption = "Server-side encryption with AWS managed KMS key"
    iam_principle = "Least privilege access with specific resource-based policies"
    vpc_isolation = "Not configured (Lambda runs in AWS managed VPC)"
  }
}