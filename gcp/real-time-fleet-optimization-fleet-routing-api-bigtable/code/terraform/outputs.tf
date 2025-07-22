# ============================================================================
# Terraform Outputs for Real-Time Fleet Optimization Infrastructure
# ============================================================================
# This file defines outputs that provide essential information about the
# deployed infrastructure including endpoints, resource identifiers, and
# configuration details needed for application integration and monitoring.

# ============================================================================
# Project and Core Configuration Outputs
# ============================================================================

output "project_id" {
  description = "Google Cloud Project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "Primary region where resources are deployed"
  value       = var.region
}

output "environment" {
  description = "Environment name for the deployed infrastructure"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# Cloud Bigtable Outputs
# ============================================================================

output "bigtable_instance_id" {
  description = "Bigtable instance ID for storing fleet and traffic data"
  value       = google_bigtable_instance.fleet_data.name
}

output "bigtable_instance_display_name" {
  description = "Bigtable instance display name"
  value       = google_bigtable_instance.fleet_data.display_name
}

output "bigtable_cluster_zones" {
  description = "Zones where Bigtable clusters are deployed"
  value = [
    for cluster in google_bigtable_instance.fleet_data.cluster : cluster.zone
  ]
}

output "bigtable_tables" {
  description = "Bigtable table names and their purposes"
  value = {
    traffic_patterns   = google_bigtable_table.traffic_patterns.name
    vehicle_locations  = google_bigtable_table.vehicle_locations.name
    route_history      = google_bigtable_table.route_history.name
  }
}

output "bigtable_connection_string" {
  description = "Connection string for Bigtable instance (for application configuration)"
  value       = "projects/${var.project_id}/instances/${google_bigtable_instance.fleet_data.name}"
}

# ============================================================================
# Pub/Sub Outputs
# ============================================================================

output "pubsub_topics" {
  description = "Pub/Sub topic names for fleet event processing"
  value = {
    fleet_events              = google_pubsub_topic.fleet_events.name
    route_optimization_requests = google_pubsub_topic.route_optimization_requests.name
    optimized_routes          = google_pubsub_topic.optimized_routes.name
    dead_letter               = google_pubsub_topic.dead_letter.name
  }
}

output "pubsub_topic_paths" {
  description = "Full Pub/Sub topic paths for API integration"
  value = {
    fleet_events              = google_pubsub_topic.fleet_events.id
    route_optimization_requests = google_pubsub_topic.route_optimization_requests.id
    optimized_routes          = google_pubsub_topic.optimized_routes.id
    dead_letter               = google_pubsub_topic.dead_letter.id
  }
}

output "pubsub_subscriptions" {
  description = "Pub/Sub subscription names for message processing"
  value = {
    location_processor = google_pubsub_subscription.location_processor.name
    route_optimizer    = google_pubsub_subscription.route_optimizer.name
  }
}

output "pubsub_schema_id" {
  description = "Pub/Sub schema ID for vehicle location messages"
  value       = google_pubsub_schema.vehicle_location_schema.id
}

# ============================================================================
# Cloud Functions Outputs
# ============================================================================

output "cloud_functions" {
  description = "Cloud Function names and their purposes"
  value = {
    location_processor = google_cloudfunctions2_function.location_processor.name
    route_optimizer    = google_cloudfunctions2_function.route_optimizer.name
    dashboard          = google_cloudfunctions2_function.dashboard.name
  }
}

output "function_urls" {
  description = "HTTP trigger URLs for Cloud Functions"
  value = {
    dashboard = google_cloudfunctions2_function.dashboard.service_config[0].uri
  }
  sensitive = false
}

output "function_service_accounts" {
  description = "Service account emails used by Cloud Functions"
  value = {
    location_processor = google_service_account.location_processor.email
    route_optimizer    = google_service_account.route_optimizer.email
    dashboard          = google_service_account.dashboard.email
  }
}

output "function_trigger_details" {
  description = "Event trigger configuration for Cloud Functions"
  value = {
    location_processor = {
      trigger_type = "Pub/Sub"
      topic        = google_pubsub_topic.fleet_events.name
      retry_policy = "RETRY_POLICY_RETRY"
    }
    route_optimizer = {
      trigger_type = "Pub/Sub"
      topic        = google_pubsub_topic.route_optimization_requests.name
      retry_policy = "RETRY_POLICY_RETRY"
    }
    dashboard = {
      trigger_type = "HTTP"
      access       = var.dashboard_public_access ? "public" : "internal"
    }
  }
}

# ============================================================================
# Security and IAM Outputs
# ============================================================================

output "service_accounts" {
  description = "Service account details for fleet optimization components"
  value = {
    location_processor = {
      email       = google_service_account.location_processor.email
      unique_id   = google_service_account.location_processor.unique_id
      description = google_service_account.location_processor.description
    }
    route_optimizer = {
      email       = google_service_account.route_optimizer.email
      unique_id   = google_service_account.route_optimizer.unique_id
      description = google_service_account.route_optimizer.description
    }
    dashboard = {
      email       = google_service_account.dashboard.email
      unique_id   = google_service_account.dashboard.unique_id
      description = google_service_account.dashboard.description
    }
    function_builder = {
      email       = google_service_account.function_builder.email
      unique_id   = google_service_account.function_builder.unique_id
      description = google_service_account.function_builder.description
    }
    pubsub_invoker = {
      email       = google_service_account.pubsub_invoker.email
      unique_id   = google_service_account.pubsub_invoker.unique_id
      description = google_service_account.pubsub_invoker.description
    }
  }
}

output "kms_key_details" {
  description = "KMS encryption key information"
  value = {
    key_ring_name = google_kms_key_ring.fleet_optimization.name
    key_ring_id   = google_kms_key_ring.fleet_optimization.id
    bigtable_key  = google_kms_crypto_key.bigtable_key.id
  }
}

output "secret_manager_secrets" {
  description = "Secret Manager secret names for secure configuration"
  value = {
    maps_api_key = google_secret_manager_secret.maps_api_key.secret_id
  }
}

# ============================================================================
# API and Integration Outputs
# ============================================================================

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for the fleet optimization system"
  value = [
    for api in google_project_service.required_apis : api.service
  ]
}

