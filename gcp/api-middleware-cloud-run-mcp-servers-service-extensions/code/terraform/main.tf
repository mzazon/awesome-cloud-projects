# Main Terraform configuration for API Middleware with Cloud Run MCP Servers and Service Extensions
# This creates a complete AI-powered API middleware solution using Model Context Protocol (MCP)

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  resource_suffix = random_id.suffix.hex
  service_prefix  = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "mcp-middleware"
    created-by  = "terraform"
  })

  # MCP Server names
  mcp_services = {
    content_analyzer  = "${local.service_prefix}-content-analyzer"
    request_router    = "${local.service_prefix}-request-router"
    response_enhancer = "${local.service_prefix}-response-enhancer"
  }
  
  # Middleware service name
  middleware_service = "${local.service_prefix}-api-middleware"
  
  # Endpoints service name
  endpoints_service = "${local.service_prefix}-endpoints"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "endpoints.googleapis.com",
    "servicecontrol.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

# Create service account for Cloud Run services
resource "google_service_account" "mcp_service_account" {
  count = var.create_service_account ? 1 : 0
  
  account_id   = "${local.service_prefix}-sa"
  display_name = "MCP Middleware Service Account"
  description  = "Service account for MCP middleware Cloud Run services"
  project      = var.project_id

  depends_on = [time_sleep.wait_for_apis]
}

# Assign IAM roles to service account
resource "google_project_iam_member" "service_account_roles" {
  for_each = var.create_service_account ? toset(var.service_account_roles) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.mcp_service_account[0].email}"

  depends_on = [google_service_account.mcp_service_account]
}

