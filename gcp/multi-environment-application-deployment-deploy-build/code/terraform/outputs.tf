# outputs.tf - Output values for the multi-environment deployment infrastructure
# This file defines outputs that provide important information about the created resources

output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
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

# GKE Cluster outputs
output "gke_clusters" {
  description = "Information about the created GKE clusters"
  value = {
    for env in local.environments : env => {
      name                = google_container_cluster.environment_clusters[env].name
      location            = google_container_cluster.environment_clusters[env].location
      endpoint            = google_container_cluster.environment_clusters[env].endpoint
      master_version      = google_container_cluster.environment_clusters[env].master_version
      self_link           = google_container_cluster.environment_clusters[env].self_link
      cluster_ca_cert     = google_container_cluster.environment_clusters[env].master_auth[0].cluster_ca_certificate
      autopilot_enabled   = google_container_cluster.environment_clusters[env].enable_autopilot
    }
  }
  sensitive = true
}

# Kubectl connection commands
output "kubectl_connection_commands" {
  description = "Commands to connect kubectl to each environment cluster"
  value = {
    for env in local.environments : env => 
      "gcloud container clusters get-credentials ${google_container_cluster.environment_clusters[env].name} --region=${var.region} --project=${var.project_id}"
  }
}

# Cloud Deploy outputs
output "clouddeploy_pipeline" {
  description = "Information about the Cloud Deploy pipeline"
  value = {
    name        = google_clouddeploy_delivery_pipeline.main_pipeline.name
    location    = google_clouddeploy_delivery_pipeline.main_pipeline.location
    uid         = google_clouddeploy_delivery_pipeline.main_pipeline.uid
    create_time = google_clouddeploy_delivery_pipeline.main_pipeline.create_time
    update_time = google_clouddeploy_delivery_pipeline.main_pipeline.update_time
    etag        = google_clouddeploy_delivery_pipeline.main_pipeline.etag
  }
}

output "clouddeploy_targets" {
  description = "Information about the Cloud Deploy targets"
  value = {
    for env in local.environments : env => {
      name        = google_clouddeploy_target.environment_targets[env].name
      location    = google_clouddeploy_target.environment_targets[env].location
      uid         = google_clouddeploy_target.environment_targets[env].uid
      create_time = google_clouddeploy_target.environment_targets[env].create_time
      update_time = google_clouddeploy_target.environment_targets[env].update_time
      etag        = google_clouddeploy_target.environment_targets[env].etag
    }
  }
}

# Service Account outputs
output "clouddeploy_service_account" {
  description = "Cloud Deploy service account information"
  value = {
    email       = google_service_account.clouddeploy_sa.email
    id          = google_service_account.clouddeploy_sa.id
    name        = google_service_account.clouddeploy_sa.name
    unique_id   = google_service_account.clouddeploy_sa.unique_id
    display_name = google_service_account.clouddeploy_sa.display_name
  }
}

output "cloudbuild_service_account" {
  description = "Cloud Build service account information"
  value = {
    email       = google_service_account.cloudbuild_sa.email
    id          = google_service_account.cloudbuild_sa.id
    name        = google_service_account.cloudbuild_sa.name
    unique_id   = google_service_account.cloudbuild_sa.unique_id
    display_name = google_service_account.cloudbuild_sa.display_name
  }
}

# Cloud Build outputs
output "cloudbuild_trigger" {
  description = "Information about the Cloud Build trigger"
  value = {
    name        = google_cloudbuild_trigger.main_trigger.name
    id          = google_cloudbuild_trigger.main_trigger.id
    trigger_id  = google_cloudbuild_trigger.main_trigger.trigger_id
    create_time = google_cloudbuild_trigger.main_trigger.create_time
  }
}

output "cloudbuild_github_trigger" {
  description = "Information about the GitHub Cloud Build trigger (if created)"
  value = var.create_github_connection && var.github_repository != "" ? {
    name        = google_cloudbuild_trigger.github_trigger[0].name
    id          = google_cloudbuild_trigger.github_trigger[0].id
    trigger_id  = google_cloudbuild_trigger.github_trigger[0].trigger_id
    create_time = google_cloudbuild_trigger.github_trigger[0].create_time
  } : null
}

