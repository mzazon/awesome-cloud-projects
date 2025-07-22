# GPU-Accelerated Multi-Agent AI Systems with Cloud Run and Vertex AI Agent Engine
# This configuration deploys a scalable multi-agent AI system using Google Cloud's 
# serverless GPU capabilities through Cloud Run combined with Vertex AI Agent Engine

# Configure Terraform and required providers
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure Google Cloud providers
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Create unique resource names with random suffix
  redis_instance_name     = "${var.redis_instance_name}-${random_id.suffix.hex}"
  pubsub_topic_name      = "${var.pubsub_topic_name}-${random_id.suffix.hex}"
  vision_agent_name      = "${var.vision_agent_name}-${random_id.suffix.hex}"
  language_agent_name    = "${var.language_agent_name}-${random_id.suffix.hex}"
  reasoning_agent_name   = "${var.reasoning_agent_name}-${random_id.suffix.hex}"
  tool_agent_name        = "${var.tool_agent_name}-${random_id.suffix.hex}"
  artifact_registry_repo = "${var.artifact_registry_repo}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    component   = "multi-agent-ai"
    managed-by  = "terraform"
    project     = var.project_id
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "redis.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Artifact Registry repository for agent container images
resource "google_artifact_registry_repository" "agent_images" {
  depends_on = [google_project_service.required_apis]

  location      = var.region
  repository_id = local.artifact_registry_repo
  description   = "Multi-agent AI system container images"
  format        = "DOCKER"

  labels = local.common_labels
}

# Create VPC network for secure communication between services
resource "google_compute_network" "agent_network" {
  depends_on = [google_project_service.required_apis]

  name                    = "${var.network_name}-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  description             = "VPC network for multi-agent AI system"
}

# Create subnet for the agent network
resource "google_compute_subnetwork" "agent_subnet" {
  name          = "${var.subnet_name}-${random_id.suffix.hex}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.agent_network.id
  description   = "Subnet for multi-agent AI system resources"

  # Enable private Google access for secure communication
  private_ip_google_access = true
}

# Create Cloud Memorystore Redis instance for shared state management
module "redis_cache" {
  source  = "terraform-google-modules/memorystore/google"
  version = "~> 15.1"

  depends_on = [google_project_service.required_apis]

  project_id = var.project_id
  region     = var.region

  name            = local.redis_instance_name
  memory_size_gb  = var.redis_memory_size_gb
  tier            = var.redis_tier
  redis_version   = var.redis_version
  display_name    = "AI Agent State Cache"
  
  # Security configuration
  auth_enabled               = true
  transit_encryption_mode    = "SERVER_CLIENT"
  connect_mode              = "PRIVATE_SERVICE_ACCESS"
  
  # Network configuration
  authorized_network = google_compute_network.agent_network.id
  
  # Performance optimization for AI workloads
  redis_configs = {
    maxmemory-policy = "allkeys-lru"
    timeout          = "300"
    maxclients       = "1000"
  }

  labels = merge(local.common_labels, {
    component = "redis-cache"
  })
}

# Create Pub/Sub topic and subscriptions for agent coordination
module "agent_pubsub" {
  source  = "terraform-google-modules/pubsub/google"
  version = "~> 8.2"

  depends_on = [google_project_service.required_apis]

  project_id = var.project_id
  topic      = local.pubsub_topic_name

  # Configure message ordering and delivery guarantees
  topic_message_retention_duration = "86400s" # 24 hours
  
  pull_subscriptions = [
    {
      name                         = "master-agent-subscription"
      ack_deadline_seconds         = 30
      enable_exactly_once_delivery = true
      enable_message_ordering      = true
      message_retention_duration   = "86400s"
      retain_acked_messages       = false
      max_delivery_attempts       = 5
    },
    {
      name                         = "worker-agents-subscription"
      ack_deadline_seconds         = 60
      enable_exactly_once_delivery = true
      enable_message_ordering      = false
      message_retention_duration   = "86400s"
      retain_acked_messages       = false
      max_delivery_attempts       = 3
    }
  ]

  topic_labels = merge(local.common_labels, {
    component = "agent-communication"
    purpose   = "multi-agent-coordination"
  })
}

