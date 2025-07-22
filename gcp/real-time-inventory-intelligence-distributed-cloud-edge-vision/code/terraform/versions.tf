# Terraform and provider version constraints for inventory intelligence solution
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
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
  zone    = var.zone
}

# Configure the Google Cloud Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure Kubernetes provider for edge cluster management
provider "kubernetes" {
  host                   = "https://${google_container_cluster.edge_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.edge_cluster.master_auth.0.cluster_ca_certificate)
}

# Get current client configuration
data "google_client_config" "default" {}