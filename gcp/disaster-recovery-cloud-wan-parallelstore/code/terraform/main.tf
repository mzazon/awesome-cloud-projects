# GCP Disaster Recovery Solution with Cloud WAN and Parallelstore
# This configuration creates a comprehensive disaster recovery solution for HPC workloads
# using Network Connectivity Center, Parallelstore, Cloud Workflows, and monitoring

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming convention
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  name_prefix     = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.common_labels, {
    environment = var.environment
    created-by  = "terraform"
    solution    = "disaster-recovery"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "workflows.googleapis.com",
    "monitoring.googleapis.com",
    "parallelstore.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "networkconnectivity.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicenetworking.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

#
# VPC Networks for Primary and Secondary Regions
#

# Primary region VPC network
resource "google_compute_network" "primary_vpc" {
  name                    = "${local.name_prefix}-primary-vpc"
  description             = "Primary region VPC for HPC disaster recovery"
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Primary region subnet with large address space for HPC workloads
resource "google_compute_subnetwork" "primary_subnet" {
  name          = "${local.name_prefix}-primary-subnet"
  description   = "Primary subnet for HPC workloads"
  network       = google_compute_network.primary_vpc.id
  ip_cidr_range = var.primary_vpc_cidr
  region        = var.primary_region

  # Enable private Google access for instances without external IPs
  private_ip_google_access = true

  # Secondary IP ranges for services
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.primary_vpc_cidr, 8, 1)
  }
}

# Secondary region VPC network
resource "google_compute_network" "secondary_vpc" {
  provider = google.secondary
  
  name                    = "${local.name_prefix}-secondary-vpc"
  description             = "Secondary region VPC for HPC disaster recovery"
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Secondary region subnet
resource "google_compute_subnetwork" "secondary_subnet" {
  provider = google.secondary
  
  name          = "${local.name_prefix}-secondary-subnet"
  description   = "Secondary subnet for HPC workloads"
  network       = google_compute_network.secondary_vpc.id
  ip_cidr_range = var.secondary_vpc_cidr
  region        = var.secondary_region

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.secondary_vpc_cidr, 8, 1)
  }
}

#
# Cloud NAT for Private Instance Internet Access
#

# Cloud Router for primary region NAT
resource "google_compute_router" "primary_nat_router" {
  name    = "${local.name_prefix}-primary-nat-router"
  region  = var.primary_region
  network = google_compute_network.primary_vpc.id

  bgp {
    asn = var.bgp_asn_primary
  }
}

