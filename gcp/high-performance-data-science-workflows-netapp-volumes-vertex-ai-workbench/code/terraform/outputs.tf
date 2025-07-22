# Outputs for high-performance data science workflows with NetApp Volumes and Vertex AI Workbench
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Project and Region Information
output "project_id" {
  description = "The Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where regional resources are deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources are deployed"
  value       = var.zone
}

# Network Infrastructure Outputs
output "network_name" {
  description = "Name of the VPC network created for the ML environment"
  value       = google_compute_network.netapp_ml_network.name
}

output "network_self_link" {
  description = "Self-link of the VPC network for reference in other configurations"
  value       = google_compute_network.netapp_ml_network.self_link
}

output "subnet_name" {
  description = "Name of the subnet created for ML workloads"
  value       = google_compute_subnetwork.netapp_ml_subnet.name
}

output "subnet_self_link" {
  description = "Self-link of the subnet for reference in other configurations"
  value       = google_compute_subnetwork.netapp_ml_subnet.self_link
}

output "subnet_cidr_range" {
  description = "CIDR range of the subnet for network planning"
  value       = google_compute_subnetwork.netapp_ml_subnet.ip_cidr_range
}

# NetApp Volumes Storage Outputs
output "storage_pool_name" {
  description = "Name of the NetApp storage pool for high-performance data access"
  value       = google_netapp_storage_pool.ml_storage_pool.name
}

output "storage_pool_id" {
  description = "Unique identifier of the NetApp storage pool"
  value       = google_netapp_storage_pool.ml_storage_pool.id
}

output "storage_pool_service_level" {
  description = "Service level of the NetApp storage pool (performance tier)"
  value       = google_netapp_storage_pool.ml_storage_pool.service_level
}

output "storage_pool_capacity_gib" {
  description = "Total capacity of the NetApp storage pool in GiB"
  value       = google_netapp_storage_pool.ml_storage_pool.capacity_gib
}

output "volume_name" {
  description = "Name of the NetApp volume for ML datasets"
  value       = google_netapp_volume.ml_datasets_volume.name
}

output "volume_id" {
  description = "Unique identifier of the NetApp volume"
  value       = google_netapp_volume.ml_datasets_volume.id
}

output "volume_capacity_gib" {
  description = "Capacity of the NetApp volume in GiB"
  value       = google_netapp_volume.ml_datasets_volume.capacity_gib
}

output "volume_share_name" {
  description = "NFS share name for the NetApp volume"
  value       = google_netapp_volume.ml_datasets_volume.share_name
}

output "volume_protocols" {
  description = "File system protocols supported by the NetApp volume"
  value       = google_netapp_volume.ml_datasets_volume.protocols
}

output "volume_mount_options" {
  description = "Mount options for the NetApp volume including IP and export path"
  value       = google_netapp_volume.ml_datasets_volume.mount_options
  sensitive   = false
}

output "volume_export_path" {
  description = "NFS export path for mounting the NetApp volume"
  value       = try(google_netapp_volume.ml_datasets_volume.mount_options[0].export_full_path, "")
}

output "volume_ip_address" {
  description = "IP address for mounting the NetApp volume"
  value       = try(google_netapp_volume.ml_datasets_volume.mount_options[0].export, "")
}

# Vertex AI Workbench Outputs
output "workbench_instance_name" {
  description = "Name of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.name
}

output "workbench_instance_id" {
  description = "Unique identifier of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.id
}

output "workbench_machine_type" {
  description = "Machine type of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.gce_setup[0].machine_type
}

output "workbench_state" {
  description = "Current state of the Vertex AI Workbench instance"
  value       = google_workbench_instance.ml_workbench.state
}

output "workbench_proxy_uri" {
  description = "Proxy URI for accessing the Jupyter notebook interface"
  value       = google_workbench_instance.ml_workbench.proxy_uri
  sensitive   = false
}

output "workbench_external_ip" {
  description = "External IP address of the Workbench instance (if assigned)"
  value       = try(google_workbench_instance.ml_workbench.gce_setup[0].network_interfaces[0].access_configs[0].nat_ip, "")
}

output "workbench_internal_ip" {
  description = "Internal IP address of the Workbench instance"
  value       = try(google_workbench_instance.ml_workbench.gce_setup[0].network_interfaces[0].network_ip, "")
}

output "workbench_gpu_config" {
  description = "GPU configuration of the Workbench instance"
  value = var.enable_gpu ? {
    type  = var.gpu_type
    count = var.gpu_count
  } : null
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for data lake integration"
  value       = google_storage_bucket.ml_datalake.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_datalake.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_datalake.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.ml_datalake.storage_class
}

