# ============================================================================
# Terraform and Provider Version Requirements
# ============================================================================
# This file defines the minimum required versions for Terraform and providers
# used in the Low-Latency Edge Applications with AWS Wavelength and CloudFront recipe.
# ============================================================================

terraform {
  # Specify minimum Terraform version
  required_version = ">= 1.6.0"

  # Required providers with version constraints
  required_providers {
    # AWS Provider for all AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Template Provider for user data scripts (if needed)
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }

  # Backend configuration (uncomment and configure for remote state)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "edge-applications/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# ============================================================================
# AWS Provider Configuration
# ============================================================================

provider "aws" {
  # Default tags applied to all resources
  default_tags {
    tags = {
      Project           = "edge-applications-wavelength-cloudfront"
      Terraform         = "true"
      Recipe            = "building-low-latency-edge-applications-with-aws-wavelength-and-cloudfront"
      TerraformVersion  = "~> 1.6"
      AWSProviderVersion = "~> 5.0"
    }
  }

  # AWS provider features and configuration
  # Note: Ensure your AWS credentials are configured via:
  # - AWS CLI: aws configure
  # - Environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  # - IAM roles (recommended for EC2/ECS)
  # - AWS SSO profiles
}

# ============================================================================
# Random Provider Configuration
# ============================================================================

provider "random" {
  # No specific configuration required for random provider
}

# ============================================================================
# Template Provider Configuration (Optional)
# ============================================================================

provider "template" {
  # Template provider for processing user data and configuration files
  # This provider is marked as deprecated in favor of Terraform's built-in
  # templatefile() function, but included for compatibility
}

# ============================================================================
# Provider Version Information
# ============================================================================

# The following provider versions are tested and compatible:
#
# AWS Provider v5.x features used in this configuration:
# - aws_ec2_carrier_gateway (Wavelength networking)
# - aws_cloudfront_origin_access_control (OAC for S3)
# - Enhanced CloudFront distribution configuration
# - Latest EC2 instance types and configurations
# - Advanced VPC and networking features
# - Modern IAM policy structures
# - CloudWatch monitoring enhancements
#
# Terraform v1.6+ features used:
# - Enhanced validation blocks
# - Improved for_each and count expressions
# - Better error handling and diagnostics
# - Template functions and expressions
#
# Compatibility Notes:
# - AWS Provider 5.x includes breaking changes from 4.x
# - Ensure AWS CLI is updated to latest version
# - Some Wavelength features require specific AWS regions
# - CloudFront OAC requires AWS Provider 4.60.0 or later

# ============================================================================
# Terraform Configuration Best Practices
# ============================================================================

# 1. State Management:
#    - Use remote state (S3 + DynamoDB) for team collaboration
#    - Enable state locking to prevent concurrent modifications
#    - Use separate state files for different environments
#
# 2. Provider Versioning:
#    - Pin provider versions to prevent unexpected changes
#    - Use pessimistic constraints (~> 5.0) for patch updates
#    - Test provider upgrades in development environments first
#
# 3. Module Organization:
#    - Consider breaking large configurations into modules
#    - Use consistent naming conventions across modules
#    - Document module inputs, outputs, and dependencies
#
# 4. Security Considerations:
#    - Store sensitive values in AWS Secrets Manager or SSM
#    - Use IAM roles instead of access keys when possible
#    - Enable CloudTrail for Terraform API call auditing
#
# 5. Performance Optimization:
#    - Use data sources efficiently to avoid unnecessary API calls
#    - Leverage depends_on only when implicit dependencies are insufficient
#    - Consider using parallel execution for independent resources

# ============================================================================
# Provider Feature Requirements
# ============================================================================

# This configuration requires the following AWS services and features:
#
# Regional Services:
# - Amazon VPC (Virtual Private Cloud)
# - Amazon EC2 (Elastic Compute Cloud)
# - Amazon S3 (Simple Storage Service)
# - Amazon CloudFront (Content Delivery Network)
# - Amazon Route 53 (DNS Service)
# - AWS IAM (Identity and Access Management)
# - Amazon CloudWatch (Monitoring and Logging)
# - AWS Systems Manager (Session Manager)
#
# Edge Computing Services:
# - AWS Wavelength (5G Edge Computing)
# - Carrier Gateways (Mobile Network Connectivity)
#
# Prerequisites:
# - AWS account with appropriate permissions
# - Wavelength Zone access (requires carrier partnership)
# - Domain name registration (optional, for custom DNS)
#
# Supported Regions:
# - Wavelength Zones are available in select metropolitan areas
# - Check AWS documentation for current Wavelength Zone availability
# - CloudFront is a global service (metrics reported from us-east-1)

# ============================================================================
# Terraform Initialization
# ============================================================================

# To initialize this Terraform configuration:
#
# 1. Install Terraform (minimum version 1.6.0):
#    - Download from: https://www.terraform.io/downloads
#    - Verify installation: terraform version
#
# 2. Configure AWS credentials:
#    - AWS CLI: aws configure
#    - Or set environment variables:
#      export AWS_ACCESS_KEY_ID="your-access-key"
#      export AWS_SECRET_ACCESS_KEY="your-secret-key"
#      export AWS_DEFAULT_REGION="your-region"
#
# 3. Initialize Terraform:
#    terraform init
#
# 4. Validate configuration:
#    terraform validate
#
# 5. Plan deployment:
#    terraform plan
#
# 6. Apply configuration:
#    terraform apply
#
# 7. Clean up resources:
#    terraform destroy

# ============================================================================
# Upgrade Path and Migration Notes
# ============================================================================

# When upgrading provider versions:
#
# 1. Review provider changelogs and breaking changes
# 2. Update version constraints in this file
# 3. Run terraform init -upgrade
# 4. Test in development environment first
# 5. Update any deprecated resource arguments
# 6. Validate with terraform plan before applying
#
# AWS Provider 4.x to 5.x Migration:
# - Review AWS provider upgrade guide
# - Some resource arguments have changed names
# - New authentication flow for assume role
# - Enhanced default tags functionality
#
# Terraform Version Upgrades:
# - Check language feature compatibility
# - Review state file format changes
# - Update CI/CD pipeline Terraform versions
# - Test complex expressions and functions