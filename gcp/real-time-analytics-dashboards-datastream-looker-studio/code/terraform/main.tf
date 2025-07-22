# Real-Time Analytics Dashboards with Datastream and Looker Studio
# This Terraform configuration deploys a complete real-time analytics solution
# using Google Cloud Datastream for change data capture, BigQuery for analytics,
# and Looker Studio for dashboards

# Configure the Google Cloud provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  required_version = ">= 1.0"
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  suffix                      = random_id.suffix.hex
  dataset_name               = var.dataset_name
  stream_name                = "${var.stream_name}-${local.suffix}"
  source_connection_name     = "${var.source_connection_name}-${local.suffix}"
  bigquery_connection_name   = "${var.bigquery_connection_name}-${local.suffix}"
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    purpose     = "real-time-analytics"
    managed-by  = "terraform"
    project     = var.project_id
  }
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "datastream_api" {
  project = var.project_id
  service = "datastream.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "bigquery_api" {
  project = var.project_id
  service = "bigquery.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "sql_api" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# BigQuery dataset for analytics data
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id                 = local.dataset_name
  project                    = var.project_id
  friendly_name              = "Real-time E-commerce Analytics Dataset"
  description                = "Dataset for real-time analytics data replicated from operational databases via Datastream"
  location                   = var.region
  default_table_expiration_ms = var.table_expiration_ms
  
  # Enable deletion of non-empty dataset during terraform destroy
  delete_contents_on_destroy = var.enable_dataset_deletion
  
  labels = local.common_labels
  
  # Access control for BigQuery dataset
  dynamic "access" {
    for_each = var.dataset_access_roles
    content {
      role          = access.value.role
      user_by_email = access.value.user_email
    }
  }
  
  # Default encryption configuration
  default_encryption_configuration {
    kms_key_name = var.kms_key_name
  }
  
  depends_on = [google_project_service.bigquery_api]
}

# Datastream connection profile for source database
resource "google_datastream_connection_profile" "source_connection" {
  display_name          = "Source Database Connection"
  location              = var.region
  connection_profile_id = local.source_connection_name
  project               = var.project_id
  
  labels = local.common_labels
  
  # MySQL connection configuration
  dynamic "mysql_profile" {
    for_each = var.source_db_type == "mysql" ? [1] : []
    content {
      hostname = var.source_db_hostname
      port     = var.source_db_port
      username = var.source_db_username
      password = var.source_db_password
      
      ssl_config {
        client_certificate = var.ssl_client_certificate
        client_key         = var.ssl_client_key
        ca_certificate     = var.ssl_ca_certificate
      }
    }
  }
  
  # PostgreSQL connection configuration
  dynamic "postgresql_profile" {
    for_each = var.source_db_type == "postgresql" ? [1] : []
    content {
      hostname = var.source_db_hostname
      port     = var.source_db_port
      username = var.source_db_username
      password = var.source_db_password
      database = var.source_db_name
    }
  }
  
  # Oracle connection configuration
  dynamic "oracle_profile" {
    for_each = var.source_db_type == "oracle" ? [1] : []
    content {
      hostname              = var.source_db_hostname
      port                  = var.source_db_port
      username              = var.source_db_username
      password              = var.source_db_password
      database_service      = var.oracle_database_service
      connection_attributes = var.oracle_connection_attributes
    }
  }
  
  depends_on = [google_project_service.datastream_api]
}

# Datastream connection profile for BigQuery destination
resource "google_datastream_connection_profile" "bigquery_connection" {
  display_name          = "BigQuery Analytics Destination"
  location              = var.region
  connection_profile_id = local.bigquery_connection_name
  project               = var.project_id
  
  labels = local.common_labels
  
  bigquery_profile {}
  
  depends_on = [
    google_project_service.datastream_api,
    google_bigquery_dataset.analytics_dataset
  ]
}

