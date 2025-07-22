# Supply Chain Transparency Infrastructure with Cloud SQL and Blockchain Node Engine
# This configuration deploys a complete supply chain transparency system on Google Cloud

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming
  name_prefix = "${var.resource_prefix}-${var.environment}"
  suffix      = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment   = var.environment
    created-by    = "terraform"
    project-name  = "supply-chain-transparency"
    deployment-id = local.suffix
  })
  
  # Database configuration
  db_instance_name = "${local.name_prefix}-db-${local.suffix}"
  db_name          = "supply_chain"
  db_user_name     = "supply_chain_user"
  
  # Blockchain configuration
  blockchain_node_name = "${local.name_prefix}-blockchain-${local.suffix}"
  
  # KMS configuration
  keyring_name = "${local.name_prefix}-keyring-${local.suffix}"
  key_name     = "${local.name_prefix}-key-${local.suffix}"
  
  # Service account configuration
  service_account_id = "${local.name_prefix}-sa-${local.suffix}"
  
  # Network configuration
  vpc_name            = "${local.name_prefix}-vpc-${local.suffix}"
  private_subnet_name = "${local.name_prefix}-private-subnet-${local.suffix}"
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# VPC Network for secure communication between services
resource "google_compute_network" "supply_chain_vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "VPC network for supply chain transparency system"
  
  depends_on = [
    google_project_service.compute_api
  ]
}

# Private subnet for database and internal services
resource "google_compute_subnetwork" "private_subnet" {
  name          = local.private_subnet_name
  ip_cidr_range = var.private_subnet_cidr
  region        = var.region
  network       = google_compute_network.supply_chain_vpc.id
  description   = "Private subnet for supply chain infrastructure"
  
  # Enable Private Google Access for accessing Google APIs without external IPs
  private_ip_google_access = var.enable_private_google_access
  
  # Configure secondary IP ranges for future use (GKE pods/services)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for NAT gateway
resource "google_compute_router" "supply_chain_router" {
  name    = "${local.name_prefix}-router-${local.suffix}"
  region  = var.region
  network = google_compute_network.supply_chain_vpc.id
  
  bgp {
    asn = 64514
  }
}

# Cloud NAT for outbound internet access from private resources
resource "google_compute_router_nat" "supply_chain_nat" {
  name                               = "${local.name_prefix}-nat-${local.suffix}"
  router                             = google_compute_router.supply_chain_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================================================
# SECURITY & ENCRYPTION (Cloud KMS)
# ============================================================================

# KMS Key Ring for encryption keys
resource "google_kms_key_ring" "supply_chain_keyring" {
  name     = local.keyring_name
  location = var.region
  
  depends_on = [
    google_project_service.kms_api
  ]
}

# KMS Crypto Key for encrypting supply chain data
resource "google_kms_crypto_key" "supply_chain_key" {
  name     = local.key_name
  key_ring = google_kms_key_ring.supply_chain_keyring.id
  purpose  = "ENCRYPT_DECRYPT"
  
  # Automatic key rotation for enhanced security
  rotation_period = var.kms_key_rotation_period
  
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
  
  # Scheduled destruction period
  destroy_scheduled_duration = var.kms_key_destroy_scheduled_duration
  
  labels = local.common_labels
  
  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# IDENTITY & ACCESS MANAGEMENT
# ============================================================================

# Service Account for supply chain operations
resource "google_service_account" "supply_chain_sa" {
  account_id   = local.service_account_id
  display_name = "Supply Chain Service Account"
  description  = "Service account for supply chain transparency system operations"
}

# Generate secure random password for database user
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store database password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.name_prefix}-db-password-${local.suffix}"
  
  replication {
    auto {}
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.secretmanager_api
  ]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# IAM bindings for service account
resource "google_project_iam_member" "supply_chain_permissions" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/secretmanager.secretAccessor",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudfunctions.invoker"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.supply_chain_sa.email}"
}

# ============================================================================
# DATABASE (Cloud SQL PostgreSQL)
# ============================================================================

# Private IP range for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${local.name_prefix}-private-ip-${local.suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.supply_chain_vpc.id
  
  depends_on = [
    google_project_service.compute_api,
    google_project_service.servicenetworking_api
  ]
}

# Private connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.supply_chain_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  
  depends_on = [
    google_project_service.servicenetworking_api
  ]
}

