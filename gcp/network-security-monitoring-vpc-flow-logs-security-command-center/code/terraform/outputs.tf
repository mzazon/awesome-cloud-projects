# Output values for Network Security Monitoring Infrastructure
# These outputs provide important information about the deployed resources

# Project and Location Information
output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = local.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were deployed"
  value       = var.zone
}

# Network Infrastructure Outputs
output "vpc_network_id" {
  description = "The ID of the created VPC network"
  value       = google_compute_network.security_monitoring_vpc.id
}

output "vpc_network_name" {
  description = "The name of the created VPC network"
  value       = google_compute_network.security_monitoring_vpc.name
}

output "vpc_network_self_link" {
  description = "The self-link of the created VPC network"
  value       = google_compute_network.security_monitoring_vpc.self_link
}

output "subnet_id" {
  description = "The ID of the monitored subnet"
  value       = google_compute_subnetwork.monitored_subnet.id
}

output "subnet_name" {
  description = "The name of the monitored subnet"
  value       = google_compute_subnetwork.monitored_subnet.name
}

output "subnet_cidr" {
  description = "The CIDR block of the monitored subnet"
  value       = google_compute_subnetwork.monitored_subnet.ip_cidr_range
}

output "subnet_self_link" {
  description = "The self-link of the monitored subnet"
  value       = google_compute_subnetwork.monitored_subnet.self_link
}

# Compute Instance Outputs
output "test_vm_id" {
  description = "The ID of the test VM instance"
  value       = google_compute_instance.test_vm.id
}

output "test_vm_name" {
  description = "The name of the test VM instance"
  value       = google_compute_instance.test_vm.name
}

output "test_vm_internal_ip" {
  description = "The internal IP address of the test VM instance"
  value       = google_compute_instance.test_vm.network_interface[0].network_ip
}

output "test_vm_external_ip" {
  description = "The external IP address of the test VM instance"
  value       = google_compute_instance.test_vm.network_interface[0].access_config[0].nat_ip
}

output "test_vm_self_link" {
  description = "The self-link of the test VM instance"
  value       = google_compute_instance.test_vm.self_link
}

output "test_vm_service_account_email" {
  description = "The email of the service account used by the test VM"
  value       = google_service_account.test_vm_sa.email
}

# Firewall Rules Outputs
output "firewall_rules" {
  description = "Information about created firewall rules"
  value = {
    ssh_rule = {
      name      = google_compute_firewall.allow_ssh.name
      id        = google_compute_firewall.allow_ssh.id
      ports     = google_compute_firewall.allow_ssh.allow[0].ports
      sources   = google_compute_firewall.allow_ssh.source_ranges
    }
    http_rule = {
      name      = google_compute_firewall.allow_http.name
      id        = google_compute_firewall.allow_http.id
      ports     = google_compute_firewall.allow_http.allow[0].ports
      sources   = google_compute_firewall.allow_http.source_ranges
    }
    internal_rule = {
      name      = google_compute_firewall.allow_internal.name
      id        = google_compute_firewall.allow_internal.id
      sources   = google_compute_firewall.allow_internal.source_ranges
    }
  }
}

# Logging Infrastructure Outputs
output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset for VPC Flow Logs"
  value       = google_bigquery_dataset.security_monitoring.dataset_id
}

output "bigquery_dataset_location" {
  description = "The location of the BigQuery dataset"
  value       = google_bigquery_dataset.security_monitoring.location
}

output "logging_sink_name" {
  description = "The name of the logging sink for VPC Flow Logs"
  value       = google_logging_project_sink.vpc_flow_logs_sink.name
}

output "logging_sink_destination" {
  description = "The destination of the logging sink"
  value       = google_logging_project_sink.vpc_flow_logs_sink.destination
}

output "logging_sink_writer_identity" {
  description = "The writer identity (service account) of the logging sink"
  value       = google_logging_project_sink.vpc_flow_logs_sink.writer_identity
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for security findings"
  value       = google_pubsub_topic.security_findings.name
}

output "pubsub_topic_id" {
  description = "The ID of the Pub/Sub topic for security findings"
  value       = google_pubsub_topic.security_findings.id
}

# Monitoring Outputs
output "monitoring_alert_policies" {
  description = "Information about created monitoring alert policies"
  value = var.enable_monitoring_alerts ? {
    high_traffic_alert = {
      name         = google_monitoring_alert_policy.high_traffic_alert.display_name
      id           = google_monitoring_alert_policy.high_traffic_alert.id
      enabled      = google_monitoring_alert_policy.high_traffic_alert.enabled
      threshold    = var.high_traffic_threshold_bytes
    }
    suspicious_connections_alert = {
      name         = google_monitoring_alert_policy.suspicious_connections_alert.display_name
      id           = google_monitoring_alert_policy.suspicious_connections_alert.id
      enabled      = google_monitoring_alert_policy.suspicious_connections_alert.enabled
      threshold    = var.suspicious_connections_threshold
    }
  } : {}
}

output "monitoring_dashboard_id" {
  description = "The ID of the network security monitoring dashboard"
  value       = google_monitoring_dashboard.network_security_dashboard.id
}

output "notification_channel_id" {
  description = "The ID of the email notification channel (if configured)"
  value       = length(var.notification_emails) > 0 ? google_monitoring_notification_channel.email_notification[0].id : null
}

