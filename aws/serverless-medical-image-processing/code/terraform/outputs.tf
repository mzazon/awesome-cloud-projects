# Output values for medical image processing infrastructure

###########################################
# S3 Bucket Outputs
###########################################

output "input_bucket_name" {
  description = "Name of the S3 bucket for DICOM input files"
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for DICOM input files"
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for processed outputs"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for processed outputs"
  value       = aws_s3_bucket.output.arn
}

###########################################
# AWS HealthImaging Outputs
###########################################

output "datastore_id" {
  description = "ID of the AWS HealthImaging data store"
  value       = aws_medicalimaging_datastore.main.datastore_id
}

output "datastore_arn" {
  description = "ARN of the AWS HealthImaging data store"
  value       = aws_medicalimaging_datastore.main.datastore_arn
}

output "datastore_name" {
  description = "Name of the AWS HealthImaging data store"
  value       = aws_medicalimaging_datastore.main.datastore_name
}

###########################################
# Lambda Function Outputs
###########################################

output "start_import_function_name" {
  description = "Name of the Lambda function that starts DICOM import"
  value       = aws_lambda_function.start_import.function_name
}

output "start_import_function_arn" {
  description = "ARN of the Lambda function that starts DICOM import"
  value       = aws_lambda_function.start_import.arn
}

output "process_metadata_function_name" {
  description = "Name of the Lambda function that processes metadata"
  value       = aws_lambda_function.process_metadata.function_name
}

output "process_metadata_function_arn" {
  description = "ARN of the Lambda function that processes metadata"
  value       = aws_lambda_function.process_metadata.arn
}

output "analyze_image_function_name" {
  description = "Name of the Lambda function that analyzes images"
  value       = aws_lambda_function.analyze_image.function_name
}

output "analyze_image_function_arn" {
  description = "ARN of the Lambda function that analyzes images"
  value       = aws_lambda_function.analyze_image.arn
}

###########################################
# Step Functions Outputs
###########################################

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.medical_imaging.name
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.medical_imaging.arn
}

output "state_machine_definition" {
  description = "Definition of the Step Functions state machine"
  value       = aws_sfn_state_machine.medical_imaging.definition
  sensitive   = false
}

###########################################
# IAM Role Outputs
###########################################

output "lambda_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

output "step_functions_role_name" {
  description = "Name of the IAM role used by Step Functions"
  value       = aws_iam_role.step_functions_role.name
}

output "step_functions_role_arn" {
  description = "ARN of the IAM role used by Step Functions"
  value       = aws_iam_role.step_functions_role.arn
}

###########################################
# EventBridge Outputs
###########################################

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for import completion"
  value       = aws_cloudwatch_event_rule.import_completed.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for import completion"
  value       = aws_cloudwatch_event_rule.import_completed.arn
}

###########################################
# CloudWatch Outputs
###########################################

output "step_functions_log_group_name" {
  description = "Name of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions.name
}

output "step_functions_log_group_arn" {
  description = "ARN of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions.arn
}

output "lambda_log_groups" {
  description = "Map of Lambda function names to their CloudWatch log group names"
  value = {
    start_import     = aws_cloudwatch_log_group.start_import.name
    process_metadata = aws_cloudwatch_log_group.process_metadata.name
    analyze_image    = aws_cloudwatch_log_group.analyze_image.name
  }
}

###########################################
# KMS Outputs (if encryption enabled)
###########################################

output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.medical_imaging[0].arn : null
}

output "kms_alias" {
  description = "Alias of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.medical_imaging[0].name : null
}

###########################################
# Network Outputs (if VPC endpoints enabled)
###########################################

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint (if enabled)"
  value       = var.enable_vpc_endpoints && var.vpc_id != "" ? aws_vpc_endpoint.s3[0].id : null
}

output "vpc_endpoint_lambda_id" {
  description = "ID of the Lambda VPC endpoint (if enabled)"
  value       = var.enable_vpc_endpoints && var.vpc_id != "" && length(var.subnet_ids) > 0 ? aws_vpc_endpoint.lambda[0].id : null
}

###########################################
# Deployment Information
###########################################

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

###########################################
# Usage Instructions
###########################################

output "usage_instructions" {
  description = "Instructions for using the deployed medical imaging pipeline"
  value = {
    upload_dicom_files = "Upload DICOM files (.dcm) to s3://${aws_s3_bucket.input.bucket}/ to trigger processing"
    view_results       = "Check processed results in s3://${aws_s3_bucket.output.bucket}/"
    monitor_workflow   = "Monitor Step Functions execution at https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.medical_imaging.arn}"
    view_logs         = "View Lambda function logs in CloudWatch at https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
  }
}

###########################################
# Security and Compliance Information
###########################################

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    encryption_at_rest     = var.enable_kms_encryption ? "Enabled (KMS)" : "Enabled (AES256)"
    encryption_in_transit  = "Enabled (HTTPS/TLS)"
    s3_public_access_block = "Enabled"
    iam_least_privilege    = "Enabled"
    vpc_endpoints          = var.enable_vpc_endpoints ? "Enabled" : "Disabled"
    xray_tracing          = var.enable_x_ray_tracing ? "Enabled" : "Disabled"
    cloudwatch_logging    = "Enabled"
    hipaa_eligible        = "Yes (with BAA)"
  }
}

###########################################
# Cost Optimization Information
###########################################

output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    s3_lifecycle_policies = var.enable_s3_lifecycle ? "Enabled" : "Disabled"
    lambda_right_sizing   = "Configured based on function requirements"
    step_functions_type   = var.step_functions_type
    log_retention        = "${var.log_retention_days} days"
    serverless_scaling   = "Automatic based on demand"
  }
}