# Datastream for real-time data replication
resource "google_datastream_stream" "analytics_stream" {
  display_name = "Real-time Analytics Stream"
  location     = var.region
  stream_id    = local.stream_name
  project      = var.project_id
  
  labels = local.common_labels
  
  # Source configuration
  source_config {
    source_connection_profile = google_datastream_connection_profile.source_connection.id
    
    # MySQL source configuration
    dynamic "mysql_source_config" {
      for_each = var.source_db_type == "mysql" ? [1] : []
      content {
        max_concurrent_cdc_tasks      = var.max_concurrent_cdc_tasks
        max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks
        
        # Include specific tables for replication
        dynamic "include_objects" {
          for_each = var.include_tables
          content {
            mysql_databases {
              database = include_objects.value.database
              
              dynamic "mysql_tables" {
                for_each = include_objects.value.tables
                content {
                  table = mysql_tables.value.table_name
                  
                  # Include specific columns if specified
                  dynamic "mysql_columns" {
                    for_each = mysql_tables.value.columns != null ? mysql_tables.value.columns : []
                    content {
                      column   = mysql_columns.value.column_name
                      data_type = mysql_columns.value.data_type
                      nullable = mysql_columns.value.nullable
                    }
                  }
                }
              }
            }
          }
        }
        
        # Exclude specific tables if needed
        dynamic "exclude_objects" {
          for_each = var.exclude_tables
          content {
            mysql_databases {
              database = exclude_objects.value.database
              
              dynamic "mysql_tables" {
                for_each = exclude_objects.value.tables
                content {
                  table = mysql_tables.value
                }
              }
            }
          }
        }
      }
    }
    
    # PostgreSQL source configuration
    dynamic "postgresql_source_config" {
      for_each = var.source_db_type == "postgresql" ? [1] : []
      content {
        max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks
        publication                   = var.postgresql_publication
        replication_slot             = var.postgresql_replication_slot
        
        # Include specific tables for replication
        dynamic "include_objects" {
          for_each = var.include_tables
          content {
            postgresql_schemas {
              schema = include_objects.value.schema
              
              dynamic "postgresql_tables" {
                for_each = include_objects.value.tables
                content {
                  table = postgresql_tables.value.table_name
                  
                  # Include specific columns if specified
                  dynamic "postgresql_columns" {
                    for_each = postgresql_tables.value.columns != null ? postgresql_tables.value.columns : []
                    content {
                      column   = postgresql_columns.value.column_name
                      data_type = postgresql_columns.value.data_type
                      nullable = postgresql_columns.value.nullable
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    
    # Oracle source configuration
    dynamic "oracle_source_config" {
      for_each = var.source_db_type == "oracle" ? [1] : []
      content {
        max_concurrent_cdc_tasks      = var.max_concurrent_cdc_tasks
        max_concurrent_backfill_tasks = var.max_concurrent_backfill_tasks
        
        # Include specific tables for replication
        dynamic "include_objects" {
          for_each = var.include_tables
          content {
            oracle_schemas {
              schema = include_objects.value.schema
              
              dynamic "oracle_tables" {
                for_each = include_objects.value.tables
                content {
                  table = oracle_tables.value.table_name
                  
                  # Include specific columns if specified
                  dynamic "oracle_columns" {
                    for_each = oracle_tables.value.columns != null ? oracle_tables.value.columns : []
                    content {
                      column   = oracle_columns.value.column_name
                      data_type = oracle_columns.value.data_type
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  
  # BigQuery destination configuration
  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery_connection.id
    
    bigquery_destination_config {
      data_freshness = var.data_freshness_seconds
      
      # Single target dataset configuration
      single_target_dataset {
        dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
      }
      
      # Source hierarchy datasets (alternative configuration)
      # Uncomment if you want table names to include source database/schema structure
      # source_hierarchy_datasets {
      #   dataset_template {
      #     location    = var.region
      #     dataset_id_prefix = "${local.dataset_name}_"
      #   }
      # }
    }
  }
  
  # Backfill configuration
  backfill_all {
    # Backfill all historical data
  }
  
  depends_on = [
    google_datastream_connection_profile.source_connection,
    google_datastream_connection_profile.bigquery_connection,
    google_bigquery_dataset.analytics_dataset
  ]
}

# BigQuery views for business intelligence
resource "google_bigquery_table" "sales_performance_view" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "sales_performance"
  project    = var.project_id
  
  labels = local.common_labels
  
  view {
    query = templatefile("${path.module}/sql/sales_performance_view.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  depends_on = [google_datastream_stream.analytics_stream]
}

resource "google_bigquery_table" "daily_sales_summary_view" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "daily_sales_summary"
  project    = var.project_id
  
  labels = local.common_labels
  
  view {
    query = templatefile("${path.module}/sql/daily_sales_summary_view.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  depends_on = [google_bigquery_table.sales_performance_view]
}

resource "google_bigquery_table" "customer_analytics_view" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "customer_analytics"
  project    = var.project_id
  
  labels = local.common_labels
  
  view {
    query = templatefile("${path.module}/sql/customer_analytics_view.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  depends_on = [google_datastream_stream.analytics_stream]
}

resource "google_bigquery_table" "product_performance_view" {
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id   = "product_performance"
  project    = var.project_id
  
  labels = local.common_labels
  
  view {
    query = templatefile("${path.module}/sql/product_performance_view.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  depends_on = [google_datastream_stream.analytics_stream]
}

# IAM bindings for Datastream service account
resource "google_project_iam_member" "datastream_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-datastream.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.datastream_api]
}

resource "google_project_iam_member" "datastream_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-datastream.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.datastream_api]
}

# Optional: Create Looker Studio data source configuration
# Note: Looker Studio connections are typically created through the UI
# This creates the necessary permissions for connecting to BigQuery
resource "google_bigquery_dataset_iam_member" "looker_studio_viewer" {
  count      = length(var.looker_studio_users)
  dataset_id = google_bigquery_dataset.analytics_dataset.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "user:${var.looker_studio_users[count.index]}"
  project    = var.project_id
}

resource "google_project_iam_member" "looker_studio_job_user" {
  count   = length(var.looker_studio_users)
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "user:${var.looker_studio_users[count.index]}"
}

# Optional: Enable BI Engine for faster dashboard performance
resource "google_bigquery_bi_reservation" "analytics_bi_engine" {
  count    = var.enable_bi_engine ? 1 : 0
  project  = var.project_id
  location = var.region
  size     = var.bi_engine_size
  
  preferred_tables = [
    "${var.project_id}.${local.dataset_name}.sales_performance",
    "${var.project_id}.${local.dataset_name}.daily_sales_summary",
    "${var.project_id}.${local.dataset_name}.customer_analytics",
    "${var.project_id}.${local.dataset_name}.product_performance"
  ]
  
  depends_on = [
    google_bigquery_table.sales_performance_view,
    google_bigquery_table.daily_sales_summary_view,
    google_bigquery_table.customer_analytics_view,
    google_bigquery_table.product_performance_view
  ]
}

# Create SQL files for views (these would be created separately)
resource "local_file" "sales_performance_sql" {
  filename = "${path.module}/sql/sales_performance_view.sql"
  content = <<-EOT
    SELECT 
        DATE(o.order_date) as order_date,
        o.customer_id,
        c.customer_name,
        o.product_id,
        p.product_name,
        o.quantity,
        o.unit_price,
        o.quantity * o.unit_price as total_amount,
        o._metadata_timestamp as last_updated
    FROM `${project_id}.${dataset_name}.sales_orders` o
    JOIN `${project_id}.${dataset_name}.customers` c 
        ON o.customer_id = c.customer_id
    JOIN `${project_id}.${dataset_name}.products` p 
        ON o.product_id = p.product_id
    WHERE o._metadata_deleted = false
  EOT
}

resource "local_file" "daily_sales_summary_sql" {
  filename = "${path.module}/sql/daily_sales_summary_view.sql"
  content = <<-EOT
    SELECT 
        DATE(order_date) as sales_date,
        COUNT(*) as total_orders,
        SUM(total_amount) as total_revenue,
        AVG(total_amount) as avg_order_value,
        COUNT(DISTINCT customer_id) as unique_customers
    FROM `${project_id}.${dataset_name}.sales_performance`
    GROUP BY DATE(order_date)
    ORDER BY sales_date DESC
  EOT
}

resource "local_file" "customer_analytics_sql" {
  filename = "${path.module}/sql/customer_analytics_view.sql"
  content = <<-EOT
    SELECT 
        c.customer_id,
        c.customer_name,
        c.customer_email,
        c.registration_date,
        COUNT(o.order_id) as total_orders,
        SUM(o.quantity * o.unit_price) as total_spent,
        AVG(o.quantity * o.unit_price) as avg_order_value,
        MAX(o.order_date) as last_order_date,
        DATE_DIFF(CURRENT_DATE(), DATE(MAX(o.order_date)), DAY) as days_since_last_order
    FROM `${project_id}.${dataset_name}.customers` c
    LEFT JOIN `${project_id}.${dataset_name}.sales_orders` o 
        ON c.customer_id = o.customer_id
        AND o._metadata_deleted = false
    WHERE c._metadata_deleted = false
    GROUP BY c.customer_id, c.customer_name, c.customer_email, c.registration_date
  EOT
}

resource "local_file" "product_performance_sql" {
  filename = "${path.module}/sql/product_performance_view.sql"
  content = <<-EOT
    SELECT 
        p.product_id,
        p.product_name,
        p.category,
        p.price as current_price,
        COUNT(o.order_id) as total_orders,
        SUM(o.quantity) as total_quantity_sold,
        SUM(o.quantity * o.unit_price) as total_revenue,
        AVG(o.unit_price) as avg_selling_price,
        MAX(o.order_date) as last_sale_date
    FROM `${project_id}.${dataset_name}.products` p
    LEFT JOIN `${project_id}.${dataset_name}.sales_orders` o 
        ON p.product_id = o.product_id
        AND o._metadata_deleted = false
    WHERE p._metadata_deleted = false
    GROUP BY p.product_id, p.product_name, p.category, p.price
    ORDER BY total_revenue DESC
  EOT
}