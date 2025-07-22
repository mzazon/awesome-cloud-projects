# High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench
# This Terraform configuration creates a complete environment for data science teams
# with high-performance storage and collaborative Jupyter notebook environments

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource names with random suffix for uniqueness
  storage_pool_name = "${var.storage_pool_name}-${random_id.suffix.hex}"
  volume_name       = "${var.volume_name}-${random_id.suffix.hex}"
  workbench_name    = "${var.workbench_name}-${random_id.suffix.hex}"
  bucket_name       = "${var.bucket_name}-${var.project_id}-${random_id.suffix.hex}"
  network_name      = "${var.network_name}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(
    {
      environment = var.environment
      purpose     = "data-science-ml"
      recipe      = "high-performance-netapp-workbench"
      managed-by  = "terraform"
      created-by  = "terraform-recipe"
    },
    var.additional_labels
  )
  
  # Subnet name
  subnet_name = "${local.network_name}-subnet"
  
  # NFS mount options for optimal performance
  nfs_mount_options = "nconnect=16,rsize=1048576,wsize=1048576,hard,intr"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "notebooks.googleapis.com",
    "netapp.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "servicenetworking.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when Terraform is destroyed
  disable_on_destroy = false
}

# Create VPC network optimized for high-performance data science workloads
resource "google_compute_network" "netapp_ml_network" {
  name                    = local.network_name
  description             = "High-performance network for ML workflows with NetApp storage"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet with adequate IP space for scaling
resource "google_compute_subnetwork" "netapp_ml_subnet" {
  name          = local.subnet_name
  description   = "Subnet for ML instances and NetApp volumes"
  region        = var.region
  network       = google_compute_network.netapp_ml_network.self_link
  ip_cidr_range = var.subnet_cidr
  
  # Enable private Google access for Cloud Storage integration
  private_ip_google_access = true
  
  # Enable flow logs for network monitoring and troubleshooting
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for ML workloads and NetApp access
resource "google_compute_firewall" "allow_netapp_nfs" {
  name    = "${local.network_name}-allow-nfs"
  network = google_compute_network.netapp_ml_network.name
  
  description = "Allow NFS traffic for NetApp volumes"
  
  allow {
    protocol = "tcp"
    ports    = ["111", "2049", "4045", "4046"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["111", "2049", "4045", "4046"]
  }
  
  source_ranges = [var.subnet_cidr]
  target_tags   = var.network_tags
}

resource "google_compute_firewall" "allow_jupyter" {
  name    = "${local.network_name}-allow-jupyter"
  network = google_compute_network.netapp_ml_network.name
  
  description = "Allow Jupyter notebook access"
  
  allow {
    protocol = "tcp"
    ports    = ["8080", "8888", "8000"]
  }
  
  source_ranges = ["0.0.0.0/0"]  # Restrict this in production
  target_tags   = var.network_tags
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.network_name}-allow-ssh"
  network = google_compute_network.netapp_ml_network.name
  
  description = "Allow SSH access for administration"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]  # Restrict this in production
  target_tags   = var.network_tags
}

# Create Cloud NetApp Volumes storage pool for high-performance data access
resource "google_netapp_storage_pool" "ml_storage_pool" {
  name               = local.storage_pool_name
  location           = var.region
  service_level      = var.storage_service_level
  capacity_gib       = var.storage_pool_capacity_gib
  network            = google_compute_network.netapp_ml_network.id
  description        = "High-performance storage pool for ML datasets and models"
  
  labels = local.common_labels
  
  depends_on = [
    google_compute_subnetwork.netapp_ml_subnet,
    google_project_service.required_apis
  ]
}

# Create NetApp volume for ML datasets with optimized configuration
resource "google_netapp_volume" "ml_datasets_volume" {
  location     = var.region
  name         = local.volume_name
  capacity_gib = var.volume_capacity_gib
  share_name   = var.volume_share_name
  storage_pool = google_netapp_storage_pool.ml_storage_pool.name
  protocols    = var.volume_protocols
  description  = "Shared volume for ML datasets, models, and notebooks"
  
  # Performance optimizations for ML workloads
  large_capacity     = var.volume_capacity_gib >= 100
  multiple_endpoints = true
  
  # Configure export policy for secure NFS access
  export_policy {
    rules {
      allowed_clients = var.subnet_cidr
      access_type     = "READ_WRITE"
      nfsv3          = contains(var.volume_protocols, "NFSV3")
      nfsv4          = contains(var.volume_protocols, "NFSV4")
      has_root_access = true
      access_type     = "READ_WRITE"
    }
  }
  
  # Security configurations
  security_style = "UNIX"
  kerberos_enabled = false
  
  labels = local.common_labels
  
  depends_on = [google_netapp_storage_pool.ml_storage_pool]
}

# Create Cloud Storage bucket for data lake integration and model versioning
resource "google_storage_bucket" "ml_datalake" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Enable versioning for model artifacts and datasets
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Security configurations
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Vertex AI Workbench instance with GPU support for ML acceleration
resource "google_workbench_instance" "ml_workbench" {
  name     = local.workbench_name
  location = var.zone
  
  gce_setup {
    machine_type = var.workbench_machine_type
    
    # GPU configuration for ML acceleration
    dynamic "accelerator_configs" {
      for_each = var.enable_gpu ? [1] : []
      content {
        type       = var.gpu_type
        core_count = var.gpu_count
      }
    }
    
    # High-performance boot disk
    boot_disk {
      disk_size_gb = var.boot_disk_size_gb
      disk_type    = var.boot_disk_type
      disk_encryption = "CMEK"  # Customer-managed encryption keys for security
    }
    
    # Additional data disk for temporary ML workloads
    data_disks {
      disk_size_gb = 500
      disk_type    = "PD_SSD"
      disk_encryption = "CMEK"
    }
    
    # Network configuration optimized for performance
    network_interfaces {
      network    = google_compute_network.netapp_ml_network.id
      subnet     = google_compute_subnetwork.netapp_ml_subnet.id
      nic_type   = "GVNIC"  # Google Virtual NIC for better performance
      no_address = false    # Assign external IP for management access
    }
    
    # Security configurations
    dynamic "shielded_instance_config" {
      for_each = var.enable_shielded_vm ? [1] : []
      content {
        enable_secure_boot          = var.enable_secure_boot
        enable_vtpm                = var.enable_vtpm
        enable_integrity_monitoring = var.enable_integrity_monitoring
      }
    }
    
    # Instance scheduling for cost optimization
    enable_ip_forwarding = var.enable_ip_forwarding
    
    # Metadata for initialization and configuration
    metadata = {
      "serial-port-logging-enable" = "false"
      "install-nvidia-driver"      = var.enable_gpu ? "True" : "False"
      "enable-oslogin"            = "true"
      "block-project-ssh-keys"    = "false"
      
      # Startup script to mount NetApp volume and configure environment
      "startup-script" = templatefile("${path.module}/startup-script.sh", {
        volume_ip          = google_netapp_volume.ml_datasets_volume.mount_options[0].export
        volume_path        = google_netapp_volume.ml_datasets_volume.mount_options[0].export_full_path
        mount_point        = "/mnt/ml-datasets"
        bucket_name        = google_storage_bucket.ml_datalake.name
        nfs_mount_options  = local.nfs_mount_options
      })
    }
    
    # Network tags for firewall rules
    tags = var.network_tags
    
    # Labels for resource management
    labels = local.common_labels
  }
  
  # Instance state
  desired_state = "ACTIVE"
  
  depends_on = [
    google_netapp_volume.ml_datasets_volume,
    google_storage_bucket.ml_datalake,
    google_compute_firewall.allow_netapp_nfs,
    google_compute_firewall.allow_jupyter,
    google_compute_firewall.allow_ssh
  ]
}

# Create startup script for Workbench instance initialization
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    volume_ip         = try(google_netapp_volume.ml_datasets_volume.mount_options[0].export, "")
    volume_path       = try(google_netapp_volume.ml_datasets_volume.mount_options[0].export_full_path, "")
    mount_point       = "/mnt/ml-datasets"
    bucket_name       = google_storage_bucket.ml_datalake.name
    nfs_mount_options = local.nfs_mount_options
  })
}

