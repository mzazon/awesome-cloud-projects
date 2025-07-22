# Main Terraform configuration for Multi-Modal AI Content Generation Pipeline
# This configuration deploys a complete infrastructure stack including:
# - Cloud Composer for workflow orchestration
# - Vertex AI for AI/ML capabilities
# - Cloud Storage for content artifacts
# - Cloud Run for API services
# - IAM and networking configurations

# =============================================================================
# LOCAL VALUES AND DATA SOURCES
# =============================================================================

locals {
  # Generate unique suffix for global resources
  random_suffix = random_id.suffix.hex
  
  # Construct unique names for global resources
  storage_bucket_full_name = "${var.storage_bucket_name}-${local.random_suffix}"
  cloud_run_full_name     = "${var.cloud_run_service_name}-${local.random_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    terraform   = "true"
  })
  
  # Required APIs for the content generation pipeline
  required_apis = [
    "aiplatform.googleapis.com",
    "composer.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "serviceusage.googleapis.com"
  ]
}

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get current client configuration
data "google_client_config" "current" {}

# =============================================================================
# PROJECT CONFIGURATION AND API ENABLEMENT
# =============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.key
  
  # Prevent disabling APIs when this resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# =============================================================================
# IAM AND SERVICE ACCOUNTS
# =============================================================================

# Service account for the content generation pipeline
resource "google_service_account" "content_pipeline_sa" {
  account_id   = var.service_account_name
  display_name = "Multi-Modal Content Pipeline Service Account"
  description  = "Service account for Cloud Composer, Vertex AI, and Cloud Run components"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Cloud Composer environment
resource "google_project_iam_member" "composer_worker" {
  project = var.project_id
  role    = "roles/composer.worker"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# IAM binding for Vertex AI access
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# IAM binding for Cloud Storage access
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# IAM binding for Cloud Run access
resource "google_project_iam_member" "cloud_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# IAM binding for logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# IAM binding for monitoring
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

# VPC network for the content pipeline
resource "google_compute_network" "content_pipeline_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  project                 = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Subnet for the content pipeline components
resource "google_compute_subnetwork" "content_pipeline_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.content_pipeline_vpc.id
  project       = var.project_id
  
  # Enable Private Google Access for accessing Google APIs
  private_ip_google_access = var.enable_private_google_access
  
  # Secondary IP ranges for GKE pods and services (used by Composer)
  secondary_ip_range {
    range_name    = "composer-pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "composer-services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Firewall rule for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-content-pipeline"
  network = google_compute_network.content_pipeline_vpc.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.subnet_cidr, "10.1.0.0/16", "10.2.0.0/16"]
  
  description = "Allow internal communication within the content pipeline network"
}

# Firewall rule for Cloud Run access
resource "google_compute_firewall" "allow_cloud_run" {
  name    = "allow-cloud-run-content-api"
  network = google_compute_network.content_pipeline_vpc.name
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "443"]
  }
  
  source_ranges = var.allowed_ingress_cidrs
  target_tags   = ["cloud-run"]
  
  description = "Allow HTTPS access to Cloud Run content API"
}

# =============================================================================
# CLOUD STORAGE CONFIGURATION
# =============================================================================

# Cloud Storage bucket for content artifacts and pipeline data
resource "google_storage_bucket" "content_pipeline_bucket" {
  name          = local.storage_bucket_full_name
  location      = var.region
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for content version control
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
        num_newer_versions   = lifecycle_rule.value.condition.num_newer_versions
      }
    }
  }
  
  # Apply labels to the bucket
  labels = local.common_labels
  
  # Enable deletion protection in production
  deletion_protection = var.deletion_protection
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket folders for organized content storage
resource "google_storage_bucket_object" "content_folders" {
  for_each = toset([
    "content/",
    "briefs/",
    "templates/",
    "models/",
    "logs/",
    "exports/"
  ])
  
  name   = each.key
  bucket = google_storage_bucket.content_pipeline_bucket.name
  source = "/dev/null"
  
  depends_on = [google_storage_bucket.content_pipeline_bucket]
}

# IAM binding for bucket access by the service account
resource "google_storage_bucket_iam_member" "content_bucket_access" {
  bucket = google_storage_bucket.content_pipeline_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.content_pipeline_sa.email}"
}

# =============================================================================
# VERTEX AI CONFIGURATION
# =============================================================================

