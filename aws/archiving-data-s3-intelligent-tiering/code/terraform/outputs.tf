# Output values for the sustainable data archiving solution

output "archive_bucket_name" {
  description = "Name of the main archive bucket with Intelligent-Tiering"
  value       = aws_s3_bucket.archive.bucket
}

output "archive_bucket_arn" {
  description = "ARN of the main archive bucket"
  value       = aws_s3_bucket.archive.arn
}

output "archive_bucket_domain_name" {
  description = "Domain name of the archive bucket"
  value       = aws_s3_bucket.archive.bucket_domain_name
}

output "analytics_bucket_name" {
  description = "Name of the analytics bucket for Storage Lens reports"
  value       = var.enable_storage_lens ? aws_s3_bucket.analytics[0].bucket : null
}

output "analytics_bucket_arn" {
  description = "ARN of the analytics bucket"
  value       = var.enable_storage_lens ? aws_s3_bucket.analytics[0].arn : null
}

output "intelligent_tiering_configurations" {
  description = "List of Intelligent-Tiering configuration IDs"
  value = concat(
    [aws_s3_bucket_intelligent_tiering_configuration.primary.name],
    var.enable_advanced_intelligent_tiering ? [aws_s3_bucket_intelligent_tiering_configuration.advanced[0].name] : []
  )
}

output "storage_lens_configuration_id" {
  description = "ID of the S3 Storage Lens configuration"
  value       = var.enable_storage_lens ? aws_s3control_storage_lens_configuration.sustainability[0].config_id : null
}

output "sustainability_monitor_function_name" {
  description = "Name of the Lambda function for sustainability monitoring"
  value       = var.enable_sustainability_monitoring ? aws_lambda_function.sustainability_monitor[0].function_name : null
}

output "sustainability_monitor_function_arn" {
  description = "ARN of the Lambda function for sustainability monitoring"
  value       = var.enable_sustainability_monitoring ? aws_lambda_function.sustainability_monitor[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for sustainability metrics"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.sustainability[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.sustainability[0].dashboard_name}" : null
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled monitoring"
  value       = var.enable_sustainability_monitoring ? aws_cloudwatch_event_rule.sustainability_daily_check[0].name : null
}

output "iam_role_arn" {
  description = "ARN of the IAM role for the sustainability monitoring Lambda"
  value       = var.enable_sustainability_monitoring ? aws_iam_role.sustainability_monitor[0].arn : null
}

output "lifecycle_policy_rules" {
  description = "List of lifecycle policy rule IDs"
  value       = [for rule in aws_s3_bucket_lifecycle_configuration.archive.rule : rule.id]
}

output "bucket_versioning_status" {
  description = "Versioning status of the archive bucket"
  value       = var.enable_versioning ? aws_s3_bucket_versioning.archive[0].versioning_configuration[0].status : "Disabled"
}

output "sample_objects" {
  description = "List of sample objects created for testing (if enabled)"
  value = var.enable_sample_data ? [
    aws_s3_object.sample_frequent[0].key,
    aws_s3_object.sample_archive[0].key,
    aws_s3_object.sample_long_term[0].key
  ] : []
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = local.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

output "cost_optimization_features" {
  description = "Summary of enabled cost optimization features"
  value = {
    intelligent_tiering_enabled         = true
    advanced_intelligent_tiering       = var.enable_advanced_intelligent_tiering
    lifecycle_policies_enabled         = true
    storage_lens_analytics_enabled     = var.enable_storage_lens
    sustainability_monitoring_enabled  = var.enable_sustainability_monitoring
    automated_cleanup_enabled         = true
  }
}

output "sustainability_metrics" {
  description = "CloudWatch namespace and metric names for sustainability tracking"
  value = var.enable_sustainability_monitoring ? {
    namespace = "SustainableArchive"
    metrics = [
      "TotalStorageGB",
      "EstimatedMonthlyCarbonKg",
      "CarbonReductionPercentage"
    ]
  } : null
}

output "deployment_summary" {
  description = "Summary of deployed infrastructure for sustainable data archiving"
  value = {
    archive_bucket               = aws_s3_bucket.archive.bucket
    analytics_bucket            = var.enable_storage_lens ? aws_s3_bucket.analytics[0].bucket : "Not enabled"
    intelligent_tiering_configs  = length(concat([aws_s3_bucket_intelligent_tiering_configuration.primary.name], var.enable_advanced_intelligent_tiering ? [aws_s3_bucket_intelligent_tiering_configuration.advanced[0].name] : []))
    lifecycle_rules             = length(aws_s3_bucket_lifecycle_configuration.archive.rule)
    monitoring_function         = var.enable_sustainability_monitoring ? aws_lambda_function.sustainability_monitor[0].function_name : "Not enabled"
    dashboard_created           = var.enable_cloudwatch_dashboard
    storage_lens_enabled        = var.enable_storage_lens
    versioning_enabled          = var.enable_versioning
    sample_data_created         = var.enable_sample_data
  }
}

# Instructions for accessing and using the deployed infrastructure
output "usage_instructions" {
  description = "Instructions for using the deployed sustainable archiving solution"
  value = {
    upload_data = "aws s3 cp your-file s3://${aws_s3_bucket.archive.bucket}/"
    monitor_tiering = "aws s3api list-objects-v2 --bucket ${aws_s3_bucket.archive.bucket} --query 'Contents[*].[Key,StorageClass,Size]' --output table"
    view_dashboard = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.sustainability[0].dashboard_name}" : "Dashboard not enabled"
    run_monitoring = var.enable_sustainability_monitoring ? "aws lambda invoke --function-name ${aws_lambda_function.sustainability_monitor[0].function_name} --payload '{}' response.json" : "Monitoring not enabled"
    check_storage_lens = var.enable_storage_lens ? "aws s3control get-storage-lens-configuration --account-id ${local.account_id} --config-id ${aws_s3control_storage_lens_configuration.sustainability[0].config_id}" : "Storage Lens not enabled"
  }
}