# =============================================================================
# INTELLIGENT BUSINESS PROCESS AUTOMATION WITH ADK AND WORKFLOWS
# =============================================================================
# This Terraform configuration deploys a complete intelligent business process 
# automation solution using Vertex AI Agent Development Kit, Cloud Workflows,
# Cloud SQL, and Cloud Functions for natural language processing and workflow
# orchestration.
# =============================================================================

# Generate random suffix for resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Resource naming with random suffix
  suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Consistent resource naming
  db_instance_name          = "business-process-db-${local.suffix}"
  workflow_name            = "business-process-workflow-${local.suffix}"
  approval_function_name   = "process-approval-${local.suffix}"
  notification_function_name = "process-notification-${local.suffix}" 
  agent_function_name      = "bpa-agent-${local.suffix}"
  
  # Workflow location defaults to region if not specified
  workflow_location = var.workflow_location != "" ? var.workflow_location : var.region
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    managed-by = "terraform"
    suffix     = local.suffix
  })
}

# =============================================================================
# API ENABLEMENT
# =============================================================================
# Enable required Google Cloud APIs for the business process automation solution

resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent APIs from being disabled when the resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================
# Configure private services access for secure Cloud SQL connectivity

# Reserve IP range for private services access
resource "google_compute_global_address" "private_services_range" {
  count = var.enable_private_services ? 1 : 0
  
  name          = "bpa-private-services-${local.suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "default"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create private connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  count = var.enable_private_services ? 1 : 0
  
  network                 = "default"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_range[0].name]
  
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD SQL DATABASE INSTANCE
# =============================================================================
# Managed PostgreSQL database for business process state and audit trails

