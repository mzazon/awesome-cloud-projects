# ==============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ==============================================================================

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
  description = "Random suffix used for resource naming uniqueness"
  value       = local.resource_suffix
}

# ==============================================================================
# CLOUD KMS OUTPUTS
# ==============================================================================

output "kms_keyring_name" {
  description = "Name of the Cloud KMS key ring for traffic encryption"
  value       = google_kms_key_ring.traffic_keyring.name
}

output "kms_keyring_id" {
  description = "Full resource ID of the Cloud KMS key ring"
  value       = google_kms_key_ring.traffic_keyring.id
}

output "kms_encryption_key_name" {
  description = "Name of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.traffic_encryption_key.name
}

output "kms_encryption_key_id" {
  description = "Full resource ID of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.traffic_encryption_key.id
  sensitive   = true
}

# ==============================================================================
# CONFIDENTIAL VM OUTPUTS
# ==============================================================================

output "confidential_vm_name" {
  description = "Name of the Confidential VM instance"
  value       = google_compute_instance.confidential_processor.name
}

output "confidential_vm_id" {
  description = "Full resource ID of the Confidential VM instance"
  value       = google_compute_instance.confidential_processor.id
}

output "confidential_vm_self_link" {
  description = "Self-link of the Confidential VM instance"
  value       = google_compute_instance.confidential_processor.self_link
}

output "confidential_vm_internal_ip" {
  description = "Internal IP address of the Confidential VM"
  value       = google_compute_instance.confidential_processor.network_interface[0].network_ip
}

output "confidential_vm_external_ip" {
  description = "External IP address of the Confidential VM (if assigned)"
  value       = length(google_compute_instance.confidential_processor.network_interface[0].access_config) > 0 ? google_compute_instance.confidential_processor.network_interface[0].access_config[0].nat_ip : null
}

output "confidential_vm_zone" {
  description = "Zone where the Confidential VM is deployed"
  value       = google_compute_instance.confidential_processor.zone
}

output "confidential_compute_type" {
  description = "Type of Confidential Computing technology enabled"
  value       = var.confidential_compute_type
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "service_account_email" {
  description = "Email address of the service account used by Confidential VM"
  value       = google_service_account.confidential_processor.email
}

output "service_account_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.confidential_processor.unique_id
}

output "service_account_name" {
  description = "Name of the service account"
  value       = google_service_account.confidential_processor.account_id
}

# ==============================================================================
# LOAD BALANCER OUTPUTS
# ==============================================================================

output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_forwarding_rule.secure_traffic_forwarding.ip_address
}

output "load_balancer_port" {
  description = "Port used by the load balancer"
  value       = google_compute_global_forwarding_rule.secure_traffic_forwarding.port_range
}

output "load_balancer_url" {
  description = "URL endpoint for the load balancer"
  value       = var.enable_ssl_certificate ? "https://${google_compute_global_forwarding_rule.secure_traffic_forwarding.ip_address}" : "http://${google_compute_global_forwarding_rule.secure_traffic_forwarding.ip_address}"
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.traffic_backend.name
}

output "backend_service_self_link" {
  description = "Self-link of the backend service"
  value       = google_compute_backend_service.traffic_backend.self_link
}

output "health_check_name" {
  description = "Name of the health check for traffic processing service"
  value       = google_compute_health_check.traffic_processor_health.name
}

# ==============================================================================
# SSL CERTIFICATE OUTPUTS
# ==============================================================================

output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (if enabled)"
  value       = var.enable_ssl_certificate ? google_compute_managed_ssl_certificate.secure_traffic_cert[0].name : null
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = var.enable_ssl_certificate ? var.ssl_certificate_domains : []
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate"
  value       = var.enable_ssl_certificate ? google_compute_managed_ssl_certificate.secure_traffic_cert[0].managed[0].status : null
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "storage_bucket_name" {
  description = "Name of the secure storage bucket"
  value       = google_storage_bucket.secure_traffic_data.name
}

output "storage_bucket_url" {
  description = "URL of the secure storage bucket"
  value       = google_storage_bucket.secure_traffic_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the secure storage bucket"
  value       = google_storage_bucket.secure_traffic_data.self_link
}

output "storage_bucket_location" {
  description = "Location of the secure storage bucket"
  value       = google_storage_bucket.secure_traffic_data.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the secure storage bucket"
  value       = google_storage_bucket.secure_traffic_data.storage_class
}

