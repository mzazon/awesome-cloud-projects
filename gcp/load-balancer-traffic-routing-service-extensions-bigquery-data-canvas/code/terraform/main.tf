# Main Terraform Configuration for GCP Load Balancer Traffic Routing with Service Extensions
# This configuration creates an intelligent traffic routing system using Service Extensions,
# BigQuery Data Canvas, and Cloud Run services

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    created_by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "serviceextensions.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# BigQuery Dataset for Traffic Analytics
resource "google_bigquery_dataset" "traffic_analytics" {
  dataset_id                 = "${var.resource_name_prefix}_analytics_${local.name_suffix}"
  friendly_name             = "Traffic Analytics Dataset"
  description               = var.bigquery_dataset_config.description
  location                  = var.bigquery_dataset_config.location
  default_table_expiration_ms = var.bigquery_dataset_config.default_table_expiration_ms
  delete_contents_on_destroy = var.bigquery_dataset_config.delete_contents_on_destroy

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# BigQuery Table for Load Balancer Metrics
resource "google_bigquery_table" "lb_metrics" {
  dataset_id = google_bigquery_dataset.traffic_analytics.dataset_id
  table_id   = "lb_metrics"

  description = "Load balancer metrics for intelligent routing analysis"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Request timestamp"
    },
    {
      name = "request_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique request identifier"
    },
    {
      name = "source_ip"
      type = "STRING"
      mode = "NULLABLE"
      description = "Source IP address"
    },
    {
      name = "target_service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Target service name"
    },
    {
      name = "response_time"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Response time in seconds"
    },
    {
      name = "status_code"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "HTTP status code"
    },
    {
      name = "user_agent"
      type = "STRING"
      mode = "NULLABLE"
      description = "User agent string"
    },
    {
      name = "request_size"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Request size in bytes"
    },
    {
      name = "response_size"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Response size in bytes"
    }
  ])

  labels = local.common_labels
}

# BigQuery Table for Routing Decisions
resource "google_bigquery_table" "routing_decisions" {
  dataset_id = google_bigquery_dataset.traffic_analytics.dataset_id
  table_id   = "routing_decisions"

  description = "AI-driven routing decisions and reasoning"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Decision timestamp"
    },
    {
      name = "decision_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique decision identifier"
    },
    {
      name = "source_criteria"
      type = "STRING"
      mode = "NULLABLE"
      description = "Source criteria for routing decision"
    },
    {
      name = "target_service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Selected target service"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "AI confidence score (0.0-1.0)"
    },
    {
      name = "ai_reasoning"
      type = "STRING"
      mode = "NULLABLE"
      description = "AI reasoning for the decision"
    }
  ])

  labels = local.common_labels
}