resource "google_sql_database_instance" "business_process_db" {
  name             = local.db_instance_name
  database_version = var.db_version
  region           = var.region
  
  # Prevent accidental deletion in production
  deletion_protection = var.enable_deletion_protection
  
  settings {
    tier              = var.db_tier
    availability_type = "ZONAL" # Use REGIONAL for high availability in production
    disk_type         = "PD_SSD"
    disk_size         = 20
    disk_autoresize   = true
    
    # Enhanced security and performance settings
    backup_configuration {
      enabled                        = var.enable_backup
      start_time                     = var.backup_start_time
      location                       = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration for private connectivity
    dynamic "ip_configuration" {
      for_each = var.enable_private_services ? [1] : []
      content {
        ipv4_enabled                                  = false
        private_network                               = "projects/${var.project_id}/global/networks/default"
        enable_private_path_for_google_cloud_services = true
        require_ssl                                   = true
      }
    }
    
    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 2  # 2 AM
      update_track = "stable"
    }
    
    # Database flags for optimization
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000" # Log queries taking more than 1 second
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Create application database
resource "google_sql_database" "business_processes_db" {
  name     = "business_processes"
  instance = google_sql_database_instance.business_process_db.name
}

# Generate random password for database user
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Set database user password
resource "google_sql_user" "postgres_user" {
  name     = "postgres"
  instance = google_sql_database_instance.business_process_db.name
  password = random_password.db_password.result
}

# =============================================================================
# CLOUD FUNCTIONS FOR BUSINESS LOGIC
# =============================================================================
# Serverless functions for approval processing, notifications, and AI agent

# Create source bucket for Cloud Functions
resource "google_storage_bucket" "function_source" {
  name     = "bpa-function-source-${local.suffix}"
  location = var.region
  
  # Prevent public access
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
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Approval function source code
data "archive_file" "approval_function_source" {
  type        = "zip"
  output_path = "/tmp/approval-function-${local.suffix}.zip"
  
  source {
    content = templatefile("${path.module}/functions/approval/main.py", {
      project_id  = var.project_id
      region      = var.region
      db_instance = local.db_instance_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/approval/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload approval function source to bucket
resource "google_storage_bucket_object" "approval_function_source" {
  name   = "approval-function-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.approval_function_source.output_path
}

# Process Approval Cloud Function
resource "google_cloudfunctions2_function" "approval_function" {
  name        = local.approval_function_name
  location    = var.region
  description = "Processes business process approval decisions with database integration"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "approve_process"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.approval_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    
    # Environment variables for database connectivity
    environment_variables = {
      DB_PASSWORD  = random_password.db_password.result
      PROJECT_ID   = var.project_id
      REGION       = var.region
      DB_INSTANCE  = local.db_instance_name
    }
    
    # VPC connector for private SQL access
    dynamic "vpc_connector" {
      for_each = var.enable_private_services ? [1] : []
      content {
        name = "projects/${var.project_id}/locations/${var.region}/connectors/default"
      }
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.business_process_db,
    google_storage_bucket_object.approval_function_source
  ]
}

# Notification function source code
data "archive_file" "notification_function_source" {
  type        = "zip"
  output_path = "/tmp/notification-function-${local.suffix}.zip"
  
  source {
    content = templatefile("${path.module}/functions/notification/main.py", {
      project_id  = var.project_id
      region      = var.region
      db_instance = local.db_instance_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/notification/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload notification function source to bucket
resource "google_storage_bucket_object" "notification_function_source" {
  name   = "notification-function-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.notification_function_source.output_path
}

# Process Notification Cloud Function
resource "google_cloudfunctions2_function" "notification_function" {
  name        = local.notification_function_name
  location    = var.region
  description = "Sends process notifications to stakeholders with audit logging"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "send_notification"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.notification_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    
    # Environment variables for database connectivity
    environment_variables = {
      DB_PASSWORD  = random_password.db_password.result
      PROJECT_ID   = var.project_id
      REGION       = var.region
      DB_INSTANCE  = local.db_instance_name
    }
    
    # VPC connector for private SQL access
    dynamic "vpc_connector" {
      for_each = var.enable_private_services ? [1] : []
      content {
        name = "projects/${var.project_id}/locations/${var.region}/connectors/default"
      }
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.business_process_db,
    google_storage_bucket_object.notification_function_source
  ]
}

# AI Agent function source code (simulates Vertex AI ADK capabilities)
data "archive_file" "agent_function_source" {
  type        = "zip"
  output_path = "/tmp/agent-function-${local.suffix}.zip"
  
  source {
    content = templatefile("${path.module}/functions/agent/main.py", {
      project_id  = var.project_id
      region      = var.region
      db_instance = local.db_instance_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/agent/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload agent function source to bucket
resource "google_storage_bucket_object" "agent_function_source" {
  name   = "agent-function-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.agent_function_source.output_path
}

# AI Agent Cloud Function for Natural Language Processing
resource "google_cloudfunctions2_function" "agent_function" {
  name        = local.agent_function_name
  location    = var.region
  description = "AI agent for natural language business process request processing"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "process_natural_language"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.agent_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    
    # Environment variables for database connectivity
    environment_variables = {
      DB_PASSWORD  = random_password.db_password.result
      PROJECT_ID   = var.project_id
      REGION       = var.region
      DB_INSTANCE  = local.db_instance_name
    }
    
    # VPC connector for private SQL access
    dynamic "vpc_connector" {
      for_each = var.enable_private_services ? [1] : []
      content {
        name = "projects/${var.project_id}/locations/${var.region}/connectors/default"
      }
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.business_process_db,
    google_storage_bucket_object.agent_function_source
  ]
}

# =============================================================================
# CLOUD WORKFLOWS FOR ORCHESTRATION
# =============================================================================
# Intelligent workflow orchestration with conditional logic and error handling

# Cloud Workflow for business process automation
resource "google_workflows_workflow" "business_process_workflow" {
  name            = local.workflow_name
  region          = local.workflow_location
  description     = "Intelligent business process automation with conditional routing"
  service_account = google_service_account.workflow_sa.email
  
  source_contents = templatefile("${path.module}/workflows/business-process-workflow.yaml", {
    approval_function_url    = google_cloudfunctions2_function.approval_function.service_config[0].uri
    notification_function_url = google_cloudfunctions2_function.notification_function.service_config[0].uri
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.approval_function,
    google_cloudfunctions2_function.notification_function
  ]
}

# =============================================================================
# IAM SERVICE ACCOUNTS AND PERMISSIONS
# =============================================================================
# Service accounts with least privilege access for secure operations

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "bpa-functions-sa-${local.suffix}"
  display_name = "Business Process Automation Functions Service Account"
  description  = "Service account for Cloud Functions with Cloud SQL access"
}

# Service account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  account_id   = "bpa-workflow-sa-${local.suffix}"
  display_name = "Business Process Automation Workflow Service Account" 
  description  = "Service account for Cloud Workflows with function invocation access"
}

# Grant Cloud SQL Client role to function service account
resource "google_project_iam_member" "function_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud SQL Editor role to function service account for database operations
resource "google_project_iam_member" "function_sql_editor" {
  project = var.project_id
  role    = "roles/cloudsql.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Logging Write role to function service account
resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Functions Invoker role to workflow service account
resource "google_project_iam_member" "workflow_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# Grant Workflows Editor role to workflow service account
resource "google_project_iam_member" "workflow_editor" {
  project = var.project_id
  role    = "roles/workflows.editor"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# Grant Logging Write role to workflow service account
resource "google_project_iam_member" "workflow_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================
# Cloud Monitoring dashboards and alerts for system observability

# Monitoring notification channel (email)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "BPA Email Notifications"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com" # Replace with actual email
  }
  
  description = "Email notifications for business process automation system"
}

# Alert policy for Cloud SQL instance health
resource "google_monitoring_alert_policy" "sql_instance_health" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Cloud SQL Instance Health - ${local.db_instance_name}"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud SQL Instance Down"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${local.db_instance_name}\""
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_notification[0].name]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}

# Alert policy for Cloud Functions errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Cloud Functions Error Rate - BPA Functions"
  combiner     = "OR"
  
  conditions {
    display_name = "High Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${local.approval_function_name}|${local.notification_function_name}|${local.agent_function_name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate
      duration        = "300s"
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.labels.function_name"]
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_notification[0].name]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================
# Security policies and configurations for data protection

# Cloud Armor security policy (optional, for future web interface)
resource "google_compute_security_policy" "bpa_security_policy" {
  name        = "bpa-security-policy-${local.suffix}"
  description = "Security policy for business process automation web interfaces"
  
  # Block known malicious IPs
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["192.0.2.0/24"] # Example blocked range
      }
    }
    description = "Block known malicious IP ranges"
  }
  
  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Rate limiting for API protection"
  }
  
  # Default allow rule
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}