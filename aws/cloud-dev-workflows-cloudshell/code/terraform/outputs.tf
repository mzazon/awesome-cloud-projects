# ============================================================================
# CODECOMMIT REPOSITORY OUTPUTS
# ============================================================================

output "repository_name" {
  description = "Name of the created CodeCommit repository"
  value       = aws_codecommit_repository.main.repository_name
}

output "repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.main.arn
}

output "repository_id" {
  description = "ID of the CodeCommit repository"
  value       = aws_codecommit_repository.main.repository_id
}

output "repository_clone_url_http" {
  description = "HTTPS clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.main.clone_url_http
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.main.clone_url_ssh
}

# ============================================================================
# IAM RESOURCES OUTPUTS
# ============================================================================

output "iam_group_name" {
  description = "Name of the IAM group for developers"
  value       = aws_iam_group.developers.name
}

output "iam_group_arn" {
  description = "ARN of the IAM group for developers"
  value       = aws_iam_group.developers.arn
}

output "codecommit_policy_arn" {
  description = "ARN of the IAM policy for CodeCommit access"
  value       = aws_iam_policy.codecommit_access.arn
}

output "cloudshell_policy_arn" {
  description = "ARN of the IAM policy for CloudShell access"
  value       = aws_iam_policy.cloudshell_access.arn
}

output "iam_user_name" {
  description = "Name of the created IAM user (if created)"
  value       = var.create_iam_user ? aws_iam_user.developer[0].name : null
}

output "iam_user_arn" {
  description = "ARN of the created IAM user (if created)"
  value       = var.create_iam_user ? aws_iam_user.developer[0].arn : null
}

output "git_username" {
  description = "Git username for CodeCommit access (if IAM user created)"
  value       = var.create_iam_user ? aws_iam_service_specific_credential.git_credentials[0].service_user_name : null
  sensitive   = true
}

output "git_password" {
  description = "Git password for CodeCommit access (if IAM user created)"
  value       = var.create_iam_user ? aws_iam_service_specific_credential.git_credentials[0].service_password : null
  sensitive   = true
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for development activities"
  value       = aws_cloudwatch_log_group.development_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for development activities"
  value       = aws_cloudwatch_log_group.development_logs.arn
}

# ============================================================================
# SYSTEMS MANAGER PARAMETER STORE OUTPUTS
# ============================================================================

output "ssm_parameter_repository_name" {
  description = "Systems Manager parameter name for repository name"
  value       = aws_ssm_parameter.repository_name.name
}

output "ssm_parameter_repository_url" {
  description = "Systems Manager parameter name for repository URL"
  value       = aws_ssm_parameter.repository_url.name
}

output "ssm_parameter_cloudshell_region" {
  description = "Systems Manager parameter name for CloudShell region"
  value       = aws_ssm_parameter.cloudshell_region.name
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for repository initialization"
  value       = aws_lambda_function.repo_initializer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for repository initialization"
  value       = aws_lambda_function.repo_initializer.arn
}

# ============================================================================
# CLOUDSHELL CONFIGURATION OUTPUTS
# ============================================================================

output "cloudshell_setup_commands" {
  description = "Commands to run in CloudShell to set up the development environment"
  value = [
    "# Configure Git credentials",
    "git config --global credential.helper '!aws codecommit credential-helper $@'",
    "git config --global credential.UseHttpPath true",
    "git config --global user.name 'CloudShell Developer'",
    "git config --global user.email 'developer@example.com'",
    "",
    "# Clone the repository",
    "git clone ${aws_codecommit_repository.main.clone_url_http}",
    "",
    "# Navigate to repository directory",
    "cd ${aws_codecommit_repository.main.repository_name}",
    "",
    "# Verify setup",
    "git remote -v",
    "aws codecommit get-repository --repository-name ${aws_codecommit_repository.main.repository_name}"
  ]
}

# ============================================================================
# DEPLOYMENT INFORMATION OUTPUTS
# ============================================================================

output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    repository_name    = aws_codecommit_repository.main.repository_name
    repository_url     = aws_codecommit_repository.main.clone_url_http
    aws_region        = var.aws_region
    environment       = var.environment
    project_name      = var.project_name
    iam_group_name    = aws_iam_group.developers.name
    team_size         = var.team_size
    cloudshell_timeout = var.cloudshell_timeout
  }
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure"
  value = {
    codecommit_cost = "Free tier: 5 active users, 50GB storage, 10,000 requests per month"
    cloudshell_cost = "Free tier: 10 hours per month, additional hours at $0.10/hour"
    lambda_cost     = "Free tier: 1M requests, 400,000 GB-seconds per month"
    cloudwatch_cost = "Log ingestion: $0.50/GB, storage: $0.03/GB/month"
    ssm_cost        = "Standard parameters: free, advanced parameters: $0.05/10,000 requests"
    total_estimate  = "$0-10/month depending on usage"
  }
}

# ============================================================================
# SECURITY INFORMATION OUTPUTS
# ============================================================================

output "security_considerations" {
  description = "Security features and considerations for the deployment"
  value = {
    iam_policies          = "Least privilege access policies for CodeCommit and CloudShell"
    encryption_at_rest    = "CodeCommit repositories are encrypted at rest by default"
    encryption_in_transit = "All communications use HTTPS/TLS encryption"
    authentication        = "IAM-based authentication with credential helper"
    audit_logging         = "CloudTrail logs all API calls for compliance"
    access_control        = "IAM groups and policies control resource access"
  }
}

# ============================================================================
# NEXT STEPS OUTPUTS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Access AWS CloudShell from the AWS Management Console",
    "2. Run the setup commands provided in 'cloudshell_setup_commands' output",
    "3. Clone the repository using the provided clone URL",
    "4. Start developing your application code",
    "5. Use Git workflows for version control and collaboration",
    "6. Add team members to the IAM group for access",
    "7. Configure branch protection rules if needed",
    "8. Set up CI/CD pipelines using CodePipeline (optional)",
    "9. Monitor usage through CloudWatch logs and metrics",
    "10. Review security settings and update as needed"
  ]
}