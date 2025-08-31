# Outputs for GCP Real-time Video Collaboration with WebRTC and Cloud Run

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "cloud_run_service_name" {
  description = "The name of the Cloud Run service"
  value       = google_cloud_run_v2_service.webrtc_signaling.name
}

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.webrtc_signaling.uri
  sensitive   = false
}

output "cloud_run_service_id" {
  description = "The fully qualified ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.webrtc_signaling.id
}

output "cloud_run_service_status" {
  description = "The current status of the Cloud Run service"
  value       = google_cloud_run_v2_service.webrtc_signaling.terminal_condition
}

output "firestore_database_name" {
  description = "The name of the Firestore database for video rooms"
  value       = google_firestore_database.video_rooms.name
}

output "firestore_database_id" {
  description = "The ID of the Firestore database"
  value       = local.firestore_database_id
}

output "firestore_database_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.video_rooms.location_id
}

output "service_account_email" {
  description = "The email address of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.email
}

output "service_account_id" {
  description = "The ID of the service account used by Cloud Run"
  value       = google_service_account.cloud_run_sa.id
}

output "security_policy_name" {
  description = "The name of the Cloud Armor security policy"
  value       = google_compute_security_policy.webrtc_security_policy.name
}

output "security_policy_id" {
  description = "The ID of the Cloud Armor security policy"
  value       = google_compute_security_policy.webrtc_security_policy.id
}

output "monitoring_alert_policy_name" {
  description = "The name of the monitoring alert policy"
  value       = google_monitoring_alert_policy.cloud_run_health.display_name
}

output "iap_enabled" {
  description = "Whether Identity-Aware Proxy is enabled"
  value       = var.enable_iap
}

output "authorized_users" {
  description = "List of users authorized to access the application via IAP"
  value       = var.authorized_users
  sensitive   = true
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

output "environment_variables" {
  description = "Environment variables configured for the Cloud Run service"
  value       = local.container_env_vars
  sensitive   = true
}

output "application_urls" {
  description = "URLs to access the WebRTC video collaboration application"
  value = {
    primary     = google_cloud_run_v2_service.webrtc_signaling.uri
    health_check = "${google_cloud_run_v2_service.webrtc_signaling.uri}/health"
  }
}

output "deployment_commands" {
  description = "Commands to interact with the deployed infrastructure"
  value = {
    view_logs = "gcloud run services logs read ${google_cloud_run_v2_service.webrtc_signaling.name} --region=${var.region} --project=${var.project_id}"
    
    describe_service = "gcloud run services describe ${google_cloud_run_v2_service.webrtc_signaling.name} --region=${var.region} --project=${var.project_id}"
    
    update_traffic = "gcloud run services update-traffic ${google_cloud_run_v2_service.webrtc_signaling.name} --to-latest --region=${var.region} --project=${var.project_id}"
    
    scale_service = "gcloud run services update ${google_cloud_run_v2_service.webrtc_signaling.name} --min-instances=1 --max-instances=20 --region=${var.region} --project=${var.project_id}"
    
    view_firestore = "gcloud firestore databases describe ${local.firestore_database_id} --project=${var.project_id}"
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = {
    cloud_run = "Set min-instances to 0 for development to avoid charges when not in use"
    firestore = "Use Firestore rules to limit read/write operations and implement data cleanup"
    monitoring = "Set up budget alerts to monitor spending on Cloud Run requests and Firestore operations"
    images = "Use multi-stage Docker builds and optimize container images to reduce cold start times"
  }
}

output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    iap = "Enable Identity-Aware Proxy for production deployments to control access"
    firestore = "Configure Firestore security rules to restrict data access based on authentication"
    networking = "Consider using VPC connectors for additional network isolation"
    secrets = "Use Secret Manager for storing sensitive configuration values"
    cors = "Configure CORS policies appropriately for your client applications"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_build_container" = "Build and push your WebRTC signaling server container image to Google Container Registry or Artifact Registry"
    "2_update_service" = "Update the Cloud Run service with your actual container image using: terraform apply -var='container_image=gcr.io/${var.project_id}/webrtc-signaling:latest'"
    "3_configure_domain" = "Set up a custom domain and SSL certificate for production use"
    "4_enable_monitoring" = "Configure logging and monitoring for production observability"
    "5_setup_iap" = "Complete OAuth consent screen setup and enable IAP for secure access"
    "6_test_application" = "Test the video collaboration functionality with multiple users"
  }
}