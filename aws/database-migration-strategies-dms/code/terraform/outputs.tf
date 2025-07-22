# AWS Database Migration Service (DMS) Outputs
# This file defines all output values from the DMS infrastructure

#############################################
# DMS Replication Instance Outputs
#############################################

output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_id
}

output "replication_instance_class" {
  description = "Class of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_class
}

output "replication_instance_private_ips" {
  description = "Private IP addresses of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_private_ips
}

output "replication_instance_public_ips" {
  description = "Public IP addresses of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_public_ips
}

output "replication_instance_engine_version" {
  description = "Engine version of the DMS replication instance"
  value       = aws_dms_replication_instance.main.engine_version
}

output "replication_instance_multi_az" {
  description = "Whether the DMS replication instance is Multi-AZ"
  value       = aws_dms_replication_instance.main.multi_az
}

#############################################
# DMS Subnet Group Outputs
#############################################

output "subnet_group_id" {
  description = "ID of the DMS replication subnet group"
  value       = aws_dms_replication_subnet_group.main.id
}

output "subnet_group_subnet_ids" {
  description = "List of subnet IDs in the DMS replication subnet group"
  value       = aws_dms_replication_subnet_group.main.subnet_ids
}

output "subnet_group_vpc_id" {
  description = "VPC ID associated with the DMS replication subnet group"
  value       = aws_dms_replication_subnet_group.main.vpc_id
}

#############################################
# DMS Endpoint Outputs
#############################################

output "source_endpoint_arn" {
  description = "ARN of the DMS source endpoint"
  value       = var.create_source_endpoint ? aws_dms_endpoint.source[0].endpoint_arn : ""
}

output "source_endpoint_id" {
  description = "ID of the DMS source endpoint"
  value       = var.create_source_endpoint ? aws_dms_endpoint.source[0].endpoint_id : ""
}

output "source_endpoint_engine_name" {
  description = "Engine name of the DMS source endpoint"
  value       = var.create_source_endpoint ? aws_dms_endpoint.source[0].engine_name : ""
}

output "target_endpoint_arn" {
  description = "ARN of the DMS target endpoint"
  value       = var.create_target_endpoint ? aws_dms_endpoint.target[0].endpoint_arn : ""
}

output "target_endpoint_id" {
  description = "ID of the DMS target endpoint"
  value       = var.create_target_endpoint ? aws_dms_endpoint.target[0].endpoint_id : ""
}

output "target_endpoint_engine_name" {
  description = "Engine name of the DMS target endpoint"
  value       = var.create_target_endpoint ? aws_dms_endpoint.target[0].engine_name : ""
}

#############################################
# DMS Replication Task Outputs
#############################################

output "replication_task_arn" {
  description = "ARN of the DMS replication task"
  value       = var.create_replication_task ? aws_dms_replication_task.main[0].replication_task_arn : ""
}

output "replication_task_id" {
  description = "ID of the DMS replication task"
  value       = var.create_replication_task ? aws_dms_replication_task.main[0].replication_task_id : ""
}

output "replication_task_migration_type" {
  description = "Migration type of the DMS replication task"
  value       = var.create_replication_task ? aws_dms_replication_task.main[0].migration_type : ""
}

output "replication_task_status" {
  description = "Status of the DMS replication task"
  value       = var.create_replication_task ? aws_dms_replication_task.main[0].status : ""
}

#############################################
# Security and Networking Outputs
#############################################

output "security_group_id" {
  description = "ID of the security group for DMS replication instance"
  value       = aws_security_group.dms_replication_instance.id
}

output "security_group_arn" {
  description = "ARN of the security group for DMS replication instance"
  value       = aws_security_group.dms_replication_instance.arn
}

output "security_group_name" {
  description = "Name of the security group for DMS replication instance"
  value       = aws_security_group.dms_replication_instance.name
}

#############################################
# KMS and Encryption Outputs
#############################################

output "kms_key_arn" {
  description = "ARN of the KMS key used for DMS encryption"
  value       = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for DMS encryption"
  value       = var.create_kms_key ? aws_kms_key.dms[0].key_id : ""
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = var.create_kms_key ? aws_kms_alias.dms[0].arn : ""
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = var.create_kms_key ? aws_kms_alias.dms[0].name : ""
}

#############################################
# S3 Bucket Outputs
#############################################

output "s3_bucket_name" {
  description = "Name of the S3 bucket for DMS logs and migration data"
  value       = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].id : var.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for DMS logs and migration data"
  value       = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].arn : ""
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].bucket_domain_name : ""
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].bucket_regional_domain_name : ""
}

#############################################
# CloudWatch Logs Outputs
#############################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DMS"
  value       = aws_cloudwatch_log_group.dms.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DMS"
  value       = aws_cloudwatch_log_group.dms.arn
}

