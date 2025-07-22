# Outputs for DynamoDB Global Tables Infrastructure
# This file defines all output values that provide information about the deployed resources
# and can be used for integration with other systems or for verification purposes

# -----------------------------------------------------------------------------
# DynamoDB Table Outputs
# -----------------------------------------------------------------------------

output "table_name" {
  description = "Name of the DynamoDB Global Table"
  value       = aws_dynamodb_table.primary_table.name
}

output "table_arn" {
  description = "ARN of the DynamoDB Global Table"
  value       = aws_dynamodb_table.primary_table.arn
}

output "table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.primary_table.stream_arn
}

output "table_stream_label" {
  description = "Label of the DynamoDB table stream"
  value       = aws_dynamodb_table.primary_table.stream_label
}

output "global_table_regions" {
  description = "List of regions where the Global Table is deployed"
  value = [
    var.primary_region,
    var.secondary_region,
    var.tertiary_region
  ]
}

output "global_secondary_index_name" {
  description = "Name of the Global Secondary Index"
  value       = "GSI1"
}

# -----------------------------------------------------------------------------
# Regional Information
# -----------------------------------------------------------------------------

output "primary_region" {
  description = "Primary AWS region for the Global Table"
  value       = var.primary_region
}

output "secondary_region" {
  description = "Secondary AWS region for the Global Table"
  value       = var.secondary_region
}

output "tertiary_region" {
  description = "Tertiary AWS region for the Global Table"
  value       = var.tertiary_region
}

# -----------------------------------------------------------------------------
# KMS Key Outputs
# -----------------------------------------------------------------------------

output "primary_kms_key_id" {
  description = "ID of the KMS key in primary region"
  value       = aws_kms_key.primary_key.key_id
}

output "primary_kms_key_arn" {
  description = "ARN of the KMS key in primary region"
  value       = aws_kms_key.primary_key.arn
}

output "secondary_kms_key_id" {
  description = "ID of the KMS key in secondary region"
  value       = aws_kms_key.secondary_key.key_id
}

output "secondary_kms_key_arn" {
  description = "ARN of the KMS key in secondary region"
  value       = aws_kms_key.secondary_key.arn
}

output "tertiary_kms_key_id" {
  description = "ID of the KMS key in tertiary region"
  value       = aws_kms_key.tertiary_key.key_id
}

output "tertiary_kms_key_arn" {
  description = "ARN of the KMS key in tertiary region"
  value       = aws_kms_key.tertiary_key.arn
}

output "kms_key_aliases" {
  description = "Map of KMS key aliases by region"
  value = {
    (var.primary_region)  = aws_kms_alias.primary_key_alias.name
    (var.secondary_region) = aws_kms_alias.secondary_key_alias.name
    (var.tertiary_region)  = aws_kms_alias.tertiary_key_alias.name
  }
}

# -----------------------------------------------------------------------------
# IAM Role Outputs
# -----------------------------------------------------------------------------

output "iam_role_name" {
  description = "Name of the IAM role for DynamoDB Global Tables access"
  value       = aws_iam_role.dynamodb_global_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for DynamoDB Global Tables access"
  value       = aws_iam_role.dynamodb_global_role.arn
}

output "iam_role_policy_name" {
  description = "Name of the IAM policy attached to the role"
  value       = aws_iam_role_policy.dynamodb_global_policy.name
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created for monitoring"
  value = var.enable_cloudwatch_alarms ? {
    read_throttles_primary = {
      name   = aws_cloudwatch_metric_alarm.read_throttles_primary[0].alarm_name
      region = var.primary_region
    }
    write_throttles_primary = {
      name   = aws_cloudwatch_metric_alarm.write_throttles_primary[0].alarm_name
      region = var.primary_region
    }
    replication_delay_secondary = {
      name   = aws_cloudwatch_metric_alarm.replication_delay_secondary[0].alarm_name
      region = var.secondary_region
    }
    replication_delay_tertiary = {
      name   = aws_cloudwatch_metric_alarm.replication_delay_tertiary[0].alarm_name
      region = var.tertiary_region
    }
  } : {}
}

output "monitoring_dashboard_url" {
  description = "URL to view DynamoDB metrics in CloudWatch console"
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=DynamoDB"
}

# -----------------------------------------------------------------------------
# Backup Configuration Outputs
# -----------------------------------------------------------------------------

output "backup_vault_name" {
  description = "Name of the backup vault"
  value       = var.enable_backup ? aws_backup_vault.dynamodb_backup_vault[0].name : null
}

output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = var.enable_backup ? aws_backup_vault.dynamodb_backup_vault[0].arn : null
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = var.enable_backup ? aws_backup_plan.dynamodb_backup_plan[0].id : null
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = var.enable_backup ? aws_backup_plan.dynamodb_backup_plan[0].arn : null
}

output "backup_schedule" {
  description = "Backup schedule configuration"
  value = var.enable_backup ? {
    schedule            = var.backup_schedule
    retention_days      = var.backup_retention_days
    start_window        = var.backup_start_window
    completion_window   = var.backup_completion_window
  } : null
}

# -----------------------------------------------------------------------------
# Lambda Function Outputs
# -----------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the Lambda function for testing"
  value       = var.enable_lambda_demo ? aws_lambda_function.global_table_test_with_code[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for testing"
  value       = var.enable_lambda_demo ? aws_lambda_function.global_table_test_with_code[0].arn : null
}

output "lambda_invoke_arn" {
  description = "ARN to invoke the Lambda function"
  value       = var.enable_lambda_demo ? aws_lambda_function.global_table_test_with_code[0].invoke_arn : null
}

# -----------------------------------------------------------------------------
# Auto Scaling Outputs
# -----------------------------------------------------------------------------

