# Main Terraform configuration for GCP Dynamic Pricing Optimization
# This file creates all the necessary infrastructure for a machine learning-powered
# pricing optimization system using BigQuery, Vertex AI, Cloud Functions, and Cloud Scheduler

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-data-${local.resource_suffix}"
  function_name   = "${var.resource_prefix}-optimizer-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    purpose    = "pricing-optimization"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental disabling of APIs
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for pricing optimization functions
resource "google_service_account" "pricing_optimizer" {
  account_id   = "${var.resource_prefix}-optimizer-sa"
  display_name = "Pricing Optimizer Service Account"
  description  = "Service account for pricing optimization Cloud Functions and Vertex AI jobs"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "pricing_optimizer_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",      # Read/write BigQuery data and create ML models
    "roles/bigquery.jobUser",         # Run BigQuery jobs and queries
    "roles/storage.objectAdmin",      # Manage Cloud Storage objects
    "roles/aiplatform.user",          # Use Vertex AI services
    "roles/monitoring.metricWriter",  # Write custom metrics
    "roles/logging.logWriter"         # Write application logs
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.pricing_optimizer.email}"

  depends_on = [google_service_account.pricing_optimizer]
}

# Create Cloud Storage bucket for data and model artifacts
resource "google_storage_bucket" "pricing_data" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.bucket_storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion in production
  force_destroy = var.environment != "prod"
  
  # Enable versioning for data integrity
  versioning {
    enabled = true
  }
  
  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Transition to cheaper storage class after 30 days
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery dataset for pricing optimization data
resource "google_bigquery_dataset" "pricing_optimization" {
  dataset_id    = var.dataset_name
  project       = var.project_id
  friendly_name = "Pricing Optimization Dataset"
  description   = var.dataset_description
  location      = var.dataset_location
  
  # Set appropriate access controls
  access {
    role          = "OWNER"
    user_by_email = google_service_account.pricing_optimizer.email
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  access {
    role           = "OWNER"
    special_group  = "projectOwners"
  }

  # Enable table expiration for cost control (optional)
  default_table_expiration_ms = var.enable_cost_controls ? 7776000000 : null # 90 days

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create sales history table in BigQuery
resource "google_bigquery_table" "sales_history" {
  dataset_id          = google_bigquery_dataset.pricing_optimization.dataset_id
  table_id            = "sales_history"
  project             = var.project_id
  deletion_protection = var.environment == "prod"

  schema = jsonencode([
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique product identifier"
    },
    {
      name = "sale_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of the sale transaction"
    },
    {
      name = "price"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Product price at time of sale"
    },
    {
      name = "quantity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of units sold"
    },
    {
      name = "revenue"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Total revenue from the sale"
    },
    {
      name = "competitor_price"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Competitor price at time of sale"
    },
    {
      name = "inventory_level"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Inventory level at time of sale"
    },
    {
      name = "season"
      type = "STRING"
      mode = "NULLABLE"
      description = "Season when sale occurred (winter, spring, summer, fall)"
    },
    {
      name = "promotion"
      type = "BOOLEAN"
      mode = "NULLABLE"
      description = "Whether the product was on promotion"
    }
  ])

  # Enable partitioning by sale_date for better performance
  time_partitioning {
    type  = "DAY"
    field = "sale_date"
  }

  # Enable clustering for better query performance
  clustering = ["product_id", "season"]

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.pricing_optimization]
}

# Create competitor pricing table in BigQuery
resource "google_bigquery_table" "competitor_pricing" {
  dataset_id          = google_bigquery_dataset.pricing_optimization.dataset_id
  table_id            = "competitor_pricing"
  project             = var.project_id
  deletion_protection = var.environment == "prod"

  schema = jsonencode([
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique product identifier"
    },
    {
      name = "competitor"
      type = "STRING"
      mode = "REQUIRED"
      description = "Competitor name or identifier"
    },
    {
      name = "price"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Competitor product price"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the price was observed"
    },
    {
      name = "availability"
      type = "BOOLEAN"
      mode = "NULLABLE"
      description = "Whether the product is available from this competitor"
    }
  ])

  # Enable partitioning by timestamp for better performance
  time_partitioning {
    type  = "HOUR"
    field = "timestamp"
  }

  # Enable clustering for better query performance
  clustering = ["product_id", "competitor"]

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.pricing_optimization]
}

