# Outputs for legacy application modernization infrastructure

# ============================================================================
# PROJECT AND GENERAL OUTPUTS
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The deployment region"
  value       = var.region
}

output "zone" {
  description = "The deployment zone"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# MIGRATION CENTER OUTPUTS
# ============================================================================

output "migration_center_source_id" {
  description = "Migration Center discovery source ID"
  value       = var.migration_center_enabled ? google_migration_center_source.legacy_discovery[0].source_id : null
}

output "migration_center_source_name" {
  description = "Migration Center discovery source name"
  value       = var.migration_center_enabled ? google_migration_center_source.legacy_discovery[0].display_name : null
}

output "migration_center_location" {
  description = "Migration Center location"
  value       = var.migration_center_enabled ? google_migration_center_source.legacy_discovery[0].location : null
}

# ============================================================================
# SOURCE REPOSITORY OUTPUTS
# ============================================================================

output "repository_name" {
  description = "Cloud Source Repository name"
  value       = google_sourcerepo_repository.app_repo.name
}

output "repository_url" {
  description = "Cloud Source Repository URL"
  value       = google_sourcerepo_repository.app_repo.url
}

output "repository_clone_url_https" {
  description = "HTTPS clone URL for the repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.app_repo.name}"
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the repository"
  value       = "ssh://source.developers.google.com:2022/p/${var.project_id}/r/${google_sourcerepo_repository.app_repo.name}"
}

# ============================================================================
# SERVICE ACCOUNT OUTPUTS
# ============================================================================

output "cloud_build_service_account_email" {
  description = "Cloud Build service account email"
  value       = google_service_account.cloud_build_sa.email
}

output "cloud_run_service_account_email" {
  description = "Cloud Run service account email"
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_deploy_service_account_email" {
  description = "Cloud Deploy service account email"
  value       = google_service_account.cloud_deploy_sa.email
}

# ============================================================================
# CLOUD BUILD OUTPUTS
# ============================================================================

output "cloud_build_trigger_id" {
  description = "Cloud Build trigger ID"
  value       = var.build_enabled ? google_cloudbuild_trigger.main_trigger[0].trigger_id : null
}

output "cloud_build_trigger_name" {
  description = "Cloud Build trigger name"
  value       = var.build_enabled ? google_cloudbuild_trigger.main_trigger[0].name : null
}

output "cloud_build_trigger_location" {
  description = "Cloud Build trigger location"
  value       = var.build_enabled ? google_cloudbuild_trigger.main_trigger[0].location : null
}

# ============================================================================
# CLOUD DEPLOY OUTPUTS
# ============================================================================

output "delivery_pipeline_name" {
  description = "Cloud Deploy delivery pipeline name"
  value       = var.deploy_enabled ? google_clouddeploy_delivery_pipeline.main_pipeline[0].name : null
}

output "delivery_pipeline_uid" {
  description = "Cloud Deploy delivery pipeline UID"
  value       = var.deploy_enabled ? google_clouddeploy_delivery_pipeline.main_pipeline[0].uid : null
}

output "development_target_name" {
  description = "Development environment target name"
  value       = var.deploy_enabled ? google_clouddeploy_target.development[0].name : null
}

output "staging_target_name" {
  description = "Staging environment target name"
  value       = var.deploy_enabled ? google_clouddeploy_target.staging[0].name : null
}

output "production_target_name" {
  description = "Production environment target name"
  value       = var.deploy_enabled ? google_clouddeploy_target.production[0].name : null
}

# ============================================================================
# CLOUD RUN OUTPUTS
# ============================================================================

output "cloud_run_service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.modernized_app.name
}

output "cloud_run_service_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.modernized_app.uri
}

output "cloud_run_service_location" {
  description = "Cloud Run service location"
  value       = google_cloud_run_v2_service.modernized_app.location
}

output "cloud_run_service_latest_revision" {
  description = "Latest Cloud Run service revision"
  value       = google_cloud_run_v2_service.modernized_app.latest_ready_revision
}

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_connector_name" {
  description = "VPC connector name (if enabled)"
  value       = var.vpc_connector_enabled ? google_vpc_access_connector.connector[0].name : null
}

