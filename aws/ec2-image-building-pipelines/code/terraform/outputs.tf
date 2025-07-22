# Output Values for EC2 Image Builder Infrastructure

# Pipeline Information
output "image_pipeline_arn" {
  description = "ARN of the EC2 Image Builder pipeline"
  value       = aws_imagebuilder_image_pipeline.web_server.arn
}

output "image_pipeline_name" {
  description = "Name of the EC2 Image Builder pipeline"
  value       = aws_imagebuilder_image_pipeline.web_server.name
}

output "image_pipeline_status" {
  description = "Status of the EC2 Image Builder pipeline"
  value       = aws_imagebuilder_image_pipeline.web_server.status
}

# Recipe Information
output "image_recipe_arn" {
  description = "ARN of the EC2 Image Builder recipe"
  value       = aws_imagebuilder_image_recipe.web_server.arn
}

output "image_recipe_name" {
  description = "Name of the EC2 Image Builder recipe"
  value       = aws_imagebuilder_image_recipe.web_server.name
}

output "image_recipe_version" {
  description = "Version of the EC2 Image Builder recipe"
  value       = aws_imagebuilder_image_recipe.web_server.version
}

# Component Information
output "build_component_arn" {
  description = "ARN of the web server build component"
  value       = aws_imagebuilder_component.web_server.arn
}

output "build_component_name" {
  description = "Name of the web server build component"
  value       = aws_imagebuilder_component.web_server.name
}

output "test_component_arn" {
  description = "ARN of the web server test component"
  value       = aws_imagebuilder_component.web_server_test.arn
}

output "test_component_name" {
  description = "Name of the web server test component"
  value       = aws_imagebuilder_component.web_server_test.name
}

# Infrastructure Configuration
output "infrastructure_configuration_arn" {
  description = "ARN of the Image Builder infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.web_server.arn
}

output "infrastructure_configuration_name" {
  description = "Name of the Image Builder infrastructure configuration"
  value       = aws_imagebuilder_infrastructure_configuration.web_server.name
}

# Distribution Configuration
output "distribution_configuration_arn" {
  description = "ARN of the Image Builder distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.web_server.arn
}

output "distribution_configuration_name" {
  description = "Name of the Image Builder distribution configuration"
  value       = aws_imagebuilder_distribution_configuration.web_server.name
}

output "distribution_regions" {
  description = "List of regions where AMIs will be distributed"
  value       = local.distribution_regions
}

# IAM Resources
output "instance_role_arn" {
  description = "ARN of the IAM role for Image Builder instances"
  value       = aws_iam_role.image_builder_instance.arn
}

output "instance_role_name" {
  description = "Name of the IAM role for Image Builder instances"
  value       = aws_iam_role.image_builder_instance.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for Image Builder"
  value       = aws_iam_instance_profile.image_builder.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for Image Builder"
  value       = aws_iam_instance_profile.image_builder.name
}

# Storage Resources
output "s3_bucket_name" {
  description = "Name of the S3 bucket for logs and components"
  value       = aws_s3_bucket.image_builder_logs.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for logs and components"
  value       = aws_s3_bucket.image_builder_logs.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.image_builder_logs.bucket_domain_name
}

# Security Resources
output "security_group_id" {
  description = "ID of the security group for Image Builder instances"
  value       = aws_security_group.image_builder.id
}

output "security_group_arn" {
  description = "ARN of the security group for Image Builder instances"
  value       = aws_security_group.image_builder.arn
}

# Notification Resources
output "sns_topic_arn" {
  description = "ARN of the SNS topic for build notifications"
  value       = aws_sns_topic.image_builder_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for build notifications"
  value       = aws_sns_topic.image_builder_notifications.name
}

# CloudWatch Resources
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Image Builder"
  value       = aws_cloudwatch_log_group.image_builder.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Image Builder"
  value       = aws_cloudwatch_log_group.image_builder.arn
}

# Base Image Information
output "base_image_id" {
  description = "ID of the base Amazon Linux 2 AMI used"
  value       = data.aws_ami.amazon_linux_2.id
}

output "base_image_name" {
  description = "Name of the base Amazon Linux 2 AMI used"
  value       = data.aws_ami.amazon_linux_2.name
}

# Environment Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.current_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = local.account_id
}

# Resource Identifiers
output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# Pipeline Execution Commands
output "manual_build_command" {
  description = "AWS CLI command to trigger a manual pipeline build"
  value       = "aws imagebuilder start-image-pipeline-execution --image-pipeline-arn ${aws_imagebuilder_image_pipeline.web_server.arn}"
}

output "check_pipeline_status_command" {
  description = "AWS CLI command to check pipeline status"
  value       = "aws imagebuilder get-image-pipeline --image-pipeline-arn ${aws_imagebuilder_image_pipeline.web_server.arn}"
}

output "list_pipeline_images_command" {
  description = "AWS CLI command to list images created by the pipeline"
  value       = "aws imagebuilder list-image-pipeline-images --image-pipeline-arn ${aws_imagebuilder_image_pipeline.web_server.arn}"
}