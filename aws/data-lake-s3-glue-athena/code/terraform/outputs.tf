# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "data_lake_bucket_name" {
  description = "Name of the main data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.id
}

output "data_lake_bucket_arn" {
  description = "ARN of the main data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.arn
}

output "data_lake_bucket_domain_name" {
  description = "Domain name of the main data lake S3 bucket"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "athena_results_bucket_name" {
  description = "Name of the Athena query results S3 bucket"
  value       = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query results S3 bucket"
  value       = aws_s3_bucket.athena_results.arn
}

# ============================================================================
# GLUE OUTPUTS
# ============================================================================

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.data_lake_db.name
}

output "glue_database_arn" {
  description = "ARN of the Glue catalog database"
  value       = aws_glue_catalog_database.data_lake_db.arn
}

output "glue_service_role_arn" {
  description = "ARN of the Glue service IAM role"
  value       = aws_iam_role.glue_service_role.arn
}

output "glue_service_role_name" {
  description = "Name of the Glue service IAM role"
  value       = aws_iam_role.glue_service_role.name
}

output "sales_data_crawler_name" {
  description = "Name of the sales data Glue crawler"
  value       = aws_glue_crawler.sales_data_crawler.name
}

output "web_logs_crawler_name" {
  description = "Name of the web logs Glue crawler"
  value       = aws_glue_crawler.web_logs_crawler.name
}

output "sales_data_etl_job_name" {
  description = "Name of the sales data ETL job"
  value       = aws_glue_job.sales_data_etl.name
}

output "sales_data_etl_job_arn" {
  description = "ARN of the sales data ETL job"
  value       = aws_glue_job.sales_data_etl.arn
}

# ============================================================================
# ATHENA OUTPUTS
# ============================================================================

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.data_lake_workgroup.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.data_lake_workgroup.arn
}

output "athena_query_results_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
}

# ============================================================================
# RESOURCE IDENTIFIERS
# ============================================================================

output "unique_suffix" {
  description = "Unique suffix used for resource names"
  value       = local.unique_suffix
}

output "resource_prefix" {
  description = "Common prefix used for resource names"
  value       = local.name_prefix
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "glue_job_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for Glue job failures"
  value       = aws_cloudwatch_metric_alarm.glue_job_failure.alarm_name
}

output "athena_high_cost_alarm_name" {
  description = "Name of the CloudWatch alarm for high Athena query costs"
  value       = aws_cloudwatch_metric_alarm.athena_high_cost.alarm_name
}

# ============================================================================
# SAMPLE DATA LOCATIONS
# ============================================================================

output "sample_sales_data_location" {
  description = "S3 location of sample sales data"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/${aws_s3_object.sample_sales_data.key}"
}

output "sample_web_logs_location" {
  description = "S3 location of sample web logs data"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/${aws_s3_object.sample_web_logs.key}"
}

# ============================================================================
# USAGE INSTRUCTIONS
# ============================================================================

output "next_steps" {
  description = "Next steps to complete the data lake setup"
  value = <<EOF
Data Lake Infrastructure Deployed Successfully!

Next steps to complete your data lake setup:

1. Run Glue Crawlers to discover schema:
   aws glue start-crawler --name "${aws_glue_crawler.sales_data_crawler.name}"
   aws glue start-crawler --name "${aws_glue_crawler.web_logs_crawler.name}"

2. Wait for crawlers to complete (check status):
   aws glue get-crawler --name "${aws_glue_crawler.sales_data_crawler.name}" --query 'Crawler.State'
   aws glue get-crawler --name "${aws_glue_crawler.web_logs_crawler.name}" --query 'Crawler.State'

3. Verify tables were created in Glue Data Catalog:
   aws glue get-tables --database-name "${aws_glue_catalog_database.data_lake_db.name}"

4. Run sample Athena queries:
   aws athena start-query-execution --query-string "SELECT * FROM ${aws_glue_catalog_database.data_lake_db.name}.sales_data LIMIT 10;" --work-group "${aws_athena_workgroup.data_lake_workgroup.name}"

5. Monitor costs and performance:
   - Check CloudWatch metrics for Glue jobs and Athena queries
   - Review S3 storage costs and lifecycle policies
   - Monitor query performance and optimization opportunities

6. Scale your data lake:
   - Add more data sources by creating additional crawlers
   - Implement data quality checks in ETL jobs
   - Set up automated workflows using AWS Step Functions
   - Integrate with BI tools like Amazon QuickSight

For more information, refer to the AWS Data Lake best practices documentation.
EOF
}

# ============================================================================
# ESTIMATED COSTS
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the data lake infrastructure"
  value = <<EOF
Estimated Monthly Costs (USD):

S3 Storage:
- Standard Storage (first 50 TB): ~$23/TB/month
- Intelligent Tiering: ~$0.0125/1000 objects/month
- Lifecycle transitions: ~$0.01/1000 requests

Glue:
- Data Catalog: First 1M objects stored/month free, then $1/100k objects
- Crawlers: $0.44/hour (billed per second with 10-minute minimum)
- ETL Jobs: $0.44/hour (billed per second with 10-minute minimum)

Athena:
- Query Processing: $5/TB of data scanned
- No charge for DDL statements or failed queries

CloudWatch:
- Metrics: $0.30/metric/month for custom metrics
- Alarms: $0.10/alarm/month

Total estimated cost for moderate usage: $20-50/month
Actual costs depend on data volume, query frequency, and processing requirements.

Cost optimization tips:
- Use partitioning to reduce data scanned by Athena
- Compress data and use columnar formats like Parquet
- Implement lifecycle policies to move data to cheaper storage classes
- Monitor and optimize Glue job performance
EOF
}

# ============================================================================
# SECURITY RECOMMENDATIONS
# ============================================================================

output "security_recommendations" {
  description = "Security recommendations for the data lake"
  value = <<EOF
Security Recommendations:

1. Data Encryption:
   - All S3 buckets are encrypted at rest
   - Consider using AWS KMS for additional key management
   - Enable encryption in transit for all data transfers

2. Access Control:
   - Implement least privilege access principles
   - Use IAM roles instead of users for service access
   - Enable CloudTrail for audit logging

3. Network Security:
   - Consider using VPC endpoints for S3 access
   - Implement network ACLs and security groups
   - Use AWS PrivateLink for secure service communication

4. Data Governance:
   - Implement data classification and tagging
   - Use AWS Lake Formation for fine-grained access control
   - Set up data lineage and metadata management

5. Monitoring and Alerting:
   - Enable CloudWatch monitoring for all services
   - Set up alerts for unusual access patterns
   - Monitor costs and usage patterns

6. Backup and Disaster Recovery:
   - Enable cross-region replication for critical data
   - Implement backup strategies for metadata
   - Test disaster recovery procedures regularly

For more detailed security guidance, refer to the AWS Security Best Practices documentation.
EOF
}