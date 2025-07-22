# Outputs for AWS automated data ingestion pipelines infrastructure

# ========================================
# S3 Storage Outputs
# ========================================

output "data_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.bucket
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.arn
}

output "data_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

output "data_bucket_hosted_zone_id" {
  description = "Hosted zone ID of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.hosted_zone_id
}

output "data_bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.region
}

# ========================================
# OpenSearch Domain Outputs
# ========================================

output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.analytics_domain.domain_name
}

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.analytics_domain.arn
}

output "opensearch_domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.analytics_domain.domain_id
}

output "opensearch_endpoint" {
  description = "Domain-specific endpoint for the OpenSearch cluster"
  value       = aws_opensearch_domain.analytics_domain.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "Domain-specific endpoint for OpenSearch Dashboards"
  value       = aws_opensearch_domain.analytics_domain.dashboard_endpoint
}

output "opensearch_engine_version" {
  description = "OpenSearch engine version"
  value       = aws_opensearch_domain.analytics_domain.engine_version
}

# ========================================
# OpenSearch Ingestion Pipeline Outputs
# ========================================

output "ingestion_pipeline_name" {
  description = "Name of the OpenSearch Ingestion pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.pipeline_name
}

output "ingestion_pipeline_arn" {
  description = "ARN of the OpenSearch Ingestion pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.pipeline_arn
}

output "ingestion_pipeline_id" {
  description = "Unique identifier for the OpenSearch Ingestion pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.id
}

output "ingestion_pipeline_endpoints" {
  description = "List of ingestion endpoints for the pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.ingest_endpoint_urls
}

output "ingestion_pipeline_min_units" {
  description = "Minimum capacity units for the ingestion pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.min_units
}

output "ingestion_pipeline_max_units" {
  description = "Maximum capacity units for the ingestion pipeline"
  value       = aws_osis_pipeline.data_ingestion_pipeline.max_units
}

# ========================================
# EventBridge Scheduler Outputs
# ========================================

output "scheduler_group_name" {
  description = "Name of the EventBridge Scheduler schedule group"
  value       = var.enable_pipeline_scheduling ? aws_scheduler_schedule_group.pipeline_schedules[0].name : null
}

output "scheduler_group_arn" {
  description = "ARN of the EventBridge Scheduler schedule group"
  value       = var.enable_pipeline_scheduling ? aws_scheduler_schedule_group.pipeline_schedules[0].arn : null
}

output "pipeline_start_schedule_name" {
  description = "Name of the pipeline start schedule"
  value       = var.enable_pipeline_scheduling ? aws_scheduler_schedule.pipeline_start[0].name : null
}

output "pipeline_stop_schedule_name" {
  description = "Name of the pipeline stop schedule"
  value       = var.enable_pipeline_scheduling ? aws_scheduler_schedule.pipeline_stop[0].name : null
}

output "pipeline_start_schedule_expression" {
  description = "Schedule expression for pipeline start"
  value       = var.pipeline_start_schedule
}

output "pipeline_stop_schedule_expression" {
  description = "Schedule expression for pipeline stop"
  value       = var.pipeline_stop_schedule
}

# ========================================
# IAM Role Outputs
# ========================================

output "ingestion_role_name" {
  description = "Name of the IAM role for OpenSearch Ingestion"
  value       = aws_iam_role.opensearch_ingestion_role.name
}

output "ingestion_role_arn" {
  description = "ARN of the IAM role for OpenSearch Ingestion"
  value       = aws_iam_role.opensearch_ingestion_role.arn
}

output "scheduler_role_name" {
  description = "Name of the IAM role for EventBridge Scheduler"
  value       = var.enable_pipeline_scheduling ? aws_iam_role.scheduler_role[0].name : null
}

output "scheduler_role_arn" {
  description = "ARN of the IAM role for EventBridge Scheduler"
  value       = var.enable_pipeline_scheduling ? aws_iam_role.scheduler_role[0].arn : null
}

# ========================================
# CloudWatch Logging Outputs
# ========================================

output "opensearch_log_groups" {
  description = "Map of OpenSearch log types to CloudWatch log group names"
  value = var.enable_cloudwatch_logs ? {
    for log_type in var.log_types : log_type => aws_cloudwatch_log_group.opensearch_logs[log_type].name
  } : {}
}