# Create sample data file for loading into BigQuery (if enabled)
resource "local_file" "sample_sales_data" {
  count    = var.load_sample_data ? 1 : 0
  filename = "sample_sales_data.csv"
  content = <<-EOF
product_id,sale_date,price,quantity,revenue,competitor_price,inventory_level,season,promotion
PROD001,2024-01-15,29.99,150,4498.50,31.99,1200,winter,false
PROD001,2024-02-15,27.99,180,5038.20,30.99,800,winter,true
PROD001,2024-03-15,32.99,120,3958.80,34.99,1500,spring,false
PROD002,2024-01-15,15.99,200,3198.00,16.99,500,winter,false
PROD002,2024-02-15,14.99,250,3747.50,15.99,300,winter,true
PROD002,2024-03-15,17.99,180,3238.20,18.99,600,spring,false
PROD003,2024-01-15,45.99,80,3679.20,47.99,200,winter,false
PROD003,2024-02-15,42.99,100,4299.00,45.99,150,winter,true
PROD003,2024-03-15,48.99,90,4409.10,49.99,250,spring,false
PROD001,2024-04-15,35.99,110,3959.00,36.99,1800,spring,false
PROD001,2024-05-15,30.99,160,4958.40,32.99,1000,spring,true
PROD002,2024-04-15,18.99,220,4177.80,19.99,700,spring,false
PROD002,2024-05-15,16.99,190,3228.10,17.99,400,spring,true
PROD003,2024-04-15,49.99,95,4749.05,51.99,300,spring,false
PROD003,2024-05-15,44.99,120,5398.80,46.99,180,spring,true
EOF
}

# Upload sample data to Cloud Storage (if enabled)
resource "google_storage_bucket_object" "sample_data" {
  count  = var.load_sample_data ? 1 : 0
  name   = "sample_data/sales_history.csv"
  bucket = google_storage_bucket.pricing_data.name
  source = local_file.sample_sales_data[0].filename

  depends_on = [local_file.sample_sales_data]
}

# Load sample data into BigQuery (if enabled)
resource "google_bigquery_job" "load_sample_data" {
  count      = var.load_sample_data ? 1 : 0
  project    = var.project_id
  job_id     = "load_sample_data_${local.resource_suffix}"
  location   = var.dataset_location
  
  load {
    source_uris = [
      "gs://${google_storage_bucket.pricing_data.name}/sample_data/sales_history.csv"
    ]
    
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.pricing_optimization.dataset_id
      table_id   = google_bigquery_table.sales_history.table_id
    }
    
    skip_leading_rows = 1
    source_format     = "CSV"
    autodetect        = true
    
    write_disposition = "WRITE_APPEND"
  }

  depends_on = [
    google_storage_bucket_object.sample_data,
    google_bigquery_table.sales_history
  ]
}

# Create Cloud Function source code archive
data "archive_file" "pricing_function_source" {
  type        = "zip"
  output_path = "pricing_function.zip"
  
  source {
    content = <<-EOF
import functions_framework
from google.cloud import bigquery
import json
import pandas as pd
import os

# Initialize clients
bq_client = bigquery.Client()

@functions_framework.http
def optimize_pricing(request):
    """HTTP Cloud Function for pricing optimization."""
    # Set CORS headers for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)

    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'Request must be JSON'}, 400, headers)
            
        product_id = request_json.get('product_id')
        
        if not product_id:
            return ({'error': 'product_id is required'}, 400, headers)
        
        # Get dataset name from environment or use default
        dataset_name = os.environ.get('DATASET_NAME', 'pricing_optimization')
        project_id = os.environ.get('GCP_PROJECT')
        
        # Get current product data
        query = f"""
        SELECT 
            price,
            competitor_price,
            inventory_level,
            season,
            promotion
        FROM `{project_id}.{dataset_name}.sales_history`
        WHERE product_id = @product_id
        ORDER BY sale_date DESC
        LIMIT 1
        """
        
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("product_id", "STRING", product_id)
            ]
        )
        
        result = bq_client.query(query, job_config=job_config).to_dataframe()
        
        if result.empty:
            return ({'error': f'Product {product_id} not found'}, 404, headers)
        
        current_data = result.iloc[0]
        
        # Simple pricing optimization logic
        base_price = float(current_data['price'])
        competitor_price = float(current_data['competitor_price']) if pd.notna(current_data['competitor_price']) else base_price * 1.1
        inventory_level = int(current_data['inventory_level']) if pd.notna(current_data['inventory_level']) else 500
        
        # Business rules for pricing constraints
        min_price = base_price * 0.8  # No more than 20% below current
        max_price = min(base_price * 1.3, competitor_price * 0.95)  # Max 30% increase or 5% below competitor
        
        # Simple optimization logic
        if inventory_level > 1000:
            recommended_price = min(max_price, base_price * 1.05)  # Small increase if high inventory
        elif inventory_level < 300:
            recommended_price = max(min_price, base_price * 0.95)  # Small decrease if low inventory
        else:
            recommended_price = base_price  # Keep current price
        
        # Calculate predicted revenue (simplified model)
        # In production, this would use the actual BigQuery ML model
        demand_factor = max(0.1, min(2.0, competitor_price / recommended_price))
        predicted_quantity = inventory_level * 0.1 * demand_factor
        predicted_revenue = recommended_price * predicted_quantity
        
        response = {
            'product_id': product_id,
            'current_price': base_price,
            'recommended_price': round(recommended_price, 2),
            'competitor_price': competitor_price,
            'predicted_revenue': round(predicted_revenue, 2),
            'price_change_percent': round(((recommended_price - base_price) / base_price) * 100, 2),
            'inventory_level': inventory_level,
            'timestamp': pd.Timestamp.now().isoformat(),
            'optimization_reason': 'inventory_level' if inventory_level != 500 else 'baseline'
        }
        
        return (response, 200, headers)
        
    except Exception as e:
        error_response = {
            'error': str(e),
            'timestamp': pd.Timestamp.now().isoformat()
        }
        return (error_response, 500, headers)
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
functions-framework==3.*
google-cloud-bigquery>=3.0.0
pandas>=1.5.0
numpy>=1.24.0
EOF
    filename = "requirements.txt"
  }
}

