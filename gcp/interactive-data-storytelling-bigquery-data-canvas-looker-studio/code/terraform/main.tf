# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  service = each.key
  project = var.project_id

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for Cloud Function source code and temporary storage
resource "google_storage_bucket" "function_bucket" {
  name     = "${var.project_id}-storytelling-${random_id.suffix.hex}"
  location = var.bucket_location
  project  = var.project_id

  # Enable versioning for source code management
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security configurations
  uniform_bucket_level_access = true
  
  # Apply labels for resource management
  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for analytics data
resource "google_bigquery_dataset" "retail_analytics" {
  dataset_id  = "${var.dataset_name}_${random_id.suffix.hex}"
  project     = var.project_id
  description = var.dataset_description
  location    = var.dataset_location

  # Data retention and access controls
  default_table_expiration_ms = 31536000000 # 1 year in milliseconds
  
  # Labels for resource management
  labels = var.labels

  # Access configuration for Looker Studio integration
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }

  # Access for BigQuery Data Canvas service
  access {
    role         = "READER"
    special_group = "projectReaders"
  }

  depends_on = [google_project_service.required_apis]
}

# BigQuery table for sales data with comprehensive schema
resource "google_bigquery_table" "sales_data" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "sales_data"
  project    = var.project_id

  # Define comprehensive schema for retail analytics
  schema = jsonencode([
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for each product"
    },
    {
      name = "product_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Display name of the product"
    },
    {
      name = "category"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product category classification"
    },
    {
      name = "sales_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of the sales transaction"
    },
    {
      name = "quantity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of units sold"
    },
    {
      name = "unit_price"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Price per unit in USD"
    },
    {
      name = "customer_segment"
      type = "STRING"
      mode = "REQUIRED"
      description = "Customer segment classification"
    },
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
      description = "Geographic region of the sale"
    },
    {
      name = "revenue"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Total revenue (quantity * unit_price)"
    }
  ])

  # Table clustering for optimal query performance
  clustering = ["category", "customer_segment", "region"]

  # Time partitioning for efficient querying
  time_partitioning {
    type  = "DAY"
    field = "sales_date"
  }

  # Apply labels for resource management
  labels = var.labels

  depends_on = [google_bigquery_dataset.retail_analytics]
}

# Materialized view for optimized Looker Studio performance
resource "google_bigquery_table" "dashboard_data" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "dashboard_data"
  project    = var.project_id

  # Define materialized view with aggregated data for dashboards
  materialized_view {
    query = <<-SQL
      SELECT 
        category,
        customer_segment,
        region,
        sales_date,
        SUM(revenue) as daily_revenue,
        SUM(quantity) as daily_quantity,
        COUNT(DISTINCT product_id) as products_sold,
        AVG(unit_price) as avg_price
      FROM `${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.sales_data`
      GROUP BY category, customer_segment, region, sales_date
    SQL

    # Enable auto refresh for real-time dashboards
    enable_refresh = true
    refresh_interval_ms = 1800000 # 30 minutes
  }

  # Apply labels for resource management
  labels = var.labels

  depends_on = [google_bigquery_table.sales_data]
}

# Load sample data into BigQuery table (conditional)
resource "google_bigquery_job" "load_sample_data" {
  count   = var.load_sample_data ? 1 : 0
  job_id  = "load_sample_data_${random_id.suffix.hex}"
  project = var.project_id

  load {
    source_uris = ["gs://${google_storage_bucket.function_bucket.name}/sample_data.csv"]

    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
      table_id   = google_bigquery_table.sales_data.table_id
    }

    # CSV loading configuration
    source_format = "CSV"
    skip_leading_rows = 1
    autodetect = false
    allow_jagged_rows = false
    allow_quoted_newlines = false

    # Schema configuration (matches table schema)
    schema = google_bigquery_table.sales_data.schema
  }

  depends_on = [
    google_storage_bucket_object.sample_data,
    google_bigquery_table.sales_data
  ]
}

# Sample data file for BigQuery loading
resource "google_storage_bucket_object" "sample_data" {
  count  = var.load_sample_data ? 1 : 0
  name   = "sample_data.csv"
  bucket = google_storage_bucket.function_bucket.name

  # Generate comprehensive sample data with realistic business patterns
  content = <<-CSV
product_id,product_name,category,sales_date,quantity,unit_price,customer_segment,region,revenue
P001,Wireless Headphones,Electronics,2024-01-15,25,99.99,Premium,North America,2499.75
P002,Fitness Tracker,Electronics,2024-01-16,18,149.99,Health-Conscious,Europe,2699.82
P003,Coffee Maker,Home & Kitchen,2024-01-17,12,79.99,Everyday,North America,959.88
P004,Running Shoes,Sports,2024-01-18,30,129.99,Athletic,Asia,3899.70
P005,Smartphone Case,Electronics,2024-01-19,45,24.99,Budget,North America,1124.55
P006,Yoga Mat,Sports,2024-01-20,22,39.99,Health-Conscious,Europe,879.78
P007,Bluetooth Speaker,Electronics,2024-01-21,15,199.99,Premium,Asia,2999.85
P008,Water Bottle,Sports,2024-01-22,60,19.99,Everyday,North America,1199.40
P009,Laptop Stand,Office,2024-01-23,8,89.99,Professional,Europe,719.92
P010,Air Fryer,Home & Kitchen,2024-01-24,10,159.99,Everyday,Asia,1599.90
P011,Gaming Mouse,Electronics,2024-01-25,35,59.99,Gaming,North America,2099.65
P012,Desk Lamp,Office,2024-01-26,14,49.99,Professional,Europe,699.86
P013,Protein Powder,Health,2024-01-27,25,39.99,Health-Conscious,North America,999.75
P014,Wireless Charger,Electronics,2024-01-28,28,29.99,Premium,Asia,839.72
P015,Kitchen Scale,Home & Kitchen,2024-01-29,16,34.99,Everyday,Europe,559.84
P016,Monitor Stand,Office,2024-01-30,12,79.99,Professional,North America,959.88
P017,Smart Watch,Electronics,2024-01-31,20,299.99,Premium,Asia,5999.80
P018,Exercise Bike,Sports,2024-02-01,5,499.99,Athletic,Europe,2499.95
P019,Desk Organizer,Office,2024-02-02,30,24.99,Professional,North America,749.70
P020,Blender,Home & Kitchen,2024-02-03,18,89.99,Everyday,Asia,1619.82
CSV

  content_type = "text/csv"
}

