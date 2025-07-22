# Outputs for AWS Cloud9 developer environments infrastructure

output "cloud9_environment_id" {
  description = "The ID of the Cloud9 environment"
  value       = aws_cloud9_environment_ec2.main.id
}

output "cloud9_environment_name" {
  description = "The name of the Cloud9 environment"
  value       = aws_cloud9_environment_ec2.main.name
}

output "cloud9_environment_arn" {
  description = "The ARN of the Cloud9 environment"
  value       = aws_cloud9_environment_ec2.main.arn
}

output "cloud9_environment_type" {
  description = "The type of the Cloud9 environment"
  value       = aws_cloud9_environment_ec2.main.type
}

output "cloud9_instance_type" {
  description = "The EC2 instance type used for the Cloud9 environment"
  value       = var.cloud9_instance_type
}

output "cloud9_auto_stop_minutes" {
  description = "Number of minutes before the Cloud9 environment automatically stops"
  value       = var.cloud9_auto_stop_minutes
}

output "cloud9_owner_arn" {
  description = "The ARN of the Cloud9 environment owner"
  value       = aws_cloud9_environment_ec2.main.owner_arn
}

output "cloud9_iam_role_name" {
  description = "The name of the IAM role created for the Cloud9 environment"
  value       = aws_iam_role.cloud9_role.name
}

output "cloud9_iam_role_arn" {
  description = "The ARN of the IAM role created for the Cloud9 environment"
  value       = aws_iam_role.cloud9_role.arn
}

output "codecommit_repository_name" {
  description = "The name of the CodeCommit repository (if created)"
  value       = var.enable_codecommit ? aws_codecommit_repository.team_repo[0].repository_name : null
}

output "codecommit_repository_id" {
  description = "The ID of the CodeCommit repository (if created)"
  value       = var.enable_codecommit ? aws_codecommit_repository.team_repo[0].repository_id : null
}

output "codecommit_clone_url_http" {
  description = "The HTTP clone URL of the CodeCommit repository (if created)"
  value       = var.enable_codecommit ? aws_codecommit_repository.team_repo[0].clone_url_http : null
  sensitive   = false
}

output "codecommit_clone_url_ssh" {
  description = "The SSH clone URL of the CodeCommit repository (if created)"
  value       = var.enable_codecommit ? aws_codecommit_repository.team_repo[0].clone_url_ssh : null
  sensitive   = false
}

output "development_policy_arn" {
  description = "The ARN of the custom development IAM policy (if created)"
  value       = var.create_development_policy ? aws_iam_policy.development_policy[0].arn : null
}

output "development_policy_name" {
  description = "The name of the custom development IAM policy (if created)"
  value       = var.create_development_policy ? aws_iam_policy.development_policy[0].name : null
}

output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard (if created)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.cloud9_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "The URL to access the CloudWatch dashboard (if created)"
  value = var.enable_cloudwatch_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cloud9_monitoring[0].dashboard_name}" : null
}

output "team_member_count" {
  description = "Number of team members added to the Cloud9 environment"
  value       = length(var.team_member_arns)
}

output "environment_access_url" {
  description = "URL to access the Cloud9 environment through AWS Console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloud9/ide/${aws_cloud9_environment_ec2.main.id}"
}

output "aws_region" {
  description = "The AWS region where resources were created"
  value       = var.aws_region
}

output "project_name" {
  description = "The project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "setup_script_path" {
  description = "Path to the Cloud9 setup script that should be run within the environment"
  value       = local_file.cloud9_setup_script.filename
}

output "environment_config_script_path" {
  description = "Path to the environment configuration script"
  value       = local_file.environment_config_script.filename
}

# Summary output for easy reference
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    cloud9_environment = {
      id           = aws_cloud9_environment_ec2.main.id
      name         = aws_cloud9_environment_ec2.main.name
      instance_type = var.cloud9_instance_type
      access_url   = "https://${var.aws_region}.console.aws.amazon.com/cloud9/ide/${aws_cloud9_environment_ec2.main.id}"
    }
    codecommit_repository = var.enable_codecommit ? {
      name           = aws_codecommit_repository.team_repo[0].repository_name
      clone_url_http = aws_codecommit_repository.team_repo[0].clone_url_http
    } : null
    monitoring = var.enable_cloudwatch_dashboard ? {
      dashboard_name = aws_cloudwatch_dashboard.cloud9_monitoring[0].dashboard_name
      dashboard_url  = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cloud9_monitoring[0].dashboard_name}"
    } : null
    next_steps = [
      "1. Access your Cloud9 environment using the provided URL",
      "2. Run the setup script (cloud9-setup.sh) within the Cloud9 environment",
      "3. Configure Git credentials for your team members",
      var.enable_codecommit ? "4. Clone the CodeCommit repository to start development" : "4. Set up your preferred Git repository",
      "5. Start developing in the ~/projects directory structure"
    ]
  }
}