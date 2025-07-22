# Project Information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone"
  value       = var.zone
}

# Resource Names and Identifiers
output "random_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.suffix
}

# Artifact Registry
output "artifact_registry_repository" {
  description = "Artifact Registry repository information"
  value = {
    name     = google_artifact_registry_repository.app_repo.name
    location = google_artifact_registry_repository.app_repo.location
    format   = google_artifact_registry_repository.app_repo.format
    url      = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app_repo.name}"
  }
}

# Cloud Storage
output "deployment_artifacts_bucket" {
  description = "Cloud Storage bucket for deployment artifacts"
  value = {
    name     = google_storage_bucket.deployment_artifacts.name
    location = google_storage_bucket.deployment_artifacts.location
    url      = google_storage_bucket.deployment_artifacts.url
  }
}

# GKE Clusters
output "gke_clusters" {
  description = "Information about all GKE clusters"
  value = {
    dev = {
      name               = google_container_cluster.dev_cluster.name
      location           = google_container_cluster.dev_cluster.location
      endpoint           = google_container_cluster.dev_cluster.endpoint
      cluster_ca_certificate = google_container_cluster.dev_cluster.master_auth[0].cluster_ca_certificate
      kubectl_config_command = "gcloud container clusters get-credentials ${google_container_cluster.dev_cluster.name} --zone=${google_container_cluster.dev_cluster.location} --project=${var.project_id}"
    }
    staging = {
      name               = google_container_cluster.staging_cluster.name
      location           = google_container_cluster.staging_cluster.location
      endpoint           = google_container_cluster.staging_cluster.endpoint
      cluster_ca_certificate = google_container_cluster.staging_cluster.master_auth[0].cluster_ca_certificate
      kubectl_config_command = "gcloud container clusters get-credentials ${google_container_cluster.staging_cluster.name} --zone=${google_container_cluster.staging_cluster.location} --project=${var.project_id}"
    }
    prod = {
      name               = google_container_cluster.prod_cluster.name
      location           = google_container_cluster.prod_cluster.location
      endpoint           = google_container_cluster.prod_cluster.endpoint
      cluster_ca_certificate = google_container_cluster.prod_cluster.master_auth[0].cluster_ca_certificate
      kubectl_config_command = "gcloud container clusters get-credentials ${google_container_cluster.prod_cluster.name} --zone=${google_container_cluster.prod_cluster.location} --project=${var.project_id}"
    }
  }
}

# Individual GKE cluster outputs for backward compatibility
output "dev_cluster_name" {
  description = "Name of the development GKE cluster"
  value       = google_container_cluster.dev_cluster.name
}

output "staging_cluster_name" {
  description = "Name of the staging GKE cluster"
  value       = google_container_cluster.staging_cluster.name
}

output "prod_cluster_name" {
  description = "Name of the production GKE cluster"
  value       = google_container_cluster.prod_cluster.name
}

# Cloud Deploy Pipeline
output "clouddeploy_pipeline" {
  description = "Cloud Deploy pipeline information"
  value = {
    name     = google_clouddeploy_delivery_pipeline.app_pipeline.name
    location = google_clouddeploy_delivery_pipeline.app_pipeline.location
    id       = google_clouddeploy_delivery_pipeline.app_pipeline.id
    uid      = google_clouddeploy_delivery_pipeline.app_pipeline.uid
  }
}

# Cloud Deploy Targets
output "clouddeploy_targets" {
  description = "Cloud Deploy targets information"
  value = {
    dev = {
      name     = google_clouddeploy_target.dev_target.name
      location = google_clouddeploy_target.dev_target.location
      id       = google_clouddeploy_target.dev_target.id
      cluster  = google_clouddeploy_target.dev_target.gke[0].cluster
    }
    staging = {
      name     = google_clouddeploy_target.staging_target.name
      location = google_clouddeploy_target.staging_target.location
      id       = google_clouddeploy_target.staging_target.id
      cluster  = google_clouddeploy_target.staging_target.gke[0].cluster
      require_approval = google_clouddeploy_target.staging_target.require_approval
    }
    prod = {
      name     = google_clouddeploy_target.prod_target.name
      location = google_clouddeploy_target.prod_target.location
      id       = google_clouddeploy_target.prod_target.id
      cluster  = google_clouddeploy_target.prod_target.gke[0].cluster
      require_approval = google_clouddeploy_target.prod_target.require_approval
    }
  }
}

# Cloud Build Trigger (if created)
output "cloudbuild_trigger" {
  description = "Cloud Build trigger information"
  value = length(google_cloudbuild_trigger.app_trigger) > 0 ? {
    name = google_cloudbuild_trigger.app_trigger[0].name
    id   = google_cloudbuild_trigger.app_trigger[0].id
    github_repo = {
      owner = google_cloudbuild_trigger.app_trigger[0].github[0].owner
      name  = google_cloudbuild_trigger.app_trigger[0].github[0].name
    }
    branch_pattern = var.branch_pattern
  } : null
}

