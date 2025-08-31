# Output values for Privacy-Preserving Analytics with Confidential GKE and BigQuery
# These outputs provide important information for accessing and managing the deployed infrastructure

#####################################################################
# Project and Regional Information
#####################################################################

output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where zonal resources were deployed"  
  value       = var.zone
}

#####################################################################
# Encryption and Security
#####################################################################

output "kms_key_ring_name" {
  description = "Name of the Cloud KMS key ring for encryption"
  value       = google_kms_key_ring.analytics_keyring.name
}

output "kms_key_name" {
  description = "Name of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.analytics_key.name
}

output "kms_key_id" {
  description = "Full resource ID of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.analytics_key.id
}

output "kms_key_resource_name" {
  description = "Full resource name for the encryption key (for CLI usage)"
  value       = "projects/${var.project_id}/locations/${var.region}/keyRings/${google_kms_key_ring.analytics_keyring.name}/cryptoKeys/${google_kms_crypto_key.analytics_key.name}"
}

#####################################################################
# Networking
#####################################################################

output "vpc_network_name" {
  description = "Name of the VPC network created for the confidential cluster"
  value       = google_compute_network.confidential_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.confidential_vpc.id
}

output "subnet_name" {
  description = "Name of the subnet for the GKE cluster"
  value       = google_compute_subnetwork.confidential_subnet.name
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = google_compute_subnetwork.confidential_subnet.id
}

output "subnet_cidr" {
  description = "CIDR range of the primary subnet"
  value       = google_compute_subnetwork.confidential_subnet.ip_cidr_range
}

output "pods_cidr_range" {
  description = "CIDR range for Kubernetes pods"
  value       = var.pods_secondary_range_cidr
}

output "services_cidr_range" {
  description = "CIDR range for Kubernetes services"
  value       = var.services_secondary_range_cidr
}

#####################################################################
# Confidential GKE Cluster
#####################################################################

output "gke_cluster_name" {
  description = "Name of the Confidential GKE cluster"
  value       = google_container_cluster.confidential_cluster.name
}

output "gke_cluster_id" {
  description = "ID of the GKE cluster"
  value       = google_container_cluster.confidential_cluster.id
}

output "gke_cluster_endpoint" {
  description = "Endpoint for the GKE cluster API server"
  value       = google_container_cluster.confidential_cluster.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "Base64 encoded public certificate for the cluster"
  value       = google_container_cluster.confidential_cluster.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "Location (zone or region) of the GKE cluster"
  value       = google_container_cluster.confidential_cluster.location
}

output "gke_cluster_node_pool_name" {
  description = "Name of the confidential node pool"
  value       = google_container_node_pool.confidential_nodes.name
}

output "gke_cluster_service_account" {
  description = "Service account used by GKE cluster nodes"
  value       = google_service_account.gke_service_account.email
}

output "kubectl_connection_command" {
  description = "Command to connect kubectl to the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.confidential_cluster.name} --zone=${var.zone} --project=${var.project_id}"
}

#####################################################################
# BigQuery Dataset and Tables
#####################################################################

output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset with CMEK encryption"
  value       = google_bigquery_dataset.sensitive_analytics.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.sensitive_analytics.location
}

output "bigquery_dataset_full_name" {
  description = "Full name of the BigQuery dataset (project:dataset)"
  value       = "${var.project_id}:${google_bigquery_dataset.sensitive_analytics.dataset_id}"
}

output "patient_analytics_table" {
  description = "Full name of the patient analytics table"
  value       = var.create_sample_data ? "${var.project_id}.${google_bigquery_dataset.sensitive_analytics.dataset_id}.${google_bigquery_table.patient_analytics[0].table_id}" : "Not created (create_sample_data = false)"
}

output "privacy_analytics_view" {
  description = "Full name of the privacy analytics summary view"
  value       = "${var.project_id}.${google_bigquery_dataset.sensitive_analytics.dataset_id}.${google_bigquery_table.privacy_analytics_summary.table_id}"
}

output "compliance_report_view" {
  description = "Full name of the compliance report view"
  value       = "${var.project_id}.${google_bigquery_dataset.sensitive_analytics.dataset_id}.${google_bigquery_table.compliance_report.table_id}"
}

#####################################################################
# Cloud Storage
#####################################################################

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for ML training data"
  value       = google_storage_bucket.ml_training_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_training_data.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_training_data.location
}

#####################################################################
# Service Accounts
#####################################################################

output "gke_service_account_email" {
  description = "Email of the GKE service account"
  value       = google_service_account.gke_service_account.email
}

output "analytics_service_account_email" {
  description = "Email of the analytics service account"
  value       = google_service_account.analytics_service_account.email
}

output "workload_identity_enabled" {
  description = "Whether Workload Identity is enabled"
  value       = var.enable_workload_identity
}

#####################################################################
# Kubernetes Application
#####################################################################

output "kubernetes_namespace" {
  description = "Kubernetes namespace for analytics applications"
  value       = var.deploy_sample_application ? kubernetes_namespace.analytics[0].metadata[0].name : "Not deployed (deploy_sample_application = false)"
}

