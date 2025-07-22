# GCP OS Patch Management Infrastructure with VM Manager and Cloud Scheduler
# This Terraform configuration creates a comprehensive patch management system
# including VM instances, Cloud Functions, Cloud Scheduler, and monitoring

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and labeling
locals {
  name_prefix = "patch-mgmt-${var.environment}"
  resource_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = var.project_id
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "osconfig.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  # Prevent APIs from being disabled when the resource is destroyed
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create VPC network for patch management infrastructure
resource "google_compute_network" "patch_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  description             = "Network for patch management infrastructure"
  project                 = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create subnet for VM instances
resource "google_compute_subnetwork" "patch_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.patch_network.id
  description   = "Subnet for patch management VM instances"
  project       = var.project_id

  # Enable private Google access for VMs without external IPs
  private_ip_google_access = true

  # Configure flow logs for network monitoring
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Create firewall rules for patch management
resource "google_compute_firewall" "patch_firewall" {
  name    = "${local.name_prefix}-firewall"
  network = google_compute_network.patch_network.name
  project = var.project_id

  # Allow internal communication within the subnet
  allow {
    protocol = "tcp"
    ports    = ["22", "3389", "80", "443"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["patch-management"]

  description = "Firewall rules for patch management infrastructure"
}

# Create firewall rule for SSH access from IAP (Identity-Aware Proxy)
resource "google_compute_firewall" "iap_ssh" {
  name    = "${local.name_prefix}-iap-ssh"
  network = google_compute_network.patch_network.name
  project = var.project_id

  # Allow SSH from IAP
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP source ranges
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["patch-management"]

  description = "Allow SSH access through Identity-Aware Proxy"
}

# Create service account for patch management operations
resource "google_service_account" "patch_management_sa" {
  count        = var.create_service_account ? 1 : 0
  account_id   = "${var.service_account_name}-${random_id.suffix.hex}"
  display_name = "Patch Management Service Account"
  description  = "Service account for VM patch management operations"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for patch management service account
resource "google_project_iam_member" "patch_sa_roles" {
  for_each = var.create_service_account ? toset([
    "roles/compute.osAdminLogin",
    "roles/osconfig.patchJobExecutor",
    "roles/compute.instanceAdmin.v1",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudfunctions.invoker"
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.patch_management_sa[0].email}"
}

# Create VM instances for patch management testing
resource "google_compute_instance" "patch_test_vms" {
  count        = var.vm_instance_count
  name         = "patch-test-vm-${count.index + 1}-${random_id.suffix.hex}"
  machine_type = var.vm_machine_type
  zone         = var.zone
  project      = var.project_id

  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "${var.vm_image_project}/${var.vm_image_family}"
      size  = var.vm_boot_disk_size
      type  = "pd-standard"
    }
  }

  # Network configuration
  network_interface {
    network    = google_compute_network.patch_network.id
    subnetwork = google_compute_subnetwork.patch_subnet.id

    # Optional external IP for testing
    access_config {
      // Ephemeral external IP
    }
  }

  # Metadata configuration for VM Manager
  metadata = {
    enable-osconfig = "TRUE"
    startup-script = <<-EOF
      #!/bin/bash
      # Install OS Config agent (usually pre-installed on newer images)
      curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
      sudo bash add-google-cloud-ops-agent-repo.sh --also-install
      
      # Configure OS Config agent
      sudo systemctl enable google-osconfig-agent
      sudo systemctl start google-osconfig-agent
      
      # Install common tools for patch management
      apt-get update
      apt-get install -y curl wget unzip
      
      # Log startup completion
      echo "VM startup completed at $(date)" >> /var/log/startup.log
    EOF
  }

  # Service account configuration
  service_account {
    email = var.create_service_account ? google_service_account.patch_management_sa[0].email : null
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/osconfig"
    ]
  }

  # Network tags for firewall rules
  tags = ["patch-management", "vm-manager-enabled"]

  # Labels for resource management
  labels = local.resource_labels

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.patch_subnet,
    google_compute_firewall.patch_firewall
  ]
}

# Create Cloud Storage bucket for patch scripts
resource "google_storage_bucket" "patch_scripts" {
  name          = "patch-scripts-${var.project_id}-${random_id.suffix.hex}"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"

  # Versioning configuration
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels for resource management
  labels = local.resource_labels

  depends_on = [google_project_service.required_apis]
}

# Create pre-patch backup script
resource "google_storage_bucket_object" "pre_patch_script" {
  name   = "pre-patch-backup.sh"
  bucket = google_storage_bucket.patch_scripts.name
  content = <<-EOF
    #!/bin/bash
    # Pre-patch backup script
    echo "Starting pre-patch backup at $(date)"
    
    # Create backup directory
    BACKUP_DIR="/tmp/pre-patch-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical system files
    sudo cp -r /etc "$BACKUP_DIR/" 2>/dev/null || true
    sudo cp -r /var/log "$BACKUP_DIR/" 2>/dev/null || true
    
    # Create system information snapshot
    echo "System Information Snapshot" > "$BACKUP_DIR/system-info.txt"
    echo "Date: $(date)" >> "$BACKUP_DIR/system-info.txt"
    echo "Hostname: $(hostname)" >> "$BACKUP_DIR/system-info.txt"
    echo "OS Version: $(lsb_release -d 2>/dev/null || cat /etc/os-release | head -1)" >> "$BACKUP_DIR/system-info.txt"
    echo "Kernel: $(uname -r)" >> "$BACKUP_DIR/system-info.txt"
    echo "Uptime: $(uptime)" >> "$BACKUP_DIR/system-info.txt"
    
    # List installed packages
    if command -v dpkg &> /dev/null; then
      dpkg -l > "$BACKUP_DIR/installed-packages.txt"
    elif command -v rpm &> /dev/null; then
      rpm -qa > "$BACKUP_DIR/installed-packages.txt"
    fi
    
    # Create compressed archive
    cd /tmp
    tar -czf "pre-patch-backup-$(date +%Y%m%d-%H%M%S).tar.gz" "$(basename $BACKUP_DIR)"
    
    # Clean up temporary directory
    rm -rf "$BACKUP_DIR"
    
    echo "Pre-patch backup completed successfully at $(date)"
    
    # Send backup completion metric to Cloud Monitoring
    curl -X POST "https://monitoring.googleapis.com/v3/projects/${var.project_id}/timeSeries" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -H "Content-Type: application/json" \
      -d '{
        "timeSeries": [{
          "resource": {
            "type": "gce_instance",
            "labels": {
              "instance_id": "'$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/id -H "Metadata-Flavor: Google")'",
              "zone": "'$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | cut -d/ -f4)'"
            }
          },
          "metric": {
            "type": "custom.googleapis.com/patch_management/backup_completed",
            "labels": {
              "script_type": "pre-patch"
            }
          },
          "points": [{
            "interval": {
              "endTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            },
            "value": {
              "doubleValue": 1
            }
          }]
        }]
      }' 2>/dev/null || true
  EOF
}

# Create post-patch validation script
resource "google_storage_bucket_object" "post_patch_script" {
  name   = "post-patch-validation.sh"
  bucket = google_storage_bucket.patch_scripts.name
  content = <<-EOF
    #!/bin/bash
    # Post-patch validation script
    echo "Starting post-patch validation at $(date)"
    
    # Initialize validation results
    VALIDATION_RESULTS="/tmp/patch-validation-$(date +%Y%m%d-%H%M%S).log"
    echo "Post-Patch Validation Results" > "$VALIDATION_RESULTS"
    echo "Date: $(date)" >> "$VALIDATION_RESULTS"
    echo "Hostname: $(hostname)" >> "$VALIDATION_RESULTS"
    echo "=================================" >> "$VALIDATION_RESULTS"
    
    # Check system services
    echo "Checking critical system services..." | tee -a "$VALIDATION_RESULTS"
    
    # SSH service
    if systemctl is-active --quiet ssh; then
      echo "✓ SSH service is active" | tee -a "$VALIDATION_RESULTS"
    else
      echo "✗ SSH service is not active" | tee -a "$VALIDATION_RESULTS"
    fi
    
    # Network service
    if systemctl is-active --quiet networking; then
      echo "✓ Networking service is active" | tee -a "$VALIDATION_RESULTS"
    else
      echo "✗ Networking service is not active" | tee -a "$VALIDATION_RESULTS"
    fi
    
    # Check disk space
    echo "Checking disk space..." | tee -a "$VALIDATION_RESULTS"
    df -h | tee -a "$VALIDATION_RESULTS"
    
    # Check for failed services
    echo "Checking for failed services..." | tee -a "$VALIDATION_RESULTS"
    FAILED_SERVICES=$(systemctl --failed --no-legend | wc -l)
    if [ "$FAILED_SERVICES" -eq 0 ]; then
      echo "✓ No failed services detected" | tee -a "$VALIDATION_RESULTS"
    else
      echo "✗ $FAILED_SERVICES failed services detected:" | tee -a "$VALIDATION_RESULTS"
      systemctl --failed --no-legend | tee -a "$VALIDATION_RESULTS"
    fi
    
    # Check system load
    echo "Checking system load..." | tee -a "$VALIDATION_RESULTS"
    uptime | tee -a "$VALIDATION_RESULTS"
    
    # Check memory usage
    echo "Checking memory usage..." | tee -a "$VALIDATION_RESULTS"
    free -h | tee -a "$VALIDATION_RESULTS"
    
    # Check network connectivity
    echo "Checking network connectivity..." | tee -a "$VALIDATION_RESULTS"
    if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
      echo "✓ External network connectivity verified" | tee -a "$VALIDATION_RESULTS"
    else
      echo "✗ External network connectivity failed" | tee -a "$VALIDATION_RESULTS"
    fi
    
    # Check OS Config agent
    if systemctl is-active --quiet google-osconfig-agent; then
      echo "✓ OS Config agent is active" | tee -a "$VALIDATION_RESULTS"
    else
      echo "✗ OS Config agent is not active" | tee -a "$VALIDATION_RESULTS"
    fi
    
    # Summary
    echo "=================================" >> "$VALIDATION_RESULTS"
    echo "Post-patch validation completed at $(date)" | tee -a "$VALIDATION_RESULTS"
    
    # Send validation completion metric to Cloud Monitoring
    curl -X POST "https://monitoring.googleapis.com/v3/projects/${var.project_id}/timeSeries" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -H "Content-Type: application/json" \
      -d '{
        "timeSeries": [{
          "resource": {
            "type": "gce_instance",
            "labels": {
              "instance_id": "'$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/id -H "Metadata-Flavor: Google")'",
              "zone": "'$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | cut -d/ -f4)'"
            }
          },
          "metric": {
            "type": "custom.googleapis.com/patch_management/validation_completed",
            "labels": {
              "script_type": "post-patch"
            }
          },
          "points": [{
            "interval": {
              "endTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            },
            "value": {
              "doubleValue": 1
            }
          }]
        }]
      }' 2>/dev/null || true
    
    echo "Validation results saved to $VALIDATION_RESULTS"
  EOF
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/patch-function-source.zip"
  source {
    content = <<-EOF
      import json
      import os
      import logging
      from google.cloud import osconfig_v1
      from google.cloud import monitoring_v3
      from datetime import datetime
      
      # Configure logging
      logging.basicConfig(level=logging.INFO)
      logger = logging.getLogger(__name__)
      
      def trigger_patch_deployment(request):
          """Cloud Function to trigger VM patch deployment"""
          
          try:
              # Get project information
              project_id = os.environ.get('GCP_PROJECT')
              if not project_id:
                  raise ValueError("GCP_PROJECT environment variable not set")
              
              # Initialize OS Config client
              client = osconfig_v1.OsConfigServiceClient()
              
              # Create patch job configuration
              patch_job = osconfig_v1.PatchJob(
                  description="Automated patch deployment via Cloud Scheduler",
                  instance_filter=osconfig_v1.PatchInstanceFilter(
                      instance_name_prefixes=["patch-test-vm-"]
                  ),
                  patch_config=osconfig_v1.PatchConfig(
                      reboot_config=osconfig_v1.PatchConfig.RebootConfig.${var.patch_reboot_config},
                      pre_step=osconfig_v1.ExecStep(
                          linux_exec_step_config=osconfig_v1.ExecStepConfig(
                              interpreter=osconfig_v1.ExecStepConfig.Interpreter.SHELL,
                              gcs_object=osconfig_v1.GcsObject(
                                  bucket="${google_storage_bucket.patch_scripts.name}",
                                  object="pre-patch-backup.sh"
                              )
                          )
                      ),
                      post_step=osconfig_v1.ExecStep(
                          linux_exec_step_config=osconfig_v1.ExecStepConfig(
                              interpreter=osconfig_v1.ExecStepConfig.Interpreter.SHELL,
                              gcs_object=osconfig_v1.GcsObject(
                                  bucket="${google_storage_bucket.patch_scripts.name}",
                                  object="post-patch-validation.sh"
                              )
                          )
                      ),
                      apt=osconfig_v1.AptSettings(
                          type_=osconfig_v1.AptSettings.Type.UPGRADE
                      )
                  ),
                  duration={"seconds": ${var.patch_duration_seconds}},
                  dry_run=False
              )
              
              # Execute patch job
              parent = f"projects/{project_id}"
              response = client.execute_patch_job(
                  request={"parent": parent, "patch_job": patch_job}
              )
              
              logger.info(f"Patch job started successfully: {response.name}")
              
              # Send success metric to Cloud Monitoring
              monitoring_client = monitoring_v3.MetricServiceClient()
              series = monitoring_v3.TimeSeries()
              series.resource.type = "cloud_function"
              series.resource.labels["function_name"] = os.environ.get('FUNCTION_NAME', 'patch-orchestrator')
              series.resource.labels["region"] = os.environ.get('FUNCTION_REGION', '${var.region}')
              series.metric.type = "custom.googleapis.com/patch_management/deployment_triggered"
              
              point = monitoring_v3.Point()
              point.value.double_value = 1
              point.interval.end_time.seconds = int(datetime.now().timestamp())
              series.points = [point]
              
              monitoring_client.create_time_series(
                  name=f"projects/{project_id}",
                  time_series=[series]
              )
              
              return {
                  "status": "success",
                  "patch_job_name": response.name,
                  "message": f"Patch job {response.name} started successfully",
                  "timestamp": datetime.now().isoformat()
              }
              
          except Exception as e:
              logger.error(f"Error triggering patch deployment: {str(e)}")
              return {
                  "status": "error",
                  "message": f"Failed to trigger patch deployment: {str(e)}",
                  "timestamp": datetime.now().isoformat()
              }, 500
    EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
      google-cloud-os-config==1.17.1
      google-cloud-monitoring==2.16.0
      functions-framework==3.4.0
    EOF
    filename = "requirements.txt"
  }
}

# Upload Cloud Function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "patch-function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.patch_scripts.name
  source = data.archive_file.function_source.output_path
}

