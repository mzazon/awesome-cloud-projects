# Project and Network Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were deployed"
  value       = var.zone
}

output "network_name" {
  description = "Name of the VPC network created for the cluster"
  value       = google_compute_network.vpc_network.name
}

output "subnet_name" {
  description = "Name of the subnet created for the cluster"
  value       = google_compute_subnetwork.cluster_subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the cluster subnet"
  value       = google_compute_subnetwork.cluster_subnet.ip_cidr_range
}

# Cluster Information
output "cluster_name" {
  description = "Name of the HPC cluster"
  value       = var.cluster_name
}

output "slurm_controller_name" {
  description = "Name of the Slurm controller instance"
  value       = google_compute_instance.slurm_controller.name
}

output "slurm_controller_internal_ip" {
  description = "Internal IP address of the Slurm controller"
  value       = google_compute_instance.slurm_controller.network_interface[0].network_ip
}

output "slurm_controller_external_ip" {
  description = "External IP address of the Slurm controller"
  value       = google_compute_instance.slurm_controller.network_interface[0].access_config[0].nat_ip
}

output "slurm_login_name" {
  description = "Name of the Slurm login node"
  value       = google_compute_instance.slurm_login.name
}

output "slurm_login_internal_ip" {
  description = "Internal IP address of the Slurm login node"
  value       = google_compute_instance.slurm_login.network_interface[0].network_ip
}

output "slurm_login_external_ip" {
  description = "External IP address of the Slurm login node"
  value       = google_compute_instance.slurm_login.network_interface[0].access_config[0].nat_ip
}

output "compute_node_template" {
  description = "Name of the compute node instance template"
  value       = google_compute_instance_template.compute_node_template.name
}

output "gpu_node_template" {
  description = "Name of the GPU node instance template"
  value       = google_compute_instance_template.gpu_node_template.name
}

# Storage Information
output "bucket_name" {
  description = "Name of the Cloud Storage bucket for video data"
  value       = google_storage_bucket.video_data_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.video_data_bucket.url
}

output "filestore_name" {
  description = "Name of the Filestore instance"
  value       = google_filestore_instance.cluster_filestore.name
}

output "filestore_ip" {
  description = "IP address of the Filestore instance"
  value       = google_filestore_instance.cluster_filestore.networks[0].ip_addresses[0]
}

output "filestore_mount_path" {
  description = "Mount path for the Filestore shared filesystem"
  value       = "/shared"
}

# Service Account Information
output "service_account_email" {
  description = "Email of the service account used by cluster nodes"
  value       = google_service_account.cluster_service_account.email
}

output "service_account_id" {
  description = "ID of the service account used by cluster nodes"
  value       = google_service_account.cluster_service_account.account_id
}

# BigQuery Information
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for analysis results"
  value       = google_bigquery_dataset.video_analysis_dataset.dataset_id
}

output "bigquery_table_id" {
  description = "ID of the BigQuery table for analysis results"
  value       = google_bigquery_table.video_analysis_results.table_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.video_analysis_dataset.location
}

# Vertex AI Information
output "vertex_ai_dataset_name" {
  description = "Name of the Vertex AI dataset for model training"
  value       = google_vertex_ai_dataset.scientific_video_dataset.name
}

output "vertex_ai_dataset_id" {
  description = "ID of the Vertex AI dataset"
  value       = google_vertex_ai_dataset.scientific_video_dataset.id
}

output "vertex_ai_region" {
  description = "Region where Vertex AI resources are located"
  value       = var.ai_region
}

# Connection Information
output "ssh_command_controller" {
  description = "SSH command to connect to the Slurm controller"
  value       = "gcloud compute ssh ${google_compute_instance.slurm_controller.name} --zone=${var.zone}"
}

output "ssh_command_login" {
  description = "SSH command to connect to the Slurm login node"
  value       = "gcloud compute ssh ${google_compute_instance.slurm_login.name} --zone=${var.zone}"
}

# Cluster Configuration
output "max_compute_nodes" {
  description = "Maximum number of compute nodes configured"
  value       = var.max_compute_nodes
}

output "max_gpu_nodes" {
  description = "Maximum number of GPU nodes configured"
  value       = var.max_gpu_nodes
}

output "compute_machine_type" {
  description = "Machine type used for compute nodes"
  value       = var.cluster_machine_type
}

output "gpu_machine_type" {
  description = "Machine type used for GPU nodes"
  value       = var.gpu_machine_type
}

output "gpu_type" {
  description = "Type of GPU accelerator used"
  value       = var.gpu_type
}

# Data Processing Paths
output "raw_videos_path" {
  description = "GCS path for raw video uploads"
  value       = "gs://${google_storage_bucket.video_data_bucket.name}/raw-videos/"
}

output "processed_results_path" {
  description = "GCS path for processed analysis results"
  value       = "gs://${google_storage_bucket.video_data_bucket.name}/processed-results/"
}

output "model_artifacts_path" {
  description = "GCS path for model artifacts and training data"
  value       = "gs://${google_storage_bucket.video_data_bucket.name}/model-artifacts/"
}

output "dataflow_temp_path" {
  description = "GCS path for Dataflow temporary files"
  value       = "gs://${google_storage_bucket.video_data_bucket.name}/temp/"
}

output "dataflow_staging_path" {
  description = "GCS path for Dataflow staging files"
  value       = "gs://${google_storage_bucket.video_data_bucket.name}/staging/"
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
    
    === Scientific Video Analysis HPC Cluster ===
    
    1. Connect to the login node:
       ${format("gcloud compute ssh %s --zone=%s", google_compute_instance.slurm_login.name, var.zone)}
    
    2. Upload videos to the data bucket:
       gsutil cp your-video.mp4 gs://${google_storage_bucket.video_data_bucket.name}/raw-videos/
    
    3. Check cluster status:
       sinfo
       squeue
    
    4. Submit a video analysis job:
       sbatch /shared/scripts/submit-video-analysis.sh gs://${google_storage_bucket.video_data_bucket.name}/raw-videos/your-video.mp4
    
    5. View analysis results in BigQuery:
       bq query "SELECT * FROM ${var.project_id}.${var.dataset_id}.video_analysis_results LIMIT 10"
    
    6. Access Filestore shared storage:
       ls /shared/
    
    === Important Notes ===
    - The cluster auto-scales based on job demand
    - GPU nodes are automatically allocated for AI workloads
    - Monitor costs in the GCP Console
    - Analysis results are stored in BigQuery and Cloud Storage
    
  EOT
}

# Cost Monitoring
output "cost_monitoring_filter" {
  description = "Billing filter to monitor costs for this deployment"
  value       = "labels.cluster-name=${var.cluster_name}"
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up the deployment"
  value = <<-EOT
    
    === Cleanup Commands ===
    
    1. Destroy Terraform infrastructure:
       terraform destroy -auto-approve
    
    2. Verify all resources are deleted:
       gcloud compute instances list --filter="labels.cluster-name=${var.cluster_name}"
       gsutil ls | grep ${local.bucket_name}
       bq ls --filter="labels.cluster-name:${var.cluster_name}"
    
    3. Check for any remaining billable resources:
       gcloud billing accounts get-iam-policy BILLING_ACCOUNT_ID
    
  EOT
}