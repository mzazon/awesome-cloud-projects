# =============================================================================
# Terraform and Provider Version Constraints
# =============================================================================
# This file defines the required Terraform version and provider versions
# for the Enterprise API Integration with AgentCore Gateway infrastructure.
# These constraints ensure compatibility and reproducible deployments.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    # AWS Provider for core AWS services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Archive provider for Lambda function packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    
    # Local provider for managing local files
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
  
  # Backend configuration placeholder
  # Uncomment and configure based on your state management requirements
  /*
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "api-integration-agentcore-gateway/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
  */
}

# =============================================================================
# Provider Configuration Details
# =============================================================================

# AWS Provider Version Information
# - Version 5.x includes the latest AWS service features
# - Supports all services used in this configuration:
#   * Lambda (with latest runtime support)
#   * Step Functions (with advanced logging and encryption)
#   * API Gateway (with detailed monitoring)
#   * IAM (with enhanced policy support)
#   * CloudWatch (with log insights and metrics)
#   * Amazon Bedrock (for AgentCore Gateway integration)

# Archive Provider Version Information
# - Version 2.4+ includes improved zip file handling
# - Supports source code hash generation for Lambda deployment detection
# - Handles binary files and large archives efficiently

# Random Provider Version Information
# - Version 3.5+ includes improved randomness algorithms
# - Used for generating unique resource names and identifiers
# - Provides consistent random values across Terraform runs

# Local Provider Version Information
# - Version 2.4+ includes enhanced file handling capabilities
# - Used for generating configuration files and OpenAPI specifications
# - Supports complex file templating and content generation

# =============================================================================
# Compatibility and Migration Notes
# =============================================================================

# Terraform Version Requirements:
# - Minimum version 1.5 required for:
#   * Import blocks
#   * Advanced variable validation
#   * Improved provider configuration
#   * Enhanced state management

# AWS Provider Migration Notes:
# - If upgrading from AWS Provider 4.x:
#   * Review IAM policy changes
#   * Check Lambda runtime deprecations
#   * Validate Step Functions logging configuration
#   * Update API Gateway integration syntax if needed

# Breaking Changes to Monitor:
# - Lambda runtime end-of-life announcements
# - Step Functions API changes
# - API Gateway deprecation notices
# - CloudWatch Logs retention policy updates

# =============================================================================
# Feature Requirements by Provider Version
# =============================================================================

# AWS Provider 5.x Features Used:
# - aws_lambda_function with advanced logging_config
# - aws_sfn_state_machine with enhanced tracing and logging
# - aws_api_gateway_* resources with improved integration options
# - aws_cloudwatch_log_group with retention and encryption
# - aws_iam_role and policies with condition improvements

# Archive Provider 2.x Features Used:
# - data.archive_file with source_code_hash generation
# - Improved compression and file handling
# - Support for large deployment packages

# Random Provider 3.x Features Used:
# - random_id with enhanced entropy
# - Consistent random generation across plan/apply cycles
# - Improved seed handling for reproducible randomness

# Local Provider 2.x Features Used:
# - local_file with content generation
# - Template processing for configuration files
# - File permission and encoding handling

# =============================================================================
# Security and Compliance Considerations
# =============================================================================

# Provider Security Features:
# - AWS Provider supports assume role configurations
# - All providers sign their releases with GPG
# - Version constraints prevent supply chain attacks
# - Provider checksums verified during download

# Recommended Practices:
# - Pin provider versions in production environments
# - Review provider changelogs before upgrades
# - Test provider upgrades in development environments
# - Monitor security advisories for all providers

# Compliance Requirements:
# - All providers are from HashiCorp verified sources
# - Version constraints ensure reproducible deployments
# - Provider configuration supports audit logging
# - State encryption supported by all providers

# =============================================================================
# Performance and Optimization Notes
# =============================================================================

# Provider Performance:
# - AWS Provider 5.x includes performance improvements
# - Parallel resource creation where dependencies allow
# - Improved error handling and retry logic
# - Better handling of eventual consistency

# Resource Creation Optimization:
# - Providers support bulk operations where possible
# - Dependency resolution optimized for parallel execution
# - Provider caching reduces redundant API calls
# - Connection pooling for improved throughput

# State Management:
# - Providers support partial state refresh
# - Improved state locking mechanisms
# - Better handling of concurrent operations
# - Enhanced state file encryption options

# =============================================================================
# Development and Testing Considerations
# =============================================================================

# Development Environment:
# - Use same provider versions as production
# - Test with provider beta versions for early feedback
# - Validate provider upgrade paths
# - Monitor deprecation warnings

# CI/CD Integration:
# - Cache provider downloads for faster builds
# - Use terraform init -upgrade judiciously
# - Validate provider checksums in pipelines
# - Test with multiple provider versions if needed

# Testing Strategies:
# - Unit tests with terraform validate
# - Integration tests with real provider resources
# - Performance tests with large deployments
# - Security tests with provider configurations

# =============================================================================
# Future Upgrade Path
# =============================================================================

# Planned Upgrades:
# - Monitor AWS Provider 6.x release timeline
# - Track Terraform 2.x development progress
# - Review provider consolidation efforts
# - Plan for potential breaking changes

# Upgrade Strategy:
# - Test upgrades in development environments first
# - Review all breaking changes and migration guides
# - Update configuration for deprecated features
# - Validate all resources after provider upgrades

# Long-term Maintenance:
# - Regular provider version reviews (quarterly)
# - Security patch monitoring and application
# - Performance optimization with new provider features
# - Compliance updates as regulations change