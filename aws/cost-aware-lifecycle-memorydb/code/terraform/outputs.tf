# Output Values for Cost-Aware MemoryDB Lifecycle Management
# These outputs provide essential information for verification, integration, and operational monitoring

# MemoryDB Cluster Information
output "memorydb_cluster_name" {
  description = "Name of the MemoryDB cluster"
  value       = aws_memorydb_cluster.main.cluster_name
}

output "memorydb_cluster_endpoint" {
  description = "MemoryDB cluster endpoint for application connections"
  value       = aws_memorydb_cluster.main.cluster_endpoint[0].address
  sensitive   = false
}

output "memorydb_cluster_port" {
  description = "Port number for MemoryDB cluster connections"
  value       = aws_memorydb_cluster.main.cluster_endpoint[0].port
}

output "memorydb_cluster_status" {
  description = "Current status of the MemoryDB cluster"
  value       = aws_memorydb_cluster.main.status
}

output "memorydb_cluster_node_type" {
  description = "Current node type of the MemoryDB cluster"
  value       = aws_memorydb_cluster.main.node_type
}

output "memorydb_cluster_arn" {
  description = "ARN of the MemoryDB cluster"
  value       = aws_memorydb_cluster.main.arn
}

output "memorydb_security_group_id" {
  description = "Security group ID for the MemoryDB cluster"
  value       = aws_security_group.memorydb.id
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the cost optimization Lambda function"
  value       = aws_lambda_function.cost_optimizer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the cost optimization Lambda function"
  value       = aws_lambda_function.cost_optimizer.arn
}

output "lambda_function_role_arn" {
  description = "IAM role ARN used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# EventBridge Scheduler Information
output "scheduler_group_name" {
  description = "Name of the EventBridge Scheduler group"
  value       = var.enable_scheduler_automation ? aws_scheduler_schedule_group.cost_optimization[0].name : null
}

output "business_hours_start_schedule_name" {
  description = "Name of the business hours start schedule"
  value       = var.enable_scheduler_automation ? aws_scheduler_schedule.business_hours_start[0].name : null
}

output "business_hours_end_schedule_name" {
  description = "Name of the business hours end schedule"
  value       = var.enable_scheduler_automation ? aws_scheduler_schedule.business_hours_end[0].name : null
}

output "weekly_analysis_schedule_name" {
  description = "Name of the weekly cost analysis schedule"
  value       = var.enable_scheduler_automation ? aws_scheduler_schedule.weekly_analysis[0].name : null
}

output "scheduler_role_arn" {
  description = "IAM role ARN used by EventBridge Scheduler"
  value       = var.enable_scheduler_automation ? aws_iam_role.scheduler_execution_role[0].arn : null
}

# Cost Management Information
output "budget_name" {
  description = "Name of the AWS Budget for cost monitoring"
  value       = var.enable_cost_budget ? aws_budgets_budget.memorydb_cost_budget[0].name : null
}

output "budget_limit_amount" {
  description = "Monthly budget limit amount in USD"
  value       = var.enable_cost_budget ? var.monthly_budget_limit : null
}

output "cost_alert_email" {
  description = "Email address configured for cost alerts"
  value       = var.cost_alert_email
  sensitive   = true
}

# Monitoring and Observability
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for cost optimization monitoring"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = var.enable_detailed_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name}" : null
}

output "weekly_cost_alarm_name" {
  description = "Name of the weekly cost threshold alarm"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.weekly_cost_high[0].alarm_name : null
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda function error alarm"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

# Networking Information
output "vpc_id" {
  description = "VPC ID where MemoryDB cluster is deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used by the MemoryDB cluster"
  value       = local.subnet_ids
}

output "subnet_group_name" {
  description = "Name of the MemoryDB subnet group"
  value       = aws_memorydb_subnet_group.main.name
}

# Configuration Information
output "cost_optimization_configuration" {
  description = "Summary of cost optimization configuration"
  value = {
    business_hours_start_cron = var.business_hours_start_cron
    business_hours_end_cron   = var.business_hours_end_cron
    weekly_analysis_cron      = var.weekly_analysis_cron
    scale_up_threshold        = var.scale_up_cost_threshold
    scale_down_threshold      = var.scale_down_cost_threshold
    weekly_analysis_threshold = var.weekly_analysis_cost_threshold
    scheduler_automation      = var.enable_scheduler_automation
    detailed_monitoring       = var.enable_detailed_monitoring
    cost_budget_enabled       = var.enable_cost_budget
  }
}

# Resource Naming Information
output "resource_naming_info" {
  description = "Information about resource naming patterns"
  value = {
    resource_prefix   = var.resource_prefix
    random_suffix     = random_string.suffix.result
    cluster_name      = local.cluster_name
    environment       = var.environment
    cost_center       = var.cost_center
  }
}

# Operational Information
output "testing_commands" {
  description = "Commands for testing the cost optimization system"
  value = {
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.cost_optimizer.function_name} --payload '{\"cluster_name\":\"${local.cluster_name}\",\"action\":\"analyze\",\"cost_threshold\":100}' /tmp/response.json"
    view_cluster_status  = "aws memorydb describe-clusters --cluster-name ${local.cluster_name}"
    view_lambda_logs     = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
    view_cost_metrics    = "aws cloudwatch get-metric-statistics --namespace MemoryDB/CostOptimization --metric-name WeeklyCost --dimensions Name=ClusterName,Value=${local.cluster_name} --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Average"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    lambda_role_name      = local.lambda_role_name
    scheduler_role_name   = local.scheduler_role_name
    security_group_id     = aws_security_group.memorydb.id
    allowed_cidr_blocks   = var.allowed_cidr_blocks
    deletion_protection   = var.enable_deletion_protection
  }
}