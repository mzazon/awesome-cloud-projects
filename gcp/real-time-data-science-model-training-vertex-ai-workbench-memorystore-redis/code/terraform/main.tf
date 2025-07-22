# Generate random suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    managed-by = "terraform"
    recipe     = "real-time-data-science-model-training"
  })
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "redis.googleapis.com",
    "batch.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "notebooks.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# Create VPC network for secure communication
resource "google_compute_network" "ml_network" {
  name                    = "${var.network_name}-${local.resource_suffix}"
  auto_create_subnetworks = false
  description             = "VPC network for ML training infrastructure"

  depends_on = [google_project_service.apis]
}

# Create subnet for ML resources
resource "google_compute_subnetwork" "ml_subnet" {
  name          = "${var.subnet_name}-${local.resource_suffix}"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.ml_network.id
  region        = var.region
  description   = "Subnet for ML training resources"

  # Enable private Google access for accessing GCP services
  private_ip_google_access = true

  # Secondary IP ranges for potential GKE usage
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Create firewall rule for Redis access
resource "google_compute_firewall" "allow_redis_access" {
  name    = "allow-redis-access-${local.resource_suffix}"
  network = google_compute_network.ml_network.name

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  source_ranges = var.allowed_ip_ranges
  target_tags   = ["redis-client"]
  description   = "Allow Redis access from ML training instances"
}

# Create firewall rule for internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-${local.resource_suffix}"
  network = google_compute_network.ml_network.name

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

  source_ranges = [var.subnet_cidr]
  description   = "Allow internal communication within the subnet"
}

# Create service account for ML training resources
resource "google_service_account" "ml_training_sa" {
  account_id   = "ml-training-sa-${local.resource_suffix}"
  display_name = "ML Training Service Account"
  description  = "Service account for ML training infrastructure"
}

# Assign IAM roles to service account
resource "google_project_iam_member" "ml_training_sa_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ml_training_sa.email}"
}

