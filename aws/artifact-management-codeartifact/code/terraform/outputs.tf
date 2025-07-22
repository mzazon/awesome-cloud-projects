# Output values for the CodeArtifact artifact management infrastructure
# These outputs provide important information for using the deployed resources

# Domain Information
output "domain_name" {
  description = "Name of the CodeArtifact domain"
  value       = aws_codeartifact_domain.main.domain
}

output "domain_arn" {
  description = "ARN of the CodeArtifact domain"
  value       = aws_codeartifact_domain.main.arn
}

output "domain_owner" {
  description = "Owner ID of the CodeArtifact domain"
  value       = aws_codeartifact_domain.main.owner
}

# Repository Information
output "npm_store_repository_name" {
  description = "Name of the npm store repository"
  value       = aws_codeartifact_repository.npm_store.repository
}

output "npm_store_repository_arn" {
  description = "ARN of the npm store repository"
  value       = aws_codeartifact_repository.npm_store.arn
}

output "pypi_store_repository_name" {
  description = "Name of the PyPI store repository"
  value       = aws_codeartifact_repository.pypi_store.repository
}

output "pypi_store_repository_arn" {
  description = "ARN of the PyPI store repository"
  value       = aws_codeartifact_repository.pypi_store.arn
}

output "team_repository_name" {
  description = "Name of the team development repository"
  value       = aws_codeartifact_repository.team_dev.repository
}

output "team_repository_arn" {
  description = "ARN of the team development repository"
  value       = aws_codeartifact_repository.team_dev.arn
}

output "production_repository_name" {
  description = "Name of the production repository"
  value       = aws_codeartifact_repository.production.repository
}

output "production_repository_arn" {
  description = "ARN of the production repository"
  value       = aws_codeartifact_repository.production.arn
}

# Repository Endpoints for Package Managers
output "team_repository_npm_endpoint" {
  description = "npm endpoint URL for the team repository"
  value       = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/npm/${aws_codeartifact_repository.team_dev.repository}/"
}

output "team_repository_pypi_endpoint" {
  description = "PyPI endpoint URL for the team repository"
  value       = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/pypi/${aws_codeartifact_repository.team_dev.repository}/"
}

output "production_repository_npm_endpoint" {
  description = "npm endpoint URL for the production repository"
  value       = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/npm/${aws_codeartifact_repository.production.repository}/"
}

output "production_repository_pypi_endpoint" {
  description = "PyPI endpoint URL for the production repository"
  value       = "https://${aws_codeartifact_domain.main.domain}-${data.aws_caller_identity.current.account_id}.d.codeartifact.${data.aws_region.current.name}.amazonaws.com/pypi/${aws_codeartifact_repository.production.repository}/"
}

# IAM Role Information
output "developer_role_arn" {
  description = "ARN of the developer IAM role"
  value       = var.create_developer_role ? aws_iam_role.developer_role[0].arn : null
}

output "developer_role_name" {
  description = "Name of the developer IAM role"
  value       = var.create_developer_role ? aws_iam_role.developer_role[0].name : null
}

output "production_role_arn" {
  description = "ARN of the production IAM role"
  value       = var.create_production_role ? aws_iam_role.production_role[0].arn : null
}

output "production_role_name" {
  description = "Name of the production IAM role"
  value       = var.create_production_role ? aws_iam_role.production_role[0].name : null
}

# AWS CLI Commands for Package Manager Configuration
output "npm_login_command" {
  description = "AWS CLI command to configure npm authentication for team repository"
  value       = "aws codeartifact login --tool npm --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.team_dev.repository}"
}

output "pip_login_command" {
  description = "AWS CLI command to configure pip authentication for team repository"
  value       = "aws codeartifact login --tool pip --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.team_dev.repository}"
}

output "production_npm_login_command" {
  description = "AWS CLI command to configure npm authentication for production repository"
  value       = "aws codeartifact login --tool npm --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.production.repository}"
}

output "production_pip_login_command" {
  description = "AWS CLI command to configure pip authentication for production repository"
  value       = "aws codeartifact login --tool pip --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.production.repository}"
}

# Authorization Token Commands
output "authorization_token_command" {
  description = "AWS CLI command to get authorization token for CodeArtifact"
  value       = "aws codeartifact get-authorization-token --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --query authorizationToken --output text"
}

# Repository Management Commands
output "list_packages_team_command" {
  description = "AWS CLI command to list packages in team repository"
  value       = "aws codeartifact list-packages --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.team_dev.repository}"
}

output "list_packages_production_command" {
  description = "AWS CLI command to list packages in production repository"
  value       = "aws codeartifact list-packages --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.production.repository}"
}

# External Connection Setup Commands
output "setup_npm_external_connection_command" {
  description = "AWS CLI command to associate external connection for npm store repository"
  value       = var.enable_npm_external_connection ? "aws codeartifact associate-external-connection --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.npm_store.repository} --external-connection 'public:npmjs'" : "External connection for npm not enabled"
}

output "setup_pypi_external_connection_command" {
  description = "AWS CLI command to associate external connection for PyPI store repository"
  value       = var.enable_pypi_external_connection ? "aws codeartifact associate-external-connection --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.pypi_store.repository} --external-connection 'public:pypi'" : "External connection for PyPI not enabled"
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed CodeArtifact infrastructure"
  value = <<-EOT
    ## CodeArtifact Infrastructure Deployed Successfully!
    
    ### Next Steps:
    
    1. Configure external connections (run these commands):
       ${var.enable_npm_external_connection ? "aws codeartifact associate-external-connection --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.npm_store.repository} --external-connection 'public:npmjs'" : "# npm external connection not enabled"}
       ${var.enable_pypi_external_connection ? "aws codeartifact associate-external-connection --domain ${aws_codeartifact_domain.main.domain} --domain-owner ${data.aws_caller_identity.current.account_id} --repository ${aws_codeartifact_repository.pypi_store.repository} --external-connection 'public:pypi'" : "# PyPI external connection not enabled"}
    
    2. Configure package managers:
       ${self.npm_login_command}
       ${self.pip_login_command}
    
    3. Test package installation:
       npm install lodash
       pip install requests
    
    4. For production access, use:
       ${self.production_npm_login_command}
       ${self.production_pip_login_command}
    
    ### Important Notes:
    - External connections must be set up manually via AWS CLI as shown above
    - Authentication tokens expire and need to be refreshed periodically
    - Use the production repository for deployment pipelines
    - Monitor package usage and costs via CloudWatch
  EOT
}