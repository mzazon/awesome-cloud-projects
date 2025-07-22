# Core Infrastructure Outputs
output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for deployment"
  value       = local.subnet_ids
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Load Balancer Outputs
output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.webapp_alb.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.webapp_alb.dns_name
}

output "load_balancer_url" {
  description = "URL of the deployed application"
  value       = "http://${aws_lb.webapp_alb.dns_name}"
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.webapp_alb.zone_id
}

# Target Group Outputs
output "blue_target_group_arn" {
  description = "ARN of the blue target group"
  value       = aws_lb_target_group.blue_tg.arn
}

output "green_target_group_arn" {
  description = "ARN of the green target group"
  value       = aws_lb_target_group.green_tg.arn
}

output "blue_target_group_name" {
  description = "Name of the blue target group"
  value       = aws_lb_target_group.blue_tg.name
}

output "green_target_group_name" {
  description = "Name of the green target group"
  value       = aws_lb_target_group.green_tg.name
}

# Auto Scaling Group Outputs
output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.webapp_asg.arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.webapp_asg.name
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.webapp_lt.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.webapp_lt.latest_version
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.alb_sg.id
}

output "ec2_security_group_id" {
  description = "ID of the EC2 instances security group"
  value       = aws_security_group.ec2_sg.id
}

# EC2 Key Pair Outputs
output "key_pair_name" {
  description = "Name of the EC2 key pair"
  value       = var.create_key_pair ? aws_key_pair.webapp_keypair[0].key_name : var.key_pair_name
}

output "private_key_pem" {
  description = "Private key in PEM format (sensitive)"
  value       = var.create_key_pair ? tls_private_key.webapp_key[0].private_key_pem : null
  sensitive   = true
}

# IAM Role Outputs
output "codedeploy_service_role_arn" {
  description = "ARN of the CodeDeploy service role"
  value       = aws_iam_role.codedeploy_service_role.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_codedeploy_profile.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_codedeploy_profile.name
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_service_role.arn
}

# S3 Bucket Outputs
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

output "artifacts_bucket_domain_name" {
  description = "Domain name of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.bucket_domain_name
}

# CodeCommit Outputs
output "codecommit_repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.webapp_repo.repository_name
}

output "codecommit_repository_id" {
  description = "ID of the CodeCommit repository"
  value       = aws_codecommit_repository.webapp_repo.repository_id
}

output "codecommit_clone_url_http" {
  description = "HTTP clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.webapp_repo.clone_url_http
}

output "codecommit_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.webapp_repo.clone_url_ssh
}

# CodeBuild Outputs
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.webapp_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.webapp_build.arn
}

# CodeDeploy Outputs
output "codedeploy_application_name" {
  description = "Name of the CodeDeploy application"
  value       = aws_codedeploy_app.webapp_app.name
}

output "codedeploy_application_id" {
  description = "ID of the CodeDeploy application"
  value       = aws_codedeploy_app.webapp_app.id
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.webapp_deployment_group.deployment_group_name
}

output "codedeploy_deployment_group_id" {
  description = "ID of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.webapp_deployment_group.id
}

output "deployment_config_name" {
  description = "CodeDeploy deployment configuration name"
  value       = var.deployment_config_name
}

# CloudWatch Alarms Outputs
output "deployment_failure_alarm_name" {
  description = "Name of the deployment failure CloudWatch alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.deployment_failure[0].alarm_name : null
}

output "target_health_alarm_name" {
  description = "Name of the target health CloudWatch alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.target_health[0].alarm_name : null
}

# Resource Names and Identifiers
output "resource_name_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_id.suffix.hex
}

# Sample Application Commands
output "sample_curl_command" {
  description = "Sample curl command to test the deployed application"
  value       = "curl -I http://${aws_lb.webapp_alb.dns_name}"
}

output "sample_build_command" {
  description = "Sample AWS CLI command to start a CodeBuild build"
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.webapp_build.name} --region ${data.aws_region.current.name}"
}

output "sample_deployment_command" {
  description = "Sample AWS CLI command to create a CodeDeploy deployment"
  value       = "aws deploy create-deployment --application-name ${aws_codedeploy_app.webapp_app.name} --deployment-group-name ${aws_codedeploy_deployment_group.webapp_deployment_group.deployment_group_name} --s3-location bucket=${aws_s3_bucket.artifacts.bucket},key=artifacts,bundleType=zip --region ${data.aws_region.current.name}"
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Step-by-step instructions for deploying the application"
  value = [
    "1. Clone the CodeCommit repository: git clone ${aws_codecommit_repository.webapp_repo.clone_url_http}",
    "2. Add your application code and appspec.yml file",
    "3. Commit and push changes: git add . && git commit -m 'Initial commit' && git push origin main",
    "4. Start a build: ${substr("aws codebuild start-build --project-name ${aws_codebuild_project.webapp_build.name} --region ${data.aws_region.current.name}", 0, 100)}...",
    "5. Create deployment using the sample command above",
    "6. Monitor deployment progress in the AWS Console",
    "7. Access your application at: http://${aws_lb.webapp_alb.dns_name}"
  ]
}