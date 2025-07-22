# Outputs for CodeGuru Automation Infrastructure
# This file defines outputs that provide important information about created resources

output "repository_name" {
  description = "Name of the created CodeCommit repository"
  value       = aws_codecommit_repository.main.repository_name
}

output "repository_clone_url_http" {
  description = "HTTP clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.main.clone_url_http
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.main.clone_url_ssh
}

output "repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.main.arn
}

output "codeguru_reviewer_association_arn" {
  description = "ARN of the CodeGuru Reviewer repository association"
  value       = var.enable_codeguru_reviewer ? aws_codegurureviewer_association_repository.main[0].arn : null
}

output "codeguru_reviewer_association_id" {
  description = "ID of the CodeGuru Reviewer repository association"
  value       = var.enable_codeguru_reviewer ? aws_codegurureviewer_association_repository.main[0].id : null
}

output "profiler_group_name" {
  description = "Name of the CodeGuru Profiler group"
  value       = var.enable_codeguru_profiler ? aws_codeguruprofiler_profiling_group.main[0].name : null
}

output "profiler_group_arn" {
  description = "ARN of the CodeGuru Profiler group"
  value       = var.enable_codeguru_profiler ? aws_codeguruprofiler_profiling_group.main[0].arn : null
}

output "iam_role_name" {
  description = "Name of the IAM role created for CodeGuru services"
  value       = aws_iam_role.codeguru_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role created for CodeGuru services"
  value       = aws_iam_role.codeguru_role.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for CodeGuru artifacts (if created)"
  value       = var.custom_detector_s3_bucket != "" ? aws_s3_bucket.codeguru_artifacts[0].bucket : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for CodeGuru artifacts (if created)"
  value       = var.custom_detector_s3_bucket != "" ? aws_s3_bucket.codeguru_artifacts[0].arn : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.codeguru_notifications[0].arn : null
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for CodeGuru events (if created)"
  value       = var.enable_eventbridge_integration ? aws_cloudwatch_event_rule.codeguru_events[0].name : null
}

output "lambda_function_name" {
  description = "Name of the Lambda function for quality gates (if created)"
  value       = var.enable_code_quality_gates ? aws_lambda_function.quality_gate[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for quality gates (if created)"
  value       = var.enable_code_quality_gates ? aws_lambda_function.quality_gate[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for CodeGuru metrics"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.codeguru_dashboard.dashboard_name}"
}

output "codeguru_reviewer_console_url" {
  description = "URL to the CodeGuru Reviewer console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/codeguru/reviewer/home?region=${data.aws_region.current.name}"
}

output "codeguru_profiler_console_url" {
  description = "URL to the CodeGuru Profiler console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/codeguru/profiler/home?region=${data.aws_region.current.name}"
}

# Environment variables for application configuration
output "profiler_environment_variables" {
  description = "Environment variables needed for CodeGuru Profiler integration"
  value = var.enable_codeguru_profiler ? {
    PROFILING_GROUP_NAME                      = aws_codeguruprofiler_profiling_group.main[0].name
    AWS_CODEGURU_PROFILER_TARGET_REGION      = data.aws_region.current.name
    AWS_CODEGURU_PROFILER_ENABLED            = "true"
  } : {}
}

# Command line examples for getting started
output "cli_commands" {
  description = "Useful CLI commands for interacting with the created resources"
  value = {
    clone_repository = "git clone ${aws_codecommit_repository.main.clone_url_http}"
    
    describe_association = var.enable_codeguru_reviewer ? "aws codeguru-reviewer describe-repository-association --association-arn ${aws_codegurureviewer_association_repository.main[0].arn}" : "CodeGuru Reviewer not enabled"
    
    describe_profiler_group = var.enable_codeguru_profiler ? "aws codeguru-profiler describe-profiling-group --profiling-group-name ${aws_codeguruprofiler_profiling_group.main[0].name}" : "CodeGuru Profiler not enabled"
    
    create_code_review = var.enable_codeguru_reviewer ? "aws codeguru-reviewer create-code-review --name 'manual-review-$(date +%Y%m%d-%H%M%S)' --repository-association-arn ${aws_codegurureviewer_association_repository.main[0].arn} --type '{\"RepositoryAnalysis\": {\"RepositoryHead\": {\"BranchName\": \"main\"}}}'" : "CodeGuru Reviewer not enabled"
    
    list_recommendations = "aws codeguru-reviewer list-recommendations --code-review-arn <CODE_REVIEW_ARN>"
    
    list_profile_times = var.enable_codeguru_profiler ? "aws codeguru-profiler list-profile-times --profiling-group-name ${aws_codeguruprofiler_profiling_group.main[0].name} --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)" : "CodeGuru Profiler not enabled"
  }
}

# Quality gate script content
output "quality_gate_script" {
  description = "Example quality gate script for CI/CD integration"
  value = var.enable_code_quality_gates ? templatefile("${path.module}/quality_gate_script.sh.tpl", {
    max_severity_threshold = var.max_severity_threshold
    lambda_function_name   = aws_lambda_function.quality_gate[0].function_name
  }) : "Quality gates not enabled"
  sensitive = false
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed CodeGuru automation configuration"
  value = {
    repository_name         = aws_codecommit_repository.main.repository_name
    reviewer_enabled        = var.enable_codeguru_reviewer
    profiler_enabled        = var.enable_codeguru_profiler
    quality_gates_enabled   = var.enable_code_quality_gates
    notifications_enabled   = var.notification_email != ""
    eventbridge_enabled     = var.enable_eventbridge_integration
    custom_detector_bucket  = var.custom_detector_s3_bucket != ""
    severity_threshold      = var.max_severity_threshold
    environment            = var.environment
    project_name           = var.project_name
  }
}