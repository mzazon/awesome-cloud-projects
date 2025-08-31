# Project and Region Information
output "project_id" {
  description = "Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Cloud SQL Database Information
output "db_instance_name" {
  description = "Name of the Cloud SQL MySQL instance"
  value       = google_sql_database_instance.product_db.name
}

output "db_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.product_db.connection_name
}

output "db_instance_ip_address" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.product_db.public_ip_address
}

output "db_instance_private_ip_address" {
  description = "Private IP address of the Cloud SQL instance (if configured)"
  value       = google_sql_database_instance.product_db.private_ip_address
}

output "db_name" {
  description = "Name of the products database"
  value       = google_sql_database.products.name
}

output "db_username" {
  description = "Database username for connections"
  value       = "root"
}

output "db_password" {
  description = "Database password for connections"
  value       = random_password.db_password.result
  sensitive   = true
}

# Cloud Storage Information
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for product data"
  value       = google_storage_bucket.product_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.product_data.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.product_data.self_link
}

# Cloud Functions Information
output "search_function_name" {
  description = "Name of the product search Cloud Function"
  value       = google_cloudfunctions2_function.product_search.name
}

output "search_function_url" {
  description = "URL of the product search Cloud Function"
  value       = google_cloudfunctions2_function.product_search.service_config[0].uri
}

output "add_function_name" {
  description = "Name of the add product Cloud Function"
  value       = google_cloudfunctions2_function.product_add.name
}

output "add_function_url" {
  description = "URL of the add product Cloud Function"
  value       = google_cloudfunctions2_function.product_add.service_config[0].uri
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_service_account_unique_id" {
  description = "Unique ID of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.unique_id
}

# Network Information
output "vpc_connector_name" {
  description = "Name of the VPC connector (if private IP is enabled)"
  value       = var.enable_private_ip ? google_vpc_access_connector.connector[0].name : null
}

output "vpc_connector_self_link" {
  description = "Self-link of the VPC connector (if private IP is enabled)"
  value       = var.enable_private_ip ? google_vpc_access_connector.connector[0].self_link : null
}

# Monitoring Information
output "db_cpu_alert_policy_name" {
  description = "Name of the database CPU monitoring alert policy"
  value       = google_monitoring_alert_policy.db_cpu_alert.name
}

output "function_error_alert_policy_name" {
  description = "Name of the function error monitoring alert policy"
  value       = google_monitoring_alert_policy.function_error_alert.name
}

# API Endpoints for Testing
output "search_api_endpoint" {
  description = "Complete API endpoint for product search"
  value       = google_cloudfunctions2_function.product_search.service_config[0].uri
}

output "add_product_api_endpoint" {
  description = "Complete API endpoint for adding products"
  value       = google_cloudfunctions2_function.product_add.service_config[0].uri
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for applications"
  value = {
    project_id         = var.project_id
    region            = var.region
    db_instance_name  = google_sql_database_instance.product_db.name
    db_name           = google_sql_database.products.name
    db_user           = "root"
    search_function_url = google_cloudfunctions2_function.product_search.service_config[0].uri
    add_function_url    = google_cloudfunctions2_function.product_add.service_config[0].uri
    storage_bucket    = google_storage_bucket.product_data.name
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = {
    cloud_sql_instance = "~$${var.db_instance_tier == "db-n1-standard-2" ? "80-120" : "varies"} (depends on tier: ${var.db_instance_tier})"
    cloud_sql_storage  = "~$${var.db_storage_size * 0.17} (${var.db_storage_size}GB SSD)"
    cloud_functions    = "~$5-20 (depends on usage, first 2M invocations free)"
    cloud_storage      = "~$1-5 (depends on data volume and access patterns)"
    vertex_ai_embeddings = "~$0.0001 per 1K tokens (depends on usage)"
    total_estimated    = "~$90-150 per month for moderate usage"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    ssl_required           = var.enable_ssl
    deletion_protection    = var.deletion_protection
    backup_enabled         = true
    point_in_time_recovery = var.enable_point_in_time_recovery
    uniform_bucket_access  = var.uniform_bucket_level_access
    private_ip_enabled     = var.enable_private_ip
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps after Terraform deployment"
  value = {
    step_1 = "Initialize database schema by connecting to Cloud SQL and running the schema creation scripts"
    step_2 = "Test the search API endpoint: ${google_cloudfunctions2_function.product_search.service_config[0].uri}"
    step_3 = "Test the add product API endpoint: ${google_cloudfunctions2_function.product_add.service_config[0].uri}"
    step_4 = "Load sample data using the provided JSON samples or your own product catalog"
    step_5 = "Configure monitoring alerts and notification channels as needed"
    step_6 = "Review security settings and adjust authorized networks if needed"
  }
}

# Sample API Usage
output "sample_api_usage" {
  description = "Sample curl commands for testing the API"
  value = {
    search_products = "curl -X POST '${google_cloudfunctions2_function.product_search.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"query\": \"comfortable running shoes\", \"limit\": 5}'"
    add_product = "curl -X POST '${google_cloudfunctions2_function.product_add.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"name\": \"Test Product\", \"description\": \"A test product for demonstration\", \"category\": \"test\", \"price\": 99.99}'"
  }
}

# Resource Labels
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}