# Terraform and provider version constraints for EKS hybrid monitoring infrastructure
# This ensures compatibility and stability across deployments

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.74.0"
    }
    
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.1.0, != 4.0.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }
}

# AWS Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = "EKS-Hybrid-Monitoring"
      ManagedBy     = "Terraform"
      CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
      Owner         = var.owner
    }
  }
}

# TLS Provider for certificate handling
provider "tls" {}

# Random provider for unique resource naming
provider "random" {}

# Kubernetes provider for EKS cluster management
provider "kubernetes" {
  host                   = aws_eks_cluster.hybrid_monitoring.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.hybrid_monitoring.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.hybrid_monitoring.name]
  }
}