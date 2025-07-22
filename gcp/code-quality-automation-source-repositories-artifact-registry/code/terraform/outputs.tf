# Output values for GCP Code Quality Automation Infrastructure

# Project and basic configuration outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

# Cloud Source Repository outputs
output "source_repository_name" {
  description = "Name of the created Cloud Source Repository"
  value       = google_sourcerepo_repository.quality_repo.name
}

output "source_repository_url" {
  description = "URL for cloning the Cloud Source Repository"
  value       = google_sourcerepo_repository.quality_repo.url
}

output "source_repository_clone_command" {
  description = "Command to clone the repository locally"
  value       = "gcloud source repos clone ${google_sourcerepo_repository.quality_repo.name} --project=${var.project_id}"
}

# Artifact Registry outputs
output "docker_registry_name" {
  description = "Name of the Docker Artifact Registry repository"
  value       = google_artifact_registry_repository.docker_registry.name
}

output "docker_registry_location" {
  description = "Location of the Docker Artifact Registry repository"
  value       = google_artifact_registry_repository.docker_registry.location
}

output "docker_registry_url" {
  description = "Full URL of the Docker Artifact Registry repository"
  value       = "${google_artifact_registry_repository.docker_registry.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_registry.name}"
}

output "python_registry_name" {
  description = "Name of the Python Artifact Registry repository"
  value       = google_artifact_registry_repository.python_registry.name
}

output "python_registry_url" {
  description = "Full URL of the Python Artifact Registry repository"
  value       = "${google_artifact_registry_repository.python_registry.location}-python.pkg.dev/${var.project_id}/${google_artifact_registry_repository.python_registry.name}"
}

output "docker_configure_command" {
  description = "Command to configure Docker authentication for Artifact Registry"
  value       = "gcloud auth configure-docker ${google_artifact_registry_repository.docker_registry.location}-docker.pkg.dev"
}

# Cloud Build outputs
output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.quality_pipeline.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.quality_pipeline.trigger_id
}

output "build_trigger_location" {
  description = "Location of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.quality_pipeline.location
}

# Cloud Storage outputs
output "build_artifacts_bucket" {
  description = "Name of the Cloud Storage bucket for build artifacts"
  value       = google_storage_bucket.build_artifacts.name
}

output "build_artifacts_bucket_url" {
  description = "URL of the Cloud Storage bucket for build artifacts"
  value       = google_storage_bucket.build_artifacts.url
}

output "access_logs_bucket" {
  description = "Name of the Cloud Storage bucket for access logs"
  value       = google_storage_bucket.access_logs.name
}

# Security and monitoring outputs
output "vulnerability_scanning_enabled" {
  description = "Whether vulnerability scanning is enabled for Artifact Registry"
  value       = var.enable_vulnerability_scanning
}

output "container_analysis_enabled" {
  description = "Whether Container Analysis API is enabled"
  value       = var.enable_container_analysis
}

output "binary_authorization_policy" {
  description = "Binary Authorization policy name (if enabled)"
  value       = var.enable_container_analysis ? google_binary_authorization_policy.quality_policy[0].name : null
}

output "quality_attestor_name" {
  description = "Name of the quality attestor (if enabled)"
  value       = var.enable_container_analysis ? google_binary_authorization_attestor.quality_attestor[0].name : null
}

# Monitoring outputs
output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "alert_policy_name" {
  description = "Name of the build failure alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.build_failure_alert[0].display_name : null
}

output "code_quality_metric_name" {
  description = "Name of the code quality logging metric (if enabled)"
  value       = var.enable_monitoring ? google_logging_metric.code_quality_score[0].name : null
}

# API status outputs
output "enabled_apis" {
  description = "List of APIs enabled for this project"
  value = [
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Usage instructions and next steps
output "setup_instructions" {
  description = "Instructions for setting up the code quality automation pipeline"
  value = <<-EOT
    
    🚀 Code Quality Automation Infrastructure Created Successfully!
    
    📋 Next Steps:
    
    1. Clone the repository:
       ${google_sourcerepo_repository.quality_repo.url}
       
    2. Configure Docker authentication:
       gcloud auth configure-docker ${google_artifact_registry_repository.docker_registry.location}-docker.pkg.dev
       
    3. Create your application code with quality configuration files:
       - requirements.txt
       - Dockerfile
       - cloudbuild.yaml
       - tests/
       - .flake8, .bandit configuration files
       
    4. Commit and push code to trigger the quality pipeline:
       git add .
       git commit -m "Initial commit with quality automation"
       git push origin main
       
    5. Monitor builds in Cloud Console:
       https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}
       
    6. View artifacts in Artifact Registry:
       https://console.cloud.google.com/artifacts?project=${var.project_id}
    
    📊 Resources Created:
    - Cloud Source Repository: ${google_sourcerepo_repository.quality_repo.name}
    - Docker Registry: ${google_artifact_registry_repository.docker_registry.name}
    - Python Registry: ${google_artifact_registry_repository.python_registry.name}
    - Build Trigger: ${google_cloudbuild_trigger.quality_pipeline.name}
    - Storage Bucket: ${google_storage_bucket.build_artifacts.name}
    
    🔒 Security Features:
    - Vulnerability scanning: ${var.enable_vulnerability_scanning ? "Enabled" : "Disabled"}
    - Container analysis: ${var.enable_container_analysis ? "Enabled" : "Disabled"}
    - Binary authorization: ${var.enable_container_analysis ? "Enabled" : "Disabled"}
    
    📈 Monitoring:
    - Build monitoring: ${var.enable_monitoring ? "Enabled" : "Disabled"}
    - Quality metrics: ${var.enable_monitoring ? "Enabled" : "Disabled"}
    
  EOT
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_id              = var.project_id
    region                 = var.region
    environment            = var.environment
    source_repository      = google_sourcerepo_repository.quality_repo.name
    docker_registry        = google_artifact_registry_repository.docker_registry.name
    python_registry        = google_artifact_registry_repository.python_registry.name
    build_trigger          = google_cloudbuild_trigger.quality_pipeline.name
    artifacts_bucket       = google_storage_bucket.build_artifacts.name
    vulnerability_scanning = var.enable_vulnerability_scanning
    container_analysis     = var.enable_container_analysis
    monitoring_enabled     = var.enable_monitoring
    machine_type          = var.machine_type
    build_timeout         = var.build_timeout
    retention_days        = var.artifact_retention_days
  }
}