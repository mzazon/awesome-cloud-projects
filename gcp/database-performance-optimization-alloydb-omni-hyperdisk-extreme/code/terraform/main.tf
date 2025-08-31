# Main Terraform configuration for AlloyDB Omni and Hyperdisk Extreme performance optimization

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix for uniqueness
  instance_name = "${var.name_prefix}-vm-${random_id.suffix.hex}"
  disk_name     = "${var.name_prefix}-hyperdisk-${random_id.suffix.hex}"
  function_name = "${var.name_prefix}-scaler-${random_id.suffix.hex}"
  
  # Startup script for VM instance configuration
  startup_script = templatefile("${path.module}/startup-script.sh", {
    alloydb_password = var.alloydb_password
    alloydb_database = var.alloydb_database
  })
  
  # Combined labels for all resources
  common_labels = merge(var.labels, {
    created_by = "terraform"
    recipe     = "database-performance-optimization-alloydb-omni-hyperdisk-extreme"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Hyperdisk Extreme volume for ultra-high performance storage
resource "google_compute_disk" "hyperdisk_extreme" {
  name = local.disk_name
  type = "hyperdisk-extreme"
  zone = var.zone
  size = var.hyperdisk_size

  # Provision maximum IOPS for database workloads
  provisioned_iops = var.hyperdisk_provisioned_iops

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create startup script for VM instance
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = <<-EOF
#!/bin/bash
set -e

# Log all output for debugging
exec > >(tee /var/log/startup-script.log) 2>&1

echo "Starting AlloyDB Omni setup at $(date)"

# Update system packages
apt-get update
apt-get install -y docker.io fio curl jq

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Wait for Docker to be ready
sleep 10

# Format and mount the Hyperdisk Extreme volume
if [ -b /dev/disk/by-id/google-alloydb-data ]; then
    echo "Formatting Hyperdisk Extreme volume..."
    mkfs.ext4 -F /dev/disk/by-id/google-alloydb-data
    
    mkdir -p /var/lib/alloydb
    mount /dev/disk/by-id/google-alloydb-data /var/lib/alloydb
    
    # Add to fstab for persistent mounting
    echo "/dev/disk/by-id/google-alloydb-data /var/lib/alloydb ext4 defaults 0 2" >> /etc/fstab
    
    # Set proper permissions
    mkdir -p /var/lib/alloydb/data
    chown -R 999:999 /var/lib/alloydb
    
    echo "Hyperdisk Extreme volume mounted successfully"
else
    echo "Hyperdisk Extreme volume not found, creating directory on boot disk"
    mkdir -p /var/lib/alloydb/data
    chown -R 999:999 /var/lib/alloydb
fi

# Pull AlloyDB Omni container image
echo "Pulling AlloyDB Omni container..."
docker pull gcr.io/alloydb-omni/alloydb-omni:latest

# Start AlloyDB Omni container with columnar engine enabled
echo "Starting AlloyDB Omni container..."
docker run -d \
  --name alloydb-omni \
  --restart unless-stopped \
  -p 5432:5432 \
  -v /var/lib/alloydb/data:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD="${alloydb_password}" \
  -e POSTGRES_DB="${alloydb_database}" \
  gcr.io/alloydb-omni/alloydb-omni:latest

# Wait for AlloyDB to be ready
echo "Waiting for AlloyDB Omni to be ready..."
sleep 30

# Verify AlloyDB Omni is running
if docker ps | grep -q alloydb-omni; then
    echo "✅ AlloyDB Omni container started successfully"
    
    # Create performance monitoring script
    cat > /usr/local/bin/alloydb-monitor.sh << 'MONITOR_EOF'
#!/bin/bash
# AlloyDB Omni Performance Monitoring Script
echo "=== AlloyDB Omni Performance Metrics ==="
echo "Container Status: $(docker inspect alloydb-omni --format='{{.State.Status}}')"
echo "CPU Usage: $(docker stats alloydb-omni --no-stream --format 'table {{.CPUPerc}}')"
echo "Memory Usage: $(docker stats alloydb-omni --no-stream --format 'table {{.MemUsage}}')"
echo "Disk Usage: $(df -h /var/lib/alloydb | tail -n 1)"
echo "PostgreSQL Connections: $(docker exec alloydb-omni psql -U postgres -d ${alloydb_database} -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null || echo "N/A")"
MONITOR_EOF
    
    chmod +x /usr/local/bin/alloydb-monitor.sh
    
    echo "✅ AlloyDB Omni setup completed successfully at $(date)"
else
    echo "❌ AlloyDB Omni container failed to start"
    docker logs alloydb-omni
    exit 1
fi
EOF
  file_permission = "0755"
}

# Create high-performance VM instance for AlloyDB Omni
resource "google_compute_instance" "alloydb_instance" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  labels = local.common_labels
  tags   = ["alloydb-omni", "database", "high-performance"]

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  # Attach Hyperdisk Extreme volume
  attached_disk {
    source      = google_compute_disk.hyperdisk_extreme.id
    device_name = "alloydb-data"
    mode        = "READ_WRITE"
  }

  # Network configuration
  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name
    
    # Assign external IP for management access
    access_config {}
  }

  # Startup script for AlloyDB Omni installation and configuration
  metadata = {
    startup-script = local_file.startup_script.content
  }

  # Service account with necessary permissions
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/logging.write"
    ]
  }

  # Allow stopping for maintenance
  allow_stopping_for_update = true

  depends_on = [
    google_compute_disk.hyperdisk_extreme,
    google_project_service.required_apis,
    local_file.startup_script
  ]
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  count    = var.enable_cloud_function ? 1 : 0
  name     = "${var.project_id}-${local.function_name}-source"
  location = var.region

  labels = local.common_labels

  # Lifecycle management for source code
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Function source code
resource "local_file" "function_source" {
  count    = var.enable_cloud_function ? 1 : 0
  filename = "${path.module}/function-source/main.py"
  content = templatefile("${path.module}/function-main.py.tpl", {
    project_id    = var.project_id
    zone          = var.zone
    instance_name = local.instance_name
  })
}

