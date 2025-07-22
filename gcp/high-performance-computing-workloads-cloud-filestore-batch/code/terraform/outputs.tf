# Outputs for the HPC workloads with Cloud Filestore and Batch infrastructure

# Network Infrastructure Outputs
output "vpc_network_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.hpc_network.name
}

output "vpc_network_id" {
  description = "ID of the created VPC network"
  value       = google_compute_network.hpc_network.id
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = google_compute_subnetwork.hpc_subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the created subnet"
  value       = google_compute_subnetwork.hpc_subnet.ip_cidr_range
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = google_compute_subnetwork.hpc_subnet.id
}

# Filestore Outputs
output "filestore_instance_name" {
  description = "Name of the Cloud Filestore instance"
  value       = google_filestore_instance.hpc_storage.name
}

output "filestore_instance_id" {
  description = "ID of the Cloud Filestore instance"
  value       = google_filestore_instance.hpc_storage.id
}

output "filestore_ip_address" {
  description = "IP address of the Cloud Filestore instance"
  value       = google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]
}

output "filestore_file_share_name" {
  description = "Name of the file share on the Filestore instance"
  value       = google_filestore_instance.hpc_storage.file_shares[0].name
}

output "filestore_capacity_gb" {
  description = "Capacity of the Filestore instance in GB"
  value       = google_filestore_instance.hpc_storage.file_shares[0].capacity_gb
}

output "filestore_tier" {
  description = "Service tier of the Filestore instance"
  value       = google_filestore_instance.hpc_storage.tier
}

output "filestore_mount_command" {
  description = "Command to mount the Filestore share on compute instances"
  value       = "sudo mount -t nfs ${google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]}:/${google_filestore_instance.hpc_storage.file_shares[0].name} /mnt/${google_filestore_instance.hpc_storage.file_shares[0].name}"
}

# Compute Infrastructure Outputs
output "instance_template_name" {
  description = "Name of the compute instance template"
  value       = google_compute_instance_template.hpc_template.name
}

output "instance_template_id" {
  description = "ID of the compute instance template"
  value       = google_compute_instance_template.hpc_template.id
}

output "instance_group_manager_name" {
  description = "Name of the managed instance group"
  value       = google_compute_region_instance_group_manager.hpc_group.name
}

output "instance_group_manager_id" {
  description = "ID of the managed instance group"
  value       = google_compute_region_instance_group_manager.hpc_group.id
}

output "autoscaler_name" {
  description = "Name of the autoscaler"
  value       = google_compute_region_autoscaler.hpc_autoscaler.name
}

output "autoscaler_target_size" {
  description = "Current target size of the autoscaler"
  value       = google_compute_region_autoscaler.hpc_autoscaler.autoscaling_policy[0].min_replicas
}

output "service_account_email" {
  description = "Email address of the HPC compute service account"
  value       = google_service_account.hpc_compute.email
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.hpc_dashboard[0].id}?project=${var.project_id}" : "Monitoring disabled"
}

output "notification_channel_name" {
  description = "Name of the monitoring notification channel"
  value       = var.enable_monitoring && var.monitoring_notification_email != "" ? google_monitoring_notification_channel.email[0].display_name : "No notification channel configured"
}

# Security and Access Outputs
output "firewall_rules" {
  description = "List of created firewall rules"
  value = {
    internal = google_compute_firewall.hpc_internal.name
    ssh      = google_compute_firewall.hpc_ssh.name
    nfs      = google_compute_firewall.hpc_nfs.name
  }
}

