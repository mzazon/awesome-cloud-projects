# Outputs for ECR Container Registry Replication Strategies
# Provides essential information about deployed resources

# ============================================================================
# ECR REPOSITORY OUTPUTS
# ============================================================================

output "production_repository_name" {
  description = "Name of the production ECR repository"
  value       = aws_ecr_repository.production.name
}

output "production_repository_arn" {
  description = "ARN of the production ECR repository"
  value       = aws_ecr_repository.production.arn
}

output "production_repository_uri" {
  description = "URI of the production ECR repository"
  value       = aws_ecr_repository.production.repository_url
}

output "testing_repository_name" {
  description = "Name of the testing ECR repository"
  value       = aws_ecr_repository.testing.name
}

output "testing_repository_arn" {
  description = "ARN of the testing ECR repository"
  value       = aws_ecr_repository.testing.arn
}

output "testing_repository_uri" {
  description = "URI of the testing ECR repository"
  value       = aws_ecr_repository.testing.repository_url
}

# ============================================================================
# REGIONAL CONFIGURATION OUTPUTS
# ============================================================================

output "source_region" {
  description = "Source AWS region for ECR repositories"
  value       = var.source_region
}

output "destination_region" {
  description = "Destination AWS region for ECR replication"
  value       = var.destination_region
}

output "secondary_region" {
  description = "Secondary AWS region for ECR replication"
  value       = var.secondary_region
}

output "account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

# ============================================================================
# REPLICATION CONFIGURATION OUTPUTS
# ============================================================================

output "replication_configuration_registry_id" {
  description = "Registry ID for replication configuration"
  value       = aws_ecr_replication_configuration.main.registry_id
}

output "replication_destinations" {
  description = "List of replication destination regions"
  value       = [var.destination_region, var.secondary_region]
}

output "repository_filter_prefix" {
  description = "Repository filter prefix for replication"
  value       = var.repository_prefix
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "production_role_arn" {
  description = "ARN of the production ECR access role"
  value       = var.create_iam_roles ? aws_iam_role.ecr_production_role[0].arn : var.existing_production_role_arn
}

output "production_role_name" {
  description = "Name of the production ECR access role"
  value       = var.create_iam_roles ? aws_iam_role.ecr_production_role[0].name : null
}

output "ci_pipeline_role_arn" {
  description = "ARN of the CI/CD pipeline ECR access role"
  value       = var.create_iam_roles ? aws_iam_role.ecr_ci_pipeline_role[0].arn : var.existing_ci_pipeline_role_arn
}

output "ci_pipeline_role_name" {
  description = "Name of the CI/CD pipeline ECR access role"
  value       = var.create_iam_roles ? aws_iam_role.ecr_ci_pipeline_role[0].name : null
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for ECR monitoring"
  value       = var.enable_monitoring ? "https://${var.source_region}.console.aws.amazon.com/cloudwatch/home?region=${var.source_region}#dashboards:name=${aws_cloudwatch_dashboard.ecr_monitoring[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_monitoring ? aws_cloudwatch_dashboard.ecr_monitoring[0].dashboard_name : null
}

output "replication_failure_alarm_name" {
  description = "Name of the replication failure CloudWatch alarm"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.replication_failure_rate[0].alarm_name : null
}

output "replication_failure_alarm_arn" {
  description = "ARN of the replication failure CloudWatch alarm"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.replication_failure_rate[0].arn : null
}

output "high_pull_rate_alarm_name" {
  description = "Name of the high pull rate CloudWatch alarm"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.high_pull_rate[0].alarm_name : null
}

output "high_pull_rate_alarm_arn" {
  description = "ARN of the high pull rate CloudWatch alarm"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.high_pull_rate[0].arn : null
}

# ============================================================================
# SNS NOTIFICATION OUTPUTS
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for ECR alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.ecr_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for ECR alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.ecr_alerts[0].name : null
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email != "" ? var.notification_email : null
  sensitive   = true
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_cleanup_function_name" {
  description = "Name of the Lambda cleanup function"
  value       = aws_lambda_function.ecr_cleanup.function_name
}

output "lambda_cleanup_function_arn" {
  description = "ARN of the Lambda cleanup function"
  value       = aws_lambda_function.ecr_cleanup.arn
}

output "lambda_cleanup_role_arn" {
  description = "ARN of the Lambda cleanup function role"
  value       = aws_iam_role.lambda_cleanup_role.arn
}

output "lambda_schedule_rule_name" {
  description = "Name of the EventBridge rule for Lambda scheduling"
  value       = aws_cloudwatch_event_rule.lambda_schedule.name
}

# ============================================================================
# LIFECYCLE POLICY OUTPUTS
# ============================================================================

output "production_lifecycle_policy_text" {
  description = "Lifecycle policy text for production repository"
  value       = aws_ecr_lifecycle_policy.production.policy
}

output "testing_lifecycle_policy_text" {
  description = "Lifecycle policy text for testing repository"
  value       = aws_ecr_lifecycle_policy.testing.policy
}

# ============================================================================
# RESOURCE NAMING OUTPUTS
# ============================================================================

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# DOCKER COMMANDS FOR REPOSITORY ACCESS
# ============================================================================

output "docker_login_command" {
  description = "Command to log in to ECR using Docker"
  value       = "aws ecr get-login-password --region ${var.source_region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.source_region}.amazonaws.com"
}

output "production_docker_push_example" {
  description = "Example command to push to production repository"
  value       = "docker tag my-app:latest ${local.account_id}.dkr.ecr.${var.source_region}.amazonaws.com/${local.production_repo_name}:prod-latest && docker push ${local.account_id}.dkr.ecr.${var.source_region}.amazonaws.com/${local.production_repo_name}:prod-latest"
}

output "testing_docker_push_example" {
  description = "Example command to push to testing repository"
  value       = "docker tag my-app:latest ${local.account_id}.dkr.ecr.${var.source_region}.amazonaws.com/${local.testing_repo_name}:test-latest && docker push ${local.account_id}.dkr.ecr.${var.source_region}.amazonaws.com/${local.testing_repo_name}:test-latest"
}

# ============================================================================
# VALIDATION COMMANDS
# ============================================================================

output "replication_validation_commands" {
  description = "Commands to validate replication across regions"
  value = {
    check_destination_region = "aws ecr describe-repositories --region ${var.destination_region} --repository-names ${local.production_repo_name}"
    check_secondary_region   = "aws ecr describe-repositories --region ${var.secondary_region} --repository-names ${local.production_repo_name}"
    list_images_destination  = "aws ecr describe-images --region ${var.destination_region} --repository-name ${local.production_repo_name}"
    list_images_secondary    = "aws ecr describe-images --region ${var.secondary_region} --repository-name ${local.production_repo_name}"
  }
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    lifecycle_policies_enabled = true
    production_retention_count = var.production_image_retention_count
    testing_retention_count    = var.testing_image_retention_count
    untagged_retention_days    = var.untagged_image_retention_days
    testing_retention_days     = var.testing_image_retention_days
  }
}

# ============================================================================
# SECURITY CONFIGURATION OUTPUTS
# ============================================================================

output "security_features" {
  description = "Security features enabled for ECR repositories"
  value = {
    image_scanning_enabled     = var.enable_image_scanning
    encryption_enabled         = true
    encryption_type           = "AES256"
    repository_policies_set   = true
    iam_roles_created         = var.create_iam_roles
  }
}