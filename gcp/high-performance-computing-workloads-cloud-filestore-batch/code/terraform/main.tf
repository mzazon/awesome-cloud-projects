# Main Terraform configuration for High-Performance Computing workloads
# with Cloud Filestore and Batch processing infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Create unique resource names using random suffix
  resource_suffix = lower(random_id.suffix.hex)
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    terraform   = "true"
    component   = "hpc-infrastructure"
  })

  # Startup script for compute instances to mount Filestore
  startup_script = templatefile("${path.module}/scripts/startup.sh", {
    filestore_ip        = google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]
    file_share_name     = var.filestore_file_share_name
    mount_point         = "/mnt/${var.filestore_file_share_name}"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "file.googleapis.com",
    "batch.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])

  service = each.value
  
  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

# Create VPC network for HPC infrastructure
resource "google_compute_network" "hpc_network" {
  name                    = "${var.network_name}-${local.resource_suffix}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for HPC compute and storage resources
resource "google_compute_subnetwork" "hpc_subnet" {
  name          = "${var.subnet_name}-${local.resource_suffix}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.hpc_network.id
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true
  
  # Enable flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rule for internal communication
resource "google_compute_firewall" "hpc_internal" {
  name    = "${var.network_name}-allow-internal-${local.resource_suffix}"
  network = google_compute_network.hpc_network.name

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
  target_tags   = ["hpc-compute"]
}

# Create firewall rule for SSH access (if needed for debugging)
resource "google_compute_firewall" "hpc_ssh" {
  name    = "${var.network_name}-allow-ssh-${local.resource_suffix}"
  network = google_compute_network.hpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP range
  target_tags   = ["hpc-compute"]
}

# Create firewall rule for NFS traffic to Filestore
resource "google_compute_firewall" "hpc_nfs" {
  name    = "${var.network_name}-allow-nfs-${local.resource_suffix}"
  network = google_compute_network.hpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["2049", "111"]
  }

  allow {
    protocol = "udp"
    ports    = ["2049", "111"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["filestore"]
}

# Create high-performance Cloud Filestore instance
resource "google_filestore_instance" "hpc_storage" {
  name     = "${var.filestore_name}-${local.resource_suffix}"
  location = var.zone
  tier     = var.filestore_tier

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = var.filestore_file_share_name
    
    # NFS export options for HPC workloads
    nfs_export_options {
      ip_ranges   = [var.subnet_cidr]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network = google_compute_network.hpc_network.name
    modes   = ["MODE_IPV4"]
    
    # Reserve IP address for consistent access
    reserved_ip_range = "10.0.255.0/29"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.hpc_subnet
  ]
}

# Create startup script for compute instances
resource "local_file" "startup_script" {
  content = templatefile("${path.module}/startup_template.sh", {
    filestore_ip    = google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]
    file_share_name = var.filestore_file_share_name
    mount_point     = "/mnt/${var.filestore_file_share_name}"
  })
  filename = "${path.module}/scripts/startup.sh"
}

# Create compute instance template for HPC nodes
resource "google_compute_instance_template" "hpc_template" {
  name_prefix  = "${var.instance_template_name}-${local.resource_suffix}-"
  machine_type = var.instance_machine_type
  region       = var.region

  # Use Ubuntu 20.04 LTS for compatibility
  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = "pd-standard"
  }

  network_interface {
    network    = google_compute_network.hpc_network.id
    subnetwork = google_compute_subnetwork.hpc_subnet.id
    
    # No external IP - use Cloud NAT or private Google access
    access_config {
      network_tier = "PREMIUM"
    }
  }

  # Metadata and startup script for Filestore mounting
  metadata = {
    startup-script = templatefile("${path.module}/startup_template.sh", {
      filestore_ip    = google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]
      file_share_name = var.filestore_file_share_name
      mount_point     = "/mnt/${var.filestore_file_share_name}"
    })
    enable-oslogin = "TRUE"
  }

  # Service account with necessary permissions
  service_account {
    email = google_service_account.hpc_compute.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/logging.write"
    ]
  }

  tags = ["hpc-compute"]

  labels = local.common_labels

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_filestore_instance.hpc_storage
  ]
}

