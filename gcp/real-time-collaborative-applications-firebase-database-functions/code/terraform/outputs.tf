# Project and basic configuration outputs
output "project_id" {
  description = "The Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region used for resources"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = var.resource_prefix
}

# Firebase project outputs
output "firebase_project_number" {
  description = "The Firebase project number"
  value       = google_firebase_project.default.project_number
}

output "firebase_project_display_name" {
  description = "The display name of the Firebase project"
  value       = var.firebase_project_display_name
}

# Firebase Realtime Database outputs
output "database_url" {
  description = "The URL of the Firebase Realtime Database"
  value       = "https://${google_firebase_database_instance.default.database_url}"
}

output "database_instance_id" {
  description = "The instance ID of the Firebase Realtime Database"
  value       = google_firebase_database_instance.default.instance_id
}

output "database_region" {
  description = "The region of the Firebase Realtime Database"
  value       = google_firebase_database_instance.default.region
}

# Firebase Web App outputs
output "firebase_web_app_id" {
  description = "The Firebase Web App ID"
  value       = google_firebase_web_app.default.app_id
}

output "firebase_config" {
  description = "Firebase configuration for client applications"
  value = {
    apiKey            = google_firebase_web_app_config.default.api_key
    authDomain        = google_firebase_web_app_config.default.auth_domain
    databaseURL       = google_firebase_web_app_config.default.database_url
    projectId         = var.project_id
    storageBucket     = google_firebase_web_app_config.default.storage_bucket
    messagingSenderId = google_firebase_web_app_config.default.messaging_sender_id
    appId             = google_firebase_web_app.default.app_id
  }
  sensitive = true
}

# Firebase Hosting outputs
output "hosting_site_id" {
  description = "The Firebase Hosting site ID"
  value       = google_firebase_hosting_site.default.site_id
}

output "hosting_default_url" {
  description = "The default URL for the Firebase Hosting site"
  value       = "https://${google_firebase_hosting_site.default.default_url}"
}

# Cloud Functions outputs
output "cloud_functions" {
  description = "Information about deployed Cloud Functions"
  value = {
    create_document = {
      name = google_cloudfunctions2_function.create_document.name
      url  = google_cloudfunctions2_function.create_document.service_config[0].uri
    }
    add_collaborator = {
      name = google_cloudfunctions2_function.add_collaborator.name
      url  = google_cloudfunctions2_function.add_collaborator.service_config[0].uri
    }
    get_user_documents = {
      name = google_cloudfunctions2_function.get_user_documents.name
      url  = google_cloudfunctions2_function.get_user_documents.service_config[0].uri
    }
  }
}

# Service Account outputs
output "functions_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.email
}

output "functions_service_account_unique_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.functions_sa.unique_id
}

# Storage outputs
output "functions_source_bucket" {
  description = "Name of the GCS bucket storing Cloud Functions source code"
  value       = google_storage_bucket.functions_source.name
}

output "functions_source_bucket_url" {
  description = "URL of the GCS bucket storing Cloud Functions source code"
  value       = google_storage_bucket.functions_source.url
}

# Authentication outputs
output "auth_config" {
  description = "Firebase Authentication configuration"
  value = {
    enabled_providers = var.auth_providers
    project_id       = var.project_id
    auth_domain      = google_firebase_web_app_config.default.auth_domain
  }
}

# Monitoring outputs
output "monitoring_resources" {
  description = "Monitoring and alerting resources"
  value = {
    document_modifications_metric = google_logging_metric.document_modifications.name
    function_error_rate_alert    = google_monitoring_alert_policy.function_error_rate.name
  }
}

# URLs and endpoints for testing
output "testing_endpoints" {
  description = "Endpoints and URLs for testing the collaborative application"
  value = {
    database_url      = "https://${google_firebase_database_instance.default.database_url}"
    hosting_url       = "https://${google_firebase_hosting_site.default.default_url}"
    auth_domain       = google_firebase_web_app_config.default.auth_domain
    functions_region  = var.region
  }
}

# Configuration for client applications
output "client_config_template" {
  description = "Template configuration for client applications"
  value = {
    firebase = {
      apiKey            = google_firebase_web_app_config.default.api_key
      authDomain        = google_firebase_web_app_config.default.auth_domain
      databaseURL       = google_firebase_web_app_config.default.database_url
      projectId         = var.project_id
      storageBucket     = google_firebase_web_app_config.default.storage_bucket
      messagingSenderId = google_firebase_web_app_config.default.messaging_sender_id
      appId             = google_firebase_web_app.default.app_id
    }
    functions = {
      region = var.region
      endpoints = {
        createDocument     = google_cloudfunctions2_function.create_document.service_config[0].uri
        addCollaborator    = google_cloudfunctions2_function.add_collaborator.service_config[0].uri
        getUserDocuments   = google_cloudfunctions2_function.get_user_documents.service_config[0].uri
      }
    }
  }
  sensitive = true
}

# Resource naming information
output "resource_names" {
  description = "Names of all created resources"
  value = {
    project_id           = var.project_id
    database_instance    = google_firebase_database_instance.default.instance_id
    functions_bucket     = google_storage_bucket.functions_source.name
    hosting_site         = google_firebase_hosting_site.default.site_id
    web_app             = google_firebase_web_app.default.app_id
    service_account     = google_service_account.functions_sa.account_id
    cloud_functions = [
      google_cloudfunctions2_function.create_document.name,
      google_cloudfunctions2_function.add_collaborator.name,
      google_cloudfunctions2_function.get_user_documents.name
    ]
  }
}

# Cost estimation helpers
output "cost_estimation_info" {
  description = "Information to help estimate costs"
  value = {
    functions_memory_mb    = var.function_memory
    functions_timeout_sec  = var.function_timeout
    database_region        = var.database_region
    storage_class          = var.storage_class
    environment           = var.environment
  }
}

# Security configuration summary
output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    auth_providers_enabled    = var.auth_providers
    functions_service_account = google_service_account.functions_sa.email
    bucket_uniform_access     = google_storage_bucket.functions_source.uniform_bucket_level_access
    cors_origins_allowed      = var.cors_allowed_origins
    audit_logs_enabled        = var.enable_audit_logs
  }
}

# Next steps information
output "next_steps" {
  description = "Next steps for completing the setup"
  value = {
    deploy_client_app = "Deploy your client application to Firebase Hosting using 'firebase deploy --only hosting'"
    configure_database_rules = "Deploy database security rules using 'firebase deploy --only database'"
    setup_oauth = "Configure OAuth providers in the Firebase Console for production use"
    monitor_usage = "Monitor function usage and database operations in the Google Cloud Console"
    test_collaboration = "Test real-time collaboration by opening multiple browser sessions"
  }
}