# Outputs for IoT firmware updates infrastructure

# ============================================================================
# S3 OUTPUTS
# ============================================================================

output "firmware_bucket_name" {
  description = "Name of the S3 bucket for firmware storage"
  value       = aws_s3_bucket.firmware_bucket.bucket
}

output "firmware_bucket_arn" {
  description = "ARN of the S3 bucket for firmware storage"
  value       = aws_s3_bucket.firmware_bucket.arn
}

output "firmware_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.firmware_bucket.bucket_domain_name
}

output "sample_firmware_s3_key" {
  description = "S3 key for the sample firmware file"
  value       = aws_s3_object.sample_firmware.key
}

output "sample_firmware_url" {
  description = "HTTPS URL for the sample firmware file"
  value       = "https://${aws_s3_bucket.firmware_bucket.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.sample_firmware.key}"
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "iot_jobs_role_arn" {
  description = "ARN of the IAM role for IoT Jobs"
  value       = aws_iam_role.iot_jobs_role.arn
}

output "iot_jobs_role_name" {
  description = "Name of the IAM role for IoT Jobs"
  value       = aws_iam_role.iot_jobs_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.name
}

# ============================================================================
# IOT OUTPUTS
# ============================================================================

output "thing_group_name" {
  description = "Name of the IoT Thing Group"
  value       = aws_iot_thing_group.firmware_update_group.name
}

output "thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.firmware_update_group.arn
}

output "test_device_name" {
  description = "Name of the test IoT device (if created)"
  value       = var.create_sample_device ? aws_iot_thing.test_device[0].name : null
}

output "test_device_arn" {
  description = "ARN of the test IoT device (if created)"
  value       = var.create_sample_device ? aws_iot_thing.test_device[0].arn : null
}

output "device_type_name" {
  description = "Name of the IoT Thing Type (if created)"
  value       = var.create_sample_device ? aws_iot_thing_type.device_type[0].name : null
}

output "device_type_arn" {
  description = "ARN of the IoT Thing Type (if created)"
  value       = var.create_sample_device ? aws_iot_thing_type.device_type[0].arn : null
}

# ============================================================================
# LAMBDA OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.firmware_update_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.firmware_update_manager.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.firmware_update_manager.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# SIGNER OUTPUTS
# ============================================================================

output "signing_profile_name" {
  description = "Name of the AWS Signer signing profile"
  value       = aws_signer_signing_profile.firmware_signing_profile.name
}

output "signing_profile_arn" {
  description = "ARN of the AWS Signer signing profile"
  value       = aws_signer_signing_profile.firmware_signing_profile.arn
}

output "signing_platform_id" {
  description = "Platform ID used for firmware signing"
  value       = aws_signer_signing_profile.firmware_signing_profile.platform_id
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.iot_jobs_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard (if created)"
  value       = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.iot_jobs_dashboard[0].dashboard_name}" : null
}

# ============================================================================
# UTILITY OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# TESTING AND USAGE OUTPUTS
# ============================================================================

output "lambda_test_payload_create_job" {
  description = "Sample Lambda payload for creating a firmware update job"
  value = jsonencode({
    action              = "create_job"
    firmware_version    = "1.0.0"
    thing_group         = aws_iot_thing_group.firmware_update_group.name
    s3_bucket           = aws_s3_bucket.firmware_bucket.bucket
    s3_key              = aws_s3_object.sample_firmware.key
    max_per_minute      = var.job_rollout_max_per_minute
    base_rate_per_minute = var.job_rollout_base_rate_per_minute
    increment_factor    = var.job_rollout_increment_factor
    failure_threshold   = var.job_abort_failure_threshold
    timeout_minutes     = var.job_timeout_minutes
  })
}

output "lambda_test_payload_check_status" {
  description = "Sample Lambda payload for checking job status (replace JOB_ID with actual job ID)"
  value = jsonencode({
    action = "check_job_status"
    job_id = "JOB_ID_PLACEHOLDER"
  })
}

output "lambda_test_payload_cancel_job" {
  description = "Sample Lambda payload for cancelling a job (replace JOB_ID with actual job ID)"
  value = jsonencode({
    action = "cancel_job"
    job_id = "JOB_ID_PLACEHOLDER"
  })
}

# ============================================================================
# CLI COMMANDS FOR TESTING
# ============================================================================

output "cli_commands" {
  description = "Useful CLI commands for testing the infrastructure"
  value = {
    # Test Lambda function with sample payload
    test_create_job = "aws lambda invoke --function-name ${aws_lambda_function.firmware_update_manager.function_name} --payload '${base64encode(jsonencode({
      action              = "create_job"
      firmware_version    = "1.0.0"
      thing_group         = aws_iot_thing_group.firmware_update_group.name
      s3_bucket           = aws_s3_bucket.firmware_bucket.bucket
      s3_key              = aws_s3_object.sample_firmware.key
      max_per_minute      = var.job_rollout_max_per_minute
      base_rate_per_minute = var.job_rollout_base_rate_per_minute
      increment_factor    = var.job_rollout_increment_factor
      failure_threshold   = var.job_abort_failure_threshold
      timeout_minutes     = var.job_timeout_minutes
    }))}' response.json"
    
    # List IoT jobs
    list_jobs = "aws iot list-jobs --status IN_PROGRESS"
    
    # Check thing group membership
    list_things_in_group = "aws iot list-things-in-thing-group --thing-group-name ${aws_iot_thing_group.firmware_update_group.name}"
    
    # View CloudWatch dashboard
    view_dashboard = var.create_cloudwatch_dashboard ? "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.iot_jobs_dashboard[0].dashboard_name}" : "No dashboard created"
    
    # Download sample firmware
    download_firmware = "aws s3 cp s3://${aws_s3_bucket.firmware_bucket.bucket}/${aws_s3_object.sample_firmware.key} ./downloaded_firmware.bin"
  }
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_name         = var.project_name
    environment          = var.environment
    aws_region          = data.aws_region.current.name
    firmware_bucket     = aws_s3_bucket.firmware_bucket.bucket
    thing_group         = aws_iot_thing_group.firmware_update_group.name
    test_device         = var.create_sample_device ? aws_iot_thing.test_device[0].name : "Not created"
    lambda_function     = aws_lambda_function.firmware_update_manager.function_name
    signing_profile     = aws_signer_signing_profile.firmware_signing_profile.name
    dashboard_created   = var.create_cloudwatch_dashboard
    versioning_enabled  = var.enable_s3_versioning
    encryption_enabled  = var.enable_s3_encryption
  }
}