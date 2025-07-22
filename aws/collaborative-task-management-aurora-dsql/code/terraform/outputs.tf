# Output values for the real-time collaborative task management infrastructure
# These outputs provide essential information for application integration and monitoring

# ===============================================================================
# AURORA POSTGRESQL CLUSTER OUTPUTS
# ===============================================================================

output "aurora_cluster_identifier" {
  description = "The Aurora PostgreSQL cluster identifier"
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "aurora_cluster_endpoint" {
  description = "The Aurora PostgreSQL cluster endpoint for database connections"
  value       = aws_rds_cluster.primary.endpoint
  sensitive   = true
}

output "aurora_cluster_port" {
  description = "The Aurora PostgreSQL cluster port for database connections"
  value       = aws_rds_cluster.primary.port
}

output "aurora_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.primary.arn
}

output "aurora_global_cluster_id" {
  description = "The Aurora PostgreSQL global cluster identifier for multi-region setup"
  value       = aws_rds_global_cluster.main.global_cluster_identifier
}

output "aurora_secondary_cluster_endpoint" {
  description = "The Aurora PostgreSQL secondary cluster endpoint (if multi-region is enabled)"
  value       = var.enable_multi_region_deployment ? aws_rds_cluster.secondary[0].endpoint : null
  sensitive   = true
}

output "aurora_secondary_cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the Aurora PostgreSQL secondary cluster"
  value       = var.enable_multi_region_deployment ? aws_rds_cluster.secondary[0].arn : null
}

# ===============================================================================
# DATABASE CREDENTIALS OUTPUTS
# ===============================================================================

output "db_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  description = "The name of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "db_username" {
  description = "The database username for Aurora DSQL connections"
  value       = var.db_username
  sensitive   = true
}

# ===============================================================================
# EVENTBRIDGE OUTPUTS
# ===============================================================================

output "event_bus_name" {
  description = "The name of the custom EventBridge event bus for task management"
  value       = aws_cloudwatch_event_bus.task_events.name
}

output "event_bus_arn" {
  description = "The Amazon Resource Name (ARN) of the custom EventBridge event bus"
  value       = aws_cloudwatch_event_bus.task_events.arn
}

output "event_processing_rule_name" {
  description = "The name of the EventBridge rule for task processing"
  value       = aws_cloudwatch_event_rule.task_processing.name
}

output "event_processing_rule_arn" {
  description = "The Amazon Resource Name (ARN) of the EventBridge rule for task processing"
  value       = aws_cloudwatch_event_rule.task_processing.arn
}

output "secondary_event_bus_name" {
  description = "The name of the secondary region EventBridge event bus (if multi-region is enabled)"
  value       = var.enable_multi_region_deployment ? aws_cloudwatch_event_bus.task_events_secondary[0].name : null
}

output "secondary_event_bus_arn" {
  description = "The Amazon Resource Name (ARN) of the secondary region EventBridge event bus"
  value       = var.enable_multi_region_deployment ? aws_cloudwatch_event_bus.task_events_secondary[0].arn : null
}

# ===============================================================================
# LAMBDA FUNCTION OUTPUTS
# ===============================================================================

output "lambda_function_name" {
  description = "The name of the task processor Lambda function"
  value       = aws_lambda_function.task_processor.function_name
}

output "lambda_function_arn" {
  description = "The Amazon Resource Name (ARN) of the task processor Lambda function"
  value       = aws_lambda_function.task_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "The ARN to be used for invoking Lambda function from API Gateway"
  value       = aws_lambda_function.task_processor.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "The qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.task_processor.qualified_arn
}

output "lambda_function_version" {
  description = "The latest published version of the Lambda function"
  value       = aws_lambda_function.task_processor.version
}

output "lambda_function_last_modified" {
  description = "The date this Lambda function was last modified"
  value       = aws_lambda_function.task_processor.last_modified
}