# Security and Access Information
output "vpc_flow_logs_configuration" {
  description = "Configuration details of VPC Flow Logs"
  value = {
    enabled              = var.enable_flow_logs
    sampling_rate        = var.flow_log_sampling_rate
    aggregation_interval = var.flow_log_aggregation_interval
    metadata_fields      = google_compute_subnetwork.monitored_subnet.log_config[0].metadata_fields
  }
}

# Quick Access URLs and Commands
output "bigquery_console_url" {
  description = "URL to access the BigQuery dataset in Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${local.project_id}&ws=!1m5!1m4!4m3!1s${local.project_id}!2s${google_bigquery_dataset.security_monitoring.dataset_id}!3e1"
}

output "monitoring_console_url" {
  description = "URL to access Cloud Monitoring in Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring?project=${local.project_id}"
}

output "vpc_flow_logs_query" {
  description = "Sample BigQuery query to analyze VPC Flow Logs"
  value       = <<-EOT
    SELECT 
      timestamp,
      jsonPayload.connection.src_ip,
      jsonPayload.connection.dest_ip,
      jsonPayload.connection.src_port,
      jsonPayload.connection.dest_port,
      jsonPayload.connection.protocol,
      jsonPayload.bytes_sent,
      jsonPayload.packets_sent
    FROM `${local.project_id}.${google_bigquery_dataset.security_monitoring.dataset_id}.compute_googleapis_com_vpc_flows_*`
    WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    ORDER BY timestamp DESC
    LIMIT 100
  EOT
}

# SSH Command for VM Access
output "ssh_command" {
  description = "Command to SSH into the test VM instance"
  value       = "gcloud compute ssh ${google_compute_instance.test_vm.name} --zone=${var.zone} --project=${local.project_id}"
}

# Web Server Access
output "web_server_url" {
  description = "URL to access the test web server"
  value       = "http://${google_compute_instance.test_vm.network_interface[0].access_config[0].nat_ip}/"
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources (USD)"
  value = {
    note           = "Costs are estimates and may vary based on actual usage"
    compute_instance = {
      type     = var.machine_type
      estimate = "~$5-10/month for e2-micro instance"
    }
    vpc_flow_logs = {
      note     = "Cost depends on traffic volume"
      estimate = "~$0.50 per GB of logs generated"
    }
    bigquery_storage = {
      note     = "First 10GB per month is free"
      estimate = "~$0.02 per GB stored per month"
    }
    cloud_monitoring = {
      note     = "First 150 metrics are free"
      estimate = "~$0.258 per metric per month"
    }
    total_estimate = "~$10-20/month for light usage"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    vpc_network    = google_compute_network.security_monitoring_vpc.name
    subnet         = google_compute_subnetwork.monitored_subnet.name
    vm_instance    = google_compute_instance.test_vm.name
    firewall_rules = [
      google_compute_firewall.allow_ssh.name,
      google_compute_firewall.allow_http.name,
      google_compute_firewall.allow_internal.name
    ]
    bigquery_dataset = google_bigquery_dataset.security_monitoring.dataset_id
    logging_sink     = google_logging_project_sink.vpc_flow_logs_sink.name
    pubsub_topic     = google_pubsub_topic.security_findings.name
    alert_policies   = var.enable_monitoring_alerts ? [
      google_monitoring_alert_policy.high_traffic_alert.display_name,
      google_monitoring_alert_policy.suspicious_connections_alert.display_name
    ] : []
    dashboard = google_monitoring_dashboard.network_security_dashboard.id
  }
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the security monitoring setup"
  value = {
    check_flow_logs = "gcloud logging read 'resource.type=\"gce_subnetwork\" AND resource.labels.subnetwork_name=\"${google_compute_subnetwork.monitored_subnet.name}\"' --limit=5 --project=${local.project_id}"
    
    check_vm_logs = "gcloud logging read 'resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${google_compute_instance.test_vm.instance_id}\"' --limit=10 --project=${local.project_id}"
    
    test_bigquery_access = "bq query --use_legacy_sql=false 'SELECT COUNT(*) as total_records FROM `${local.project_id}.${google_bigquery_dataset.security_monitoring.dataset_id}.compute_googleapis_com_vpc_flows_*` WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)'"
    
    check_alerts = "gcloud alpha monitoring policies list --filter='displayName:(\"High Network Traffic\" OR \"Suspicious Connection\")' --project=${local.project_id}"
    
    generate_test_traffic = "gcloud compute ssh ${google_compute_instance.test_vm.name} --zone=${var.zone} --project=${local.project_id} --command='/usr/local/bin/generate-test-traffic.sh'"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployed infrastructure"
  value = {
    firewall_review = "Review firewall rules and restrict source ranges to specific IP addresses or ranges"
    ssh_access = "Consider using IAP for SSH access instead of allowing SSH from 0.0.0.0/0"
    flow_logs_retention = "Configure appropriate log retention policies based on compliance requirements"
    alerting = "Configure notification channels and escalation policies for security alerts"
    monitoring = "Set up additional custom metrics and alerts based on your specific security requirements"
    access_controls = "Implement least privilege access using IAM roles and service accounts"
  }
}