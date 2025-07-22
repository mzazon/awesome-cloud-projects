# =============================================================================
# Outputs for Advanced Data Lake Governance Infrastructure
# =============================================================================
# This file defines all outputs that provide important information about
# the deployed infrastructure for integration, monitoring, and validation.

# =============================================================================
# DATA LAKE STORAGE OUTPUTS
# =============================================================================

output "data_lake_bucket_name" {
  description = "Name of the S3 bucket used for the data lake"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_lake_bucket_arn" {
  description = "ARN of the S3 bucket used for the data lake"
  value       = aws_s3_bucket.data_lake.arn
}

output "data_lake_bucket_domain_name" {
  description = "Bucket domain name for programmatic access"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "raw_data_path" {
  description = "S3 path for raw data zone"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/${var.raw_data_prefix}/"
}

output "curated_data_path" {
  description = "S3 path for curated data zone"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/${var.curated_data_prefix}/"
}

output "analytics_data_path" {
  description = "S3 path for analytics-ready data zone"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/${var.analytics_data_prefix}/"
}

# =============================================================================
# IAM ROLES AND PERMISSIONS OUTPUTS
# =============================================================================

output "lake_formation_service_role_arn" {
  description = "ARN of the Lake Formation service role for cross-service operations"
  value       = aws_iam_role.lake_formation_service_role.arn
}

output "lake_formation_service_role_name" {
  description = "Name of the Lake Formation service role"
  value       = aws_iam_role.lake_formation_service_role.name
}

output "data_analyst_role_arn" {
  description = "ARN of the data analyst role for restricted data access"
  value       = aws_iam_role.data_analyst_role.arn
}

output "data_analyst_role_name" {
  description = "Name of the data analyst role"
  value       = aws_iam_role.data_analyst_role.name
}

# =============================================================================
# LAKE FORMATION OUTPUTS
# =============================================================================

output "lake_formation_registered_location" {
  description = "S3 location registered with Lake Formation for governance"
  value       = aws_lakeformation_resource.data_lake.arn
}

output "lake_formation_data_lake_admins" {
  description = "List of Lake Formation administrators"
  value       = aws_lakeformation_data_lake_settings.main.admins
}

output "data_cells_filter_name" {
  description = "Name of the data cells filter for PII protection"
  value       = aws_lakeformation_data_cells_filter.customer_data_pii_filter.table_data[0].name
}

# =============================================================================
# GLUE DATA CATALOG OUTPUTS
# =============================================================================

output "glue_database_name" {
  description = "Name of the Glue database for the enterprise data catalog"
  value       = aws_glue_catalog_database.enterprise_data_catalog.name
}

output "glue_database_arn" {
  description = "ARN of the Glue database"
  value       = aws_glue_catalog_database.enterprise_data_catalog.arn
}

output "customer_data_table_name" {
  description = "Name of the customer data table in Glue catalog"
  value       = aws_glue_catalog_table.customer_data.name
}

output "transaction_data_table_name" {
  description = "Name of the transaction data table in Glue catalog"
  value       = aws_glue_catalog_table.transaction_data.name
}

output "customer_data_table_location" {
  description = "S3 location of the customer data table"
  value       = aws_glue_catalog_table.customer_data.storage_descriptor[0].location
}

output "transaction_data_table_location" {
  description = "S3 location of the transaction data table"
  value       = aws_glue_catalog_table.transaction_data.storage_descriptor[0].location
}

# =============================================================================
# GLUE ETL JOB OUTPUTS
# =============================================================================

output "etl_job_name" {
  description = "Name of the Glue ETL job for customer data processing"
  value       = aws_glue_job.customer_data_etl.name
}

output "etl_job_arn" {
  description = "ARN of the Glue ETL job"
  value       = aws_glue_job.customer_data_etl.arn
}

output "etl_script_location" {
  description = "S3 location of the ETL job script"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/scripts/customer_data_etl.py"
}

# =============================================================================
# AMAZON DATAZONE OUTPUTS
# =============================================================================

output "datazone_domain_id" {
  description = "ID of the Amazon DataZone domain"
  value       = aws_datazone_domain.enterprise_governance.id
}

output "datazone_domain_arn" {
  description = "ARN of the Amazon DataZone domain"
  value       = aws_datazone_domain.enterprise_governance.arn
}

output "datazone_domain_name" {
  description = "Name of the Amazon DataZone domain"
  value       = aws_datazone_domain.enterprise_governance.name
}

output "datazone_domain_portal_url" {
  description = "Portal URL for accessing the DataZone domain"
  value       = aws_datazone_domain.enterprise_governance.portal_url
}

output "business_glossary_id" {
  description = "ID of the business glossary in DataZone"
  value       = aws_datazone_glossary.enterprise_glossary.id
}

output "business_glossary_name" {
  description = "Name of the business glossary"
  value       = aws_datazone_glossary.enterprise_glossary.name
}

output "analytics_project_id" {
  description = "ID of the customer analytics project in DataZone"
  value       = aws_datazone_project.customer_analytics.id
}

output "analytics_project_name" {
  description = "Name of the customer analytics project"
  value       = aws_datazone_project.customer_analytics.name
}

# =============================================================================
# MONITORING AND ALERTING OUTPUTS
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for data quality monitoring"
  value       = aws_cloudwatch_log_group.data_quality.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.data_quality.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for data quality alerts"
  value       = aws_sns_topic.data_quality_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.data_quality_alerts.name
}