output "lambda_execution_role_arn" {
  description = "The Amazon Resource Name (ARN) of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "The name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "secondary_lambda_function_arn" {
  description = "The Amazon Resource Name (ARN) of the secondary region Lambda function"
  value       = var.enable_multi_region_deployment ? aws_lambda_function.task_processor_secondary[0].arn : null
}

output "secondary_lambda_function_name" {
  description = "The name of the secondary region Lambda function"
  value       = var.enable_multi_region_deployment ? aws_lambda_function.task_processor_secondary[0].function_name : null
}

# ===============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ===============================================================================

output "lambda_log_group_name" {
  description = "The name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "The Amazon Resource Name (ARN) of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_dashboard_url" {
  description = "The URL of the CloudWatch dashboard for monitoring (if enabled)"
  value = var.create_cloudwatch_dashboard ? (
    "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.task_management[0].dashboard_name}"
  ) : null
}

output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard (if enabled)"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.task_management[0].dashboard_name : null
}

output "lambda_error_alarm_arn" {
  description = "The Amazon Resource Name (ARN) of the Lambda error alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "lambda_duration_alarm_arn" {
  description = "The Amazon Resource Name (ARN) of the Lambda duration alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.arn
}

output "lambda_throttle_alarm_arn" {
  description = "The Amazon Resource Name (ARN) of the Lambda throttle alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_throttles.arn
}

# ===============================================================================
# DEAD LETTER QUEUE OUTPUTS
# ===============================================================================

output "lambda_dlq_url" {
  description = "The URL of the Lambda dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.lambda_dlq[0].url : null
}

output "lambda_dlq_arn" {
  description = "The Amazon Resource Name (ARN) of the Lambda dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.lambda_dlq[0].arn : null
}

output "task_dlq_url" {
  description = "The URL of the task processing dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.task_dlq[0].url : null
}

output "task_dlq_arn" {
  description = "The Amazon Resource Name (ARN) of the task processing dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.task_dlq[0].arn : null
}

# ===============================================================================
# SECURITY AND ENCRYPTION OUTPUTS
# ===============================================================================

output "logs_kms_key_id" {
  description = "The KMS key ID used for CloudWatch logs encryption"
  value       = aws_kms_key.logs_encryption.key_id
}

output "logs_kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key used for logs encryption"
  value       = aws_kms_key.logs_encryption.arn
}

output "logs_kms_alias" {
  description = "The KMS key alias for CloudWatch logs encryption"
  value       = aws_kms_alias.logs_encryption.name
}

# ===============================================================================
# REGIONAL CONFIGURATION OUTPUTS
# ===============================================================================

output "primary_region" {
  description = "The primary AWS region for the deployment"
  value       = var.aws_region
}

output "secondary_region" {
  description = "The secondary AWS region for multi-region deployment (if enabled)"
  value       = var.enable_multi_region_deployment ? var.secondary_region : null
}

output "availability_zones" {
  description = "The availability zones used for the deployment"
  value       = data.aws_availability_zones.available.names
}

output "multi_region_enabled" {
  description = "Whether multi-region deployment is enabled"
  value       = var.enable_multi_region_deployment
}

# ===============================================================================
# API INTEGRATION OUTPUTS
# ===============================================================================

output "api_integration_guide" {
  description = "Guide for integrating with the task management API"
  value = {
    lambda_invoke_arn    = aws_lambda_function.task_processor.invoke_arn
    event_bus_name       = aws_cloudwatch_event_bus.task_events.name
    database_secret_arn  = aws_secretsmanager_secret.db_credentials.arn
    sample_event_payload = jsonencode({
      source      = "task.management"
      detail-type = "Task Created"
      detail = {
        eventType = "task.created"
        taskData = {
          title       = "Example Task"
          description = "This is an example task"
          priority    = "high"
          assigned_to = "user@example.com"
          created_by  = "manager@example.com"
          project_id  = 1
        }
      }
    })
  }
}

# ===============================================================================
# CONNECTION INFORMATION FOR APPLICATIONS
# ===============================================================================