# Cloud Run service for Content Analyzer MCP Server
resource "google_cloud_run_service" "content_analyzer" {
  name     = local.mcp_services.content_analyzer
  location = var.region
  project  = var.project_id

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/minScale"         = var.mcp_server_config.min_instances
        "autoscaling.knative.dev/maxScale"         = var.mcp_server_config.max_instances
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/ingress"               = var.ingress
      }
    }

    spec {
      container_concurrency = var.mcp_server_config.concurrency
      timeout_seconds       = var.mcp_server_config.timeout_seconds
      
      dynamic "service_account_name" {
        for_each = var.create_service_account ? [1] : []
        content {
          service_account_name = google_service_account.mcp_service_account[0].email
        }
      }

      containers {
        image = var.container_images.content_analyzer

        resources {
          limits = {
            memory = var.mcp_server_config.memory
            cpu    = var.mcp_server_config.cpu
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "REGION"
          value = var.region
        }

        env {
          name  = "VERTEX_AI_LOCATION"
          value = var.vertex_ai_location
        }

        env {
          name  = "GEMINI_MODEL"
          value = var.gemini_model
        }

        env {
          name  = "LOG_LEVEL"
          value = var.log_level
        }

        env {
          name  = "SERVICE_TYPE"
          value = "content-analyzer"
        }

        ports {
          container_port = 8080
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 60
          timeout_seconds       = 10
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 30
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    time_sleep.wait_for_apis,
    google_project_iam_member.service_account_roles
  ]

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }
}

# Cloud Run service for Request Router MCP Server
resource "google_cloud_run_service" "request_router" {
  name     = local.mcp_services.request_router
  location = var.region
  project  = var.project_id

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/minScale"         = var.mcp_server_config.min_instances
        "autoscaling.knative.dev/maxScale"         = var.mcp_server_config.max_instances
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/ingress"               = var.ingress
      }
    }

    spec {
      container_concurrency = var.mcp_server_config.concurrency
      timeout_seconds       = var.mcp_server_config.timeout_seconds
      
      dynamic "service_account_name" {
        for_each = var.create_service_account ? [1] : []
        content {
          service_account_name = google_service_account.mcp_service_account[0].email
        }
      }

      containers {
        image = var.container_images.request_router

        resources {
          limits = {
            memory = var.mcp_server_config.memory
            cpu    = var.mcp_server_config.cpu
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "REGION"
          value = var.region
        }

        env {
          name  = "LOG_LEVEL"
          value = var.log_level
        }

        env {
          name  = "SERVICE_TYPE"
          value = "request-router"
        }

        ports {
          container_port = 8080
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 60
          timeout_seconds       = 10
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 30
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    time_sleep.wait_for_apis,
    google_project_iam_member.service_account_roles
  ]

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }
}

# Cloud Run service for Response Enhancer MCP Server
resource "google_cloud_run_service" "response_enhancer" {
  name     = local.mcp_services.response_enhancer
  location = var.region
  project  = var.project_id

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/minScale"         = var.mcp_server_config.min_instances
        "autoscaling.knative.dev/maxScale"         = var.mcp_server_config.max_instances
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/ingress"               = var.ingress
      }
    }

    spec {
      container_concurrency = var.mcp_server_config.concurrency
      timeout_seconds       = var.mcp_server_config.timeout_seconds
      
      dynamic "service_account_name" {
        for_each = var.create_service_account ? [1] : []
        content {
          service_account_name = google_service_account.mcp_service_account[0].email
        }
      }

      containers {
        image = var.container_images.response_enhancer

        resources {
          limits = {
            memory = var.mcp_server_config.memory
            cpu    = var.mcp_server_config.cpu
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "REGION"
          value = var.region
        }

        env {
          name  = "VERTEX_AI_LOCATION"
          value = var.vertex_ai_location
        }

        env {
          name  = "GEMINI_MODEL"
          value = var.gemini_model
        }

        env {
          name  = "LOG_LEVEL"
          value = var.log_level
        }

        env {
          name  = "SERVICE_TYPE"
          value = "response-enhancer"
        }

        ports {
          container_port = 8080
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 60
          timeout_seconds       = 10
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 30
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    time_sleep.wait_for_apis,
    google_project_iam_member.service_account_roles
  ]

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }
}

# Cloud Run service for Main API Middleware
resource "google_cloud_run_service" "api_middleware" {
  name     = local.middleware_service
  location = var.region
  project  = var.project_id

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/minScale"         = var.middleware_config.min_instances
        "autoscaling.knative.dev/maxScale"         = var.middleware_config.max_instances
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/ingress"               = var.ingress
      }
    }

    spec {
      container_concurrency = var.middleware_config.concurrency
      timeout_seconds       = var.middleware_config.timeout_seconds
      
      dynamic "service_account_name" {
        for_each = var.create_service_account ? [1] : []
        content {
          service_account_name = google_service_account.mcp_service_account[0].email
        }
      }

      containers {
        image = var.container_images.api_middleware

        resources {
          limits = {
            memory = var.middleware_config.memory
            cpu    = var.middleware_config.cpu
          }
        }

        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "REGION"
          value = var.region
        }

        env {
          name  = "CONTENT_ANALYZER_URL"
          value = google_cloud_run_service.content_analyzer.status[0].url
        }

        env {
          name  = "REQUEST_ROUTER_URL"
          value = google_cloud_run_service.request_router.status[0].url
        }

        env {
          name  = "RESPONSE_ENHANCER_URL"
          value = google_cloud_run_service.response_enhancer.status[0].url
        }

        env {
          name  = "LOG_LEVEL"
          value = var.log_level
        }

        env {
          name  = "SERVICE_TYPE"
          value = "api-middleware"
        }

        ports {
          container_port = 8080
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 30
          period_seconds        = 60
          timeout_seconds       = 10
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path = "/health"
            port = 8080
          }
          initial_delay_seconds = 10
          period_seconds        = 10
          timeout_seconds       = 5
          failure_threshold     = 30
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_cloud_run_service.content_analyzer,
    google_cloud_run_service.request_router,
    google_cloud_run_service.response_enhancer,
    google_project_iam_member.service_account_roles
  ]

  lifecycle {
    ignore_changes = [
      template[0].metadata[0].annotations["run.googleapis.com/operation-id"],
      template[0].metadata[0].annotations["client.knative.dev/user-image"],
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }
}

