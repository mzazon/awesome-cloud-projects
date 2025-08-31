# Smart Parking Management - Terraform Outputs
# Provides important resource information for integration and verification

# ================================================================================
# PROJECT AND RESOURCE IDENTIFICATION OUTPUTS
# ================================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone used for zonal resources"
  value       = var.zone
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "deployment_labels" {
  description = "Labels applied to all resources for organization and cost tracking"
  value       = var.labels
}

# ================================================================================
# PUB/SUB INFRASTRUCTURE OUTPUTS
# ================================================================================

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for parking sensor data"
  value       = google_pubsub_topic.parking_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.parking_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for message processing"
  value       = google_pubsub_subscription.parking_processing.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.parking_processing.id
}

output "pubsub_dead_letter_topic" {
  description = "Name of the dead letter queue topic for failed messages"
  value       = google_pubsub_topic.parking_events_dlq.name
}

# ================================================================================
# CLOUD FUNCTIONS OUTPUTS
# ================================================================================

output "parking_processor_function_name" {
  description = "Name of the parking data processor Cloud Function"
  value       = google_cloudfunctions2_function.parking_processor.name
}

output "parking_processor_function_url" {
  description = "URL of the parking data processor Cloud Function"
  value       = google_cloudfunctions2_function.parking_processor.service_config[0].uri
}

output "parking_api_function_name" {
  description = "Name of the parking management API Cloud Function"
  value       = google_cloudfunctions2_function.parking_api.name
}

output "parking_api_function_url" {
  description = "URL of the parking management API Cloud Function"
  value       = google_cloudfunctions2_function.parking_api.service_config[0].uri
}

output "parking_api_endpoints" {
  description = "Available REST API endpoints for the parking management system"
  value = {
    search_parking = "${google_cloudfunctions2_function.parking_api.service_config[0].uri}/parking/search?lat=LAT&lng=LNG&radius=RADIUS"
    zone_stats     = "${google_cloudfunctions2_function.parking_api.service_config[0].uri}/parking/zones/ZONE_ID/stats"
    base_url       = google_cloudfunctions2_function.parking_api.service_config[0].uri
  }
}

# ================================================================================
# FIRESTORE DATABASE OUTPUTS
# ================================================================================

output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.parking_data.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.parking_data.location_id
}

output "firestore_type" {
  description = "Type of the Firestore database"
  value       = google_firestore_database.parking_data.type
}

output "firestore_collections" {
  description = "Firestore collections used by the parking system"
  value = {
    parking_spaces = var.parking_spaces_collection
    parking_zones  = var.parking_zones_collection
  }
}

# ================================================================================
# SERVICE ACCOUNTS OUTPUTS
# ================================================================================

output "mqtt_service_account_email" {
  description = "Email address of the MQTT service account for Pub/Sub publishing"
  value       = google_service_account.mqtt_publisher.email
}

output "mqtt_service_account_id" {
  description = "Unique ID of the MQTT service account"
  value       = google_service_account.mqtt_publisher.unique_id
}

output "cloud_functions_service_account_email" {
  description = "Email address of the Cloud Functions service account"
  value       = google_service_account.cloud_functions.email
}

output "mqtt_service_account_key_secret" {
  description = "Secret Manager secret name containing the MQTT service account key"
  value       = var.create_service_account_key ? google_secret_manager_secret.mqtt_key[0].secret_id : null
  sensitive   = true
}

# ================================================================================
# GOOGLE MAPS PLATFORM OUTPUTS
# ================================================================================

output "maps_api_key_name" {
  description = "Name of the Google Maps Platform API key"
  value       = google_apikeys_key.maps_api.name
}

output "maps_api_key_id" {
  description = "ID of the Google Maps Platform API key"
  value       = google_apikeys_key.maps_api.uid
}

output "maps_api_key_value" {
  description = "The actual API key value for Google Maps Platform (sensitive)"
  value       = google_apikeys_key.maps_api.key_string
  sensitive   = true
}

# ================================================================================
# STORAGE OUTPUTS
# ================================================================================

output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

# ================================================================================
# NETWORKING OUTPUTS (IF VPC IS ENABLED)
# ================================================================================

output "vpc_network_name" {
  description = "Name of the VPC network (if private networking is enabled)"
  value       = var.enable_private_google_access ? google_compute_network.parking_vpc[0].name : null
}

output "vpc_network_id" {
  description = "ID of the VPC network (if private networking is enabled)"
  value       = var.enable_private_google_access ? google_compute_network.parking_vpc[0].id : null
}

output "functions_subnet_name" {
  description = "Name of the subnet used by Cloud Functions (if VPC is enabled)"
  value       = var.enable_private_google_access ? google_compute_subnetwork.functions_subnet[0].name : null
}

output "vpc_connector_name" {
  description = "Name of the VPC connector for Cloud Functions (if VPC is enabled)"
  value       = var.enable_private_google_access ? google_vpc_access_connector.functions_connector[0].name : null
}

# ================================================================================
# MONITORING OUTPUTS
# ================================================================================

output "monitoring_notification_channel" {
  description = "ID of the monitoring notification channel (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email_alerts[0].id : null
}