output "vpc_connector_id" {
  description = "VPC connector ID (if enabled)"
  value       = var.vpc_connector_enabled ? google_vpc_access_connector.connector[0].id : null
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "monitoring_dashboard_id" {
  description = "Monitoring dashboard ID"
  value       = var.dashboard_enabled ? google_monitoring_dashboard.app_dashboard[0].id : null
}

output "alert_policy_name" {
  description = "Alert policy name for high error rate"
  value       = var.alerting_enabled ? google_monitoring_alert_policy.high_error_rate[0].name : null
}

# ============================================================================
# CONTAINER SECURITY OUTPUTS
# ============================================================================

output "binary_authorization_policy_name" {
  description = "Binary Authorization policy name (if enabled)"
  value       = var.enable_binary_authorization ? google_binary_authorization_policy.policy[0].id : null
}

output "binary_authorization_attestor_name" {
  description = "Binary Authorization attestor name (if enabled)"
  value       = var.enable_binary_authorization ? google_binary_authorization_attestor.attestor[0].name : null
}

# ============================================================================
# COST MANAGEMENT OUTPUTS
# ============================================================================

output "budget_name" {
  description = "Budget name (if enabled)"
  value       = var.budget_enabled ? google_billing_budget.budget[0].name : null
}

output "budget_amount" {
  description = "Budget amount in USD (if enabled)"
  value       = var.budget_enabled ? var.budget_amount : null
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "deployment_commands" {
  description = "Helpful commands for deployment and management"
  value = {
    # Migration Center commands
    migration_center = var.migration_center_enabled ? {
      list_sources = "gcloud migration-center sources list --location=${var.region}"
      describe_source = "gcloud migration-center sources describe ${google_migration_center_source.legacy_discovery[0].source_id} --location=${var.region}"
    } : null

    # Cloud Build commands
    cloud_build = var.build_enabled ? {
      list_triggers = "gcloud builds triggers list"
      describe_trigger = "gcloud builds triggers describe ${google_cloudbuild_trigger.main_trigger[0].trigger_id} --region=${var.region}"
      manual_trigger = "gcloud builds triggers run ${google_cloudbuild_trigger.main_trigger[0].name} --branch=${var.trigger_branch} --region=${var.region}"
    } : null

    # Cloud Deploy commands
    cloud_deploy = var.deploy_enabled ? {
      list_pipelines = "gcloud deploy delivery-pipelines list --region=${var.region}"
      describe_pipeline = "gcloud deploy delivery-pipelines describe ${google_clouddeploy_delivery_pipeline.main_pipeline[0].name} --region=${var.region}"
      list_releases = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.main_pipeline[0].name} --region=${var.region}"
    } : null

    # Cloud Run commands
    cloud_run = {
      describe_service = "gcloud run services describe ${google_cloud_run_v2_service.modernized_app.name} --region=${var.region}"
      get_url = "gcloud run services describe ${google_cloud_run_v2_service.modernized_app.name} --region=${var.region} --format='value(status.url)'"
      test_endpoint = "curl -s $(gcloud run services describe ${google_cloud_run_v2_service.modernized_app.name} --region=${var.region} --format='value(status.url)')/health"
    }

    # Repository commands
    repository = {
      clone_https = "gcloud source repos clone ${google_sourcerepo_repository.app_repo.name} --project=${var.project_id}"
      list_repos = "gcloud source repos list"
    }
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Next steps for completing the modernization setup"
  value = [
    "1. Clone the source repository: gcloud source repos clone ${google_sourcerepo_repository.app_repo.name}",
    "2. Add your application code to the repository",
    "3. Create cloudbuild.yaml and skaffold.yaml configuration files",
    "4. Commit and push code to trigger the first build",
    "5. Monitor the build progress in Cloud Build console",
    "6. Deploy releases through Cloud Deploy pipeline",
    "7. Configure Migration Center discovery client in your legacy environment",
    "8. Use Application Design Center to design your modernized architecture",
    "9. Set up monitoring alerts and dashboards for your application",
    "10. Configure custom domains and SSL certificates if needed"
  ]
}

# ============================================================================
# USEFUL URLS
# ============================================================================

output "console_urls" {
  description = "Direct links to Google Cloud Console pages"
  value = {
    cloud_run_service = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.modernized_app.name}/metrics?project=${var.project_id}"
    cloud_build_triggers = "https://console.cloud.google.com/cloud-build/triggers?project=${var.project_id}"
    cloud_deploy_pipelines = "https://console.cloud.google.com/deploy/delivery-pipelines?project=${var.project_id}"
    source_repositories = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
    migration_center = var.migration_center_enabled ? "https://console.cloud.google.com/migration/discovery/sources?project=${var.project_id}" : null
    monitoring_dashboard = var.dashboard_enabled ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.app_dashboard[0].id}?project=${var.project_id}" : null
  }
}