# Vertex AI dataset for storing training and inference data
resource "google_vertex_ai_dataset" "content_generation_dataset" {
  provider     = google-beta
  display_name = var.vertex_ai_dataset_name
  region       = var.region
  project      = var.project_id
  
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/text_1.0.0.yaml"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Vertex AI Featurestore for managing ML features (if needed for advanced use cases)
resource "google_vertex_ai_featurestore" "content_features" {
  provider = google-beta
  name     = "content-features"
  region   = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  online_serving_config {
    fixed_node_count = 1
  }
  
  # Enable encryption at rest
  encryption_spec {
    kms_key_name = "" # Use Google-managed encryption keys
  }
  
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD COMPOSER CONFIGURATION
# =============================================================================

# Cloud Composer environment for workflow orchestration
resource "google_composer_environment" "content_pipeline_composer" {
  provider = google-beta
  name     = var.composer_environment_name
  region   = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  config {
    # Node configuration
    node_config {
      zone         = var.zone
      machine_type = var.composer_machine_type
      disk_size_gb = var.composer_disk_size_gb
      
      # Use custom service account
      service_account = google_service_account.content_pipeline_sa.email
      
      # Network configuration
      network    = google_compute_network.content_pipeline_vpc.id
      subnetwork = google_compute_subnetwork.content_pipeline_subnet.id
      
      # Enable IP aliases for better networking
      enable_ip_alias = true
      
      # Configure secondary ranges
      ip_allocation_policy {
        cluster_secondary_range_name  = "composer-pods"
        services_secondary_range_name = "composer-services"
      }
      
      # Apply labels to nodes
      labels = local.common_labels
    }
    
    # Software configuration
    software_config {
      image_version  = "composer-2.9.1-airflow-${var.composer_airflow_version}"
      python_version = var.composer_python_version
      
      # Python package dependencies for ADK and other requirements
      pypi_packages = {
        "google-cloud-adk"                         = ">=1.5.0"
        "google-cloud-aiplatform"                 = ">=1.48.0"
        "google-cloud-storage"                    = ">=2.13.0"
        "google-cloud-run"                        = ">=0.10.0"
        "apache-airflow-providers-google"         = ">=10.12.0"
        "pillow"                                  = ">=10.2.0"
        "moviepy"                                 = ">=1.0.3"
        "google-generativeai"                     = ">=0.5.0"
      }
      
      # Environment variables for the Composer environment
      env_variables = {
        PROJECT_ID                = var.project_id
        REGION                   = var.region
        STORAGE_BUCKET           = google_storage_bucket.content_pipeline_bucket.name
        COMPOSER_ENV_NAME        = var.composer_environment_name
        VERTEX_AI_DATASET_NAME   = google_vertex_ai_dataset.content_generation_dataset.display_name
        ENABLE_MONITORING        = tostring(var.enable_monitoring)
      }
      
      # Airflow configuration overrides
      airflow_config_overrides = {
        "webserver-expose_config"           = "True"
        "core-dags_are_paused_at_creation" = "False"
        "core-max_active_runs_per_dag"     = "1"
        "scheduler-dag_dir_list_interval"  = "300"
      }
    }
    
    # Private environment configuration for enhanced security
    private_environment_config {
      enable_private_endpoint = true
      
      # Master IP range for the GKE cluster
      master_ipv4_cidr_block = "172.16.0.0/28"
    }
    
    # Web server network access control
    web_server_network_access_control {
      allowed_ip_range {
        value       = "0.0.0.0/0"
        description = "Allow access from all IPs (consider restricting in production)"
      }
    }
    
    # Database configuration
    database_config {
      machine_type = "db-n1-standard-2"
    }
    
    # Web server configuration
    web_server_config {
      machine_type = "composer-n1-webserver-2"
    }
    
    # Workloads configuration for better resource management
    workloads_config {
      scheduler {
        cpu        = 2
        memory_gb  = 7.5
        storage_gb = 5
        count      = 1
      }
      
      web_server {
        cpu        = 1
        memory_gb  = 3.75
        storage_gb = 5
      }
      
      worker {
        cpu        = 1
        memory_gb  = 3.75
        storage_gb = 5
        min_count  = 1
        max_count  = 3
      }
    }
    
    # Enable maintenance window
    maintenance_window {
      start_time = "2025-01-01T01:00:00Z"
      end_time   = "2025-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_compute_network.content_pipeline_vpc,
    google_compute_subnetwork.content_pipeline_subnet,
    google_service_account.content_pipeline_sa,
    google_project_iam_member.composer_worker
  ]
  
  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}

# =============================================================================
# CLOUD RUN CONFIGURATION
# =============================================================================

# Local file for Cloud Run application source code
resource "local_file" "cloud_run_app" {
  filename = "${path.module}/app.py"
  content  = <<-EOF
from flask import Flask, request, jsonify
from google.cloud import storage, composer_v1
import os
import json
import uuid
from datetime import datetime

app = Flask(__name__)

@app.route('/generate-content', methods=['POST'])
def generate_content():
    """Trigger multi-modal content generation pipeline"""
    try:
        content_brief = request.get_json()
        
        # Validate content brief
        required_fields = ['target_audience', 'content_type', 'brand_guidelines']
        if not all(field in content_brief for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400
        
        # Generate unique content ID
        content_id = str(uuid.uuid4())
        
        # Store content brief for DAG access
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        brief_blob = bucket.blob(f"briefs/{content_id}/content_brief.json")
        brief_blob.upload_from_string(json.dumps(content_brief, indent=2))
        
        response_data = {
            'content_id': content_id,
            'status': 'initiated',
            'pipeline_status': 'running',
            'estimated_completion': '15-20 minutes',
            'brief_location': f"gs://{os.environ['STORAGE_BUCKET']}/briefs/{content_id}/content_brief.json"
        }
        
        return jsonify(response_data), 202
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/content-status/<content_id>', methods=['GET'])
def get_content_status(content_id):
    """Check content generation status"""
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        # Check for completed content
        review_blob = bucket.blob(f"content/{content_id}/quality_review.json")
        
        if review_blob.exists():
            review_data = json.loads(review_blob.download_as_text())
            return jsonify({
                'content_id': content_id,
                'status': 'completed',
                'quality_score': review_data.get('quality_score', 0),
                'approved': review_data.get('approved_for_publishing', False),
                'content_location': f"gs://{os.environ['STORAGE_BUCKET']}/content/{content_id}/"
            })
        else:
            return jsonify({
                'content_id': content_id,
                'status': 'processing',
                'message': 'Content generation in progress'
            })
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
}

# Create requirements.txt for Cloud Run
resource "local_file" "cloud_run_requirements" {
  filename = "${path.module}/requirements.txt"
  content  = <<-EOF
flask>=2.3.0
google-cloud-storage>=2.13.0
google-cloud-composer>=1.10.0
gunicorn>=20.1.0
EOF
}

# Create Dockerfile for Cloud Run
resource "local_file" "cloud_run_dockerfile" {
  filename = "${path.module}/Dockerfile"
  content  = <<-EOF
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 app:app
EOF
}

# Cloud Run service for the content API
resource "google_cloud_run_service" "content_api" {
  name     = local.cloud_run_full_name
  location = var.region
  project  = var.project_id
  
  template {
    metadata {
      labels = local.common_labels
      
      annotations = {
        "autoscaling.knative.dev/maxScale"      = tostring(var.cloud_run_max_instances)
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/vpc-access-connector" = ""
      }
    }
    
    spec {
      container_concurrency = var.cloud_run_concurrency
      timeout_seconds      = var.cloud_run_timeout
      service_account_name = google_service_account.content_pipeline_sa.email
      
      containers {
        # Use a placeholder image - in production, build and push your image
        image = "gcr.io/cloudrun/hello"
        
        ports {
          container_port = 8080
        }
        
        resources {
          limits = {
            cpu    = var.cloud_run_cpu
            memory = var.cloud_run_memory
          }
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "REGION"
          value = var.region
        }
        
        env {
          name  = "STORAGE_BUCKET"
          value = google_storage_bucket.content_pipeline_bucket.name
        }
        
        env {
          name  = "COMPOSER_ENV_NAME"
          value = var.composer_environment_name
        }
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.content_pipeline_sa
  ]
}

# IAM policy for Cloud Run service (conditional on allow_unauthenticated)
resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_service.content_api.location
  service  = google_cloud_run_service.content_api.name
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

# Log sink for content pipeline logs
resource "google_logging_project_sink" "content_pipeline_sink" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "content-pipeline-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.content_pipeline_bucket.name}"
  project     = var.project_id
  
  # Filter for content pipeline related logs
  filter = <<-EOF
    resource.type="cloud_run_revision"
    OR resource.type="composer_environment"
    OR resource.type="aiplatform.googleapis.com/Endpoint"
    OR protoPayload.serviceName="storage.googleapis.com"
  EOF
  
  # Use a unique writer identity
  unique_writer_identity = true
}

# Grant the log sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.content_pipeline_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.content_pipeline_sink[0].writer_identity
}

# Budget alert for cost monitoring
resource "google_billing_budget" "content_pipeline_budget" {
  count = var.enable_monitoring ? 1 : 0
  
  billing_account = data.google_project.current.billing_account
  display_name    = "Content Pipeline Budget"
  
  budget_filter {
    projects = [var.project_id]
    
    # Filter by content pipeline related services
    services = [
      "services/6F81-5844-456A", # Compute Engine
      "services/95FF-2EF5-5EA1", # Cloud Storage
      "services/E5AC-2363-4B96", # Cloud Run
      "services/6B32-1B8C-4E9A", # Cloud Composer
      "services/ml.googleapis.com" # Vertex AI
    ]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }
}