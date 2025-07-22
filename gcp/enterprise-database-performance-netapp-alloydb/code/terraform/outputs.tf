# Output Values for Enterprise Database Performance Solution
# This file defines outputs that provide important information about the deployed infrastructure

# ============================================================================
# NETWORK INFORMATION
# ============================================================================

output "vpc_network_id" {
  description = "ID of the VPC network created for the enterprise database infrastructure"
  value       = google_compute_network.enterprise_vpc.id
}

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.enterprise_vpc.name
}

output "database_subnet_id" {
  description = "ID of the database subnet"
  value       = google_compute_subnetwork.database_subnet.id
}

output "database_subnet_cidr" {
  description = "CIDR range of the database subnet"
  value       = google_compute_subnetwork.database_subnet.ip_cidr_range
}

output "private_service_range" {
  description = "Private IP range allocated for service networking"
  value       = google_compute_global_address.private_service_range.address
}

# ============================================================================
# ALLOYDB CLUSTER INFORMATION
# ============================================================================

output "alloydb_cluster_id" {
  description = "ID of the AlloyDB cluster"
  value       = google_alloydb_cluster.enterprise_cluster.cluster_id
}

output "alloydb_cluster_name" {
  description = "Full resource name of the AlloyDB cluster"
  value       = google_alloydb_cluster.enterprise_cluster.name
}

output "alloydb_database_version" {
  description = "PostgreSQL version of the AlloyDB cluster"
  value       = google_alloydb_cluster.enterprise_cluster.database_version
}

output "alloydb_cluster_uid" {
  description = "Unique identifier of the AlloyDB cluster"
  value       = google_alloydb_cluster.enterprise_cluster.uid
}

# ============================================================================
# ALLOYDB INSTANCE INFORMATION
# ============================================================================

output "primary_instance_name" {
  description = "Name of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary_instance.name
}

output "primary_instance_ip" {
  description = "Private IP address of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary_instance.ip_address
}

output "primary_instance_uid" {
  description = "Unique identifier of the primary instance"
  value       = google_alloydb_instance.primary_instance.uid
}

output "primary_instance_cpu_count" {
  description = "Number of CPUs allocated to the primary instance"
  value       = google_alloydb_instance.primary_instance.machine_config[0].cpu_count
}

output "read_replica_instance_name" {
  description = "Name of the AlloyDB read replica instance"
  value       = var.enable_read_replicas ? google_alloydb_instance.read_replica[0].name : null
}

output "read_replica_instance_ip" {
  description = "Private IP address of the AlloyDB read replica instance"
  value       = var.enable_read_replicas ? google_alloydb_instance.read_replica[0].ip_address : null
}

output "read_replica_node_count" {
  description = "Number of nodes in the read replica pool"
  value       = var.enable_read_replicas ? google_alloydb_instance.read_replica[0].read_pool_config[0].node_count : null
}

# ============================================================================
# NETAPP VOLUMES INFORMATION
# ============================================================================

output "netapp_storage_pool_name" {
  description = "Name of the NetApp storage pool"
  value       = google_netapp_storage_pool.enterprise_storage_pool.name
}

output "netapp_storage_pool_capacity" {
  description = "Capacity of the NetApp storage pool in GiB"
  value       = google_netapp_storage_pool.enterprise_storage_pool.capacity_gib
}

output "netapp_storage_pool_service_level" {
  description = "Service level of the NetApp storage pool"
  value       = google_netapp_storage_pool.enterprise_storage_pool.service_level
}

output "netapp_volume_name" {
  description = "Name of the NetApp volume for database storage"
  value       = google_netapp_volume.database_volume.name
}

output "netapp_volume_capacity" {
  description = "Capacity of the NetApp volume in GiB"
  value       = google_netapp_volume.database_volume.capacity_gib
}

output "netapp_volume_mount_path" {
  description = "NFS mount path for the NetApp volume"
  value       = google_netapp_volume.database_volume.mount_options[0].export
}

output "netapp_volume_protocols" {
  description = "Supported protocols for the NetApp volume"
  value       = google_netapp_volume.database_volume.protocols
}

output "netapp_volume_share_name" {
  description = "NFS share name of the NetApp volume"
  value       = google_netapp_volume.database_volume.share_name
}

# ============================================================================
# SECURITY AND ENCRYPTION
# ============================================================================

output "kms_keyring_name" {
  description = "Name of the KMS keyring for database encryption"
  value       = var.enable_kms_encryption ? google_kms_key_ring.alloydb_keyring[0].name : null
}

output "kms_key_name" {
  description = "Name of the KMS key for database encryption"
  value       = var.enable_kms_encryption ? google_kms_crypto_key.alloydb_key[0].name : null
}

output "kms_key_id" {
  description = "Full resource ID of the KMS key"
  value       = var.enable_kms_encryption ? google_kms_crypto_key.alloydb_key[0].id : null
}

# ============================================================================
# LOAD BALANCER INFORMATION
# ============================================================================

output "load_balancer_ip" {
  description = "IP address of the internal load balancer for database connections"
  value       = var.enable_load_balancer ? google_compute_forwarding_rule.alloydb_forwarding_rule[0].ip_address : null
}