output "cloudwatch_log_group_retention_in_days" {
  description = "Retention period in days for CloudWatch log group"
  value       = aws_cloudwatch_log_group.dms.retention_in_days
}

#############################################
# IAM Role Outputs
#############################################

output "iam_roles" {
  description = "ARNs of the IAM roles created for DMS"
  value = {
    dms_vpc_role            = var.create_dms_vpc_role ? aws_iam_role.dms_vpc_role[0].arn : ""
    dms_cloudwatch_logs_role = var.create_dms_cloudwatch_logs_role ? aws_iam_role.dms_cloudwatch_logs_role[0].arn : ""
    dms_access_for_endpoint = var.create_dms_access_for_endpoint_role ? aws_iam_role.dms_access_for_endpoint[0].arn : ""
  }
}

output "dms_vpc_role_name" {
  description = "Name of the DMS VPC role"
  value       = var.create_dms_vpc_role ? aws_iam_role.dms_vpc_role[0].name : ""
}

output "dms_cloudwatch_logs_role_name" {
  description = "Name of the DMS CloudWatch logs role"
  value       = var.create_dms_cloudwatch_logs_role ? aws_iam_role.dms_cloudwatch_logs_role[0].name : ""
}

output "dms_access_for_endpoint_role_name" {
  description = "Name of the DMS access for endpoint role"
  value       = var.create_dms_access_for_endpoint_role ? aws_iam_role.dms_access_for_endpoint[0].name : ""
}

#############################################
# CloudWatch Alarm Outputs
#############################################

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs for DMS monitoring"
  value = var.enable_cloudwatch_alarms ? {
    cpu_utilization = {
      name = aws_cloudwatch_metric_alarm.dms_cpu_utilization[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.dms_cpu_utilization[0].arn
    }
    freeable_memory = {
      name = aws_cloudwatch_metric_alarm.dms_freeable_memory[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.dms_freeable_memory[0].arn
    }
    replication_lag = var.migration_type != "full-load" && var.create_replication_task ? {
      name = aws_cloudwatch_metric_alarm.dms_replication_lag[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.dms_replication_lag[0].arn
    } : null
  } : {}
}

#############################################
# Connection Information Outputs
#############################################

output "connection_info" {
  description = "Connection information for DMS resources"
  value = {
    replication_instance = {
      id         = aws_dms_replication_instance.main.replication_instance_id
      class      = aws_dms_replication_instance.main.replication_instance_class
      multi_az   = aws_dms_replication_instance.main.multi_az
      vpc_id     = aws_dms_replication_subnet_group.main.vpc_id
      subnet_ids = aws_dms_replication_subnet_group.main.subnet_ids
    }
    endpoints = {
      source = var.create_source_endpoint ? {
        id          = aws_dms_endpoint.source[0].endpoint_id
        engine_name = aws_dms_endpoint.source[0].engine_name
        server_name = aws_dms_endpoint.source[0].server_name
        port        = aws_dms_endpoint.source[0].port
      } : null
      target = var.create_target_endpoint ? {
        id          = aws_dms_endpoint.target[0].endpoint_id
        engine_name = aws_dms_endpoint.target[0].engine_name
        server_name = aws_dms_endpoint.target[0].server_name
        port        = aws_dms_endpoint.target[0].port
      } : null
    }
    task = var.create_replication_task ? {
      id             = aws_dms_replication_task.main[0].replication_task_id
      migration_type = aws_dms_replication_task.main[0].migration_type
      status         = aws_dms_replication_task.main[0].status
    } : null
  }
  sensitive = true
}

#############################################
# Resource Summary Output
#############################################

output "resource_summary" {
  description = "Summary of all created DMS resources"
  value = {
    replication_instance_id = aws_dms_replication_instance.main.replication_instance_id
    subnet_group_id        = aws_dms_replication_subnet_group.main.id
    security_group_id      = aws_security_group.dms_replication_instance.id
    source_endpoint_id     = var.create_source_endpoint ? aws_dms_endpoint.source[0].endpoint_id : "not_created"
    target_endpoint_id     = var.create_target_endpoint ? aws_dms_endpoint.target[0].endpoint_id : "not_created"
    replication_task_id    = var.create_replication_task ? aws_dms_replication_task.main[0].replication_task_id : "not_created"
    kms_key_arn           = var.create_kms_key ? aws_kms_key.dms[0].arn : var.kms_key_arn
    s3_bucket_name        = var.create_s3_bucket ? aws_s3_bucket.dms_migration_logs[0].id : var.s3_bucket_name
    log_group_name        = aws_cloudwatch_log_group.dms.name
    alarms_enabled        = var.enable_cloudwatch_alarms
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
  }
}