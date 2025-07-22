# Output values for the Edge-Based Predictive Maintenance solution
output "resource_group_name" {
  description = "Name of the resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "iot_hub_name" {
  description = "Name of the IoT Hub"
  value       = azurerm_iothub.main.name
}

output "iot_hub_hostname" {
  description = "Hostname of the IoT Hub"
  value       = azurerm_iothub.main.hostname
}

output "iot_hub_connection_string" {
  description = "Connection string for the IoT Hub (sensitive)"
  value       = azurerm_iothub.main.shared_access_policy[0].connection_string
  sensitive   = true
}

output "edge_device_id" {
  description = "ID of the IoT Edge device"
  value       = azurerm_iothub_device_identity.edge_device.name
}

output "edge_device_connection_string" {
  description = "Connection string for the IoT Edge device (sensitive)"
  value       = azurerm_iothub_device_identity.edge_device.connection_string
  sensitive   = true
}

output "edge_device_primary_key" {
  description = "Primary key for the IoT Edge device (sensitive)"
  value       = azurerm_iothub_device_identity.edge_device.primary_key
  sensitive   = true
}

output "edge_device_secondary_key" {
  description = "Secondary key for the IoT Edge device (sensitive)"
  value       = azurerm_iothub_device_identity.edge_device.secondary_key
  sensitive   = true
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account (sensitive)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "storage_container_stream_analytics" {
  description = "Name of the Stream Analytics storage container"
  value       = azurerm_storage_container.stream_analytics.name
}

output "storage_container_telemetry_archive" {
  description = "Name of the telemetry archive storage container"
  value       = azurerm_storage_container.telemetry_archive.name
}

output "stream_analytics_job_name" {
  description = "Name of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.edge_job.name
}

output "stream_analytics_job_id" {
  description = "ID of the Stream Analytics job"
  value       = azurerm_stream_analytics_job.edge_job.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights resource"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (sensitive)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_queue_name" {
  description = "Name of the Service Bus queue for anomaly alerts"
  value       = azurerm_servicebus_queue.anomaly_alerts.name
}

output "servicebus_connection_string" {
  description = "Connection string for Service Bus namespace (sensitive)"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "action_group_name" {
  description = "Name of the monitor action group"
  value       = azurerm_monitor_action_group.maintenance_team.name
}

output "metric_alert_name" {
  description = "Name of the metric alert rule"
  value       = azurerm_monitor_metric_alert.high_temperature.name
}

output "deployment_manifest_path" {
  description = "Path to the IoT Edge deployment manifest file"
  value       = local_file.edge_deployment_manifest.filename
}

output "anomaly_query_path" {
  description = "Path to the Stream Analytics anomaly detection query file"
  value       = local_file.anomaly_query.filename
}

# Deployment guidance outputs
output "deployment_instructions" {
  description = "Instructions for deploying the solution"
  value = <<-EOF
    ## Deployment Instructions

    1. **Configure IoT Edge Device**:
       - Install IoT Edge runtime on your device
       - Configure with connection string: ${azurerm_iothub_device_identity.edge_device.connection_string}
       - Deploy modules using: az iot edge deployment create --deployment-id predictive-maintenance-v1 --hub-name ${azurerm_iothub.main.name} --content ${local_file.edge_deployment_manifest.filename}

    2. **Configure Stream Analytics**:
       - Update Stream Analytics job with query from: ${local_file.anomaly_query.filename}
       - Start the job: az stream-analytics job start --name ${azurerm_stream_analytics_job.edge_job.name} --resource-group ${azurerm_resource_group.main.name}

    3. **Monitor Solution**:
       - View telemetry in IoT Hub: ${azurerm_iothub.main.name}
       - Check logs in Log Analytics: ${azurerm_log_analytics_workspace.main.name}
       - Monitor alerts in Action Group: ${azurerm_monitor_action_group.maintenance_team.name}

    4. **Verify Operation**:
       - Check edge device status: az iot hub device-identity show --device-id ${azurerm_iothub_device_identity.edge_device.name} --hub-name ${azurerm_iothub.main.name}
       - Monitor message flow: az iot hub monitor-events --hub-name ${azurerm_iothub.main.name} --device-id ${azurerm_iothub_device_identity.edge_device.name}
       - View archived telemetry in storage container: ${azurerm_storage_container.telemetry_archive.name}

    ## Cost Optimization

    - Estimated monthly cost: ~$50-150 (depends on message volume and storage usage)
    - Use F1 tier for IoT Hub during development (free tier)
    - Configure lifecycle policies on storage containers to archive old data
    - Monitor and adjust Stream Analytics streaming units based on workload

    ## Security Considerations

    - All connection strings are marked as sensitive and stored securely
    - IoT Edge device uses symmetric key authentication (consider X.509 certificates for production)
    - Storage account and Service Bus use default encryption at rest
    - Log Analytics workspace configured with appropriate retention policies
    - Network security groups should be configured to restrict access to edge devices

    ## Next Steps

    1. Install IoT Edge runtime on your target device
    2. Configure the device with the provided connection string
    3. Deploy the edge modules using the generated manifest
    4. Configure Stream Analytics with the anomaly detection query
    5. Test the solution by generating temperature data
    6. Monitor alerts and adjust thresholds as needed
  EOF
}

# Summary of created resources
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    
    iot_hub = {
      name     = azurerm_iothub.main.name
      sku      = "${var.iot_hub_sku} (${var.iot_hub_capacity} units)"
      hostname = azurerm_iothub.main.hostname
    }
    
    edge_device = {
      id           = azurerm_iothub_device_identity.edge_device.name
      edge_enabled = azurerm_iothub_device_identity.edge_device.edge_enabled
    }
    
    storage_account = {
      name             = azurerm_storage_account.main.name
      tier             = var.storage_account_tier
      replication_type = var.storage_account_replication
      containers       = [
        azurerm_storage_container.stream_analytics.name,
        azurerm_storage_container.telemetry_archive.name
      ]
    }
    
    stream_analytics = {
      name             = azurerm_stream_analytics_job.edge_job.name
      streaming_units  = var.stream_analytics_streaming_units
      compatibility_level = azurerm_stream_analytics_job.edge_job.compatibility_level
    }
    
    monitoring = {
      log_analytics_workspace = azurerm_log_analytics_workspace.main.name
      application_insights    = azurerm_application_insights.main.name
      action_group           = azurerm_monitor_action_group.maintenance_team.name
      metric_alert           = azurerm_monitor_metric_alert.high_temperature.name
    }
    
    messaging = {
      servicebus_namespace = azurerm_servicebus_namespace.main.name
      servicebus_queue     = azurerm_servicebus_queue.anomaly_alerts.name
    }
  }
}