output "etl_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for ETL failures"
  value       = aws_cloudwatch_metric_alarm.etl_failures.alarm_name
}

output "etl_failure_alarm_arn" {
  description = "ARN of the ETL failure alarm"
  value       = aws_cloudwatch_metric_alarm.etl_failures.arn
}

# =============================================================================
# ATHENA QUERY EXAMPLES
# =============================================================================

output "sample_athena_queries" {
  description = "Sample Athena queries for testing data access and governance"
  value = {
    customer_segment_analysis = "SELECT customer_segment, COUNT(*) as customer_count FROM ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.customer_data.name} GROUP BY customer_segment"
    
    regional_customer_distribution = "SELECT region, customer_segment, COUNT(*) as customers, AVG(lifetime_value) as avg_clv FROM ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.customer_data.name} GROUP BY region, customer_segment"
    
    transaction_summary = "SELECT DATE_TRUNC('month', transaction_date) as month, COUNT(*) as transaction_count, SUM(amount) as total_amount FROM ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.transaction_data.name} GROUP BY DATE_TRUNC('month', transaction_date) ORDER BY month"
    
    customer_transaction_join = "SELECT c.customer_segment, c.region, COUNT(t.transaction_id) as transaction_count, AVG(t.amount) as avg_transaction_amount FROM ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.customer_data.name} c LEFT JOIN ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.transaction_data.name} t ON c.customer_id = t.customer_id GROUP BY c.customer_segment, c.region"
  }
}

# =============================================================================
# ACCESS COMMANDS AND INSTRUCTIONS
# =============================================================================

output "data_analyst_assume_role_command" {
  description = "AWS CLI command to assume the data analyst role for testing"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.data_analyst_role.arn} --role-session-name data-analysis-session"
}

output "athena_query_execution_command" {
  description = "Sample AWS CLI command to execute Athena queries"
  value       = "aws athena start-query-execution --query-string 'SELECT customer_segment, COUNT(*) FROM ${aws_glue_catalog_database.enterprise_data_catalog.name}.${aws_glue_catalog_table.customer_data.name} GROUP BY customer_segment' --result-configuration OutputLocation=s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
}

output "glue_job_run_command" {
  description = "AWS CLI command to run the ETL job"
  value       = "aws glue start-job-run --job-name ${aws_glue_job.customer_data_etl.name}"
}

# =============================================================================
# VALIDATION AND TESTING OUTPUTS
# =============================================================================

output "lake_formation_permissions_check" {
  description = "Command to check Lake Formation permissions"
  value       = "aws lakeformation list-permissions --resource '{\"Database\":{\"Name\":\"${aws_glue_catalog_database.enterprise_data_catalog.name}\"}}'"
}