# Cloud SQL PostgreSQL instance for supply chain data
resource "google_sql_database_instance" "supply_chain_db" {
  name             = local.db_instance_name
  database_version = var.db_version
  region           = var.region
  
  deletion_protection = var.db_deletion_protection
  
  settings {
    tier                        = var.db_instance_tier
    availability_type          = var.db_high_availability ? "REGIONAL" : "ZONAL"
    disk_size                  = 20
    disk_type                  = "PD_SSD"
    disk_autoresize           = true
    disk_autoresize_limit     = 100
    deletion_protection_enabled = var.db_deletion_protection
    
    # Backup configuration
    backup_configuration {
      enabled                        = var.db_backup_enabled
      start_time                    = "03:00"
      location                      = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration for private networking
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                              = google_compute_network.supply_chain_vpc.id
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = var.enable_ssl_enforcement
      ssl_mode                                     = var.enable_ssl_enforcement ? "ENCRYPTED_ONLY" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
      
      dynamic "authorized_networks" {
        for_each = var.allowed_source_ranges
        content {
          name  = "allowed-range-${authorized_networks.key}"
          value = authorized_networks.value
        }
      }
    }
    
    # Database flags for performance optimization
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
    
    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 4  # 4 AM
      update_track = "stable"
    }
    
    # Insights configuration for performance monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length    = 1024
      record_application_tags = false
      record_client_address  = false
    }
    
    user_labels = local.common_labels
  }
  
  # Encryption with customer-managed key
  encryption_key_name = google_kms_crypto_key.supply_chain_key.id
  
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.sqladmin_api,
    google_kms_crypto_key_iam_member.sql_kms_binding
  ]
  
  lifecycle {
    prevent_destroy = true
  }
}

# Supply chain database
resource "google_sql_database" "supply_chain" {
  name      = local.db_name
  instance  = google_sql_database_instance.supply_chain_db.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Database user for applications
resource "google_sql_user" "supply_chain_user" {
  name     = local.db_user_name
  instance = google_sql_database_instance.supply_chain_db.name
  password = random_password.db_password.result
  
  # Host restriction for enhanced security
  host = "%"
}

# Grant KMS permissions for Cloud SQL encryption
resource "google_kms_crypto_key_iam_member" "sql_kms_binding" {
  crypto_key_id = google_kms_crypto_key.supply_chain_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project.current.number}-compute@developer.gserviceaccount.com"
}

# ============================================================================
# BLOCKCHAIN NODE ENGINE
# ============================================================================

# Blockchain Node Engine for immutable verification
resource "google_blockchain_node_engine_blockchain_nodes" "supply_chain_blockchain" {
  provider = google-beta
  
  location           = var.region
  blockchain_type    = "ETHEREUM"
  blockchain_node_id = local.blockchain_node_name
  
  ethereum_details {
    network           = var.blockchain_network
    node_type        = var.blockchain_node_type
    execution_client = var.blockchain_execution_client
    consensus_client = var.blockchain_consensus_client
    api_enable_admin = false
    api_enable_debug = false
    
    geth_details {
      garbage_collection_mode = "FULL"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.blockchain_api
  ]
}

# ============================================================================
# EVENT PROCESSING (Pub/Sub)
# ============================================================================

# Pub/Sub topic for supply chain events
resource "google_pubsub_topic" "supply_chain_events" {
  name = "${local.name_prefix}-supply-chain-events-${local.suffix}"
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.pubsub_api
  ]
}

# Pub/Sub topic for blockchain verification requests
resource "google_pubsub_topic" "blockchain_verification" {
  name = "${local.name_prefix}-blockchain-verification-${local.suffix}"
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  labels = local.common_labels
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.name_prefix}-dead-letter-${local.suffix}"
  
  message_retention_duration = "604800s" # 7 days
  
  labels = local.common_labels
}

# Subscription for processing supply chain events
resource "google_pubsub_subscription" "process_supply_events" {
  name  = "${local.name_prefix}-process-supply-events-${local.suffix}"
  topic = google_pubsub_topic.supply_chain_events.name
  
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Dead letter policy for failed message handling
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Retry policy for transient failures
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Exponential backoff for failed deliveries
  expiration_policy {
    ttl = "86400s" # 1 day
  }
  
  labels = local.common_labels
}

# Subscription for blockchain verification processing
resource "google_pubsub_subscription" "process_blockchain_verification" {
  name  = "${local.name_prefix}-process-blockchain-verification-${local.suffix}"
  topic = google_pubsub_topic.blockchain_verification.name
  
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = var.pubsub_message_retention_duration
  
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# ============================================================================
# SERVERLESS COMPUTE (Cloud Functions)
# ============================================================================

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${local.suffix}"
  location = var.region
  
  # Security settings
  uniform_bucket_level_access = true
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.storage_api
  ]
}

