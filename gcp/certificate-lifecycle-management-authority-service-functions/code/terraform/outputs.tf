# ==============================================================================
# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# Output Values
# ==============================================================================

# ==============================================================================
# Project and Resource Identification Outputs
# ==============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = local.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for the deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
  sensitive   = false
}

# ==============================================================================
# Certificate Authority Infrastructure Outputs
# ==============================================================================

output "ca_pool_name" {
  description = "Name of the Certificate Authority pool"
  value       = google_privateca_ca_pool.enterprise_ca_pool.name
}

output "ca_pool_id" {
  description = "Full resource ID of the Certificate Authority pool"
  value       = google_privateca_ca_pool.enterprise_ca_pool.id
}

output "ca_pool_tier" {
  description = "Tier of the Certificate Authority pool"
  value       = google_privateca_ca_pool.enterprise_ca_pool.tier
}

output "root_ca_name" {
  description = "Name of the root Certificate Authority"
  value       = google_privateca_certificate_authority.root_ca_enable.certificate_authority_id
}

output "root_ca_id" {
  description = "Full resource ID of the root Certificate Authority"
  value       = google_privateca_certificate_authority.root_ca_enable.id
}

output "root_ca_state" {
  description = "Current state of the root Certificate Authority"
  value       = google_privateca_certificate_authority.root_ca_enable.state
}

output "subordinate_ca_name" {
  description = "Name of the subordinate Certificate Authority"
  value       = google_privateca_certificate_authority.sub_ca_enable.certificate_authority_id
}

output "subordinate_ca_id" {
  description = "Full resource ID of the subordinate Certificate Authority"
  value       = google_privateca_certificate_authority.sub_ca_enable.id
}

output "subordinate_ca_state" {
  description = "Current state of the subordinate Certificate Authority"
  value       = google_privateca_certificate_authority.sub_ca_enable.state
}

output "certificate_template_name" {
  description = "Name of the certificate template for web servers"
  value       = google_privateca_certificate_template.web_server_template.name
}

output "certificate_template_id" {
  description = "Full resource ID of the certificate template"
  value       = google_privateca_certificate_template.web_server_template.id
}

# ==============================================================================
# Service Account and IAM Outputs
# ==============================================================================

output "service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.cert_automation.email
}

output "service_account_id" {
  description = "Full resource ID of the service account"
  value       = google_service_account.cert_automation.id
}

output "service_account_unique_id" {
  description = "Unique ID of the service account"
  value       = google_service_account.cert_automation.unique_id
}

# ==============================================================================
# Cloud Functions Outputs
# ==============================================================================

output "monitor_function_name" {
  description = "Name of the certificate monitoring Cloud Function"
  value       = google_cloudfunctions2_function.cert_monitor.name
}

output "monitor_function_url" {
  description = "HTTP trigger URL for the certificate monitoring function"
  value       = google_cloudfunctions2_function.cert_monitor.service_config[0].uri
  sensitive   = true
}

output "renewal_function_name" {
  description = "Name of the certificate renewal Cloud Function"
  value       = google_cloudfunctions2_function.cert_renewal.name
}

output "renewal_function_url" {
  description = "HTTP trigger URL for the certificate renewal function"
  value       = google_cloudfunctions2_function.cert_renewal.service_config[0].uri
  sensitive   = true
}

output "revocation_function_name" {
  description = "Name of the certificate revocation Cloud Function"
  value       = google_cloudfunctions2_function.cert_revocation.name
}

output "revocation_function_url" {
  description = "HTTP trigger URL for the certificate revocation function"
  value       = google_cloudfunctions2_function.cert_revocation.service_config[0].uri
  sensitive   = true
}

# ==============================================================================
# Cloud Scheduler Outputs
# ==============================================================================

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for certificate monitoring"
  value       = google_cloud_scheduler_job.cert_monitoring.name
}

output "scheduler_job_id" {
  description = "Full resource ID of the Cloud Scheduler job"
  value       = google_cloud_scheduler_job.cert_monitoring.id
}

output "monitoring_schedule" {
  description = "Cron schedule for certificate monitoring"
  value       = google_cloud_scheduler_job.cert_monitoring.schedule
}

output "monitoring_timezone" {
  description = "Time zone for the monitoring schedule"
  value       = google_cloud_scheduler_job.cert_monitoring.time_zone
}

# ==============================================================================
# Storage Outputs
# ==============================================================================

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# ==============================================================================
# Monitoring and Alerting Outputs
# ==============================================================================

output "monitor_alert_policy_name" {
  description = "Name of the alerting policy for certificate monitor function errors"
  value       = google_monitoring_alert_policy.cert_monitor_errors.display_name
}

output "monitor_alert_policy_id" {
  description = "ID of the alerting policy for certificate monitor function errors"
  value       = google_monitoring_alert_policy.cert_monitor_errors.id
}

output "renewal_alert_policy_name" {
  description = "Name of the alerting policy for certificate renewal function errors"
  value       = google_monitoring_alert_policy.cert_renewal_errors.display_name
}

output "renewal_alert_policy_id" {
  description = "ID of the alerting policy for certificate renewal function errors"
  value       = google_monitoring_alert_policy.cert_renewal_errors.id
}

# ==============================================================================
# Certificate Configuration Outputs
# ==============================================================================

output "renewal_threshold_days" {
  description = "Number of days before expiration that triggers certificate renewal"
  value       = var.renewal_threshold_days
}

output "max_certificate_lifetime_days" {
  description = "Maximum lifetime allowed for issued certificates in days"
  value       = var.max_cert_lifetime_days
}

output "organization_name" {
  description = "Organization name used in certificate subjects"
  value       = var.organization_name
}

output "country_code" {
  description = "Country code used in certificate subjects"
  value       = var.country_code
}

