# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for project information
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

data "google_billing_account" "current" {
  count           = var.enable_monitoring ? 1 : 0
  billing_account = data.google_project.current.billing_account
}

# Enable required APIs for HPC workloads
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "batch.googleapis.com",
    "container.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbilling.googleapis.com",
    "serviceusage.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]

  create_duration = "60s"
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# VPC Network for HPC cluster with optimized configuration
resource "google_compute_network" "hpc_vpc" {
  name                    = "${var.vpc_name}-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  mtu                     = 8896 # Jumbo frames for high-performance computing
  
  depends_on = [time_sleep.wait_for_apis]
}

# Subnet for HPC compute instances with private Google access
resource "google_compute_subnetwork" "hpc_subnet" {
  name          = "${var.subnet_name}-${random_id.suffix.hex}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.hpc_vpc.id

  # Enable private Google access for instances without external IPs
  private_ip_google_access = true

  # Secondary IP ranges for container networking if needed
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rules for HPC cluster communication
resource "google_compute_firewall" "hpc_internal" {
  name    = "hpc-internal-${random_id.suffix.hex}"
  network = google_compute_network.hpc_vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["hpc-cluster"]

  description = "Allow internal communication within HPC cluster"
}

# Firewall rule for SSH access
resource "google_compute_firewall" "hpc_ssh" {
  name    = "hpc-ssh-${random_id.suffix.hex}"
  network = google_compute_network.hpc_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # Google Cloud IAP IP range
  target_tags   = ["hpc-cluster"]

  description = "Allow SSH access via Cloud IAP"
}

# Cloud NAT for outbound internet access from private instances
resource "google_compute_router" "hpc_router" {
  name    = "hpc-router-${random_id.suffix.hex}"
  region  = var.region
  network = google_compute_network.hpc_vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "hpc_nat" {
  name                               = "hpc-nat-${random_id.suffix.hex}"
  router                             = google_compute_router.hpc_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================================================
# STORAGE INFRASTRUCTURE
# ============================================================================

# High-performance Cloud Storage bucket for HPC data
resource "google_storage_bucket" "hpc_data" {
  name          = "${var.hpc_bucket_name}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = var.storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle rules for cost optimization
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

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # Delete non-current versions after 30 days
  lifecycle_rule {
    condition {
      age                   = 30
      with_state           = "ARCHIVED"
      matches_storage_class = []
    }
    action {
      type = "Delete"
    }
  }

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Enable logging for access patterns
  logging {
    log_bucket        = google_storage_bucket.hpc_logs.name
    log_object_prefix = "access-logs/"
  }

  labels = var.labels

  depends_on = [time_sleep.wait_for_apis]
}

# Separate bucket for logs to avoid circular dependencies
resource "google_storage_bucket" "hpc_logs" {
  name          = "${var.hpc_bucket_name}-logs-${random_id.suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  labels                     = var.labels

  depends_on = [time_sleep.wait_for_apis]
}

# ============================================================================
# PLACEMENT POLICY FOR HIGH-PERFORMANCE COMPUTING
# ============================================================================

# Placement policy for low-latency communication between HPC nodes
resource "google_compute_resource_policy" "hpc_placement" {
  name   = "hpc-placement-${random_id.suffix.hex}"
  region = var.region

  group_placement_policy {
    vm_count                = var.hpc_instance_count
    availability_domain_count = 1
    collocation             = "COLLOCATED"
  }

  description = "Placement policy for HPC cluster nodes to ensure low-latency communication"
}

# ============================================================================
# HPC COMPUTE INSTANCES
# ============================================================================

# Service account for HPC compute instances
resource "google_service_account" "hpc_compute" {
  account_id   = "hpc-compute-${random_id.suffix.hex}"
  display_name = "HPC Compute Service Account"
  description  = "Service account for HPC compute instances"
}

# IAM bindings for HPC compute service account
resource "google_project_iam_member" "hpc_compute_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.hpc_compute.email}"
}

resource "google_project_iam_member" "hpc_compute_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.hpc_compute.email}"
}

resource "google_project_iam_member" "hpc_compute_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.hpc_compute.email}"
}

resource "google_project_iam_member" "hpc_compute_batch" {
  project = var.project_id
  role    = "roles/batch.agentReporter"
  member  = "serviceAccount:${google_service_account.hpc_compute.email}"
}