output "auto_scaling_configuration" {
  description = "Auto scaling configuration details"
  value = var.enable_auto_scaling ? {
    enabled           = true
    min_capacity      = var.auto_scaling_min_capacity
    max_capacity      = var.auto_scaling_max_capacity
    target_utilization = var.auto_scaling_target_utilization
    read_target_arn   = aws_appautoscaling_target.table_read_target[0].arn
    write_target_arn  = aws_appautoscaling_target.table_write_target[0].arn
  } : {
    enabled = false
  }
}

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------

output "dynamodb_endpoints" {
  description = "DynamoDB endpoints for each region"
  value = {
    (var.primary_region)  = "https://dynamodb.${var.primary_region}.amazonaws.com"
    (var.secondary_region) = "https://dynamodb.${var.secondary_region}.amazonaws.com"
    (var.tertiary_region)  = "https://dynamodb.${var.tertiary_region}.amazonaws.com"
  }
}

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for managing the Global Table"
  value = {
    describe_table = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region}"
    scan_table = "aws dynamodb scan --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region} --limit 10"
    describe_global_table = "aws dynamodb describe-global-table --global-table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region}"
    invoke_test_lambda = var.enable_lambda_demo ? "aws lambda invoke --function-name ${aws_lambda_function.global_table_test_with_code[0].function_name} --region ${var.primary_region} response.json" : null
  }
}

# -----------------------------------------------------------------------------
# Cost Optimization Information
# -----------------------------------------------------------------------------

output "capacity_configuration" {
  description = "Current capacity configuration for cost optimization"
  value = {
    table_read_capacity  = var.read_capacity
    table_write_capacity = var.write_capacity
    gsi_read_capacity    = var.gsi_read_capacity
    gsi_write_capacity   = var.gsi_write_capacity
    billing_mode         = "PROVISIONED"
    auto_scaling_enabled = var.enable_auto_scaling
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost components (prices may vary by region)"
  value = {
    note = "Costs vary by region and usage patterns. This is an estimate based on provisioned capacity."
    table_read_capacity_units  = var.read_capacity
    table_write_capacity_units = var.write_capacity
    gsi_read_capacity_units    = var.gsi_read_capacity
    gsi_write_capacity_units   = var.gsi_write_capacity
    regions                    = 3
    additional_costs = [
      "Cross-region data transfer",
      "Storage costs",
      "Backup storage",
      "KMS key usage",
      "Lambda execution (if enabled)"
    ]
  }
}

# -----------------------------------------------------------------------------
# Security Information
# -----------------------------------------------------------------------------

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    encryption_at_rest      = var.enable_server_side_encryption
    encryption_in_transit   = true
    kms_customer_managed    = var.enable_server_side_encryption
    point_in_time_recovery  = var.enable_point_in_time_recovery
    deletion_protection     = var.enable_deletion_protection
    iam_role_based_access   = true
    backup_encryption       = var.enable_backup
  }
}

# -----------------------------------------------------------------------------
# Validation Commands
# -----------------------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the Global Table deployment"
  value = {
    check_table_status = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region} --query 'Table.TableStatus'"
    check_global_table = "aws dynamodb describe-global-table --global-table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region}"
    test_replication = "aws dynamodb put-item --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region} --item '{\"PK\":{\"S\":\"TEST\"},\"SK\":{\"S\":\"VALIDATION\"},\"timestamp\":{\"S\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"},\"data\":{\"S\":\"Test replication\"}}'"
    verify_replication = "aws dynamodb get-item --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.secondary_region} --key '{\"PK\":{\"S\":\"TEST\"},\"SK\":{\"S\":\"VALIDATION\"}}'"
  }
}

# -----------------------------------------------------------------------------
# Cleanup Commands
# -----------------------------------------------------------------------------

output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    warning = "These commands will permanently delete resources. Use with extreme caution."
    terraform_destroy = "terraform destroy -auto-approve"
    manual_table_deletion = "aws dynamodb delete-table --table-name ${aws_dynamodb_table.primary_table.name} --region ${var.primary_region}"
  }
}

# -----------------------------------------------------------------------------
# Documentation Links
# -----------------------------------------------------------------------------

output "documentation_links" {
  description = "Useful documentation links"
  value = {
    dynamodb_global_tables = "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html"
    dynamodb_best_practices = "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html"
    dynamodb_encryption = "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/encryption.html"
    dynamodb_backup = "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/BackupRestore.html"
    dynamodb_monitoring = "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html"
    terraform_aws_provider = "https://registry.terraform.io/providers/hashicorp/aws/latest/docs"
  }
}

# -----------------------------------------------------------------------------
# Summary Output
# -----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of the deployed DynamoDB Global Tables infrastructure"
  value = {
    table_name = aws_dynamodb_table.primary_table.name
    regions = [
      var.primary_region,
      var.secondary_region,
      var.tertiary_region
    ]
    features_enabled = {
      global_tables            = true
      encryption_at_rest       = var.enable_server_side_encryption
      point_in_time_recovery   = var.enable_point_in_time_recovery
      deletion_protection      = var.enable_deletion_protection
      cloudwatch_monitoring    = var.enable_cloudwatch_alarms
      automated_backup         = var.enable_backup
      auto_scaling            = var.enable_auto_scaling
      lambda_demo_function    = var.enable_lambda_demo
    }
    next_steps = [
      "Test the Global Table by inserting data in one region and verifying replication",
      "Configure your application to use the appropriate regional endpoints",
      "Set up monitoring dashboards for operational visibility",
      "Review and adjust capacity settings based on actual usage patterns",
      "Implement application-level health checks for regional failover"
    ]
  }
}