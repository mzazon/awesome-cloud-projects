# Output values for the Advanced DynamoDB Streaming with Global Tables deployment
# These outputs provide important information about the created resources

# ========================================
# Resource Names and Identifiers
# ========================================

output "table_name" {
  description = "Name of the DynamoDB Global Table"
  value       = local.table_name
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Streams"
  value       = local.kinesis_stream_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_password.suffix.result
}

# ========================================
# DynamoDB Resources
# ========================================

output "dynamodb_table_arns" {
  description = "ARNs of the DynamoDB tables in all regions"
  value = {
    primary   = aws_dynamodb_table.primary.arn
    secondary = aws_dynamodb_table.secondary.arn
    tertiary  = aws_dynamodb_table.tertiary.arn
  }
}

output "dynamodb_stream_arns" {
  description = "ARNs of the DynamoDB Streams in all regions"
  value = {
    primary   = aws_dynamodb_table.primary.stream_arn
    secondary = aws_dynamodb_table.secondary.stream_arn
    tertiary  = aws_dynamodb_table.tertiary.stream_arn
  }
}

output "global_table_status" {
  description = "Global table configuration details"
  value = {
    name = aws_dynamodb_global_table.ecommerce_global.name
    regions = [
      var.primary_region,
      var.secondary_region,
      var.tertiary_region
    ]
  }
}

# ========================================
# Kinesis Resources
# ========================================

output "kinesis_stream_arns" {
  description = "ARNs of the Kinesis Data Streams in all regions"
  value = {
    primary   = aws_kinesis_stream.primary.arn
    secondary = aws_kinesis_stream.secondary.arn
    tertiary  = aws_kinesis_stream.tertiary.arn
  }
}

output "kinesis_stream_shards" {
  description = "Number of shards for each Kinesis Data Stream"
  value = {
    primary   = aws_kinesis_stream.primary.shard_count
    secondary = aws_kinesis_stream.secondary.shard_count
    tertiary  = aws_kinesis_stream.tertiary.shard_count
  }
}

output "kinesis_streaming_destination" {
  description = "Kinesis Data Streams integration status"
  value = {
    table_name = aws_dynamodb_kinesis_streaming_destination.primary.table_name
    stream_arn = aws_dynamodb_kinesis_streaming_destination.primary.stream_arn
    region     = var.primary_region
  }
}

# ========================================
# Lambda Functions
# ========================================

output "stream_processor_functions" {
  description = "DynamoDB Stream processor Lambda function details"
  value = {
    primary = {
      function_name = aws_lambda_function.stream_processor_primary.function_name
      arn          = aws_lambda_function.stream_processor_primary.arn
      region       = var.primary_region
    }
    secondary = {
      function_name = aws_lambda_function.stream_processor_secondary.function_name
      arn          = aws_lambda_function.stream_processor_secondary.arn
      region       = var.secondary_region
    }
    tertiary = {
      function_name = aws_lambda_function.stream_processor_tertiary.function_name
      arn          = aws_lambda_function.stream_processor_tertiary.arn
      region       = var.tertiary_region
    }
  }
}

output "kinesis_processor_functions" {
  description = "Kinesis Data Stream processor Lambda function details"
  value = {
    primary = {
      function_name = aws_lambda_function.kinesis_processor_primary.function_name
      arn          = aws_lambda_function.kinesis_processor_primary.arn
      region       = var.primary_region
    }
    secondary = {
      function_name = aws_lambda_function.kinesis_processor_secondary.function_name
      arn          = aws_lambda_function.kinesis_processor_secondary.arn
      region       = var.secondary_region
    }
    tertiary = {
      function_name = aws_lambda_function.kinesis_processor_tertiary.function_name
      arn          = aws_lambda_function.kinesis_processor_tertiary.arn
      region       = var.tertiary_region
    }
  }
}

# ========================================
# Event Source Mappings
# ========================================

output "dynamodb_event_source_mappings" {
  description = "DynamoDB Streams event source mapping UUIDs"
  value = {
    primary   = aws_lambda_event_source_mapping.dynamodb_stream_primary.uuid
    secondary = aws_lambda_event_source_mapping.dynamodb_stream_secondary.uuid
    tertiary  = aws_lambda_event_source_mapping.dynamodb_stream_tertiary.uuid
  }
}

