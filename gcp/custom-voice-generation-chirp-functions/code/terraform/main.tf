# Custom Voice Generation with Chirp 3 and Functions - Main Infrastructure
# This file contains the core infrastructure for the voice synthesis system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names with provided suffixes or random suffix
  bucket_name    = var.bucket_name_suffix != "" ? "voice-audio-${var.bucket_name_suffix}" : "voice-audio-${random_id.suffix.hex}"
  db_instance    = var.db_instance_name_suffix != "" ? "voice-profiles-${var.db_instance_name_suffix}" : "voice-profiles-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    recipe      = "custom-voice-generation-chirp-functions"
  })
  
  # Required Google Cloud APIs
  required_apis = [
    "texttospeech.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "sqladmin.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : []
  
  project = var.project_id
  service = each.key
  
  # Prevent disabling APIs on destroy to avoid breaking dependencies
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Generate secure random password for Cloud SQL
resource "random_password" "db_password" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Cloud Storage bucket for audio files
resource "google_storage_bucket" "voice_audio" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for audio file protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                        = lifecycle_rule.value.condition.age
        created_before             = lifecycle_rule.value.condition.created_before
        with_state                 = lifecycle_rule.value.condition.with_state
        matches_storage_class      = lifecycle_rule.value.condition.matches_storage_class
        num_newer_versions         = lifecycle_rule.value.condition.num_newer_versions
        custom_time_before         = lifecycle_rule.value.condition.custom_time_before
        days_since_custom_time     = lifecycle_rule.value.condition.days_since_custom_time
        days_since_noncurrent_time = lifecycle_rule.value.condition.days_since_noncurrent_time
        noncurrent_time_before     = lifecycle_rule.value.condition.noncurrent_time_before
      }
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create directory structure in the bucket using null resources
resource "google_storage_bucket_object" "samples_folder" {
  name   = "samples/.keep"
  bucket = google_storage_bucket.voice_audio.name
  content = "This file maintains the samples directory structure"
}

resource "google_storage_bucket_object" "generated_folder" {
  name   = "generated/.keep"
  bucket = google_storage_bucket.voice_audio.name
  content = "This file maintains the generated directory structure"
}

# Cloud SQL PostgreSQL instance for voice profile metadata
resource "google_sql_database_instance" "voice_profiles" {
  name                = local.db_instance
  database_version    = "POSTGRES_15"
  region              = var.region
  deletion_protection = var.deletion_protection
  
  settings {
    tier                        = var.db_tier
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.db_storage_size
    disk_autoresize             = true
    disk_autoresize_limit       = 0
    
    # Backup configuration
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
    
    # IP configuration with private IP
    ip_configuration {
      ipv4_enabled    = true
      private_network = null
      require_ssl     = false
      
      # Authorized networks for access
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Database flags for performance and logging
    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
    
    # Maintenance window
    maintenance_window {
      day  = 7  # Sunday
      hour = 3  # 3 AM
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [google_project_service.apis]
}

# Set password for the default postgres user
resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.voice_profiles.name
  password = random_password.db_password.result
}

# Create the voice_profiles database
resource "google_sql_database" "voice_profiles" {
  name     = "voice_profiles"
  instance = google_sql_database_instance.voice_profiles.name
}

# Service account for Cloud Functions with enhanced security
resource "google_service_account" "voice_synthesis" {
  account_id   = "voice-synthesis-sa-${random_id.suffix.hex}"
  display_name = "Voice Synthesis Service Account"
  description  = "Service account for voice generation Cloud Functions with least privilege access"
}

# IAM roles for the service account
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.voice_synthesis.email}"
}

resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.voice_synthesis.email}"
}

resource "google_project_iam_member" "texttospeech_user" {
  project = var.project_id
  role    = "roles/cloudtts.user"
  member  = "serviceAccount:${google_service_account.voice_synthesis.email}"
}

# Allow the service account to invoke Cloud Functions
resource "google_project_iam_member" "functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.voice_synthesis.email}"
}