# Instance template for HPC compute nodes
resource "google_compute_instance_template" "hpc_template" {
  name_prefix  = "hpc-template-${random_id.suffix.hex}-"
  machine_type = var.hpc_machine_type

  disk {
    source_image = "${var.hpc_image_project}/${var.hpc_image_family}"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.hpc_disk_size
    disk_type    = var.disk_type
  }

  network_interface {
    network    = google_compute_network.hpc_vpc.id
    subnetwork = google_compute_subnetwork.hpc_subnet.id
    # No external IP - use Cloud NAT for outbound access
  }

  service_account {
    email  = google_service_account.hpc_compute.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data = base64encode(templatefile("${path.module}/scripts/hpc-startup.sh", {
      bucket_name = google_storage_bucket.hpc_data.name
      project_id  = var.project_id
    }))
  }

  tags = ["hpc-cluster", "hpc-compute"]

  labels = var.labels

  # Resource policies for placement
  resource_policies = [google_compute_resource_policy.hpc_placement.id]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Managed instance group for HPC compute nodes
resource "google_compute_instance_group_manager" "hpc_mig" {
  name               = "hpc-mig-${random_id.suffix.hex}"
  base_instance_name = "hpc-worker"
  zone               = var.zone
  target_size        = var.hpc_instance_count

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_health_check.hpc_health.id
    initial_delay_sec = 300
  }

  # Update policy
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 1
    max_unavailable_fixed        = 0
  }

  named_port {
    name = "ssh"
    port = 22
  }

  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Health check for HPC instances
resource "google_compute_health_check" "hpc_health" {
  name                = "hpc-health-${random_id.suffix.hex}"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "22"
  }
}

# ============================================================================
# GPU COMPUTE INSTANCES
# ============================================================================