# Create startup script template
resource "local_file" "startup_script_template" {
  filename = "${path.module}/startup-script.tpl"
  content = <<-EOF
#!/bin/bash
# Startup script for Vertex AI Workbench instance
# Mounts NetApp volume and configures ML environment

set -e
export DEBIAN_FRONTEND=noninteractive

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/startup-script.log
}

log "Starting NetApp volume mount and ML environment setup"

# Install NFS utilities if not present
if ! command -v mount.nfs4 &> /dev/null; then
    log "Installing NFS utilities"
    apt-get update
    apt-get install -y nfs-common
fi

# Create mount point
log "Creating mount point: ${mount_point}"
mkdir -p ${mount_point}

# Mount NetApp volume with performance optimizations
if [ -n "${volume_ip}" ] && [ -n "${volume_path}" ]; then
    log "Mounting NetApp volume: ${volume_ip}:${volume_path} to ${mount_point}"
    mount -t nfs4 -o ${nfs_mount_options} ${volume_ip}:${volume_path} ${mount_point}
    
    # Add to fstab for persistent mounting
    echo "${volume_ip}:${volume_path} ${mount_point} nfs4 ${nfs_mount_options} 0 0" >> /etc/fstab
    
    # Set appropriate permissions
    chown -R jupyter:jupyter ${mount_point}
    chmod 755 ${mount_point}
    
    log "NetApp volume mounted successfully"