output "analytics_app_service_account" {
  description = "Kubernetes service account for analytics application"
  value       = var.deploy_sample_application && var.enable_workload_identity ? kubernetes_service_account.analytics_app[0].metadata[0].name : "Not created"
}

output "analytics_deployment_name" {
  description = "Name of the analytics application deployment"
  value       = var.deploy_sample_application ? kubernetes_deployment.analytics_app[0].metadata[0].name : "Not deployed"
}

#####################################################################
# Connection and Access Information
#####################################################################

output "bigquery_connection_examples" {
  description = "Example commands for connecting to BigQuery"
  value = {
    cli_query = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.sensitive_analytics.dataset_id}.privacy_analytics_summary` LIMIT 5'"
    web_console = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.sensitive_analytics.dataset_id}!3spatient_analytics"
  }
}

output "monitoring_urls" {
  description = "URLs for monitoring and observability"
  value = {
    gke_cluster = "https://console.cloud.google.com/kubernetes/clusters/details/${var.zone}/${google_container_cluster.confidential_cluster.name}/details?project=${var.project_id}"
    bigquery = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    cloud_kms = "https://console.cloud.google.com/security/kms/keys?project=${var.project_id}"
    storage = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.ml_training_data.name}?project=${var.project_id}"
  }
}

#####################################################################
# Validation Commands
#####################################################################

output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    check_confidential_nodes = "kubectl get nodes -o jsonpath='{.items[*].metadata.labels}' | grep -o 'cloud\\.google\\.com/gke-confidential-nodes[^,]*'"
    verify_encryption = "bq show --format=prettyjson ${var.project_id}:${google_bigquery_dataset.sensitive_analytics.dataset_id} | jq '.defaultEncryptionConfiguration'"
    check_kms_keys = "gcloud kms keys list --location=${var.region} --keyring=${google_kms_key_ring.analytics_keyring.name} --format='table(name,purpose,createTime)'"
    test_analytics = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.sensitive_analytics.dataset_id}.compliance_report`'"
  }
}

#####################################################################
# Cost and Resource Information
#####################################################################

output "deployed_resources_summary" {
  description = "Summary of key resources deployed"
  value = {
    confidential_gke_cluster = "1 cluster with ${var.node_count} confidential computing nodes"
    bigquery_dataset = "1 encrypted dataset with ${var.create_sample_data ? "sample data" : "no sample data"}"
    cloud_kms = "1 key ring with 1 encryption key"
    cloud_storage = "1 encrypted bucket"
    networking = "1 VPC with 1 subnet and NAT gateway"
    service_accounts = "2 service accounts with appropriate IAM bindings"
  }
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (may vary based on usage)"
  value = {
    confidential_gke_nodes = "~$150-300 (based on n2d-standard-4 instances)"
    bigquery_storage = "~$10-50 (based on data volume)"
    cloud_storage = "~$5-20 (based on data volume)"
    cloud_kms = "~$1-5 (based on key operations)"
    networking = "~$10-30 (NAT gateway and egress)"
    total_estimate = "~$176-405 per month"
    note = "Actual costs depend on usage patterns, data volume, and query frequency"
  }
}

#####################################################################
# Security and Compliance Information
#####################################################################

output "security_features_enabled" {
  description = "Security features enabled in this deployment"
  value = {
    confidential_computing = "Hardware-based memory encryption (AMD SEV/Intel TDX)"
    customer_managed_encryption = "CMEK encryption for all data at rest"
    workload_identity = var.enable_workload_identity ? "Enabled" : "Disabled"
    private_cluster = var.enable_private_nodes ? "Enabled" : "Disabled"
    network_policy = var.enable_network_policy ? "Enabled" : "Disabled"
    binary_authorization = var.enable_binary_authorization ? "Enabled" : "Disabled"
    shielded_gke_nodes = "Secure Boot and Integrity Monitoring enabled"
  }
}

output "compliance_capabilities" {
  description = "Compliance and privacy capabilities provided"
  value = {
    data_residency = "Data processed in ${var.region} with regional encryption"
    privacy_preservation = "K-anonymity and differential privacy support"
    audit_logging = "Cloud Audit Logs enabled for all resource access"
    encryption_at_rest = "CMEK encryption for BigQuery, Storage, and GKE disks"
    encryption_in_transit = "TLS 1.2+ for all service communications"
    encryption_in_use = "Hardware-based memory encryption during processing"
  }
}

#####################################################################
# Next Steps and Recommendations
#####################################################################

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Connect to the GKE cluster: ${output.validation_commands.value.check_confidential_nodes}",
    "2. Verify confidential computing: kubectl get nodes -o wide",
    "3. Test BigQuery encryption: ${output.validation_commands.value.verify_encryption}",
    "4. Run privacy analytics: ${output.validation_commands.value.test_analytics}",
    "5. Monitor applications: check logs in ${var.deploy_sample_application ? "privacy-analytics namespace" : "deploy sample app first"}",
    "6. Set up monitoring alerts for cost and security compliance",
    "7. Configure backup and disaster recovery procedures",
    "8. Review and customize privacy parameters based on your requirements"
  ]
}