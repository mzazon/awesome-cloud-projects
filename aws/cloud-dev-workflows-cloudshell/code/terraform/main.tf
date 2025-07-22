# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Generate unique names with random suffix
  repository_name = var.repository_name != "" ? var.repository_name : "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  iam_user_name   = var.iam_user_name != "" ? var.iam_user_name : "${var.project_name}-developer-${random_id.suffix.hex}"

  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "cloudshell-codecommit"
      ManagedBy   = "terraform"
      TeamSize    = tostring(var.team_size)
    },
    var.additional_tags
  )
}

# ============================================================================
# CODECOMMIT REPOSITORY
# ============================================================================

# CodeCommit repository for version control
resource "aws_codecommit_repository" "main" {
  repository_name   = local.repository_name
  repository_description = var.repository_description

  tags = merge(local.common_tags, {
    Name        = local.repository_name
    Type        = "repository"
    Description = "Git repository for cloud-based development workflow"
  })
}

# ============================================================================
# IAM RESOURCES FOR CODECOMMIT ACCESS
# ============================================================================

# IAM policy for CodeCommit access
resource "aws_iam_policy" "codecommit_access" {
  name        = "${local.repository_name}-codecommit-access"
  path        = "/"
  description = "IAM policy for CodeCommit repository access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codecommit:BatchGet*",
          "codecommit:BatchDescribe*",
          "codecommit:Describe*",
          "codecommit:EvaluatePullRequestApprovalRules",
          "codecommit:Get*",
          "codecommit:List*",
          "codecommit:GitPull"
        ]
        Resource = aws_codecommit_repository.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GitPush",
          "codecommit:Merge*",
          "codecommit:Put*",
          "codecommit:Post*",
          "codecommit:Create*",
          "codecommit:Update*",
          "codecommit:Test*",
          "codecommit:Tag*",
          "codecommit:Untag*"
        ]
        Resource = aws_codecommit_repository.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:ListRepositories",
          "codecommit:ListRepositoriesForApprovalRuleTemplate"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-codecommit-access"
    Type = "iam-policy"
  })
}

# IAM policy for CloudShell access
resource "aws_iam_policy" "cloudshell_access" {
  name        = "${local.repository_name}-cloudshell-access"
  path        = "/"
  description = "IAM policy for AWS CloudShell access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudshell:CreateEnvironment",
          "cloudshell:CreateSession",
          "cloudshell:DeleteEnvironment",
          "cloudshell:DescribeEnvironment",
          "cloudshell:GetFileDownloadUrls",
          "cloudshell:GetFileUploadUrls",
          "cloudshell:PutCredentials",
          "cloudshell:StartEnvironment",
          "cloudshell:StopEnvironment"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-cloudshell-access"
    Type = "iam-policy"
  })
}

# IAM group for developers
resource "aws_iam_group" "developers" {
  name = "${local.repository_name}-developers"
  path = "/"

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-developers"
    Type = "iam-group"
  })
}

# Attach CodeCommit policy to developers group
resource "aws_iam_group_policy_attachment" "developers_codecommit" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.codecommit_access.arn
}

# Attach CloudShell policy to developers group
resource "aws_iam_group_policy_attachment" "developers_cloudshell" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.cloudshell_access.arn
}

# Optional IAM user for testing
resource "aws_iam_user" "developer" {
  count = var.create_iam_user ? 1 : 0
  name  = local.iam_user_name
  path  = "/"

  tags = merge(local.common_tags, {
    Name = local.iam_user_name
    Type = "iam-user"
    Role = "developer"
  })
}

# Add user to developers group
resource "aws_iam_group_membership" "developers" {
  count = var.create_iam_user ? 1 : 0
  name  = "${local.repository_name}-developers-membership"

  users = [aws_iam_user.developer[0].name]
  group = aws_iam_group.developers.name
}

# Generate Git credentials for the IAM user
resource "aws_iam_service_specific_credential" "git_credentials" {
  count        = var.create_iam_user ? 1 : 0
  user_name    = aws_iam_user.developer[0].name
  service_name = "codecommit.amazonaws.com"
}

# ============================================================================
# CLOUDWATCH RESOURCES FOR MONITORING
# ============================================================================

# CloudWatch Log Group for development activities
resource "aws_cloudwatch_log_group" "development_logs" {
  name              = "/aws/development/${local.repository_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "/aws/development/${local.repository_name}"
    Type = "cloudwatch-log-group"
  })
}

# ============================================================================
# SYSTEMS MANAGER PARAMETERS FOR CONFIGURATION
# ============================================================================

# Store repository information in Systems Manager Parameter Store
resource "aws_ssm_parameter" "repository_name" {
  name        = "/${var.project_name}/${var.environment}/codecommit/repository-name"
  description = "CodeCommit repository name for development workflow"
  type        = "String"
  value       = aws_codecommit_repository.main.repository_name

  tags = merge(local.common_tags, {
    Name = "repository-name"
    Type = "ssm-parameter"
  })
}

resource "aws_ssm_parameter" "repository_url" {
  name        = "/${var.project_name}/${var.environment}/codecommit/repository-url"
  description = "CodeCommit repository HTTPS clone URL"
  type        = "String"
  value       = aws_codecommit_repository.main.clone_url_http

  tags = merge(local.common_tags, {
    Name = "repository-url"
    Type = "ssm-parameter"
  })
}

resource "aws_ssm_parameter" "cloudshell_region" {
  name        = "/${var.project_name}/${var.environment}/cloudshell/region"
  description = "AWS region for CloudShell environment"
  type        = "String"
  value       = var.aws_region

  tags = merge(local.common_tags, {
    Name = "cloudshell-region"
    Type = "ssm-parameter"
  })
}

# ============================================================================
# LAMBDA FUNCTION FOR REPOSITORY INITIALIZATION
# ============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.repository_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-lambda-execution-role"
    Type = "iam-role"
  })
}

# IAM policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${local.repository_name}-lambda-policy"
  description = "IAM policy for repository initialization Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:BatchGet*",
          "codecommit:Get*",
          "codecommit:Describe*",
          "codecommit:List*",
          "codecommit:GitPush",
          "codecommit:CreateCommit",
          "codecommit:CreateBranch",
          "codecommit:PutFile"
        ]
        Resource = aws_codecommit_repository.main.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-lambda-policy"
    Type = "iam-policy"
  })
}

# Attach policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "repo_initializer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      repository_name = aws_codecommit_repository.main.repository_name
      project_name    = var.project_name
      environment     = var.environment
    })
    filename = "index.py"
  }
}

# Lambda function for repository initialization
resource "aws_lambda_function" "repo_initializer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.repository_name}-initializer"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      REPOSITORY_NAME = aws_codecommit_repository.main.repository_name
      REPOSITORY_ARN  = aws_codecommit_repository.main.arn
      PROJECT_NAME    = var.project_name
      ENVIRONMENT     = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.repository_name}-initializer"
    Type = "lambda-function"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_codecommit_repository.main,
    data.archive_file.lambda_zip
  ]
}

# ============================================================================
# OUTPUTS CONFIGURATION
# ============================================================================

# Export repository information for use by other resources or modules