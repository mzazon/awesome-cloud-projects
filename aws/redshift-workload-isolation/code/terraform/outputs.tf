# Redshift Cluster Outputs
output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier"
  value       = var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].cluster_identifier : var.redshift_cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The Redshift cluster endpoint"
  value       = var.create_redshift_cluster ? "${aws_redshift_cluster.analytics_cluster[0].endpoint}:${aws_redshift_cluster.analytics_cluster[0].port}" : "cluster-not-created"
}

output "redshift_cluster_arn" {
  description = "The Redshift cluster ARN"
  value       = var.create_redshift_cluster ? aws_redshift_cluster.analytics_cluster[0].arn : "cluster-not-created"
}

output "redshift_database_name" {
  description = "The name of the initial database in the Redshift cluster"
  value       = var.redshift_database_name
}

output "redshift_master_username" {
  description = "The master username for the Redshift cluster"
  value       = var.redshift_master_username
  sensitive   = true
}

output "redshift_port" {
  description = "The port on which the Redshift cluster accepts connections"
  value       = var.redshift_port
}

# WLM Configuration Outputs
output "parameter_group_name" {
  description = "The name of the Redshift parameter group with WLM configuration"
  value       = aws_redshift_parameter_group.wlm_parameter_group.name
}

output "wlm_configuration_summary" {
  description = "Summary of WLM queue configuration"
  value = {
    bi_dashboard_queue = {
      concurrency    = var.wlm_dashboard_queue_concurrency
      memory_percent = var.wlm_dashboard_memory_percent
      user_group     = "bi-dashboard-group"
      query_group    = "dashboard"
    }
    data_science_queue = {
      concurrency    = var.wlm_analytics_queue_concurrency
      memory_percent = var.wlm_analytics_memory_percent
      user_group     = "data-science-group"
      query_group    = "analytics"
    }
    etl_queue = {
      concurrency    = var.wlm_etl_queue_concurrency
      memory_percent = var.wlm_etl_memory_percent
      user_group     = "etl-process-group"
      query_group    = "etl"
    }
    default_queue = {
      concurrency    = 2
      memory_percent = 10
      description    = "Default queue for ad-hoc queries"
    }
  }
}

# Security Configuration Outputs
output "security_group_id" {
  description = "The ID of the security group used by the Redshift cluster"
  value       = aws_security_group.redshift_sg.id
}

output "subnet_group_name" {
  description = "The name of the Redshift subnet group"
  value       = aws_redshift_subnet_group.redshift_subnet_group.name
}

output "vpc_id" {
  description = "The VPC ID where the Redshift cluster is deployed"
  value       = local.vpc_id
}

# Monitoring and Alerting Outputs
output "sns_topic_arn" {
  description = "The ARN of the SNS topic for WLM alerts"
  value       = var.enable_wlm_monitoring ? aws_sns_topic.wlm_alerts[0].arn : "monitoring-disabled"
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for WLM monitoring"
  value       = var.enable_wlm_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=RedshiftWLM-${random_string.suffix.result}" : "monitoring-disabled"
}

output "cloudwatch_alarms" {
  description = "Names of CloudWatch alarms created for monitoring"
  value = var.enable_wlm_monitoring ? {
    high_queue_wait_time       = aws_cloudwatch_metric_alarm.high_queue_wait_time[0].alarm_name
    high_cpu_utilization      = aws_cloudwatch_metric_alarm.high_cpu_utilization[0].alarm_name
    low_query_completion_rate  = aws_cloudwatch_metric_alarm.low_query_completion_rate[0].alarm_name
  } : {}
}

# Logging Configuration Outputs
output "s3_log_bucket_name" {
  description = "The name of the S3 bucket for Redshift logs"
  value       = aws_s3_bucket.redshift_logs.bucket
}

output "s3_log_bucket_arn" {
  description = "The ARN of the S3 bucket for Redshift logs"
  value       = aws_s3_bucket.redshift_logs.arn
}

# Secrets Manager Output
output "redshift_password_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Redshift password"
  value       = var.create_redshift_cluster ? aws_secretsmanager_secret.redshift_password[0].arn : "cluster-not-created"
  sensitive   = true
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to the Redshift cluster and testing WLM"
  value = var.create_redshift_cluster ? {
    endpoint = "${aws_redshift_cluster.analytics_cluster[0].endpoint}:${aws_redshift_cluster.analytics_cluster[0].port}"
    database = var.redshift_database_name
    username = var.redshift_master_username
    ssl_mode = "require"
    connection_string = "postgresql://${var.redshift_master_username}@${aws_redshift_cluster.analytics_cluster[0].endpoint}:${aws_redshift_cluster.analytics_cluster[0].port}/${var.redshift_database_name}?sslmode=require"
    
    # SQL commands to create user groups and test WLM
    setup_commands = [
      "-- Create user groups for workload isolation",
      "CREATE GROUP \"bi-dashboard-group\";",
      "CREATE GROUP \"data-science-group\";",
      "CREATE GROUP \"etl-process-group\";",
      "",
      "-- Create test users",
      "CREATE USER dashboard_user1 PASSWORD 'BiUser123!@#' IN GROUP \"bi-dashboard-group\";",
      "CREATE USER analytics_user1 PASSWORD 'DsUser123!@#' IN GROUP \"data-science-group\";",
      "CREATE USER etl_user1 PASSWORD 'EtlUser123!@#' IN GROUP \"etl-process-group\";",
      "",
      "-- Grant permissions",
      "GRANT ALL ON SCHEMA public TO GROUP \"bi-dashboard-group\";",
      "GRANT ALL ON SCHEMA public TO GROUP \"data-science-group\";",
      "GRANT ALL ON SCHEMA public TO GROUP \"etl-process-group\";"
    ]
    
    monitoring_queries = [
      "-- Check WLM configuration",
      "SELECT * FROM stv_wlm_classification_config ORDER BY service_class;",
      "",
      "-- Monitor queue performance",
      "SELECT service_class, num_query_tasks, num_executing_queries, num_queued_queries FROM stv_wlm_service_class_state WHERE service_class >= 5;",
      "",
      "-- View query monitoring rule actions",
      "SELECT * FROM stl_wlm_rule_action WHERE recordtime >= DATEADD(hour, -1, GETDATE());"
    ]
  } : "cluster-not-created"
  sensitive = true
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes for cost optimization and resource management"
  value = {
    cluster_pause = "Consider pausing the cluster during non-business hours to reduce costs"
    reserved_instances = "Consider purchasing reserved instances for production workloads"
    monitoring_costs = "CloudWatch charges apply for custom metrics and alarms"
    storage_costs = "S3 storage costs apply for audit logs with 90-day retention"
    snapshot_costs = "Automated snapshots incur storage costs based on cluster size"
    
    cost_monitoring_queries = [
      "-- Monitor cluster usage patterns",
      "SELECT DATE_TRUNC('hour', starttime) as hour, COUNT(*) as query_count FROM stl_query WHERE starttime >= DATEADD(day, -7, GETDATE()) GROUP BY 1 ORDER BY 1;",
      "",
      "-- Identify resource-intensive queries",
      "SELECT query, userid, total_exec_time/1000000 as exec_time_seconds FROM stl_query WHERE starttime >= DATEADD(day, -1, GETDATE()) ORDER BY total_exec_time DESC LIMIT 10;"
    ]
  }
}

# Resource Tags Summary
output "resource_tags" {
  description = "Summary of tags applied to all resources"
  value = merge(
    {
      Project     = "Analytics Workload Isolation"
      Recipe      = "analytics-workload-isolation-redshift-workload-management"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}