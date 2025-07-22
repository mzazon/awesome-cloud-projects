# Outputs for the Quality Gates CodeBuild infrastructure

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.quality_gates.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.quality_gates.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_service_role.arn
}

output "s3_artifacts_bucket_name" {
  description = "Name of the S3 bucket for artifacts"
  value       = aws_s3_bucket.artifacts.id
}

output "s3_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_notifications ? aws_sns_topic.quality_gate_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = var.enable_notifications ? aws_sns_topic.quality_gate_notifications[0].name : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.codebuild_logs[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.quality_gates[0].dashboard_name}" : null
}

output "ssm_parameters" {
  description = "Map of Systems Manager parameters for quality gates"
  value = {
    coverage_threshold = aws_ssm_parameter.coverage_threshold.name
    sonar_quality_gate = aws_ssm_parameter.sonar_quality_gate.name
    security_threshold = aws_ssm_parameter.security_threshold.name
  }
}

output "quality_gate_thresholds" {
  description = "Current quality gate threshold values"
  value = {
    coverage_threshold = var.coverage_threshold
    sonar_quality_gate = var.sonar_quality_gate
    security_threshold = var.security_threshold
  }
}

output "start_build_command" {
  description = "AWS CLI command to start a build"
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.quality_gates.name} --region ${data.aws_region.current.name}"
}

output "project_configuration" {
  description = "Key project configuration details"
  value = {
    project_name         = local.project_name_with_suffix
    environment         = var.environment
    aws_region          = data.aws_region.current.name
    aws_account_id      = data.aws_caller_identity.current.account_id
    build_timeout       = var.build_timeout
    compute_type        = var.compute_type
    notifications_enabled = var.enable_notifications
    caching_enabled     = var.enable_s3_caching
    dashboard_enabled   = var.create_dashboard
  }
}

output "webhook_configuration" {
  description = "Information for setting up GitHub webhook (manual setup required)"
  value = {
    payload_url = "https://codebuild.${data.aws_region.current.name}.amazonaws.com/webhooks/${aws_codebuild_project.quality_gates.name}"
    content_type = "application/json"
    events = [
      "push",
      "pull_request"
    ]
    note = "GitHub webhook must be configured manually in the repository settings"
  }
}

output "buildspec_location" {
  description = "Location of the sample buildspec file"
  value       = "s3://${aws_s3_bucket.artifacts.id}/sample-buildspec.yml"
}

output "monitoring_urls" {
  description = "URLs for monitoring the quality gates"
  value = {
    codebuild_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codebuild/projects/${aws_codebuild_project.quality_gates.name}/history"
    cloudwatch_logs   = var.enable_cloudwatch_logs ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.codebuild_logs[0].name, "/", "$252F")}" : null
    s3_artifacts      = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.artifacts.id}"
    sns_topic         = var.enable_notifications ? "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topic/${aws_sns_topic.quality_gate_notifications[0].arn}" : null
  }
}

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Configure your GitHub repository with source code and buildspec.yml",
    "2. Set up GitHub webhook using the webhook_configuration output",
    "3. Configure SonarQube token as environment variable if using SonarQube",
    "4. Test the pipeline by pushing code to the repository",
    "5. Monitor builds through the CodeBuild console and CloudWatch dashboard"
  ]
}