# Output values for the App Runner and RDS infrastructure

# Application Outputs
output "application_url" {
  description = "URL of the deployed App Runner service"
  value       = "https://${aws_apprunner_service.main.service_url}"
}

output "app_runner_service_name" {
  description = "Name of the App Runner service"
  value       = aws_apprunner_service.main.service_name
}

output "app_runner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.main.arn
}

output "app_runner_service_id" {
  description = "ID of the App Runner service"
  value       = aws_apprunner_service.main.service_id
}

output "app_runner_status" {
  description = "Current status of the App Runner service"
  value       = aws_apprunner_service.main.status
}

# Database Outputs
output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "database_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "database_username" {
  description = "Database master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "database_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

# Secrets Manager Outputs
output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "database_secret_name" {
  description = "Name of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

# ECR Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

# Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "app_runner_security_group_id" {
  description = "ID of the App Runner security group"
  value       = aws_security_group.apprunner.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "vpc_connector_arn" {
  description = "ARN of the App Runner VPC connector"
  value       = aws_apprunner_vpc_connector.main.arn
}

# IAM Outputs
output "app_runner_instance_role_arn" {
  description = "ARN of the App Runner instance role"
  value       = aws_iam_role.apprunner_instance_role.arn
}

output "app_runner_access_role_arn" {
  description = "ARN of the App Runner access role"
  value       = aws_iam_role.apprunner_access_role.arn
}

# Monitoring Outputs
output "cloudwatch_log_group_application" {
  description = "CloudWatch log group for App Runner application logs"
  value       = aws_cloudwatch_log_group.apprunner_application.name
}

output "cloudwatch_log_group_service" {
  description = "CloudWatch log group for App Runner service logs"
  value       = aws_cloudwatch_log_group.apprunner_service.name
}

output "observability_configuration_arn" {
  description = "ARN of the App Runner observability configuration"
  value       = aws_apprunner_observability_configuration.main.arn
}

# SNS Topic (if created)
output "alarm_topic_arn" {
  description = "ARN of the SNS topic for alarms (if email notification is configured)"
  value       = var.alarm_notification_email != "" ? aws_sns_topic.alarms[0].arn : null
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.main.arn
}

output "kms_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.main.name
}

# Deployment Information
output "deployment_commands" {
  description = "Commands to build and deploy the container image"
  value = {
    docker_build = "docker build -t ${aws_ecr_repository.main.repository_url}:${var.container_image_tag} ."
    docker_login = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}"
    docker_push  = "docker push ${aws_ecr_repository.main.repository_url}:${var.container_image_tag}"
  }
}

# Health Check Information
output "health_check_url" {
  description = "URL for health check endpoint"
  value       = "https://${aws_apprunner_service.main.service_url}${var.apprunner_health_check_path}"
}

# Connection Information for Development
output "connection_info" {
  description = "Information for connecting to resources during development"
  value = {
    app_url                    = "https://${aws_apprunner_service.main.service_url}"
    health_check_url          = "https://${aws_apprunner_service.main.service_url}${var.apprunner_health_check_path}"
    ecr_repository            = aws_ecr_repository.main.repository_url
    database_secret_name      = aws_secretsmanager_secret.db_credentials.name
    application_logs_command  = "aws logs tail ${aws_cloudwatch_log_group.apprunner_application.name} --follow"
    service_logs_command     = "aws logs tail ${aws_cloudwatch_log_group.apprunner_service.name} --follow"
  }
  sensitive = true
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    project_name        = var.project_name
    environment        = var.environment
    aws_region         = var.aws_region
    app_runner_service = aws_apprunner_service.main.service_name
    database_type      = "PostgreSQL ${var.db_engine_version}"
    database_size      = var.db_instance_class
    container_registry = aws_ecr_repository.main.name
    monitoring_enabled = var.enable_cloudwatch_alarms
    encryption_enabled = var.db_storage_encrypted
  }
}