# Create service account for HPC compute instances
resource "google_service_account" "hpc_compute" {
  account_id   = "hpc-compute-${local.resource_suffix}"
  display_name = "HPC Compute Service Account"
  description  = "Service account for HPC compute instances"
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "hpc_compute_roles" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/batch.jobsEditor"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.hpc_compute.email}"
}

# Create managed instance group for auto-scaling
resource "google_compute_region_instance_group_manager" "hpc_group" {
  name   = "${var.instance_group_name}-${local.resource_suffix}"
  region = var.region

  base_instance_name = "hpc-node"
  target_size        = var.autoscaler_min_replicas

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  # Health check for instance management
  auto_healing_policies {
    health_check      = google_compute_health_check.hpc_health_check.id
    initial_delay_sec = 300
  }

  # Update policy for rolling updates
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
  }

  depends_on = [
    google_compute_instance_template.hpc_template
  ]
}

# Create health check for managed instance group
resource "google_compute_health_check" "hpc_health_check" {
  name               = "hpc-health-check-${local.resource_suffix}"
  check_interval_sec = 30
  timeout_sec        = 10

  tcp_health_check {
    port = "22"
  }
}

# Create autoscaler for the managed instance group
resource "google_compute_region_autoscaler" "hpc_autoscaler" {
  name   = "hpc-autoscaler-${local.resource_suffix}"
  region = var.region
  target = google_compute_region_instance_group_manager.hpc_group.id

  autoscaling_policy {
    max_replicas    = var.autoscaler_max_replicas
    min_replicas    = var.autoscaler_min_replicas
    cooldown_period = 300

    cpu_utilization {
      target = var.autoscaler_cpu_target
    }
  }
}

# Create Cloud Monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.monitoring_notification_email != "" ? 1 : 0
  
  display_name = "HPC Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.monitoring_notification_email
  }
}

# Create monitoring alert policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "HPC High CPU Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "CPU usage above 80%"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"hpc-node-.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.monitoring_notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Create monitoring alert policy for Filestore capacity
resource "google_monitoring_alert_policy" "filestore_capacity" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Filestore High Capacity Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Filestore capacity above 85%"
    
    condition_threshold {
      filter          = "resource.type=\"filestore_instance\" AND resource.labels.instance_id=\"${google_filestore_instance.hpc_storage.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.85
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.monitoring_notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Create monitoring dashboard for HPC infrastructure
resource "google_monitoring_dashboard" "hpc_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "HPC Infrastructure Monitoring"
    
    gridLayout = {
      widgets = [
        {
          title = "Compute Instance CPU Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"hpc-node-.*\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields = ["resource.labels.instance_name"]
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        },
        {
          title = "Filestore Capacity Usage"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"filestore_instance\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }
            ]
          }
        }
      ]
    }
  })
}

# Create startup script template
resource "local_file" "startup_template" {
  content = <<-EOF
#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get install -y nfs-common htop iotop

# Create mount point
mkdir -p ${mount_point}

# Mount Filestore NFS share
mount -t nfs ${filestore_ip}:/${file_share_name} ${mount_point}

# Add to fstab for persistent mounting
echo "${filestore_ip}:/${file_share_name} ${mount_point} nfs defaults 0 0" >> /etc/fstab

# Set appropriate permissions
chmod 755 ${mount_point}

# Create results directory
mkdir -p ${mount_point}/results
mkdir -p ${mount_point}/data
mkdir -p ${mount_point}/logs

# Install monitoring agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Log successful setup
echo "$(date): HPC node setup completed successfully" >> /var/log/hpc-setup.log
echo "$(date): Filestore mounted at ${mount_point}" >> /var/log/hpc-setup.log

# Signal healthy status
systemctl enable google-cloud-ops-agent
systemctl start google-cloud-ops-agent
EOF

  filename = "${path.module}/startup_template.sh"
}