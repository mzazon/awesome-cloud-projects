# ==============================================================================
# S3 OUTPUTS
# ==============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for ETL data storage"
  value       = aws_s3_bucket.etl_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket created for ETL data storage"
  value       = aws_s3_bucket.etl_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.etl_bucket.bucket_domain_name
}

output "s3_raw_data_path" {
  description = "S3 path for raw data uploads"
  value       = "s3://${aws_s3_bucket.etl_bucket.bucket}/raw-data/"
}

output "s3_processed_data_path" {
  description = "S3 path where processed data will be stored"
  value       = "s3://${aws_s3_bucket.etl_bucket.bucket}/processed-data/"
}

output "s3_scripts_path" {
  description = "S3 path where ETL scripts are stored"
  value       = "s3://${aws_s3_bucket.etl_bucket.bucket}/scripts/"
}

# ==============================================================================
# AWS GLUE OUTPUTS
# ==============================================================================

output "glue_database_name" {
  description = "Name of the AWS Glue database"
  value       = aws_glue_catalog_database.etl_database.name
}

output "glue_database_arn" {
  description = "ARN of the AWS Glue database"
  value       = aws_glue_catalog_database.etl_database.arn
}

output "glue_job_name" {
  description = "Name of the AWS Glue ETL job"
  value       = aws_glue_job.etl_job.name
}

output "glue_job_arn" {
  description = "ARN of the AWS Glue ETL job"
  value       = aws_glue_job.etl_job.arn
}

output "glue_crawler_name" {
  description = "Name of the AWS Glue crawler"
  value       = aws_glue_crawler.etl_crawler.name
}

output "glue_crawler_arn" {
  description = "ARN of the AWS Glue crawler"
  value       = aws_glue_crawler.etl_crawler.arn
}

output "glue_workflow_name" {
  description = "Name of the AWS Glue workflow"
  value       = aws_glue_workflow.etl_workflow.name
}

output "glue_workflow_arn" {
  description = "ARN of the AWS Glue workflow"
  value       = aws_glue_workflow.etl_workflow.arn
}

output "glue_service_role_arn" {
  description = "ARN of the AWS Glue service role"
  value       = aws_iam_role.glue_service_role.arn
}

# ==============================================================================
# LAMBDA OUTPUTS
# ==============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda orchestrator function"
  value       = aws_lambda_function.etl_orchestrator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda orchestrator function"
  value       = aws_lambda_function.etl_orchestrator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.etl_orchestrator.invoke_arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ==============================================================================
# IAM OUTPUTS
# ==============================================================================

output "glue_s3_access_policy_arn" {
  description = "ARN of the custom S3 access policy for Glue"
  value       = aws_iam_policy.glue_s3_access_policy.arn
}

output "lambda_glue_access_policy_arn" {
  description = "ARN of the custom Glue access policy for Lambda"
  value       = aws_iam_policy.lambda_glue_access_policy.arn
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "glue_log_group_name" {
  description = "Name of the CloudWatch log group for Glue jobs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.glue_logs[0].name : null
}

# ==============================================================================
# WORKFLOW OUTPUTS
# ==============================================================================

output "workflow_trigger_name" {
  description = "Name of the scheduled workflow trigger"
  value       = var.enable_workflow_trigger ? aws_glue_trigger.scheduled_trigger[0].name : null
}

output "workflow_schedule" {
  description = "Schedule expression for the workflow trigger"
  value       = var.workflow_schedule
}

# ==============================================================================
# CONFIGURATION OUTPUTS
# ==============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ==============================================================================
# TESTING AND VALIDATION OUTPUTS
# ==============================================================================

output "test_lambda_command" {
  description = "AWS CLI command to test the Lambda function"
  value = "aws lambda invoke --function-name ${aws_lambda_function.etl_orchestrator.function_name} --payload '{\"job_name\":\"${aws_glue_job.etl_job.name}\",\"database_name\":\"${aws_glue_catalog_database.etl_database.name}\",\"output_path\":\"s3://${aws_s3_bucket.etl_bucket.bucket}/processed-data\"}' response.json"
}

output "start_crawler_command" {
  description = "AWS CLI command to start the Glue crawler"
  value       = "aws glue start-crawler --name ${aws_glue_crawler.etl_crawler.name}"
}

output "check_glue_job_status_command" {
  description = "AWS CLI command template to check Glue job status"
  value       = "aws glue get-job-runs --job-name ${aws_glue_job.etl_job.name} --max-results 1"
}

output "list_processed_data_command" {
  description = "AWS CLI command to list processed data files"
  value       = "aws s3 ls s3://${aws_s3_bucket.etl_bucket.bucket}/processed-data/ --recursive"
}

output "upload_sample_data_commands" {
  description = "Commands to upload additional sample data for testing"
  value = {
    sales_data = "aws s3 cp your_sales_data.csv s3://${aws_s3_bucket.etl_bucket.bucket}/raw-data/"
    customer_data = "aws s3 cp your_customer_data.csv s3://${aws_s3_bucket.etl_bucket.bucket}/raw-data/"
  }
}

# ==============================================================================
# ATHENA QUERY SETUP OUTPUTS
# ==============================================================================

output "athena_database_name" {
  description = "Database name to use for Athena queries"
  value       = aws_glue_catalog_database.etl_database.name
}

output "athena_query_result_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${aws_s3_bucket.etl_bucket.bucket}/athena-query-results/"
}

output "sample_athena_queries" {
  description = "Sample Athena queries to test processed data"
  value = {
    daily_sales = "SELECT * FROM ${aws_glue_catalog_database.etl_database.name}.daily_sales LIMIT 10;"
    customer_metrics = "SELECT * FROM ${aws_glue_catalog_database.etl_database.name}.customer_metrics LIMIT 10;"
    raw_sales = "SELECT * FROM ${aws_glue_catalog_database.etl_database.name}.raw_data_sales_data_csv LIMIT 10;"
  }
}

# ==============================================================================
# COST OPTIMIZATION OUTPUTS
# ==============================================================================

output "cost_optimization_notes" {
  description = "Notes about cost optimization for the ETL pipeline"
  value = {
    s3_lifecycle = "S3 lifecycle policies are ${var.s3_lifecycle_enabled ? "enabled" : "disabled"} - objects transition to IA after ${var.s3_transition_to_ia_days} days and to Glacier after ${var.s3_transition_to_glacier_days} days"
    glue_workers = "Glue job configured with ${var.glue_job_number_of_workers} ${var.glue_job_worker_type} workers - adjust based on data volume"
    lambda_memory = "Lambda function allocated ${var.lambda_memory_size}MB memory - optimize based on actual usage patterns"
    log_retention = "CloudWatch logs retained for ${var.log_retention_days} days - adjust based on compliance requirements"
  }
}

# ==============================================================================
# SECURITY OUTPUTS
# ==============================================================================

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    s3_encryption = "AES256 server-side encryption enabled"
    s3_public_access = "Public access blocked on S3 bucket"
    iam_least_privilege = "IAM roles follow least privilege principle"
    vpc_endpoints = "Consider adding VPC endpoints for enhanced security"
    kms_encryption = "Consider upgrading to KMS encryption for enhanced security"
  }
}