# Create requirements.txt for Cloud Function
resource "local_file" "function_requirements" {
  count    = var.enable_cloud_function ? 1 : 0
  filename = "${path.module}/function-source/requirements.txt"
  content  = <<-EOF
google-cloud-compute>=1.19.0
google-cloud-monitoring>=2.22.0
functions-framework>=3.8.0
EOF
}

# Create ZIP archive for Cloud Function deployment
data "archive_file" "function_source" {
  count       = var.enable_cloud_function ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function-source/"
  
  depends_on = [
    local_file.function_source,
    local_file.function_requirements
  ]
}

# Upload Cloud Function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  count  = var.enable_cloud_function ? 1 : 0
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source[0].name
  source = data.archive_file.function_source[0].output_path

  depends_on = [data.archive_file.function_source]
}

# Create Cloud Function for automated performance scaling
resource "google_cloudfunctions_function" "performance_scaler" {
  count               = var.enable_cloud_function ? 1 : 0
  name                = local.function_name
  description         = "Automated performance scaling for AlloyDB Omni based on metrics"
  runtime             = var.function_runtime
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  entry_point         = "scale_performance"
  region              = var.region

  source_archive_bucket = google_storage_bucket.function_source[0].name
  source_archive_object = google_storage_bucket_object.function_source[0].name

  # HTTP trigger for manual testing and webhook integration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  # Environment variables for function configuration
  environment_variables = {
    PROJECT_ID    = var.project_id
    ZONE          = var.zone
    INSTANCE_NAME = local.instance_name
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_service.required_apis
  ]
}

# Cloud Monitoring Dashboard for AlloyDB Omni performance
resource "google_monitoring_dashboard" "alloydb_performance" {
  count        = var.enable_monitoring ? 1 : 0
  dashboard_id = "${local.instance_name}-dashboard"
  display_name = "AlloyDB Omni Performance Dashboard"

  dashboard_json = jsonencode({
    displayName = "AlloyDB Omni Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${local.instance_name}\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = {
                label = "CPU Utilization %"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Disk IOPS"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${local.instance_name}\" AND metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
              yAxis = {
                label = "IOPS"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "Memory Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${local.instance_name}\" AND metric.type=\"compute.googleapis.com/instance/memory/utilization\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = {
                label = "Memory Utilization %"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          yPos = 4
          widget = {
            title = "Disk Throughput"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${local.instance_name}\" AND metric.type=\"compute.googleapis.com/instance/disk/read_bytes_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
              yAxis = {
                label = "Bytes/sec"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_compute_instance.alloydb_instance,
    google_project_service.required_apis
  ]
}

# Alert policy for high CPU utilization
resource "google_monitoring_alert_policy" "high_cpu_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "AlloyDB Omni High CPU Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU utilization high"
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${local.instance_name}\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      duration       = var.alert_duration
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.cpu_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Alert strategy configuration
  alert_strategy {
    auto_close = "1800s"
  }

  # Notification channels would be added here in production
  documentation {
    content = "AlloyDB Omni instance ${local.instance_name} has high CPU utilization. Consider scaling or optimizing database queries."
    mime_type = "text/markdown"
  }

  depends_on = [
    google_compute_instance.alloydb_instance,
    google_project_service.required_apis
  ]
}

# Firewall rule to allow AlloyDB Omni access (PostgreSQL port 5432)
resource "google_compute_firewall" "alloydb_access" {
  name    = "${local.instance_name}-alloydb-access"
  network = var.network_name

  description = "Allow access to AlloyDB Omni PostgreSQL port"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Restrict source ranges as needed for security
  source_ranges = ["0.0.0.0/0"]  # WARNING: This allows access from anywhere
  target_tags   = ["alloydb-omni"]

  depends_on = [google_project_service.required_apis]
}

# Create function template file
resource "local_file" "function_template" {
  count    = var.enable_cloud_function ? 1 : 0
  filename = "${path.module}/function-main.py.tpl"
  content = <<-EOF
import json
from google.cloud import compute_v1
from google.cloud import monitoring_v3
import functions_framework
import os

@functions_framework.http
def scale_performance(request):
    """Scale AlloyDB Omni performance based on metrics."""
    
    # Initialize clients
    compute_client = compute_v1.InstancesClient()
    monitoring_client = monitoring_v3.MetricServiceClient()
    
    project_id = "${project_id}"
    zone = "${zone}"
    instance_name = "${instance_name}"
    
    try:
        # Get current instance details
        instance = compute_client.get(
            project=project_id,
            zone=zone,
            instance=instance_name
        )
        
        # Get current machine type
        current_machine_type = instance.machine_type.split("/")[-1]
        
        # In a production environment, you would implement actual scaling logic here
        # based on monitoring metrics, database performance indicators, etc.
        
        # Return scaling recommendation
        return {
            "status": "success",
            "current_machine_type": current_machine_type,
            "instance_status": instance.status,
            "recommendation": "Monitor CPU and memory metrics for scaling decisions",
            "zone": zone,
            "instance_name": instance_name,
            "message": "Performance scaling function executed successfully"
        }
        
    except Exception as e:
        return {
            "status": "error", 
            "message": str(e),
            "instance_name": instance_name
        }
EOF
}