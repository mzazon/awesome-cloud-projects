# outputs.tf - Output values for DynamoDB Global Tables infrastructure
# This file defines all output values that can be used by other Terraform
# configurations or for verification and integration purposes

# ===================================================================
# DynamoDB Table Outputs
# ===================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Global Table"
  value       = aws_dynamodb_table.global_table.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB Global Table"
  value       = aws_dynamodb_table.global_table.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB Global Table"
  value       = aws_dynamodb_table.global_table.id
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.global_table.stream_arn
}

output "dynamodb_table_stream_label" {
  description = "Label of the DynamoDB table stream"
  value       = aws_dynamodb_table.global_table.stream_label
}

output "dynamodb_table_billing_mode" {
  description = "Billing mode of the DynamoDB table"
  value       = aws_dynamodb_table.global_table.billing_mode
}

output "dynamodb_table_hash_key" {
  description = "Hash key of the DynamoDB table"
  value       = aws_dynamodb_table.global_table.hash_key
}

output "dynamodb_table_range_key" {
  description = "Range key of the DynamoDB table"
  value       = aws_dynamodb_table.global_table.range_key
}

output "dynamodb_table_replica_regions" {
  description = "List of regions where the DynamoDB table has replicas"
  value       = [var.primary_region, var.secondary_region, var.tertiary_region]
}

output "dynamodb_table_global_secondary_indexes" {
  description = "List of Global Secondary Indexes"
  value = var.enable_email_gsi ? [
    {
      name            = var.email_gsi_name
      hash_key        = "Email"
      projection_type = "ALL"
    }
  ] : []
}

# ===================================================================
# KMS Key Outputs
# ===================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for DynamoDB encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.dynamodb_key[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for DynamoDB encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.dynamodb_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for DynamoDB encryption"
  value       = var.enable_kms_encryption ? aws_kms_alias.dynamodb_key_alias[0].name : null
}

# ===================================================================
# Lambda Function Outputs
# ===================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = local.lambda_function_name
}

output "lambda_function_arn_primary" {
  description = "ARN of the Lambda function in primary region"
  value       = aws_lambda_function.global_table_processor_primary.arn
}

output "lambda_function_arn_secondary" {
  description = "ARN of the Lambda function in secondary region"
  value       = aws_lambda_function.global_table_processor_secondary.arn
}

output "lambda_function_arn_tertiary" {
  description = "ARN of the Lambda function in tertiary region"
  value       = aws_lambda_function.global_table_processor_tertiary.arn
}

output "lambda_function_invoke_arn_primary" {
  description = "Invoke ARN of the Lambda function in primary region"
  value       = aws_lambda_function.global_table_processor_primary.invoke_arn
}

output "lambda_function_invoke_arn_secondary" {
  description = "Invoke ARN of the Lambda function in secondary region"
  value       = aws_lambda_function.global_table_processor_secondary.invoke_arn
}

output "lambda_function_invoke_arn_tertiary" {
  description = "Invoke ARN of the Lambda function in tertiary region"
  value       = aws_lambda_function.global_table_processor_tertiary.invoke_arn
}

output "lambda_function_runtime" {
  description = "Runtime of the Lambda functions"
  value       = var.lambda_runtime
}

output "lambda_function_timeout" {
  description = "Timeout of the Lambda functions"
  value       = var.lambda_timeout
}

output "lambda_function_memory_size" {
  description = "Memory size of the Lambda functions"
  value       = var.lambda_memory_size
}

# ===================================================================
# IAM Role Outputs
# ===================================================================

output "iam_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

# ===================================================================
# CloudWatch Monitoring Outputs
# ===================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.global_table_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.global_table_dashboard[0].dashboard_name}" : null
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created"
  value = var.enable_cloudwatch_alarms ? [
    {
      name        = aws_cloudwatch_metric_alarm.replication_latency[0].alarm_name
      metric_name = "ReplicationLatency"
      threshold   = var.replication_latency_threshold
    },
    {
      name        = aws_cloudwatch_metric_alarm.user_errors[0].alarm_name
      metric_name = "UserErrors"
      threshold   = var.user_errors_threshold
    }
  ] : []
}

# ===================================================================
# SNS Notification Outputs
# ===================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.cloudwatch_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.cloudwatch_notifications[0].name : null
}

# ===================================================================
# Configuration Outputs
# ===================================================================

output "regions" {
  description = "List of all regions used in the deployment"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    tertiary  = var.tertiary_region
  }
}

output "configuration_summary" {
  description = "Summary of the configuration used"
  value = {
    environment                    = var.environment
    project_name                  = var.project_name
    table_name                    = local.table_name
    billing_mode                  = var.billing_mode
    enable_point_in_time_recovery = var.enable_point_in_time_recovery
    enable_deletion_protection    = var.enable_deletion_protection
    enable_kms_encryption         = var.enable_kms_encryption
    enable_email_gsi              = var.enable_email_gsi
    enable_cloudwatch_alarms      = var.enable_cloudwatch_alarms
    enable_cloudwatch_dashboard   = var.enable_cloudwatch_dashboard
    enable_sns_notifications      = var.enable_sns_notifications
  }
}

# ===================================================================
# Testing and Verification Outputs
# ===================================================================

