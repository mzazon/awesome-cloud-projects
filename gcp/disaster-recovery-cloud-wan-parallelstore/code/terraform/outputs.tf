# Outputs for GCP Disaster Recovery with Cloud WAN and Parallelstore
# This file defines output values that provide important information about the deployed infrastructure

#
# Network Infrastructure Outputs
#

output "primary_vpc_id" {
  description = "ID of the primary region VPC network"
  value       = google_compute_network.primary_vpc.id
}

output "primary_vpc_name" {
  description = "Name of the primary region VPC network"
  value       = google_compute_network.primary_vpc.name
}

output "primary_subnet_id" {
  description = "ID of the primary region subnet"
  value       = google_compute_subnetwork.primary_subnet.id
}

output "primary_subnet_cidr" {
  description = "CIDR block of the primary region subnet"
  value       = google_compute_subnetwork.primary_subnet.ip_cidr_range
}

output "secondary_vpc_id" {
  description = "ID of the secondary region VPC network"
  value       = google_compute_network.secondary_vpc.id
}

output "secondary_vpc_name" {
  description = "Name of the secondary region VPC network"
  value       = google_compute_network.secondary_vpc.name
}

output "secondary_subnet_id" {
  description = "ID of the secondary region subnet"
  value       = google_compute_subnetwork.secondary_subnet.id
}

output "secondary_subnet_cidr" {
  description = "CIDR block of the secondary region subnet"
  value       = google_compute_subnetwork.secondary_subnet.ip_cidr_range
}

#
# Network Connectivity Center (Cloud WAN) Outputs
#

output "wan_hub_id" {
  description = "ID of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.wan_hub.id
}

output "wan_hub_name" {
  description = "Name of the Network Connectivity Center hub"
  value       = google_network_connectivity_hub.wan_hub.name
}

output "primary_spoke_id" {
  description = "ID of the primary region spoke"
  value       = google_network_connectivity_spoke.primary_spoke.id
}

output "secondary_spoke_id" {
  description = "ID of the secondary region spoke"
  value       = google_network_connectivity_spoke.secondary_spoke.id
}

#
# VPN Connectivity Outputs
#

output "primary_vpn_gateway_id" {
  description = "ID of the primary region HA VPN gateway"
  value       = google_compute_ha_vpn_gateway.primary_vpn_gateway.id
}

output "secondary_vpn_gateway_id" {
  description = "ID of the secondary region HA VPN gateway"
  value       = google_compute_ha_vpn_gateway.secondary_vpn_gateway.id
}

output "primary_vpn_gateway_interfaces" {
  description = "Interface information for primary VPN gateway"
  value = [
    for interface in google_compute_ha_vpn_gateway.primary_vpn_gateway.vpn_interfaces : {
      id               = interface.id
      ip_address       = interface.ip_address
      interconnect_attachment = interface.interconnect_attachment
    }
  ]
}

output "secondary_vpn_gateway_interfaces" {
  description = "Interface information for secondary VPN gateway"
  value = [
    for interface in google_compute_ha_vpn_gateway.secondary_vpn_gateway.vpn_interfaces : {
      id               = interface.id
      ip_address       = interface.ip_address
      interconnect_attachment = interface.interconnect_attachment
    }
  ]
}

output "vpn_tunnel_primary_to_secondary" {
  description = "ID of the VPN tunnel from primary to secondary region"
  value       = google_compute_vpn_tunnel.primary_to_secondary.id
}

output "vpn_tunnel_secondary_to_primary" {
  description = "ID of the VPN tunnel from secondary to primary region"
  value       = google_compute_vpn_tunnel.secondary_to_primary.id
}

#
# Parallelstore Outputs
#

output "primary_parallelstore_id" {
  description = "ID of the primary Parallelstore instance"
  value       = google_parallelstore_instance.primary_storage.id
}

output "primary_parallelstore_name" {
  description = "Name of the primary Parallelstore instance"
  value       = google_parallelstore_instance.primary_storage.instance_id
}

output "primary_parallelstore_capacity" {
  description = "Capacity of the primary Parallelstore instance in GiB"
  value       = google_parallelstore_instance.primary_storage.capacity_gib
}