# Monitoring outputs
output "monitoring_dashboard" {
  description = "Information about the monitoring dashboard"
  value = {
    id   = google_monitoring_dashboard.deployment_dashboard.id
    name = google_monitoring_dashboard.deployment_dashboard.id
  }
}

# Logging outputs
output "logging_sink" {
  description = "Information about the Cloud Logging sink"
  value = {
    name              = google_logging_project_sink.clouddeploy_logs.name
    destination       = google_logging_project_sink.clouddeploy_logs.destination
    filter            = google_logging_project_sink.clouddeploy_logs.filter
    writer_identity   = google_logging_project_sink.clouddeploy_logs.writer_identity
  }
}

# Useful URLs and commands
output "useful_urls" {
  description = "Useful URLs for monitoring and managing the deployment"
  value = {
    cloud_console_project = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    cloud_deploy_pipeline = "https://console.cloud.google.com/deploy/delivery-pipelines/${google_clouddeploy_delivery_pipeline.main_pipeline.name}?project=${var.project_id}&region=${var.region}"
    cloud_build_history   = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    gke_clusters          = "https://console.cloud.google.com/kubernetes/list/overview?project=${var.project_id}"
    container_registry    = "https://console.cloud.google.com/gcr/images/${var.project_id}?project=${var.project_id}"
    storage_bucket        = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.build_artifacts.name}?project=${var.project_id}"
    monitoring_dashboard  = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.deployment_dashboard.id}?project=${var.project_id}"
    cloud_logging         = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Deployment commands
output "deployment_commands" {
  description = "Commands to deploy and manage the application"
  value = {
    trigger_manual_build = "gcloud builds submit . --config=cloudbuild.yaml --project=${var.project_id} --substitutions=_CLOUDDEPLOY_SA=${google_service_account.clouddeploy_sa.email}"
    list_releases       = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.main_pipeline.name} --region=${var.region} --project=${var.project_id}"
    promote_release     = "gcloud deploy releases promote --delivery-pipeline=${google_clouddeploy_delivery_pipeline.main_pipeline.name} --region=${var.region} --project=${var.project_id}"
    rollback_release    = "gcloud deploy rollouts cancel --delivery-pipeline=${google_clouddeploy_delivery_pipeline.main_pipeline.name} --region=${var.region} --project=${var.project_id}"
    get_pipeline_status = "gcloud deploy delivery-pipelines describe ${google_clouddeploy_delivery_pipeline.main_pipeline.name} --region=${var.region} --project=${var.project_id}"
  }
}

# Environment-specific service endpoints (will be populated after deployment)
output "environment_service_endpoints" {
  description = "Service endpoints for each environment (available after application deployment)"
  value = {
    dev = {
      service_name = "dev-${var.app_name}-service"
      get_endpoint_command = "kubectl get service dev-${var.app_name}-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --context=gke_${var.project_id}_${var.region}_${google_container_cluster.environment_clusters["dev"].name}"
    }
    staging = {
      service_name = "staging-${var.app_name}-service"
      get_endpoint_command = "kubectl get service staging-${var.app_name}-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --context=gke_${var.project_id}_${var.region}_${google_container_cluster.environment_clusters["staging"].name}"
    }
    prod = {
      service_name = "prod-${var.app_name}-service"
      get_endpoint_command = "kubectl get service prod-${var.app_name}-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --context=gke_${var.project_id}_${var.region}_${google_container_cluster.environment_clusters["prod"].name}"
    }
  }
}

# Resource IDs for cleanup
output "resource_ids" {
  description = "Resource IDs for cleanup and management"
  value = {
    random_suffix = random_id.suffix.hex
    cluster_names = [for env in local.environments : google_container_cluster.environment_clusters[env].name]
    service_accounts = [
      google_service_account.clouddeploy_sa.email,
      google_service_account.cloudbuild_sa.email
    ]
    storage_buckets = [google_storage_bucket.build_artifacts.name]
  }
}

# Next steps guidance
output "next_steps" {
  description = "Next steps to complete the deployment setup"
  value = [
    "1. Create your application source code and Kubernetes manifests",
    "2. Set up your Git repository with the application code",
    "3. Create a cloudbuild.yaml file in your repository root",
    "4. Run the manual build trigger to test the pipeline",
    "5. Monitor deployments through the Cloud Console URLs provided",
    "6. Configure GitHub triggers if using GitHub integration",
    "7. Set up additional monitoring and alerting as needed"
  ]
}