# Centralized Data Lake Governance with Dataproc Metastore and BigQuery
# This configuration creates a comprehensive data governance solution using:
# - BigLake Metastore for unified metadata management
# - Cloud Storage for data lake storage
# - BigQuery for analytics and governance
# - Dataproc for Spark/Hive processing
# - Data Catalog for metadata discovery

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with environment and random suffix
  suffix              = random_id.suffix.hex
  storage_bucket_name = var.storage_bucket_name != "" ? "${var.storage_bucket_name}-${local.suffix}" : "${var.resource_prefix}-data-lake-${var.environment}-${local.suffix}"
  metastore_name      = var.metastore_name != "" ? var.metastore_name : "${var.resource_prefix}-metastore-${var.environment}-${local.suffix}"
  bigquery_dataset_id = var.bigquery_dataset_id != "" ? var.bigquery_dataset_id : "${var.resource_prefix}_dataset_${var.environment}_${local.suffix}"
  dataproc_cluster_name = var.dataproc_cluster_name != "" ? var.dataproc_cluster_name : "${var.resource_prefix}-cluster-${var.environment}-${local.suffix}"

  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    suffix      = local.suffix
    created-by  = "terraform"
    recipe-name = "centralized-data-lake-governance"
    timestamp   = formatdate("YYYY-MM-DD", timestamp())
  })

  # Sample data configuration
  sample_data_files = [
    "transactions.csv",
    "customers.csv", 
    "products.csv"
  ]
}

# Enable required APIs for the data governance solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "dataproc.googleapis.com", 
    "storage.googleapis.com",
    "metastore.googleapis.com",
    "compute.googleapis.com",
    "datacatalog.googleapis.com",
    "cloudkms.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent automatic disabling of APIs
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create KMS key for encryption (if encryption is enabled and no key provided)
resource "google_kms_key_ring" "governance_keyring" {
  count = var.enable_encryption && var.kms_key_name == "" ? 1 : 0

  name     = "${var.resource_prefix}-governance-keyring-${local.suffix}"
  location = var.region
  project  = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_kms_crypto_key" "governance_key" {
  count = var.enable_encryption && var.kms_key_name == "" ? 1 : 0

  name            = "${var.resource_prefix}-governance-key-${local.suffix}"
  key_ring        = google_kms_key_ring.governance_keyring[0].id
  rotation_period = "7776000s" # 90 days

  purpose = "ENCRYPT_DECRYPT"

  labels = local.common_labels

  lifecycle {
    prevent_destroy = false
  }
}

# Data source for existing KMS key (if provided)
data "google_kms_crypto_key" "existing_key" {
  count = var.enable_encryption && var.kms_key_name != "" ? 1 : 0

  name     = var.kms_key_name
  key_ring = var.kms_key_name
}

# Local value for KMS key
locals {
  kms_key_name = var.enable_encryption ? (
    var.kms_key_name != "" ? data.google_kms_crypto_key.existing_key[0].id : google_kms_crypto_key.governance_key[0].id
  ) : null
}

