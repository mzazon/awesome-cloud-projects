# Healthcare Data Processing Pipelines Outputs
# This file defines outputs that provide important information about the deployed infrastructure

# HealthLake Data Store Information
output "healthlake_datastore_id" {
  description = "ID of the HealthLake FHIR data store"
  value       = aws_healthlake_fhir_datastore.main.datastore_id
}

output "healthlake_datastore_arn" {
  description = "ARN of the HealthLake FHIR data store"
  value       = aws_healthlake_fhir_datastore.main.arn
}

output "healthlake_datastore_endpoint" {
  description = "FHIR endpoint URL for the HealthLake data store"
  value       = aws_healthlake_fhir_datastore.main.endpoint
}

output "healthlake_datastore_status" {
  description = "Status of the HealthLake data store"
  value       = aws_healthlake_fhir_datastore.main.datastore_status
}

output "healthlake_datastore_name" {
  description = "Name of the HealthLake data store"
  value       = aws_healthlake_fhir_datastore.main.datastore_name
}

# S3 Bucket Information
output "input_bucket_name" {
  description = "Name of the S3 bucket for input healthcare data"
  value       = aws_s3_bucket.input.id
}

output "input_bucket_arn" {
  description = "ARN of the S3 input bucket"
  value       = aws_s3_bucket.input.arn
}

output "input_bucket_domain_name" {
  description = "Domain name of the S3 input bucket"
  value       = aws_s3_bucket.input.bucket_domain_name
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output analytics and logs"
  value       = aws_s3_bucket.output.id
}

output "output_bucket_arn" {
  description = "ARN of the S3 output bucket"
  value       = aws_s3_bucket.output.arn
}

output "output_bucket_domain_name" {
  description = "Domain name of the S3 output bucket"
  value       = aws_s3_bucket.output.bucket_domain_name
}

# Lambda Function Information
output "lambda_processor_function_name" {
  description = "Name of the Lambda processor function"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_processor_function_arn" {
  description = "ARN of the Lambda processor function"
  value       = aws_lambda_function.processor.arn
}

output "lambda_processor_invoke_arn" {
  description = "Invoke ARN of the Lambda processor function"
  value       = aws_lambda_function.processor.invoke_arn
}

output "lambda_analytics_function_name" {
  description = "Name of the Lambda analytics function"
  value       = aws_lambda_function.analytics.function_name
}

output "lambda_analytics_function_arn" {
  description = "ARN of the Lambda analytics function"
  value       = aws_lambda_function.analytics.arn
}

output "lambda_analytics_invoke_arn" {
  description = "Invoke ARN of the Lambda analytics function"
  value       = aws_lambda_function.analytics.invoke_arn
}

# IAM Role Information
output "healthlake_service_role_arn" {
  description = "ARN of the HealthLake service role"
  value       = aws_iam_role.healthlake_service_role.arn
}

