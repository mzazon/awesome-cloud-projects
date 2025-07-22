# Outputs for threat detection pipeline infrastructure
# This file provides important information about the deployed resources

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Network Infrastructure Outputs
output "vpc_network_name" {
  description = "Name of the VPC network created for threat detection"
  value       = google_compute_network.threat_detection_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network created for threat detection"
  value       = google_compute_network.threat_detection_vpc.id
}

output "vpc_network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.threat_detection_vpc.self_link
}

output "subnet_name" {
  description = "Name of the subnet created for compute resources"
  value       = google_compute_subnetwork.threat_detection_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the created subnet"
  value       = google_compute_subnetwork.threat_detection_subnet.ip_cidr_range
}

output "subnet_self_link" {
  description = "Self-link of the subnet"
  value       = google_compute_subnetwork.threat_detection_subnet.self_link
}

# Cloud IDS Outputs
output "ids_endpoint_name" {
  description = "Name of the Cloud IDS endpoint"
  value       = google_ids_endpoint.threat_detection_endpoint.name
}

output "ids_endpoint_id" {
  description = "ID of the Cloud IDS endpoint"
  value       = google_ids_endpoint.threat_detection_endpoint.id
}

output "ids_endpoint_service_attachment" {
  description = "Service attachment for the Cloud IDS endpoint (used for packet mirroring)"
  value       = google_ids_endpoint.threat_detection_endpoint.endpoint_forwarding_rule
}

output "ids_endpoint_severity" {
  description = "Severity level configured for the Cloud IDS endpoint"
  value       = google_ids_endpoint.threat_detection_endpoint.severity
}

# BigQuery Outputs
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for threat detection analytics"
  value       = google_bigquery_dataset.threat_detection.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.threat_detection.location
}

output "bigquery_findings_table_id" {
  description = "ID of the BigQuery table for Cloud IDS findings"
  value       = google_bigquery_table.ids_findings.table_id
}

output "bigquery_metrics_table_id" {
  description = "ID of the BigQuery table for threat metrics"
  value       = google_bigquery_table.threat_metrics.table_id
}

output "bigquery_summary_view_id" {
  description = "ID of the BigQuery view for threat analysis"
  value       = google_bigquery_table.threat_summary_view.table_id
}

output "bigquery_data_canvas_url" {
  description = "URL to access BigQuery Data Canvas for visual threat analytics"
  value       = "https://console.cloud.google.com/bigquery/canvas?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.threat_detection.dataset_id}!3s${google_bigquery_table.ids_findings.table_id}"
}

# Pub/Sub Outputs
output "pubsub_findings_topic_name" {
  description = "Name of the Pub/Sub topic for Cloud IDS findings"
  value       = google_pubsub_topic.threat_detection_findings.name
}

output "pubsub_findings_topic_id" {
  description = "ID of the Pub/Sub topic for Cloud IDS findings"
  value       = google_pubsub_topic.threat_detection_findings.id
}

output "pubsub_alerts_topic_name" {
  description = "Name of the Pub/Sub topic for security alerts"
  value       = google_pubsub_topic.security_alerts.name
}

output "pubsub_alerts_topic_id" {
  description = "ID of the Pub/Sub topic for security alerts"
  value       = google_pubsub_topic.security_alerts.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for processing findings"
  value       = google_pubsub_subscription.process_findings_sub.name
}

# Cloud Functions Outputs
output "threat_processor_function_name" {
  description = "Name of the Cloud Function for processing threat findings"
  value       = google_cloudfunctions_function.process_threat_finding.name
}

output "threat_processor_function_url" {
  description = "URL of the threat processing Cloud Function"
  value       = google_cloudfunctions_function.process_threat_finding.https_trigger_url
}

output "alert_processor_function_name" {
  description = "Name of the Cloud Function for processing security alerts"
  value       = google_cloudfunctions_function.process_security_alert.name
}

output "alert_processor_function_url" {
  description = "URL of the alert processing Cloud Function"
  value       = google_cloudfunctions_function.process_security_alert.https_trigger_url
}

# Test VM Outputs (conditional)
output "web_server_name" {
  description = "Name of the test web server VM (if created)"
  value       = var.create_test_vms ? google_compute_instance.web_server[0].name : "Not created"
}

output "web_server_internal_ip" {
  description = "Internal IP address of the test web server VM (if created)"
  value       = var.create_test_vms ? google_compute_instance.web_server[0].network_interface[0].network_ip : "Not created"
}

