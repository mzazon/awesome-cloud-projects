# Outputs for GCP Digital Twin Manufacturing Resilience Infrastructure
# These outputs provide essential information for connecting to and using the deployed resources

# ============================================================================
# PROJECT AND BASIC INFORMATION
# ============================================================================

output "project_id" {
  description = "The GCP project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "resource_prefix" {
  description = "The prefix used for resource naming"
  value       = local.resource_prefix
}

output "random_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# PUB/SUB OUTPUTS
# ============================================================================

output "pubsub_topics" {
  description = "Map of Pub/Sub topic names and their full resource IDs"
  value = {
    for k, v in google_pubsub_topic.topics : k => {
      name = v.name
      id   = v.id
    }
  }
}

output "pubsub_subscriptions" {
  description = "Pub/Sub subscription information for data processing"
  value = {
    sensor_data_processing = {
      name = google_pubsub_subscription.sensor_data_processing.name
      id   = google_pubsub_subscription.sensor_data_processing.id
    }
    simulation_processing = {
      name = google_pubsub_subscription.simulation_processing.name
      id   = google_pubsub_subscription.simulation_processing.id
    }
  }
}

output "dead_letter_topic" {
  description = "Dead letter topic information for failed message handling"
  value = {
    name = google_pubsub_topic.dead_letter.name
    id   = google_pubsub_topic.dead_letter.id
  }
}

# ============================================================================
# CLOUD STORAGE OUTPUTS
# ============================================================================

output "storage_bucket" {
  description = "Cloud Storage bucket information for model artifacts and data"
  value = {
    name     = google_storage_bucket.digital_twin_storage.name
    url      = google_storage_bucket.digital_twin_storage.url
    location = google_storage_bucket.digital_twin_storage.location
  }
}

output "storage_bucket_folders" {
  description = "Organized folder structure in Cloud Storage bucket"
  value = {
    models              = "gs://${google_storage_bucket.digital_twin_storage.name}/models/"
    training_data       = "gs://${google_storage_bucket.digital_twin_storage.name}/training-data/"
    simulation_configs  = "gs://${google_storage_bucket.digital_twin_storage.name}/simulation-configs/"
    dataflow           = "gs://${google_storage_bucket.digital_twin_storage.name}/dataflow/"
    temp               = "gs://${google_storage_bucket.digital_twin_storage.name}/temp/"
  }
}

# ============================================================================
# BIGQUERY OUTPUTS
# ============================================================================

output "bigquery_dataset" {
  description = "BigQuery dataset information for manufacturing data"
  value = {
    dataset_id    = google_bigquery_dataset.manufacturing_data.dataset_id
    project       = google_bigquery_dataset.manufacturing_data.project
    location      = google_bigquery_dataset.manufacturing_data.location
    friendly_name = google_bigquery_dataset.manufacturing_data.friendly_name
  }
}

output "bigquery_tables" {
  description = "BigQuery table information for different data types"
  value = {
    sensor_data = {
      table_id      = google_bigquery_table.sensor_data.table_id
      friendly_name = google_bigquery_table.sensor_data.friendly_name
      full_table_id = "${var.project_id}.${google_bigquery_dataset.manufacturing_data.dataset_id}.${google_bigquery_table.sensor_data.table_id}"
    }
    simulation_results = {
      table_id      = google_bigquery_table.simulation_results.table_id
      friendly_name = google_bigquery_table.simulation_results.friendly_name
      full_table_id = "${var.project_id}.${google_bigquery_dataset.manufacturing_data.dataset_id}.${google_bigquery_table.simulation_results.table_id}"
    }
    equipment_metadata = {
      table_id      = google_bigquery_table.equipment_metadata.table_id
      friendly_name = google_bigquery_table.equipment_metadata.friendly_name
      full_table_id = "${var.project_id}.${google_bigquery_dataset.manufacturing_data.dataset_id}.${google_bigquery_table.equipment_metadata.table_id}"
    }
  }
}

# ============================================================================
# VERTEX AI OUTPUTS
# ============================================================================

output "vertex_ai_dataset" {
  description = "Vertex AI dataset information for ML model training"
  value = {
    name         = google_vertex_ai_dataset.failure_prediction.name
    display_name = google_vertex_ai_dataset.failure_prediction.display_name
    region       = google_vertex_ai_dataset.failure_prediction.region
  }
}

# ============================================================================
# CLOUD FUNCTION OUTPUTS
# ============================================================================

output "cloud_function" {
  description = "Cloud Function information for digital twin simulation"
  value = {
    name        = google_cloudfunctions2_function.digital_twin_simulator.name
    location    = google_cloudfunctions2_function.digital_twin_simulator.location
    url         = google_cloudfunctions2_function.digital_twin_simulator.service_config[0].uri
    description = google_cloudfunctions2_function.digital_twin_simulator.description
  }
}

