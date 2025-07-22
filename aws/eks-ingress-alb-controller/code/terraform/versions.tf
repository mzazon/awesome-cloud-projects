# ============================================================================
# AWS EKS Ingress Controllers with AWS Load Balancer Controller
# Terraform Configuration - Provider Versions and Requirements
# ============================================================================

terraform {
  # Specify minimum Terraform version required
  required_version = ">= 1.5.0"

  # Configure required providers with version constraints
  required_providers {
    # AWS Provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }

    # Kubernetes Provider for managing Kubernetes resources
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }

    # Helm Provider for managing Helm charts
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }

    # TLS Provider for certificate operations
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Time Provider for time-based resources
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }

    # Random Provider for generating random values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configuration (uncomment and modify as needed)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "eks-ingress-controller/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # Experiment features (if needed)
  # experiments = []
}

# ============================================================================
# Provider Configuration Details
# ============================================================================

# AWS Provider - Official HashiCorp AWS provider
# Documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
# Release Notes: https://github.com/hashicorp/terraform-provider-aws/releases
# 
# Version ~> 5.0 provides:
# - Support for latest AWS services and features
# - Enhanced EKS resource management
# - Improved load balancer and target group configurations
# - Advanced IAM and security features
# - Better error handling and validation

# Kubernetes Provider - Official HashiCorp Kubernetes provider
# Documentation: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
# Release Notes: https://github.com/hashicorp/terraform-provider-kubernetes/releases
#
# Version ~> 2.23 provides:
# - Support for Kubernetes 1.28+ features
# - Enhanced manifest resource support
# - Improved ingress v1 resource management
# - Better service account and RBAC handling
# - Support for custom resource definitions (CRDs)

# Helm Provider - Official HashiCorp Helm provider
# Documentation: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
# Release Notes: https://github.com/hashicorp/terraform-provider-helm/releases
#
# Version ~> 2.11 provides:
# - Support for Helm 3.x chart installations
# - Enhanced chart dependency management
# - Improved error handling for chart installations
# - Better integration with Kubernetes authentication
# - Support for OCI registry chart sources

# TLS Provider - Official HashiCorp TLS provider
# Documentation: https://registry.terraform.io/providers/hashicorp/tls/latest/docs
# Release Notes: https://github.com/hashicorp/terraform-provider-tls/releases
#
# Version ~> 4.0 provides:
# - Certificate generation and validation
# - OIDC thumbprint calculation for EKS IRSA
# - Enhanced cryptographic operations
# - Support for modern TLS protocols
# - Certificate chain validation

# Random Provider - Official HashiCorp Random provider
# Documentation: https://registry.terraform.io/providers/hashicorp/random/latest/docs
# Release Notes: https://github.com/hashicorp/terraform-provider-random/releases
#
# Version ~> 3.5 provides:
# - Secure random string generation
# - UUID and password generation
# - Consistent random values across plan/apply cycles
# - Entropy source configuration
# - Deterministic random values with seed support

# ============================================================================
# Version Compatibility Matrix
# ============================================================================

# Terraform Core: >= 1.5.0
# - Required for enhanced variable validation
# - Support for improved state management
# - Better error reporting and debugging
# - Enhanced module composition features

# AWS Provider: ~> 5.0
# - EKS: Full support for managed node groups and Fargate
# - ELBv2: Application Load Balancer and Network Load Balancer support
# - IAM: Enhanced IRSA (IAM Roles for Service Accounts) support
# - ACM: Certificate Manager integration
# - S3: Enhanced bucket management and security features

# Kubernetes Provider: ~> 2.23
# - Kubernetes API: Support for v1.28+ clusters
# - Ingress: Full networking.k8s.io/v1 ingress support
# - Manifest: Support for custom Kubernetes resources
# - ServiceAccount: Enhanced IRSA annotation support

# Helm Provider: ~> 2.11
# - Helm: Support for Helm 3.x charts
# - Repositories: OCI and traditional repository support
# - Charts: Enhanced dependency resolution
# - Values: Improved value merging and templating

# ============================================================================
# Important Notes
# ============================================================================

# 1. Provider Version Constraints:
#    - Use pessimistic version constraints (~>) to allow patch updates
#    - This ensures security fixes while preventing breaking changes
#    - Update providers regularly to benefit from bug fixes and new features

# 2. Terraform Version:
#    - Minimum version 1.5.0 required for enhanced validation features
#    - Consider using latest stable version for best experience
#    - Update Terraform regularly for security and feature improvements

# 3. Backend Configuration:
#    - Uncomment and configure backend for team collaboration
#    - Use S3 backend with DynamoDB for state locking
#    - Enable encryption for sensitive state data

# 4. Provider Authentication:
#    - AWS Provider: Uses AWS CLI credentials, IAM roles, or environment variables
#    - Kubernetes Provider: Uses EKS cluster authentication via AWS provider
#    - Helm Provider: Uses Kubernetes provider authentication

# 5. State Management:
#    - Store state in shared location for team environments
#    - Use state locking to prevent concurrent modifications
#    - Regular state backups recommended for production environments

# 6. Security Considerations:
#    - Never commit credentials to version control
#    - Use IAM roles with least privilege principle
#    - Enable provider-level security features (encryption, logging)
#    - Regular security audits of provider versions and configurations

# ============================================================================
# Upgrade Path
# ============================================================================

# When upgrading providers:
# 1. Review provider changelog for breaking changes
# 2. Test upgrades in development environment first
# 3. Update version constraints gradually
# 4. Run `terraform plan` to review changes before applying
# 5. Consider using `terraform state backup` before major upgrades

# Example upgrade process:
# 1. Update versions.tf with new version constraints
# 2. Run: terraform init -upgrade
# 3. Run: terraform plan
# 4. Review changes and test thoroughly
# 5. Run: terraform apply (after approval)

# ============================================================================
# Additional Provider Features
# ============================================================================

# AWS Provider Features Used:
# - Data sources for EKS cluster information
# - IAM policy and role management
# - S3 bucket creation and configuration
# - ACM certificate management
# - ELB service account data source

# Kubernetes Provider Features Used:
# - Namespace creation and management
# - Service account with annotations
# - Deployment and service resources
# - Ingress v1 resources with advanced annotations
# - Custom resource manifests for IngressClass

# Helm Provider Features Used:
# - Chart installation from official repositories
# - Value customization through set blocks
# - Dependency management for chart installations
# - Integration with Kubernetes authentication

# TLS Provider Features Used:
# - Certificate data extraction for OIDC
# - Thumbprint calculation for identity providers
# - Certificate chain validation

# Random Provider Features Used:
# - Unique suffix generation for resource naming
# - Consistent random values across deployments
# - Secure random string generation