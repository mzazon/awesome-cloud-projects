# Outputs for Custom Voice Generation with Chirp 3 and Functions
# This file contains all output values for accessing and managing the deployed infrastructure

# Project and Regional Information
output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.voice_audio.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.voice_audio.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.voice_audio.self_link
}

# Cloud SQL Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL database instance"
  value       = google_sql_database_instance.voice_profiles.name
}

output "database_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.voice_profiles.connection_name
}

output "database_instance_ip_address" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.voice_profiles.public_ip_address
  sensitive   = true
}

output "database_instance_self_link" {
  description = "Self-link of the Cloud SQL instance"
  value       = google_sql_database_instance.voice_profiles.self_link
}

output "database_name" {
  description = "Name of the voice profiles database"
  value       = google_sql_database.voice_profiles.name
}

output "database_password" {
  description = "Password for the postgres user (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the voice synthesis service account"
  value       = google_service_account.voice_synthesis.email
}

output "service_account_id" {
  description = "ID of the voice synthesis service account"
  value       = google_service_account.voice_synthesis.account_id
}

output "service_account_unique_id" {
  description = "Unique ID of the voice synthesis service account"
  value       = google_service_account.voice_synthesis.unique_id
}

# Cloud Functions Outputs
output "profile_manager_function_name" {
  description = "Name of the profile manager Cloud Function"
  value       = google_cloudfunctions_function.profile_manager.name
}

output "profile_manager_function_url" {
  description = "HTTPS trigger URL for the profile manager function"
  value       = google_cloudfunctions_function.profile_manager.https_trigger_url
}

output "profile_manager_function_status" {
  description = "Status of the profile manager function"
  value       = google_cloudfunctions_function.profile_manager.status
}

output "voice_synthesis_function_name" {
  description = "Name of the voice synthesis Cloud Function"
  value       = google_cloudfunctions_function.voice_synthesis.name
}

output "voice_synthesis_function_url" {
  description = "HTTPS trigger URL for the voice synthesis function"
  value       = google_cloudfunctions_function.voice_synthesis.https_trigger_url
}

output "voice_synthesis_function_status" {
  description = "Status of the voice synthesis function"
  value       = google_cloudfunctions_function.voice_synthesis.status
}

# API Endpoints and Usage Information
output "api_endpoints" {
  description = "API endpoints for the voice generation system"
  value = {
    profile_manager = {
      url         = google_cloudfunctions_function.profile_manager.https_trigger_url
      methods     = ["GET", "POST"]
      description = "Manage voice profiles - GET to list, POST to create"
    }
    voice_synthesis = {
      url         = google_cloudfunctions_function.voice_synthesis.https_trigger_url
      methods     = ["POST"]
      description = "Synthesize speech using Chirp 3: HD voices"
    }
  }
}

# Sample Usage Commands
output "usage_examples" {
  description = "Example commands for testing the voice generation system"
  value = {
    create_profile = "curl -X POST ${google_cloudfunctions_function.profile_manager.https_trigger_url} -H 'Content-Type: application/json' -d '{\"profileName\":\"test-profile\",\"voiceStyle\":\"en-US-Chirp3-HD-Achernar\",\"languageCode\":\"en-US\"}'"
    list_profiles  = "curl -X GET ${google_cloudfunctions_function.profile_manager.https_trigger_url}"
    synthesize_voice = "curl -X POST ${google_cloudfunctions_function.voice_synthesis.https_trigger_url} -H 'Content-Type: application/json' -d '{\"text\":\"Hello, this is a test of Chirp 3 HD voice synthesis.\",\"voiceStyle\":\"en-US-Chirp3-HD-Achernar\"}'"
  }
}

# Resource Monitoring and Management
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value       = local.required_apis
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation and monitoring"
  value = {
    storage_bucket = {
      name          = google_storage_bucket.voice_audio.name
      storage_class = google_storage_bucket.voice_audio.storage_class
      location      = google_storage_bucket.voice_audio.location
    }
    database = {
      tier         = google_sql_database_instance.voice_profiles.settings[0].tier
      storage_size = google_sql_database_instance.voice_profiles.settings[0].disk_size
      storage_type = google_sql_database_instance.voice_profiles.settings[0].disk_type
    }
    functions = {
      profile_manager = {
        memory_mb = google_cloudfunctions_function.profile_manager.available_memory_mb
        timeout   = google_cloudfunctions_function.profile_manager.timeout
      }
      voice_synthesis = {
        memory_mb = google_cloudfunctions_function.voice_synthesis.available_memory_mb
        timeout   = google_cloudfunctions_function.voice_synthesis.timeout
      }
    }
  }
}

# Security and Access Information
output "security_info" {
  description = "Security and access configuration information"
  value = {
    service_account = {
      email = google_service_account.voice_synthesis.email
      roles = [
        "roles/cloudsql.client",
        "roles/storage.objectAdmin",
        "roles/cloudtts.user",
        "roles/cloudfunctions.invoker"
      ]
    }
    database_access = {
      connection_name = google_sql_database_instance.voice_profiles.connection_name
      user           = "postgres"
      ssl_required   = false
    }
    storage_access = {
      bucket_name = google_storage_bucket.voice_audio.name
      cors_enabled = true
      versioning_enabled = google_storage_bucket.voice_audio.versioning[0].enabled
    }
  }
}

# Debugging and Troubleshooting Information
output "debug_info" {
  description = "Information useful for debugging and troubleshooting"
  value = {
    random_suffix = random_id.suffix.hex
    function_source_locations = {
      profile_manager = "gs://${google_storage_bucket.voice_audio.name}/${google_storage_bucket_object.profile_manager_source.name}"
      voice_synthesis = "gs://${google_storage_bucket.voice_audio.name}/${google_storage_bucket_object.voice_synthesis_source.name}"
    }
    database_connection = {
      host     = "/cloudsql/${google_sql_database_instance.voice_profiles.connection_name}"
      database = google_sql_database.voice_profiles.name
      user     = "postgres"
    }
  }
  sensitive = true
}

# Quick Start Information
output "quick_start" {
  description = "Quick start guide for using the voice generation system"
  value = {
    step_1 = "Test profile manager: curl -X GET ${google_cloudfunctions_function.profile_manager.https_trigger_url}"
    step_2 = "Create a voice profile using the profile manager endpoint with POST method"
    step_3 = "Synthesize speech using the voice synthesis endpoint with your text"
    step_4 = "Access generated audio files from the returned signed URLs"
    note   = "See the usage_examples output for detailed curl commands"
  }
}