output "primary_parallelstore_access_points" {
  description = "Access points for the primary Parallelstore instance"
  value       = google_parallelstore_instance.primary_storage.access_points
}

output "secondary_parallelstore_id" {
  description = "ID of the secondary Parallelstore instance"
  value       = google_parallelstore_instance.secondary_storage.id
}

output "secondary_parallelstore_name" {
  description = "Name of the secondary Parallelstore instance"
  value       = google_parallelstore_instance.secondary_storage.instance_id
}

output "secondary_parallelstore_capacity" {
  description = "Capacity of the secondary Parallelstore instance in GiB"
  value       = google_parallelstore_instance.secondary_storage.capacity_gib
}

output "secondary_parallelstore_access_points" {
  description = "Access points for the secondary Parallelstore instance"
  value       = google_parallelstore_instance.secondary_storage.access_points
}

#
# Pub/Sub Infrastructure Outputs
#

output "health_alerts_topic_id" {
  description = "ID of the health alerts Pub/Sub topic"
  value       = google_pubsub_topic.health_alerts.id
}

output "failover_commands_topic_id" {
  description = "ID of the failover commands Pub/Sub topic"
  value       = google_pubsub_topic.failover_commands.id
}

output "replication_status_topic_id" {
  description = "ID of the replication status Pub/Sub topic"
  value       = google_pubsub_topic.replication_status.id
}

output "health_subscription_id" {
  description = "ID of the health alerts subscription"
  value       = google_pubsub_subscription.health_subscription.id
}

output "failover_subscription_id" {
  description = "ID of the failover commands subscription"
  value       = google_pubsub_subscription.failover_subscription.id
}

output "replication_subscription_id" {
  description = "ID of the replication status subscription"
  value       = google_pubsub_subscription.replication_subscription.id
}

#
# Cloud Functions Outputs
#

output "health_monitor_function_id" {
  description = "ID of the health monitoring Cloud Function"
  value       = google_cloudfunctions2_function.health_monitor.id
}

output "health_monitor_function_name" {
  description = "Name of the health monitoring Cloud Function"
  value       = google_cloudfunctions2_function.health_monitor.name
}

output "health_monitor_function_url" {
  description = "URL of the health monitoring Cloud Function"
  value       = google_cloudfunctions2_function.health_monitor.service_config[0].uri
}

output "replication_function_id" {
  description = "ID of the replication Cloud Function"
  value       = google_cloudfunctions2_function.replication.id
}

output "replication_function_name" {
  description = "Name of the replication Cloud Function"
  value       = google_cloudfunctions2_function.replication.name
}

#
# Cloud Workflows Outputs
#

output "dr_workflow_id" {
  description = "ID of the disaster recovery orchestration workflow"
  value       = google_workflows_workflow.dr_orchestrator.id
}

output "dr_workflow_name" {
  description = "Name of the disaster recovery orchestration workflow"
  value       = google_workflows_workflow.dr_orchestrator.name
}

output "dr_workflow_revision_id" {
  description = "Current revision ID of the disaster recovery workflow"
  value       = google_workflows_workflow.dr_orchestrator.revision_id
}

#
# Cloud Scheduler Outputs
#

output "replication_scheduler_job_id" {
  description = "ID of the replication scheduler job"
  value       = google_cloud_scheduler_job.replication_job.id
}

output "replication_scheduler_job_name" {
  description = "Name of the replication scheduler job"
  value       = google_cloud_scheduler_job.replication_job.name
}

output "replication_schedule" {
  description = "Cron schedule for automated replication"
  value       = google_cloud_scheduler_job.replication_job.schedule
}

#
# Service Account Outputs
#

output "health_monitor_service_account_email" {
  description = "Email of the health monitor service account"
  value       = google_service_account.health_monitor_sa.email
}

output "replication_service_account_email" {
  description = "Email of the replication service account"
  value       = google_service_account.replication_sa.email
}

output "workflow_service_account_email" {
  description = "Email of the workflow service account"
  value       = google_service_account.workflow_sa.email
}