# Create Cloud Function for patch orchestration
resource "google_cloudfunctions_function" "patch_orchestrator" {
  name                  = "${local.name_prefix}-orchestrator-${random_id.suffix.hex}"
  description           = "Cloud Function for orchestrating patch deployments"
  runtime               = "python39"
  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.patch_scripts.name
  source_archive_object = google_storage_bucket_object.function_source.name
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  timeout               = 300
  entry_point          = "trigger_patch_deployment"
  region               = var.region
  project              = var.project_id

  # Environment variables
  environment_variables = {
    GCP_PROJECT     = var.project_id
    FUNCTION_REGION = var.region
    PATCH_DURATION  = tostring(var.patch_duration_seconds)
  }

  # Service account
  service_account_email = var.create_service_account ? google_service_account.patch_management_sa[0].email : null

  # Labels
  labels = local.resource_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_storage_bucket_object.pre_patch_script,
    google_storage_bucket_object.post_patch_script
  ]
}

# Create Cloud Scheduler job for automated patch deployment
resource "google_cloud_scheduler_job" "patch_scheduler" {
  name             = "${local.name_prefix}-scheduler-${random_id.suffix.hex}"
  description      = "Automated patch deployment scheduler"
  schedule         = var.patch_schedule
  time_zone        = var.patch_schedule_timezone
  region           = var.region
  project          = var.project_id

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.patch_orchestrator.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled-patch-deployment"
      schedule = var.patch_schedule
    }))
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.patch_orchestrator
  ]
}