# Create a zip file for the profile management function
data "archive_file" "profile_manager_source" {
  type        = "zip"
  output_path = "${path.module}/profile-manager.zip"
  
  source {
    content = jsonencode({
      name = "voice-profile-manager"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.3.0"
        "@google-cloud/storage" = "^7.7.0"
        "pg" = "^8.11.3"
        "express" = "^4.18.2"
      }
    })
    filename = "package.json"
  }
  
  source {
    content = templatefile("${path.module}/functions/profile-manager.js", {
      bucket_name = google_storage_bucket.voice_audio.name
    })
    filename = "index.js"
  }
}

# Create a zip file for the voice synthesis function
data "archive_file" "voice_synthesis_source" {
  type        = "zip"
  output_path = "${path.module}/voice-synthesis.zip"
  
  source {
    content = jsonencode({
      name = "voice-synthesis"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.3.0"
        "@google-cloud/text-to-speech" = "^5.3.0"
        "@google-cloud/storage" = "^7.7.0"
        "pg" = "^8.11.3"
      }
    })
    filename = "package.json"
  }
  
  source {
    content = templatefile("${path.module}/functions/voice-synthesis.js", {
      bucket_name = google_storage_bucket.voice_audio.name
    })
    filename = "index.js"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "profile_manager_source" {
  name   = "functions/profile-manager-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.voice_audio.name
  source = data.archive_file.profile_manager_source.output_path
  
  depends_on = [google_storage_bucket.voice_audio]
}

resource "google_storage_bucket_object" "voice_synthesis_source" {
  name   = "functions/voice-synthesis-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.voice_audio.name
  source = data.archive_file.voice_synthesis_source.output_path
  
  depends_on = [google_storage_bucket.voice_audio]
}

# Cloud Function for voice profile management
resource "google_cloudfunctions_function" "profile_manager" {
  name        = "profile-manager-${random_id.suffix.hex}"
  description = "Manages voice profiles with Cloud SQL integration"
  runtime     = "nodejs18"
  region      = var.region
  
  # Function source code
  source_archive_bucket = google_storage_bucket.voice_audio.name
  source_archive_object = google_storage_bucket_object.profile_manager_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Function configuration
  entry_point                = "profileManager"
  timeout                    = var.function_timeout_seconds
  available_memory_mb        = 256
  max_instances              = 100
  min_instances              = 0
  service_account_email      = google_service_account.voice_synthesis.email
  
  # Environment variables
  environment_variables = {
    BUCKET_NAME  = google_storage_bucket.voice_audio.name
    PROJECT_ID   = var.project_id
    REGION       = var.region
    DB_INSTANCE  = google_sql_database_instance.voice_profiles.name
    DB_PASSWORD  = random_password.db_password.result
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.profile_manager_source
  ]
}

# Cloud Function for voice synthesis with Chirp 3
resource "google_cloudfunctions_function" "voice_synthesis" {
  name        = "voice-synthesis-${random_id.suffix.hex}"
  description = "Synthesizes speech using Chirp 3: HD voices"
  runtime     = "nodejs18"
  region      = var.region
  
  # Function source code
  source_archive_bucket = google_storage_bucket.voice_audio.name
  source_archive_object = google_storage_bucket_object.voice_synthesis_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Function configuration
  entry_point                = "voiceSynthesis"
  timeout                    = var.function_timeout_seconds
  available_memory_mb        = var.function_memory_mb
  max_instances              = 100
  min_instances              = 0
  service_account_email      = google_service_account.voice_synthesis.email
  
  # Environment variables
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.voice_audio.name
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.voice_synthesis_source
  ]
}

# Allow unauthenticated access to Cloud Functions for testing
resource "google_cloudfunctions_function_iam_member" "profile_manager_invoker" {
  project        = google_cloudfunctions_function.profile_manager.project
  region         = google_cloudfunctions_function.profile_manager.region
  cloud_function = google_cloudfunctions_function.profile_manager.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "voice_synthesis_invoker" {
  project        = google_cloudfunctions_function.voice_synthesis.project
  region         = google_cloudfunctions_function.voice_synthesis.region
  cloud_function = google_cloudfunctions_function.voice_synthesis.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}