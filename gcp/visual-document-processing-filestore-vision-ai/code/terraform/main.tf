# Visual Document Processing with Cloud Filestore and Vision AI
# This Terraform configuration deploys a complete event-driven document processing solution
# using Google Cloud Filestore, Cloud Vision AI, Cloud Pub/Sub, and Cloud Functions

# ============================================================================
# LOCAL VALUES AND DATA SOURCES
# ============================================================================

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

# Current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get the default compute service account
data "google_compute_default_service_account" "default" {
  project = var.project_id
}

# Get the storage service account for Pub/Sub notifications
data "google_storage_project_service_account" "gcs_account" {
  project = var.project_id
}

locals {
  # Common naming convention
  suffix = random_id.suffix.hex
  
  # Resource names with consistent naming pattern
  filestore_instance_name    = "${var.resource_prefix}-filestore-${local.suffix}"
  monitor_function_name      = "${var.resource_prefix}-monitor-${local.suffix}"
  processor_function_name    = "${var.resource_prefix}-processor-${local.suffix}"
  document_topic_name        = "${var.resource_prefix}-documents-${local.suffix}"
  results_topic_name         = "${var.resource_prefix}-results-${local.suffix}"
  source_bucket_name         = "${var.resource_prefix}-source-${local.suffix}"
  results_bucket_name        = "${var.resource_prefix}-results-${local.suffix}"
  client_instance_name       = "${var.resource_prefix}-client-${local.suffix}"
  service_account_name       = "${var.resource_prefix}-sa-${local.suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    solution       = "visual-document-processing"
    managed-by     = "terraform"
    recipe-id      = "8a9b4c3d"
    created-date   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "compute.googleapis.com",
    "file.googleapis.com",
    "vision.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "eventarc.googleapis.com"
  ] : []
}

# ============================================================================
# ENABLE GOOGLE CLOUD APIS
# ============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when this resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ============================================================================
# SERVICE ACCOUNT FOR FUNCTIONS
# ============================================================================

# Create dedicated service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_name
  display_name = "Visual Document Processing Service Account"
  description  = "Service account for Cloud Functions in the document processing pipeline"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset(concat([
    "roles/storage.objectAdmin",
    "roles/pubsub.editor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor"
  ], var.service_account_roles))
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# ============================================================================
# CLOUD FILESTORE INSTANCE
# ============================================================================

