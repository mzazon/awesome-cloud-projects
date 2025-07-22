# ============================================================================
# Outputs for Quantum-Safe Security Posture Management
# ============================================================================
# This file defines outputs that provide important information about the
# deployed quantum-safe security infrastructure for integration and monitoring.

# ============================================================================
# Project and Organization Information
# ============================================================================

output "project_id" {
  description = "GCP Project ID where quantum security infrastructure is deployed"
  value       = google_project.quantum_security.project_id
}

output "project_number" {
  description = "GCP Project number for programmatic access and service account configuration"
  value       = google_project.quantum_security.number
}

output "organization_id" {
  description = "GCP Organization ID where quantum security policies are applied"
  value       = var.organization_id
}

output "region" {
  description = "Primary GCP region for quantum security infrastructure"
  value       = var.region
}

output "zone" {
  description = "Primary GCP zone for resource placement"
  value       = var.zone
}

# ============================================================================
# KMS and Post-Quantum Cryptography Resources
# ============================================================================

output "kms_keyring_id" {
  description = "Full resource ID of the quantum-safe KMS keyring"
  value       = google_kms_key_ring.quantum_keyring.id
}

output "kms_keyring_name" {
  description = "Name of the quantum-safe KMS keyring"
  value       = google_kms_key_ring.quantum_keyring.name
}

output "ml_dsa_key_id" {
  description = "Resource ID of the ML-DSA-65 post-quantum cryptographic key"
  value       = google_kms_crypto_key.ml_dsa_key.id
}

output "ml_dsa_key_name" {
  description = "Name of the ML-DSA-65 post-quantum cryptographic key"
  value       = google_kms_crypto_key.ml_dsa_key.name
}

output "slh_dsa_key_id" {
  description = "Resource ID of the SLH-DSA-SHA2-128S post-quantum cryptographic key"
  value       = google_kms_crypto_key.slh_dsa_key.id
}

output "slh_dsa_key_name" {
  description = "Name of the SLH-DSA-SHA2-128S post-quantum cryptographic key"
  value       = google_kms_crypto_key.slh_dsa_key.name
}

output "post_quantum_algorithms" {
  description = "Post-quantum cryptography algorithms deployed for quantum resistance"
  value = {
    ml_dsa_algorithm  = var.pq_algorithms.ml_dsa
    slh_dsa_algorithm = var.pq_algorithms.slh_dsa
  }
}

output "key_rotation_period" {
  description = "Automatic key rotation period configured for cryptographic agility"
  value       = var.kms_key_rotation_period
}

# ============================================================================
# Service Account and IAM
# ============================================================================

output "quantum_security_service_account_email" {
  description = "Email address of the quantum security automation service account"
  value       = google_service_account.quantum_security_automation.email
}

output "quantum_security_service_account_id" {
  description = "Unique ID of the quantum security automation service account"
  value       = google_service_account.quantum_security_automation.unique_id
}

output "quantum_security_service_account_name" {
  description = "Full resource name of the quantum security automation service account"
  value       = google_service_account.quantum_security_automation.name
}

# ============================================================================
# Asset Inventory and Monitoring
# ============================================================================

output "crypto_asset_feed_name" {
  description = "Name of the Cloud Asset Inventory feed for cryptographic resources"
  value       = google_cloud_asset_organization_feed.crypto_assets_feed.feed_id
}

output "crypto_asset_topic_id" {
  description = "Pub/Sub topic ID for cryptographic asset change notifications"
  value       = google_pubsub_topic.crypto_asset_changes.id
}

output "crypto_asset_topic_name" {
  description = "Pub/Sub topic name for asset change notifications"
  value       = google_pubsub_topic.crypto_asset_changes.name
}

output "crypto_asset_subscription_id" {
  description = "Pub/Sub subscription ID for processing asset changes"
  value       = google_pubsub_subscription.crypto_asset_subscription.id
}

output "asset_types_tracked" {
  description = "List of asset types being tracked for quantum vulnerability assessment"
  value       = var.asset_types_to_track
}

# ============================================================================
# Storage Resources
# ============================================================================