output "test_commands" {
  description = "AWS CLI commands for testing the Global Table"
  value = {
    # Test Lambda function in primary region
    test_lambda_primary = "aws lambda invoke --function-name ${local.lambda_function_name} --payload '{\"operation\":\"scan\"}' --region ${var.primary_region} /tmp/response.json && cat /tmp/response.json"
    
    # Test Lambda function in secondary region
    test_lambda_secondary = "aws lambda invoke --function-name ${local.lambda_function_name} --payload '{\"operation\":\"scan\"}' --region ${var.secondary_region} /tmp/response.json && cat /tmp/response.json"
    
    # Test Lambda function in tertiary region
    test_lambda_tertiary = "aws lambda invoke --function-name ${local.lambda_function_name} --payload '{\"operation\":\"scan\"}' --region ${var.tertiary_region} /tmp/response.json && cat /tmp/response.json"
    
    # Check table status
    check_table_status = "aws dynamodb describe-table --table-name ${local.table_name} --region ${var.primary_region} --query 'Table.{TableName:TableName,TableStatus:TableStatus,Replicas:Replicas[*].{Region:RegionName,Status:ReplicaStatus}}'"
    
    # Check replication metrics
    check_replication_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/DynamoDB --metric-name ReplicationLatency --dimensions Name=TableName,Value=${local.table_name} Name=ReceivingRegion,Value=${var.secondary_region} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average --region ${var.primary_region}"
    
    # Test cross-region write and read
    test_cross_region_write = "aws lambda invoke --function-name ${local.lambda_function_name} --payload '{\"operation\":\"put\",\"userId\":\"test-${random_password.suffix.result}\",\"name\":\"Cross Region Test\",\"email\":\"test@example.com\"}' --region ${var.primary_region} /tmp/write_response.json && sleep 5 && aws lambda invoke --function-name ${local.lambda_function_name} --payload '{\"operation\":\"get\",\"userId\":\"test-${random_password.suffix.result}\"}' --region ${var.secondary_region} /tmp/read_response.json && cat /tmp/read_response.json"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring the Global Table"
  value = {
    # DynamoDB console URLs for each region
    dynamodb_primary   = "https://${var.primary_region}.console.aws.amazon.com/dynamodbv2/home?region=${var.primary_region}#table?name=${local.table_name}"
    dynamodb_secondary = "https://${var.secondary_region}.console.aws.amazon.com/dynamodbv2/home?region=${var.secondary_region}#table?name=${local.table_name}"
    dynamodb_tertiary  = "https://${var.tertiary_region}.console.aws.amazon.com/dynamodbv2/home?region=${var.tertiary_region}#table?name=${local.table_name}"
    
    # CloudWatch console URLs
    cloudwatch_primary   = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#metricsV2:graph=~();search=DynamoDB;namespace=AWS/DynamoDB;dimensions=TableName"
    cloudwatch_secondary = "https://${var.secondary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.secondary_region}#metricsV2:graph=~();search=DynamoDB;namespace=AWS/DynamoDB;dimensions=TableName"
    cloudwatch_tertiary  = "https://${var.tertiary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.tertiary_region}#metricsV2:graph=~();search=DynamoDB;namespace=AWS/DynamoDB;dimensions=TableName"
  }
}

# ===================================================================
# Resource Identifiers for Integration
# ===================================================================

output "resource_identifiers" {
  description = "Resource identifiers for integration with other systems"
  value = {
    table_name        = local.table_name
    table_arn         = aws_dynamodb_table.global_table.arn
    lambda_role_arn   = aws_iam_role.lambda_role.arn
    random_suffix     = random_password.suffix.result
    
    # Resource tags for integration
    common_tags = local.common_tags
  }
}

# ===================================================================
# Cost Estimation Information
# ===================================================================

output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    billing_mode             = var.billing_mode
    regions_count           = length(local.regions)
    lambda_functions_count  = length(local.regions)
    cloudwatch_alarms_count = var.enable_cloudwatch_alarms ? 2 : 0
    kms_key_enabled        = var.enable_kms_encryption
    
    # Cost factors
    cost_factors = {
      dynamodb_storage     = "Pay per GB stored per month"
      dynamodb_requests    = var.billing_mode == "PAY_PER_REQUEST" ? "Pay per request" : "Provisioned capacity"
      replication_cost     = "Cross-region replication charges apply"
      lambda_invocations   = "Pay per invocation and duration"
      cloudwatch_metrics   = "Standard CloudWatch metrics pricing"
      kms_encryption       = var.enable_kms_encryption ? "KMS key usage charges" : "No additional KMS charges"
    }
  }
}

# ===================================================================
# Security Information
# ===================================================================

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    encryption_at_rest         = var.enable_kms_encryption ? "Enabled with KMS" : "Enabled with AWS managed keys"
    point_in_time_recovery     = var.enable_point_in_time_recovery
    deletion_protection        = var.enable_deletion_protection
    iam_role_least_privilege   = "Lambda functions use least privilege IAM policies"
    vpc_configuration          = "Lambda functions run in AWS managed VPC"
    
    # Security recommendations
    recommendations = [
      "Enable VPC endpoints for DynamoDB to keep traffic within AWS network",
      "Use AWS CloudTrail to monitor DynamoDB API calls",
      "Implement application-level encryption for sensitive data",
      "Use fine-grained access control with IAM policies",
      "Enable AWS Config to monitor configuration changes"
    ]
  }
}