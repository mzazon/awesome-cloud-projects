# Terraform version requirements and provider configuration
# for Privacy-Preserving Analytics with Confidential GKE and BigQuery

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure Kubernetes provider for cluster management
provider "kubernetes" {
  host                   = "https://${google_container_cluster.confidential_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.confidential_cluster.master_auth.0.cluster_ca_certificate)
}

# Configure Helm provider for application deployment
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.confidential_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.confidential_cluster.master_auth.0.cluster_ca_certificate)
  }
}

# Data source for client configuration
data "google_client_config" "default" {}