output "crypto_inventory_bucket_name" {
  description = "Name of the storage bucket for cryptographic asset inventory exports"
  value       = google_storage_bucket.crypto_inventory.name
}

output "crypto_inventory_bucket_url" {
  description = "URL of the storage bucket for asset inventory exports"
  value       = google_storage_bucket.crypto_inventory.url
}

output "function_source_bucket_name" {
  description = "Name of the storage bucket for Cloud Functions source code"
  value       = google_storage_bucket.function_source.name
}

output "storage_encryption_key" {
  description = "KMS key used for storage bucket encryption"
  value       = google_kms_crypto_key.ml_dsa_key.id
}

# ============================================================================
# Cloud Functions and Automation
# ============================================================================

output "compliance_function_name" {
  description = "Name of the Cloud Function for automated compliance reporting"
  value       = google_cloudfunctions_function.quantum_compliance_report.name
}

output "compliance_function_url" {
  description = "HTTPS trigger URL for the compliance reporting function"
  value       = google_cloudfunctions_function.quantum_compliance_report.https_trigger_url
}

output "compliance_scheduler_name" {
  description = "Name of the Cloud Scheduler job for automated compliance reports"
  value       = google_cloud_scheduler_job.quantum_compliance_scheduler.name
}

output "compliance_schedule" {
  description = "Cron schedule for automated compliance report generation"
  value       = var.compliance_schedule
}

output "function_service_account" {
  description = "Service account used by Cloud Functions for secure operations"
  value       = google_service_account.quantum_security_automation.email
}

# ============================================================================
# Monitoring and Alerting
# ============================================================================

output "monitoring_dashboard_id" {
  description = "ID of the quantum security posture monitoring dashboard"
  value       = google_monitoring_dashboard.quantum_security_dashboard.id
}

output "security_alert_notification_channel" {
  description = "Notification channel for quantum security alerts"
  value       = google_monitoring_notification_channel.security_alerts.name
}

output "notification_email" {
  description = "Email address configured for security notifications"
  value       = var.notification_email
  sensitive   = true
}

output "quantum_vulnerability_alert_policy" {
  description = "Alert policy for quantum vulnerability detection"
  value       = google_monitoring_alert_policy.quantum_vulnerability_alerts.name
}

output "key_rotation_alert_policy" {
  description = "Alert policy for KMS key rotation compliance monitoring"
  value       = google_monitoring_alert_policy.key_rotation_compliance.name
}

# ============================================================================
# Organization Policies
# ============================================================================

output "organization_policies" {
  description = "Organization policies enforced for quantum security compliance"
  value = {
    os_login_enforced = var.enforce_os_login ? google_org_policy_policy.require_os_login[0].name : "Not enforced"
    service_account_keys_disabled = var.disable_service_account_keys ? google_org_policy_policy.disable_service_account_keys[0].name : "Not enforced"
    crypto_algorithms_restricted = google_org_policy_policy.restrict_crypto_algorithms.name
  }
}

output "quantum_security_policies" {
  description = "Summary of quantum security policies and their enforcement status"
  value = {
    post_quantum_crypto_required = true
    key_rotation_automated = true
    asset_inventory_enabled = true
    compliance_reporting_scheduled = true
    vulnerability_monitoring_active = true
  }
}

# ============================================================================
# Security and Compliance Summary
# ============================================================================

output "quantum_readiness_summary" {
  description = "Summary of quantum readiness implementation status"
  value = {
    post_quantum_keys_deployed = {
      ml_dsa_65 = google_kms_crypto_key.ml_dsa_key.name
      slh_dsa_sha2_128s = google_kms_crypto_key.slh_dsa_key.name
    }
    automatic_key_rotation = var.kms_key_rotation_period
    asset_tracking_enabled = true
    compliance_automation = true
    threat_monitoring = true
    organization_policies_enforced = var.enforce_os_login && var.disable_service_account_keys
  }
}

output "security_command_center_integration" {
  description = "Security Command Center integration points and configuration"
  value = {
    project_id = google_project.quantum_security.project_id
    asset_feed_configured = true
    monitoring_enabled = true
    alert_policies_active = true
    compliance_reporting_enabled = true
  }
}