output "data_cells_filter_check" {
  description = "Command to list data cells filters"
  value       = "aws lakeformation list-data-cells-filter --table '{\"CatalogId\":\"${data.aws_caller_identity.current.account_id}\",\"DatabaseName\":\"${aws_glue_catalog_database.enterprise_data_catalog.name}\",\"Name\":\"${aws_glue_catalog_table.customer_data.name}\"}'"
}

output "s3_data_structure_check" {
  description = "Commands to verify S3 data structure"
  value = {
    list_raw_data     = "aws s3 ls s3://${aws_s3_bucket.data_lake.bucket}/${var.raw_data_prefix}/ --recursive"
    list_curated_data = "aws s3 ls s3://${aws_s3_bucket.data_lake.bucket}/${var.curated_data_prefix}/ --recursive"
    list_analytics_data = "aws s3 ls s3://${aws_s3_bucket.data_lake.bucket}/${var.analytics_data_prefix}/ --recursive"
  }
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    data_lake_bucket = "S3 bucket '${aws_s3_bucket.data_lake.bucket}' serves as the enterprise data lake with three zones: raw, curated, and analytics"
    
    lake_formation_governance = "Lake Formation provides fine-grained access control with data cell filters protecting PII in customer data"
    
    glue_data_catalog = "Glue database '${aws_glue_catalog_database.enterprise_data_catalog.name}' contains customer_data and transaction_data tables with comprehensive metadata"
    
    datazone_portal = "DataZone domain '${aws_datazone_domain.enterprise_governance.name}' enables business-friendly data discovery and collaboration"
    
    etl_pipeline = "Glue job '${aws_glue_job.customer_data_etl.name}' processes data with lineage tracking and quality validation"
    
    monitoring = "CloudWatch and SNS provide comprehensive monitoring and alerting for data quality and pipeline health"
  }
}

# =============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample data to the raw data zone: s3://${aws_s3_bucket.data_lake.bucket}/${var.raw_data_prefix}/",
    "2. Run the ETL job to process data: aws glue start-job-run --job-name ${aws_glue_job.customer_data_etl.name}",
    "3. Test data access using the data analyst role: aws sts assume-role --role-arn ${aws_iam_role.data_analyst_role.arn} --role-session-name test-session",
    "4. Verify PII protection by querying customer data through Athena",
    "5. Explore the DataZone portal at: ${aws_datazone_domain.enterprise_governance.portal_url}",
    "6. Configure email notifications by subscribing to SNS topic: ${aws_sns_topic.data_quality_alerts.arn}",
    "7. Monitor ETL job performance through CloudWatch logs and metrics",
    "8. Expand data governance by adding more tables and data sources"
  ]
}

# =============================================================================
# COST OPTIMIZATION RECOMMENDATIONS
# =============================================================================

output "cost_optimization_tips" {
  description = "Recommendations for optimizing costs"
  value = [
    "Enable S3 Intelligent Tiering for automatic storage class optimization",
    "Use Glue job bookmarks to process only new data in subsequent runs",
    "Schedule ETL jobs during off-peak hours to reduce compute costs",
    "Monitor Athena query costs and implement query result caching",
    "Review DataZone usage patterns and optimize project configurations",
    "Set up CloudWatch billing alarms to monitor unexpected cost increases"
  ]
}

# =============================================================================
# SECURITY RECOMMENDATIONS
# =============================================================================

output "security_best_practices" {
  description = "Security best practices for the deployed infrastructure"
  value = [
    "Regularly review Lake Formation permissions and access patterns",
    "Enable AWS CloudTrail for comprehensive audit logging",
    "Implement VPC endpoints for secure service communication",
    "Use AWS KMS for enhanced encryption of sensitive data",
    "Regular security assessments of data access patterns",
    "Implement least privilege access principles for all users",
    "Monitor for unusual data access patterns using AWS GuardDuty",
    "Regular backup and disaster recovery testing"
  ]
}