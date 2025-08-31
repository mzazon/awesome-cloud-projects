# Output values for GCP automated API testing infrastructure
# This file defines outputs that provide important information about the deployed resources

# ==============================================================================
# PROJECT INFORMATION
# ==============================================================================

output "project_id" {
  description = "The GCP project ID where resources were created"
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

# ==============================================================================
# RESOURCE NAMES AND IDENTIFIERS
# ==============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for test results"
  value       = google_storage_bucket.test_results.name
}

output "function_name" {
  description = "Name of the Cloud Function for test case generation"
  value       = google_cloudfunctions2_function.test_generator.name
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service for test execution"
  value       = google_cloud_run_v2_service.test_runner.name
}

# ==============================================================================
# SERVICE ENDPOINTS AND URLS
# ==============================================================================

output "function_url" {
  description = "HTTP trigger URL for the test generator Cloud Function"
  value       = google_cloudfunctions2_function.test_generator.service_config[0].uri
  sensitive   = false
}

output "cloud_run_url" {
  description = "URL of the test runner Cloud Run service"
  value       = google_cloud_run_v2_service.test_runner.uri
  sensitive   = false
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = "gs://${google_storage_bucket.test_results.name}"
}

output "console_bucket_url" {
  description = "Google Cloud Console URL for the storage bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.test_results.name}"
}

# ==============================================================================
# SERVICE ACCOUNTS
# ==============================================================================

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "cloud_run_service_account" {
  description = "Email of the service account used by the Cloud Run service"
  value       = google_service_account.cloud_run_sa.email
}

# ==============================================================================
# CONFIGURATION VALUES
# ==============================================================================

output "vertex_ai_location" {
  description = "Location used for Vertex AI resources"
  value       = local.vertex_ai_location
}

output "gemini_model" {
  description = "Vertex AI Gemini model configured for test generation"
  value       = var.gemini_model
}

output "function_runtime" {
  description = "Runtime version for the Cloud Function"
  value       = var.function_runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function"
  value       = var.function_memory
}

output "cloud_run_memory" {
  description = "Memory allocation for the Cloud Run service"
  value       = var.cloud_run_memory
}

output "cloud_run_cpu" {
  description = "CPU allocation for the Cloud Run service"
  value       = var.cloud_run_cpu
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

output "storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.test_results.storage_class
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the storage bucket"
  value       = var.versioning_enabled
}

output "test_results_retention_days" {
  description = "Number of days test results are retained"
  value       = var.test_results_retention_days
}

# ==============================================================================
# MONITORING AND SECURITY
# ==============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_cloud_monitoring
}

output "audit_logs_enabled" {
  description = "Whether audit logging is enabled"
  value       = var.enable_audit_logs
}

output "secret_manager_enabled" {
  description = "Whether Secret Manager is enabled"
  value       = var.enable_secret_manager
}

output "secret_name" {
  description = "Name of the Secret Manager secret (if enabled)"
  value       = var.enable_secret_manager ? google_secret_manager_secret.api_config[0].secret_id : null
}

# ==============================================================================
# COST OPTIMIZATION INFORMATION
# ==============================================================================

output "function_min_instances" {
  description = "Minimum number of function instances (cost optimization)"
  value       = var.function_min_instances
}

output "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (cost optimization)"
  value       = var.cloud_run_min_instances
}

output "cost_optimization_enabled" {
  description = "Whether cost optimization features are enabled"
  value       = var.enable_cost_optimization
}

# ==============================================================================
# NETWORKING INFORMATION
# ==============================================================================

output "vpc_connector_enabled" {
  description = "Whether VPC connector is enabled for private networking"
  value       = var.enable_vpc_connector
}

output "vpc_connector_name" {
  description = "Name of the VPC connector (if enabled)"
  value       = var.enable_vpc_connector ? var.vpc_connector_name : null
}

# ==============================================================================
# DEPLOYMENT COMMANDS
# ==============================================================================

output "test_function_command" {
  description = "Command to test the Cloud Function endpoint"
  value = <<-EOT
    curl -X POST "${google_cloudfunctions2_function.test_generator.service_config[0].uri}" \
      -H "Content-Type: application/json" \
      -d '{
        "api_specification": "Sample API specification",
        "endpoints": ["https://httpbin.org/get"],
        "test_types": ["functional", "security"],
        "request_id": "test-$(date +%s)"
      }'
  EOT
}

output "test_cloud_run_command" {
  description = "Command to test the Cloud Run service health endpoint"
  value = "curl ${google_cloud_run_v2_service.test_runner.uri}/health"
}

output "workflow_environment_setup" {
  description = "Environment variables needed for the testing workflow"
  value = <<-EOT
    export PROJECT_ID="${var.project_id}"
    export REGION="${var.region}"
    export BUCKET_NAME="${google_storage_bucket.test_results.name}"
    export FUNCTION_URL="${google_cloudfunctions2_function.test_generator.service_config[0].uri}"
    export SERVICE_URL="${google_cloud_run_v2_service.test_runner.uri}"
  EOT
}

