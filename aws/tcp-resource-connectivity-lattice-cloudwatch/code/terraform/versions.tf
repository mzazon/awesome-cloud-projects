# =========================================================================
# Provider and Terraform Version Requirements
# =========================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS Provider for core AWS services
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Random Provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Optional: Configure backend for state management
  # Uncomment and configure as needed for your environment
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "vpc-lattice-tcp-connectivity/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-locks"
  # }
}

# =========================================================================
# Provider Configuration
# =========================================================================

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Terraform   = "true"
      Project     = "VPCLattice-TCP-Connectivity"
      Environment = "Development"
      ManagedBy   = "Terraform"
      Repository  = "recipes/aws/tcp-resource-connectivity-lattice-cloudwatch"
      Recipe      = "TCP Resource Connectivity with VPC Lattice and CloudWatch"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    }
  }

  # Optional: Assume role configuration for cross-account deployments
  # assume_role {
  #   role_arn     = "arn:aws:iam::ACCOUNT-ID:role/TerraformExecutionRole"
  #   session_name = "TerraformVPCLatticeDeployment"
  # }
}

# Configure the Random Provider
provider "random" {}

# =========================================================================
# Local Values for Configuration
# =========================================================================

locals {
  # Common tags for all resources
  common_tags = merge(
    var.common_tags,
    {
      DeploymentTimestamp = formatdate("YYYY-MM-DD'T'hh:mm:ssZ", timestamp())
      TerraformVersion    = "1.0+"
      AWSProviderVersion  = "5.0+"
    }
  )

  # Resource naming convention
  name_prefix = "vpc-lattice-tcp"
  
  # Region-specific configurations
  availability_zones = data.aws_availability_zones.available.names
  
  # VPC Lattice service network configuration
  service_network_config = {
    name      = "${local.name_prefix}-service-network"
    auth_type = "AWS_IAM"
  }

  # Database configuration
  database_config = {
    engine         = "mysql"
    engine_version = var.mysql_engine_version
    port          = var.mysql_port
    username      = var.db_username
  }

  # Monitoring configuration
  monitoring_config = {
    dashboard_name = "VPCLattice-TCP-Connectivity-Monitoring"
    alarm_prefix   = "VPCLattice-TCP"
  }
}

# =========================================================================
# Data Sources for Provider Information
# =========================================================================

# Get available availability zones in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get current AWS partition (aws, aws-cn, aws-us-gov)
data "aws_partition" "current" {}

# =========================================================================
# Provider Feature Compatibility
# =========================================================================

# Terraform and Provider version compatibility matrix:
# 
# | Terraform Version | AWS Provider Version | VPC Lattice Support | Features Supported |
# |-------------------|---------------------|---------------------|-------------------|
# | >= 1.0.0          | >= 5.0.0           | Full Support        | All resources     |
# | >= 0.15.0         | >= 4.50.0          | Limited Support     | Basic resources   |
# | < 0.15.0          | Any                 | Not Supported       | None              |
#
# VPC Lattice Resources Supported:
# - aws_vpclattice_service_network
# - aws_vpclattice_service
# - aws_vpclattice_target_group
# - aws_vpclattice_listener
# - aws_vpclattice_service_network_service_association
# - aws_vpclattice_service_network_vpc_association
# - aws_vpclattice_target_group_attachment
#
# Required IAM Permissions for Deployment:
# - vpc-lattice:*
# - rds:*
# - ec2:Describe*
# - ec2:CreateSecurityGroup
# - ec2:AuthorizeSecurityGroupIngress
# - iam:CreateRole
# - iam:AttachRolePolicy
# - iam:PassRole
# - cloudwatch:*
# - logs:*

# =========================================================================
# Provider Configuration Validation
# =========================================================================

# Validate that required AWS services are available in the region
data "aws_region" "current" {}

# Check if VPC Lattice is available in the current region
# VPC Lattice is available in most AWS regions, but may have limitations
# in some regions or partitions
locals {
  supported_regions = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
    "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
    "ap-south-1", "ca-central-1", "sa-east-1"
  ]
  
  is_supported_region = contains(local.supported_regions, data.aws_region.current.name)
}

# Output warning if region might not support VPC Lattice
output "region_support_warning" {
  value = local.is_supported_region ? null : "Warning: VPC Lattice support in ${data.aws_region.current.name} should be verified. This region may have limited support."
}