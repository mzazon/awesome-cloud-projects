# =============================================================================
# TERRAFORM OUTPUTS
# =============================================================================
# Output values for verification, testing, and integration with other systems

# Database Information
output "database_instance_name" {
  description = "Name of the Cloud SQL database instance"
  value       = google_sql_database_instance.business_process_db.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.business_process_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = var.enable_private_services ? google_sql_database_instance.business_process_db.private_ip_address : null
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = var.enable_private_services ? null : google_sql_database_instance.business_process_db.public_ip_address
}

output "database_name" {
  description = "Name of the business processes database"
  value       = google_sql_database.business_processes_db.name
}

output "database_password" {
  description = "Password for the database postgres user"
  value       = random_password.db_password.result
  sensitive   = true
}

# Cloud Functions Information
output "approval_function_name" {
  description = "Name of the approval processing Cloud Function"
  value       = google_cloudfunctions2_function.approval_function.name
}

output "approval_function_url" {
  description = "URL of the approval processing Cloud Function"
  value       = google_cloudfunctions2_function.approval_function.service_config[0].uri
}

output "notification_function_name" {
  description = "Name of the notification Cloud Function"
  value       = google_cloudfunctions2_function.notification_function.name
}

output "notification_function_url" {
  description = "URL of the notification Cloud Function"
  value       = google_cloudfunctions2_function.notification_function.service_config[0].uri
}

output "agent_function_name" {
  description = "Name of the AI agent Cloud Function"
  value       = google_cloudfunctions2_function.agent_function.name
}

output "agent_function_url" {
  description = "URL of the AI agent Cloud Function"
  value       = google_cloudfunctions2_function.agent_function.service_config[0].uri
}

# Workflow Information
output "workflow_name" {
  description = "Name of the business process Cloud Workflow"
  value       = google_workflows_workflow.business_process_workflow.name
}

output "workflow_id" {
  description = "Full resource ID of the Cloud Workflow"
  value       = google_workflows_workflow.business_process_workflow.id
}

output "workflow_location" {
  description = "Location of the Cloud Workflow"
  value       = google_workflows_workflow.business_process_workflow.region
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "workflow_service_account_email" {
  description = "Email of the service account used by Cloud Workflows"
  value       = google_service_account.workflow_sa.email
}

# Storage Information
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# Security Information
output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = google_compute_security_policy.bpa_security_policy.name
}

output "security_policy_self_link" {
  description = "Self link of the Cloud Armor security policy"
  value       = google_compute_security_policy.bpa_security_policy.self_link
}

# Monitoring Information
output "monitoring_notification_channel" {
  description = "Name of the monitoring notification channel"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email_notification[0].name : null
}

output "sql_health_alert_policy" {
  description = "Name of the Cloud SQL health alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.sql_instance_health[0].name : null
}

output "function_error_alert_policy" {
  description = "Name of the Cloud Functions error alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_errors[0].name : null
}

# Network Information
output "private_services_range" {
  description = "Name of the private services IP range"
  value       = var.enable_private_services ? google_compute_global_address.private_services_range[0].name : null
}

output "private_vpc_connection" {
  description = "Name of the private VPC connection"
  value       = var.enable_private_services ? google_service_networking_connection.private_vpc_connection[0].network : null
}

# Resource Naming
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Project Information
output "project_id" {
  description = "GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources were created"
  value       = var.region
}

output "zone" {
  description = "GCP zone where resources were created"
  value       = var.zone
}

# Testing Commands
output "test_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    # Test AI agent function
    test_agent = "curl -X POST ${google_cloudfunctions2_function.agent_function.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"message\": \"I need approval for a $500 expense for office supplies\", \"user_email\": \"employee@company.com\"}'"
    
    # Test workflow execution
    test_workflow = "gcloud workflows execute ${google_workflows_workflow.business_process_workflow.name} --location=${local.workflow_location} --data='{\"request_id\": \"test-001\", \"process_type\": \"expense_approval\", \"requester_email\": \"test@company.com\", \"request_data\": {\"amount\": \"250\", \"category\": \"office supplies\"}, \"priority\": 3}'"
    
    # Check database connectivity
    test_database = "gcloud sql connect ${google_sql_database_instance.business_process_db.name} --user=postgres --database=${google_sql_database.business_processes_db.name}"
    
    # View workflow executions
    view_executions = "gcloud workflows executions list --workflow=${google_workflows_workflow.business_process_workflow.name} --location=${local.workflow_location} --limit=5"
    
    # View function logs
    view_logs = "gcloud functions logs read ${google_cloudfunctions2_function.agent_function.name} --region=${var.region} --limit=10"
  }
}

# Database Schema Commands
output "database_schema_setup" {
  description = "SQL commands to set up the database schema"
  value = {
    connect_command = "gcloud sql connect ${google_sql_database_instance.business_process_db.name} --user=postgres --database=${google_sql_database.business_processes_db.name}"
    schema_sql = <<-EOF
      -- Business Process Automation Database Schema
      
      -- Process requests table
      CREATE TABLE IF NOT EXISTS process_requests (
          id SERIAL PRIMARY KEY,
          request_id VARCHAR(50) UNIQUE NOT NULL,
          requester_email VARCHAR(255) NOT NULL,
          process_type VARCHAR(100) NOT NULL,
          request_data JSONB NOT NULL,
          status VARCHAR(50) DEFAULT 'pending',
          priority INTEGER DEFAULT 3,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      -- Process approvals table
      CREATE TABLE IF NOT EXISTS process_approvals (
          id SERIAL PRIMARY KEY,
          request_id VARCHAR(50) REFERENCES process_requests(request_id),
          approver_email VARCHAR(255) NOT NULL,
          decision VARCHAR(20) NOT NULL,
          comments TEXT,
          approved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      -- Process audit table
      CREATE TABLE IF NOT EXISTS process_audit (
          id SERIAL PRIMARY KEY,
          request_id VARCHAR(50) REFERENCES process_requests(request_id),
          action VARCHAR(100) NOT NULL,
          actor VARCHAR(255) NOT NULL,
          details JSONB,
          timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
      
      -- Create indexes for performance
      CREATE INDEX IF NOT EXISTS idx_requests_status ON process_requests(status);
      CREATE INDEX IF NOT EXISTS idx_requests_type ON process_requests(process_type);
      CREATE INDEX IF NOT EXISTS idx_audit_request ON process_audit(request_id);
      CREATE INDEX IF NOT EXISTS idx_requests_created ON process_requests(created_at);
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON process_audit(timestamp);
    EOF
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Key endpoints for external system integration"
  value = {
    agent_endpoint      = google_cloudfunctions2_function.agent_function.service_config[0].uri
    approval_endpoint   = google_cloudfunctions2_function.approval_function.service_config[0].uri
    notification_endpoint = google_cloudfunctions2_function.notification_function.service_config[0].uri
    workflow_name      = google_workflows_workflow.business_process_workflow.name
    workflow_location  = local.workflow_location
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cloud_sql_f1_micro    = "$7-15 (depending on usage)"
    cloud_functions_gen2  = "$0-5 (first 2M invocations free)"
    cloud_workflows       = "$0-2 (first 5K executions free)"
    cloud_storage         = "$0-1 (minimal storage usage)"
    total_estimated       = "$7-23 USD/month for development workloads"
    note                  = "Costs vary based on actual usage. Monitor through Cloud Billing for accurate tracking."
  }
}