# Cloud Run Service A (Fast Response)
resource "google_cloud_run_service" "service_a" {
  name     = "${var.resource_name_prefix}-service-a-${local.name_suffix}"
  location = var.region

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.cloud_run_services.service_a.max_instances
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }

    spec {
      containers {
        image = var.cloud_run_services.service_a.image

        resources {
          limits = {
            memory = var.cloud_run_services.service_a.memory
            cpu    = var.cloud_run_services.service_a.cpu
          }
        }

        dynamic "env" {
          for_each = var.cloud_run_services.service_a.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        ports {
          container_port = 8080
        }
      }

      service_account_name = google_service_account.cloud_run_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Run Service B (Standard Response)
resource "google_cloud_run_service" "service_b" {
  name     = "${var.resource_name_prefix}-service-b-${local.name_suffix}"
  location = var.region

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.cloud_run_services.service_b.max_instances
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }

    spec {
      containers {
        image = var.cloud_run_services.service_b.image

        resources {
          limits = {
            memory = var.cloud_run_services.service_b.memory
            cpu    = var.cloud_run_services.service_b.cpu
          }
        }

        dynamic "env" {
          for_each = var.cloud_run_services.service_b.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        ports {
          container_port = 8080
        }
      }

      service_account_name = google_service_account.cloud_run_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Run Service C (Resource-Intensive)
resource "google_cloud_run_service" "service_c" {
  name     = "${var.resource_name_prefix}-service-c-${local.name_suffix}"
  location = var.region

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.cloud_run_services.service_c.max_instances
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }

    spec {
      containers {
        image = var.cloud_run_services.service_c.image

        resources {
          limits = {
            memory = var.cloud_run_services.service_c.memory
            cpu    = var.cloud_run_services.service_c.cpu
          }
        }

        dynamic "env" {
          for_each = var.cloud_run_services.service_c.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        ports {
          container_port = 8080
        }
      }

      service_account_name = google_service_account.cloud_run_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Run services
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.resource_name_prefix}-cr-sa-${local.name_suffix}"
  display_name = "Cloud Run Service Account for Intelligent Routing"
  description  = "Service account used by Cloud Run services"
}

# IAM binding for Cloud Run service account
resource "google_project_iam_member" "cloud_run_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# IAM policy for unauthenticated access to Cloud Run services
resource "google_cloud_run_service_iam_member" "service_a_noauth" {
  service  = google_cloud_run_service.service_a.name
  location = google_cloud_run_service.service_a.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "service_b_noauth" {
  service  = google_cloud_run_service.service_b.name
  location = google_cloud_run_service.service_b.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "service_c_noauth" {
  service  = google_cloud_run_service.service_c.name
  location = google_cloud_run_service.service_c.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Network Endpoint Groups for Cloud Run services
resource "google_compute_region_network_endpoint_group" "service_a_neg" {
  name                  = "${var.resource_name_prefix}-service-a-neg-${local.name_suffix}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.service_a.name
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_region_network_endpoint_group" "service_b_neg" {
  name                  = "${var.resource_name_prefix}-service-b-neg-${local.name_suffix}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.service_b.name
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_region_network_endpoint_group" "service_c_neg" {
  name                  = "${var.resource_name_prefix}-service-c-neg-${local.name_suffix}"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_service.service_c.name
  }

  depends_on = [google_project_service.required_apis]
}

# Health Check for Cloud Run services
resource "google_compute_health_check" "cloud_run_health_check" {
  name               = "${var.resource_name_prefix}-cr-health-check-${local.name_suffix}"
  check_interval_sec = var.load_balancer_config.health_check_interval
  timeout_sec        = var.load_balancer_config.health_check_timeout
  healthy_threshold  = var.load_balancer_config.health_check_healthy_threshold
  unhealthy_threshold = var.load_balancer_config.health_check_unhealthy_threshold

  http_health_check {
    port         = 8080
    request_path = var.load_balancer_config.health_check_path
  }

  depends_on = [google_project_service.required_apis]
}

# Backend Services for each Cloud Run service
resource "google_compute_backend_service" "service_a_backend" {
  name                  = "${var.resource_name_prefix}-service-a-backend-${local.name_suffix}"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.cloud_run_health_check.id]

  backend {
    group = google_compute_region_network_endpoint_group.service_a_neg.id
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_backend_service" "service_b_backend" {
  name                  = "${var.resource_name_prefix}-service-b-backend-${local.name_suffix}"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.cloud_run_health_check.id]

  backend {
    group = google_compute_region_network_endpoint_group.service_b_neg.id
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_backend_service" "service_c_backend" {
  name                  = "${var.resource_name_prefix}-service-c-backend-${local.name_suffix}"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.cloud_run_health_check.id]

  backend {
    group = google_compute_region_network_endpoint_group.service_c_neg.id
  }

  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_name_prefix}-fn-sa-${local.name_suffix}"
  display_name = "Traffic Router Function Service Account"
  description  = "Service account for traffic routing Cloud Function"
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "function_sa_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create source code for traffic routing function
resource "local_file" "function_source" {
  content = templatefile("${path.module}/templates/traffic_router_function.py.tpl", {
    project_id   = var.project_id
    dataset_name = google_bigquery_dataset.traffic_analytics.dataset_id
  })
  filename = "${path.module}/function_source/main.py"
}

resource "local_file" "function_requirements" {
  content = <<-EOF
functions-framework==3.*
google-cloud-bigquery==3.*
google-cloud-monitoring==2.*
google-cloud-logging==3.*
EOF
  filename = "${path.module}/function_source/requirements.txt"
}

# Archive function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function_source"
  output_path = "${path.module}/function_source.zip"
  depends_on  = [local_file.function_source, local_file.function_requirements]
}

# Cloud Storage bucket for function source
resource "google_storage_bucket" "function_source" {
  name                        = "${var.resource_name_prefix}-function-source-${local.name_suffix}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = local.common_labels
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "traffic-router-${local.name_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for traffic routing logic
resource "google_cloudfunctions_function" "traffic_router" {
  name        = "${var.resource_name_prefix}-traffic-router-${local.name_suffix}"
  description = "Intelligent traffic routing function with BigQuery analytics"
  runtime     = var.cloud_function_config.runtime
  region      = var.region

  available_memory_mb   = var.cloud_function_config.memory_mb
  timeout               = var.cloud_function_config.timeout_seconds
  max_instances         = var.cloud_function_config.max_instances
  ingress_settings      = var.cloud_function_config.ingress_settings
  entry_point           = "route_traffic"
  service_account_email = google_service_account.function_sa.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_OPTIONAL"
    }
  }

  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = google_bigquery_dataset.traffic_analytics.dataset_id
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_bigquery,
    google_project_iam_member.function_sa_monitoring,
    google_project_iam_member.function_sa_logging
  ]
}

# Service Extension for intelligent routing
resource "google_service_extensions_lb_traffic_extension" "intelligent_routing" {
  provider = google-beta
  
  name     = "${var.resource_name_prefix}-extension-${local.name_suffix}"
  location = var.region

  description = "Intelligent traffic routing with BigQuery analytics"

  forwarding_rules = [google_compute_global_forwarding_rule.default.id]

  extension_chains {
    name = "intelligent-routing-chain"

    match_condition {
      cel_expression = "true"  # Apply to all requests
    }

    extensions {
      name = "traffic-router"
      
      service = google_cloudfunctions_function.traffic_router.https_trigger_url
      
      timeout {
        seconds = var.service_extensions_config.callout_timeout_seconds
      }
      
      fail_open = var.service_extensions_config.failover_behavior == "CONTINUE"
    }
  }

  load_balancing_scheme = "EXTERNAL_MANAGED"

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.traffic_router
  ]
}

# URL Map with path-based routing
resource "google_compute_url_map" "intelligent_lb" {
  name            = "${var.resource_name_prefix}-intelligent-lb-${local.name_suffix}"
  default_service = google_compute_backend_service.service_a_backend.id

  path_matcher {
    name            = "intelligent-matcher"
    default_service = google_compute_backend_service.service_a_backend.id

    path_rule {
      paths   = ["/api/fast/*"]
      service = google_compute_backend_service.service_a_backend.id
    }

    path_rule {
      paths   = ["/api/standard/*"]
      service = google_compute_backend_service.service_b_backend.id
    }

    path_rule {
      paths   = ["/api/intensive/*"]
      service = google_compute_backend_service.service_c_backend.id
    }
  }

  host_rule {
    hosts        = ["*"]
    path_matcher = "intelligent-matcher"
  }

  depends_on = [google_project_service.required_apis]
}

# HTTP(S) Target Proxy
resource "google_compute_target_http_proxy" "intelligent_proxy" {
  name    = "${var.resource_name_prefix}-intelligent-proxy-${local.name_suffix}"
  url_map = google_compute_url_map.intelligent_lb.id

  depends_on = [google_project_service.required_apis]
}

# Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "default" {
  name       = "${var.resource_name_prefix}-lb-rule-${local.name_suffix}"
  target     = google_compute_target_http_proxy.intelligent_proxy.id
  port_range = "80"

  depends_on = [google_project_service.required_apis]
}

