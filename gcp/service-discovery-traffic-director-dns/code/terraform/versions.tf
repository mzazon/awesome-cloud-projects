# ==============================================================================
# Service Discovery with Traffic Director and Cloud DNS - Version Constraints
# ==============================================================================

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
  }
  
  # Optional: Configure remote state backend
  # Uncomment and customize the backend configuration below for production use
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/service-discovery-traffic-director-dns"
  # }
}