# Batch Processing Information
output "batch_job_example" {
  description = "Example gcloud command to submit a batch job"
  value = <<-EOT
    # Create a batch job configuration file and submit:
    gcloud batch jobs submit hpc-simulation-job \
      --location=${var.region} \
      --config=batch-job-config.json

    # Example batch job config (save as batch-job-config.json):
    {
      "taskGroups": [{
        "taskSpec": {
          "runnables": [{
            "script": {
              "text": "#!/bin/bash\necho 'HPC simulation starting'\nmkdir -p /mnt/${google_filestore_instance.hpc_storage.file_shares[0].name}/results\necho 'Job completed' > /mnt/${google_filestore_instance.hpc_storage.file_shares[0].name}/results/job_$BATCH_TASK_INDEX.log"
            }
          }],
          "computeResource": {
            "cpuMilli": 2000,
            "memoryMib": 4096
          },
          "volumes": [{
            "nfs": {
              "server": "${google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]}",
              "remotePath": "/${google_filestore_instance.hpc_storage.file_shares[0].name}"
            },
            "mountPath": "/mnt/${google_filestore_instance.hpc_storage.file_shares[0].name}"
          }]
        },
        "taskCount": 4
      }],
      "allocationPolicy": {
        "instances": [{
          "instanceTemplate": {
            "machineType": "${var.instance_machine_type}"
          }
        }],
        "location": {
          "allowedLocations": ["zones/${var.zone}"]
        },
        "network": {
          "networkInterfaces": [{
            "network": "${google_compute_network.hpc_network.id}",
            "subnetwork": "${google_compute_subnetwork.hpc_subnet.id}"
          }]
        }
      }
    }
  EOT
}

# Resource Information Summary
output "deployment_summary" {
  description = "Summary of deployed HPC infrastructure resources"
  value = {
    project_id = var.project_id
    region     = var.region
    zone       = var.zone
    
    network = {
      vpc_name    = google_compute_network.hpc_network.name
      subnet_name = google_compute_subnetwork.hpc_subnet.name
      subnet_cidr = google_compute_subnetwork.hpc_subnet.ip_cidr_range
    }
    
    storage = {
      filestore_name     = google_filestore_instance.hpc_storage.name
      filestore_ip       = google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]
      filestore_capacity = "${google_filestore_instance.hpc_storage.file_shares[0].capacity_gb} GB"
      filestore_tier     = google_filestore_instance.hpc_storage.tier
    }
    
    compute = {
      instance_template = google_compute_instance_template.hpc_template.name
      instance_group    = google_compute_region_instance_group_manager.hpc_group.name
      machine_type      = var.instance_machine_type
      min_instances     = var.autoscaler_min_replicas
      max_instances     = var.autoscaler_max_replicas
    }
    
    monitoring = {
      enabled           = var.enable_monitoring
      dashboard_enabled = var.enable_monitoring
      notifications     = var.monitoring_notification_email != "" ? "Enabled" : "Disabled"
    }
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = <<-EOT
    Estimated Monthly Costs (USD):
    - Filestore ${var.filestore_tier} (${var.filestore_capacity_gb}GB): $${var.filestore_tier == "ENTERPRISE" ? var.filestore_capacity_gb * 0.30 : var.filestore_capacity_gb * 0.20}
    - Compute instances (varies by usage): $${var.autoscaler_max_replicas * 50} - $${var.autoscaler_max_replicas * 150}
    - Network and monitoring: $20 - $50
    
    Note: Actual costs depend on usage patterns, data transfer, and compute duration.
    Use Google Cloud Pricing Calculator for detailed estimates.
  EOT
}

# Next Steps and Usage Instructions
output "next_steps" {
  description = "Instructions for using the deployed HPC infrastructure"
  value = <<-EOT
    HPC Infrastructure Deployment Complete!
    
    Next Steps:
    1. Verify Filestore access: gcloud filestore instances describe ${google_filestore_instance.hpc_storage.name} --location=${var.zone}
    
    2. Submit batch jobs using the example configuration in 'batch_job_example' output
    
    3. Monitor infrastructure: 
       - Visit the monitoring dashboard (see monitoring_dashboard_url output)
       - Check compute instance metrics and Filestore capacity
    
    4. Access compute instances (if needed):
       - List instances: gcloud compute instances list --filter="labels.component=hpc-infrastructure"
       - SSH via IAP: gcloud compute ssh <instance-name> --zone=${var.zone} --tunnel-through-iap
    
    5. Mount Filestore on additional systems:
       ${google_filestore_instance.hpc_storage.networks[0].ip_addresses[0]}:/${google_filestore_instance.hpc_storage.file_shares[0].name}
    
    For cleanup: terraform destroy
  EOT
}