output "fleet_routing_api_endpoint" {
  description = "Google Cloud Fleet Routing API endpoint for route optimization"
  value       = "https://routeoptimization.googleapis.com/v1"
}

output "routes_api_endpoint" {
  description = "Google Maps Platform Routes API endpoint"
  value       = "https://routes.googleapis.com"
}

# ============================================================================
# Storage and Data Management Outputs
# ============================================================================

output "storage_bucket" {
  description = "Cloud Storage bucket for function source code"
  value = {
    name     = google_storage_bucket.function_source.name
    url      = google_storage_bucket.function_source.url
    location = google_storage_bucket.function_source.location
  }
}

output "data_configuration" {
  description = "Data management configuration settings"
  value = {
    retention_days   = var.data_retention_days
    cleanup_enabled  = var.enable_data_cleanup
    backup_frequency = var.backup_frequency_hours
  }
}

# ============================================================================
# Monitoring and Observability Outputs
# ============================================================================

output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    alerts_enabled     = var.enable_monitoring_alerts
    log_retention_days = var.log_retention_days
    debug_logging      = var.enable_debug_logging
  }
}

output "log_based_metrics" {
  description = "Log-based metrics for monitoring fleet optimization performance"
  value = {
    function_errors = google_logging_metric.function_errors.name
  }
}

output "alert_policies" {
  description = "Cloud Monitoring alert policy names"
  value = {
    function_errors = google_monitoring_alert_policy.function_error_alert.name
  }
}

# ============================================================================
# Network and Connectivity Outputs
# ============================================================================

output "network_configuration" {
  description = "Network configuration for fleet optimization services"
  value = {
    region                    = var.region
    zone                      = var.zone
    backup_region            = var.backup_region
    replica_zone             = var.replica_zone
    private_google_access    = var.enable_private_google_access
  }
}

# ============================================================================
# Cost and Resource Optimization Outputs
# ============================================================================