# Cloud Storage bucket for data lake foundation
resource "google_storage_bucket" "data_lake" {
  name     = local.storage_bucket_name
  location = var.bucket_location
  project  = var.project_id

  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  # Versioning for data governance
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

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # Enable logging for governance
  dynamic "logging" {
    for_each = var.enable_logging ? [1] : []
    content {
      log_bucket = google_storage_bucket.logs_bucket[0].name
    }
  }

  # Encryption configuration
  dynamic "encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      default_kms_key_name = local.kms_key_name
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Logging bucket (if logging is enabled)
resource "google_storage_bucket" "logs_bucket" {
  count = var.enable_logging ? 1 : 0

  name     = "${local.storage_bucket_name}-logs"
  location = var.bucket_location
  project  = var.project_id

  storage_class               = "COLDLINE"
  uniform_bucket_level_access = true
  force_destroy              = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create directory structure in the data lake
resource "google_storage_bucket_object" "data_lake_structure" {
  for_each = toset([
    "raw-data/",
    "processed-data/",
    "warehouse/",
    "staging/",
    "metadata/"
  ])

  name   = each.value
  bucket = google_storage_bucket.data_lake.name
  content = " " # Placeholder content to create directory

  depends_on = [google_storage_bucket.data_lake]
}

# Sample data objects (if loading sample data is enabled)
resource "google_storage_bucket_object" "sample_data" {
  for_each = var.load_sample_data ? toset(local.sample_data_files) : toset([])

  name   = "raw-data/retail/${each.value}"
  bucket = google_storage_bucket.data_lake.name
  source = "data://${each.value}" # This would be replaced with actual data in real deployment

  # Generate sample CSV content for demonstration
  content = each.value == "transactions.csv" ? <<-EOF
customer_id,product_id,quantity,price,transaction_date
CUST001,PROD001,2,29.99,2025-01-01
CUST002,PROD002,1,49.99,2025-01-02
CUST003,PROD001,3,29.99,2025-01-03
CUST001,PROD003,1,19.99,2025-01-04
CUST004,PROD002,2,49.99,2025-01-05
EOF : (each.value == "customers.csv" ? <<-EOF
customer_id,name,email,region
CUST001,John Doe,john@example.com,US-WEST
CUST002,Jane Smith,jane@example.com,US-EAST
CUST003,Bob Wilson,bob@example.com,EU-WEST
CUST004,Alice Brown,alice@example.com,ASIA
EOF : <<-EOF
product_id,name,category,price
PROD001,Widget A,Electronics,29.99
PROD002,Widget B,Electronics,49.99
PROD003,Widget C,Home,19.99
EOF
  )

  depends_on = [google_storage_bucket_object.data_lake_structure]
}

# BigLake Metastore for unified metadata management
resource "google_dataproc_metastore_service" "governance_metastore" {
  service_id = local.metastore_name
  location   = var.region
  project    = var.project_id

  tier            = var.metastore_tier
  database_type   = var.metastore_database_type
  port            = 9083

  hive_metastore_config {
    version = var.hive_metastore_version

    # Configuration overrides for governance
    config_overrides = {
      "javax.jdo.option.ConnectionURL" = "jdbc:mysql://google/${local.metastore_name}?createDatabaseIfNotExist=true&useSSL=true&requireSSL=true"
      "hive.metastore.warehouse.dir"  = "gs://${google_storage_bucket.data_lake.name}/warehouse/"
      "hive.metastore.uris"           = "thrift://localhost:9083"
    }

    # Auxiliary versions for enhanced compatibility
    auxiliary_versions {
      version = "3.1.2"
      config_overrides = {
        "hive.metastore.client.socket.timeout" = "60"
      }
    }
  }

  # Maintenance window for updates
  maintenance_window {
    hour_of_day    = 3
    day_of_week    = "SUNDAY"
  }

  # Network configuration
  network_config {
    consumers {
      network = "projects/${var.project_id}/global/networks/${var.network}"
    }
  }

  # Encryption configuration
  dynamic "encryption_config" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key = local.kms_key_name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.data_lake
  ]

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# Wait for metastore to be fully ready
resource "time_sleep" "wait_for_metastore" {
  depends_on = [google_dataproc_metastore_service.governance_metastore]

  create_duration = "300s" # 5 minutes
}

# BigQuery dataset for analytics and governance
resource "google_bigquery_dataset" "governance_dataset" {
  dataset_id    = local.bigquery_dataset_id
  project       = var.project_id
  location      = var.bigquery_location
  description   = var.dataset_description

  # Table expiration (if specified)
  default_table_expiration_ms = var.table_expiration_ms

  # Enable delete protection for production
  delete_contents_on_destroy = var.environment != "prod"

  # Access configuration
  access {
    role          = "OWNER"
    user_by_email = "terraform@${var.project_id}.iam.gserviceaccount.com"
  }

  access {
    role   = "READER"
    domain = "google.com"
  }

  # Default encryption configuration
  dynamic "default_encryption_configuration" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_name = local.kms_key_name
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# External table in BigQuery pointing to Cloud Storage data
resource "google_bigquery_table" "retail_data_external" {
  dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
  table_id   = "retail_data"
  project    = var.project_id

  description = "External table for retail transaction data in data lake"

  external_data_configuration {
    autodetect    = false
    source_format = "CSV"
    source_uris   = ["gs://${google_storage_bucket.data_lake.name}/raw-data/retail/*.csv"]

    # Schema definition
    schema = jsonencode([
      {
        name = "customer_id"
        type = "STRING"
        mode = "REQUIRED"
        description = "Unique customer identifier"
      },
      {
        name = "product_id"
        type = "STRING"
        mode = "REQUIRED"
        description = "Unique product identifier"
      },
      {
        name = "quantity"
        type = "INTEGER"
        mode = "REQUIRED"
        description = "Quantity purchased"
      },
      {
        name = "price"
        type = "FLOAT"
        mode = "REQUIRED"
        description = "Unit price"
      },
      {
        name = "transaction_date"
        type = "DATE"
        mode = "REQUIRED"
        description = "Date of transaction"
      }
    ])

    csv_options {
      skip_leading_rows = 1
      quote             = "\""
      allow_quoted_newlines = false
      allow_jagged_rows     = false
    }
  }

  labels = local.common_labels

  depends_on = [
    google_bigquery_dataset.governance_dataset,
    google_storage_bucket_object.sample_data
  ]
}

# Governance views for controlled data access
resource "google_bigquery_table" "customer_summary_view" {
  dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
  table_id   = "customer_summary"
  project    = var.project_id

  description = "Governance view providing customer analytics summary"

  view {
    query = <<-EOF
    SELECT 
      customer_id,
      COUNT(*) as transaction_count,
      SUM(quantity * price) as total_value,
      MAX(transaction_date) as last_transaction,
      AVG(quantity * price) as avg_transaction_value
    FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.retail_data`
    GROUP BY customer_id
    EOF

    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.retail_data_external]
}

# Materialized view for performance optimization
resource "google_bigquery_table" "daily_sales_materialized" {
  dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
  table_id   = "daily_sales"
  project    = var.project_id

  description = "Materialized view for daily sales analytics with automatic refresh"

  materialized_view {
    query = <<-EOF
    SELECT 
      transaction_date,
      SUM(quantity * price) as daily_revenue,
      COUNT(DISTINCT customer_id) as unique_customers,
      COUNT(*) as transaction_count,
      AVG(quantity * price) as avg_transaction_value
    FROM `${var.project_id}.${google_bigquery_dataset.governance_dataset.dataset_id}.retail_data`
    GROUP BY transaction_date
    EOF

    enable_refresh = true
    refresh_interval_ms = 3600000 # 1 hour
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.retail_data_external]
}

# Service account for Dataproc cluster
resource "google_service_account" "dataproc_sa" {
  account_id   = "${var.resource_prefix}-dataproc-sa-${local.suffix}"
  display_name = "Dataproc Service Account for Data Governance"
  description  = "Service account for Dataproc cluster with metastore access"
  project      = var.project_id
}

# IAM bindings for Dataproc service account
resource "google_project_iam_member" "dataproc_sa_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
    "roles/dataproc.worker",
    "roles/metastore.user",
    "roles/metastore.metadataEditor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataproc_sa.email}"
}

# Dataproc cluster with metastore integration
resource "google_dataproc_cluster" "analytics_cluster" {
  name    = local.dataproc_cluster_name
  region  = var.region
  project = var.project_id

  cluster_config {
    # Master node configuration
    master_config {
      num_instances    = 1
      machine_type     = var.master_machine_type
      min_cpu_platform = "Intel Skylake"
      
      disk_config {
        boot_disk_type    = var.disk_type
        boot_disk_size_gb = var.disk_size_gb
        num_local_ssds    = 0
      }

      is_preemptible = var.enable_preemptible_masters
    }

    # Worker node configuration
    worker_config {
      num_instances    = var.num_workers
      machine_type     = var.worker_machine_type
      min_cpu_platform = "Intel Skylake"

      disk_config {
        boot_disk_type    = var.disk_type
        boot_disk_size_gb = var.disk_size_gb
        num_local_ssds    = 0
      }

      is_preemptible = false
    }

    # Preemptible worker configuration
    preemptible_worker_config {
      num_instances = var.preemptible_workers
      
      disk_config {
        boot_disk_type    = var.disk_type
        boot_disk_size_gb = var.disk_size_gb
        num_local_ssds    = 0
      }
    }

    # Software configuration
    software_config {
      image_version = var.dataproc_image_version
      
      override_properties = {
        "dataproc:dataproc.conscrypt.provider.enable" = "false"
        "spark:spark.sql.adaptive.enabled"            = "true"
        "spark:spark.sql.adaptive.coalescePartitions.enabled" = "true"
        "spark:spark.sql.catalogImplementation"       = "hive"
        "spark:spark.sql.warehouse.dir"               = "gs://${google_storage_bucket.data_lake.name}/warehouse/"
        "hive:javax.jdo.option.ConnectionURL"         = "jdbc:mysql://google/${local.metastore_name}?createDatabaseIfNotExist=true"
      }

      optional_components = [
        "ZEPPELIN",
        "JUPYTER"
      ]
    }

    # Metastore configuration
    metastore_config {
      dataproc_metastore_service = google_dataproc_metastore_service.governance_metastore.id
    }

    # Autoscaling configuration
    dynamic "autoscaling_config" {
      for_each = var.enable_autoscaling ? [1] : []
      content {
        policy_uri = google_dataproc_autoscaling_policy.cluster_autoscaling[0].name
      }
    }

    # Network and security configuration
    gce_cluster_config {
      zone = var.zone
      
      # Network configuration
      network    = "projects/${var.project_id}/global/networks/${var.network}"
      subnetwork = var.subnetwork != "" ? "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.subnetwork}" : ""

      # Security configuration
      service_account = google_service_account.dataproc_sa.email
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]

      internal_ip_only = var.enable_private_cluster

      # Metadata for governance and monitoring
      metadata = {
        "enable-cloud-sql-hive-metastore" = "false"
        "enable-ip-alias"                 = "true"
        "dataproc-metastore"             = google_dataproc_metastore_service.governance_metastore.name
      }

      tags = ["dataproc", "analytics", "governance"]
    }

    # Initialization scripts for additional setup
    initialization_action {
      script      = "gs://goog-dataproc-initialization-actions-${var.region}/cloud-sql-proxy/cloud-sql-proxy.sh"
      timeout_sec = 300
    }

    # Encryption configuration
    dynamic "encryption_config" {
      for_each = var.enable_encryption ? [1] : []
      content {
        gce_pd_kms_key_name = local.kms_key_name
      }
    }

    # Endpoint configuration
    endpoint_config {
      enable_http_port_access = !var.enable_private_endpoint
    }

    # Lifecycle configuration
    dynamic "lifecycle_config" {
      for_each = var.auto_delete_cluster > 0 ? [1] : []
      content {
        auto_delete_time = timeadd(timestamp(), "${var.auto_delete_cluster}s")
      }
    }
  }

  labels = local.common_labels

  depends_on = [
    google_dataproc_metastore_service.governance_metastore,
    google_service_account.dataproc_sa,
    google_project_iam_member.dataproc_sa_roles,
    time_sleep.wait_for_metastore
  ]

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Autoscaling policy for Dataproc cluster
resource "google_dataproc_autoscaling_policy" "cluster_autoscaling" {
  count = var.enable_autoscaling ? 1 : 0

  policy_id = "${var.resource_prefix}-autoscaling-policy-${local.suffix}"
  location  = var.region
  project   = var.project_id

  worker_config {
    max_instances = var.max_workers
    min_instances = var.min_workers
    weight        = 1
  }

  secondary_worker_config {
    max_instances = var.max_workers
    min_instances = 0
    weight        = 1
  }

  basic_algorithm {
    cooldown_period = "2m"
    yarn_config {
      graceful_decommission_timeout = "1h"
      scale_up_factor               = 0.05
      scale_down_factor             = 1.0
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Data Catalog entry group for governance metadata
resource "google_data_catalog_entry_group" "governance_catalog" {
  count = var.enable_data_catalog ? 1 : 0

  entry_group_id = "${var.resource_prefix}-governance-catalog-${local.suffix}"
  region         = var.region
  project        = var.project_id

  display_name = "Data Governance Catalog"
  description  = "Centralized catalog for data lake governance and metadata discovery"

  depends_on = [google_project_service.required_apis]
}

# Data Catalog entries for key datasets
resource "google_data_catalog_entry" "customer_analytics_entry" {
  count = var.enable_data_catalog ? 1 : 0

  entry_group = google_data_catalog_entry_group.governance_catalog[0].id
  entry_id    = "customer-analytics-dataset"

  display_name = "Customer Analytics Dataset"
  description  = "Governed customer analytics with lineage tracking and automated quality monitoring"

  gcs_fileset_spec {
    file_patterns = ["gs://${google_storage_bucket.data_lake.name}/raw-data/retail/*.csv"]
  }

  schema = jsonencode({
    columns = [
      {
        column     = "customer_id"
        type       = "STRING"
        description = "Unique customer identifier"
      },
      {
        column     = "product_id"  
        type       = "STRING"
        description = "Unique product identifier"
      },
      {
        column     = "quantity"
        type       = "INTEGER"
        description = "Quantity purchased"
      },
      {
        column     = "price"
        type       = "FLOAT"
        description = "Unit price"
      },
      {
        column     = "transaction_date"
        type       = "DATE"
        description = "Date of transaction"
      }
    ]
  })

  depends_on = [
    google_data_catalog_entry_group.governance_catalog,
    google_storage_bucket_object.sample_data
  ]
}

# Cloud Monitoring dashboard for governance metrics (if monitoring enabled)
resource "google_monitoring_dashboard" "governance_dashboard" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Data Lake Governance Dashboard"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "BigQuery Query Performance"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"bigquery_project\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Dataproc Cluster Health"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"dataproc_cluster\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Storage Usage and Costs"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
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

  depends_on = [google_project_service.required_apis]
}

# Cloud Logging sink for governance audit trail
resource "google_logging_project_sink" "governance_audit_sink" {
  count = var.enable_logging ? 1 : 0

  name                   = "${var.resource_prefix}-governance-audit-${local.suffix}"
  destination            = "storage.googleapis.com/${google_storage_bucket.logs_bucket[0].name}"
  unique_writer_identity = true

  # Capture governance-related log entries
  filter = <<-EOF
    (resource.type="bigquery_resource" OR 
     resource.type="dataproc_cluster" OR 
     resource.type="gcs_bucket") AND
    (protoPayload.methodName="jobservice.jobcompleted" OR
     protoPayload.methodName="storage.objects.create" OR
     protoPayload.methodName="bigquery.jobs.insert")
  EOF

  depends_on = [
    google_storage_bucket.logs_bucket,
    google_project_service.required_apis
  ]
}

# IAM binding for the logging sink
resource "google_storage_bucket_iam_member" "logs_bucket_writer" {
  count = var.enable_logging ? 1 : 0

  bucket = google_storage_bucket.logs_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.governance_audit_sink[0].writer_identity

  depends_on = [google_logging_project_sink.governance_audit_sink]
}