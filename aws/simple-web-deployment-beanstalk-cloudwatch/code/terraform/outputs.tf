# Output values for the Elastic Beanstalk and CloudWatch deployment

# Application information
output "application_name" {
  description = "Name of the Elastic Beanstalk application"
  value       = aws_elastic_beanstalk_application.app.name
}

output "environment_name" {
  description = "Name of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.env.name
}

output "environment_id" {
  description = "ID of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.env.id
}

# Application access
output "application_url" {
  description = "URL to access the deployed web application"
  value       = "http://${aws_elastic_beanstalk_environment.env.cname}"
}

output "application_cname" {
  description = "CNAME of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.env.cname
}

# Environment status
output "environment_status" {
  description = "Current status of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.env.status
}

output "environment_health" {
  description = "Health status of the Elastic Beanstalk environment"
  value       = aws_elastic_beanstalk_environment.env.health
}

# Infrastructure details
output "load_balancers" {
  description = "List of load balancers associated with the environment"
  value       = aws_elastic_beanstalk_environment.env.load_balancers
}

output "instances" {
  description = "List of EC2 instances associated with the environment"
  value       = aws_elastic_beanstalk_environment.env.instances
}

output "autoscaling_groups" {
  description = "List of Auto Scaling groups associated with the environment"
  value       = aws_elastic_beanstalk_environment.env.autoscaling_groups
}

# Security information
output "security_group_id" {
  description = "ID of the security group created for the Elastic Beanstalk environment"
  value       = aws_security_group.eb_sg.id
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.eb_ec2_profile.name
}

output "iam_service_role_arn" {
  description = "ARN of the IAM service role for Elastic Beanstalk"
  value       = aws_iam_role.eb_service_role.arn
}

# Storage information
output "s3_bucket_name" {
  description = "Name of the S3 bucket used for application source bundles"
  value       = aws_s3_bucket.source_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for application source bundles"
  value       = aws_s3_bucket.source_bucket.arn
}

# Application version
output "application_version" {
  description = "Name of the application version deployed"
  value       = aws_elastic_beanstalk_application_version.app_version.name
}

# CloudWatch monitoring
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for the application"
  value = [
    "/aws/elasticbeanstalk/${aws_elastic_beanstalk_environment.env.name}/var/log/eb-engine.log",
    "/aws/elasticbeanstalk/${aws_elastic_beanstalk_environment.env.name}/var/log/eb-hooks.log",
    "/aws/elasticbeanstalk/${aws_elastic_beanstalk_environment.env.name}/var/log/httpd/access_log",
    "/aws/elasticbeanstalk/${aws_elastic_beanstalk_environment.env.name}/var/log/httpd/error_log"
  ]
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created for monitoring"
  value = var.enable_alarms ? [
    {
      name = aws_cloudwatch_metric_alarm.environment_health[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.environment_health[0].arn
    },
    {
      name = aws_cloudwatch_metric_alarm.application_4xx_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.application_4xx_errors[0].arn
    },
    {
      name = aws_cloudwatch_metric_alarm.application_5xx_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.application_5xx_errors[0].arn
    },
    {
      name = aws_cloudwatch_metric_alarm.response_time[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.response_time[0].arn
    }
  ] : []
}

# SNS topic for notifications
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = var.enable_alarms && var.alarm_notification_email != "" ? aws_sns_topic.alarms[0].arn : null
}

# Network configuration
output "vpc_id" {
  description = "ID of the VPC where the environment is deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "IDs of the subnets where the environment is deployed"
  value       = local.subnet_ids
}

# Cost tracking
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for resources (USD, approximate)"
  value = "Based on t3.micro instances in ${var.aws_region}: ~$8.50/month for 1 instance, ~$17/month for 2 instances (plus data transfer and storage costs)"
}

# Monitoring dashboard
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring the application"
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_elastic_beanstalk_environment.env.name}"
}

# Application endpoints for testing
output "health_check_url" {
  description = "URL for application health check endpoint"
  value       = "http://${aws_elastic_beanstalk_environment.env.cname}/health"
}

output "api_info_url" {
  description = "URL for application info API endpoint"
  value       = "http://${aws_elastic_beanstalk_environment.env.cname}/api/info"
}

# Enhanced health reporting URL
output "enhanced_health_url" {
  description = "URL to view enhanced health reports in the AWS console"
  value = "https://${var.aws_region}.console.aws.amazon.com/elasticbeanstalk/home?region=${var.aws_region}#/environment/dashboard?applicationName=${aws_elastic_beanstalk_application.app.name}&environmentId=${aws_elastic_beanstalk_environment.env.id}"
}

# Application logs URL
output "cloudwatch_logs_url" {
  description = "URL to view application logs in CloudWatch"
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/$252Faws$252Felasticbeanstalk$252F${aws_elastic_beanstalk_environment.env.name}"
}

# Resource summary
output "resource_summary" {
  description = "Summary of AWS resources created"
  value = {
    elastic_beanstalk_application = 1
    elastic_beanstalk_environment = 1
    s3_bucket                    = 1
    iam_roles                    = 2
    iam_instance_profile         = 1
    security_group               = 1
    cloudwatch_alarms            = var.enable_alarms ? 4 : 0
    sns_topic                    = var.enable_alarms && var.alarm_notification_email != "" ? 1 : 0
    ec2_instances                = "${var.min_size}-${var.max_size}"
    application_load_balancer    = 1
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources (for reference)"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "# Terminate environment:",
      "aws elasticbeanstalk terminate-environment --environment-name ${aws_elastic_beanstalk_environment.env.name}",
      "# Delete application:",
      "aws elasticbeanstalk delete-application --application-name ${aws_elastic_beanstalk_application.app.name} --terminate-env-by-force"
    ]
  }
}