# Service Accounts (if created)
output "service_accounts" {
  description = "Service accounts created for Cloud Deploy and Cloud Build"
  value = var.create_service_accounts ? {
    clouddeploy = {
      email       = google_service_account.clouddeploy_sa[0].email
      name        = google_service_account.clouddeploy_sa[0].name
      account_id  = google_service_account.clouddeploy_sa[0].account_id
      unique_id   = google_service_account.clouddeploy_sa[0].unique_id
    }
    cloudbuild = {
      email       = google_service_account.cloudbuild_sa[0].email
      name        = google_service_account.cloudbuild_sa[0].name
      account_id  = google_service_account.cloudbuild_sa[0].account_id
      unique_id   = google_service_account.cloudbuild_sa[0].unique_id
    }
  } : null
}

# Container Image Information
output "container_image_url" {
  description = "Container image URL for the application"
  value       = local.container_image
}

# Application Configuration
output "application_config" {
  description = "Application configuration information"
  value = {
    name           = var.app_name
    container_image = local.container_image
    pipeline_name  = local.pipeline_name
    environments   = ["dev", "staging", "prod"]
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands for managing the deployment"
  value = {
    # Docker commands
    build_and_push_image = "docker build -t ${local.container_image} . && docker push ${local.container_image}"
    
    # gcloud commands
    create_release = "gcloud deploy releases create release-$(date +%Y%m%d-%H%M%S) --delivery-pipeline=${google_clouddeploy_delivery_pipeline.app_pipeline.name} --region=${var.region} --images=${var.app_name}=${local.container_image}"
    
    list_releases = "gcloud deploy releases list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.app_pipeline.name} --region=${var.region}"
    
    list_rollouts = "gcloud deploy rollouts list --delivery-pipeline=${google_clouddeploy_delivery_pipeline.app_pipeline.name} --region=${var.region}"
    
    # kubectl commands
    get_dev_credentials    = "gcloud container clusters get-credentials ${google_container_cluster.dev_cluster.name} --zone=${var.zone} --project=${var.project_id}"
    get_staging_credentials = "gcloud container clusters get-credentials ${google_container_cluster.staging_cluster.name} --zone=${var.zone} --project=${var.project_id}"
    get_prod_credentials   = "gcloud container clusters get-credentials ${google_container_cluster.prod_cluster.name} --zone=${var.zone} --project=${var.project_id}"
  }
}

# Monitoring and Logging
output "monitoring_links" {
  description = "Links to monitoring and logging dashboards"
  value = {
    cloud_deploy_pipelines = "https://console.cloud.google.com/deploy/delivery-pipelines?project=${var.project_id}"
    cloud_build_history    = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    gke_clusters          = "https://console.cloud.google.com/kubernetes/list?project=${var.project_id}"
    artifact_registry     = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.app_repo.name}?project=${var.project_id}"
    cloud_storage         = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.deployment_artifacts.name}?project=${var.project_id}"
  }
}

# Configuration Files Templates
output "configuration_templates" {
  description = "Templates for configuration files"
  value = {
    skaffold_yaml = templatefile("${path.module}/templates/skaffold.yaml.tpl", {
      project_id      = var.project_id
      region          = var.region
      repo_name       = local.repo_name
      app_name        = var.app_name
      container_image = local.container_image
    })
    
    clouddeploy_yaml = templatefile("${path.module}/templates/clouddeploy.yaml.tpl", {
      project_id     = var.project_id
      zone           = var.zone
      pipeline_name  = local.pipeline_name
      dev_cluster    = google_container_cluster.dev_cluster.name
      staging_cluster = google_container_cluster.staging_cluster.name
      prod_cluster   = google_container_cluster.prod_cluster.name
    })
    
    cloudbuild_yaml = templatefile("${path.module}/templates/cloudbuild.yaml.tpl", {
      project_id     = var.project_id
      region         = var.region
      repo_name      = local.repo_name
      pipeline_name  = local.pipeline_name
      bucket_name    = local.bucket_name
      app_name       = var.app_name
    })
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    note = "Costs are estimates and may vary based on usage patterns"
    gke_clusters = {
      dev_cluster = "~$73/month (1 node, e2-standard-2, preemptible)"
      staging_cluster = "~$73/month (1 node, e2-standard-2)"
      prod_cluster = "~$218/month (3 nodes, e2-standard-4)"
    }
    storage = {
      artifact_registry = "~$5/month (10GB storage)"
      cloud_storage = "~$2/month (10GB storage)"
    }
    other_services = {
      cloud_deploy = "Free tier available"
      cloud_build = "$0.003/minute (first 120 minutes/day free)"
    }
    total_estimate = "~$350-400/month"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    workload_identity_enabled = var.enable_workload_identity
    network_policy_enabled    = var.enable_network_policy
    shielded_nodes_enabled    = true
    private_cluster_enabled   = var.gke_prod_config.enable_private_nodes
    uniform_bucket_access     = true
    
    service_accounts_created = var.create_service_accounts
    
    recommended_next_steps = [
      "Configure Binary Authorization for container image security",
      "Enable Pod Security Standards",
      "Configure network policies for workload isolation",
      "Enable audit logging for compliance requirements"
    ]
  }
}