# Output Values for Document Processing Pipeline
# This file defines the output values that will be displayed after deployment

# ========================================
# S3 BUCKET OUTPUTS
# ========================================

output "input_bucket_name" {
  description = "Name of the S3 bucket for document uploads"
  value       = aws_s3_bucket.input.id
}

output "input_bucket_arn" {
  description = "ARN of the S3 input bucket"
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for processed results"
  value       = aws_s3_bucket.output.id
}

output "output_bucket_arn" {
  description = "ARN of the S3 output bucket"
  value       = aws_s3_bucket.output.arn
}

output "archive_bucket_name" {
  description = "Name of the S3 bucket for document archival"
  value       = aws_s3_bucket.archive.id
}

output "archive_bucket_arn" {
  description = "ARN of the S3 archive bucket"
  value       = aws_s3_bucket.archive.arn
}

# ========================================
# LAMBDA FUNCTION OUTPUTS
# ========================================

output "document_processor_function_name" {
  description = "Name of the document processor Lambda function"
  value       = aws_lambda_function.document_processor.function_name
}

output "document_processor_function_arn" {
  description = "ARN of the document processor Lambda function"
  value       = aws_lambda_function.document_processor.arn
}

output "results_processor_function_name" {
  description = "Name of the results processor Lambda function"
  value       = aws_lambda_function.results_processor.function_name
}

output "results_processor_function_arn" {
  description = "ARN of the results processor Lambda function"
  value       = aws_lambda_function.results_processor.arn
}

output "s3_trigger_function_name" {
  description = "Name of the S3 trigger Lambda function"
  value       = aws_lambda_function.s3_trigger.function_name
}

output "s3_trigger_function_arn" {
  description = "ARN of the S3 trigger Lambda function"
  value       = aws_lambda_function.s3_trigger.arn
}

# ========================================
# STEP FUNCTIONS OUTPUTS
# ========================================

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.document_pipeline.name
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.document_pipeline.arn
}

output "state_machine_definition" {
  description = "Definition of the Step Functions state machine"
  value       = aws_sfn_state_machine.document_pipeline.definition
  sensitive   = false
}

# ========================================
# IAM ROLE OUTPUTS
# ========================================

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "stepfunctions_role_name" {
  description = "Name of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_role.name
}

output "stepfunctions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_role.arn
}

# ========================================
# CLOUDWATCH OUTPUTS
# ========================================

output "cloudwatch_log_groups" {
  description = "List of CloudWatch log groups created"
  value = {
    document_processor = aws_cloudwatch_log_group.document_processor.name
    results_processor  = aws_cloudwatch_log_group.results_processor.name
    s3_trigger        = aws_cloudwatch_log_group.s3_trigger.name
    stepfunctions     = aws_cloudwatch_log_group.stepfunctions.name
  }
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${local.project_id}-pipeline-monitoring" : "Dashboard not enabled"
}

# ========================================
# MONITORING AND NOTIFICATIONS
# ========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for failure notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.failure_notifications[0].arn : "Notifications not enabled"
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

# ========================================
# DEPLOYMENT INFORMATION
# ========================================

output "project_id" {
  description = "Unique project identifier used for resource naming"
  value       = local.project_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_timestamp" {
  description = "Timestamp of the deployment"
  value       = timestamp()
}

# ========================================
# USAGE INSTRUCTIONS
# ========================================

output "usage_instructions" {
  description = "Instructions for using the deployed document processing pipeline"
  value = <<-EOT
    Document Processing Pipeline Deployment Complete!
    
    Quick Start:
    1. Upload documents to: s3://${aws_s3_bucket.input.id}
    2. Monitor processing: AWS Console > Step Functions > ${aws_sfn_state_machine.document_pipeline.name}
    3. Check results: s3://${aws_s3_bucket.output.id}/processed/
    4. View archived documents: s3://${aws_s3_bucket.archive.id}/archive/
    
    Monitoring:
    - CloudWatch Dashboard: ${var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${local.project_id}-pipeline-monitoring" : "Dashboard not enabled"}
    - Step Functions Console: https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.document_pipeline.arn}
    
    Supported File Types: ${join(", ", var.allowed_file_types)}
    Textract Features: ${join(", ", var.textract_features)}
    
    For testing, try uploading a PDF document to the input bucket.
  EOT
}

# ========================================
# RESOURCE SUMMARY
# ========================================

output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_buckets = {
      input   = aws_s3_bucket.input.id
      output  = aws_s3_bucket.output.id
      archive = aws_s3_bucket.archive.id
    }
    lambda_functions = {
      document_processor = aws_lambda_function.document_processor.function_name
      results_processor  = aws_lambda_function.results_processor.function_name
      s3_trigger        = aws_lambda_function.s3_trigger.function_name
    }
    step_functions = {
      state_machine = aws_sfn_state_machine.document_pipeline.name
    }
    iam_roles = {
      lambda_role        = aws_iam_role.lambda_role.name
      stepfunctions_role = aws_iam_role.stepfunctions_role.name
    }
    monitoring = {
      dashboard_enabled = var.enable_dashboard
      xray_enabled     = var.enable_xray_tracing
      notifications    = var.notification_email != ""
    }
  }
}

# ========================================
# COST ESTIMATION
# ========================================

output "cost_considerations" {
  description = "Information about potential costs and optimization"
  value = <<-EOT
    Cost Considerations:
    
    Primary Cost Drivers:
    - Amazon Textract: $1.50 per 1,000 pages (document analysis)
    - Lambda Invocations: $0.20 per 1M requests + duration costs
    - Step Functions: $0.025 per 1,000 state transitions
    - S3 Storage: $0.023 per GB/month (Standard tier)
    
    Cost Optimization Tips:
    - Use S3 lifecycle policies to transition old documents to cheaper storage
    - Monitor Lambda memory allocation vs. execution time
    - Consider reserved capacity for predictable workloads
    - Set up billing alerts for cost monitoring
    
    Estimated Monthly Cost (100 documents/day):
    - Textract: ~$45-90 (assuming 10-20 pages per document)
    - Lambda: ~$5-10
    - Step Functions: ~$1-2
    - S3: ~$5-15 (depending on document size and retention)
    
    Total Estimated: $56-117/month for 100 documents/day
  EOT
}

# ========================================
# SECURITY INFORMATION
# ========================================

output "security_features" {
  description = "Security features implemented in the deployment"
  value = {
    encryption = {
      s3_encryption_enabled = var.enable_encryption
      lambda_environment_encrypted = true
    }
    access_control = {
      iam_least_privilege = true
      s3_public_access_blocked = true
      lambda_execution_role_scoped = true
    }
    monitoring = {
      cloudwatch_logging = true
      xray_tracing = var.enable_xray_tracing
      step_functions_logging = true
    }
    network_security = {
      vpc_deployment = false
      note = "Consider VPC deployment for enhanced network security"
    }
  }
}