# Project and Region Information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were created"
  value       = var.zone
}

# Resource Naming and Identification
output "resource_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = local.name_suffix
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Storage Resources
output "assessment_reports_bucket" {
  description = "Cloud Storage bucket for storing infrastructure assessment reports"
  value = {
    name = google_storage_bucket.assessment_reports.name
    url  = google_storage_bucket.assessment_reports.url
  }
}

output "remediation_templates_bucket" {
  description = "Cloud Storage bucket for storing remediation configuration templates"
  value = {
    name = google_storage_bucket.remediation_templates.name
    url  = google_storage_bucket.remediation_templates.url
  }
}

# GKE Cluster Information
output "gke_cluster" {
  description = "GKE cluster information for infrastructure assessment target"
  value = var.cluster_enable_autopilot ? {
    name              = google_container_cluster.autopilot_cluster[0].name
    location          = google_container_cluster.autopilot_cluster[0].location
    endpoint          = google_container_cluster.autopilot_cluster[0].endpoint
    cluster_ca_certificate = google_container_cluster.autopilot_cluster[0].master_auth[0].cluster_ca_certificate
    type              = "autopilot"
    } : {
    name              = google_container_cluster.assessment_cluster[0].name
    location          = google_container_cluster.assessment_cluster[0].location
    endpoint          = google_container_cluster.assessment_cluster[0].endpoint
    cluster_ca_certificate = google_container_cluster.assessment_cluster[0].master_auth[0].cluster_ca_certificate
    type              = "standard"
    node_count        = var.cluster_node_count
    machine_type      = var.cluster_machine_type
  }
}

output "kubectl_connection_command" {
  description = "Command to connect kubectl to the created GKE cluster"
  value = var.cluster_enable_autopilot ? (
    "gcloud container clusters get-credentials ${google_container_cluster.autopilot_cluster[0].name} --region=${google_container_cluster.autopilot_cluster[0].location} --project=${var.project_id}"
  ) : (
    "gcloud container clusters get-credentials ${google_container_cluster.assessment_cluster[0].name} --zone=${google_container_cluster.assessment_cluster[0].location} --project=${var.project_id}"
  )
}

# Pub/Sub Resources
output "pubsub_topics" {
  description = "Pub/Sub topics for event-driven health assessment architecture"
  value = {
    health_assessment_events = {
      name = google_pubsub_topic.health_assessment_events.name
      id   = google_pubsub_topic.health_assessment_events.id
    }
    health_monitoring_alerts = {
      name = google_pubsub_topic.health_monitoring_alerts.name
      id   = google_pubsub_topic.health_monitoring_alerts.id
    }
  }
}

output "pubsub_subscriptions" {
  description = "Pub/Sub subscriptions for deployment pipeline triggers"
  value = {
    health_deployment_trigger = {
      name = google_pubsub_subscription.health_deployment_trigger.name
      id   = google_pubsub_subscription.health_deployment_trigger.id
    }
  }
}

# Cloud Function Information
output "cloud_function" {
  description = "Cloud Function for processing health assessment results"
  value = {
    name                = google_cloudfunctions_function.assessment_processor.name
    trigger_bucket      = google_storage_bucket.assessment_reports.name
    service_account     = google_service_account.function_sa.email
    runtime            = var.function_runtime
    memory_mb          = var.function_memory_mb
    timeout_seconds    = var.function_timeout_seconds
  }
}

output "function_logs_command" {
  description = "Command to view Cloud Function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions_function.assessment_processor.name} --region=${var.region} --project=${var.project_id}"
}

# Cloud Deploy Pipeline Information
output "cloud_deploy_pipeline" {
  description = "Cloud Deploy delivery pipeline for infrastructure remediation"
  value = {
    name        = google_clouddeploy_delivery_pipeline.health_pipeline.name
    location    = google_clouddeploy_delivery_pipeline.health_pipeline.location
    uid         = google_clouddeploy_delivery_pipeline.health_pipeline.uid
  }
}

output "cloud_deploy_targets" {
  description = "Cloud Deploy targets for staging and production environments"
  value = {
    staging = {
      name     = google_clouddeploy_target.staging_target.name
      location = google_clouddeploy_target.staging_target.location
    }
    production = {
      name             = google_clouddeploy_target.production_target.name
      location         = google_clouddeploy_target.production_target.location
      require_approval = google_clouddeploy_target.production_target.require_approval
    }
  }
}

# Service Accounts
output "service_accounts" {
  description = "Service accounts created for infrastructure health assessment components"
  value = {
    cloud_function = {
      email       = google_service_account.function_sa.email
      unique_id   = google_service_account.function_sa.unique_id
      description = google_service_account.function_sa.description
    }
    cloud_deploy = {
      email       = google_service_account.deploy_sa.email
      unique_id   = google_service_account.deploy_sa.unique_id
      description = google_service_account.deploy_sa.description
    }
  }
}

# Monitoring and Alerting
output "monitoring_alert_policy" {
  description = "Cloud Monitoring alert policy for critical health issues"
  value = {
    name         = google_monitoring_alert_policy.critical_health_issues.name
    display_name = google_monitoring_alert_policy.critical_health_issues.display_name
    enabled      = google_monitoring_alert_policy.critical_health_issues.enabled
  }
}

output "notification_channel" {
  description = "Notification channel for health assessment alerts"
  value = var.notification_email != "" ? {
    name  = google_monitoring_notification_channel.email[0].name
    type  = google_monitoring_notification_channel.email[0].type
    email = var.notification_email
  } : null
}

output "logging_metric" {
  description = "Custom logging metric for tracking deployment success"
  value = {
    name   = google_logging_metric.deployment_success.name
    filter = google_logging_metric.deployment_success.filter
  }
}

