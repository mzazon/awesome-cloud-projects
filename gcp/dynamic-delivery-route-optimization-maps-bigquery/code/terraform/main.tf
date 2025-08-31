# main.tf
# Main Terraform configuration for GCP Dynamic Delivery Route Optimization

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix        = random_id.suffix.hex
  dataset_name          = "delivery_analytics"
  function_name         = "${var.resource_name_prefix}-optimizer-${local.resource_suffix}"
  bucket_name           = "${var.project_id}-${var.resource_name_prefix}-data-${local.resource_suffix}"
  source_bucket_name    = var.function_source_bucket != "" ? var.function_source_bucket : "${var.project_id}-${var.resource_name_prefix}-source-${local.resource_suffix}"
  scheduler_job_name    = "optimize-routes-automated"
  
  # Table names
  deliveries_table_name = "delivery_history"
  routes_table_name     = "optimized_routes"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
  
  # Required APIs for the solution
  required_apis = [
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "routeoptimization.googleapis.com",
    "storage.googleapis.com", 
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    read   = "5m"
  }
}

# BigQuery Dataset for delivery analytics
resource "google_bigquery_dataset" "delivery_analytics" {
  dataset_id    = local.dataset_name
  friendly_name = "Delivery and Route Optimization Analytics"
  description   = "Dataset containing delivery history and optimized route data for logistics analytics"
  location      = var.bigquery_dataset_location
  
  delete_contents_on_destroy = !var.bigquery_deletion_protection
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery Table for delivery history with partitioning and clustering
resource "google_bigquery_table" "delivery_history" {
  dataset_id = google_bigquery_dataset.delivery_analytics.dataset_id
  table_id   = local.deliveries_table_name
  
  description = "Historical delivery performance data with geographic and temporal partitioning"
  
  labels = local.common_labels
  
  # Time-based partitioning for efficient queries
  time_partitioning {
    type  = "DAY"
    field = "delivery_date"
  }
  
  # Clustering for geospatial and vehicle type queries
  clustering = ["delivery_zone", "vehicle_type"]
  
  schema = jsonencode([
    {
      name = "delivery_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the delivery"
    },
    {
      name = "delivery_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of the delivery"
    },
    {
      name = "pickup_lat"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Pickup location latitude"
    },
    {
      name = "pickup_lng"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Pickup location longitude"
    },
    {
      name = "delivery_lat"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Delivery location latitude"
    },
    {
      name = "delivery_lng"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Delivery location longitude"
    },
    {
      name = "delivery_zone"
      type = "STRING"
      mode = "REQUIRED"
      description = "Geographic delivery zone identifier"
    },
    {
      name = "vehicle_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of delivery vehicle (van, truck, etc.)"
    },
    {
      name = "delivery_time_minutes"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Total delivery time in minutes"
    },
    {
      name = "distance_km"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Total delivery distance in kilometers"
    },
    {
      name = "fuel_cost"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Fuel cost for the delivery"
    },
    {
      name = "driver_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Identifier for the delivery driver"
    },
    {
      name = "customer_priority"
      type = "STRING"
      mode = "REQUIRED"
      description = "Customer priority level (high, medium, low)"
    }
  ])
}

# BigQuery Table for optimized routes
resource "google_bigquery_table" "optimized_routes" {
  dataset_id = google_bigquery_dataset.delivery_analytics.dataset_id
  table_id   = local.routes_table_name
  
  description = "AI-generated optimized delivery routes with performance metrics"
  
  labels = local.common_labels
  
  # Time-based partitioning for route analysis
  time_partitioning {
    type  = "DAY"
    field = "route_date"
  }
  
  schema = jsonencode([
    {
      name = "route_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the optimized route"
    },
    {
      name = "route_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date the route was generated"
    },
    {
      name = "vehicle_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Identifier for the assigned vehicle"
    },
    {
      name = "driver_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Identifier for the assigned driver"
    },
    {
      name = "total_stops"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Total number of delivery stops in the route"
    },
    {
      name = "estimated_duration_minutes"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Estimated total route duration in minutes"
    },
    {
      name = "estimated_distance_km"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Estimated total route distance in kilometers"
    },
    {
      name = "optimization_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Route optimization efficiency score (0.0 to 1.0)"
    },
    {
      name = "route_waypoints"
      type = "STRING"
      mode = "REQUIRED"
      description = "JSON string containing route waypoint coordinates"
    }
  ])
}

# BigQuery Views for analytics
resource "google_bigquery_table" "delivery_performance_view" {
  dataset_id = google_bigquery_dataset.delivery_analytics.dataset_id
  table_id   = "delivery_performance_view"
  
  description = "Real-time delivery performance metrics aggregated by zone and vehicle type"
  
  labels = local.common_labels
  
  view {
    query = <<-EOT
      SELECT 
        delivery_zone,
        vehicle_type,
        DATE(delivery_date) as delivery_date,
        COUNT(*) as total_deliveries,
        AVG(delivery_time_minutes) as avg_delivery_time,
        AVG(distance_km) as avg_distance,
        AVG(fuel_cost) as avg_fuel_cost,
        SUM(fuel_cost) as total_fuel_cost
      FROM `${var.project_id}.${local.dataset_name}.${local.deliveries_table_name}`
      WHERE delivery_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
      GROUP BY delivery_zone, vehicle_type, DATE(delivery_date)
      ORDER BY delivery_date DESC, delivery_zone
    EOT
    use_legacy_sql = false
  }
  
  depends_on = [google_bigquery_table.delivery_history]
}

resource "google_bigquery_table" "route_efficiency_view" {
  dataset_id = google_bigquery_dataset.delivery_analytics.dataset_id
  table_id   = "route_efficiency_view"
  
  description = "Route optimization performance analysis with efficiency metrics"
  
  labels = local.common_labels
  
  view {
    query = <<-EOT
      SELECT 
        DATE(route_date) as route_date,
        COUNT(*) as total_routes,
        AVG(optimization_score) as avg_optimization_score,
        AVG(estimated_duration_minutes) as avg_duration,
        AVG(estimated_distance_km) as avg_distance,
        AVG(total_stops) as avg_stops_per_route
      FROM `${var.project_id}.${local.dataset_name}.${local.routes_table_name}`
      WHERE route_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
      GROUP BY DATE(route_date)
      ORDER BY route_date DESC
    EOT
    use_legacy_sql = false
  }
  
  depends_on = [google_bigquery_table.optimized_routes]
}

# Cloud Storage bucket for route data and logs
resource "google_storage_bucket" "route_data" {
  name     = local.bucket_name
  location = var.region
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_nearline_age
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_coldline_age
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  force_destroy = var.storage_bucket_force_destroy
  
  depends_on = [google_project_service.required_apis]
}

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = local.source_bucket_name
  location = var.region
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  force_destroy = true
  
  depends_on = [google_project_service.required_apis]
}