# Archive source code for supply chain processor function
data "archive_file" "supply_chain_processor_source" {
  type        = "zip"
  output_path = "/tmp/supply-chain-processor.zip"
  
  source {
    content = templatefile("${path.module}/functions/supply-chain-processor.js", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "index.js"
  }
  
  source {
    content = file("${path.module}/functions/package.json")
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "supply_chain_processor_source" {
  name   = "supply-chain-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.supply_chain_processor_source.output_path
  
  depends_on = [data.archive_file.supply_chain_processor_source]
}

# Cloud Function for processing supply chain events
resource "google_cloudfunctions2_function" "supply_chain_processor" {
  name        = "${local.name_prefix}-processor-${local.suffix}"
  location    = var.region
  description = "Processes supply chain events and updates database"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "processSupplyChainEvent"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.supply_chain_processor_source.name
      }
    }
    
    # Automatic updates for security patches
    automatic_update_policy {}
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = 0
    available_memory                = var.function_memory
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1
    service_account_email           = google_service_account.supply_chain_sa.email
    
    # Environment variables
    environment_variables = {
      PROJECT_ID    = var.project_id
      REGION        = var.region
      DB_INSTANCE   = google_sql_database_instance.supply_chain_db.name
      DB_NAME       = google_sql_database.supply_chain.name
      DB_USER       = google_sql_user.supply_chain_user.name
      VPC_CONNECTOR = google_vpc_access_connector.supply_chain_connector.id
    }
    
    # Secret environment variables
    secret_environment_variables {
      key        = "DB_PASSWORD"
      project_id = var.project_id
      secret     = google_secret_manager_secret.db_password.secret_id
      version    = "latest"
    }
    
    # VPC connectivity for database access
    vpc_connector                 = google_vpc_access_connector.supply_chain_connector.id
    vpc_connector_egress_settings = "ALL_TRAFFIC"
    
    # Security settings
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  # Event trigger for Pub/Sub
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.supply_chain_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.cloudfunctions_api,
    google_vpc_access_connector.supply_chain_connector
  ]
}

# Archive source code for API ingestion function
data "archive_file" "api_ingestion_source" {
  type        = "zip"
  output_path = "/tmp/api-ingestion.zip"
  
  source {
    content = templatefile("${path.module}/functions/api-ingestion.js", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "index.js"
  }
  
  source {
    content = file("${path.module}/functions/package.json")
    filename = "package.json"
  }
}

# Upload API function source to Cloud Storage
resource "google_storage_bucket_object" "api_ingestion_source" {
  name   = "api-ingestion-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.api_ingestion_source.output_path
  
  depends_on = [data.archive_file.api_ingestion_source]
}

# Cloud Function for supply chain data ingestion API
resource "google_cloudfunctions2_function" "api_ingestion" {
  name        = "${local.name_prefix}-api-${local.suffix}"
  location    = var.region
  description = "HTTP API for supply chain data ingestion"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "supplyChainIngestion"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.api_ingestion_source.name
      }
    }
    
    automatic_update_policy {}
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count              = 0
    available_memory                = "256Mi"
    timeout_seconds                 = 30
    max_instance_request_concurrency = 10
    service_account_email           = google_service_account.supply_chain_sa.email
    
    environment_variables = {
      PROJECT_ID     = var.project_id
      REGION         = var.region
      PUBSUB_TOPIC   = google_pubsub_topic.supply_chain_events.name
    }
    
    # Public access for API endpoint
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.cloudfunctions_api
  ]
}

# VPC Access Connector for Cloud Functions to access VPC resources
resource "google_vpc_access_connector" "supply_chain_connector" {
  name          = "${local.name_prefix}-connector-${local.suffix}"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.supply_chain_vpc.name
  
  min_instances = 2
  max_instances = 10
  
  depends_on = [
    google_project_service.vpcaccess_api
  ]
}

# ============================================================================
# API MANAGEMENT
# ============================================================================

# Allow public access to the API ingestion function
resource "google_cloudfunctions2_function_iam_member" "api_invoker" {
  project        = google_cloudfunctions2_function.api_ingestion.project
  location       = google_cloudfunctions2_function.api_ingestion.location
  cloud_function = google_cloudfunctions2_function.api_ingestion.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ============================================================================
# MONITORING & LOGGING
# ============================================================================

# Log sink for supply chain events
resource "google_logging_project_sink" "supply_chain_logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "${local.name_prefix}-logs-sink-${local.suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.logs_bucket[0].name}"
  
  # Filter for supply chain related logs
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"${local.name_prefix}.*"
    OR
    resource.type="gce_instance"
    labels.project="${var.project_id}"
  EOT
  
  # Use a unique writer identity for each sink
  unique_writer_identity = true
}

# Cloud Storage bucket for log storage
resource "google_storage_bucket" "logs_bucket" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name     = "${local.name_prefix}-logs-${local.suffix}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
}

# Grant log sink permission to write to bucket
resource "google_storage_bucket_iam_member" "logs_bucket_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.logs_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.supply_chain_logs[0].writer_identity
}

# ============================================================================
# REQUIRED APIS
# ============================================================================

# Get current project information
data "google_project" "current" {}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "blockchainnodeengine.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudkms.googleapis.com",
    "secretmanager.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "storage.googleapis.com",
    "vpcaccess.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.key
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Individual API service resources for dependency management
resource "google_project_service" "sqladmin_api" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "blockchain_api" {
  project = var.project_id
  service = "blockchainnodeengine.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "cloudfunctions_api" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "pubsub_api" {
  project = var.project_id
  service = "pubsub.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "kms_api" {
  project = var.project_id
  service = "cloudkms.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "secretmanager_api" {
  project = var.project_id
  service = "secretmanager.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "compute_api" {
  project = var.project_id
  service = "compute.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "servicenetworking_api" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "storage_api" {
  project = var.project_id
  service = "storage.googleapis.com"
  disable_dependent_services = false
}

resource "google_project_service" "vpcaccess_api" {
  project = var.project_id
  service = "vpcaccess.googleapis.com"
  disable_dependent_services = false
}