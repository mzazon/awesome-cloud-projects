# Outputs for multi-environment development isolation solution

# Project Information
output "project_ids" {
  description = "Map of environment names to project IDs"
  value = {
    development = var.dev_project_id
    testing     = var.test_project_id
    production  = var.prod_project_id
  }
}

# Access Context Manager Information
output "access_policy_id" {
  description = "The ID of the Access Context Manager policy"
  value       = google_access_context_manager_access_policy.policy.name
}

output "access_level_name" {
  description = "The name of the internal users access level"
  value       = google_access_context_manager_access_level.internal_users.name
}

# VPC Service Controls Information
output "service_perimeter_names" {
  description = "Map of environment names to VPC Service Controls perimeter names"
  value = {
    for env, perimeter in google_access_context_manager_service_perimeter.perimeter :
    env => perimeter.name
  }
}

# Network Information
output "vpc_networks" {
  description = "Map of environment names to VPC network information"
  value = {
    for env, vpc in google_compute_network.vpc :
    env => {
      project_id = vpc.project
      name       = vpc.name
      id         = vpc.id
      self_link  = vpc.self_link
    }
  }
}

output "subnets" {
  description = "Map of environment names to subnet information"
  value = {
    for env, subnet in google_compute_subnetwork.subnet :
    env => {
      project_id    = subnet.project
      name          = subnet.name
      id            = subnet.id
      ip_cidr_range = subnet.ip_cidr_range
      region        = subnet.region
      self_link     = subnet.self_link
    }
  }
}

# Cloud Filestore Information
output "filestore_instances" {
  description = "Map of environment names to Cloud Filestore instance information"
  value = {
    for env, filestore in google_filestore_instance.filestore :
    env => {
      project_id   = filestore.project
      name         = filestore.name
      location     = filestore.location
      tier         = filestore.tier
      capacity_gb  = filestore.file_shares[0].capacity_gb
      share_name   = filestore.file_shares[0].name
      ip_addresses = filestore.networks[0].ip_addresses
      mount_command = "sudo mount -t nfs ${filestore.networks[0].ip_addresses[0]}:/${filestore.file_shares[0].name} /mnt/${env}-filestore"
    }
  }
  sensitive = false
}

# Cloud Source Repositories Information
output "source_repositories" {
  description = "Map of environment names to Cloud Source Repository information"
  value = {
    for env, repo in google_sourcerepo_repository.repo :
    env => {
      project_id = repo.project
      name       = repo.name
      url        = repo.url
      clone_url  = "gcloud source repos clone ${repo.name} --project=${repo.project}"
    }
  }
}

# Cloud Workstations Information
output "workstation_clusters" {
  description = "Map of environment names to Cloud Workstations cluster information"
  value = {
    for env, cluster in google_workstations_workstation_cluster.cluster :
    env => {
      project_id              = cluster.project
      workstation_cluster_id  = cluster.workstation_cluster_id
      location                = cluster.location
      name                    = cluster.name
      uid                     = cluster.uid
    }
  }
}

output "workstation_configs" {
  description = "Map of environment names to Cloud Workstations configuration information"
  value = {
    for env, config in google_workstations_workstation_config.config :
    env => {
      project_id             = config.project
      workstation_config_id  = config.workstation_config_id
      location               = config.location
      name                   = config.name
      uid                    = config.uid
      machine_type           = config.host[0].gce_instance[0].machine_type
      boot_disk_size_gb      = config.host[0].gce_instance[0].boot_disk_size_gb
      container_image        = config.container[0].image
    }
  }
}

output "workstations" {
  description = "Map of environment names to sample workstation information"
  value = {
    for env, workstation in google_workstations_workstation.workstation :
    env => {
      project_id    = workstation.project
      workstation_id = workstation.workstation_id
      location      = workstation.location
      name          = workstation.name
      uid           = workstation.uid
      state         = workstation.state
      ssh_command   = "gcloud workstations ssh ${workstation.workstation_id} --cluster=${workstation.workstation_cluster_id} --config=${workstation.workstation_config_id} --region=${workstation.location} --project=${workstation.project}"
    }
  }
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to the development environments"
  value = {
    for env, workstation in google_workstations_workstation.workstation :
    env => {
      ssh_command = "gcloud workstations ssh ${workstation.workstation_id} --cluster=${workstation.workstation_cluster_id} --config=${workstation.workstation_config_id} --region=${workstation.location} --project=${workstation.project}"
      filestore_mount = "sudo mount -t nfs ${google_filestore_instance.filestore[env].networks[0].ip_addresses[0]}:/${google_filestore_instance.filestore[env].file_shares[0].name} /mnt/${env}-filestore"
      repository_clone = "gcloud source repos clone ${google_sourcerepo_repository.repo[env].name} --project=${google_sourcerepo_repository.repo[env].project}"
    }
  }
}

# Security Information
output "security_summary" {
  description = "Summary of security controls implemented"
  value = {
    vpc_service_controls = {
      enabled = true
      perimeters = length(google_access_context_manager_service_perimeter.perimeter)
      restricted_services = var.restricted_services
    }
    access_controls = {
      access_policy_title = var.access_policy_title
      internal_users_count = length(var.internal_users)
    }
    network_isolation = {
      separate_vpcs = true
      private_google_access = true
      iap_enabled = true
    }
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources per environment"
  value = {
    for env in keys(local.environments) :
    env => {
      project_id = local.environments[env].project_id
      vpc_network = google_compute_network.vpc[env].name
      subnet = google_compute_subnetwork.subnet[env].name
      filestore_instance = google_filestore_instance.filestore[env].name
      source_repository = google_sourcerepo_repository.repo[env].name
      workstation_cluster = google_workstations_workstation_cluster.cluster[env].workstation_cluster_id
      workstation_config = google_workstations_workstation_config.config[env].workstation_config_id
      sample_workstation = google_workstations_workstation.workstation[env].workstation_id
      service_perimeter = google_access_context_manager_service_perimeter.perimeter[env].name
    }
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Information for cost estimation"
  value = {
    workstation_machine_type = var.workstation_machine_type
    filestore_tier = var.filestore_tier
    filestore_capacity_gb = var.filestore_capacity_gb
    persistent_disk_size_gb = var.workstation_persistent_disk_size_gb
    environments_count = length(local.environments)
    note = "Actual costs depend on usage patterns, uptime, and regional pricing. Use Google Cloud Pricing Calculator for detailed estimates."
  }
}