# Upload Cloud Function source to Storage
resource "google_storage_bucket_object" "pricing_function_source" {
  name   = "cloud_functions/pricing_optimizer/pricing_function.zip"
  bucket = google_storage_bucket.pricing_data.name
  source = data.archive_file.pricing_function_source.output_path

  depends_on = [data.archive_file.pricing_function_source]
}

# Create Cloud Function for pricing optimization
resource "google_cloudfunctions2_function" "pricing_optimizer" {
  name        = local.function_name
  project     = var.project_id
  location    = var.region
  description = "Dynamic pricing optimization function using ML models"

  build_config {
    runtime     = var.function_runtime
    entry_point = "optimize_pricing"
    
    source {
      storage_source {
        bucket = google_storage_bucket.pricing_data.name
        object = google_storage_bucket_object.pricing_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      DATASET_NAME = var.dataset_name
      GCP_PROJECT  = var.project_id
    }
    
    service_account_email = google_service_account.pricing_optimizer.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.pricing_function_source
  ]
}

# Create IAM policy for Cloud Function access
resource "google_cloudfunctions2_function_iam_binding" "pricing_optimizer_invoker" {
  count           = var.enable_public_access ? 1 : 0
  project         = var.project_id
  location        = var.region
  cloud_function  = google_cloudfunctions2_function.pricing_optimizer.name
  role            = "roles/cloudfunctions.invoker"
  members         = ["allUsers"]
}

# Create IAM policy for specific members (when public access is disabled)
resource "google_cloudfunctions2_function_iam_binding" "pricing_optimizer_private_invoker" {
  count           = var.enable_public_access ? 0 : (length(var.allowed_members) > 0 ? 1 : 0)
  project         = var.project_id
  location        = var.region
  cloud_function  = google_cloudfunctions2_function.pricing_optimizer.name
  role            = "roles/cloudfunctions.invoker"
  members         = var.allowed_members
}

# Create Cloud Scheduler jobs for automated pricing updates
resource "google_cloud_scheduler_job" "pricing_optimization" {
  count            = length(var.product_ids)
  name             = "${var.resource_prefix}-scheduler-${var.product_ids[count.index]}-${local.resource_suffix}"
  project          = var.project_id
  region           = var.region
  description      = "Automated pricing optimization for product ${var.product_ids[count.index]}"
  schedule         = var.scheduler_frequency
  time_zone        = var.scheduler_timezone
  attempt_deadline = "${var.function_timeout + 30}s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.pricing_optimizer.service_config[0].uri
    
    body = base64encode(jsonencode({
      product_id = var.product_ids[count.index]
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }

    # Use service account for authentication
    oidc_token {
      service_account_email = google_service_account.pricing_optimizer.email
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.pricing_optimizer
  ]
}

# Grant scheduler service account permission to invoke Cloud Function
resource "google_cloudfunctions2_function_iam_member" "scheduler_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.pricing_optimizer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.pricing_optimizer.email}"
}

# Create monitoring dashboard (if enabled)
resource "google_monitoring_dashboard" "pricing_optimization" {
  count          = var.enable_monitoring_dashboard ? 1 : 0
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Dynamic Pricing Optimization Dashboard"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Function Executions"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Executions per minute"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Execution Duration"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\" metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Duration (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "BigQuery Query Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_dataset\" resource.labels.dataset_id=\"${var.dataset_name}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Queries per 5 minutes"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Errors"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\" metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" metric.labels.status!=\"ok\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Errors per minute"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.pricing_optimizer
  ]
}

# Create alert policy for function errors (if notification email provided)
resource "google_monitoring_alert_policy" "function_errors" {
  count               = var.notification_email != "" ? 1 : 0
  project             = var.project_id
  display_name        = "Pricing Optimizer Function Errors"
  combiner            = "OR"
  enabled             = true
  notification_channels = [google_monitoring_notification_channel.email[0].id]

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\" metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" metric.labels.status!=\"ok\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_monitoring_notification_channel.email,
    google_cloudfunctions2_function.pricing_optimizer
  ]
}

# Create notification channel for email alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "Pricing Optimization Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}