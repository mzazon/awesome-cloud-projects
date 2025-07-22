# Output Values for Progressive Web App Amplify Infrastructure
# These outputs provide important information about the deployed infrastructure

output "amplify_app_id" {
  description = "ID of the Amplify application"
  value       = aws_amplify_app.pwa_app.id
}

output "amplify_app_arn" {
  description = "ARN of the Amplify application"
  value       = aws_amplify_app.pwa_app.arn
}

output "amplify_app_name" {
  description = "Name of the Amplify application"
  value       = aws_amplify_app.pwa_app.name
}

output "default_domain" {
  description = "Default domain for the Amplify application"
  value       = aws_amplify_app.pwa_app.default_domain
}

output "branch_name" {
  description = "Name of the main branch"
  value       = aws_amplify_branch.main.branch_name
}

output "branch_url" {
  description = "URL of the main branch deployment"
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.pwa_app.default_domain}"
}

output "custom_domain" {
  description = "Custom domain URL if configured"
  value       = var.domain_name != "" ? "https://${local.full_domain}" : null
}

output "domain_association_status" {
  description = "Status of the custom domain association"
  value       = var.domain_name != "" ? aws_amplify_domain_association.main[0].domain_status : null
}

output "certificate_verification_dns_record" {
  description = "DNS record for certificate verification (if using custom domain)"
  value       = var.domain_name != "" ? aws_amplify_domain_association.main[0].certificate_verification_dns_record : null
}

output "amplify_console_url" {
  description = "URL to the Amplify Console for this application"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/amplify/home?region=${data.aws_region.current.name}#/${aws_amplify_app.pwa_app.id}"
}

output "repository_url" {
  description = "Connected repository URL"
  value       = var.repository_url != "" ? var.repository_url : "Manual deployment (no repository connected)"
}

output "iam_service_role_arn" {
  description = "ARN of the IAM service role for Amplify"
  value       = var.repository_url != "" ? aws_iam_role.amplify_service_role[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.amplify_logs.name
}

output "cloudwatch_build_log_group_name" {
  description = "Name of the CloudWatch log group for build logs"
  value       = aws_cloudwatch_log_group.amplify_build_logs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.pwa_dashboard.dashboard_name}"
}

output "build_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for build failures"
  value       = aws_cloudwatch_metric_alarm.build_failures.alarm_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "framework" {
  description = "Framework configuration"
  value       = var.framework
}

output "performance_mode" {
  description = "Performance mode setting"
  value       = var.performance_mode
}

output "auto_branch_creation_enabled" {
  description = "Whether automatic branch creation is enabled"
  value       = var.enable_auto_branch_creation
}

output "pull_request_preview_enabled" {
  description = "Whether pull request preview is enabled"
  value       = var.enable_pull_request_preview
}

output "deployment_instructions" {
  description = "Instructions for deploying the PWA to this Amplify application"
  value = var.repository_url != "" ? [
    "Repository connected: Automatic deployments enabled",
    "Push code to the '${var.branch_name}' branch to trigger deployment",
    "Monitor build progress in the Amplify Console: ${aws_amplify_app.pwa_app.default_domain}",
    var.domain_name != "" ? "Custom domain: https://${local.full_domain}" : "Default domain: https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.pwa_app.default_domain}"
  ] : [
    "Manual deployment required",
    "1. Connect your Git repository in the Amplify Console",
    "2. Configure your repository URL and access token",
    "3. Push code to trigger automatic deployment",
    "Console URL: https://${data.aws_region.current.name}.console.aws.amazon.com/amplify/home#/${aws_amplify_app.pwa_app.id}"
  ]
}

# Security and best practices outputs
output "security_headers_configured" {
  description = "Confirmation that security headers are configured"
  value       = "Security headers configured: X-Frame-Options, X-Content-Type-Options, Referrer-Policy, X-XSS-Protection"
}

output "pwa_optimization_configured" {
  description = "Confirmation that PWA optimizations are configured"
  value       = "PWA optimizations configured: Service Worker caching, Manifest headers, SPA routing"
}

output "monitoring_configured" {
  description = "Confirmation that monitoring is configured"
  value = {
    cloudwatch_logs      = "Enabled with 14-day retention"
    build_logs          = "Enabled with 7-day retention" 
    build_failure_alarm = "Configured for immediate notification"
    dashboard           = "Available for performance monitoring"
  }
}

# Cost optimization information
output "cost_optimization_notes" {
  description = "Information about cost optimization features"
  value = [
    "Free tier: 1,000 build minutes and 5 GB data transfer per month",
    "Pay-as-you-use: $0.01 per build minute after free tier",
    "Data transfer: $0.15 per GB after free tier",
    "Storage: $0.023 per GB stored",
    "Custom domain: No additional cost (SSL certificates included)",
    "CloudWatch logs: Minimal cost for retention periods configured"
  ]
}