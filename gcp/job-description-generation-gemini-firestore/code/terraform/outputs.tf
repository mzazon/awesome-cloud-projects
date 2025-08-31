# =============================================================================
# Outputs for Job Description Generation with Gemini and Firestore
# =============================================================================
# This file defines all outputs that provide important information about 
# the deployed infrastructure for integration and verification purposes.
# =============================================================================

# =============================================================================
# Project and Basic Information
# =============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources are deployed"
  value       = data.google_project.current.project_id
}

output "project_number" {
  description = "The Google Cloud Project number"
  value       = data.google_project.current.number
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# =============================================================================
# Cloud Functions Information
# =============================================================================

output "job_description_generator_function_name" {
  description = "Name of the job description generator Cloud Function"
  value       = google_cloudfunctions2_function.generate_job_description.name
}

output "job_description_generator_function_url" {
  description = "HTTP trigger URL for the job description generator function"
  value       = google_cloudfunctions2_function.generate_job_description.service_config[0].uri
}

output "job_description_generator_function_id" {
  description = "Full resource ID of the job description generator function"
  value       = google_cloudfunctions2_function.generate_job_description.id
}

output "compliance_validator_function_name" {
  description = "Name of the compliance validator Cloud Function"
  value       = google_cloudfunctions2_function.validate_compliance.name
}

output "compliance_validator_function_url" {
  description = "HTTP trigger URL for the compliance validator function"
  value       = google_cloudfunctions2_function.validate_compliance.service_config[0].uri
}

output "compliance_validator_function_id" {
  description = "Full resource ID of the compliance validator function"
  value       = google_cloudfunctions2_function.validate_compliance.id
}

# =============================================================================
# Firestore Database Information
# =============================================================================

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.hr_database.name
}

output "firestore_database_id" {
  description = "Full resource ID of the Firestore database"
  value       = google_firestore_database.hr_database.id
}

output "firestore_database_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.hr_database.location_id
}

output "firestore_database_create_time" {
  description = "Timestamp when the Firestore database was created"
  value       = google_firestore_database.hr_database.create_time
}

output "firestore_database_uid" {
  description = "System-generated UUID for the Firestore database"
  value       = google_firestore_database.hr_database.uid
}

# =============================================================================
# Storage Information
# =============================================================================

output "function_source_bucket_name" {
  description = "Name of the storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

output "function_source_object_name" {
  description = "Name of the function source code object in storage"
  value       = google_storage_bucket_object.function_source.name
}

# =============================================================================
# Service Account Information
# =============================================================================

output "function_service_account_email" {
  description = "Email address of the function service account"
  value       = google_service_account.function_service_account.email
}

output "function_service_account_id" {
  description = "Unique ID of the function service account"
  value       = google_service_account.function_service_account.unique_id
}

output "build_service_account_email" {
  description = "Email address of the build service account"
  value       = google_service_account.build_service_account.email
}

output "build_service_account_id" {
  description = "Unique ID of the build service account"
  value       = google_service_account.build_service_account.unique_id
}

# =============================================================================
# API Endpoints and Usage Examples
# =============================================================================

output "api_endpoints" {
  description = "Available API endpoints and their purposes"
  value = {
    job_description_generator = {
      url         = google_cloudfunctions2_function.generate_job_description.service_config[0].uri
      method      = "POST"
      description = "Generate job descriptions based on role templates"
      example_payload = jsonencode({
        role_id             = "software_engineer"
        custom_requirements = "Experience with microservices architecture"
      })
    }
    compliance_validator = {
      url         = google_cloudfunctions2_function.validate_compliance.service_config[0].uri
      method      = "POST"
      description = "Validate job descriptions for compliance issues"
      example_payload = jsonencode({
        job_description = "Software Engineer position requiring 10+ years experience..."
      })
    }
  }
}

# =============================================================================
# Configuration and Settings
# =============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value       = [for api in google_project_service.required_apis : api.service]
}

