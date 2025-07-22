# Outputs for Quantum Computing Pipeline Infrastructure
# This file defines all output values from the quantum computing pipeline

# S3 Bucket Information
output "s3_input_bucket" {
  description = "Name of the S3 input bucket for quantum computing data"
  value       = aws_s3_bucket.input.id
}

output "s3_output_bucket" {
  description = "Name of the S3 output bucket for quantum computing results"
  value       = aws_s3_bucket.output.id
}

output "s3_code_bucket" {
  description = "Name of the S3 code bucket for quantum algorithm storage"
  value       = aws_s3_bucket.code.id
}

output "s3_bucket_arns" {
  description = "ARNs of all S3 buckets created"
  value = {
    input  = aws_s3_bucket.input.arn
    output = aws_s3_bucket.output.arn
    code   = aws_s3_bucket.code.arn
  }
}

# Lambda Function Information
output "lambda_function_names" {
  description = "Names of all Lambda functions created"
  value = {
    data_preparation = aws_lambda_function.data_preparation.function_name
    job_submission   = aws_lambda_function.job_submission.function_name
    job_monitoring   = aws_lambda_function.job_monitoring.function_name
    post_processing  = aws_lambda_function.post_processing.function_name
  }
}

output "lambda_function_arns" {
  description = "ARNs of all Lambda functions created"
  value = {
    data_preparation = aws_lambda_function.data_preparation.arn
    job_submission   = aws_lambda_function.job_submission.arn
    job_monitoring   = aws_lambda_function.job_monitoring.arn
    post_processing  = aws_lambda_function.post_processing.arn
  }
}

output "lambda_function_invoke_arns" {
  description = "Invoke ARNs of all Lambda functions"
  value = {
    data_preparation = aws_lambda_function.data_preparation.invoke_arn
    job_submission   = aws_lambda_function.job_submission.invoke_arn
    job_monitoring   = aws_lambda_function.job_monitoring.invoke_arn
    post_processing  = aws_lambda_function.post_processing.invoke_arn
  }
}

# IAM Role Information
output "execution_role_arn" {
  description = "ARN of the execution role for Lambda functions and Braket"
  value       = aws_iam_role.execution_role.arn
}

output "execution_role_name" {
  description = "Name of the execution role"
  value       = aws_iam_role.execution_role.name
}

# CloudWatch Information
output "cloudwatch_log_groups" {
  description = "Names of CloudWatch log groups created"
  value = {
    data_preparation = aws_cloudwatch_log_group.data_preparation.name
    job_submission   = aws_cloudwatch_log_group.job_submission.name
    job_monitoring   = aws_cloudwatch_log_group.job_monitoring.name
    post_processing  = aws_cloudwatch_log_group.post_processing.name
  }
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.quantum_pipeline.dashboard_name}"
}

output "cloudwatch_alarms" {
  description = "Names of CloudWatch alarms created"
  value = {
    job_failure_rate = aws_cloudwatch_metric_alarm.job_failure_rate.alarm_name
    low_efficiency   = aws_cloudwatch_metric_alarm.low_efficiency.alarm_name
  }
}

# Project Information
output "project_name" {
  description = "Name of the quantum computing project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

# Quantum Computing Configuration
output "quantum_configuration" {
  description = "Quantum computing configuration parameters"
  value = {
    enable_braket_qpu      = var.enable_braket_qpu
    braket_device_type     = var.braket_device_type
    optimization_iterations = var.optimization_iterations
    learning_rate          = var.learning_rate
    problem_types          = var.quantum_problem_types
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the quantum computing pipeline"
  value = <<-EOT
    Quantum Computing Pipeline Deployment Complete!
    
    To use this pipeline:
    
    1. Data Preparation:
       aws lambda invoke \
         --function-name ${aws_lambda_function.data_preparation.function_name} \
         --payload '{"input_bucket": "${aws_s3_bucket.input.id}", "output_bucket": "${aws_s3_bucket.output.id}", "problem_type": "optimization", "problem_size": 4}' \
         response.json
    
    2. Job Submission:
       aws lambda invoke \
         --function-name ${aws_lambda_function.job_submission.function_name} \
         --payload '{"input_bucket": "${aws_s3_bucket.input.id}", "output_bucket": "${aws_s3_bucket.output.id}", "code_bucket": "${aws_s3_bucket.code.id}", "data_key": "YOUR_DATA_KEY"}' \
         response.json
    
    3. Monitor via CloudWatch Dashboard:
       ${aws_cloudwatch_dashboard.quantum_pipeline.dashboard_name}
    
    4. Access Results:
       aws s3 ls s3://${aws_s3_bucket.output.id}/jobs/
  EOT
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    s3_encryption_enabled = var.s3_bucket_encryption
    s3_versioning_enabled = var.s3_bucket_versioning
    iam_role_arn         = aws_iam_role.execution_role.arn
    log_retention_days   = var.cloudwatch_retention_days
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Cost optimization recommendations"
  value = <<-EOT
    Cost Optimization Tips:
    
    1. Use quantum simulators for development and testing
    2. Monitor CloudWatch metrics to optimize Lambda memory allocation
    3. Set appropriate S3 lifecycle policies for result data
    4. Use Braket QPUs only for production workloads
    5. Monitor quantum job duration and optimize algorithms
    6. Clean up unused quantum results regularly
    
    Current Configuration:
    - Lambda Memory: ${var.lambda_memory_size}MB
    - Lambda Timeout: ${var.lambda_timeout}s
    - Log Retention: ${var.cloudwatch_retention_days} days
    - Braket QPU Enabled: ${var.enable_braket_qpu}
  EOT
}