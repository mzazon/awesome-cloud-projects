# Outputs for ECS Task Definitions with Environment Variable Management

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.main.id
}

output "task_definition_arn" {
  description = "ARN of the primary task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "task_definition_family" {
  description = "Family of the task definition"
  value       = aws_ecs_task_definition.main.family
}

output "task_definition_revision" {
  description = "Revision number of the task definition"
  value       = aws_ecs_task_definition.main.revision
}

output "envfiles_task_definition_arn" {
  description = "ARN of the environment files focused task definition"
  value       = aws_ecs_task_definition.envfiles.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing environment files"
  value       = aws_s3_bucket.env_configs.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing environment files"
  value       = aws_s3_bucket.env_configs.arn
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.task_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for the main task"
  value       = aws_cloudwatch_log_group.main.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for the main task"
  value       = aws_cloudwatch_log_group.main.arn
}

output "envfiles_log_group_name" {
  description = "Name of the CloudWatch log group for the envfiles task"
  value       = aws_cloudwatch_log_group.envfiles.name
}

output "systems_manager_parameters" {
  description = "List of Systems Manager parameter names created"
  value = [
    for param in aws_ssm_parameter.app_parameters : param.name
  ]
}

output "systems_manager_secrets" {
  description = "List of Systems Manager secure parameter names created"
  value = [
    for secret in aws_ssm_parameter.app_secrets : secret.name
  ]
  sensitive = true
}

output "environment_file_s3_keys" {
  description = "S3 keys of the uploaded environment files"
  value = [
    for file in aws_s3_object.env_files : file.key
  ]
}

output "vpc_id" {
  description = "ID of the VPC used"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "IDs of the subnets used"
  value       = local.subnet_ids
}

output "security_group_id" {
  description = "ID of the security group used"
  value       = local.security_group_id
}

output "service_discovery_commands" {
  description = "Commands to discover and monitor the deployed service"
  value = {
    describe_service = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.main.name}"
    list_tasks       = "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.main.name}"
    view_logs        = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.main.name}"
    get_parameters   = "aws ssm get-parameters-by-path --path /myapp/${var.environment} --recursive"
    list_env_files   = "aws s3 ls s3://${aws_s3_bucket.env_configs.bucket}/configs/"
  }
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_cluster_status = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.main.name}"
    check_service_health = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.main.name} --query 'services[0].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}'"
    verify_parameters    = "aws ssm get-parameters-by-path --path /myapp --recursive --query 'Parameters[*].Name' --output table"
    test_env_files      = "aws s3 ls s3://${aws_s3_bucket.env_configs.bucket}/configs/ --recursive"
  }
}