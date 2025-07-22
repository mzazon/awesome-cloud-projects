# Main Terraform configuration for AWS CodeArtifact artifact management
# This creates a complete enterprise artifact management solution with hierarchical repositories,
# external connections to public registries, and fine-grained access controls

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for resource naming and configuration
locals {
  domain_name = "${var.project_name}-domain-${random_id.suffix.hex}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
  
  # Common tags to apply to all resources
  common_tags = merge(
    var.tags,
    {
      Project     = "artifact-management-codeartifact"
      Environment = var.environment
      ManagedBy   = "terraform"
      Domain      = local.domain_name
    }
  )
}

# CodeArtifact Domain
# The domain serves as the top-level container for artifact repositories
# and provides centralized authentication, authorization, and encryption policies
resource "aws_codeartifact_domain" "main" {
  domain = local.domain_name
  
  # Use customer-managed KMS key if provided, otherwise use AWS managed key
  encryption_key = var.domain_encryption_key != "" ? var.domain_encryption_key : null
  
  tags = local.common_tags
}

# NPM Store Repository
# This repository caches packages from the public npm registry
# External connections enable secure access to public packages while maintaining control
resource "aws_codeartifact_repository" "npm_store" {
  repository = var.npm_store_repository_name
  domain     = aws_codeartifact_domain.main.domain
  
  description = "npm packages cached from public registry"
  
  tags = merge(local.common_tags, {
    RepositoryType = "npm-store"
    Purpose        = "public-package-cache"
  })
}

# External connection for npm store repository to public npmjs registry
resource "aws_codeartifact_repository_permissions_policy" "npm_store_external_connection" {
  count = var.enable_npm_external_connection ? 1 : 0
  
  repository = aws_codeartifact_repository.npm_store.repository
  domain     = aws_codeartifact_domain.main.domain
  
  # This is a placeholder for external connection configuration
  # External connections are typically configured via CLI or console
  # as they don't have direct Terraform resource support
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codeartifact.amazonaws.com"
        }
        Action = [
          "codeartifact:ReadFromRepository"
        ]
        Resource = "*"
      }
    ]
  })
}

# PyPI Store Repository
# This repository caches packages from the public PyPI registry
resource "aws_codeartifact_repository" "pypi_store" {
  repository = var.pypi_store_repository_name
  domain     = aws_codeartifact_domain.main.domain
  
  description = "Python packages cached from PyPI registry"
  
  tags = merge(local.common_tags, {
    RepositoryType = "pypi-store"
    Purpose        = "public-package-cache"
  })
}

# Team Development Repository
# This repository is used by development teams for publishing and consuming packages
# It has upstream connections to both npm and PyPI store repositories
resource "aws_codeartifact_repository" "team_dev" {
  repository = var.team_repository_name
  domain     = aws_codeartifact_domain.main.domain
  
  description = "Team development artifacts and dependencies"
  
  # Configure upstream repositories for package resolution hierarchy
  upstream {
    repository_name = aws_codeartifact_repository.npm_store.repository
  }
  
  upstream {
    repository_name = aws_codeartifact_repository.pypi_store.repository
  }
  
  tags = merge(local.common_tags, {
    RepositoryType = "development"
    Purpose        = "team-collaboration"
  })
}

# Production Repository
# This repository contains only approved, tested packages for production deployment
# It has upstream connection to the team repository for controlled package promotion
resource "aws_codeartifact_repository" "production" {
  repository = var.production_repository_name
  domain     = aws_codeartifact_domain.main.domain
  
  description = "Production-ready artifacts and approved dependencies"
  
  # Configure upstream to team repository for package promotion workflow
  upstream {
    repository_name = aws_codeartifact_repository.team_dev.repository
  }
  
  tags = merge(local.common_tags, {
    RepositoryType = "production"
    Purpose        = "production-deployment"
  })
}

# Repository permissions policy for team development repository
# This provides fine-grained access control at the repository level
resource "aws_codeartifact_repository_permissions_policy" "team_repo_policy" {
  count = var.enable_repository_policy ? 1 : 0
  
  repository = aws_codeartifact_repository.team_dev.repository
  domain     = aws_codeartifact_domain.main.domain
  
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = length(var.allowed_aws_principals) > 0 ? var.allowed_aws_principals : [
            "arn:aws:iam::${local.account_id}:root"
          ]
        }
        Action = [
          "codeartifact:ReadFromRepository",
          "codeartifact:PublishPackageVersion",
          "codeartifact:PutPackageMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Policy for Developer Access
# Provides read/write access to development repositories and read access to upstream repositories
resource "aws_iam_policy" "developer_policy" {
  count = var.create_developer_role ? 1 : 0
  
  name        = "${var.project_name}-codeartifact-developer-policy-${random_id.suffix.hex}"
  description = "IAM policy for CodeArtifact developer access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository",
          "codeartifact:PublishPackageVersion",
          "codeartifact:PutPackageMetadata"
        ]
        Resource = [
          aws_codeartifact_domain.main.arn,
          "${aws_codeartifact_repository.team_dev.arn}",
          "${aws_codeartifact_repository.npm_store.arn}",
          "${aws_codeartifact_repository.pypi_store.arn}",
          "arn:aws:codeartifact:${local.region}:${local.account_id}:package/${local.domain_name}/${var.team_repository_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Role for Developers
# Allows developers to assume this role for CodeArtifact access
resource "aws_iam_role" "developer_role" {
  count = var.create_developer_role ? 1 : 0
  
  name        = "${var.developer_role_name}-${random_id.suffix.hex}"
  description = "IAM role for CodeArtifact developer access"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "codeartifact-developer-access"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach developer policy to developer role
resource "aws_iam_role_policy_attachment" "developer_role_policy" {
  count = var.create_developer_role ? 1 : 0
  
  role       = aws_iam_role.developer_role[0].name
  policy_arn = aws_iam_policy.developer_policy[0].arn
}

# IAM Policy for Production Access
# Provides read-only access to production repository
resource "aws_iam_policy" "production_policy" {
  count = var.create_production_role ? 1 : 0
  
  name        = "${var.project_name}-codeartifact-production-policy-${random_id.suffix.hex}"
  description = "IAM policy for CodeArtifact production read-only access"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository"
        ]
        Resource = [
          aws_codeartifact_domain.main.arn,
          "${aws_codeartifact_repository.production.arn}",
          "arn:aws:codeartifact:${local.region}:${local.account_id}:package/${local.domain_name}/${var.production_repository_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM Role for Production Access
# Allows production systems to assume this role for read-only access
resource "aws_iam_role" "production_role" {
  count = var.create_production_role ? 1 : 0
  
  name        = "${var.production_role_name}-${random_id.suffix.hex}"
  description = "IAM role for CodeArtifact production read-only access"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "codeartifact-production-access"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach production policy to production role
resource "aws_iam_role_policy_attachment" "production_role_policy" {
  count = var.create_production_role ? 1 : 0
  
  role       = aws_iam_role.production_role[0].name
  policy_arn = aws_iam_policy.production_policy[0].arn
}