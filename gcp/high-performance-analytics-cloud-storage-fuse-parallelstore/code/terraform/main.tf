# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed names and configurations
locals {
  resource_suffix        = random_id.suffix.hex
  bucket_name           = "${var.resource_prefix}-data-${local.resource_suffix}"
  parallelstore_name    = "${var.resource_prefix}-store-${local.resource_suffix}"
  vm_name              = "${var.resource_prefix}-vm-${local.resource_suffix}"
  dataproc_cluster_name = "${var.resource_prefix}-cluster-${local.resource_suffix}"
  service_account_id    = "${var.resource_prefix}-sa-${local.resource_suffix}"
  dataset_id           = replace("${var.resource_prefix}_analytics_${local.resource_suffix}", "-", "_")
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    recipe       = "high-performance-analytics-cloud-storage-fuse-parallelstore"
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "storage.googleapis.com",
    "dataproc.googleapis.com",
    "bigquery.googleapis.com",
    "parallelstore.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for high-performance analytics workloads
resource "google_service_account" "analytics_sa" {
  count = var.create_service_account ? 1 : 0
  
  account_id   = local.service_account_id
  display_name = "High-Performance Analytics Service Account"
  description  = "Service account for managing high-performance analytics resources with Cloud Storage FUSE and Parallelstore"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "analytics_sa_roles" {
  for_each = var.create_service_account ? toset(var.service_account_roles) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.analytics_sa[0].email}"
  
  depends_on = [google_service_account.analytics_sa]
}

# Create Cloud Storage bucket with hierarchical namespace for optimal performance
resource "google_storage_bucket" "analytics_data" {
  name     = local.bucket_name
  location = var.bucket_location
  project  = var.project_id
  
  # Enable hierarchical namespace for POSIX-like file system semantics
  hierarchical_namespace {
    enabled = true
  }
  
  # Configure storage class for performance and cost optimization
  storage_class = var.bucket_storage_class
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age                    = 30
      matches_storage_class  = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age                   = 90
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Configure uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Apply labels for resource organization
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Grant storage permissions to the service account
resource "google_storage_bucket_iam_member" "analytics_sa_storage_admin" {
  count = var.create_service_account ? 1 : 0
  
  bucket = google_storage_bucket.analytics_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.analytics_sa[0].email}"
}

# Create sample data structure in Cloud Storage for testing
resource "google_storage_bucket_object" "sample_data_structure" {
  count = var.create_sample_data ? 1 : 0
  
  name   = "sample_data/raw/2024/01/.gitkeep"
  bucket = google_storage_bucket.analytics_data.name
  source = "/dev/null"
}

# Create Parallelstore instance for high-performance storage
resource "google_parallelstore_instance" "hpc_storage" {
  provider = google-beta
  
  instance_id = local.parallelstore_name
  location    = var.zone
  project     = var.project_id
  
  description = "High-performance parallel storage for analytics workloads using DAOS technology"
  
  capacity_gib = var.parallelstore_capacity_gib
  
  # Configure network for Parallelstore access
  network = var.network_name != "" ? "projects/${var.project_id}/global/networks/${var.network_name}" : "projects/${var.project_id}/global/networks/default"
  
  # Configure file and directory stripe levels for balanced performance
  file_stripe_level      = "FILE_STRIPE_LEVEL_BALANCED"
  directory_stripe_level = "DIRECTORY_STRIPE_LEVEL_BALANCED"
  
  # Apply labels for resource organization
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create startup script for VM configuration
resource "local_file" "vm_startup_script" {
  filename = "${path.module}/startup-script.sh"
  content = templatefile("${path.module}/startup-script.tpl", {
    bucket_name        = google_storage_bucket.analytics_data.name
    parallelstore_ip   = google_parallelstore_instance.hpc_storage.access_points[0].access_point_ip
    service_account    = var.create_service_account ? google_service_account.analytics_sa[0].email : ""
  })
}

# Create analytics VM with Cloud Storage FUSE and Parallelstore mounts
resource "google_compute_instance" "analytics_vm" {
  name         = local.vm_name
  machine_type = var.vm_machine_type
  zone         = var.zone
  project      = var.project_id
  
  # Configure boot disk with appropriate size and type
  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"
      size  = var.vm_boot_disk_size
      type  = var.vm_boot_disk_type
      labels = local.common_labels
    }
  }
  
  # Configure network interface
  network_interface {
    network    = var.network_name != "" ? var.network_name : "default"
    subnetwork = var.subnet_name != "" ? var.subnet_name : null
    
    # Assign external IP for management access
    access_config {
      # Ephemeral external IP
    }
  }
  
  # Configure service account and scopes
  service_account {
    email = var.create_service_account ? google_service_account.analytics_sa[0].email : null
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # Configure security features
  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                = var.enable_vtpm
    enable_integrity_monitoring = var.enable_integrity_monitoring
  }
  
  # Configure metadata and startup script
  metadata = {
    enable-oslogin = "TRUE"
    startup-script = local_file.vm_startup_script.content
  }
  
  # Apply labels for resource organization
  labels = local.common_labels
  
  # Configure VM to allow stopping for maintenance
  allow_stopping_for_update = true
  
  depends_on = [
    google_project_service.required_apis,
    google_parallelstore_instance.hpc_storage,
    google_storage_bucket.analytics_data
  ]
}