#
# Cloud Storage Outputs
#

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.url
}

output "replication_staging_bucket_name" {
  description = "Name of the Cloud Storage bucket for replication staging"
  value       = google_storage_bucket.replication_staging.name
}

output "replication_staging_bucket_url" {
  description = "URL of the Cloud Storage bucket for replication staging"
  value       = google_storage_bucket.replication_staging.url
}

#
# Monitoring Outputs
#

output "monitoring_notification_channel_id" {
  description = "ID of the Pub/Sub monitoring notification channel"
  value       = var.enable_detailed_monitoring ? google_monitoring_notification_channel.pubsub_channel[0].id : null
}

output "monitoring_alert_policy_id" {
  description = "ID of the Parallelstore health monitoring alert policy"
  value       = var.enable_detailed_monitoring ? google_monitoring_alert_policy.parallelstore_health[0].id : null
}

#
# Configuration Summary Outputs
#

output "deployment_summary" {
  description = "Summary of the deployed disaster recovery infrastructure"
  value = {
    project_id                = var.project_id
    environment              = var.environment
    primary_region           = var.primary_region
    secondary_region         = var.secondary_region
    resource_prefix          = local.name_prefix
    parallelstore_capacity   = var.parallelstore_capacity_gib
    replication_schedule     = var.replication_schedule
    monitoring_enabled       = var.enable_detailed_monitoring
    deletion_protection      = var.enable_deletion_protection
  }
}

output "mount_commands" {
  description = "Commands to mount Parallelstore instances on compute instances"
  value = {
    primary_mount_command = "sudo mount -t lustre ${join(",", [for ap in google_parallelstore_instance.primary_storage.access_points : ap.network_endpoint])}:/${google_parallelstore_instance.primary_storage.instance_id} /mnt/parallelstore"
    secondary_mount_command = "sudo mount -t lustre ${join(",", [for ap in google_parallelstore_instance.secondary_storage.access_points : ap.network_endpoint])}:/${google_parallelstore_instance.secondary_storage.instance_id} /mnt/parallelstore"
  }
}

output "validation_commands" {
  description = "Commands to validate the disaster recovery deployment"
  value = {
    check_vpn_status = "gcloud compute vpn-tunnels describe ${google_compute_vpn_tunnel.primary_to_secondary.name} --region=${var.primary_region} --format='value(status)'"
    check_workflow_status = "gcloud workflows describe ${google_workflows_workflow.dr_orchestrator.name} --location=${var.primary_region} --format='value(state)'"
    test_health_function = "gcloud functions call ${google_cloudfunctions2_function.health_monitor.name} --region=${var.primary_region}"
    check_parallelstore_primary = "gcloud parallelstore instances describe ${google_parallelstore_instance.primary_storage.instance_id} --location=${var.primary_zone} --format='value(state)'"
    check_parallelstore_secondary = "gcloud parallelstore instances describe ${google_parallelstore_instance.secondary_storage.instance_id} --location=${var.secondary_zone} --format='value(state)'"
  }
}

#
# BGP and Routing Information
#

output "bgp_configuration" {
  description = "BGP configuration details for VPN connectivity"
  value = {
    primary_asn   = var.bgp_asn_primary
    secondary_asn = var.bgp_asn_secondary
    primary_bgp_ip = google_compute_router_interface.primary_interface.ip_range
    secondary_bgp_ip = google_compute_router_interface.secondary_interface.ip_range
  }
}

#
# Cost Estimation Outputs
#

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for major components (USD)"
  value = {
    parallelstore_primary   = "~$${var.parallelstore_capacity_gib * 0.6 / 1024}"
    parallelstore_secondary = "~$${var.parallelstore_capacity_gib * 0.6 / 1024}"
    cloud_functions        = "~$50-100"
    vpn_gateways          = "~$36"
    cloud_workflows       = "~$10-20"
    pubsub_topics         = "~$10-30"
    monitoring            = "~$20-50"
    total_estimated       = "~$${(var.parallelstore_capacity_gib * 1.2 / 1024) + 156}"
    note                  = "Costs vary based on usage patterns and data transfer"
  }
}