# ============================================================================
# Cost and Resource Information
# ============================================================================

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost for quantum security infrastructure in USD"
  value = {
    security_command_center_enterprise = "$500-2000 (organization-level)"
    cloud_kms_keys = "$1-10 per key per month"
    cloud_functions = "$0.0000004 per invocation"
    cloud_storage = "$0.020 per GB per month"
    cloud_monitoring = "$0.258 per million data points"
    estimated_total = "$500-2500 per month"
  }
}

output "resource_count_summary" {
  description = "Summary of resources created for quantum security infrastructure"
  value = {
    kms_keyrings = 1
    kms_keys = 2
    storage_buckets = 2
    cloud_functions = 1
    pubsub_topics = 2
    monitoring_dashboards = 1
    alert_policies = 2
    organization_policies = 3
    iam_service_accounts = 1
  }
}

# ============================================================================
# Integration and Next Steps
# ============================================================================

output "integration_endpoints" {
  description = "Key endpoints for integrating with external systems"
  value = {
    compliance_function_url = google_cloudfunctions_function.quantum_compliance_report.https_trigger_url
    asset_change_topic = google_pubsub_topic.crypto_asset_changes.id
    monitoring_dashboard_url = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.quantum_security_dashboard.id}?project=${google_project.quantum_security.project_id}"
    kms_keyring_url = "https://console.cloud.google.com/security/kms/keyring/manage/${google_kms_key_ring.quantum_keyring.location}/${google_kms_key_ring.quantum_keyring.name}?project=${google_project.quantum_security.project_id}"
  }
}

output "next_steps_guidance" {
  description = "Recommended next steps for quantum security implementation"
  value = [
    "1. Review and test post-quantum key operations using gcloud CLI",
    "2. Configure additional applications to use post-quantum cryptographic keys",
    "3. Set up custom dashboards for quantum vulnerability tracking",
    "4. Schedule regular quantum readiness assessments and compliance audits",
    "5. Implement quantum-safe algorithms in application-layer encryption",
    "6. Train security team on post-quantum cryptography best practices",
    "7. Establish incident response procedures for quantum security threats",
    "8. Monitor NIST updates for additional post-quantum algorithm standards"
  ]
}

# ============================================================================
# Verification Commands
# ============================================================================

output "verification_commands" {
  description = "Commands to verify quantum security infrastructure deployment"
  value = {
    check_kms_keys = "gcloud kms keys list --location=${var.region} --keyring=${google_kms_key_ring.quantum_keyring.name} --project=${google_project.quantum_security.project_id}"
    test_ml_dsa_signing = "echo 'test message' | gcloud kms asymmetric-sign --key=${google_kms_crypto_key.ml_dsa_key.name} --keyring=${google_kms_key_ring.quantum_keyring.name} --location=${var.region} --digest-algorithm=sha256 --input-file=- --project=${google_project.quantum_security.project_id}"
    check_asset_feed = "gcloud asset feeds describe ${google_cloud_asset_organization_feed.crypto_assets_feed.feed_id} --organization=${var.organization_id}"
    view_monitoring_dashboard = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.quantum_security_dashboard.id}?project=${google_project.quantum_security.project_id}"
    trigger_compliance_report = "curl -X GET '${google_cloudfunctions_function.quantum_compliance_report.https_trigger_url}'"
  }
}

# ============================================================================
# Documentation Links
# ============================================================================

output "documentation_links" {
  description = "Relevant documentation for quantum security implementation"
  value = {
    post_quantum_cryptography = "https://cloud.google.com/kms/docs/post-quantum-cryptography"
    security_command_center = "https://cloud.google.com/security-command-center/docs"
    cloud_asset_inventory = "https://cloud.google.com/asset-inventory/docs"
    kms_best_practices = "https://cloud.google.com/kms/docs/best-practices"
    nist_pqc_standards = "https://csrc.nist.gov/pqc-standardization"
    quantum_threat_timeline = "https://www.nist.gov/news-events/news/2022/07/nist-announces-first-four-quantum-resistant-cryptographic-algorithms"
  }
}