output "connection_info" {
  description = "Connection information for applications integrating with the task management system"
  value = {
    database = {
      endpoint   = aws_rds_cluster.primary.endpoint
      port       = aws_rds_cluster.primary.port
      secret_arn = aws_secretsmanager_secret.db_credentials.arn
      username   = var.db_username
    }
    eventbridge = {
      bus_name = aws_cloudwatch_event_bus.task_events.name
      bus_arn  = aws_cloudwatch_event_bus.task_events.arn
    }
    lambda = {
      function_name   = aws_lambda_function.task_processor.function_name
      function_arn    = aws_lambda_function.task_processor.arn
      invoke_arn      = aws_lambda_function.task_processor.invoke_arn
    }
    monitoring = {
      log_group = aws_cloudwatch_log_group.lambda_logs.name
      dashboard = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.task_management[0].dashboard_name : null
    }
  }
  sensitive = true
}

# ===============================================================================
# COST INFORMATION
# ===============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources (development workload)"
  value = {
    aurora_postgresql_estimated = "$15-30/month (Aurora Serverless v2 based on usage)"
    lambda_estimated          = "$5-15/month (based on invocations)"
    eventbridge_estimated     = "$1-5/month (based on events)"
    cloudwatch_estimated      = "$2-8/month (based on logs and metrics)"
    kms_estimated            = "$1/month (key usage)"
    secrets_manager_estimated = "$0.40/month (per secret)"
    vpc_networking_estimated  = "$5-10/month (NAT Gateway and VPC endpoints)"
    total_estimated_range    = "$29-69/month for development workloads"
    notes = [
      "Costs scale with actual usage",
      "Production workloads will have higher costs",
      "Multi-region deployment approximately doubles costs",
      "Consider Reserved Capacity for predictable workloads"
    ]
  }
}

# ===============================================================================
# VALIDATION AND TESTING OUTPUTS
# ===============================================================================

output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.task_processor.function_name} --payload '{}' response.json"
    check_eventbridge_rule = "aws events describe-rule --name ${aws_cloudwatch_event_rule.task_processing.name} --event-bus-name ${aws_cloudwatch_event_bus.task_events.name}"
    view_logs = "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.lambda_logs.name}"
    test_database_connectivity = "aws rds describe-db-clusters --db-cluster-identifier ${aws_rds_cluster.primary.cluster_identifier}"
    get_database_credentials = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_credentials.arn}"
    send_test_event = "aws events put-events --entries '[{\"Source\":\"task.management\",\"DetailType\":\"Task Created\",\"Detail\":\"{\\\"eventType\\\":\\\"task.created\\\",\\\"taskData\\\":{\\\"title\\\":\\\"Test Task\\\",\\\"created_by\\\":\\\"test@example.com\\\"}}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.task_events.name}\"}]'"
  }
}

# ===============================================================================
# RESOURCE SUMMARY
# ===============================================================================

output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    aurora_postgresql_clusters = var.enable_multi_region_deployment ? 2 : 1
    aurora_cluster_instances = var.enable_multi_region_deployment ? 2 : 1
    lambda_functions    = var.enable_multi_region_deployment ? 2 : 1
    eventbridge_buses   = var.enable_multi_region_deployment ? 2 : 1
    eventbridge_rules   = var.enable_multi_region_deployment ? 2 : 1
    cloudwatch_alarms   = 3
    log_groups         = var.enable_multi_region_deployment ? 2 : 1
    secrets            = var.enable_multi_region_deployment ? 2 : 1
    kms_keys           = var.enable_multi_region_deployment ? 2 : 1
    sqs_queues         = var.enable_dead_letter_queue ? (var.enable_multi_region_deployment ? 4 : 2) : 0
    iam_roles          = var.enable_multi_region_deployment ? 2 : 1
    iam_policies       = var.enable_multi_region_deployment ? 2 : 1
    dashboard          = var.create_cloudwatch_dashboard ? 1 : 0
    vpcs               = var.enable_multi_region_deployment ? 2 : 1
    subnets            = var.enable_multi_region_deployment ? 8 : 4
    nat_gateways       = var.enable_multi_region_deployment ? 2 : 1
    security_groups    = var.enable_multi_region_deployment ? 4 : 2
  }
}