# Instance template for GPU compute nodes
resource "google_compute_instance_template" "gpu_template" {
  count = var.gpu_instance_count > 0 ? 1 : 0
  
  name_prefix  = "gpu-template-${random_id.suffix.hex}-"
  machine_type = var.gpu_machine_type

  disk {
    source_image = "${var.gpu_image_project}/${var.gpu_image_family}"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.gpu_disk_size
    disk_type    = var.disk_type
  }

  network_interface {
    network    = google_compute_network.hpc_vpc.id
    subnetwork = google_compute_subnetwork.hpc_subnet.id
    # No external IP - use Cloud NAT for outbound access
  }

  # GPU configuration
  guest_accelerator {
    type  = var.gpu_type
    count = var.gpu_count
  }

  # GPU instances require specific scheduling
  scheduling {
    on_host_maintenance = "TERMINATE"
  }

  service_account {
    email  = google_service_account.hpc_compute.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata = {
    enable-oslogin           = "TRUE"
    install-nvidia-driver    = "True"
    user-data = base64encode(templatefile("${path.module}/scripts/gpu-startup.sh", {
      bucket_name = google_storage_bucket.hpc_data.name
      project_id  = var.project_id
    }))
  }

  tags = ["hpc-cluster", "gpu-compute"]

  labels = var.labels

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [time_sleep.wait_for_apis]
}

# Managed instance group for GPU compute nodes
resource "google_compute_instance_group_manager" "gpu_mig" {
  count = var.gpu_instance_count > 0 ? 1 : 0
  
  name               = "gpu-mig-${random_id.suffix.hex}"
  base_instance_name = "gpu-worker"
  zone               = var.zone
  target_size        = var.gpu_instance_count

  version {
    instance_template = google_compute_instance_template.gpu_template[0].id
  }

  # Auto-healing configuration
  auto_healing_policies {
    health_check      = google_compute_health_check.gpu_health[0].id
    initial_delay_sec = 600 # GPU instances take longer to initialize
  }

  # Update policy
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 1
    max_unavailable_fixed        = 0
  }

  named_port {
    name = "ssh"
    port = 22
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# Health check for GPU instances
resource "google_compute_health_check" "gpu_health" {
  count = var.gpu_instance_count > 0 ? 1 : 0
  
  name                = "gpu-health-${random_id.suffix.hex}"
  check_interval_sec  = 60
  timeout_sec         = 20
  healthy_threshold   = 2
  unhealthy_threshold = 5

  tcp_health_check {
    port = "22"
  }
}

# ============================================================================
# GPU RESERVATIONS FOR PREDICTABLE ACCESS
# ============================================================================

# Future GPU reservation for predictable access
resource "google_compute_reservation" "gpu_reservation" {
  count = var.enable_gpu_reservation && var.gpu_instance_count > 0 ? 1 : 0
  
  name = "hpc-gpu-reservation-${random_id.suffix.hex}"
  zone = var.zone

  specific_reservation {
    count = 2
    instance_properties {
      machine_type = var.gpu_machine_type
      guest_accelerators {
        accelerator_type  = var.gpu_type
        accelerator_count = var.gpu_count
      }
    }
  }

  # Commitment configuration for cost optimization
  specific_reservation_required = true

  description = "GPU reservation for predictable HPC workload access"
}

# ============================================================================
# CLOUD BATCH CONFIGURATION
# ============================================================================

# Sample batch job for HPC workload with spot instances
resource "google_batch_job" "hpc_spot_job" {
  count = var.enable_batch_jobs ? 1 : 0
  
  name     = "hpc-spot-job-${random_id.suffix.hex}"
  location = var.region

  task_groups {
    task_count  = var.batch_task_count
    parallelism = var.batch_parallelism

    task_spec {
      compute_resource {
        cpu_milli      = 8000
        memory_mib     = 16384
        boot_disk_mib  = 10240
      }

      max_retry_count = 2
      max_run_duration = "1800s"

      runnables {
        script {
          text = templatefile("${path.module}/scripts/batch-workload.sh", {
            bucket_name = google_storage_bucket.hpc_data.name
            project_id  = var.project_id
          })
        }
      }

      environment {
        variables = {
          PROJECT_ID   = var.project_id
          BUCKET_NAME  = google_storage_bucket.hpc_data.name
          JOB_INDEX    = "$BATCH_TASK_INDEX"
        }
      }
    }
  }

  allocation_policy {
    instances {
      policy {
        machine_type       = var.batch_machine_type
        provisioning_model = "SPOT"
      }
    }

    location {
      allowed_locations = ["zones/${var.zone}"]
    }

    service_account {
      email = google_service_account.hpc_compute.email
    }
  }

  logs_policy {
    destination = "CLOUD_LOGGING"
  }

  labels = var.labels

  depends_on = [
    google_project_iam_member.hpc_compute_batch,
    time_sleep.wait_for_apis
  ]
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Monitoring dashboard for HPC cluster
resource "google_monitoring_dashboard" "hpc_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "HPC Cluster Monitoring - ${random_id.suffix.hex}"
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
                    filter = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"hpc-worker.*\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner  = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields     = ["resource.label.instance_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "GPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\""
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Batch Job Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/num_tasks_per_state\""
                }
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Storage Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${google_storage_bucket.hpc_data.name}\""
                    aggregation = {
                      alignmentPeriod   = "3600s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
}

# Budget alert for cost monitoring
resource "google_billing_budget" "hpc_budget" {
  count = var.enable_monitoring && length(data.google_billing_account.current) > 0 ? 1 : 0
  
  billing_account = data.google_billing_account.current[0].billing_account
  display_name    = "HPC Cluster Budget Alert - ${random_id.suffix.hex}"

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    labels = {
      for k, v in var.labels : "labels.${k}" => v
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

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget_alerts[0].id
    schema_version                   = "1.0"
    monitoring_notification_channels = []
  }
}

# Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  count = var.enable_monitoring ? 1 : 0
  
  name = "hpc-budget-alerts-${random_id.suffix.hex}"

  labels = var.labels
}

# Alert policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "HPC High CPU Usage - ${random_id.suffix.hex}"
  combiner     = "OR"

  conditions {
    display_name = "HPC Instance High CPU"

    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"hpc-worker.*\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.9

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = []

  documentation {
    content = "High CPU usage detected on HPC cluster instances. Consider scaling up or optimizing workloads."
  }
}

# Alert policy for GPU utilization
resource "google_monitoring_alert_policy" "gpu_utilization" {
  count = var.enable_monitoring && var.gpu_instance_count > 0 ? 1 : 0
  
  display_name = "HPC GPU Utilization - ${random_id.suffix.hex}"
  combiner     = "OR"

  conditions {
    display_name = "Low GPU Utilization"

    condition_threshold {
      filter         = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/accelerator/utilization\""
      duration       = "900s"
      comparison     = "COMPARISON_LT"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "3600s"
  }

  notification_channels = []

  documentation {
    content = "Low GPU utilization detected. Consider optimizing GPU workloads or scaling down instances."
  }
}