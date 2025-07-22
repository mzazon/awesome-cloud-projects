# outputs.tf - Output values for AWS Application Migration Service infrastructure
# This file defines all output values that can be referenced by other Terraform configurations

# =============================================================================
# CORE MGN OUTPUTS
# =============================================================================

output "mgn_replication_template_id" {
  description = "ID of the MGN replication configuration template"
  value       = aws_mgn_replication_configuration_template.main.replication_configuration_template_id
}

output "mgn_replication_template_arn" {
  description = "ARN of the MGN replication configuration template"
  value       = aws_mgn_replication_configuration_template.main.arn
}

# =============================================================================
# MIGRATION WAVE OUTPUTS
# =============================================================================

output "migration_wave_ids" {
  description = "IDs of created migration waves for organized server migration"
  value = {
    for idx, wave in aws_mgn_wave.migration_waves : 
    wave.name => wave.wave_id
  }
}

output "migration_wave_arns" {
  description = "ARNs of created migration waves"
  value = {
    for idx, wave in aws_mgn_wave.migration_waves : 
    wave.name => wave.arn
  }
}

output "migration_wave_names" {
  description = "Names of all created migration waves"
  value       = aws_mgn_wave.migration_waves[*].name
}

# =============================================================================
# SECURITY GROUP OUTPUTS
# =============================================================================

output "security_group_ids" {
  description = "Security group IDs for MGN infrastructure components"
  value = {
    replication_servers = aws_security_group.mgn_replication_servers.id
    migrated_instances  = aws_security_group.mgn_migrated_instances.id
  }
}

output "security_group_arns" {
  description = "Security group ARNs for MGN infrastructure components"
  value = {
    replication_servers = aws_security_group.mgn_replication_servers.arn
    migrated_instances  = aws_security_group.mgn_migrated_instances.arn
  }
}

output "replication_servers_security_group_id" {
  description = "Security group ID for MGN replication servers"
  value       = aws_security_group.mgn_replication_servers.id
}