output "web_server_external_ip" {
  description = "External IP address of the test web server VM (if created)"
  value       = var.create_test_vms ? google_compute_instance.web_server[0].network_interface[0].access_config[0].nat_ip : "Not created"
}

output "app_server_name" {
  description = "Name of the test application server VM (if created)"
  value       = var.create_test_vms ? google_compute_instance.app_server[0].name : "Not created"
}

output "app_server_internal_ip" {
  description = "Internal IP address of the test application server VM (if created)"
  value       = var.create_test_vms ? google_compute_instance.app_server[0].network_interface[0].network_ip : "Not created"
}

# Packet Mirroring Outputs (conditional)
output "packet_mirroring_policy_name" {
  description = "Name of the packet mirroring policy (if enabled)"
  value       = var.enable_packet_mirroring ? google_compute_packet_mirroring.threat_detection_mirroring[0].name : "Not enabled"
}

output "packet_mirroring_policy_id" {
  description = "ID of the packet mirroring policy (if enabled)"
  value       = var.enable_packet_mirroring ? google_compute_packet_mirroring.threat_detection_mirroring[0].id : "Not enabled"
}

# Cloud Storage Outputs
output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# Monitoring and Management URLs
output "cloud_console_project_url" {
  description = "URL to the Google Cloud Console for this project"
  value       = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
}

output "cloud_ids_console_url" {
  description = "URL to the Cloud IDS console for monitoring threat detection"
  value       = "https://console.cloud.google.com/net-security/ids/endpoints?project=${var.project_id}"
}

output "bigquery_console_url" {
  description = "URL to the BigQuery console for data analysis"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
}

output "cloud_functions_console_url" {
  description = "URL to the Cloud Functions console for monitoring serverless processing"
  value       = "https://console.cloud.google.com/functions/list?project=${var.project_id}"
}

output "pubsub_console_url" {
  description = "URL to the Pub/Sub console for monitoring message processing"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

output "compute_console_url" {
  description = "URL to the Compute Engine console for VM management"
  value       = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
}

# Testing and Validation Commands
output "sample_pubsub_test_command" {
  description = "Sample command to test Pub/Sub message publishing for threat findings"
  value = "gcloud pubsub topics publish ${google_pubsub_topic.threat_detection_findings.name} --message='{\"finding_id\":\"test-001\",\"severity\":\"HIGH\",\"threat_type\":\"Test Threat\",\"source_ip\":\"192.0.2.100\",\"destination_ip\":\"10.0.1.1\",\"protocol\":\"TCP\",\"details\":{\"test\":true}}' --project=${var.project_id}"
}

output "sample_bq_query_command" {
  description = "Sample BigQuery command to query threat detection data"
  value = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as total_findings, severity, threat_type FROM `${var.project_id}.${google_bigquery_dataset.threat_detection.dataset_id}.${google_bigquery_table.ids_findings.table_id}` GROUP BY severity, threat_type ORDER BY total_findings DESC' --project_id=${var.project_id}"
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the threat detection infrastructure"
  value = {
    cloud_ids_endpoint = "~$350-450/month (varies by traffic volume)"
    bigquery_storage   = "~$20-100/month (varies by data volume)"
    cloud_functions    = "~$10-50/month (varies by invocations)"
    compute_vms        = var.create_test_vms ? "~$40-80/month (if test VMs are created)" : "$0 (no test VMs)"
    networking         = "~$10-30/month (VPC, load balancing)"
    storage            = "~$5-15/month (function source, logs)"
    total_estimated    = "~$435-725/month (excluding data transfer costs)"
  }
}

# Next Steps and Usage Information
output "getting_started_guide" {
  description = "Getting started guide for using the threat detection pipeline"
  value = {
    step_1 = "Access BigQuery Data Canvas at: ${local.bigquery_data_canvas_url}"
    step_2 = "Query threat data using natural language or SQL in BigQuery"
    step_3 = "Monitor Cloud IDS findings in the Cloud Console"
    step_4 = "Test the pipeline by publishing messages to Pub/Sub topics"
    step_5 = "Review Cloud Functions logs for processing status"
    step_6 = "Set up monitoring and alerting based on your security requirements"
  }
}

# Define the BigQuery Data Canvas URL as a local value
locals {
  bigquery_data_canvas_url = "https://console.cloud.google.com/bigquery/canvas?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.threat_detection.dataset_id}!3s${google_bigquery_table.ids_findings.table_id}"
}