output "company_configuration" {
  description = "Company configuration stored in Firestore"
  value = {
    company_name              = var.company_name
    company_mission          = var.company_mission
    company_values           = var.company_values
    culture_description      = var.company_culture_description
    benefits                 = var.company_benefits
    work_environment         = var.work_environment
  }
  sensitive = false
}

output "vertex_ai_configuration" {
  description = "Vertex AI model configuration"
  value = {
    gemini_model = var.gemini_model
    region       = var.region
    project_id   = data.google_project.current.project_id
  }
}

# =============================================================================
# Firestore Collections and Documents
# =============================================================================

output "firestore_collections" {
  description = "Firestore collections created by this deployment"
  value = {
    company_culture = {
      collection = "company_culture"
      documents  = ["default"]
      description = "Company culture data and organizational information"
    }
    job_templates = {
      collection = "job_templates"
      documents  = ["software_engineer", "marketing_manager"]
      description = "Job role templates with requirements and responsibilities"
    }
    generated_jobs = {
      collection = "generated_jobs"
      documents  = "Dynamic - created when jobs are generated"
      description = "Generated job descriptions with metadata"
    }
  }
}

# =============================================================================
# Monitoring and Logging
# =============================================================================

output "monitoring_dashboards" {
  description = "Available monitoring and logging resources"
  value = var.enable_monitoring ? {
    function_errors_metric = google_logging_metric.function_errors[0].name
    successful_generations_metric = google_logging_metric.successful_generations[0].name
    cloud_console_logs_url = "https://console.cloud.google.com/logs/query?project=${data.google_project.current.project_id}&query=resource.type%3D%22cloud_function%22"
    cloud_console_functions_url = "https://console.cloud.google.com/functions/list?project=${data.google_project.current.project_id}"
  } : {}
}

# =============================================================================
# Security and Access Information
# =============================================================================

output "security_configuration" {
  description = "Security and access configuration summary"
  value = {
    unauthenticated_access_enabled = var.allow_unauthenticated_access
    firestore_delete_protection    = var.firestore_delete_protection
    firestore_pitr_enabled        = var.enable_firestore_pitr
    function_ingress_settings     = "ALLOW_ALL"
  }
}

output "iam_roles_granted" {
  description = "IAM roles granted to service accounts"
  value = {
    function_service_account = {
      email = google_service_account.function_service_account.email
      roles = [
        "roles/aiplatform.user",
        "roles/datastore.user",
        "roles/logging.logWriter"
      ]
    }
    build_service_account = {
      email = google_service_account.build_service_account.email
      roles = [
        "roles/logging.logWriter",
        "roles/artifactregistry.writer",
        "roles/storage.objectAdmin"
      ]
    }
  }
}

# =============================================================================
# Cost and Resource Information
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for different usage levels (USD)"
  value = {
    low_usage = {
      description = "~100 job generations per month"
      breakdown = {
        vertex_ai_requests    = "~$5"
        cloud_functions_calls = "~$1"
        firestore_operations = "~$2"
        storage_costs        = "~$1"
        total_estimated      = "~$9"
      }
    }
    medium_usage = {
      description = "~1000 job generations per month"
      breakdown = {
        vertex_ai_requests    = "~$30"
        cloud_functions_calls = "~$5"
        firestore_operations = "~$10"
        storage_costs        = "~$2"
        total_estimated      = "~$47"
      }
    }
    high_usage = {
      description = "~10000 job generations per month"
      breakdown = {
        vertex_ai_requests    = "~$200"
        cloud_functions_calls = "~$25"
        firestore_operations = "~$50"
        storage_costs        = "~$5"
        total_estimated      = "~$280"
      }
    }
    note = "Actual costs may vary based on usage patterns, data size, and regional pricing"
  }
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value = {
    application = "hr-automation"
    component   = "job-description-generator"
    environment = var.environment
    created_by  = "terraform"
    recipe      = "job-description-generation-gemini-firestore"
  }
}