# Create folder structure in storage bucket using objects
resource "google_storage_bucket_object" "folder_markers" {
  for_each = toset([
    "route-requests/README.txt",
    "route-responses/README.txt", 
    "logs/README.txt",
    "historical-data/README.txt"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.route_data.name
  
  content = "Folder for ${split("/", each.value)[0]} data"
  
  depends_on = [google_storage_bucket.route_data]
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/route-optimizer-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
      bucket_name  = local.bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "route-optimizer-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Service account for Cloud Function
resource "google_service_account" "function_service_account" {
  account_id   = "${var.resource_name_prefix}-func-sa-${local.resource_suffix}"
  display_name = "Route Optimizer Function Service Account"
  description  = "Service account for route optimization Cloud Function"
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_route_optimization_user" {
  project = var.project_id
  role    = "roles/routeoptimization.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Cloud Function for route optimization
resource "google_cloudfunctions2_function" "route_optimizer" {
  name     = local.function_name
  location = var.region
  
  description = "Serverless function for route optimization using Maps Platform Route Optimization API"
  
  build_config {
    runtime     = "python311"
    entry_point = "optimize_routes"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.cloud_function_memory}Mi"
    timeout_seconds                  = var.cloud_function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      BUCKET_NAME  = local.bucket_name
      DATASET_NAME = local.dataset_name
      DEPOT_LAT    = var.depot_latitude
      DEPOT_LNG    = var.depot_longitude
    }
    
    service_account_email = google_service_account.function_service_account.email
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source_zip,
    google_bigquery_table.optimized_routes
  ]
}

# IAM policy for function invocation
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.route_optimizer.location
  cloud_function = google_cloudfunctions2_function.route_optimizer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Scheduler job for automated route optimization
resource "google_cloud_scheduler_job" "route_optimization_scheduler" {
  name      = local.scheduler_job_name
  region    = var.region
  schedule  = var.scheduler_frequency
  time_zone = "UTC"
  
  description = "Automated route optimization scheduling every 2 hours"
  
  http_target {
    uri         = google_cloudfunctions2_function.route_optimizer.service_config[0].uri
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      deliveries = [
        {
          delivery_id        = "AUTO001"
          lat               = 37.7749
          lng               = -122.4194
          estimated_minutes = 25
          estimated_km      = 3.2
        },
        {
          delivery_id        = "AUTO002"
          lat               = 37.7849
          lng               = -122.4094
          estimated_minutes = 30
          estimated_km      = 4.1
        },
        {
          delivery_id        = "AUTO003"
          lat               = 37.7949
          lng               = -122.4294
          estimated_minutes = 35
          estimated_km      = 5.8
        }
      ]
      vehicle_id       = "SCHED_VEH001"
      driver_id        = "SCHED_DRV001"
      vehicle_capacity = 10
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_service_account.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.route_optimizer
  ]
}

# Load sample data into BigQuery if enabled
resource "google_bigquery_job" "load_sample_data" {
  count = var.sample_data_load ? 1 : 0
  
  job_id = "sample_data_load_${local.resource_suffix}"
  
  load {
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.delivery_analytics.dataset_id
      table_id   = google_bigquery_table.delivery_history.table_id
    }
    
    source_uris = ["gs://${google_storage_bucket.route_data.name}/historical-data/sample_deliveries.csv"]
    
    skip_leading_rows = 1
    field_delimiter   = ","
    source_format     = "CSV"
    autodetect        = true
    
    write_disposition = "WRITE_APPEND"
  }
  
  depends_on = [
    google_bigquery_table.delivery_history,
    google_storage_bucket_object.sample_data
  ]
}

# Sample data file
resource "google_storage_bucket_object" "sample_data" {
  count = var.sample_data_load ? 1 : 0
  
  name   = "historical-data/sample_deliveries.csv"
  bucket = google_storage_bucket.route_data.name
  
  content = <<-EOT
delivery_id,delivery_date,pickup_lat,pickup_lng,delivery_lat,delivery_lng,delivery_zone,vehicle_type,delivery_time_minutes,distance_km,fuel_cost,driver_id,customer_priority
DEL001,2024-07-10,37.7749,-122.4194,37.7849,-122.4094,zone_downtown,van,25,3.2,8.50,driver_001,high
DEL002,2024-07-10,37.7749,-122.4194,37.8049,-122.4294,zone_north,van,35,5.8,12.75,driver_001,medium
DEL003,2024-07-10,37.7649,-122.4094,37.7949,-122.4394,zone_west,truck,45,8.1,18.20,driver_002,high
DEL004,2024-07-11,37.7549,-122.4294,37.7749,-122.4094,zone_downtown,van,20,2.5,6.80,driver_003,low
DEL005,2024-07-11,37.7849,-122.4194,37.8149,-122.4494,zone_north,van,40,6.9,15.30,driver_003,medium
DEL006,2024-07-11,37.7449,-122.4394,37.7649,-122.4194,zone_south,truck,50,9.3,21.50,driver_002,high
DEL007,2024-07-12,37.7749,-122.4194,37.7549,-122.4494,zone_west,van,30,4.1,9.75,driver_001,medium
DEL008,2024-07-12,37.7949,-122.4094,37.8249,-122.4194,zone_north,van,28,3.8,8.90,driver_004,high
EOT
  
  depends_on = [google_storage_bucket.route_data]
}

# Monitoring dashboard (optional)
resource "google_monitoring_dashboard" "route_optimization_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id    = var.project_id
    function_name = local.function_name
    region        = var.region
  })
  
  depends_on = [google_project_service.required_apis]
}