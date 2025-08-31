# Outputs for AlloyDB Omni and Hyperdisk Extreme performance optimization

# Instance Information
output "instance_name" {
  description = "Name of the AlloyDB Omni compute instance"
  value       = google_compute_instance.alloydb_instance.name
}

output "instance_id" {
  description = "ID of the AlloyDB Omni compute instance"
  value       = google_compute_instance.alloydb_instance.instance_id
}

output "instance_zone" {
  description = "Zone where the AlloyDB Omni instance is deployed"
  value       = google_compute_instance.alloydb_instance.zone
}

output "instance_machine_type" {
  description = "Machine type of the AlloyDB Omni instance"
  value       = google_compute_instance.alloydb_instance.machine_type
}

output "instance_internal_ip" {
  description = "Internal IP address of the AlloyDB Omni instance"
  value       = google_compute_instance.alloydb_instance.network_interface[0].network_ip
}

output "instance_external_ip" {
  description = "External IP address of the AlloyDB Omni instance"
  value       = google_compute_instance.alloydb_instance.network_interface[0].access_config[0].nat_ip
}

# Storage Information
output "hyperdisk_name" {
  description = "Name of the Hyperdisk Extreme volume"
  value       = google_compute_disk.hyperdisk_extreme.name
}

output "hyperdisk_size" {
  description = "Size of the Hyperdisk Extreme volume in GB"
  value       = google_compute_disk.hyperdisk_extreme.size
}

output "hyperdisk_provisioned_iops" {
  description = "Provisioned IOPS for the Hyperdisk Extreme volume"
  value       = google_compute_disk.hyperdisk_extreme.provisioned_iops
}

output "hyperdisk_type" {
  description = "Type of the Hyperdisk volume"
  value       = google_compute_disk.hyperdisk_extreme.type
}

# AlloyDB Connection Information
output "alloydb_connection_host" {
  description = "Host for connecting to AlloyDB Omni (internal IP)"
  value       = google_compute_instance.alloydb_instance.network_interface[0].network_ip
}

output "alloydb_connection_port" {
  description = "Port for connecting to AlloyDB Omni PostgreSQL"
  value       = "5432"
}

output "alloydb_database_name" {
  description = "Default database name in AlloyDB Omni"
  value       = var.alloydb_database
}

output "alloydb_username" {
  description = "Username for connecting to AlloyDB Omni"
  value       = "postgres"
}

# Connection string for applications (excluding password for security)
output "alloydb_connection_string_template" {
  description = "PostgreSQL connection string template (password not included)"
  value       = "postgresql://postgres:<PASSWORD>@${google_compute_instance.alloydb_instance.network_interface[0].network_ip}:5432/${var.alloydb_database}"
}

# Cloud Function Information
output "cloud_function_name" {
  description = "Name of the performance scaling Cloud Function"
  value       = var.enable_cloud_function ? google_cloudfunctions_function.performance_scaler[0].name : null
}

output "cloud_function_url" {
  description = "URL of the performance scaling Cloud Function"
  value       = var.enable_cloud_function ? google_cloudfunctions_function.performance_scaler[0].https_trigger_url : null
}

output "cloud_function_region" {
  description = "Region where the Cloud Function is deployed"
  value       = var.enable_cloud_function ? google_cloudfunctions_function.performance_scaler[0].region : null
}

# Monitoring Information
output "monitoring_dashboard_id" {
  description = "ID of the AlloyDB Omni performance monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.alloydb_performance[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.alloydb_performance[0].dashboard_id}?project=${var.project_id}" : null
}

output "alert_policy_name" {
  description = "Name of the CPU utilization alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_cpu_alert[0].name : null
}

# SSH Connection Command
output "ssh_command" {
  description = "Command to SSH into the AlloyDB Omni instance"
  value       = "gcloud compute ssh ${google_compute_instance.alloydb_instance.name} --zone=${google_compute_instance.alloydb_instance.zone} --project=${var.project_id}"
}

# Performance Testing Commands
output "performance_test_commands" {
  description = "Commands for testing AlloyDB Omni performance"
  value = {
    fio_disk_test = "sudo fio --name=test --ioengine=libaio --iodepth=64 --rw=randread --bs=4k --direct=1 --size=1G --runtime=30 --numjobs=4 --filename=/var/lib/alloydb/test_file --group_reporting"
    psql_connect  = "docker exec -it alloydb-omni psql -U postgres -d ${var.alloydb_database}"
    monitor_performance = "/usr/local/bin/alloydb-monitor.sh"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    compute_instance = {
      name         = google_compute_instance.alloydb_instance.name
      machine_type = google_compute_instance.alloydb_instance.machine_type
      zone         = google_compute_instance.alloydb_instance.zone
      internal_ip  = google_compute_instance.alloydb_instance.network_interface[0].network_ip
      external_ip  = google_compute_instance.alloydb_instance.network_interface[0].access_config[0].nat_ip
    }
    storage = {
      name              = google_compute_disk.hyperdisk_extreme.name
      type              = google_compute_disk.hyperdisk_extreme.type
      size_gb           = google_compute_disk.hyperdisk_extreme.size
      provisioned_iops  = google_compute_disk.hyperdisk_extreme.provisioned_iops
    }
    cloud_function = var.enable_cloud_function ? {
      name        = google_cloudfunctions_function.performance_scaler[0].name
      url         = google_cloudfunctions_function.performance_scaler[0].https_trigger_url
      runtime     = google_cloudfunctions_function.performance_scaler[0].runtime
      memory_mb   = google_cloudfunctions_function.performance_scaler[0].available_memory_mb
    } : null
    monitoring = var.enable_monitoring ? {
      dashboard_id = google_monitoring_dashboard.alloydb_performance[0].dashboard_id
      alert_policy = google_monitoring_alert_policy.high_cpu_alert[0].name
    } : null
  }
}

# Cost Estimation Information
output "estimated_monthly_cost_info" {
  description = "Information about the estimated monthly costs for the resources"
  value = {
    note = "Cost estimates are approximate and vary by region and usage"
    compute_instance = "c3-highmem-8: ~$400-500/month (us-central1)"
    hyperdisk_extreme = "500GB at 100k IOPS: ~$1500-2000/month"
    cloud_function = "Minimal cost for low usage: ~$5-10/month"
    total_estimated = "~$1900-2500/month for high-performance database workload"
    cost_optimization = "Consider using smaller instances or Hyperdisk Balanced for non-production environments"
  }
}

# Next Steps and Usage Information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    verify_deployment = "SSH to instance and check AlloyDB Omni: ${google_compute_instance.alloydb_instance.name}"
    connect_to_database = "Use connection string with external IP or internal IP from same VPC"
    monitor_performance = "Check monitoring dashboard for real-time performance metrics"
    scale_performance = var.enable_cloud_function ? "Trigger scaling function: ${google_cloudfunctions_function.performance_scaler[0].https_trigger_url}" : "Cloud Function not enabled"
    load_test_data = "SSH to instance and run sample data loading scripts as described in recipe"
  }
}