output "load_balancer_port" {
  description = "Port number for database connections through the load balancer"
  value       = var.enable_load_balancer ? "5432" : null
}

output "backend_service_name" {
  description = "Name of the backend service for load balancing"
  value       = var.enable_load_balancer ? google_compute_region_backend_service.alloydb_backend[0].name : null
}

# ============================================================================
# MONITORING INFORMATION
# ============================================================================

output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = var.enable_monitoring ? google_monitoring_dashboard.database_performance_dashboard[0].id : null
}

output "cpu_alert_policy_name" {
  description = "Name of the CPU utilization alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.alloydb_high_cpu[0].name : null
}

output "memory_alert_policy_name" {
  description = "Name of the memory utilization alert policy"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.alloydb_high_memory[0].name : null
}

# ============================================================================
# CONNECTION INFORMATION
# ============================================================================

output "database_connection_info" {
  description = "Database connection information for applications"
  value = {
    # Primary instance connection (for write operations)
    primary = {
      host     = google_alloydb_instance.primary_instance.ip_address
      port     = 5432
      database = "postgres"
      username = "postgres"
      ssl_mode = "require"
    }
    
    # Read replica connection (for read operations)
    read_replica = var.enable_read_replicas ? {
      host     = google_alloydb_instance.read_replica[0].ip_address
      port     = 5432
      database = "postgres"
      username = "postgres"
      ssl_mode = "require"
    } : null
    
    # Load balancer connection (if enabled)
    load_balancer = var.enable_load_balancer ? {
      host     = google_compute_forwarding_rule.alloydb_forwarding_rule[0].ip_address
      port     = 5432
      database = "postgres"
      username = "postgres"
      ssl_mode = "require"
    } : null
  }
  sensitive = false
}

# ============================================================================
# RESOURCE IDENTIFIERS
# ============================================================================

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

output "project_id" {
  description = "Google Cloud project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where resources are deployed"
  value       = var.zone
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed enterprise database performance solution"
  value = {
    solution_name = "Enterprise Database Performance with NetApp Volumes and AlloyDB"
    
    # Core components
    alloydb_cluster = {
      id               = google_alloydb_cluster.enterprise_cluster.cluster_id
      database_version = google_alloydb_cluster.enterprise_cluster.database_version
      primary_ip       = google_alloydb_instance.primary_instance.ip_address
      replica_enabled  = var.enable_read_replicas
    }
    
    netapp_storage = {
      pool_name        = google_netapp_storage_pool.enterprise_storage_pool.name
      pool_capacity    = "${google_netapp_storage_pool.enterprise_storage_pool.capacity_gib} GiB"
      volume_name      = google_netapp_volume.database_volume.name
      volume_capacity  = "${google_netapp_volume.database_volume.capacity_gib} GiB"
      service_level    = google_netapp_storage_pool.enterprise_storage_pool.service_level
    }
    
    # Features enabled
    features = {
      kms_encryption    = var.enable_kms_encryption
      load_balancer     = var.enable_load_balancer
      monitoring        = var.enable_monitoring
      read_replicas     = var.enable_read_replicas
      automated_backups = true
      continuous_backup = true
    }
    
    # Network configuration
    networking = {
      vpc_name         = google_compute_network.enterprise_vpc.name
      subnet_cidr      = google_compute_subnetwork.database_subnet.ip_cidr_range
      private_service  = true
    }
    
    # Estimated monthly cost range (USD)
    estimated_cost_range = "$1,200 - $2,500 per month"
    
    # Next steps
    next_steps = [
      "Connect applications using the provided connection information",
      "Configure additional database users and permissions",
      "Set up application-specific monitoring and alerting",
      "Review and adjust database performance settings",
      "Implement backup and disaster recovery procedures"
    ]
  }
}

# ============================================================================
# QUICK START COMMANDS
# ============================================================================

output "quick_start_commands" {
  description = "Quick start commands for connecting to and managing the database"
  value = {
    # Connect to primary instance using gcloud
    connect_primary = "gcloud alloydb instances describe ${google_alloydb_instance.primary_instance.instance_id} --cluster=${google_alloydb_cluster.enterprise_cluster.cluster_id} --region=${var.region}"
    
    # Connect to read replica (if enabled)
    connect_replica = var.enable_read_replicas ? "gcloud alloydb instances describe ${google_alloydb_instance.read_replica[0].instance_id} --cluster=${google_alloydb_cluster.enterprise_cluster.cluster_id} --region=${var.region}" : null
    
    # View NetApp volume details
    netapp_volume_info = "gcloud netapp volumes describe ${google_netapp_volume.database_volume.name} --location=${var.region}"
    
    # View monitoring dashboard
    monitoring_dashboard = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.database_performance_dashboard[0].id}?project=${var.project_id}" : null
    
    # psql connection string for primary
    psql_primary = "psql 'host=${google_alloydb_instance.primary_instance.ip_address} port=5432 dbname=postgres user=postgres sslmode=require'"
    
    # psql connection string for read replica
    psql_replica = var.enable_read_replicas ? "psql 'host=${google_alloydb_instance.read_replica[0].ip_address} port=5432 dbname=postgres user=postgres sslmode=require'" : null
  }
}