# Network Resources (if private cluster enabled)
output "network_resources" {
  description = "Network resources created for private GKE cluster"
  value = var.enable_private_cluster ? {
    vpc_network = {
      name      = google_compute_network.vpc[0].name
      self_link = google_compute_network.vpc[0].self_link
    }
    subnet = {
      name         = google_compute_subnetwork.subnet[0].name
      cidr_range   = google_compute_subnetwork.subnet[0].ip_cidr_range
      pods_range   = "10.1.0.0/16"
      services_range = "10.2.0.0/20"
    }
  } : null
}

# Cloud Scheduler Information
output "assessment_scheduler" {
  description = "Cloud Scheduler job for triggering periodic health assessments"
  value = {
    name      = google_cloud_scheduler_job.assessment_trigger.name
    schedule  = google_cloud_scheduler_job.assessment_trigger.schedule
    time_zone = google_cloud_scheduler_job.assessment_trigger.time_zone
  }
}

# Assessment Configuration
output "assessment_configuration" {
  description = "Configuration settings for infrastructure health assessments"
  value = {
    schedule                    = var.assessment_schedule
    enable_security_assessment  = var.enable_security_assessment
    enable_performance_assessment = var.enable_performance_assessment
    enable_cost_assessment      = var.enable_cost_assessment
    alert_threshold            = var.alert_threshold_critical_issues
    storage_retention_days     = var.storage_retention_days
  }
}

# Commands for Manual Operations
output "useful_commands" {
  description = "Useful commands for managing the infrastructure health assessment system"
  value = {
    # Cloud Deploy commands
    list_pipelines = "gcloud deploy delivery-pipelines list --region=${var.region} --project=${var.project_id}"
    list_targets   = "gcloud deploy targets list --region=${var.region} --project=${var.project_id}"
    create_release = "gcloud deploy releases create test-release-001 --delivery-pipeline=${google_clouddeploy_delivery_pipeline.health_pipeline.name} --region=${var.region} --project=${var.project_id}"
    
    # Pub/Sub commands
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.health_assessment_events.name} --message='{\"test\":\"message\"}' --project=${var.project_id}"
    view_subscription   = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.health_deployment_trigger.name} --auto-ack --project=${var.project_id}"
    
    # Storage commands
    list_reports = "gsutil ls gs://${google_storage_bucket.assessment_reports.name}/"
    list_templates = "gsutil ls gs://${google_storage_bucket.remediation_templates.name}/"
    
    # Monitoring commands
    list_alert_policies = "gcloud alpha monitoring policies list --project=${var.project_id}"
    view_metrics       = "gcloud logging metrics list --project=${var.project_id}"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the infrastructure health assessment system"
  value = {
    description = "Cost estimates are approximate and depend on actual usage patterns"
    components = {
      gke_cluster = var.cluster_enable_autopilot ? 
        "Autopilot cluster: ~$72/month (0.10/hour per vCPU)" :
        "Standard cluster: ~$73/month (management fee) + ~$24/month per e2-medium node"
      cloud_function = "~$0.40/month per 1M invocations + $0.0000025/GB-second"
      cloud_storage  = "~$0.02/GB per month (Standard storage)"
      pub_sub       = "~$0.40/month per 1M messages"
      cloud_deploy  = "Free for first 5 targets, $10/month per additional target"
      monitoring    = "Free tier: 150 MB/month, then $0.2580/MB"
      cloud_scheduler = "Free tier: 3 jobs, then $0.10/job per month"
    }
    estimated_total = var.cluster_enable_autopilot ? 
      "$80-120/month (depending on cluster usage)" :
      "$100-150/month (depending on node count and usage)"
  }
}

# Security Information
output "security_configuration" {
  description = "Security features and recommendations for the infrastructure health assessment system"
  value = {
    enabled_features = [
      "Workload Identity for GKE",
      "Private cluster nodes (if enabled)",
      "Shielded GKE nodes",
      "Uniform bucket-level access for Cloud Storage",
      "Service account with least privilege permissions",
      "Network policy for GKE cluster",
      "Secure boot and integrity monitoring"
    ]
    recommendations = [
      "Regularly rotate service account keys",
      "Monitor Cloud Audit Logs for API access",
      "Review and update IAM permissions periodically",
      "Enable Binary Authorization for container images",
      "Configure network security policies",
      "Implement backup and disaster recovery procedures"
    ]
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Connect to GKE cluster: ${var.cluster_enable_autopilot ? 
      "gcloud container clusters get-credentials ${google_container_cluster.autopilot_cluster[0].name} --region=${google_container_cluster.autopilot_cluster[0].location} --project=${var.project_id}" :
      "gcloud container clusters get-credentials ${google_container_cluster.assessment_cluster[0].name} --zone=${google_container_cluster.assessment_cluster[0].location} --project=${var.project_id}"
    }",
    "2. Deploy sample workloads to the cluster for assessment testing",
    "3. Upload assessment report to trigger Cloud Function: gsutil cp test-report.json gs://${google_storage_bucket.assessment_reports.name}/",
    "4. Monitor Cloud Function logs: gcloud functions logs read ${google_cloudfunctions_function.assessment_processor.name} --region=${var.region}",
    "5. Create test release: gcloud deploy releases create test-release-001 --delivery-pipeline=${google_clouddeploy_delivery_pipeline.health_pipeline.name} --region=${var.region}",
    "6. Configure Workload Manager assessment rules and schedules",
    "7. Set up additional notification channels for alerts",
    "8. Customize remediation templates in the templates bucket"
  ]
}