# ==============================================================================
# NETWORK SECURITY OUTPUTS
# ==============================================================================

output "firewall_rule_name" {
  description = "Name of the firewall rule allowing traffic processor access"
  value       = google_compute_firewall.allow_traffic_processor.name
}

output "allowed_source_ranges" {
  description = "CIDR ranges allowed to access the traffic processor"
  value       = var.allowed_source_ranges
}

output "traffic_processor_port" {
  description = "Port used by the traffic processing service"
  value       = var.traffic_processor_port
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_monitoring
}

output "logging_enabled" {
  description = "Whether Cloud Logging is enabled"
  value       = var.enable_logging
}

output "alert_policy_name" {
  description = "Name of the monitoring alert policy (if enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.vm_health[0].display_name : null
}

# ==============================================================================
# CONNECTION AND TESTING OUTPUTS
# ==============================================================================

output "ssh_command" {
  description = "Command to SSH into the Confidential VM"
  value       = "gcloud compute ssh ${google_compute_instance.confidential_processor.name} --zone=${var.zone} --project=${var.project_id}"
}

output "curl_test_command" {
  description = "Command to test the load balancer endpoint"
  value = var.enable_ssl_certificate ? (
    "curl -k -v https://${google_compute_global_forwarding_rule.secure_traffic_forwarding.ip_address} -H \"Host: ${var.ssl_certificate_domains[0]}\" --connect-timeout 10"
  ) : (
    "curl -v http://${google_compute_global_forwarding_rule.secure_traffic_forwarding.ip_address} --connect-timeout 10"
  )
}

output "health_check_test_command" {
  description = "Command to test the health check endpoint"
  value       = "gcloud compute ssh ${google_compute_instance.confidential_processor.name} --zone=${var.zone} --project=${var.project_id} --command=\"sudo systemctl status traffic-processor\""
}

# ==============================================================================
# SECURITY VERIFICATION OUTPUTS
# ==============================================================================

output "confidential_vm_verification_commands" {
  description = "Commands to verify Confidential VM security features"
  value = {
    check_confidential_config = "gcloud compute instances describe ${google_compute_instance.confidential_processor.name} --zone=${var.zone} --format=\"value(confidentialInstanceConfig)\""
    check_tee_capabilities   = "gcloud compute ssh ${google_compute_instance.confidential_processor.name} --zone=${var.zone} --command=\"dmesg | grep -i 'sev\\|tee\\|amd'\""
  }
}

output "kms_test_commands" {
  description = "Commands to test KMS encryption functionality"
  value = {
    encrypt_test = "echo 'test-sensitive-data' | gcloud kms encrypt --key=${local.key_name} --keyring=${local.keyring_name} --location=${var.region} --plaintext-file=- --ciphertext-file=test.encrypted"
    decrypt_test = "gcloud kms decrypt --key=${local.key_name} --keyring=${local.keyring_name} --location=${var.region} --ciphertext-file=test.encrypted --plaintext-file=-"
  }
}

# ==============================================================================
# CLEANUP OUTPUTS
# ==============================================================================

output "cleanup_commands" {
  description = "Commands for cleaning up resources (use with caution)"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup = [
      "# Delete forwarding rule",
      "gcloud compute forwarding-rules delete ${local.forwarding_rule_name} --global --quiet",
      "# Delete Confidential VM",
      "gcloud compute instances delete ${local.vm_name} --zone=${var.zone} --quiet",
      "# Delete storage bucket",
      "gsutil -m rm -r gs://${local.bucket_name}",
      "# Note: KMS keys have mandatory retention periods"
    ]
  }
}

# ==============================================================================
# COST ESTIMATION OUTPUTS
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for deployed resources (approximate)"
  value = {
    confidential_vm     = "~$150-200 (n2d-standard-4 with Confidential Computing)"
    load_balancer      = "~$20-30 (Application Load Balancer)"
    storage            = "~$5-10 (50GB bucket + egress)"
    kms                = "~$1-5 (key operations)"
    networking         = "~$5-10 (firewall rules, IPs)"
    monitoring         = "~$5-10 (Cloud Monitoring/Logging)"
    total_estimated    = "~$186-265 USD/month"
    note              = "Costs vary based on usage, region, and actual resource consumption"
  }
}