output "migrated_instances_security_group_id" {
  description = "Security group ID for MGN migrated instances"
  value       = aws_security_group.mgn_migrated_instances.id
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "iam_role_arns" {
  description = "IAM role ARNs for MGN service and replication servers"
  value = {
    service_role            = aws_iam_role.mgn_service_role.arn
    replication_server_role = aws_iam_role.mgn_replication_server_role.arn
  }
}

output "mgn_service_role_arn" {
  description = "ARN of the MGN service role for cross-service access"
  value       = aws_iam_role.mgn_service_role.arn
}

output "mgn_service_role_name" {
  description = "Name of the MGN service role"
  value       = aws_iam_role.mgn_service_role.name
}

output "replication_server_role_arn" {
  description = "ARN of the IAM role for MGN replication servers"
  value       = aws_iam_role.mgn_replication_server_role.arn
}

output "replication_server_instance_profile_arn" {
  description = "ARN of the IAM instance profile for replication servers"
  value       = aws_iam_instance_profile.mgn_replication_server_profile.arn
}

output "replication_server_instance_profile_name" {
  description = "Name of the IAM instance profile for replication servers"
  value       = aws_iam_instance_profile.mgn_replication_server_profile.name
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "s3_bucket_info" {
  description = "S3 bucket information for MGN logs and artifacts"
  value = {
    bucket_name   = aws_s3_bucket.mgn_logs.bucket
    bucket_arn    = aws_s3_bucket.mgn_logs.arn
    bucket_region = aws_s3_bucket.mgn_logs.region
  }
}

output "mgn_logs_bucket_name" {
  description = "Name of the S3 bucket for MGN logs"
  value       = aws_s3_bucket.mgn_logs.bucket
}

output "mgn_logs_bucket_arn" {
  description = "ARN of the S3 bucket for MGN logs"
  value       = aws_s3_bucket.mgn_logs.arn
}

# =============================================================================
# CLOUDWATCH OUTPUTS
# =============================================================================

output "cloudwatch_log_group" {
  description = "CloudWatch log group for MGN operations (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mgn_operations[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for MGN operations (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mgn_operations[0].arn : null
}

output "replication_lag_alarm_arn" {
  description = "ARN of the CloudWatch alarm for replication lag monitoring (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_lag[0].arn : null
}

# =============================================================================
# LAUNCH TEMPLATE OUTPUTS
# =============================================================================

output "launch_template_info" {
  description = "Launch template information for post-launch actions"
  value = {
    id             = aws_launch_template.mgn_post_launch.id
    arn            = aws_launch_template.mgn_post_launch.arn
    latest_version = aws_launch_template.mgn_post_launch.latest_version
    name           = aws_launch_template.mgn_post_launch.name
  }
}

output "launch_template_id" {
  description = "ID of the launch template for post-launch actions"
  value       = aws_launch_template.mgn_post_launch.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template for post-launch actions"
  value       = aws_launch_template.mgn_post_launch.latest_version
}

# =============================================================================
# CONFIGURATION OUTPUTS
# =============================================================================

output "mgn_configuration_summary" {
  description = "Summary of MGN configuration settings"
  value = {
    replication_server_instance_type = var.mgn_replication_server_instance_type
    staging_disk_type               = var.mgn_staging_disk_type
    data_plane_routing              = var.mgn_data_plane_routing
    bandwidth_throttling            = var.mgn_bandwidth_throttling
    create_public_ip                = var.mgn_create_public_ip
    use_dedicated_replication_server = var.mgn_use_dedicated_replication_server
    ebs_encryption                  = var.mgn_ebs_encryption
  }
}

output "launch_configuration_summary" {
  description = "Summary of launch configuration settings"
  value = {
    target_instance_type_right_sizing_method = var.target_instance_type_right_sizing_method
    launch_disposition                      = var.launch_disposition
    copy_private_ip                         = var.copy_private_ip
    copy_tags                               = var.copy_tags
    enable_map_auto_tagging                 = var.enable_map_auto_tagging
    licensing_os_byol                       = var.licensing_os_byol
    post_launch_actions_deployment          = var.post_launch_actions_deployment
  }
}

# =============================================================================
# RESOURCE IDENTIFIERS
# =============================================================================

output "resource_identifiers" {
  description = "Important resource identifiers for MGN operations"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    aws_region      = var.aws_region
    aws_account_id  = data.aws_caller_identity.current.account_id
    random_suffix   = random_string.suffix.result
    name_prefix     = local.name_prefix
  }
}

# =============================================================================
# AGENT INSTALLATION OUTPUTS
# =============================================================================

output "agent_installation_info" {
  description = "Information needed for MGN agent installation on source servers"
  value = {
    aws_region                      = var.aws_region
    replication_template_id         = aws_mgn_replication_configuration_template.main.replication_configuration_template_id
    service_role_arn                = aws_iam_role.mgn_service_role.arn
    replication_servers_security_group = aws_security_group.mgn_replication_servers.id
    agent_download_url_linux        = "https://aws-application-migration-service-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/linux/aws-replication-installer-init.py"
    agent_download_url_windows      = "https://aws-application-migration-service-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe"
  }
}

# =============================================================================
# MIGRATION READINESS OUTPUTS
# =============================================================================

output "migration_readiness_checklist" {
  description = "Migration readiness checklist and next steps"
  value = {
    mgn_service_initialized     = "Run: aws mgn initialize-service --region ${var.aws_region}"
    replication_template_ready  = "Template ID: ${aws_mgn_replication_configuration_template.main.replication_configuration_template_id}"
    security_groups_configured  = "Replication SG: ${aws_security_group.mgn_replication_servers.id}, Migrated SG: ${aws_security_group.mgn_migrated_instances.id}"
    s3_bucket_ready            = "Logs bucket: ${aws_s3_bucket.mgn_logs.bucket}"
    cloudwatch_enabled         = var.enable_cloudwatch_monitoring ? "Enabled" : "Disabled"
    migration_waves_created    = length(aws_mgn_wave.migration_waves)
  }
}

# =============================================================================
# TAGS OUTPUT
# =============================================================================

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "staging_area_tags" {
  description = "Tags applied to MGN staging area resources"
  value       = local.staging_tags
}