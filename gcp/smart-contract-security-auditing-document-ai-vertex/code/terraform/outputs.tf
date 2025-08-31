# Outputs for smart contract security auditing infrastructure

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "bucket_name" {
  description = "Name of the Cloud Storage bucket for contract artifacts"
  value       = google_storage_bucket.contract_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.contract_bucket.url
}

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.contract_analyzer.name
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.contract_analyzer.service_config[0].uri
}

output "processor_id" {
  description = "ID of the Document AI processor"
  value       = google_document_ai_processor.contract_processor.name
}

output "processor_display_name" {
  description = "Display name of the Document AI processor"
  value       = google_document_ai_processor.contract_processor.display_name
}

output "function_service_account" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "upload_instructions" {
  description = "Instructions for uploading smart contracts for analysis"
  value = <<-EOT
    To analyze smart contracts, upload files to the following Cloud Storage locations:
    
    Smart Contract Files:
    gsutil cp your_contract.sol gs://${google_storage_bucket.contract_bucket.name}/contracts/
    
    Contract Documentation:
    gsutil cp your_documentation.md gs://${google_storage_bucket.contract_bucket.name}/documentation/
    
    View Audit Reports:
    gsutil ls gs://${google_storage_bucket.contract_bucket.name}/audit-reports/
    gsutil cp gs://${google_storage_bucket.contract_bucket.name}/audit-reports/your_contract_security_audit.json ./
  EOT
}

output "sample_contract_location" {
  description = "Location of the sample vulnerable contract for testing"
  value       = "gs://${google_storage_bucket.contract_bucket.name}/contracts/sample_vulnerable_contract.sol"
}

output "monitoring_commands" {
  description = "Commands to monitor the security analysis pipeline"
  value = <<-EOT
    Monitor Cloud Function logs:
    gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${google_cloudfunctions2_function.contract_analyzer.name}" --limit=10 --format="value(timestamp,severity,textPayload)"
    
    Check Document AI processor status:
    gcloud documentai processors list --location=${var.region} --format="table(name,displayName,state)"
    
    List generated audit reports:
    gsutil ls gs://${google_storage_bucket.contract_bucket.name}/audit-reports/
  EOT
}

output "vertex_ai_model" {
  description = "Vertex AI model used for contract analysis"
  value       = var.vertex_ai_model
}

output "notification_topic" {
  description = "Pub/Sub topic for audit notifications (if enabled)"
  value       = var.notification_email != "" ? google_pubsub_topic.audit_notifications[0].name : "Not configured"
}

output "estimated_costs" {
  description = "Estimated monthly costs for different usage levels"
  value = <<-EOT
    Estimated monthly costs (USD):
    
    Low Usage (10 contracts/month):
    - Document AI: $5-10
    - Vertex AI (Gemini): $3-7
    - Cloud Functions: $1-3
    - Cloud Storage: $1-2
    Total: $10-22/month
    
    Medium Usage (100 contracts/month):
    - Document AI: $15-30
    - Vertex AI (Gemini): $20-40
    - Cloud Functions: $5-10
    - Cloud Storage: $2-5
    Total: $42-85/month
    
    High Usage (1000 contracts/month):
    - Document AI: $50-100
    - Vertex AI (Gemini): $150-300
    - Cloud Functions: $15-30
    - Cloud Storage: $5-15
    Total: $220-445/month
    
    Note: Costs may vary based on contract complexity and analysis depth.
  EOT
}

output "security_considerations" {
  description = "Important security considerations for the deployed infrastructure"
  value = <<-EOT
    Security Best Practices Implemented:
    
    1. Service Account: Dedicated service account with minimal required permissions
    2. IAM Roles: Least privilege access for Document AI, Vertex AI, and Storage
    3. Bucket Access: Uniform bucket-level access control enabled
    4. Versioning: Object versioning enabled for audit trail compliance
    5. Encryption: Data encrypted at rest and in transit by default
    
    Additional Recommendations:
    - Regularly review and rotate service account keys
    - Monitor access logs and audit trails
    - Implement VPC Service Controls for enhanced security
    - Set up alerting for unusual activity patterns
    - Consider using Customer-Managed Encryption Keys (CMEK) for sensitive data
  EOT
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = <<-EOT
    Next Steps:
    
    1. Test the pipeline with the sample contract:
       gsutil cp gs://${google_storage_bucket.contract_bucket.name}/contracts/sample_vulnerable_contract.sol ./
       # The function will automatically process and generate an audit report
    
    2. Upload your own smart contracts:
       gsutil cp your_contract.sol gs://${google_storage_bucket.contract_bucket.name}/contracts/
    
    3. Monitor processing:
       gcloud logging read "resource.type=cloud_function" --limit=5
    
    4. Download audit reports:
       gsutil ls gs://${google_storage_bucket.contract_bucket.name}/audit-reports/
       gsutil cp gs://${google_storage_bucket.contract_bucket.name}/audit-reports/your_contract_security_audit.json ./
    
    5. Customize the analysis:
       - Modify the Vertex AI prompt in the Cloud Function for specific requirements
       - Add custom vulnerability patterns or compliance frameworks
       - Integrate with your CI/CD pipeline for automated security checks
  EOT
}