# Create service account for Cloud Run services
resource "google_service_account" "cloud_run_service_account" {
  depends_on = [google_project_service.required_apis]

  account_id   = "multi-agent-cloud-run-sa"
  display_name = "Multi-Agent AI Cloud Run Service Account"
  description  = "Service account for Cloud Run services in multi-agent AI system"
}

# Grant necessary IAM permissions to the service account
resource "google_project_iam_member" "cloud_run_permissions" {
  for_each = toset([
    "roles/aiplatform.user",           # Vertex AI access
    "roles/redis.editor",              # Redis access
    "roles/pubsub.editor",             # Pub/Sub access
    "roles/monitoring.metricWriter",   # Monitoring metrics
    "roles/logging.logWriter",         # Cloud Logging
    "roles/cloudtrace.agent",          # Cloud Trace
    "roles/storage.objectViewer"       # Storage access for models
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
}

# Vision Agent - GPU-accelerated image and video processing
resource "google_cloud_run_v2_service" "vision_agent" {
  depends_on = [
    google_project_service.required_apis,
    google_service_account.cloud_run_service_account
  ]

  name     = local.vision_agent_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_service_account.email
    
    # Configure GPU resources for vision processing
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}/vision-agent:${var.container_image_tag}"
      
      # GPU and memory configuration
      resources {
        limits = {
          "cpu"            = "4"
          "memory"         = "16Gi"
          "nvidia.com/gpu" = "1"
        }
        startup_cpu_boost = true
      }

      # Environment variables for agent configuration
      env {
        name  = "REDIS_HOST"
        value = module.redis_cache.host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(module.redis_cache.port)
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = module.agent_pubsub.topic
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }

      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    # GPU-specific annotations
    annotations = {
      "run.googleapis.com/gpu-type" = var.gpu_type
      "run.googleapis.com/gpu"      = "1"
    }

    # Scaling configuration
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances_gpu
    }

    # VPC connector for secure communication
    vpc_access {
      network_interfaces {
        network    = google_compute_network.agent_network.name
        subnetwork = google_compute_subnetwork.agent_subnet.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  labels = merge(local.common_labels, {
    component = "vision-agent"
    gpu       = "enabled"
  })
}

# Language Agent - GPU-accelerated natural language processing
resource "google_cloud_run_v2_service" "language_agent" {
  depends_on = [
    google_project_service.required_apis,
    google_service_account.cloud_run_service_account
  ]

  name     = local.language_agent_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_service_account.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}/language-agent:${var.container_image_tag}"
      
      resources {
        limits = {
          "cpu"            = "4"
          "memory"         = "16Gi"
          "nvidia.com/gpu" = "1"
        }
        startup_cpu_boost = true
      }

      env {
        name  = "REDIS_HOST"
        value = module.redis_cache.host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(module.redis_cache.port)
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = module.agent_pubsub.topic
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    annotations = {
      "run.googleapis.com/gpu-type" = var.gpu_type
      "run.googleapis.com/gpu"      = "1"
    }

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances_gpu
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.agent_network.name
        subnetwork = google_compute_subnetwork.agent_subnet.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  labels = merge(local.common_labels, {
    component = "language-agent"
    gpu       = "enabled"
  })
}

# Reasoning Agent - GPU-accelerated complex reasoning and inference
resource "google_cloud_run_v2_service" "reasoning_agent" {
  depends_on = [
    google_project_service.required_apis,
    google_service_account.cloud_run_service_account
  ]

  name     = local.reasoning_agent_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_service_account.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}/reasoning-agent:${var.container_image_tag}"
      
      resources {
        limits = {
          "cpu"            = "4"
          "memory"         = "16Gi"
          "nvidia.com/gpu" = "1"
        }
        startup_cpu_boost = true
      }

      env {
        name  = "REDIS_HOST"
        value = module.redis_cache.host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(module.redis_cache.port)
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = module.agent_pubsub.topic
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    annotations = {
      "run.googleapis.com/gpu-type" = var.gpu_type
      "run.googleapis.com/gpu"      = "1"
    }

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances_gpu
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.agent_network.name
        subnetwork = google_compute_subnetwork.agent_subnet.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  labels = merge(local.common_labels, {
    component = "reasoning-agent"
    gpu       = "enabled"
  })
}

# Tool Agent - CPU-only for external integrations and utility functions
resource "google_cloud_run_v2_service" "tool_agent" {
  depends_on = [
    google_project_service.required_apis,
    google_service_account.cloud_run_service_account
  ]

  name     = local.tool_agent_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_service_account.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent_images.repository_id}/tool-agent:${var.container_image_tag}"
      
      # CPU-only configuration for utility functions
      resources {
        limits = {
          "cpu"    = "2"
          "memory" = "4Gi"
        }
        startup_cpu_boost = true
      }

      env {
        name  = "REDIS_HOST"
        value = module.redis_cache.host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(module.redis_cache.port)
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = module.agent_pubsub.topic
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances_cpu
    }

    vpc_access {
      network_interfaces {
        network    = google_compute_network.agent_network.name
        subnetwork = google_compute_subnetwork.agent_subnet.name
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  labels = merge(local.common_labels, {
    component = "tool-agent"
    gpu       = "disabled"
  })
}

# Create monitoring dashboard for the multi-agent system
resource "google_monitoring_dashboard" "ai_system_dashboard" {
  depends_on = [google_project_service.required_apis]

  dashboard_json = jsonencode({
    displayName = "Multi-Agent AI System Dashboard"
    
    gridLayout = {
      columns = 12
      widgets = [
        {
          title = "Cloud Run Service Health"
          xPos = 0
          yPos = 0
          width = 6
          height = 4
          scorecard = {
            timeSeries = {
              filter = "resource.type=\"cloud_run_revision\" resource.label.service_name=~\".*agent.*\""
              aggregation = {
                perSeriesAligner = "ALIGN_RATE"
                crossSeriesReducer = "REDUCE_SUM"
                groupByFields = ["resource.label.service_name"]
              }
            }
            sparkChartView = {
              sparkChartType = "SPARK_LINE"
            }
          }
        },
        {
          title = "GPU Utilization"
          xPos = 6
          yPos = 0
          width = 6
          height = 4
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" metric.type=\"run.googleapis.com/container/gpu/utilization\""
                  aggregation = {
                    perSeriesAligner = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_MEAN"
                    groupByFields = ["resource.label.service_name"]
                  }
                }
              }
              plotType = "LINE"
            }]
            yAxis = {
              label = "GPU Utilization %"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Agent Response Times"
          xPos = 0
          yPos = 4
          width = 12
          height = 4
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" metric.type=\"run.googleapis.com/request_latencies\""
                  aggregation = {
                    perSeriesAligner = "ALIGN_DELTA"
                    crossSeriesReducer = "REDUCE_PERCENTILE_95"
                    groupByFields = ["resource.label.service_name"]
                  }
                }
              }
              plotType = "LINE"
            }]
            yAxis = {
              label = "Latency (ms)"
              scale = "LINEAR"
            }
          }
        }
      ]
    }
  })
}

# Create log-based metrics for agent performance tracking
resource "google_logging_metric" "agent_response_time" {
  depends_on = [google_project_service.required_apis]

  name   = "agent_response_time"
  filter = "resource.type=\"cloud_run_revision\" jsonPayload.processing_time>0"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "s"
    display_name = "Agent Response Time"
  }

  value_extractor = "EXTRACT(jsonPayload.processing_time)"

  label_extractors = {
    service_name = "EXTRACT(resource.labels.service_name)"
    agent_type   = "EXTRACT(jsonPayload.agent_type)"
  }
}

# Create alerting policy for high GPU costs
resource "google_monitoring_alert_policy" "high_gpu_cost_alert" {
  depends_on = [google_project_service.required_apis]

  display_name = "High GPU Cost Alert - Multi-Agent AI System"
  
  conditions {
    display_name = "GPU cost threshold exceeded"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" resource.label.service_name=~\".*agent.*\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.cost_alert_threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "GPU costs for the multi-agent AI system have exceeded the configured threshold. Consider reviewing scaling policies or instance configurations."
    mime_type = "text/markdown"
  }

  enabled = var.enable_cost_alerts
}