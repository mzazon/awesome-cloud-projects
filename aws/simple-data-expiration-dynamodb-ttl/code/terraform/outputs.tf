# Output values for DynamoDB TTL infrastructure
# These outputs provide important information about the created resources

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table with TTL enabled"
  value       = aws_dynamodb_table.session_table.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.session_table.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.session_table.id
}

output "ttl_attribute_name" {
  description = "Name of the TTL attribute configured on the table"
  value       = var.ttl_attribute_name
}

output "ttl_enabled" {
  description = "Whether TTL is enabled on the table"
  value       = aws_dynamodb_table.session_table.ttl[0].enabled
}

output "table_billing_mode" {
  description = "Billing mode of the DynamoDB table"
  value       = aws_dynamodb_table.session_table.billing_mode
}

output "table_hash_key" {
  description = "Hash key (partition key) of the DynamoDB table"
  value       = aws_dynamodb_table.session_table.hash_key
}

output "table_range_key" {
  description = "Range key (sort key) of the DynamoDB table"
  value       = aws_dynamodb_table.session_table.range_key
}

output "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery is enabled"
  value       = aws_dynamodb_table.session_table.point_in_time_recovery[0].enabled
}

output "server_side_encryption_enabled" {
  description = "Whether server-side encryption is enabled"
  value       = aws_dynamodb_table.session_table.server_side_encryption[0].enabled
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for monitoring (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.dynamodb_logs[0].name : null
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for TTL monitoring (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.ttl_deletions[0].alarm_name : null
}

output "sample_data_created" {
  description = "Whether sample data items were created"
  value       = var.create_sample_data
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

# CLI Commands for testing and validation
output "cli_commands" {
  description = "Useful AWS CLI commands for testing the DynamoDB TTL configuration"
  value = {
    # Command to describe the TTL configuration
    describe_ttl = "aws dynamodb describe-time-to-live --table-name ${aws_dynamodb_table.session_table.name}"
    
    # Command to scan all items in the table
    scan_all_items = "aws dynamodb scan --table-name ${aws_dynamodb_table.session_table.name}"
    
    # Command to scan only non-expired items
    scan_active_items = "aws dynamodb scan --table-name ${aws_dynamodb_table.session_table.name} --filter-expression \"#ttl > :current_time\" --expression-attribute-names '{\"#ttl\": \"${var.ttl_attribute_name}\"}' --expression-attribute-values '{\": current_time\": {\"N\": \"'$(date +%s)'\"}}'"
    
    # Command to get item count
    get_item_count = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.session_table.name} --query 'Table.ItemCount'"
    
    # Command to get TTL metrics from CloudWatch
    get_ttl_metrics = "aws cloudwatch get-metric-statistics --namespace \"AWS/DynamoDB\" --metric-name \"TimeToLiveDeletedItemCount\" --dimensions Name=TableName,Value=${aws_dynamodb_table.session_table.name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --period 300 --statistics Sum"
  }
}

# Resource tags for reference
output "resource_tags" {
  description = "Tags applied to the DynamoDB table"
  value       = aws_dynamodb_table.session_table.tags
}

# Connection information for applications
output "connection_info" {
  description = "Information needed to connect to the DynamoDB table from applications"
  value = {
    table_name     = aws_dynamodb_table.session_table.name
    region         = data.aws_region.current.name
    hash_key       = aws_dynamodb_table.session_table.hash_key
    range_key      = aws_dynamodb_table.session_table.range_key
    ttl_attribute  = var.ttl_attribute_name
    billing_mode   = aws_dynamodb_table.session_table.billing_mode
  }
}

# Cost estimation information
output "estimated_costs" {
  description = "Estimated monthly costs for the DynamoDB table (approximate)"
  value = {
    note = "Costs depend on actual usage patterns and data volume"
    on_demand_info = "On-demand billing charges per read/write request unit consumed"
    provisioned_info = var.billing_mode == "PROVISIONED" ? "Monthly cost for ${var.read_capacity} RCU and ${var.write_capacity} WCU" : "Not applicable (using on-demand billing)"
    storage_info = "Storage charged per GB-month for actual data stored"
    ttl_benefit = "TTL deletions do not consume write capacity units, reducing costs"
  }
}