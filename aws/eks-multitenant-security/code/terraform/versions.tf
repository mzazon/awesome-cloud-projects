# Terraform and Provider Version Requirements
# This file specifies the required versions for Terraform and all providers used in this configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    # AWS provider for managing AWS resources (IAM roles, EKS access entries)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Kubernetes provider for managing Kubernetes resources
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  # AWS provider will use the default profile and region from AWS CLI configuration
  # or environment variables (AWS_PROFILE, AWS_REGION)
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "EKS-Multi-Tenant-Security"
      Recipe      = "eks-multi-tenant-cluster-security-namespace-isolation"
      ManagedBy   = "Terraform"
    }
  }
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  # Configure the Kubernetes provider to connect to the existing EKS cluster
  host                   = data.aws_eks_cluster.existing.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.existing.token

  # Optional: Configure exec-based authentication for long-running operations
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
      "--region",
      data.aws_region.current.name
    ]
  }
}