# Service account for Cloud Function with appropriate permissions
resource "google_service_account" "function_sa" {
  account_id   = "storytelling-function-sa"
  display_name = "Data Storytelling Function Service Account"
  description  = "Service account for automated data storytelling Cloud Function"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the function service account
resource "google_project_iam_member" "function_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_bigquery_data_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_vertex_ai_user" {
  count   = var.enable_vertex_ai ? 1 : 0
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/storytelling-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      dataset_name = google_bigquery_dataset.retail_analytics.dataset_id
      region       = var.region
    })
    filename = "main.py"
  }

  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "storytelling-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for automated data storytelling
resource "google_cloudfunctions_function" "storytelling_function" {
  name    = "${var.resource_prefix}${var.function_name}-${random_id.suffix.hex}"
  project = var.project_id
  region  = var.region

  # Function source configuration
  source_archive_bucket = google_storage_bucket.function_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name

  # Runtime configuration
  runtime           = "python39"
  entry_point       = "generate_data_story"
  available_memory_mb = var.function_memory
  timeout           = var.function_timeout

  # Trigger configuration for HTTP access
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  # Environment variables for function configuration
  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = google_bigquery_dataset.retail_analytics.dataset_id
    REGION       = var.region
    BUCKET_NAME  = google_storage_bucket.function_bucket.name
  }

  # Service account configuration
  service_account_email = google_service_account.function_sa.email

  # Labels for resource management
  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_bigquery_user,
    google_project_iam_member.function_bigquery_data_viewer
  ]
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "scheduler-sa"
  display_name = "Cloud Scheduler Service Account"
  description  = "Service account for Cloud Scheduler job execution"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM binding for Cloud Scheduler to invoke Cloud Functions
resource "google_project_iam_member" "scheduler_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Cloud Scheduler job for automated report generation
resource "google_cloud_scheduler_job" "storytelling_job" {
  name     = "${var.resource_prefix}${var.scheduler_job_name}-${random_id.suffix.hex}"
  project  = var.project_id
  region   = var.region
  schedule = var.scheduler_cron
  time_zone = var.scheduler_timezone

  description = "Automated data storytelling report generation"

  # HTTP target configuration to invoke Cloud Function
  http_target {
    uri         = google_cloudfunctions_function.storytelling_function.https_trigger_url
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      automated = true
      source    = "scheduler"
      timestamp = "{{.ts}}"
    }))

    # OAuth authentication using the scheduler service account
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience             = google_cloudfunctions_function.storytelling_function.https_trigger_url
    }
  }

  depends_on = [
    google_cloudfunctions_function.storytelling_function,
    google_project_iam_member.scheduler_function_invoker
  ]
}

# Data source to get current user information
data "google_client_openid_userinfo" "me" {}

# BigQuery saved query for advanced analytics (optional enhancement)
resource "google_bigquery_routine" "revenue_analysis" {
  dataset_id      = google_bigquery_dataset.retail_analytics.dataset_id
  routine_id      = "revenue_analysis"
  project         = var.project_id
  routine_type    = "SCALAR_FUNCTION"
  language        = "SQL"
  
  # SQL function for revenue trend analysis
  definition_body = <<-SQL
    (
      SELECT 
        STRUCT(
          SUM(revenue) as total_revenue,
          COUNT(DISTINCT product_id) as unique_products,
          AVG(unit_price) as avg_price,
          APPROX_QUANTILES(revenue, 4)[OFFSET(2)] as median_revenue
        )
      FROM `${var.project_id}.${google_bigquery_dataset.retail_analytics.dataset_id}.sales_data`
      WHERE sales_date >= start_date AND sales_date <= end_date
    )
  SQL

  arguments {
    name = "start_date"
    data_type = jsonencode({"typeKind": "DATE"})
  }

  arguments {
    name = "end_date"
    data_type = jsonencode({"typeKind": "DATE"})
  }

  return_type = jsonencode({
    "typeKind": "STRUCT",
    "structType": {
      "fields": [
        {"name": "total_revenue", "type": {"typeKind": "FLOAT64"}},
        {"name": "unique_products", "type": {"typeKind": "INT64"}},
        {"name": "avg_price", "type": {"typeKind": "FLOAT64"}},
        {"name": "median_revenue", "type": {"typeKind": "FLOAT64"}}
      ]
    }
  })

  description = "Custom function for comprehensive revenue analysis"

  depends_on = [google_bigquery_dataset.retail_analytics]
}