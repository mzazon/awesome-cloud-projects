# versions.tf
# Terraform and provider version constraints for GCP multiplayer gaming infrastructure

terraform {
  required_version = ">= 1.0"
  
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
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider to connect to GKE cluster
provider "kubernetes" {
  host                   = "https://${google_container_cluster.game_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.game_cluster.master_auth.0.cluster_ca_certificate)
}

# Configure Helm provider for installing Agones
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.game_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.game_cluster.master_auth.0.cluster_ca_certificate)
  }
}

# Data source for Google Cloud client configuration
data "google_client_config" "default" {}