output "function_service_account" {
  description = "Service account information for Cloud Function"
  value = {
    email        = google_service_account.function_service_account.email
    display_name = google_service_account.function_service_account.display_name
  }
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "monitoring_dashboard" {
  description = "Cloud Monitoring dashboard information"
  value = var.monitoring_dashboard_enabled ? {
    name         = google_monitoring_dashboard.digital_twin_dashboard[0].display_name
    dashboard_id = google_monitoring_dashboard.digital_twin_dashboard[0].id
  } : null
}

output "alert_policies" {
  description = "Monitoring alert policy information"
  value = {
    high_error_rate = {
      name         = google_monitoring_alert_policy.high_error_rate.display_name
      policy_id    = google_monitoring_alert_policy.high_error_rate.name
    }
  }
}

# ============================================================================
# SECURITY AND IAM OUTPUTS
# ============================================================================

output "custom_iam_role" {
  description = "Custom IAM role for digital twin operations"
  value = {
    role_id = google_project_iam_custom_role.digital_twin_operator.role_id
    title   = google_project_iam_custom_role.digital_twin_operator.title
  }
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "testing_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    # Test Pub/Sub message publishing
    test_pubsub = "gcloud pubsub topics publish ${google_pubsub_topic.topics["sensor_data"].name} --message='{\"equipment_id\":\"test_pump\",\"sensor_type\":\"temperature\",\"value\":75.5,\"unit\":\"celsius\",\"timestamp\":\"2025-01-25T10:00:00Z\"}'"
    
    # Test Cloud Function
    test_function = "curl -X POST ${google_cloudfunctions2_function.digital_twin_simulator.service_config[0].uri} -H 'Content-Type: application/json' -d '{\"equipment_id\":\"pump_001\",\"failure_type\":\"temperature_spike\",\"duration_hours\":2}'"
    
    # Query BigQuery sensor data
    test_bigquery = "bq query --use_legacy_sql=false 'SELECT equipment_id, COUNT(*) as reading_count FROM `${var.project_id}.${google_bigquery_dataset.manufacturing_data.dataset_id}.${google_bigquery_table.sensor_data.table_id}` GROUP BY equipment_id ORDER BY reading_count DESC'"
    
    # Check Vertex AI dataset
    test_vertex_ai = "gcloud ai datasets list --region=${var.vertex_ai_region} --filter='displayName:${google_vertex_ai_dataset.failure_prediction.display_name}'"
  }
}

output "connection_info" {
  description = "Connection information for external systems"
  value = {
    # Pub/Sub connection details
    pubsub = {
      sensor_data_topic = "projects/${var.project_id}/topics/${google_pubsub_topic.topics["sensor_data"].name}"
      simulation_topic  = "projects/${var.project_id}/topics/${google_pubsub_topic.topics["simulation_events"].name}"
      recovery_topic    = "projects/${var.project_id}/topics/${google_pubsub_topic.topics["recovery_commands"].name}"
    }
    
    # BigQuery connection details
    bigquery = {
      dataset_reference = "${var.project_id}:${google_bigquery_dataset.manufacturing_data.dataset_id}"
      sensor_table      = "${var.project_id}.${google_bigquery_dataset.manufacturing_data.dataset_id}.${google_bigquery_table.sensor_data.table_id}"
    }
    
    # Cloud Storage connection details
    storage = {
      bucket_uri        = "gs://${google_storage_bucket.digital_twin_storage.name}"
      training_data_uri = "gs://${google_storage_bucket.digital_twin_storage.name}/training-data/"
    }
    
    # Vertex AI connection details
    vertex_ai = {
      dataset_resource_name = google_vertex_ai_dataset.failure_prediction.name
      region               = google_vertex_ai_dataset.failure_prediction.region
    }
  }
}

# ============================================================================
# COST ESTIMATION OUTPUTS
# ============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (approximate)"
  value = {
    pubsub_topics       = "$0.40 per million messages"
    bigquery_storage    = "$0.020 per GB per month"
    cloud_storage       = "$0.020 per GB per month (Standard class)"
    cloud_function      = "$0.0000004 per request + compute time"
    vertex_ai_dataset   = "Free for dataset storage, training costs vary"
    monitoring          = "Free tier includes basic monitoring"
    estimated_monthly   = "$50-100 for moderate usage (as per recipe estimate)"
  }
}

# ============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test Pub/Sub message flow using the test_pubsub command",
    "2. Verify Cloud Function deployment using the test_function command",
    "3. Check BigQuery tables using the test_bigquery command",
    "4. Validate Vertex AI dataset using the test_vertex_ai command",
    "5. Set up continuous integration for Dataflow pipeline deployment",
    "6. Configure monitoring alerts and notification channels",
    "7. Implement authentication and authorization for production use",
    "8. Upload real training data to replace sample data",
    "9. Train and deploy ML models using Vertex AI",
    "10. Set up automated data pipeline using Dataflow"
  ]
}