# Output values for GCP Load Balancer Traffic Routing with Service Extensions

output "load_balancer_ip" {
  description = "The external IP address of the Application Load Balancer"
  value       = google_compute_global_forwarding_rule.default.ip_address
}

output "load_balancer_url" {
  description = "The HTTP URL for accessing the load balancer"
  value       = "http://${google_compute_global_forwarding_rule.default.ip_address}"
}

output "cloud_run_services" {
  description = "Information about deployed Cloud Run services"
  value = {
    service_a = {
      name = google_cloud_run_service.service_a.name
      url  = google_cloud_run_service.service_a.status[0].url
    }
    service_b = {
      name = google_cloud_run_service.service_b.name
      url  = google_cloud_run_service.service_b.status[0].url
    }
    service_c = {
      name = google_cloud_run_service.service_c.name
      url  = google_cloud_run_service.service_c.status[0].url
    }
  }
}

output "bigquery_dataset" {
  description = "BigQuery dataset information for traffic analytics"
  value = {
    dataset_id   = google_bigquery_dataset.traffic_analytics.dataset_id
    project_id   = google_bigquery_dataset.traffic_analytics.project
    location     = google_bigquery_dataset.traffic_analytics.location
    dataset_url  = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.traffic_analytics.dataset_id}"
  }
}

output "bigquery_tables" {
  description = "BigQuery tables for analytics"
  value = {
    lb_metrics = {
      table_id = google_bigquery_table.lb_metrics.table_id
      table_url = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.traffic_analytics.dataset_id}!3s${google_bigquery_table.lb_metrics.table_id}"
    }
    routing_decisions = {
      table_id = google_bigquery_table.routing_decisions.table_id
      table_url = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m5!1m4!4m3!1s${var.project_id}!2s${google_bigquery_dataset.traffic_analytics.dataset_id}!3s${google_bigquery_table.routing_decisions.table_id}"
    }
  }
}

output "traffic_router_function" {
  description = "Information about the traffic routing Cloud Function"
  value = {
    name         = google_cloudfunctions_function.traffic_router.name
    trigger_url  = google_cloudfunctions_function.traffic_router.https_trigger_url
    function_url = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.traffic_router.name}?project=${var.project_id}"
  }
}

output "service_extension" {
  description = "Information about the Service Extension"
  value = {
    name = google_service_extensions_lb_traffic_extension.intelligent_routing.name
    id   = google_service_extensions_lb_traffic_extension.intelligent_routing.id
  }
}

output "analytics_workflow" {
  description = "Information about the analytics Cloud Workflow"
  value = {
    name         = google_workflows_workflow.analytics_processor.name
    workflow_url = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.analytics_processor.name}?project=${var.project_id}"
  }
}

output "backend_services" {
  description = "Information about backend services"
  value = {
    service_a = {
      name = google_compute_backend_service.service_a_backend.name
      id   = google_compute_backend_service.service_a_backend.id
    }
    service_b = {
      name = google_compute_backend_service.service_b_backend.name
      id   = google_compute_backend_service.service_b_backend.id
    }
    service_c = {
      name = google_compute_backend_service.service_c_backend.name
      id   = google_compute_backend_service.service_c_backend.id
    }
  }
}

output "network_endpoint_groups" {
  description = "Information about Network Endpoint Groups"
  value = {
    service_a = {
      name = google_compute_region_network_endpoint_group.service_a_neg.name
      id   = google_compute_region_network_endpoint_group.service_a_neg.id
    }
    service_b = {
      name = google_compute_region_network_endpoint_group.service_b_neg.name
      id   = google_compute_region_network_endpoint_group.service_b_neg.id
    }
    service_c = {
      name = google_compute_region_network_endpoint_group.service_c_neg.name
      id   = google_compute_region_network_endpoint_group.service_c_neg.id
    }
  }
}

output "service_accounts" {
  description = "Service accounts created for the solution"
  value = {
    cloud_run_sa = {
      email = google_service_account.cloud_run_sa.email
      name  = google_service_account.cloud_run_sa.name
    }
    function_sa = {
      email = google_service_account.function_sa.email
      name  = google_service_account.function_sa.name
    }
    workflow_sa = {
      email = google_service_account.workflow_sa.email
      name  = google_service_account.workflow_sa.name
    }
  }
}

