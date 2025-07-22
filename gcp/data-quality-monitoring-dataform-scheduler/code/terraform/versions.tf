# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Terraform configuration for Data Quality Monitoring with Dataform and Cloud Scheduler
# This file defines the required providers and their versions

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Platform provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform beta provider for Dataform resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for managing resource timing and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels to apply to all resources
  default_labels = {
    environment   = var.environment
    project       = "data-quality-monitoring"
    managed-by    = "terraform"
    recipe-id     = "f8a3b2c1"
  }
}

# Google Cloud beta provider for accessing beta features like Dataform
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels to apply to all resources
  default_labels = {
    environment   = var.environment
    project       = "data-quality-monitoring"
    managed-by    = "terraform"
    recipe-id     = "f8a3b2c1"
  }
}