# IAM policy for Cloud Run services (allow unauthenticated access)
resource "google_cloud_run_service_iam_policy" "content_analyzer_policy" {
  count = var.mcp_server_config.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_service.content_analyzer.location
  project  = google_cloud_run_service.content_analyzer.project
  service  = google_cloud_run_service.content_analyzer.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_service_iam_policy" "request_router_policy" {
  count = var.mcp_server_config.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_service.request_router.location
  project  = google_cloud_run_service.request_router.project
  service  = google_cloud_run_service.request_router.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_service_iam_policy" "response_enhancer_policy" {
  count = var.mcp_server_config.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_service.response_enhancer.location
  project  = google_cloud_run_service.response_enhancer.project
  service  = google_cloud_run_service.response_enhancer.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_service_iam_policy" "api_middleware_policy" {
  count = var.middleware_config.allow_unauthenticated ? 1 : 0
  
  location = google_cloud_run_service.api_middleware.location
  project  = google_cloud_run_service.api_middleware.project
  service  = google_cloud_run_service.api_middleware.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# Data source for no-auth IAM policy
data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Create OpenAPI specification for Cloud Endpoints
resource "google_endpoints_service" "api_gateway" {
  service_name   = "${local.endpoints_service}.endpoints.${var.project_id}.cloud.goog"
  project        = var.project_id
  
  openapi_config = templatefile("${path.module}/openapi.yaml.tpl", {
    service_name    = "${local.endpoints_service}.endpoints.${var.project_id}.cloud.goog"
    title           = var.endpoints_config.title
    description     = var.endpoints_config.description
    version         = var.endpoints_config.version
    backend_address = google_cloud_run_service.api_middleware.status[0].url
  })

  depends_on = [
    google_cloud_run_service.api_middleware,
    time_sleep.wait_for_apis
  ]
}

# OpenAPI specification template
resource "local_file" "openapi_template" {
  filename = "${path.module}/openapi.yaml.tpl"
  content = <<EOF
swagger: '2.0'
info:
  title: $${title}
  description: $${description}
  version: $${version}
host: $${service_name}
schemes:
  - https
produces:
  - application/json
paths:
  /{proxy+}:
    x-google-backend:
      address: $${backend_address}
      path_translation: APPEND_PATH_TO_ADDRESS
    get:
      summary: Intelligent GET requests through MCP servers
      operationId: intelligentGet
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
      responses:
        200:
          description: Successful response with AI enhancement
          schema:
            type: object
            properties:
              status:
                type: string
              data:
                type: object
              middleware_metadata:
                type: object
                properties:
                  processing_chain:
                    type: array
                    items:
                      type: string
                  mcp_servers_used:
                    type: integer
                  enhancements_applied:
                    type: array
                    items:
                      type: string
        500:
          description: Middleware processing error
    post:
      summary: Intelligent POST requests through MCP servers
      operationId: intelligentPost
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
        - name: body
          in: body
          schema:
            type: object
      responses:
        200:
          description: Successful response with AI enhancement
          schema:
            type: object
        500:
          description: Middleware processing error
    put:
      summary: Intelligent PUT requests through MCP servers
      operationId: intelligentPut
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
        - name: body
          in: body
          schema:
            type: object
      responses:
        200:
          description: Successful response with AI enhancement
        500:
          description: Middleware processing error
    delete:
      summary: Intelligent DELETE requests through MCP servers
      operationId: intelligentDelete
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
      responses:
        200:
          description: Successful response with AI enhancement
        500:
          description: Middleware processing error
    patch:
      summary: Intelligent PATCH requests through MCP servers
      operationId: intelligentPatch
      parameters:
        - name: proxy
          in: path
          required: true
          type: string
        - name: body
          in: body
          schema:
            type: object
      responses:
        200:
          description: Successful response with AI enhancement
        500:
          description: Middleware processing error
  /health:
    get:
      summary: Health check endpoint
      operationId: healthCheck
      responses:
        200:
          description: Service is healthy
          schema:
            type: object
            properties:
              status:
                type: string
              mcp_servers:
                type: object
EOF
}

# Wait for endpoint service to be fully deployed
resource "time_sleep" "wait_for_endpoints" {
  depends_on = [google_endpoints_service.api_gateway]
  create_duration = "30s"
}