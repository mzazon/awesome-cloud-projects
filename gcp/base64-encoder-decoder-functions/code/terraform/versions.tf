# Copyright 2025 Google LLC
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

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}