# =============================================================================
# Testing and Validation Information
# =============================================================================

output "testing_information" {
  description = "Information for testing the deployed solution"
  value = {
    curl_examples = {
      generate_software_engineer_job = "curl -X POST '${google_cloudfunctions2_function.generate_job_description.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"role_id\": \"software_engineer\", \"custom_requirements\": \"Experience with microservices\"}'"
      generate_marketing_manager_job = "curl -X POST '${google_cloudfunctions2_function.generate_job_description.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"role_id\": \"marketing_manager\", \"custom_requirements\": \"B2B SaaS experience preferred\"}'"
      validate_compliance = "curl -X POST '${google_cloudfunctions2_function.validate_compliance.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"job_description\": \"Your generated job description here\"}'"
    }
    available_role_templates = [
      "software_engineer",
      "marketing_manager"
    ]
    firestore_console_url = "https://console.firebase.google.com/project/${data.google_project.current.project_id}/firestore"
  }
}

# =============================================================================
# Integration Information
# =============================================================================

output "integration_details" {
  description = "Details for integrating with external systems"
  value = {
    webhook_endpoints = var.webhook_endpoints
    api_authentication = {
      type = var.allow_unauthenticated_access ? "None (Public Access)" : "Service Account Authentication"
      notes = var.allow_unauthenticated_access ? "Consider enabling authentication for production use" : "Use service account tokens for authentication"
    }
    cors_configuration = {
      enabled = true
      origins = var.cors_origins
    }
    rate_limiting = {
      enabled = var.rate_limit_per_minute > 0
      limit   = "${var.rate_limit_per_minute} requests per minute"
    }
  }
}

# =============================================================================
# Troubleshooting Information
# =============================================================================

output "troubleshooting_resources" {
  description = "Resources and commands for troubleshooting issues"
  value = {
    cloud_console_links = {
      functions     = "https://console.cloud.google.com/functions/list?project=${data.google_project.current.project_id}"
      firestore     = "https://console.firebase.google.com/project/${data.google_project.current.project_id}/firestore"
      vertex_ai     = "https://console.cloud.google.com/vertex-ai?project=${data.google_project.current.project_id}"
      logs          = "https://console.cloud.google.com/logs?project=${data.google_project.current.project_id}"
      iam           = "https://console.cloud.google.com/iam-admin/iam?project=${data.google_project.current.project_id}"
    }
    gcloud_commands = {
      view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.generate_job_description.name} --region=${var.region} --project=${data.google_project.current.project_id}"
      test_function = "gcloud functions call ${google_cloudfunctions2_function.generate_job_description.name} --region=${var.region} --project=${data.google_project.current.project_id} --data='{\"role_id\":\"software_engineer\"}'"
      check_firestore = "gcloud firestore databases describe ${google_firestore_database.hr_database.name} --project=${data.google_project.current.project_id}"
    }
    common_issues = {
      permission_denied = "Check that the function service account has the required IAM roles"
      function_timeout = "Increase function timeout or optimize Vertex AI calls"
      firestore_access = "Verify Firestore database is in the correct region and accessible"
      vertex_ai_quota = "Check Vertex AI quotas and request increases if needed"
    }
  }
}

# =============================================================================
# Next Steps and Recommendations
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    immediate_actions = [
      "Test the job generation endpoint with sample data",
      "Verify Firestore collections contain the expected company data",
      "Check Cloud Function logs for any initialization issues",
      "Test compliance validation with various job descriptions"
    ]
    production_readiness = [
      "Enable authentication by setting allow_unauthenticated_access = false",
      "Set up monitoring alerts and dashboards",
      "Configure backup schedules for Firestore",
      "Implement rate limiting and API key authentication",
      "Review and adjust IAM permissions for least privilege"
    ]
    customization_options = [
      "Add more job role templates to Firestore",
      "Customize company culture data",
      "Integrate with external HR systems",
      "Add webhook notifications for job generation events",
      "Implement caching for frequently accessed data"
    ]
  }
}