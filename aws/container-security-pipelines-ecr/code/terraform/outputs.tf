# ECR Repository outputs
output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

# CodeBuild outputs
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.security_scanning.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.security_scanning.arn
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.security_scan_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.security_scan_processor.arn
}

# SNS Topic outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

# EventBridge Rule outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.ecr_scan_completed.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.ecr_scan_completed.arn
}

# IAM Role outputs
output "codebuild_role_name" {
  description = "Name of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.name
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch Dashboard outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.security_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.security_dashboard.dashboard_name}"
}

# Config outputs (conditional)
output "config_bucket_name" {
  description = "Name of the S3 bucket for Config"
  value       = var.enable_config_rules ? aws_s3_bucket.config_bucket[0].bucket : null
}

output "config_rule_name" {
  description = "Name of the Config rule"
  value       = var.enable_config_rules ? aws_config_config_rule.ecr_scan_enabled[0].name : null
}

# Enhanced scanning status
output "enhanced_scanning_enabled" {
  description = "Whether enhanced scanning is enabled"
  value       = var.enable_enhanced_scanning
}

# Resource naming suffix
output "name_suffix" {
  description = "Random suffix used for resource names"
  value       = local.name_suffix
}

# Deployment information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Container push command
output "docker_push_command" {
  description = "Command to push Docker images to ECR"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}"
}

# Sample build command
output "sample_build_commands" {
  description = "Sample commands to build and push a container image"
  value = [
    "docker build -t ${aws_ecr_repository.main.name}:latest .",
    "docker tag ${aws_ecr_repository.main.name}:latest ${aws_ecr_repository.main.repository_url}:latest",
    "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}",
    "docker push ${aws_ecr_repository.main.repository_url}:latest"
  ]
}

# Security configuration summary
output "security_configuration" {
  description = "Summary of security configuration settings"
  value = {
    enhanced_scanning_enabled     = var.enable_enhanced_scanning
    scan_frequency               = var.scan_frequency
    scan_on_push                 = var.ecr_scan_on_push
    snyk_scanning_enabled        = var.enable_snyk_scanning
    prisma_scanning_enabled      = var.enable_prisma_scanning
    config_rules_enabled         = var.enable_config_rules
    security_hub_enabled         = var.enable_security_hub
    critical_vuln_threshold      = var.critical_vulnerability_threshold
    high_vuln_threshold          = var.high_vulnerability_threshold
  }
}

# Notification settings
output "notification_settings" {
  description = "Notification configuration"
  value = {
    email_notifications = var.notification_email
    sns_topic_arn      = aws_sns_topic.security_alerts.arn
  }
}

# Next steps
output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Configure third-party scanner credentials in AWS Secrets Manager",
    "2. Subscribe to SNS topic for email notifications",
    "3. Create buildspec.yml in your source repository",
    "4. Push a test container image to trigger scanning",
    "5. Monitor CloudWatch dashboard for security findings"
  ]
}