# ==============================================================================
# URLs and Endpoints for Integration
# ==============================================================================

output "ca_pool_ca_certs_url" {
  description = "URL where CA certificates are published (if enabled)"
  value = var.enable_ca_cert_distribution ? "https://privateca-content-${random_id.suffix.hex}.googleapis.com/v1/projects/${local.project_id}/locations/${var.region}/caPools/${local.ca_pool_name}/cacerts" : null
}

output "ca_pool_crl_url" {
  description = "URL where Certificate Revocation Lists are published (if enabled)"
  value = var.enable_crl_distribution ? "https://privateca-content-${random_id.suffix.hex}.googleapis.com/v1/projects/${local.project_id}/locations/${var.region}/caPools/${local.ca_pool_name}/certificateRevocationLists" : null
}

# ==============================================================================
# Usage Instructions and Next Steps
# ==============================================================================

output "next_steps" {
  description = "Instructions for using the deployed certificate lifecycle management system"
  value = <<-EOT
    Certificate Lifecycle Management System has been successfully deployed!
    
    Next steps:
    1. Test certificate monitoring function:
       curl -X POST "${google_cloudfunctions2_function.cert_monitor.service_config[0].uri}" \
         -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
         -H "Content-Type: application/json" \
         -d '{"source":"manual_test","action":"monitor"}'
    
    2. Issue a test certificate:
       curl -X POST "${google_cloudfunctions2_function.cert_renewal.service_config[0].uri}" \
         -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
         -H "Content-Type: application/json" \
         -d '{"common_name":"test.example.com","validity_days":90}'
    
    3. Monitor the Cloud Scheduler job:
       gcloud scheduler jobs describe ${google_cloud_scheduler_job.cert_monitoring.name} --location=${var.region}
    
    4. View certificate monitoring logs:
       gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${local.monitor_function_name}" --limit=10
    
    5. Check alerting policies in Cloud Monitoring console:
       https://console.cloud.google.com/monitoring/alerting/policies
    
    Important URLs:
    - CA Pool: https://console.cloud.google.com/security/cas/pools/details/${var.region}/${local.ca_pool_name}
    - Functions: https://console.cloud.google.com/functions/list
    - Scheduler: https://console.cloud.google.com/cloudscheduler
    - Secret Manager: https://console.cloud.google.com/security/secret-manager
  EOT
}

output "certificate_issuance_example" {
  description = "Example commands for issuing certificates using the deployed infrastructure"
  value = <<-EOT
    To issue a certificate using the Certificate Authority Service:
    
    1. Create a certificate request:
       gcloud privateca certificates create test-cert-$(date +%s) \
         --issuer-pool=${local.ca_pool_name} \
         --issuer-location=${var.region} \
         --generate-key \
         --key-output-file=test-key.pem \
         --cert-output-file=test-cert.pem \
         --subject="CN=test.example.com,O=${var.organization_name},C=${var.country_code}" \
         --dns-san="test.example.com" \
         --dns-san="www.test.example.com"
    
    2. Or use the renewal function to automate issuance:
       curl -X POST "${google_cloudfunctions2_function.cert_renewal.service_config[0].uri}" \
         -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
         -H "Content-Type: application/json" \
         -d '{
           "common_name": "api.example.com",
           "validity_days": 365,
           "dns_sans": ["api.example.com", "www.api.example.com"]
         }'
    
    3. Revoke a certificate if compromised:
       curl -X POST "${google_cloudfunctions2_function.cert_revocation.service_config[0].uri}" \
         -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
         -H "Content-Type: application/json" \
         -d '{
           "certificate_name": "projects/${local.project_id}/locations/${var.region}/caPools/${local.ca_pool_name}/certificates/CERTIFICATE_ID",
           "revocation_reason": "KEY_COMPROMISE"
         }'
  EOT
}

# ==============================================================================
# Cost and Resource Summary
# ==============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = <<-EOT
    Estimated Monthly Costs (USD):
    
    Certificate Authority Service:
    - Enterprise CA Pool: ~$200/month (includes root and subordinate CAs)
    - Certificate issuance: $0.50 per certificate
    
    Cloud Functions:
    - Monitoring function: ~$0.10/month (based on daily executions)
    - Renewal function: ~$0.20/month (based on certificate renewals)
    - Revocation function: ~$0.05/month (infrequent usage)
    
    Cloud Scheduler: ~$0.10/month (1 daily job)
    Cloud Storage: ~$0.02/month (function source code)
    Cloud Monitoring: ~$0.50/month (metrics and alerts)
    Secret Manager: ~$0.06/month (certificate storage)
    
    Total Estimated: ~$201/month
    
    Note: Costs may vary based on actual usage patterns, certificate issuance frequency,
    and the number of certificates stored. DevOps tier CA pools cost ~$30/month but
    lack revocation capabilities.
  EOT
}

output "security_recommendations" {
  description = "Security recommendations for the deployed certificate lifecycle management system"
  value = <<-EOT
    Security Recommendations:
    
    1. Access Control:
       - Review and limit IAM permissions for the service account
       - Enable audit logging for all Certificate Authority operations
       - Implement network policies to restrict function access
    
    2. Monitoring:
       - Set up notification channels for alerting policies
       - Monitor certificate issuance patterns for anomalies
       - Review function logs regularly for security events
    
    3. Certificate Management:
       - Implement certificate transparency logging
       - Set up automated backup of certificate templates
       - Regularly rotate service account keys
    
    4. Compliance:
       - Enable Cloud Asset Inventory for compliance tracking
       - Implement certificate usage auditing
       - Document certificate lifecycle procedures
    
    5. Disaster Recovery:
       - Backup CA certificates and configuration
       - Test certificate issuance failover procedures
       - Document recovery procedures for CA compromise
  EOT
}