# Create Cloud Dataproc cluster with high-performance storage integration
resource "google_dataproc_cluster" "analytics_cluster" {
  name   = local.dataproc_cluster_name
  region = var.region
  project = var.project_id
  
  cluster_config {
    # Configure staging bucket for Dataproc operations
    staging_bucket = google_storage_bucket.analytics_data.name
    
    # Configure master node
    master_config {
      num_instances = 1
      machine_type  = var.dataproc_master_machine_type
      
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 200
      }
    }
    
    # Configure worker nodes
    worker_config {
      num_instances = var.dataproc_num_workers
      machine_type  = var.dataproc_worker_machine_type
      
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 200
      }
    }
    
    # Configure software and image version
    software_config {
      image_version = var.dataproc_image_version
      
      # Enable optional components for analytics
      optional_components = [
        "JUPYTER",
        "ZEPPELIN"
      ]
      
      # Configure properties for optimal performance
      properties = {
        "dataproc:dataproc.conscrypt.provider.enable" = "false"
        "spark:spark.sql.adaptive.enabled"            = "true"
        "spark:spark.sql.adaptive.coalescePartitions.enabled" = "true"
        "spark:spark.serializer"                      = "org.apache.spark.serializer.KryoSerializer"
        "spark:spark.sql.execution.arrow.pyspark.enabled" = "true"
      }
    }
    
    # Configure initialization actions for Cloud Storage FUSE
    initialization_action {
      script      = "gs://goog-dataproc-initialization-actions-${var.region}/cloud-storage-fuse/cloud-storage-fuse.sh"
      timeout_sec = 1200
    }
    
    # Configure endpoint access
    endpoint_config {
      enable_http_port_access = true
    }
    
    # Configure security and network access
    gce_cluster_config {
      service_account = var.create_service_account ? google_service_account.analytics_sa[0].email : null
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
      
      network    = var.network_name != "" ? var.network_name : "default"
      subnetwork = var.subnet_name != "" ? var.subnet_name : null
      
      # Configure metadata for Parallelstore integration
      metadata = {
        "parallel-store-ip"  = google_parallelstore_instance.hpc_storage.access_points[0].access_point_ip
        "enable-cloud-sql-hive-metastore" = "true"
      }
      
      # Apply labels for resource organization
      tags = ["analytics", "dataproc", "hpc"]
    }
  }
  
  # Apply labels for resource organization
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_parallelstore_instance.hpc_storage,
    google_storage_bucket.analytics_data,
    google_service_account.analytics_sa
  ]
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id  = local.dataset_id
  project     = var.project_id
  location    = var.bigquery_dataset_location
  description = var.bigquery_dataset_description
  
  # Configure access controls
  access {
    role          = "OWNER"
    user_by_email = var.create_service_account ? google_service_account.analytics_sa[0].email : data.google_client_config.current.client_email
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  # Configure dataset labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery external table for processed analytics data
resource "google_bigquery_table" "sensor_analytics" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "sensor_analytics"
  project    = var.project_id
  
  description = "External table for sensor analytics data processed through high-performance pipeline"
  
  external_data_configuration {
    autodetect    = false
    source_format = "PARQUET"
    source_uris   = ["gs://${google_storage_bucket.analytics_data.name}/sample_data/processed/analytics/*"]
    
    # Define schema for the external table
    schema = jsonencode([
      {
        name = "sensor_id"
        type = "STRING"
        mode = "REQUIRED"
      },
      {
        name = "avg_value"
        type = "FLOAT"
        mode = "NULLABLE"
      },
      {
        name = "max_value"
        type = "FLOAT"
        mode = "NULLABLE"
      },
      {
        name = "min_value"
        type = "FLOAT"
        mode = "NULLABLE"
      }
    ])
  }
  
  # Configure table labels
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.analytics_dataset]
}

# Create analytics pipeline script
resource "local_file" "analytics_pipeline" {
  filename = "${path.module}/analytics_pipeline.py"
  content = templatefile("${path.module}/analytics_pipeline.tpl", {
    bucket_name = google_storage_bucket.analytics_data.name
    project_id  = var.project_id
    dataset_id  = google_bigquery_dataset.analytics_dataset.dataset_id
  })
}

# Create Cloud Monitoring alert policy for Parallelstore performance
resource "google_monitoring_alert_policy" "parallelstore_performance" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Parallelstore High Latency Alert"
  project      = var.project_id
  
  documentation {
    content = "Alert when Parallelstore experiences high latency that could impact analytics performance"
  }
  
  conditions {
    display_name = "Parallelstore High Latency Condition"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"${google_compute_instance.analytics_vm.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 100
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.monitoring_notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring custom metric for Parallelstore throughput
resource "google_logging_metric" "parallelstore_throughput" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "parallelstore_throughput"
  project = var.project_id
  
  description = "Track Parallelstore throughput metrics for performance monitoring"
  filter      = "resource.type=\"gce_instance\" AND \"parallelstore\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Parallelstore Throughput"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Get current client configuration for default access
data "google_client_config" "current" {}

# Create firewall rules for secure access (if using custom network)
resource "google_compute_firewall" "analytics_ssh" {
  count = var.network_name != "" ? 1 : 0
  
  name    = "${var.resource_prefix}-allow-ssh-${local.resource_suffix}"
  network = var.network_name
  project = var.project_id
  
  description = "Allow SSH access to analytics VM for management"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["35.235.240.0/20"] # Cloud Shell and IAP ranges
  target_tags   = ["analytics"]
  
  depends_on = [google_project_service.required_apis]
}

# Create firewall rules for Dataproc cluster communication
resource "google_compute_firewall" "dataproc_internal" {
  count = var.network_name != "" ? 1 : 0
  
  name    = "${var.resource_prefix}-dataproc-internal-${local.resource_suffix}"
  network = var.network_name
  project = var.project_id
  
  description = "Allow internal communication for Dataproc cluster"
  
  allow {
    protocol = "tcp"
  }
  
  allow {
    protocol = "udp"
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_tags = ["analytics", "dataproc"]
  target_tags = ["analytics", "dataproc"]
  
  depends_on = [google_project_service.required_apis]
}