# ==============================================================================
# VERIFICATION COMMANDS
# ==============================================================================

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    list_bucket_contents = "gsutil ls -r gs://${google_storage_bucket.test_results.name}/"
    check_function_logs  = "gcloud functions logs read ${google_cloudfunctions2_function.test_generator.name} --region=${var.region} --limit=50"
    check_cloud_run_logs = "gcloud logging read 'resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.test_runner.name}\"' --limit=50 --format='table(timestamp,textPayload)'"
    test_complete_workflow = "python test-workflow.py"
  }
}

# ==============================================================================
# MONITORING URLS
# ==============================================================================

output "monitoring_urls" {
  description = "URLs for monitoring and managing the deployed resources"
  value = {
    cloud_functions_console = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.test_generator.name}?project=${var.project_id}"
    cloud_run_console      = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.test_runner.name}?project=${var.project_id}"
    storage_console        = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.test_results.name}?project=${var.project_id}"
    vertex_ai_console      = "https://console.cloud.google.com/vertex-ai?project=${var.project_id}"
    monitoring_console     = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    logs_console          = "https://console.cloud.google.com/logs?project=${var.project_id}"
  }
}

# ==============================================================================
# RESOURCE LABELS
# ==============================================================================

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# ==============================================================================
# API ENDPOINTS
# ==============================================================================

output "api_endpoints" {
  description = "API endpoints for the testing services"
  value = {
    generate_tests = "${google_cloudfunctions2_function.test_generator.service_config[0].uri}"
    run_tests     = "${google_cloud_run_v2_service.test_runner.uri}/run-tests"
    health_check  = "${google_cloud_run_v2_service.test_runner.uri}/health"
  }
}

# ==============================================================================
# CLEANUP COMMANDS
# ==============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources when no longer needed"
  value = {
    delete_function   = "gcloud functions delete ${google_cloudfunctions2_function.test_generator.name} --region=${var.region} --quiet"
    delete_cloud_run  = "gcloud run services delete ${google_cloud_run_v2_service.test_runner.name} --region=${var.region} --quiet"
    delete_bucket     = "gsutil -m rm -r gs://${google_storage_bucket.test_results.name}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# ==============================================================================
# SAMPLE USAGE
# ==============================================================================

output "sample_api_specification" {
  description = "Sample API specification for testing the solution"
  value = jsonencode({
    openapi = "3.0.0"
    info = {
      title   = "Sample API"
      version = "1.0.0"
    }
    paths = {
      "/users" = {
        get = {
          summary = "Get all users"
          responses = {
            "200" = {
              description = "List of users"
            }
          }
        }
      }
      "/posts" = {
        get = {
          summary = "Get all posts"
          responses = {
            "200" = {
              description = "List of posts"
            }
          }
        }
        post = {
          summary = "Create a new post"
          requestBody = {
            content = {
              "application/json" = {
                schema = {
                  type = "object"
                  properties = {
                    title  = { type = "string" }
                    body   = { type = "string" }
                    userId = { type = "integer" }
                  }
                }
              }
            }
          }
          responses = {
            "201" = {
              description = "Post created successfully"
            }
          }
        }
      }
    }
  })
}

# ==============================================================================
# SUCCESS MESSAGE
# ==============================================================================

output "deployment_complete" {
  description = "Deployment completion message with next steps"
  value = <<-EOT
    ✅ GCP Automated API Testing Infrastructure Deployed Successfully!
    
    🚀 Quick Start:
    1. Set environment variables: ${join(" && ", split("\n", chomp(local.workflow_setup)))}
    2. Test the function: ${substr(local.test_function_cmd, 0, 100)}...
    3. Test the Cloud Run service: ${local.test_cloud_run_cmd}
    4. Run the complete workflow: python test-workflow.py
    
    📊 Monitor your resources:
    - Functions: https://console.cloud.google.com/functions?project=${var.project_id}
    - Cloud Run: https://console.cloud.google.com/run?project=${var.project_id}
    - Storage: https://console.cloud.google.com/storage/browser?project=${var.project_id}
    
    💡 Next steps:
    1. Upload your API specifications to test
    2. Customize the Gemini prompts for your use case
    3. Set up monitoring alerts for production use
    4. Configure CI/CD pipelines for automated testing
  EOT
}

# ==============================================================================
# LOCAL VALUES FOR OUTPUT FORMATTING
# ==============================================================================

locals {
  workflow_setup = <<-EOT
    export PROJECT_ID="${var.project_id}"
    export REGION="${var.region}"
    export BUCKET_NAME="${google_storage_bucket.test_results.name}"
    export FUNCTION_URL="${google_cloudfunctions2_function.test_generator.service_config[0].uri}"
    export SERVICE_URL="${google_cloud_run_v2_service.test_runner.uri}"
  EOT
  
  test_function_cmd = "curl -X POST \"${google_cloudfunctions2_function.test_generator.service_config[0].uri}\" -H \"Content-Type: application/json\" -d '{\"api_specification\": \"Sample\", \"request_id\": \"test\"}'"
  
  test_cloud_run_cmd = "curl ${google_cloud_run_v2_service.test_runner.uri}/health"
}