output "healthlake_service_role_name" {
  description = "Name of the HealthLake service role"
  value       = aws_iam_role.healthlake_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# EventBridge Rules Information
output "eventbridge_processor_rule_arn" {
  description = "ARN of the EventBridge processor rule"
  value       = aws_cloudwatch_event_rule.healthlake_processor.arn
}

output "eventbridge_processor_rule_name" {
  description = "Name of the EventBridge processor rule"
  value       = aws_cloudwatch_event_rule.healthlake_processor.name
}

output "eventbridge_analytics_rule_arn" {
  description = "ARN of the EventBridge analytics rule"
  value       = aws_cloudwatch_event_rule.healthlake_analytics.arn
}

output "eventbridge_analytics_rule_name" {
  description = "Name of the EventBridge analytics rule"
  value       = aws_cloudwatch_event_rule.healthlake_analytics.name
}

# CloudWatch Log Groups
output "lambda_processor_log_group_name" {
  description = "Name of the CloudWatch log group for processor Lambda"
  value       = aws_cloudwatch_log_group.lambda_processor_logs.name
}

output "lambda_processor_log_group_arn" {
  description = "ARN of the CloudWatch log group for processor Lambda"
  value       = aws_cloudwatch_log_group.lambda_processor_logs.arn
}

output "lambda_analytics_log_group_name" {
  description = "Name of the CloudWatch log group for analytics Lambda"
  value       = aws_cloudwatch_log_group.lambda_analytics_logs.name
}

output "lambda_analytics_log_group_arn" {
  description = "ARN of the CloudWatch log group for analytics Lambda"
  value       = aws_cloudwatch_log_group.lambda_analytics_logs.arn
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Resource URLs and Connections
output "fhir_api_base_url" {
  description = "Base URL for FHIR API interactions"
  value       = "${aws_healthlake_fhir_datastore.main.endpoint}"
}

output "sample_patient_s3_uri" {
  description = "S3 URI of the sample patient data"
  value       = "s3://${aws_s3_bucket.input.id}/${aws_s3_object.sample_patient_data.key}"
}

# Useful CLI Commands
output "import_job_command" {
  description = "AWS CLI command to start a FHIR import job"
  value = "aws healthlake start-fhir-import-job --input-data-config S3Uri=s3://${aws_s3_bucket.input.id}/fhir-data/ --output-data-config S3Uri=s3://${aws_s3_bucket.output.id}/import-logs/ --datastore-id ${aws_healthlake_fhir_datastore.main.datastore_id} --data-access-role-arn ${aws_iam_role.healthlake_service_role.arn}"
}

output "export_job_command" {
  description = "AWS CLI command to start a FHIR export job"
  value = "aws healthlake start-fhir-export-job --output-data-config S3Uri=s3://${aws_s3_bucket.output.id}/export-data/ --datastore-id ${aws_healthlake_fhir_datastore.main.datastore_id} --data-access-role-arn ${aws_iam_role.healthlake_service_role.arn}"
}

output "patient_search_command" {
  description = "CURL command to search for patients via FHIR API"
  value = "curl -X GET '${aws_healthlake_fhir_datastore.main.endpoint}Patient' -H 'Authorization: Bearer YOUR_TOKEN' -H 'Content-Type: application/fhir+json'"
}

# Configuration Summary
output "infrastructure_summary" {
  description = "Summary of the deployed healthcare infrastructure"
  value = {
    project_name           = var.project_name
    environment           = var.environment
    region                = data.aws_region.current.name
    datastore_name        = aws_healthlake_fhir_datastore.main.datastore_name
    fhir_version          = var.fhir_version
    input_bucket          = aws_s3_bucket.input.id
    output_bucket         = aws_s3_bucket.output.id
    processor_function    = aws_lambda_function.processor.function_name
    analytics_function    = aws_lambda_function.analytics.function_name
    eventbridge_rules     = [
      aws_cloudwatch_event_rule.healthlake_processor.name,
      aws_cloudwatch_event_rule.healthlake_analytics.name
    ]
    compliance_level      = var.compliance_level
    data_classification   = var.data_classification
  }
}

# Cost Tracking
output "resource_tags" {
  description = "Common tags applied to all resources for cost tracking"
  value = {
    Project             = var.project_name
    Environment         = var.environment
    ManagedBy          = "terraform"
    Recipe             = "healthcare-data-processing-pipelines-healthlake"
    CostCenter         = var.cost_center
    ComplianceLevel    = var.compliance_level
    DataClassification = var.data_classification
  }
}

# Security Information
output "security_considerations" {
  description = "Important security information for the deployment"
  value = {
    encryption_at_rest     = "Enabled (S3 AES256, HealthLake managed)"
    encryption_in_transit  = "Enabled (HTTPS/TLS)"
    access_control        = "IAM roles with least privilege"
    audit_logging         = var.enable_cloudtrail_logging ? "Enabled" : "Disabled"
    compliance_framework  = var.compliance_level
    vpc_isolation        = var.enable_vpc_configuration ? "Enabled" : "Disabled"
  }
}

# Monitoring Information
output "monitoring_resources" {
  description = "CloudWatch resources for monitoring the pipeline"
  value = {
    log_groups = [
      aws_cloudwatch_log_group.lambda_processor_logs.name,
      aws_cloudwatch_log_group.lambda_analytics_logs.name
    ]
    log_retention_days = var.log_retention_days
    xray_tracing      = var.enable_xray_tracing ? "Enabled" : "Disabled"
  }
}