# Create Cloud Monitoring dashboard for patch management
resource "google_monitoring_dashboard" "patch_management" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "VM Patch Management Dashboard"
  project      = var.project_id

  dashboard_json = jsonencode({
    displayName = "VM Patch Management Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "VM Instance Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/up\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields = ["resource.label.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                  targetAxis = "Y1"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Instance Status"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 0
          xPos = 6
          widget = {
            title = "Patch Deployment Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"custom.googleapis.com/patch_management/deployment_triggered\""
                      aggregation = {
                        alignmentPeriod = "3600s"
                        perSeriesAligner = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "STACKED_BAR"
                  targetAxis = "Y1"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Deployments per Hour"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 4
          widget = {
            title = "System Load Average"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod = "300s"
                        perSeriesAligner = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields = ["resource.label.instance_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                  targetAxis = "Y1"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create alert policy for patch deployment failures
resource "google_monitoring_alert_policy" "patch_failure_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Patch Deployment Failure Alert"
  project      = var.project_id

  documentation {
    content = "Alert triggered when patch deployment fails on VM instances"
  }

  conditions {
    display_name = "Cloud Function Errors"
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.patch_orchestrator.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields    = ["resource.label.function_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = true

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.patch_orchestrator
  ]
}

# Create alert policy for VM instance down
resource "google_monitoring_alert_policy" "instance_down_alert" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "VM Instance Down Alert"
  project      = var.project_id

  documentation {
    content = "Alert triggered when VM instances are down for patch management"
  }

  conditions {
    display_name = "VM Instance Down"
    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/up\""
      duration       = "300s"
      comparison     = "COMPARISON_LT"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.instance_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  enabled = true

  depends_on = [
    google_project_service.required_apis,
    google_compute_instance.patch_test_vms
  ]
}

# Create log sink for patch management activities
resource "google_logging_project_sink" "patch_logging" {
  count = var.enable_logging ? 1 : 0
  name  = "${local.name_prefix}-logging-sink"

  # Send logs to Cloud Storage for long-term retention
  destination = "storage.googleapis.com/${google_storage_bucket.patch_scripts.name}/logs"

  # Filter for patch-related logs
  filter = <<-EOF
    resource.type="gce_instance"
    AND (
      jsonPayload.message:"patch"
      OR jsonPayload.message:"OS Config"
      OR jsonPayload.message:"osconfig"
      OR protoPayload.methodName:"compute.instances.setMetadata"
      OR protoPayload.methodName:"osconfig.patchJobs.execute"
    )
  EOF

  # Grant Cloud Logging the necessary permissions
  unique_writer_identity = true

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.patch_scripts
  ]
}

# Grant Cloud Logging permissions to write to Cloud Storage
resource "google_storage_bucket_iam_member" "logging_writer" {
  count  = var.enable_logging ? 1 : 0
  bucket = google_storage_bucket.patch_scripts.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.patch_logging[0].writer_identity
}

# Create custom metric descriptors for patch management
resource "google_monitoring_metric_descriptor" "patch_deployment_metric" {
  count       = var.enable_monitoring ? 1 : 0
  type        = "custom.googleapis.com/patch_management/deployment_triggered"
  display_name = "Patch Deployment Triggered"
  description = "Number of patch deployments triggered"
  metric_kind = "GAUGE"
  value_type  = "DOUBLE"
  project     = var.project_id
  
  labels {
    key         = "function_name"
    value_type  = "STRING"
    description = "Name of the Cloud Function that triggered the deployment"
  }
  
  labels {
    key         = "deployment_type"
    value_type  = "STRING"
    description = "Type of patch deployment (scheduled, manual, emergency)"
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_metric_descriptor" "patch_backup_metric" {
  count       = var.enable_monitoring ? 1 : 0
  type        = "custom.googleapis.com/patch_management/backup_completed"
  display_name = "Patch Backup Completed"
  description = "Number of successful pre-patch backups"
  metric_kind = "GAUGE"
  value_type  = "DOUBLE"
  project     = var.project_id
  
  labels {
    key         = "script_type"
    value_type  = "STRING"
    description = "Type of script executed (pre-patch, post-patch)"
  }
  
  labels {
    key         = "instance_name"
    value_type  = "STRING"
    description = "Name of the VM instance"
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_metric_descriptor" "patch_validation_metric" {
  count       = var.enable_monitoring ? 1 : 0
  type        = "custom.googleapis.com/patch_management/validation_completed"
  display_name = "Patch Validation Completed"
  description = "Number of successful post-patch validations"
  metric_kind = "GAUGE"
  value_type  = "DOUBLE"
  project     = var.project_id
  
  labels {
    key         = "script_type"
    value_type  = "STRING"
    description = "Type of script executed (pre-patch, post-patch)"
  }
  
  labels {
    key         = "validation_status"
    value_type  = "STRING"
    description = "Status of the validation (success, warning, error)"
  }

  depends_on = [google_project_service.required_apis]
}