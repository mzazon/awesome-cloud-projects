# Terraform version constraints and provider requirements for GitOps workflow
# This configuration ensures compatibility with the required providers and versions

terraform {
  # Minimum Terraform version required for EKS and advanced features
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # AWS provider for managing AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Kubernetes provider for ArgoCD installation
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }

    # Helm provider for installing Helm charts (ArgoCD, AWS Load Balancer Controller)
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }

    # TLS provider for generating certificates if needed
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# AWS provider configuration
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Project     = "GitOps-EKS-ArgoCD"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "gitops-workflows-eks-argocd-codecommit"
    }
  }
}

# Kubernetes provider configuration
# This provider is configured after EKS cluster creation
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Helm provider configuration
# This provider is configured after EKS cluster creation for installing Helm charts
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}