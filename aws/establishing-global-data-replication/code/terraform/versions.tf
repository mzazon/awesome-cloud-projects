# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the AWS Provider for primary region
provider "aws" {
  region = var.primary_region
  
  default_tags {
    tags = {
      Environment         = var.environment
      Application         = "MultiRegionReplication"
      CostCenter         = "IT-Storage"
      Owner              = "DataTeam"
      Compliance         = "SOX-GDPR"
      BackupStrategy     = "MultiRegion"
      TerraformManaged   = "true"
      Project            = var.project_name
    }
  }
}

# Configure AWS Provider for secondary region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Environment         = var.environment
      Application         = "MultiRegionReplication"
      CostCenter         = "IT-Storage"
      Owner              = "DataTeam"
      Compliance         = "SOX-GDPR"
      BackupStrategy     = "MultiRegion"
      TerraformManaged   = "true"
      Project            = var.project_name
    }
  }
}

# Configure AWS Provider for tertiary region
provider "aws" {
  alias  = "tertiary"
  region = var.tertiary_region
  
  default_tags {
    tags = {
      Environment         = var.environment
      Application         = "MultiRegionReplication"
      CostCenter         = "IT-Storage"
      Owner              = "DataTeam"
      Compliance         = "SOX-GDPR"
      BackupStrategy     = "MultiRegion"
      TerraformManaged   = "true"
      Project            = var.project_name
    }
  }
}