# Cloud NAT for primary region
resource "google_compute_router_nat" "primary_nat" {
  count = var.enable_cloud_nat ? 1 : 0

  name                               = "${local.name_prefix}-primary-nat"
  router                             = google_compute_router.primary_nat_router.name
  region                             = var.primary_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Cloud Router for secondary region NAT
resource "google_compute_router" "secondary_nat_router" {
  provider = google.secondary
  
  name    = "${local.name_prefix}-secondary-nat-router"
  region  = var.secondary_region
  network = google_compute_network.secondary_vpc.id

  bgp {
    asn = var.bgp_asn_secondary
  }
}

# Cloud NAT for secondary region
resource "google_compute_router_nat" "secondary_nat" {
  provider = google.secondary
  count    = var.enable_cloud_nat ? 1 : 0

  name                               = "${local.name_prefix}-secondary-nat"
  router                             = google_compute_router.secondary_nat_router.name
  region                             = var.secondary_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#
# Network Connectivity Center (Cloud WAN)
#

# Network Connectivity Center hub for global WAN functionality
resource "google_network_connectivity_hub" "wan_hub" {
  name            = "${local.name_prefix}-wan-hub"
  description     = "Global WAN hub for HPC disaster recovery"
  policy_mode     = "PRESET"
  preset_topology = "STAR"
  export_psc      = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Primary region spoke for Network Connectivity Center
resource "google_network_connectivity_spoke" "primary_spoke" {
  name        = "${local.name_prefix}-primary-spoke"
  location    = var.primary_region
  description = "Primary region spoke for disaster recovery"
  hub         = google_network_connectivity_hub.wan_hub.id

  linked_vpc_network {
    uri                      = google_compute_network.primary_vpc.id
    exclude_export_ranges    = []
    include_export_ranges    = []
  }

  labels = local.common_labels
}

# Secondary region spoke for Network Connectivity Center
resource "google_network_connectivity_spoke" "secondary_spoke" {
  name        = "${local.name_prefix}-secondary-spoke"
  location    = var.secondary_region
  description = "Secondary region spoke for disaster recovery"
  hub         = google_network_connectivity_hub.wan_hub.id

  linked_vpc_network {
    uri                      = google_compute_network.secondary_vpc.id
    exclude_export_ranges    = []
    include_export_ranges    = []
  }

  labels = local.common_labels
}

#
# VPN Connectivity for Secure Cross-Region Communication
#

# Generate VPN shared secret if not provided
resource "random_password" "vpn_shared_secret" {
  count   = var.vpn_shared_secret == "" ? 1 : 0
  length  = 32
  special = true
}

locals {
  vpn_secret = var.vpn_shared_secret != "" ? var.vpn_shared_secret : random_password.vpn_shared_secret[0].result
}

# HA VPN Gateway for primary region
resource "google_compute_ha_vpn_gateway" "primary_vpn_gateway" {
  name       = "${local.name_prefix}-primary-vpn-gw"
  region     = var.primary_region
  network    = google_compute_network.primary_vpc.id
  stack_type = "IPV4_ONLY"
}

# HA VPN Gateway for secondary region
resource "google_compute_ha_vpn_gateway" "secondary_vpn_gateway" {
  provider = google.secondary
  
  name       = "${local.name_prefix}-secondary-vpn-gw"
  region     = var.secondary_region
  network    = google_compute_network.secondary_vpc.id
  stack_type = "IPV4_ONLY"
}

# VPN tunnel from primary to secondary
resource "google_compute_vpn_tunnel" "primary_to_secondary" {
  name                            = "${local.name_prefix}-primary-to-secondary"
  region                          = var.primary_region
  vpn_gateway                     = google_compute_ha_vpn_gateway.primary_vpn_gateway.id
  vpn_gateway_interface           = 0
  peer_gcp_gateway                = google_compute_ha_vpn_gateway.secondary_vpn_gateway.id
  shared_secret                   = local.vpn_secret
  router                          = google_compute_router.primary_nat_router.id
  ike_version                     = 2

  depends_on = [google_compute_ha_vpn_gateway.secondary_vpn_gateway]
}

# VPN tunnel from secondary to primary
resource "google_compute_vpn_tunnel" "secondary_to_primary" {
  provider = google.secondary
  
  name                            = "${local.name_prefix}-secondary-to-primary"
  region                          = var.secondary_region
  vpn_gateway                     = google_compute_ha_vpn_gateway.secondary_vpn_gateway.id
  vpn_gateway_interface           = 0
  peer_gcp_gateway                = google_compute_ha_vpn_gateway.primary_vpn_gateway.id
  shared_secret                   = local.vpn_secret
  router                          = google_compute_router.secondary_nat_router.id
  ike_version                     = 2

  depends_on = [google_compute_ha_vpn_gateway.primary_vpn_gateway]
}

# BGP session for primary router
resource "google_compute_router_interface" "primary_interface" {
  name       = "${local.name_prefix}-primary-interface"
  router     = google_compute_router.primary_nat_router.name
  region     = var.primary_region
  ip_range   = "169.254.1.1/30"
  vpn_tunnel = google_compute_vpn_tunnel.primary_to_secondary.name
}

resource "google_compute_router_peer" "primary_peer" {
  name                      = "${local.name_prefix}-primary-peer"
  router                    = google_compute_router.primary_nat_router.name
  region                    = var.primary_region
  peer_ip_address           = "169.254.1.2"
  peer_asn                  = var.bgp_asn_secondary
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.primary_interface.name
}

# BGP session for secondary router
resource "google_compute_router_interface" "secondary_interface" {
  provider = google.secondary
  
  name       = "${local.name_prefix}-secondary-interface"
  router     = google_compute_router.secondary_nat_router.name
  region     = var.secondary_region
  ip_range   = "169.254.1.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.secondary_to_primary.name
}

resource "google_compute_router_peer" "secondary_peer" {
  provider = google.secondary
  
  name                      = "${local.name_prefix}-secondary-peer"
  router                    = google_compute_router.secondary_nat_router.name
  region                    = var.secondary_region
  peer_ip_address           = "169.254.1.1"
  peer_asn                  = var.bgp_asn_primary
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.secondary_interface.name
}

#
# Private Service Networking for Parallelstore
#

# Reserve IP range for private services in primary region
resource "google_compute_global_address" "primary_private_ip_range" {
  name          = "${local.name_prefix}-primary-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.primary_vpc.id
}

# Private service connection for primary region
resource "google_service_networking_connection" "primary_private_connection" {
  network                 = google_compute_network.primary_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.primary_private_ip_range.name]

  depends_on = [google_project_service.required_apis]
}

# Reserve IP range for private services in secondary region
resource "google_compute_global_address" "secondary_private_ip_range" {
  provider = google.secondary
  
  name          = "${local.name_prefix}-secondary-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.secondary_vpc.id
}

# Private service connection for secondary region
resource "google_service_networking_connection" "secondary_private_connection" {
  provider = google.secondary
  
  network                 = google_compute_network.secondary_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.secondary_private_ip_range.name]

  depends_on = [google_project_service.required_apis]
}

#
# Parallelstore Instances for High-Performance Storage
#

# Primary Parallelstore instance
resource "google_parallelstore_instance" "primary_storage" {
  provider = google-beta
  
  instance_id             = "${local.name_prefix}-primary-pfs"
  location                = var.primary_zone
  description             = "Primary Parallelstore for HPC workloads"
  capacity_gib            = var.parallelstore_capacity_gib
  network                 = google_compute_network.primary_vpc.name
  file_stripe_level       = var.parallelstore_file_stripe_level
  directory_stripe_level  = var.parallelstore_directory_stripe_level
  deployment_type         = var.parallelstore_deployment_type

  labels = local.common_labels

  depends_on = [
    google_service_networking_connection.primary_private_connection,
    google_project_service.required_apis
  ]
}

# Secondary Parallelstore instance for disaster recovery
resource "google_parallelstore_instance" "secondary_storage" {
  provider = google-beta
  
  instance_id             = "${local.name_prefix}-secondary-pfs"
  location                = var.secondary_zone
  description             = "Secondary Parallelstore for disaster recovery replication"
  capacity_gib            = var.parallelstore_capacity_gib
  network                 = google_compute_network.secondary_vpc.name
  file_stripe_level       = var.parallelstore_file_stripe_level
  directory_stripe_level  = var.parallelstore_directory_stripe_level
  deployment_type         = var.parallelstore_deployment_type

  labels = local.common_labels

  depends_on = [
    google_service_networking_connection.secondary_private_connection,
    google_project_service.required_apis
  ]
}

#
# Pub/Sub Infrastructure for Orchestration Communication
#

# Pub/Sub topic for health alerts
resource "google_pubsub_topic" "health_alerts" {
  name = "${local.name_prefix}-health-alerts"

  message_retention_duration = var.pubsub_message_retention_duration

  message_storage_policy {
    allowed_persistence_regions = [
      var.primary_region,
      var.secondary_region
    ]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for failover commands
resource "google_pubsub_topic" "failover_commands" {
  name = "${local.name_prefix}-failover-commands"

  message_retention_duration = var.pubsub_message_retention_duration

  message_storage_policy {
    allowed_persistence_regions = [
      var.primary_region,
      var.secondary_region
    ]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for replication status
resource "google_pubsub_topic" "replication_status" {
  name = "${local.name_prefix}-replication-status"

  message_retention_duration = var.pubsub_message_retention_duration

  message_storage_policy {
    allowed_persistence_regions = [
      var.primary_region,
      var.secondary_region
    ]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscriptions for workflow processing
resource "google_pubsub_subscription" "health_subscription" {
  name  = "${local.name_prefix}-health-subscription"
  topic = google_pubsub_topic.health_alerts.name

  message_retention_duration = var.pubsub_message_retention_duration
  retain_acked_messages      = false
  ack_deadline_seconds       = 20

  expiration_policy {
    ttl = "300000.5s"
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.health_alerts.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels
}

resource "google_pubsub_subscription" "failover_subscription" {
  name  = "${local.name_prefix}-failover-subscription"
  topic = google_pubsub_topic.failover_commands.name

  message_retention_duration = var.pubsub_message_retention_duration
  retain_acked_messages      = false
  ack_deadline_seconds       = 20

  expiration_policy {
    ttl = "300000.5s"
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels
}

resource "google_pubsub_subscription" "replication_subscription" {
  name  = "${local.name_prefix}-replication-subscription"
  topic = google_pubsub_topic.replication_status.name

  message_retention_duration = var.pubsub_message_retention_duration
  retain_acked_messages      = false
  ack_deadline_seconds       = 600

  expiration_policy {
    ttl = "300000.5s"
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels
}

#
# Cloud Storage for Function Code and Replication Staging
#

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.name_prefix}-function-source-${random_id.suffix.hex}"
  location      = var.primary_region
  force_destroy = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

# Storage bucket for replication staging
resource "google_storage_bucket" "replication_staging" {
  name          = "${local.name_prefix}-replication-staging-${random_id.suffix.hex}"
  location      = var.primary_region
  force_destroy = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels
}

#
# Service Accounts for Cloud Functions and Workflows
#

# Service account for health monitoring function
resource "google_service_account" "health_monitor_sa" {
  account_id   = "${local.name_prefix}-health-monitor"
  display_name = "Health Monitor Service Account"
  description  = "Service account for HPC health monitoring function"
}

# Service account for replication function
resource "google_service_account" "replication_sa" {
  account_id   = "${local.name_prefix}-replication"
  display_name = "Replication Service Account"
  description  = "Service account for HPC data replication function"
}

# Service account for disaster recovery workflow
resource "google_service_account" "workflow_sa" {
  account_id   = "${local.name_prefix}-workflow"
  display_name = "DR Workflow Service Account"
  description  = "Service account for disaster recovery orchestration workflow"
}

#
# IAM Bindings for Service Accounts
#

# Health monitor function permissions
resource "google_project_iam_member" "health_monitor_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.health_monitor_sa.email}"
}

resource "google_project_iam_member" "health_monitor_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.health_monitor_sa.email}"
}

# Allow health monitor to view Parallelstore instances
resource "google_project_iam_member" "health_monitor_parallelstore_viewer" {
  project = var.project_id
  role    = "roles/parallelstore.viewer"
  member  = "serviceAccount:${google_service_account.health_monitor_sa.email}"
}

# Replication function permissions
resource "google_project_iam_member" "replication_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.replication_sa.email}"
}

resource "google_project_iam_member" "replication_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.replication_sa.email}"
}

resource "google_project_iam_member" "replication_parallelstore_admin" {
  project = var.project_id
  role    = "roles/parallelstore.admin"
  member  = "serviceAccount:${google_service_account.replication_sa.email}"
}

# Workflow service account permissions
resource "google_project_iam_member" "workflow_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_monitoring_editor" {
  project = var.project_id
  role    = "roles/monitoring.editor"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

#
# Cloud Functions for Health Monitoring and Replication
#

# Create function source code archives
data "archive_file" "health_monitor_source" {
  type        = "zip"
  output_path = "/tmp/health-monitor-source.zip"
  source {
    content = templatefile("${path.module}/functions/health_monitor.py", {
      project_id       = var.project_id
      dr_prefix        = local.name_prefix
      primary_region   = var.primary_region
      secondary_region = var.secondary_region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/health_monitor_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload health monitor function source to Cloud Storage
resource "google_storage_bucket_object" "health_monitor_source" {
  name   = "health-monitor-source-${data.archive_file.health_monitor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.health_monitor_source.output_path
}

# Health monitoring Cloud Function
resource "google_cloudfunctions2_function" "health_monitor" {
  name        = "${local.name_prefix}-health-monitor"
  location    = var.primary_region
  description = "Health monitoring function for HPC disaster recovery"

  build_config {
    runtime     = "python312"
    entry_point = "monitor_hpc_health"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.health_monitor_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 100
    min_instance_count               = 1
    available_memory                 = "${var.health_monitor_memory}M"
    timeout_seconds                  = var.health_monitor_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      DR_PREFIX        = local.name_prefix
      PRIMARY_REGION   = var.primary_region
      SECONDARY_REGION = var.secondary_region
    }

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.health_monitor_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.health_monitor_source
  ]
}

# Create replication function source
data "archive_file" "replication_source" {
  type        = "zip"
  output_path = "/tmp/replication-source.zip"
  source {
    content = templatefile("${path.module}/functions/replication.py", {
      project_id       = var.project_id
      dr_prefix        = local.name_prefix
      primary_region   = var.primary_region
      secondary_region = var.secondary_region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/replication_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload replication function source to Cloud Storage
resource "google_storage_bucket_object" "replication_source" {
  name   = "replication-source-${data.archive_file.replication_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.replication_source.output_path
}

# Replication Cloud Function
resource "google_cloudfunctions2_function" "replication" {
  name        = "${local.name_prefix}-replication-scheduler"
  location    = var.primary_region
  description = "Automated data replication function for HPC disaster recovery"

  build_config {
    runtime     = "python312"
    entry_point = "replicate_hpc_data"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.replication_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 50
    min_instance_count               = 0
    available_memory                 = "${var.replication_function_memory}M"
    timeout_seconds                  = var.replication_function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "2"
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      DR_PREFIX        = local.name_prefix
      PRIMARY_REGION   = var.primary_region
      SECONDARY_REGION = var.secondary_region
    }

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.replication_sa.email
  }

  event_trigger {
    trigger_region = var.primary_region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.replication_status.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.replication_source
  ]
}

#
# Cloud Workflows for Disaster Recovery Orchestration
#

# Disaster recovery orchestration workflow
resource "google_workflows_workflow" "dr_orchestrator" {
  name                     = "${local.name_prefix}-dr-orchestrator"
  region                   = var.primary_region
  description              = "HPC disaster recovery orchestration workflow"
  service_account          = google_service_account.workflow_sa.id
  call_log_level          = "LOG_ERRORS_ONLY"
  execution_history_level = "EXECUTION_HISTORY_DETAILED"

  user_env_vars = {
    PROJECT_ID       = var.project_id
    DR_PREFIX        = local.name_prefix
    PRIMARY_REGION   = var.primary_region
    SECONDARY_REGION = var.secondary_region
  }

  source_contents = templatefile("${path.module}/workflows/dr_orchestration.yaml", {
    project_id           = var.project_id
    dr_prefix            = local.name_prefix
    primary_region       = var.primary_region
    secondary_region     = var.secondary_region
    health_function_name = google_cloudfunctions2_function.health_monitor.name
  })

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.health_monitor
  ]
}

#
# Cloud Scheduler for Automated Replication
#

# Cloud Scheduler job for regular replication
resource "google_cloud_scheduler_job" "replication_job" {
  name             = "${local.name_prefix}-replication-job"
  description      = "Automated HPC data replication every 15 minutes"
  schedule         = var.replication_schedule
  time_zone        = "UTC"
  region           = var.primary_region
  attempt_deadline = "320s"

  retry_config {
    retry_count = 3
  }

  pubsub_target {
    topic_name = google_pubsub_topic.replication_status.id
    data       = base64encode(jsonencode({
      trigger = "scheduled_replication"
      timestamp = formatdate("RFC3339", timestamp())
    }))
  }

  depends_on = [google_project_service.required_apis]
}

#
# Cloud Monitoring Configuration
#

# Notification channel for Pub/Sub integration
resource "google_monitoring_notification_channel" "pubsub_channel" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  display_name = "${local.name_prefix} DR Trigger Channel"
  description  = "Pub/Sub notification channel for DR workflow triggering"
  type         = "pubsub"

  labels = {
    topic = google_pubsub_topic.health_alerts.id
  }

  enabled = true
}

# Alerting policy for Parallelstore health monitoring
resource "google_monitoring_alert_policy" "parallelstore_health" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  display_name = "${local.name_prefix} HPC Infrastructure Health Alert"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Monitors critical HPC infrastructure components for disaster recovery triggering"
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Parallelstore Instance Unavailable"
    
    condition_threshold {
      filter         = "resource.type=\"parallelstore_instance\" AND resource.labels.instance_name=~\"${local.name_prefix}-primary-pfs\""
      duration       = "300s"
      comparison     = "COMPARISON_EQUAL"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  conditions {
    display_name = "High Replication Lag"
    
    condition_threshold {
      filter         = "metric.type=\"custom.googleapis.com/hpc/replication_lag_minutes\""
      duration       = "180s"
      comparison     = "COMPARISON_GREATER"
      threshold_value = var.replication_lag_threshold_minutes
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  notification_channels = concat(
    [google_monitoring_notification_channel.pubsub_channel[0].name],
    var.alert_notification_channels
  )

  severity = "CRITICAL"

  depends_on = [google_project_service.required_apis]
}

#
# Firewall Rules for VPC Communication
#

# Allow internal communication within primary VPC
resource "google_compute_firewall" "primary_internal" {
  name    = "${local.name_prefix}-primary-internal"
  network = google_compute_network.primary_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.primary_vpc_cidr]
  target_tags   = ["hpc-workload"]
}

# Allow internal communication within secondary VPC
resource "google_compute_firewall" "secondary_internal" {
  provider = google.secondary
  
  name    = "${local.name_prefix}-secondary-internal"
  network = google_compute_network.secondary_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.secondary_vpc_cidr]
  target_tags   = ["hpc-workload"]
}

# Allow VPN traffic between regions
resource "google_compute_firewall" "allow_vpn_traffic" {
  name    = "${local.name_prefix}-allow-vpn"
  network = google_compute_network.primary_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3389", "80", "443", "111", "2049", "4045"]
  }
  allow {
    protocol = "udp"
    ports    = ["111", "2049", "4045"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.secondary_vpc_cidr]
  target_tags   = ["hpc-workload"]
}

resource "google_compute_firewall" "secondary_allow_vpn_traffic" {
  provider = google.secondary
  
  name    = "${local.name_prefix}-secondary-allow-vpn"
  network = google_compute_network.secondary_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "3389", "80", "443", "111", "2049", "4045"]
  }
  allow {
    protocol = "udp"
    ports    = ["111", "2049", "4045"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.primary_vpc_cidr]
  target_tags   = ["hpc-workload"]
}