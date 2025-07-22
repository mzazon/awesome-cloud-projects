# versions.tf - Provider requirements and version constraints

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "multi-region-event-replication"
      Purpose     = "eventbridge-global-replication"
      ManagedBy   = "terraform"
    }
  }
}

# Configure the AWS Provider for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "multi-region-event-replication"
      Purpose     = "eventbridge-global-replication"
      ManagedBy   = "terraform"
    }
  }
}

# Configure the AWS Provider for tertiary region
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "multi-region-event-replication"
      Purpose     = "eventbridge-global-replication"
      ManagedBy   = "terraform"
    }
  }
}