output "pipeline_log_group_name" {
  description = "Name of the CloudWatch log group for the ingestion pipeline"
  value       = aws_cloudwatch_log_group.pipeline_logs.name
}

output "pipeline_log_group_arn" {
  description = "ARN of the CloudWatch log group for the ingestion pipeline"
  value       = aws_cloudwatch_log_group.pipeline_logs.arn
}

# ========================================
# Configuration and Connection Information
# ========================================

output "opensearch_dashboard_url" {
  description = "Complete URL for OpenSearch Dashboards access"
  value       = "https://${aws_opensearch_domain.analytics_domain.dashboard_endpoint}"
}

output "opensearch_domain_url" {
  description = "Complete URL for OpenSearch domain API access"
  value       = "https://${aws_opensearch_domain.analytics_domain.endpoint}"
}

output "data_upload_instructions" {
  description = "Instructions for uploading data to the S3 bucket"
  value = {
    bucket_name = aws_s3_bucket.data_bucket.bucket
    supported_prefixes = var.data_source_prefixes
    example_aws_cli_command = "aws s3 cp your-file.log s3://${aws_s3_bucket.data_bucket.bucket}/${var.data_source_prefixes[0]}$(date +%Y/%m/%d)/"
    example_paths = [
      for prefix in var.data_source_prefixes : "s3://${aws_s3_bucket.data_bucket.bucket}/${prefix}$(date +%Y/%m/%d)/"
    ]
  }
}

output "pipeline_status_check" {
  description = "AWS CLI command to check pipeline status"
  value       = "aws osis get-pipeline --pipeline-name ${aws_osis_pipeline.data_ingestion_pipeline.pipeline_name} --query 'Pipeline.Status' --output text"
}

output "opensearch_index_pattern" {
  description = "OpenSearch index pattern for viewing processed data"
  value       = replace(var.opensearch_index_template, "%{yyyy.MM.dd}", "*")
}

# ========================================
# Resource Summary
# ========================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_bucket = {
      name   = aws_s3_bucket.data_bucket.bucket
      region = aws_s3_bucket.data_bucket.region
    }
    opensearch_domain = {
      name     = aws_opensearch_domain.analytics_domain.domain_name
      endpoint = aws_opensearch_domain.analytics_domain.endpoint
      version  = aws_opensearch_domain.analytics_domain.engine_version
    }
    ingestion_pipeline = {
      name      = aws_osis_pipeline.data_ingestion_pipeline.pipeline_name
      min_units = aws_osis_pipeline.data_ingestion_pipeline.min_units
      max_units = aws_osis_pipeline.data_ingestion_pipeline.max_units
    }
    scheduling_enabled = var.enable_pipeline_scheduling
    start_schedule     = var.pipeline_start_schedule
    stop_schedule      = var.pipeline_stop_schedule
  }
}

# ========================================
# Cost Estimation Information
# ========================================

output "cost_estimation_info" {
  description = "Information for estimating operational costs"
  value = {
    opensearch_instance_type = var.opensearch_instance_type
    opensearch_instance_count = var.opensearch_instance_count
    opensearch_storage_gb = var.opensearch_ebs_volume_size
    opensearch_storage_type = var.opensearch_ebs_volume_type
    pipeline_min_icu = var.pipeline_min_units
    pipeline_max_icu = var.pipeline_max_units
    s3_lifecycle_days = var.s3_lifecycle_expiration_days
    log_retention_days = var.cloudwatch_log_retention_days
    note = "Actual costs depend on data volume, processing time, and AWS region pricing"
  }
}

# ========================================
# Next Steps and Usage Information
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample data to S3 bucket: ${aws_s3_bucket.data_bucket.bucket}",
    "2. Check pipeline status: aws osis get-pipeline --pipeline-name ${aws_osis_pipeline.data_ingestion_pipeline.pipeline_name}",
    "3. Access OpenSearch Dashboards: https://${aws_opensearch_domain.analytics_domain.dashboard_endpoint}",
    "4. Create index patterns in OpenSearch Dashboards: ${replace(var.opensearch_index_template, "%{yyyy.MM.dd}", "*")}",
    "5. Monitor logs in CloudWatch: /aws/osis/pipelines/${aws_osis_pipeline.data_ingestion_pipeline.pipeline_name}",
    "6. Verify scheduled pipeline operations in EventBridge Scheduler console"
  ]
}