output "monitoring_alert_policies" {
  description = "IDs of the monitoring alert policies (if monitoring is enabled)"
  value = var.enable_monitoring ? {
    pubsub_backlog   = google_monitoring_alert_policy.pubsub_backlog[0].id
    function_errors  = google_monitoring_alert_policy.function_errors[0].id
  } : {}
}

# ================================================================================
# INTEGRATION AND TESTING OUTPUTS
# ================================================================================

output "mqtt_broker_integration_guide" {
  description = "Configuration guide for integrating MQTT brokers with the system"
  value = {
    pubsub_topic              = google_pubsub_topic.parking_events.name
    service_account_email     = google_service_account.mqtt_publisher.email
    service_account_key_secret = var.create_service_account_key ? google_secret_manager_secret.mqtt_key[0].secret_id : "Key creation disabled"
    required_permissions      = ["pubsub.publisher"]
    message_format           = "JSON with fields: space_id, sensor_id, occupied, confidence, zone, location, timestamp"
  }
}

output "test_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    publish_test_message = "gcloud pubsub topics publish ${google_pubsub_topic.parking_events.name} --message='{\"space_id\":\"A001\",\"sensor_id\":\"test-sensor\",\"occupied\":false,\"confidence\":0.95,\"zone\":\"downtown\",\"location\":{\"lat\":37.7749,\"lng\":-122.4194}}'"
    test_api_search      = "curl '${google_cloudfunctions2_function.parking_api.service_config[0].uri}/parking/search?lat=37.7749&lng=-122.4194&radius=1000'"
    test_zone_stats      = "curl '${google_cloudfunctions2_function.parking_api.service_config[0].uri}/parking/zones/downtown/stats'"
    view_function_logs   = "gcloud functions logs read ${google_cloudfunctions2_function.parking_processor.name} --region=${var.region} --gen2"
  }
}

output "cost_estimation" {
  description = "Estimated monthly costs for different usage patterns"
  value = {
    light_usage = {
      description = "1,000 sensors, 10 updates/hour each, 100 API calls/day"
      components = {
        pubsub        = "$2-5 (240M messages/month)"
        cloud_functions = "$5-10 (480K invocations/month)"
        firestore     = "$5-15 (depends on document size and reads)"
        maps_platform = "$5-20 (depends on API usage)"
        storage       = "$1-3 (function source and logs)"
      }
      total_estimate = "$18-53 per month"
    }
    production_usage = {
      description = "10,000 sensors, 6 updates/hour each, 10,000 API calls/day"
      components = {
        pubsub        = "$20-40 (1.44B messages/month)"
        cloud_functions = "$50-100 (2.88M invocations/month)"
        firestore     = "$50-150 (higher read/write volume)"
        maps_platform = "$50-200 (higher API usage)"
        storage       = "$5-10 (function source and logs)"
      }
      total_estimate = "$175-500 per month"
    }
  }
}

# ================================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ================================================================================

output "security_considerations" {
  description = "Important security considerations for the deployed infrastructure"
  value = {
    api_authentication = var.enable_api_authentication ? "Enabled - API requires authentication" : "Disabled - API allows public access"
    service_account_key = var.create_service_account_key ? "Created and stored in Secret Manager" : "Not created - use workload identity in production"
    maps_api_restrictions = var.enable_maps_api_restrictions ? "Enabled with referrer restrictions" : "Disabled - consider enabling for production"
    vpc_security = var.enable_private_google_access ? "Private VPC enabled for enhanced network security" : "Using default networking"
    firestore_security = "Access controlled through IAM roles and service accounts"
    recommendations = [
      "Enable API authentication for production deployments",
      "Restrict Maps API key to specific domains/IPs",
      "Configure VPC for private networking in sensitive environments",
      "Use workload identity instead of service account keys when possible",
      "Enable audit logging for compliance requirements",
      "Configure backup and disaster recovery policies"
    ]
  }
}

# ================================================================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ================================================================================

output "deployment_status" {
  description = "Status and verification information for the deployment"
  value = {
    apis_enabled = [
      "pubsub.googleapis.com",
      "cloudfunctions.googleapis.com", 
      "firestore.googleapis.com",
      "maps-backend.googleapis.com",
      "cloudbuild.googleapis.com"
    ]
    resources_created = {
      pubsub_topics       = 2  # Main topic + DLQ
      pubsub_subscriptions = 1
      cloud_functions     = 2  # Processor + API
      firestore_database  = 1
      service_accounts    = 2  # MQTT + Functions
      api_keys           = 1   # Maps Platform
      storage_buckets    = 1   # Function source
      vpc_resources      = var.enable_private_google_access ? 3 : 0 # Network + Subnet + Connector
      monitoring_resources = var.enable_monitoring ? 3 : 0 # Channel + 2 Policies
    }
    next_steps = [
      "Configure your MQTT broker to publish to the Pub/Sub topic",
      "Test the API endpoints with sample data",
      "Configure monitoring alerts with appropriate email addresses",
      "Set up backup and disaster recovery procedures",
      "Review and adjust IAM permissions for production use"
    ]
  }
}