output "resource_configuration" {
  description = "Resource configuration and scaling settings"
  value = {
    bigtable = {
      min_nodes                = var.bigtable_min_nodes
      max_nodes               = var.bigtable_max_nodes
      cpu_target              = var.bigtable_cpu_target
      replication_enabled     = var.enable_bigtable_replication
    }
    functions = {
      max_instances           = var.max_function_instances
      timeout_seconds         = var.function_timeout_seconds
    }
    pubsub = {
      message_retention_hours = var.pubsub_message_retention_hours
    }
  }
}

output "cost_optimization" {
  description = "Cost optimization settings and features"
  value = {
    preemptible_instances     = var.use_preemptible_instances
    committed_use_discounts   = var.enable_committed_use_discounts
    storage_class            = var.storage_class
    high_availability        = var.enable_high_availability
  }
}

# ============================================================================
# Fleet-Specific Configuration Outputs
# ============================================================================

output "fleet_configuration" {
  description = "Fleet-specific optimization configuration"
  value = {
    max_vehicles_per_optimization = var.max_vehicles_per_optimization
    vehicle_capacity_units        = var.vehicle_capacity_units
    default_vehicle_speed_kmh     = var.default_vehicle_speed_kmh
    optimization_objectives       = var.optimization_objectives
    optimization_batch_size       = var.optimization_batch_size
  }
}

# ============================================================================
# Deployment Information Outputs
# ============================================================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.0"
}

output "google_provider_version" {
  description = "Google Cloud Provider version used for deployment"
  value       = "~> 6.0"
}

# ============================================================================
# Quick Start Commands
# ============================================================================

output "quick_start_commands" {
  description = "Commands to quickly interact with the deployed infrastructure"
  value = {
    # Bigtable commands
    bigtable_list_tables = "cbt -project=${var.project_id} -instance=${google_bigtable_instance.fleet_data.name} ls"
    bigtable_read_traffic = "cbt -project=${var.project_id} -instance=${google_bigtable_instance.fleet_data.name} read ${google_bigtable_table.traffic_patterns.name} count=10"
    
    # Pub/Sub commands
    publish_test_event = "gcloud pubsub topics publish ${google_pubsub_topic.fleet_events.name} --message='{\"vehicle_id\":\"test-001\",\"latitude\":37.7749,\"longitude\":-122.4194,\"timestamp\":${formatdate("DDMMYYHHmmss", timestamp())}}'"
    
    # Function commands
    view_function_logs = "gcloud functions logs read ${google_cloudfunctions2_function.location_processor.name} --limit=10"
    
    # Dashboard access
    open_dashboard = "open ${google_cloudfunctions2_function.dashboard.service_config[0].uri}"
  }
}

# ============================================================================
# Integration Examples
# ============================================================================

output "integration_examples" {
  description = "Example code snippets for integrating with the fleet optimization system"
  value = {
    python_publish_location = <<-EOF
      from google.cloud import pubsub_v1
      import json
      
      publisher = pubsub_v1.PublisherClient()
      topic_path = "${google_pubsub_topic.fleet_events.id}"
      
      location_data = {
          "vehicle_id": "vehicle-001",
          "latitude": 37.7749,
          "longitude": -122.4194,
          "timestamp": 1703721600,
          "speed": 45.5,
          "road_segment": "highway-101-north"
      }
      
      future = publisher.publish(topic_path, json.dumps(location_data).encode())
      print(f"Published message: {future.result()}")
    EOF
    
    curl_dashboard_access = <<-EOF
      curl -X GET "${google_cloudfunctions2_function.dashboard.service_config[0].uri}" \
        -H "Content-Type: application/json"
    EOF
    
    bigtable_query_example = <<-EOF
      cbt -project=${var.project_id} -instance=${google_bigtable_instance.fleet_data.name} \
        read ${google_bigtable_table.traffic_patterns.name} \
        start=highway-101# end=highway-101#~ count=50
    EOF
  }
}

# ============================================================================
# Resource Summary
# ============================================================================

output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    bigtable_instances = 1
    bigtable_tables    = 3
    pubsub_topics      = 4
    pubsub_subscriptions = 2
    cloud_functions    = 3
    service_accounts   = 5
    kms_keys          = 1
    storage_buckets   = 1
    monitoring_alerts = 1
    log_metrics       = 1
  }
}