# Access and Connection Information
output "nfs_mount_command" {
  description = "Command to manually mount the NetApp volume on compute instances"
  value = format(
    "sudo mount -t nfs4 -o %s %s:%s /mnt/ml-datasets",
    local.nfs_mount_options,
    try(google_netapp_volume.ml_datasets_volume.mount_options[0].export, ""),
    try(google_netapp_volume.ml_datasets_volume.mount_options[0].export_full_path, "")
  )
}

output "jupyter_access_url" {
  description = "URL to access the Jupyter notebook interface"
  value       = google_workbench_instance.ml_workbench.proxy_uri
}

output "ssh_command" {
  description = "Command to SSH into the Workbench instance"
  value = format(
    "gcloud compute ssh %s --zone=%s --project=%s",
    google_workbench_instance.ml_workbench.name,
    var.zone,
    var.project_id
  )
}

# Data Pipeline Integration
output "gsutil_sync_command" {
  description = "Command to sync data between NetApp volume and Cloud Storage"
  value = format(
    "gsutil -m rsync -r /mnt/ml-datasets/models/ gs://%s/models/",
    google_storage_bucket.ml_datalake.name
  )
}

# Resource Labels and Tags
output "common_labels" {
  description = "Common labels applied to all resources for management and billing"
  value       = local.common_labels
}

output "network_tags" {
  description = "Network tags applied to the Workbench instance for firewall rules"
  value       = var.network_tags
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure (USD)"
  value = {
    netapp_storage_pool = format("~$%.2f", var.storage_pool_capacity_gib * 0.35)  # $0.35/GB/month for Premium
    netapp_volume      = format("~$%.2f", var.volume_capacity_gib * 0.35)        # Volume cost included in pool
    workbench_instance = format("~$%.2f", 24 * 30 * 0.50)                       # ~$0.50/hour for standard instance
    cloud_storage      = "~$20-50 (depending on usage)"                          # Variable based on data volume
    network_egress     = "~$10-30 (depending on usage)"                          # Variable based on data transfer
    total_estimate     = format("~$%.2f - $%.2f", 
      (var.storage_pool_capacity_gib * 0.35) + (24 * 30 * 0.50) + 30,
      (var.storage_pool_capacity_gib * 0.35) + (24 * 30 * 0.50) + 80
    )
  }
}

# Performance Information
output "performance_characteristics" {
  description = "Performance characteristics of the deployed storage and compute"
  value = {
    netapp_service_level = var.storage_service_level
    expected_throughput = var.storage_service_level == "EXTREME" ? "Up to 4.5 GiB/sec" : 
                         var.storage_service_level == "PREMIUM" ? "Up to 64 MiB/s per TiB" : 
                         "Custom performance (FLEX)"
    expected_latency    = "Sub-millisecond for NetApp volumes"
    gpu_acceleration    = var.enable_gpu ? "${var.gpu_type} x${var.gpu_count}" : "None"
    network_performance = "Enhanced with gVNIC for optimal throughput"
  }
}

# Environment Configuration
output "deployment_summary" {
  description = "Summary of the deployed high-performance data science environment"
  value = {
    environment_type    = "High-Performance Data Science Workflow"
    storage_solution   = "Google Cloud NetApp Volumes"
    compute_platform   = "Vertex AI Workbench"
    collaboration_model = "Shared NFS storage with individual compute instances"
    backup_strategy    = "Cloud Storage integration with versioning"
    security_features  = var.enable_shielded_vm ? "Shielded VM enabled" : "Standard security"
    deployment_time    = "~15-20 minutes"
    ready_for_use     = "After Workbench instance reaches ACTIVE state"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Access Jupyter notebook interface using the jupyter_access_url",
    "2. Verify NetApp volume mount at /mnt/ml-datasets in the Workbench instance",
    "3. Run the performance test notebook to validate storage performance",
    "4. Upload your datasets to /mnt/ml-datasets/raw-data/",
    "5. Use /mnt/ml-datasets/notebooks/ for collaborative notebook development",
    "6. Sync trained models to Cloud Storage using the provided sync script",
    "7. Monitor resource usage and costs in the Google Cloud Console"
  ]
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting commands and information"
  value = {
    check_volume_mount = "df -h /mnt/ml-datasets"
    check_nfs_service  = "systemctl status nfs-client"
    view_startup_logs  = "sudo tail -f /var/log/startup-script.log"
    test_storage_performance = "python /mnt/ml-datasets/notebooks/netapp_performance_test.ipynb"
    check_gpu_status   = var.enable_gpu ? "nvidia-smi" : "N/A - GPU not enabled"
    workbench_console  = "Google Cloud Console > Vertex AI > Workbench"
  }
}