output "kinesis_event_source_mappings" {
  description = "Kinesis Data Streams event source mapping UUIDs"
  value = {
    primary   = aws_lambda_event_source_mapping.kinesis_stream_primary.uuid
    secondary = aws_lambda_event_source_mapping.kinesis_stream_secondary.uuid
    tertiary  = aws_lambda_event_source_mapping.kinesis_stream_tertiary.uuid
  }
}

# ========================================
# Monitoring and Dashboard
# ========================================

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard details"
  value = {
    name = aws_cloudwatch_dashboard.global_monitoring.dashboard_name
    url  = "https://console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.global_monitoring.dashboard_name}"
  }
}

# ========================================
# Regional Information
# ========================================

output "deployment_regions" {
  description = "Regions where resources are deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    tertiary  = var.tertiary_region
  }
}

# ========================================
# Testing and Validation Information
# ========================================

output "testing_commands" {
  description = "Example commands for testing the deployment"
  value = {
    insert_test_product = "aws dynamodb put-item --region ${var.primary_region} --table-name ${local.table_name} --item '{\"PK\": {\"S\": \"PRODUCT#12345\"}, \"SK\": {\"S\": \"METADATA\"}, \"GSI1PK\": {\"S\": \"CATEGORY#Electronics\"}, \"GSI1SK\": {\"S\": \"PRODUCT#12345\"}, \"Name\": {\"S\": \"Test Product\"}, \"Price\": {\"N\": \"99.99\"}, \"Stock\": {\"N\": \"100\"}}'"
    
    check_replication = "aws dynamodb get-item --region ${var.secondary_region} --table-name ${local.table_name} --key '{\"PK\": {\"S\": \"PRODUCT#12345\"}, \"SK\": {\"S\": \"METADATA\"}}'"
    
    check_kinesis_records = "aws kinesis get-shard-iterator --region ${var.primary_region} --stream-name ${local.kinesis_stream_name} --shard-id shardId-000000000000 --shard-iterator-type LATEST"
    
    view_cloudwatch_logs = "aws logs describe-log-groups --region ${var.primary_region} --log-group-name-prefix /aws/lambda/${local.table_name}"
  }
}

# ========================================
# Cost and Resource Information
# ========================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployment (USD)"
  value = {
    note = "Costs vary based on usage patterns and data volume"
    components = {
      dynamodb_global_tables = "Pay-per-request pricing + cross-region replication charges"
      kinesis_data_streams   = "$0.015 per shard-hour × ${var.kinesis_shard_count} shards × 3 regions × 24 × 30 = ~$97/month (base cost)"
      lambda_functions       = "Pay-per-request based on invocations and duration"
      cloudwatch_dashboard   = "$3 per dashboard per month"
      data_transfer          = "Varies based on cross-region replication volume"
    }
    optimization_tips = [
      "Monitor DynamoDB consumption to right-size capacity",
      "Adjust Kinesis shard count based on throughput requirements",
      "Use Lambda reserved concurrency to control costs",
      "Enable detailed monitoring only when needed"
    ]
  }
}

# ========================================
# Next Steps and Documentation
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test Global Tables replication by inserting data in different regions",
    "2. Verify Lambda functions are processing DynamoDB and Kinesis streams",
    "3. Check CloudWatch dashboard for real-time metrics",
    "4. Configure EventBridge rules for business-specific event processing",
    "5. Set up CloudWatch alarms for operational monitoring",
    "6. Review and adjust Lambda function memory and timeout settings based on actual usage",
    "7. Implement proper error handling and dead letter queues for Lambda functions"
  ]
}

output "important_notes" {
  description = "Important notes about the deployment"
  value = [
    "Global Tables provide eventual consistency across regions (typically <1 second)",
    "DynamoDB Streams have a 24-hour retention period; Kinesis Data Streams have configurable retention up to 365 days",
    "Lambda functions are configured with basic error handling; implement robust error handling for production use",
    "Kinesis Data Streams integration is enabled only in the primary region for Global Tables",
    "Monitor costs carefully as Global Tables incur cross-region data transfer charges",
    "Use AWS Config and CloudTrail for compliance and auditing requirements"
  ]
}