else
    log "WARNING: NetApp volume connection details not available"
fi

# Create directory structure for ML workflows
log "Creating ML directory structure"
mkdir -p ${mount_point}/{raw-data,processed-data,models,notebooks,config}
chown -R jupyter:jupyter ${mount_point}

# Install additional Python packages for data science
log "Installing additional Python packages"
pip install --upgrade \
    pandas \
    numpy \
    scikit-learn \
    matplotlib \
    seaborn \
    plotly \
    jupyter \
    google-cloud-storage \
    google-cloud-aiplatform

# Create configuration for Google Cloud Storage sync
log "Creating Cloud Storage sync script"
cat > ${mount_point}/sync_to_storage.py << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Sync ML artifacts to Cloud Storage for versioning and collaboration
"""
import subprocess
import os
import sys
from datetime import datetime

BUCKET_NAME = "${bucket_name}"
LOCAL_BASE_PATH = "${mount_point}"

def run_command(cmd):
    """Run shell command and return result"""
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {cmd}")
        print(f"Error: {e.stderr}")
        return None

def sync_models():
    """Sync trained models to Cloud Storage"""
    local_path = f"{LOCAL_BASE_PATH}/models/"
    remote_path = f"gs://{BUCKET_NAME}/models/"
    
    if os.path.exists(local_path):
        cmd = f"gsutil -m rsync -r {local_path} {remote_path}"
        print(f"Syncing models: {local_path} -> {remote_path}")
        run_command(cmd)
        print("Models synced successfully")
    else:
        print(f"Models directory not found: {local_path}")

def sync_notebooks():
    """Sync notebooks to Cloud Storage"""
    local_path = f"{LOCAL_BASE_PATH}/notebooks/"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    remote_path = f"gs://{BUCKET_NAME}/notebooks-backup/{timestamp}/"
    
    if os.path.exists(local_path):
        cmd = f"gsutil -m cp -r {local_path}* {remote_path}"
        print(f"Backing up notebooks: {local_path} -> {remote_path}")
        run_command(cmd)
        print("Notebooks backed up successfully")
    else:
        print(f"Notebooks directory not found: {local_path}")

def list_bucket_contents():
    """List bucket contents"""
    cmd = f"gsutil ls -r gs://{BUCKET_NAME}/"
    print("Cloud Storage bucket contents:")
    output = run_command(cmd)
    if output:
        print(output)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        action = sys.argv[1]
        if action == "models":
            sync_models()
        elif action == "notebooks":
            sync_notebooks()
        elif action == "list":
            list_bucket_contents()
        else:
            print("Usage: python sync_to_storage.py [models|notebooks|list]")
    else:
        print("Syncing all artifacts...")
        sync_models()
        sync_notebooks()
        list_bucket_contents()
PYTHON_EOF

chmod +x ${mount_point}/sync_to_storage.py
chown jupyter:jupyter ${mount_point}/sync_to_storage.py

# Create sample dataset and performance test notebook
log "Creating sample dataset and test notebook"
mkdir -p ${mount_point}/raw-data
curl -s -o ${mount_point}/raw-data/iris_sample.csv \
    "https://storage.googleapis.com/cloud-samples-data/ai-platform/iris/iris_data.csv" || \
    log "Warning: Could not download sample dataset"

# Create performance test notebook
cat > ${mount_point}/notebooks/netapp_performance_test.ipynb << 'NOTEBOOK_EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# NetApp Volumes Performance Test\n",
    "\n",
    "This notebook tests the performance of the Cloud NetApp Volumes integration with Vertex AI Workbench."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import time\n",
    "import os\n",
    "import subprocess\n",
    "\n",
    "# Test NetApp volume performance\n",
    "mount_point = '${mount_point}'\n",
    "print(f'Testing NetApp volume at: {mount_point}')\n",
    "\n",
    "# Check mount status\n",
    "result = subprocess.run(['df', '-h', mount_point], capture_output=True, text=True)\n",
    "print('\\nMount status:')\n",
    "print(result.stdout)\n",
    "\n",
    "# Test write performance\n",
    "print('\\nTesting write performance...')\n",
    "start_time = time.time()\n",
    "test_data = np.random.random((10000, 100))\n",
    "df = pd.DataFrame(test_data)\n",
    "test_file = f'{mount_point}/test_performance.csv'\n",
    "df.to_csv(test_file, index=False)\n",
    "write_time = time.time() - start_time\n",
    "print(f'Write time: {write_time:.4f} seconds')\n",
    "\n",
    "# Test read performance\n",
    "print('\\nTesting read performance...')\n",
    "start_time = time.time()\n",
    "df_read = pd.read_csv(test_file)\n",
    "read_time = time.time() - start_time\n",
    "print(f'Read time: {read_time:.4f} seconds')\n",
    "print(f'Data shape: {df_read.shape}')\n",
    "\n",
    "# Clean up test file\n",
    "os.remove(test_file)\n",
    "print('\\nPerformance test completed successfully')"
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
NOTEBOOK_EOF

chown jupyter:jupyter ${mount_point}/notebooks/netapp_performance_test.ipynb

# Create team collaboration guidelines
cat > ${mount_point}/notebooks/team_guidelines.md << 'GUIDELINES_EOF'
# Data Science Team Guidelines

## Shared Directory Structure

- **raw-data/**: Original datasets (read-only recommended)
- **processed-data/**: Cleaned and transformed datasets
- **models/**: Trained model artifacts and checkpoints
- **notebooks/**: Jupyter notebooks for experiments and analysis
- **config/**: Shared configuration files and scripts

## NetApp Volumes Benefits

- High-performance access (up to 4.5 GiB/sec throughput)
- Sub-millisecond latency for data operations
- Instant snapshots for data protection
- Shared access for seamless team collaboration
- POSIX-compliant file system

## Best Practices

1. **Data Organization**: Keep raw data separate from processed data
2. **Version Control**: Use Cloud Storage sync for model versioning
3. **Performance**: Leverage NFS4 with optimized mount options
4. **Collaboration**: Use shared notebooks directory for team projects
5. **Security**: Follow principle of least privilege for data access

## Quick Commands

```bash
# Check NetApp volume status
df -h ${mount_point}

# Sync models to Cloud Storage
python ${mount_point}/sync_to_storage.py models

# Backup notebooks
python ${mount_point}/sync_to_storage.py notebooks

# List Cloud Storage contents
python ${mount_point}/sync_to_storage.py list
```
GUIDELINES_EOF

chown jupyter:jupyter ${mount_point}/notebooks/team_guidelines.md

log "Startup script completed successfully"
log "NetApp volume available at: ${mount_point}"
log "Cloud Storage bucket: ${bucket_name}"
log "Access Jupyter at the Workbench instance URL"
EOF
}