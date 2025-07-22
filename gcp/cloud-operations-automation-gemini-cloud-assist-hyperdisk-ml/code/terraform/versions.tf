# Terraform version and provider requirements for Cloud Operations Automation
# with Gemini Cloud Assist and Hyperdisk ML

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
      version = "~> 2.24"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Kubernetes provider configuration (configured after GKE cluster creation)
provider "kubernetes" {
  host                   = "https://${google_container_cluster.ml_ops_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.ml_ops_cluster.master_auth.0.cluster_ca_certificate)
}

# Data source for Google Cloud client configuration
data "google_client_config" "default" {}