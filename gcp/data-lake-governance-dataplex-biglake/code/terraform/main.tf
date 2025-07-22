# Main Terraform configuration for GCP Data Lake Governance with Dataplex and BigLake
# This configuration implements an intelligent data governance system using Google Cloud services

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  bucket_name     = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  connection_name = "${var.connection_name_prefix}-${random_id.suffix.hex}"
  zone           = var.zone != "" ? var.zone : "${var.region}-a"
  
  # Standard labels applied to all resources
  common_labels = merge(var.labels, {
    deployment-id = random_id.suffix.hex
  })
  
  # Required APIs for the data governance solution
  required_apis = [
    "dataplex.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for data lake storage
resource "google_storage_bucket" "data_lake" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
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
  
  # Enable uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = true
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create sample data files for demonstration
resource "google_storage_bucket_object" "customer_data" {
  count  = var.create_sample_data ? 1 : 0
  name   = "raw/customers/customer_data.csv"
  bucket = google_storage_bucket.data_lake.name
  
  content = <<-EOF
customer_id,name,email,phone,registration_date,country
1001,John Smith,john.smith@email.com,555-0123,2024-01-15,USA
1002,Jane Doe,jane.doe@email.com,555-0124,2024-01-16,Canada
1003,Bob Johnson,bob.johnson@email.com,555-0125,2024-01-17,USA
1004,Alice Brown,alice.brown@email.com,555-0126,2024-01-18,UK
1005,Carlos Rodriguez,carlos.rodriguez@email.com,555-0127,2024-01-19,Spain
1006,Marie Dubois,marie.dubois@email.com,555-0128,2024-01-20,France
EOF
}

resource "google_storage_bucket_object" "transaction_data" {
  count  = var.create_sample_data ? 1 : 0
  name   = "raw/transactions/transaction_data.csv"
  bucket = google_storage_bucket.data_lake.name
  
  content = <<-EOF
transaction_id,customer_id,amount,currency,transaction_date,category
TXN001,1001,150.50,USD,2024-02-01,retail
TXN002,1002,89.99,CAD,2024-02-02,online
TXN003,1001,200.00,USD,2024-02-03,retail
TXN004,1003,75.25,USD,2024-02-04,dining
TXN005,1004,45.75,GBP,2024-02-05,online
TXN006,1005,120.00,EUR,2024-02-06,retail
EOF
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "governance_analytics" {
  dataset_id  = var.dataset_name
  project     = var.project_id
  location    = var.region
  description = "Analytics dataset with BigLake governance controls"
  
  # Enable delete protection for production environments
  delete_contents_on_destroy = !var.deletion_protection
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery connection for BigLake tables
resource "google_bigquery_connection" "biglake_connection" {
  provider      = google-beta
  connection_id = local.connection_name
  project       = var.project_id
  location      = var.region
  description   = "BigLake connection for multi-cloud data access"
  
  cloud_resource {}
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to BigLake connection service account
resource "google_storage_bucket_iam_member" "biglake_storage_access" {
  bucket = google_storage_bucket.data_lake.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_bigquery_connection.biglake_connection.cloud_resource[0].service_account_id}"
}

resource "google_project_iam_member" "biglake_dataplex_viewer" {
  project = var.project_id
  role    = "roles/dataplex.viewer"
  member  = "serviceAccount:${google_bigquery_connection.biglake_connection.cloud_resource[0].service_account_id}"
}

resource "google_project_iam_member" "biglake_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_bigquery_connection.biglake_connection.cloud_resource[0].service_account_id}"
}

# Create Dataplex lake for data governance
resource "google_dataplex_lake" "enterprise_lake" {
  provider     = google-beta
  name         = var.lake_name
  location     = var.region
  project      = var.project_id
  display_name = "Enterprise Data Lake"
  description  = "Centralized governance for enterprise data assets"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Dataplex zone for raw data with discovery enabled
resource "google_dataplex_zone" "raw_data_zone" {
  provider     = google-beta
  name         = var.zone_name
  location     = var.region
  project      = var.project_id
  lake         = google_dataplex_lake.enterprise_lake.name
  display_name = "Raw Data Zone"
  description  = "Zone for raw data with automatic discovery enabled"
  type         = "RAW"
  
  # Enable discovery for automatic cataloging
  discovery_spec {
    enabled = true
    
    # Configure CSV parsing for structured data discovery
    csv_options {
      header_rows = 1
      delimiter   = ","
    }
  }
  
  # Configure resource specifications
  resource_spec {
    location_type = "SINGLE_REGION"
  }
  
  labels = local.common_labels
}

# Create Dataplex asset for Cloud Storage bucket
resource "google_dataplex_asset" "storage_asset" {
  provider     = google-beta
  name         = var.asset_name
  location     = var.region
  project      = var.project_id
  lake         = google_dataplex_lake.enterprise_lake.name
  dataplex_zone = google_dataplex_zone.raw_data_zone.name
  display_name = "Governance Storage Asset"
  description  = "Cloud Storage asset for data governance demonstration"
  
  # Configure resource specification for Cloud Storage
  resource_spec {
    name = "projects/${var.project_id}/buckets/${google_storage_bucket.data_lake.name}"
    type = "STORAGE_BUCKET"
  }
  
  # Enable discovery with specific patterns
  discovery_spec {
    enabled = true
    
    include_patterns = [
      "gs://${google_storage_bucket.data_lake.name}/raw/*"
    ]
    
    csv_options {
      header_rows = 1
      delimiter   = ","
    }
  }
  
  labels = local.common_labels
}

# Create BigLake table for customer data
resource "google_bigquery_table" "customers_biglake" {
  dataset_id          = google_bigquery_dataset.governance_analytics.dataset_id
  table_id            = "customers_biglake"
  project             = var.project_id
  description         = "BigLake table for customer data with governance controls"
  deletion_protection = var.deletion_protection
  
  external_data_configuration {
    autodetect            = false
    source_format         = "CSV"
    connection_id         = google_bigquery_connection.biglake_connection.name
    
    source_uris = [
      "gs://${google_storage_bucket.data_lake.name}/raw/customers/*"
    ]
    
    csv_options {
      skip_leading_rows = 1
      quote             = "\""
    }
    
    schema = jsonencode([
      {
        name = "customer_id"
        type = "INTEGER"
        mode = "REQUIRED"
      },
      {
        name = "name"
        type = "STRING"
        mode = "REQUIRED"
      },
      {
        name = "email"
        type = "STRING"
        mode = "REQUIRED"
      },
      {
        name = "phone"
        type = "STRING"
        mode = "NULLABLE"
      },
      {
        name = "registration_date"
        type = "DATE"
        mode = "REQUIRED"
      },
      {
        name = "country"
        type = "STRING"
        mode = "REQUIRED"
      }
    ])
  }
  
  labels = local.common_labels
}

# Create BigLake table for transaction data
resource "google_bigquery_table" "transactions_biglake" {
  dataset_id          = google_bigquery_dataset.governance_analytics.dataset_id
  table_id            = "transactions_biglake"
  project             = var.project_id
  description         = "BigLake table for transaction data with governance controls"
  deletion_protection = var.deletion_protection
  
  external_data_configuration {
    autodetect            = false
    source_format         = "CSV"
    connection_id         = google_bigquery_connection.biglake_connection.name
    
    source_uris = [
      "gs://${google_storage_bucket.data_lake.name}/raw/transactions/*"
    ]
    
    csv_options {
      skip_leading_rows = 1
      quote             = "\""
    }
    
    schema = jsonencode([
      {
        name = "transaction_id"
        type = "STRING"
        mode = "REQUIRED"
      },
      {
        name = "customer_id"
        type = "INTEGER"
        mode = "REQUIRED"
      },
      {
        name = "amount"
        type = "NUMERIC"
        mode = "REQUIRED"
      },
      {
        name = "currency"
        type = "STRING"
        mode = "REQUIRED"
      },
      {
        name = "transaction_date"
        type = "DATE"
        mode = "REQUIRED"
      },
      {
        name = "category"
        type = "STRING"
        mode = "REQUIRED"
      }
    ])
  }
  
  labels = local.common_labels
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  count    = var.function_source_archive_bucket == "" ? 1 : 0
  name     = "${local.bucket_name}-functions"
  location = var.region
  project  = var.project_id
  
  uniform_bucket_level_access = true
  labels                     = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/governance-function-${random_id.suffix.hex}.zip"
  
  source {
    content = <<-EOF
import functions_framework
from google.cloud import dataplex_v1
from google.cloud import bigquery
from google.cloud import logging
import json
import os

@functions_framework.http
def governance_monitor(request):
    """Monitor data quality and governance metrics"""
    
    # Initialize clients
    dataplex_client = dataplex_v1.DataplexServiceClient()
    bq_client = bigquery.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("governance-monitor")
    
    project_id = os.environ.get('GCP_PROJECT')
    location = os.environ.get('REGION', '${var.region}')
    
    try:
        # Query data quality metrics from BigLake tables
        quality_query = f"""
        SELECT 
            'customers_biglake' as table_name,
            COUNT(*) as total_rows,
            COUNT(DISTINCT customer_id) as unique_customers,
            COUNTIF(email IS NULL OR email = '') as missing_emails,
            COUNTIF(REGEXP_CONTAINS(email, r'^[^@]+@[^@]+\.[^@]+$') = FALSE) as invalid_emails
        FROM `{project_id}.${var.dataset_name}.customers_biglake`
        UNION ALL
        SELECT 
            'transactions_biglake' as table_name,
            COUNT(*) as total_rows,
            COUNT(DISTINCT transaction_id) as unique_transactions,
            COUNTIF(amount <= 0) as invalid_amounts,
            COUNTIF(currency NOT IN ('USD', 'CAD', 'EUR', 'GBP')) as invalid_currencies
        FROM `{project_id}.${var.dataset_name}.transactions_biglake`
        """
        
        # Execute quality monitoring query
        query_job = bq_client.query(quality_query)
        results = query_job.result()
        
        # Process results and log quality metrics
        quality_metrics = []
        for row in results:
            metrics = dict(row)
            quality_metrics.append(metrics)
            
            # Log quality issues
            if 'missing_emails' in metrics and metrics['missing_emails'] > 0:
                logger.warning(f"Data quality issue: {metrics['missing_emails']} missing emails in {metrics['table_name']}")
            
            if 'invalid_amounts' in metrics and metrics['invalid_amounts'] > 0:
                logger.warning(f"Data quality issue: {metrics['invalid_amounts']} invalid amounts in {metrics['table_name']}")
        
        return {
            'status': 'success',
            'quality_metrics': quality_metrics,
            'message': 'Governance monitoring completed successfully'
        }
        
    except Exception as e:
        logger.error(f"Governance monitoring failed: {str(e)}")
        return {
            'status': 'error',
            'message': f'Monitoring failed: {str(e)}'
        }, 500
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
google-cloud-dataplex==1.9.3
google-cloud-bigquery==3.13.0
google-cloud-logging==3.8.0
functions-framework==3.5.0
EOF
    filename = "requirements.txt"
  }
}

# Upload Cloud Function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "governance-function-${random_id.suffix.hex}.zip"
  bucket = var.function_source_archive_bucket != "" ? var.function_source_archive_bucket : google_storage_bucket.function_source[0].name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create Cloud Function for governance monitoring
resource "google_cloudfunctions2_function" "governance_monitor" {
  name        = var.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated data governance monitoring function"
  
  build_config {
    runtime     = "python311"
    entry_point = "governance_monitor"
    
    source {
      storage_source {
        bucket = var.function_source_archive_bucket != "" ? var.function_source_archive_bucket : google_storage_bucket.function_source[0].name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "256M"
    timeout_seconds    = 300
    
    environment_variables = {
      REGION = var.region
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create IAM policy for Cloud Function to access BigQuery and Dataplex
resource "google_project_iam_member" "function_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_cloudfunctions2_function.governance_monitor.service_config[0].service_account_email}"
}

resource "google_project_iam_member" "function_bigquery_data_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_cloudfunctions2_function.governance_monitor.service_config[0].service_account_email}"
}

resource "google_project_iam_member" "function_dataplex_viewer" {
  project = var.project_id
  role    = "roles/dataplex.viewer"
  member  = "serviceAccount:${google_cloudfunctions2_function.governance_monitor.service_config[0].service_account_email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_cloudfunctions2_function.governance_monitor.service_config[0].service_account_email}"
}