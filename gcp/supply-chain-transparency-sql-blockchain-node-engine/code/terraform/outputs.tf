# Output Values for Supply Chain Transparency Infrastructure
# These outputs provide essential information for connecting to and managing the deployed infrastructure

# ============================================================================
# PROJECT & GENERAL INFORMATION
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "deployment_id" {
  description = "Unique deployment identifier for this infrastructure"
  value       = local.suffix
}

output "resource_prefix" {
  description = "Resource naming prefix used for all deployed resources"
  value       = local.name_prefix
}

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_network_name" {
  description = "Name of the VPC network created for the supply chain system"
  value       = google_compute_network.supply_chain_vpc.name
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network"
  value       = google_compute_network.supply_chain_vpc.id
}

output "private_subnet_name" {
  description = "Name of the private subnet for internal resources"
  value       = google_compute_subnetwork.private_subnet.name
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = google_compute_subnetwork.private_subnet.ip_cidr_range
}

output "vpc_connector_name" {
  description = "Name of the VPC Access Connector for Cloud Functions"
  value       = google_vpc_access_connector.supply_chain_connector.name
}

# ============================================================================
# DATABASE (Cloud SQL) OUTPUTS
# ============================================================================

output "database_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.supply_chain_db.name
}

output "database_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance (used for Cloud SQL Proxy)"
  value       = google_sql_database_instance.supply_chain_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.supply_chain_db.private_ip_address
  sensitive   = true
}

output "database_name" {
  description = "Name of the supply chain database"
  value       = google_sql_database.supply_chain.name
}

output "database_user" {
  description = "Username for the supply chain database user"
  value       = google_sql_user.supply_chain_user.name
}

output "database_password_secret_name" {
  description = "Name of the Secret Manager secret containing the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "database_ssl_required" {
  description = "Whether SSL is required for database connections"
  value       = var.enable_ssl_enforcement
}

# Connection string for applications (without password)
output "database_connection_string" {
  description = "Database connection string template (password should be retrieved from Secret Manager)"
  value = "postgresql://${google_sql_user.supply_chain_user.name}:PASSWORD_FROM_SECRET@${google_sql_database_instance.supply_chain_db.private_ip_address}:5432/${google_sql_database.supply_chain.name}?sslmode=${var.enable_ssl_enforcement ? "require" : "prefer"}"
  sensitive = true
}

# ============================================================================
# BLOCKCHAIN OUTPUTS
# ============================================================================

output "blockchain_node_name" {
  description = "Name of the Blockchain Node Engine instance"
  value       = google_blockchain_node_engine_blockchain_nodes.supply_chain_blockchain.blockchain_node_id
}

output "blockchain_node_location" {
  description = "Location of the Blockchain Node Engine instance"
  value       = google_blockchain_node_engine_blockchain_nodes.supply_chain_blockchain.location
}

output "blockchain_network" {
  description = "Blockchain network type (MAINNET, GOERLI, SEPOLIA)"
  value       = var.blockchain_network
}

output "blockchain_node_type" {
  description = "Type of blockchain node (FULL, ARCHIVE)"
  value       = var.blockchain_node_type
}

output "blockchain_execution_client" {
  description = "Blockchain execution client (GETH, ERIGON)"
  value       = var.blockchain_execution_client
}

# ============================================================================
# SECURITY & ENCRYPTION OUTPUTS
# ============================================================================

output "kms_keyring_name" {
  description = "Name of the Cloud KMS key ring"
  value       = google_kms_key_ring.supply_chain_keyring.name
}

output "kms_key_name" {
  description = "Name of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.supply_chain_key.name
}

output "kms_key_id" {
  description = "Full resource ID of the Cloud KMS encryption key"
  value       = google_kms_crypto_key.supply_chain_key.id
}

output "service_account_email" {
  description = "Email address of the supply chain service account"
  value       = google_service_account.supply_chain_sa.email
}

output "service_account_name" {
  description = "Name of the supply chain service account"
  value       = google_service_account.supply_chain_sa.name
}

# ============================================================================
# PUB/SUB MESSAGING OUTPUTS
# ============================================================================

output "pubsub_supply_chain_events_topic" {
  description = "Name of the Pub/Sub topic for supply chain events"
  value       = google_pubsub_topic.supply_chain_events.name
}

output "pubsub_blockchain_verification_topic" {
  description = "Name of the Pub/Sub topic for blockchain verification requests"
  value       = google_pubsub_topic.blockchain_verification.name
}

output "pubsub_dead_letter_topic" {
  description = "Name of the Pub/Sub dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

output "pubsub_supply_events_subscription" {
  description = "Name of the subscription for processing supply chain events"
  value       = google_pubsub_subscription.process_supply_events.name
}

output "pubsub_blockchain_verification_subscription" {
  description = "Name of the subscription for processing blockchain verification"
  value       = google_pubsub_subscription.process_blockchain_verification.name
}

# ============================================================================
# CLOUD FUNCTIONS OUTPUTS
# ============================================================================

output "supply_chain_processor_function_name" {
  description = "Name of the Cloud Function that processes supply chain events"
  value       = google_cloudfunctions2_function.supply_chain_processor.name
}

output "api_ingestion_function_name" {
  description = "Name of the Cloud Function that provides the API ingestion endpoint"
  value       = google_cloudfunctions2_function.api_ingestion.name
}

output "api_ingestion_function_url" {
  description = "HTTP trigger URL for the API ingestion function"
  value       = google_cloudfunctions2_function.api_ingestion.service_config[0].uri
}

output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "logs_bucket_name" {
  description = "Name of the Cloud Storage bucket for log storage"
  value       = var.enable_cloud_logging ? google_storage_bucket.logs_bucket[0].name : null
}

# ============================================================================
# MONITORING & LOGGING OUTPUTS
# ============================================================================

output "log_sink_name" {
  description = "Name of the Cloud Logging sink for supply chain logs"
  value       = var.enable_cloud_logging ? google_logging_project_sink.supply_chain_logs[0].name : null
}

output "cloud_monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled for this deployment"
  value       = var.enable_cloud_monitoring
}