# Create Cloud Filestore instance for shared document storage
resource "google_filestore_instance" "documents" {
  name     = local.filestore_instance_name
  location = var.zone
  tier     = var.filestore_tier
  project  = var.project_id
  
  # Configure file share
  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = var.filestore_file_share_name
    
    # NFS export options for secure access
    nfs_export_options {
      ip_ranges   = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }
  
  # Network configuration
  networks {
    network      = var.filestore_network
    modes        = ["MODE_IPV4"]
    connect_mode = "DIRECT_PEERING"
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
  
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# ============================================================================
# CLOUD STORAGE BUCKETS
# ============================================================================

# Bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name     = local.source_bucket_name
  location = var.storage_location
  project  = var.project_id
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Storage class configuration
  storage_class = var.storage_class
  
  # Versioning configuration
  versioning {
    enabled = var.enable_storage_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    content {
      condition {
        age = 30
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    content {
      condition {
        age = 90
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Bucket for processed document results
resource "google_storage_bucket" "results" {
  name     = local.results_bucket_name
  location = var.storage_location
  project  = var.project_id
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Storage class configuration
  storage_class = var.storage_class
  
  # Versioning configuration
  versioning {
    enabled = var.enable_storage_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    content {
      condition {
        age = 30
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_storage_lifecycle ? [1] : []
    content {
      condition {
        age = 90
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# ============================================================================
# CLOUD PUB/SUB TOPICS AND SUBSCRIPTIONS
# ============================================================================

# Pub/Sub topic for document processing queue
resource "google_pubsub_topic" "document_processing" {
  name    = local.document_topic_name
  project = var.project_id
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub topic for processing results
resource "google_pubsub_topic" "processing_results" {
  name    = local.results_topic_name
  project = var.project_id
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Subscription for document processing
resource "google_pubsub_subscription" "document_processing" {
  name    = "${local.document_topic_name}-sub"
  topic   = google_pubsub_topic.document_processing.id
  project = var.project_id
  
  # Acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.processing_results.id
    max_delivery_attempts = 5
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.document_processing]
}

# Subscription for processing results
resource "google_pubsub_subscription" "processing_results" {
  name    = "${local.results_topic_name}-sub"
  topic   = google_pubsub_topic.processing_results.id
  project = var.project_id
  
  # Acknowledgment deadline
  ack_deadline_seconds = 300
  
  # Message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Cloud Storage configuration for results archival
  cloud_storage_config {
    bucket = google_storage_bucket.results.name
    
    filename_prefix          = "processed/"
    filename_suffix          = ".json"
    filename_datetime_format = "YYYY-MM-DD/hh_mm_ssZ"
    
    max_bytes    = 1000000  # 1MB
    max_duration = "300s"
    max_messages = 100
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [
    google_pubsub_topic.processing_results,
    google_storage_bucket.results,
    google_storage_bucket_iam_member.pubsub_storage_admin
  ]
}

# IAM binding for Pub/Sub to write to Storage
resource "google_storage_bucket_iam_member" "pubsub_storage_admin" {
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.admin"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  
  depends_on = [google_storage_bucket.results]
}

# ============================================================================
# CLOUD FUNCTIONS SOURCE CODE
# ============================================================================

# Create source code archives for Cloud Functions (only if enabled)
resource "local_file" "monitor_function_code" {
  count = var.create_sample_functions ? 1 : 0
  
  filename = "${path.module}/function_source/monitor/main.py"
  content = templatefile("${path.module}/templates/monitor_function.py.tpl", {
    project_id        = var.project_id
    pubsub_topic      = google_pubsub_topic.document_processing.name
    filestore_ip      = google_filestore_instance.documents.networks[0].ip_addresses[0]
    filestore_share   = var.filestore_file_share_name
  })
  
  depends_on = [google_filestore_instance.documents]
}

resource "local_file" "processor_function_code" {
  count = var.create_sample_functions ? 1 : 0
  
  filename = "${path.module}/function_source/processor/main.py"
  content = templatefile("${path.module}/templates/processor_function.py.tpl", {
    project_id      = var.project_id
    results_topic   = google_pubsub_topic.processing_results.name
    results_bucket  = google_storage_bucket.results.name
  })
}

resource "local_file" "monitor_requirements" {
  count = var.create_sample_functions ? 1 : 0
  
  filename = "${path.module}/function_source/monitor/requirements.txt"
  content = <<EOF
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
functions-framework==3.4.0
EOF
}

resource "local_file" "processor_requirements" {
  count = var.create_sample_functions ? 1 : 0
  
  filename = "${path.module}/function_source/processor/requirements.txt"
  content = <<EOF
google-cloud-vision==3.4.5
google-cloud-pubsub==2.18.4
google-cloud-storage==2.10.0
functions-framework==3.4.0
Pillow==10.0.1
EOF
}

# Create ZIP archives for function deployment
data "archive_file" "monitor_function_zip" {
  count = var.create_sample_functions ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/function_source/monitor-function.zip"
  source_dir  = "${path.module}/function_source/monitor"
  
  depends_on = [
    local_file.monitor_function_code[0],
    local_file.monitor_requirements[0]
  ]
}

data "archive_file" "processor_function_zip" {
  count = var.create_sample_functions ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/function_source/processor-function.zip"
  source_dir  = "${path.module}/function_source/processor"
  
  depends_on = [
    local_file.processor_function_code[0],
    local_file.processor_requirements[0]
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "monitor_function_source" {
  count = var.create_sample_functions ? 1 : 0
  
  name   = "monitor-function-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.monitor_function_zip[0].output_path
  
  depends_on = [data.archive_file.monitor_function_zip[0]]
}

resource "google_storage_bucket_object" "processor_function_source" {
  count = var.create_sample_functions ? 1 : 0
  
  name   = "processor-function-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.processor_function_zip[0].output_path
  
  depends_on = [data.archive_file.processor_function_zip[0]]
}

# ============================================================================
# CLOUD FUNCTIONS (2ND GENERATION)
# ============================================================================

# File Monitor Cloud Function
resource "google_cloudfunctions2_function" "file_monitor" {
  count = var.create_sample_functions ? 1 : 0
  
  name        = local.monitor_function_name
  location    = var.region
  description = "Monitors Filestore for new documents and triggers processing"
  project     = var.project_id
  
  # Build configuration
  build_config {
    runtime     = var.functions_runtime
    entry_point = "monitor_documents"
    
    # Source from Cloud Storage
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.monitor_function_source[0].name
      }
    }
    
    # Environment variables for build
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    
    # Use the dedicated service account for building
    service_account = google_service_account.function_sa.id
  }
  
  # Service configuration
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = var.monitor_function_memory
    timeout_seconds       = var.function_timeout_seconds
    max_instance_request_concurrency = 80
    available_cpu         = "1"
    
    # Environment variables for runtime
    environment_variables = {
      PROJECT_ID        = var.project_id
      PUBSUB_TOPIC      = google_pubsub_topic.document_processing.name
      FILESTORE_IP      = google_filestore_instance.documents.networks[0].ip_addresses[0]
      FILESTORE_SHARE   = var.filestore_file_share_name
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }
  
  # Event trigger for scheduled execution
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.document_processing.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.function_sa,
    google_storage_bucket_object.monitor_function_source[0],
    google_project_iam_member.function_sa_roles
  ]
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Vision AI Processor Cloud Function
resource "google_cloudfunctions2_function" "vision_processor" {
  count = var.create_sample_functions ? 1 : 0
  
  name        = local.processor_function_name
  location    = var.region
  description = "Processes documents with Vision AI and publishes results"
  project     = var.project_id
  
  # Build configuration
  build_config {
    runtime     = var.functions_runtime
    entry_point = "process_document"
    
    # Source from Cloud Storage
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.processor_function_source[0].name
      }
    }
    
    # Environment variables for build
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    
    # Use the dedicated service account for building
    service_account = google_service_account.function_sa.id
  }
  
  # Service configuration
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = var.processor_function_memory
    timeout_seconds       = var.function_timeout_seconds
    max_instance_request_concurrency = 80
    available_cpu         = "2"
    
    # Environment variables for runtime
    environment_variables = {
      PROJECT_ID      = var.project_id
      RESULTS_TOPIC   = google_pubsub_topic.processing_results.name
      RESULTS_BUCKET  = google_storage_bucket.results.name
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }
  
  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.document_processing.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.function_sa,
    google_storage_bucket_object.processor_function_source[0],
    google_project_iam_member.function_sa_roles
  ]
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# ============================================================================
# COMPUTE ENGINE CLIENT INSTANCE
# ============================================================================

# Compute Engine instance for Filestore access demonstration
resource "google_compute_instance" "filestore_client" {
  count = var.create_client_instance ? 1 : 0
  
  name         = local.client_instance_name
  machine_type = var.client_machine_type
  zone         = var.zone
  project      = var.project_id
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "${var.client_image_project}/${var.client_image_family}"
      size  = var.client_boot_disk_size_gb
      type  = "pd-standard"
    }
    auto_delete = var.auto_delete_resources
  }
  
  # Network configuration
  network_interface {
    network = var.filestore_network
    
    # Assign external IP for management access
    access_config {
      // Ephemeral IP
    }
  }
  
  # Service account configuration
  service_account {
    email = data.google_compute_default_service_account.default.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  # Startup script to mount Filestore and configure directories
  metadata_startup_script = templatefile("${path.module}/templates/client_startup.sh.tpl", {
    filestore_ip    = google_filestore_instance.documents.networks[0].ip_addresses[0]
    filestore_share = var.filestore_file_share_name
  })
  
  # Scheduling configuration
  scheduling {
    automatic_restart   = !var.enable_preemptible_instances
    on_host_maintenance = var.enable_preemptible_instances ? "TERMINATE" : "MIGRATE"
    preemptible         = var.enable_preemptible_instances
  }
  
  # Security configuration
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
  
  # Apply labels
  labels = local.common_labels
  
  # Apply tags for firewall rules
  tags = ["filestore-client", "document-processing"]
  
  # Deletion protection
  deletion_protection = var.deletion_protection
  
  depends_on = [
    google_project_service.apis,
    google_filestore_instance.documents
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# ============================================================================
# FIREWALL RULES FOR CLIENT ACCESS
# ============================================================================

# Allow SSH access to client instance
resource "google_compute_firewall" "allow_ssh" {
  count = var.create_client_instance ? 1 : 0
  
  name    = "${var.resource_prefix}-allow-ssh-${local.suffix}"
  network = var.filestore_network
  project = var.project_id
  
  description = "Allow SSH access to document processing client instances"
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["filestore-client"]
  
  depends_on = [google_project_service.apis]
}

# Allow internal communication
resource "google_compute_firewall" "allow_internal" {
  count = var.create_client_instance ? 1 : 0
  
  name    = "${var.resource_prefix}-allow-internal-${local.suffix}"
  network = var.filestore_network
  project = var.project_id
  
  description = "Allow internal communication for document processing"
  
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
  
  source_ranges = ["10.0.0.0/8"]
  target_tags   = ["document-processing"]
  
  depends_on = [google_project_service.apis]
}

# ============================================================================
# MONITORING AND LOGGING CONFIGURATION
# ============================================================================

# Log sink for function errors
resource "google_logging_project_sink" "function_errors" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "${var.resource_prefix}-function-errors-${local.suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.results.name}"
  
  # Filter for function errors
  filter = <<EOF
resource.type="cloud_function"
severity>=ERROR
resource.labels.function_name:("${local.monitor_function_name}" OR "${local.processor_function_name}")
EOF

  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [
    google_storage_bucket.results,
    google_cloudfunctions2_function.file_monitor,
    google_cloudfunctions2_function.vision_processor
  ]
}

# Grant logging sink permission to write to bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.results.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_errors[0].writer_identity
  
  depends_on = [google_logging_project_sink.function_errors]
}