output "logging_sink" {
  description = "Information about the Cloud Logging sink"
  value = {
    name        = google_logging_project_sink.traffic_analytics_sink.name
    destination = google_logging_project_sink.traffic_analytics_sink.destination
    filter      = google_logging_project_sink.traffic_analytics_sink.filter
  }
}

output "health_check" {
  description = "Information about the health check"
  value = {
    name = google_compute_health_check.cloud_run_health_check.name
    id   = google_compute_health_check.cloud_run_health_check.id
  }
}

output "url_map" {
  description = "Information about the URL map"
  value = {
    name = google_compute_url_map.intelligent_lb.name
    id   = google_compute_url_map.intelligent_lb.id
  }
}

output "target_proxy" {
  description = "Information about the target HTTP proxy"
  value = {
    name = google_compute_target_http_proxy.intelligent_proxy.name
    id   = google_compute_target_http_proxy.intelligent_proxy.id
  }
}

output "forwarding_rule" {
  description = "Information about the global forwarding rule"
  value = {
    name = google_compute_global_forwarding_rule.default.name
    id   = google_compute_global_forwarding_rule.default.id
  }
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

# BigQuery Data Canvas Access Instructions
output "bigquery_data_canvas_instructions" {
  description = "Instructions for accessing BigQuery Data Canvas"
  value = <<-EOT
    To access BigQuery Data Canvas for natural language analytics:
    
    1. Navigate to BigQuery in the Google Cloud Console:
       https://console.cloud.google.com/bigquery?project=${var.project_id}
    
    2. Select the dataset: ${google_bigquery_dataset.traffic_analytics.dataset_id}
    
    3. Use the Data Canvas feature to ask natural language questions like:
       - "Show me the slowest services in the last hour"
       - "Which routing decisions had the highest confidence scores?"
       - "What are the traffic patterns by time of day?"
    
    4. Access the tables directly:
       - Load Balancer Metrics: ${google_bigquery_table.lb_metrics.table_id}
       - Routing Decisions: ${google_bigquery_table.routing_decisions.table_id}
  EOT
}

# Testing Commands
output "testing_commands" {
  description = "Commands for testing the intelligent routing system"
  value = <<-EOT
    Test the intelligent routing system with these commands:
    
    # Basic connectivity test
    curl -s -o /dev/null -w "Status: %%{http_code}, Time: %%{time_total}s\n" \
      http://${google_compute_global_forwarding_rule.default.ip_address}/
    
    # Test different routing paths
    curl -s -w "Path: /api/fast/test, Status: %%{http_code}, Time: %%{time_total}s\n" \
      -o /dev/null http://${google_compute_global_forwarding_rule.default.ip_address}/api/fast/test
    
    curl -s -w "Path: /api/standard/process, Status: %%{http_code}, Time: %%{time_total}s\n" \
      -o /dev/null http://${google_compute_global_forwarding_rule.default.ip_address}/api/standard/process
    
    curl -s -w "Path: /api/intensive/compute, Status: %%{http_code}, Time: %%{time_total}s\n" \
      -o /dev/null http://${google_compute_global_forwarding_rule.default.ip_address}/api/intensive/compute
    
    # Execute analytics workflow
    gcloud workflows execute ${google_workflows_workflow.analytics_processor.name} \
      --location=${var.region}
  EOT
}

# Cleanup Instructions
output "cleanup_instructions" {
  description = "Instructions for cleaning up resources"
  value = <<-EOT
    To clean up all resources created by this Terraform configuration:
    
    1. Run terraform destroy:
       terraform destroy -auto-approve
    
    2. Verify all resources are deleted in the Google Cloud Console
    
    3. Clean up any remaining log data if needed:
       bq rm -rf --dataset ${var.project_id}:${google_bigquery_dataset.traffic_analytics.dataset_id}
    
    Note: Some resources may have deletion protection or require manual cleanup.
  EOT
}