output "cloud_logging_enabled" {
  description = "Whether Cloud Logging is enabled for this deployment"
  value       = var.enable_cloud_logging
}

# ============================================================================
# CONFIGURATION SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed supply chain transparency infrastructure"
  value = {
    project_id                = var.project_id
    region                    = var.region
    environment               = var.environment
    deployment_id             = local.suffix
    database_instance         = google_sql_database_instance.supply_chain_db.name
    blockchain_node          = google_blockchain_node_engine_blockchain_nodes.supply_chain_blockchain.blockchain_node_id
    api_endpoint             = google_cloudfunctions2_function.api_ingestion.service_config[0].uri
    vpc_network              = google_compute_network.supply_chain_vpc.name
    service_account          = google_service_account.supply_chain_sa.email
    kms_key                  = google_kms_crypto_key.supply_chain_key.name
    pubsub_topics            = [
      google_pubsub_topic.supply_chain_events.name,
      google_pubsub_topic.blockchain_verification.name
    ]
    cloud_functions          = [
      google_cloudfunctions2_function.supply_chain_processor.name,
      google_cloudfunctions2_function.api_ingestion.name
    ]
  }
}

# ============================================================================
# CONNECTION INFORMATION
# ============================================================================

output "connection_instructions" {
  description = "Instructions for connecting to the deployed infrastructure"
  value = {
    database_connection = "Use Cloud SQL Proxy or private IP: ${google_sql_database_instance.supply_chain_db.private_ip_address}:5432"
    api_endpoint        = "POST requests to: ${google_cloudfunctions2_function.api_ingestion.service_config[0].uri}"
    blockchain_access   = "Access through Blockchain Node Engine: ${google_blockchain_node_engine_blockchain_nodes.supply_chain_blockchain.blockchain_node_id}"
    secret_access       = "Database password in Secret Manager: ${google_secret_manager_secret.db_password.secret_id}"
    monitoring          = var.enable_cloud_monitoring ? "View metrics in Cloud Monitoring console" : "Cloud Monitoring not enabled"
    logs               = var.enable_cloud_logging ? "View logs in Cloud Logging console or storage bucket: ${google_storage_bucket.logs_bucket[0].name}" : "Cloud Logging not enabled"
  }
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for deployed resources (USD)"
  value = {
    cloud_sql_instance    = "~$50-150 (depending on tier: ${var.db_instance_tier})"
    blockchain_node       = "~$100-200 (Ethereum ${var.blockchain_network} ${var.blockchain_node_type} node)"
    cloud_functions       = "~$5-20 (depending on usage)"
    pubsub_messaging      = "~$1-10 (depending on message volume)"
    cloud_storage         = "~$1-5 (function source and logs)"
    vpc_and_networking    = "~$5-15 (VPC connector and NAT)"
    kms_keys             = "~$1-3 (key usage and operations)"
    total_estimated      = "~$160-400 per month"
    note                 = "Costs vary based on usage patterns, data volume, and function execution frequency"
  }
}

# ============================================================================
# SECURITY RECOMMENDATIONS
# ============================================================================

output "security_recommendations" {
  description = "Security best practices and recommendations for this deployment"
  value = {
    database_security = [
      "Database is encrypted with customer-managed KMS key",
      "SSL enforcement is ${var.enable_ssl_enforcement ? "enabled" : "DISABLED - consider enabling"}",
      "Database is on private network only",
      "Automatic backups are ${var.db_backup_enabled ? "enabled" : "DISABLED - consider enabling"}"
    ]
    network_security = [
      "VPC network isolates resources",
      "Cloud Functions use VPC connector for private database access",
      "NAT gateway provides controlled outbound internet access"
    ]
    access_control = [
      "Service account uses least-privilege IAM roles",
      "Database password stored in Secret Manager",
      "KMS key has automatic rotation enabled"
    ]
    monitoring = [
      "Cloud Logging is ${var.enable_cloud_logging ? "enabled" : "DISABLED - consider enabling"}",
      "Cloud Monitoring is ${var.enable_cloud_monitoring ? "enabled" : "DISABLED - consider enabling"}",
      "Database insights and query performance monitoring enabled"
    ]
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test API endpoint: curl -X POST ${google_cloudfunctions2_function.api_ingestion.service_config[0].uri} with JSON payload",
    "2. Connect to database using: gcloud sql connect ${google_sql_database_instance.supply_chain_db.name} --user=${google_sql_user.supply_chain_user.name}",
    "3. Create database schema using the SQL provided in the recipe",
    "4. Configure application clients to use the service account: ${google_service_account.supply_chain_sa.email}",
    "5. Monitor system health in Cloud Monitoring and Cloud Logging consoles",
    "6. Set up alerting policies for database performance and function errors",
    "7. Review and customize the deployed Cloud Functions code for your specific business logic",
    "8. Consider setting up automated testing and CI/CD pipelines for function deployments"
  ]
}