# Cloud Logging Sink for BigQuery export
resource "google_logging_project_sink" "traffic_analytics_sink" {
  name = "${var.resource_name_prefix}-traffic-analytics-sink-${local.name_suffix}"

  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.traffic_analytics.dataset_id}"

  filter = <<-EOT
    resource.type="gce_instance" OR 
    resource.type="cloud_run_revision" OR
    jsonPayload.source_ip!=""
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [google_project_service.required_apis]
}

# Grant BigQuery data editor role to the logging sink
resource "google_project_iam_member" "logging_sink_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.traffic_analytics_sink.writer_identity
}

# Service Account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  account_id   = "${var.resource_name_prefix}-wf-sa-${local.name_suffix}"
  display_name = "Workflow Service Account for Analytics Processing"
  description  = "Service account for Cloud Workflows analytics processing"
}

# IAM bindings for Workflow service account
resource "google_project_iam_member" "workflow_sa_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# Create workflow definition
resource "local_file" "workflow_definition" {
  content = templatefile("${path.module}/templates/analytics_workflow.yaml.tpl", {
    project_id   = var.project_id
    dataset_name = google_bigquery_dataset.traffic_analytics.dataset_id
  })
  filename = "${path.module}/workflow_definition.yaml"
}

# Cloud Workflow for automated analytics
resource "google_workflows_workflow" "analytics_processor" {
  name            = "${var.resource_name_prefix}-analytics-processor-${local.name_suffix}"
  region          = var.region
  description     = var.workflow_config.description
  service_account = google_service_account.workflow_sa.id
  source_contents = local_file.workflow_definition.content

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    local_file.workflow_definition
  ]
}