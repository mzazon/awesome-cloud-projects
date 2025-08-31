# Outputs for AWS Well-Architected Tool Assessment Infrastructure

# Well-Architected Workload Information
output "workload_id" {
  description = "The ID of the Well-Architected workload"
  value       = aws_wellarchitected_workload.main.id
}

output "workload_name" {
  description = "The name of the Well-Architected workload"
  value       = aws_wellarchitected_workload.main.workload_name
}

output "workload_arn" {
  description = "The ARN of the Well-Architected workload"
  value       = aws_wellarchitected_workload.main.arn
}

output "workload_environment" {
  description = "The environment of the workload"
  value       = aws_wellarchitected_workload.main.environment
}

output "workload_review_owner" {
  description = "The review owner of the workload"
  value       = aws_wellarchitected_workload.main.review_owner
}

output "workload_lenses" {
  description = "The lenses applied to the workload"
  value       = aws_wellarchitected_workload.main.lenses
}

# AWS Console Access URLs
output "wellarchitected_console_url" {
  description = "URL to access the Well-Architected workload in AWS Console"
  value       = "https://console.aws.amazon.com/wellarchitected/home?region=${data.aws_region.current.name}#/workload/${aws_wellarchitected_workload.main.id}"
}

output "lens_review_url" {
  description = "URL to access the lens review in AWS Console"
  value       = "https://console.aws.amazon.com/wellarchitected/home?region=${data.aws_region.current.name}#/workload/${aws_wellarchitected_workload.main.id}/lensReview/wellarchitected"
}

# CloudWatch Resources
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for assessment logging"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_log_group.workload_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_log_group.workload_logs[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.workload_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.workload_dashboard[0].dashboard_name}" : null
}

# SNS Notification Resources
output "sns_topic_arn" {
  description = "ARN of the SNS topic for assessment notifications"
  value       = var.enable_notifications ? aws_sns_topic.assessment_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = var.enable_notifications ? aws_sns_topic.assessment_notifications[0].name : null
}

# IAM Resources
output "automation_role_arn" {
  description = "ARN of the IAM role for Well-Architected automation"
  value       = aws_iam_role.wellarchitected_automation.arn
}

output "automation_role_name" {
  description = "Name of the IAM role for automation"
  value       = aws_iam_role.wellarchitected_automation.name
}

# Sample Infrastructure (when enabled)
output "sample_vpc_id" {
  description = "ID of the sample VPC (if created)"
  value       = var.create_sample_resources ? aws_vpc.sample[0].id : null
}

output "sample_vpc_cidr" {
  description = "CIDR block of the sample VPC"
  value       = var.create_sample_resources ? aws_vpc.sample[0].cidr_block : null
}

output "sample_subnet_id" {
  description = "ID of the sample public subnet"
  value       = var.create_sample_resources ? aws_subnet.sample_public[0].id : null
}

output "sample_security_group_id" {
  description = "ID of the sample security group"
  value       = var.create_sample_resources ? aws_security_group.sample_web[0].id : null
}

# Milestone Information
output "initial_milestone_number" {
  description = "The milestone number for the initial assessment"
  value       = aws_wellarchitected_milestone.initial.milestone_number
}

# Assessment Commands
output "aws_cli_commands" {
  description = "Useful AWS CLI commands for interacting with the workload"
  value = {
    get_workload = "aws wellarchitected get-workload --workload-id ${aws_wellarchitected_workload.main.id}"
    list_answers = "aws wellarchitected list-answers --workload-id ${aws_wellarchitected_workload.main.id} --lens-alias wellarchitected"
    get_lens_review = "aws wellarchitected get-lens-review --workload-id ${aws_wellarchitected_workload.main.id} --lens-alias wellarchitected"
    list_improvements = "aws wellarchitected list-lens-review-improvements --workload-id ${aws_wellarchitected_workload.main.id} --lens-alias wellarchitected"
    list_milestones = "aws wellarchitected list-milestones --workload-id ${aws_wellarchitected_workload.main.id}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    workload_created = true
    monitoring_enabled = var.enable_cloudwatch_dashboard
    notifications_enabled = var.enable_notifications
    sample_infrastructure = var.create_sample_resources
    regions = local.aws_regions
    environment = var.environment
    project_name = var.project_name
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for conducting the Well-Architected assessment"
  value = [
    "1. Access the workload in AWS Console: ${aws_wellarchitected_workload.main.workload_name}",
    "2. Begin lens review using the Well-Architected Framework",
    "3. Answer assessment questions for each of the six pillars",
    "4. Review improvement recommendations and prioritize actions",
    "5. Create additional milestones to track progress over time",
    "6. Set up regular review cycles (recommended: every 6-12 months)"
  ]
}