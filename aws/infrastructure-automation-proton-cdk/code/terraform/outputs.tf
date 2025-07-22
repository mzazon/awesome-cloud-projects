# General Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = local.account_id
}

output "project_name" {
  description = "Project name with unique suffix"
  value       = local.project_name_unique
}

output "random_suffix" {
  description = "Random suffix used for unique naming"
  value       = random_string.suffix.result
}

# S3 Bucket Information
output "template_bucket_name" {
  description = "Name of the S3 bucket storing Proton templates"
  value       = aws_s3_bucket.proton_templates.id
}

output "template_bucket_arn" {
  description = "ARN of the S3 bucket storing Proton templates"
  value       = aws_s3_bucket.proton_templates.arn
}

output "template_bucket_region" {
  description = "Region of the S3 bucket storing Proton templates"
  value       = aws_s3_bucket.proton_templates.region
}

# IAM Role Information
output "proton_service_role_name" {
  description = "Name of the Proton service role"
  value       = var.create_proton_service_role ? aws_iam_role.proton_service_role[0].name : "Not created"
}

output "proton_service_role_arn" {
  description = "ARN of the Proton service role"
  value       = var.create_proton_service_role ? aws_iam_role.proton_service_role[0].arn : "Not created"
}

# Environment Template Information
output "environment_template_name" {
  description = "Name of the Proton environment template"
  value       = aws_proton_environment_template.web_app_env.name
}

output "environment_template_arn" {
  description = "ARN of the Proton environment template"
  value       = aws_proton_environment_template.web_app_env.arn
}

output "environment_template_version" {
  description = "Version of the environment template"
  value       = "${aws_proton_environment_template_version.web_app_env_v1.major_version}.${aws_proton_environment_template_version.web_app_env_v1.minor_version}"
}

output "environment_template_status" {
  description = "Status of the environment template version"
  value       = aws_proton_environment_template_version.web_app_env_v1.status
}

# Service Template Information
output "service_template_name" {
  description = "Name of the Proton service template"
  value       = aws_proton_service_template.web_app_svc.name
}

output "service_template_arn" {
  description = "ARN of the Proton service template"
  value       = aws_proton_service_template.web_app_svc.arn
}

output "service_template_version" {
  description = "Version of the service template"
  value       = "${aws_proton_service_template_version.web_app_svc_v1.major_version}.${aws_proton_service_template_version.web_app_svc_v1.minor_version}"
}

output "service_template_status" {
  description = "Status of the service template version"
  value       = aws_proton_service_template_version.web_app_svc_v1.status
}

# Template Files Information
output "environment_template_s3_key" {
  description = "S3 key of the environment template bundle"
  value       = aws_s3_object.environment_template.key
}

output "service_template_s3_key" {
  description = "S3 key of the service template bundle"
  value       = aws_s3_object.service_template.key
}

# CLI Commands for Creating Environment and Service
output "create_environment_command" {
  description = "AWS CLI command to create a Proton environment"
  value = templatefile("${path.module}/templates/create-environment.tpl", {
    environment_template_name = aws_proton_environment_template.web_app_env.name
    environment_template_version = "${aws_proton_environment_template_version.web_app_env_v1.major_version}.${aws_proton_environment_template_version.web_app_env_v1.minor_version}"
    proton_service_role_arn = var.create_proton_service_role ? aws_iam_role.proton_service_role[0].arn : "YOUR_PROTON_SERVICE_ROLE_ARN"
  })
}

output "create_service_command" {
  description = "AWS CLI command to create a Proton service"
  value = templatefile("${path.module}/templates/create-service.tpl", {
    service_template_name = aws_proton_service_template.web_app_svc.name
    service_template_version = "${aws_proton_service_template_version.web_app_svc_v1.major_version}.${aws_proton_service_template_version.web_app_svc_v1.minor_version}"
  })
}

# Proton Console URLs
output "proton_console_url" {
  description = "URL to access AWS Proton in the console"
  value       = "https://${local.region}.console.aws.amazon.com/proton/home?region=${local.region}"
}

output "environment_template_console_url" {
  description = "URL to view the environment template in the console"
  value       = "https://${local.region}.console.aws.amazon.com/proton/home?region=${local.region}#/environment-templates/${aws_proton_environment_template.web_app_env.name}"
}

output "service_template_console_url" {
  description = "URL to view the service template in the console"
  value       = "https://${local.region}.console.aws.amazon.com/proton/home?region=${local.region}#/service-templates/${aws_proton_service_template.web_app_svc.name}"
}

# Template Summary
output "template_summary" {
  description = "Summary of created Proton templates"
  value = {
    environment_template = {
      name     = aws_proton_environment_template.web_app_env.name
      version  = "${aws_proton_environment_template_version.web_app_env_v1.major_version}.${aws_proton_environment_template_version.web_app_env_v1.minor_version}"
      status   = aws_proton_environment_template_version.web_app_env_v1.status
      description = aws_proton_environment_template.web_app_env.description
    }
    service_template = {
      name     = aws_proton_service_template.web_app_svc.name
      version  = "${aws_proton_service_template_version.web_app_svc_v1.major_version}.${aws_proton_service_template_version.web_app_svc_v1.minor_version}"
      status   = aws_proton_service_template_version.web_app_svc_v1.status
      description = aws_proton_service_template.web_app_svc.description
    }
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps to deploy environments and services"
  value = [
    "1. Review the created templates in the AWS Proton console",
    "2. Create a Proton environment using the environment template",
    "3. Deploy services using the service template",
    "4. Monitor deployments in the Proton console",
    "5. Extend templates with additional infrastructure as needed"
  ]
}