# Create Cloud Storage bucket for datasets and models
resource "google_storage_bucket" "ml_bucket" {
  name          = "${var.resource_prefix}-bucket-${local.resource_suffix}"
  location      = var.bucket_location
  storage_class = var.bucket_storage_class

  # Enable versioning for model artifacts
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for old versions
  lifecycle_rule {
    condition {
      age                = 7
      with_state         = "ARCHIVED"
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  labels = local.common_labels
}

# Create bucket folders for organization
resource "google_storage_bucket_object" "dataset_folder" {
  name   = "datasets/"
  bucket = google_storage_bucket.ml_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "models_folder" {
  name   = "models/"
  bucket = google_storage_bucket.ml_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "notebooks_folder" {
  name   = "notebooks/"
  bucket = google_storage_bucket.ml_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "scripts_folder" {
  name   = "scripts/"
  bucket = google_storage_bucket.ml_bucket.name
  content = " "
}

# Create Memorystore Redis instance for feature caching
resource "google_redis_instance" "ml_cache" {
  name           = "ml-feature-cache-${local.resource_suffix}"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  
  # Redis configuration
  redis_version     = var.redis_version
  tier             = var.redis_tier
  auth_enabled     = var.redis_auth_enabled
  display_name     = "ML Feature Cache"
  
  # Network configuration
  authorized_network = google_compute_network.ml_network.id
  
  # Maintenance policy
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  # Redis configuration parameters for ML workloads
  redis_configs = {
    maxmemory-policy = "allkeys-lru"
    timeout         = "60"
    tcp-keepalive   = "60"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.apis,
    google_compute_network.ml_network
  ]
}

# Create Vertex AI Workbench instance
resource "google_workbench_instance" "ml_workbench" {
  name     = "ml-workbench-${local.resource_suffix}"
  location = var.zone

  # Machine configuration
  gce_setup {
    machine_type = var.workbench_machine_type
    
    # Accelerator configuration
    accelerator_configs {
      type         = var.workbench_accelerator_type
      core_count   = var.workbench_accelerator_count
    }

    # Boot disk configuration
    boot_disk {
      disk_size_gb = var.workbench_boot_disk_size_gb
      disk_type    = var.workbench_disk_type
    }

    # Data disk configuration
    data_disks {
      disk_size_gb = var.workbench_data_disk_size_gb
      disk_type    = var.workbench_disk_type
    }

    # Network configuration
    network_interfaces {
      network = google_compute_network.ml_network.id
      subnet  = google_compute_subnetwork.ml_subnet.id
    }

    # Service account configuration
    service_accounts {
      email  = google_service_account.ml_training_sa.email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }

    # Metadata for configuration
    metadata = {
      enable-oslogin = "true"
      startup-script = templatefile("${path.module}/startup-script.sh", {
        redis_host   = google_redis_instance.ml_cache.host
        redis_port   = google_redis_instance.ml_cache.port
        bucket_name  = google_storage_bucket.ml_bucket.name
        project_id   = var.project_id
      })
    }

    # Tags for firewall rules
    tags = ["redis-client", "ml-workbench"]
  }

  # Install Jupyter extensions and ML libraries
  desired_state = "ACTIVE"

  labels = local.common_labels

  depends_on = [
    google_project_service.apis,
    google_redis_instance.ml_cache,
    google_compute_subnetwork.ml_subnet,
    google_service_account.ml_training_sa
  ]
}

# Create startup script for Workbench instance
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    redis_host  = google_redis_instance.ml_cache.host
    redis_port  = google_redis_instance.ml_cache.port
    bucket_name = google_storage_bucket.ml_bucket.name
    project_id  = var.project_id
  })
}

# Create startup script template
resource "local_file" "startup_script_template" {
  filename = "${path.module}/startup-script.tpl"
  content = <<-EOF
#!/bin/bash

# Update system packages
apt-get update
apt-get install -y python3-pip redis-tools

# Install Python packages for ML and Redis
pip3 install --upgrade pip
pip3 install redis pandas scikit-learn google-cloud-storage google-cloud-monitoring numpy jupyter

# Set environment variables for Redis and storage
echo "export REDIS_HOST=${redis_host}" >> /etc/environment
echo "export REDIS_PORT=${redis_port}" >> /etc/environment
echo "export BUCKET_NAME=${bucket_name}" >> /etc/environment
echo "export PROJECT_ID=${project_id}" >> /etc/environment

# Create Redis configuration test script
cat > /tmp/test_redis.py << 'SCRIPT'
import redis
import os

try:
    r = redis.Redis(host=os.environ.get('REDIS_HOST'), port=int(os.environ.get('REDIS_PORT', 6379)))
    r.ping()
    print("Redis connection successful")
except Exception as e:
    print(f"Redis connection failed: {e}")
SCRIPT

# Test Redis connection
python3 /tmp/test_redis.py

# Create ML training utilities
mkdir -p /opt/ml-training
cat > /opt/ml-training/utils.py << 'UTILS'
import redis
import pickle
import os
from google.cloud import storage

def get_redis_client():
    """Get Redis client connection"""
    host = os.environ.get('REDIS_HOST', 'localhost')
    port = int(os.environ.get('REDIS_PORT', 6379))
    return redis.Redis(host=host, port=port)

def get_storage_client():
    """Get Cloud Storage client"""
    return storage.Client()

def cache_data(key, data, expire_seconds=3600):
    """Cache data in Redis with expiration"""
    r = get_redis_client()
    r.setex(key, expire_seconds, pickle.dumps(data))

def get_cached_data(key):
    """Retrieve cached data from Redis"""
    r = get_redis_client()
    data = r.get(key)
    return pickle.loads(data) if data else None
UTILS

# Set permissions
chown -R jupyter:jupyter /opt/ml-training
chmod +x /opt/ml-training/utils.py

# Log completion
echo "ML training environment setup completed" | logger -t ml-setup
EOF
}

# Create Cloud Monitoring dashboard if enabled
resource "google_monitoring_dashboard" "ml_dashboard" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "ML Training Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Redis Cache Hit Ratio"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"redis_instance\" resource.labels.instance_id=\"${google_redis_instance.ml_cache.name}\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width = 6
          height = 4
          widget = {
            title = "Workbench Instance CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" resource.labels.instance_id=\"${google_workbench_instance.ml_workbench.name}\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width = 12
          height = 4
          widget = {
            title = "Storage Bucket Operations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" resource.labels.bucket_name=\"${google_storage_bucket.ml_bucket.name}\""
                    aggregation = {
                      alignmentPeriod = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_project_service.apis,
    google_redis_instance.ml_cache,
    google_workbench_instance.ml_workbench,
    google_storage_bucket.ml_bucket
  ]
}

# Create IAM policy for bucket access
resource "google_storage_bucket_iam_member" "ml_bucket_access" {
  bucket = google_storage_bucket.ml_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ml_training_sa.email}"
}

# Create sample training script and upload to bucket
resource "google_storage_bucket_object" "training_script" {
  name   = "scripts/training_script.py"
  bucket = google_storage_bucket.ml_bucket.name
  content = templatefile("${path.module}/training_script.py.tpl", {
    redis_host  = google_redis_instance.ml_cache.host
    redis_port  = google_redis_instance.ml_cache.port
    bucket_name = google_storage_bucket.ml_bucket.name
  })
}

# Create training script template
resource "local_file" "training_script_template" {
  filename = "${path.module}/training_script.py.tpl"
  content = <<-EOF
import os
import redis
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import pickle
import json
from google.cloud import storage
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def connect_to_redis():
    """Connect to Redis cache"""
    redis_host = "${redis_host}"
    redis_port = ${redis_port}
    
    r = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    logger.info(f"Connected to Redis at {redis_host}:{redis_port}")
    return r

def cache_features(r, X_train, X_test, y_train, y_test):
    """Cache preprocessed features in Redis"""
    logger.info("Caching features in Redis...")
    
    # Cache training features
    r.set('X_train', pickle.dumps(X_train))
    r.set('y_train', pickle.dumps(y_train))
    r.set('X_test', pickle.dumps(X_test))
    r.set('y_test', pickle.dumps(y_test))
    
    # Set expiration (24 hours)
    r.expire('X_train', 86400)
    r.expire('y_train', 86400)
    r.expire('X_test', 86400)
    r.expire('y_test', 86400)
    
    logger.info("Features cached successfully")

def train_model():
    """Main training function"""
    logger.info("Starting model training...")
    
    # Connect to Redis
    r = connect_to_redis()
    
    # Download dataset from Cloud Storage
    bucket_name = "${bucket_name}"
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    # Generate sample data if dataset doesn't exist
    from sklearn.datasets import make_classification
    X, y = make_classification(
        n_samples=10000,
        n_features=20,
        n_informative=15,
        n_redundant=5,
        n_classes=2,
        random_state=42
    )
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Cache features in Redis
    cache_features(r, X_train, X_test, y_train, y_test)
    
    # Train model
    logger.info("Training Random Forest model...")
    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)
    
    # Make predictions
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    logger.info(f"Model training completed. Accuracy: {accuracy:.4f}")
    
    # Save model
    with open('trained_model.pkl', 'wb') as f:
        pickle.dump(model, f)
    
    # Upload model to Cloud Storage
    blob = bucket.blob('models/trained_model.pkl')
    blob.upload_from_filename('trained_model.pkl')
    
    # Cache model metrics in Redis
    metrics = {
        'accuracy': accuracy,
        'model_path': f'gs://{bucket_name}/models/trained_model.pkl'
    }
    r.set('model_metrics', json.dumps(metrics))
    
    logger.info("Model saved and metrics cached")

if __name__ == "__main__":
    train_model()
EOF
}

# Create Jupyter notebook and upload to bucket
resource "google_storage_bucket_object" "jupyter_notebook" {
  name   = "notebooks/ml_training_notebook.ipynb"
  bucket = google_storage_bucket.ml_bucket.name
  content = templatefile("${path.module}/notebook.ipynb.tpl", {
    redis_host  = google_redis_instance.ml_cache.host
    redis_port  = google_redis_instance.ml_cache.port
    bucket_name = google_storage_bucket.ml_bucket.name
  })
}

# Create notebook template
resource "local_file" "notebook_template" {
  filename = "${path.module}/notebook.ipynb.tpl"
  content = <<-EOF
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Real-Time ML Training with Redis Caching\n",
    "\n",
    "This notebook demonstrates high-performance model training using Vertex AI Workbench with Redis caching for feature storage and retrieval."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Install required packages\n",
    "!pip install redis pandas scikit-learn google-cloud-storage google-cloud-monitoring"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import redis\nimport pandas as pd\nimport numpy as np\nfrom sklearn.ensemble import RandomForestClassifier\nfrom sklearn.model_selection import train_test_split\nfrom sklearn.metrics import accuracy_score\nimport pickle\nimport time\nfrom google.cloud import storage\nimport os\n\n# Configuration\nREDIS_HOST = '${redis_host}'\nREDIS_PORT = ${redis_port}\nBUCKET_NAME = '${bucket_name}'\n\nprint(f'Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Connect to Redis cache\nr = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=False)\nprint('Redis connection status:', r.ping())\n\n# Check cache statistics\ninfo = r.info()\nprint(f'Redis memory usage: {info[\"used_memory_human\"]}')\nprint(f'Connected clients: {info[\"connected_clients\"]}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load data with caching optimization\ndef load_cached_features():\n    \"\"\"Load features from Redis cache or generate new data\"\"\"\n    \n    # Try to load from cache first\n    cached_X = r.get('X_train')\n    cached_y = r.get('y_train')\n    \n    if cached_X and cached_y:\n        print('Loading features from Redis cache...')\n        X_train = pickle.loads(cached_X)\n        y_train = pickle.loads(cached_y)\n        return X_train, y_train\n    \n    # Generate sample data if not cached\n    print('Generating sample data and caching...')\n    from sklearn.datasets import make_classification\n    X, y = make_classification(\n        n_samples=10000,\n        n_features=20,\n        n_informative=15,\n        n_redundant=5,\n        n_classes=2,\n        random_state=42\n    )\n    \n    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)\n    \n    # Cache for future use\n    r.setex('X_train', 3600, pickle.dumps(X_train))\n    r.setex('y_train', 3600, pickle.dumps(y_train))\n    r.setex('X_test', 3600, pickle.dumps(X_test))\n    r.setex('y_test', 3600, pickle.dumps(y_test))\n    \n    return X_train, y_train\n\n# Load features\nstart_time = time.time()\nX_train, y_train = load_cached_features()\nload_time = time.time() - start_time\nprint(f'Data loading completed in {load_time:.2f} seconds')\nprint(f'Training data shape: {X_train.shape}')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Train model with performance monitoring\nprint('Starting model training...')\nstart_time = time.time()\n\nmodel = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)\nmodel.fit(X_train, y_train)\n\ntraining_time = time.time() - start_time\nprint(f'Model training completed in {training_time:.2f} seconds')\n\n# Cache trained model\nmodel_bytes = pickle.dumps(model)\nr.setex('trained_model', 3600, model_bytes)\nprint('Model cached in Redis for fast access')"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Evaluate model performance\nX_test = pickle.loads(r.get('X_test'))\ny_test = pickle.loads(r.get('y_test'))\n\npredictions = model.predict(X_test)\naccuracy = accuracy_score(y_test, predictions)\n\nprint(f'Model Accuracy: {accuracy:.4f}')\n\n# Store metrics in Redis\nmetrics = {\n    'accuracy': accuracy,\n    'training_time': training_time,\n    'data_load_time': load_time,\n    'timestamp': time.time()\n}\nr.setex('model_metrics', 3600, pickle.dumps(metrics))\nprint('Metrics cached for dashboard access')"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF
}