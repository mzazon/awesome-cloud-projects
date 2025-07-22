# ============================================================================
# Outputs for Low-Latency Edge Applications with AWS Wavelength and CloudFront
# ============================================================================

# ============================================================================
# Project Information
# ============================================================================

output "project_name" {
  description = "The project name with random suffix"
  value       = local.project_name
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "wavelength_zone" {
  description = "Wavelength Zone used for edge deployment"
  value       = local.wavelength_zone
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

# ============================================================================
# Network Information
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "wavelength_subnet_id" {
  description = "ID of the Wavelength subnet"
  value       = aws_subnet.wavelength.id
}

output "regional_subnet_id" {
  description = "ID of the regional subnet"
  value       = aws_subnet.regional.id
}

output "carrier_gateway_id" {
  description = "ID of the Carrier Gateway"
  value       = aws_ec2_carrier_gateway.main.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# ============================================================================
# Security Groups
# ============================================================================

output "wavelength_security_group_id" {
  description = "ID of the Wavelength security group"
  value       = aws_security_group.wavelength.id
}

output "regional_security_group_id" {
  description = "ID of the regional security group"
  value       = aws_security_group.regional.id
}

# ============================================================================
# Compute Resources
# ============================================================================

output "wavelength_instance_id" {
  description = "ID of the Wavelength edge server"
  value       = aws_instance.wavelength_server.id
}

output "wavelength_instance_private_ip" {
  description = "Private IP address of the Wavelength edge server"
  value       = aws_instance.wavelength_server.private_ip
}

output "wavelength_instance_type" {
  description = "Instance type of the Wavelength edge server"
  value       = aws_instance.wavelength_server.instance_type
}

output "regional_instance_ids" {
  description = "IDs of the regional backend servers"
  value       = var.deploy_regional_backend ? aws_instance.regional_server[*].id : []
}

output "regional_instance_private_ips" {
  description = "Private IP addresses of the regional backend servers"
  value       = var.deploy_regional_backend ? aws_instance.regional_server[*].private_ip : []
}

output "regional_instance_public_ips" {
  description = "Public IP addresses of the regional backend servers"
  value       = var.deploy_regional_backend ? aws_instance.regional_server[*].public_ip : []
}

# ============================================================================
# Load Balancer Information
# ============================================================================

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.wavelength_alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.wavelength_alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.wavelength_alb.zone_id
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.wavelength_alb.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.wavelength_targets.arn
}

# ============================================================================
# S3 and Storage
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  value       = aws_s3_bucket.static_assets.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for static assets"
  value       = aws_s3_bucket.static_assets.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.static_assets.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.static_assets.bucket_regional_domain_name
}

# ============================================================================
# CloudFront Distribution
# ============================================================================

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_hosted_zone_id" {
  description = "Zone ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "cloudfront_status" {
  description = "Status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.status
}

# ============================================================================
# DNS Information
# ============================================================================

output "route53_zone_id" {
  description = "ID of the Route 53 hosted zone"
  value       = var.domain_name != "" ? aws_route53_zone.main[0].zone_id : null
}

output "route53_name_servers" {
  description = "Name servers for the Route 53 hosted zone"
  value       = var.domain_name != "" ? aws_route53_zone.main[0].name_servers : null
}

output "custom_domain_url" {
  description = "URL using custom domain (if configured)"
  value       = var.domain_name != "" ? "https://app.${var.domain_name}" : null
}

# ============================================================================
# IAM Resources
# ============================================================================

output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

# ============================================================================
# Monitoring and Logging
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# ============================================================================
# Application Configuration
# ============================================================================

output "application_port" {
  description = "Port used by the edge application"
  value       = var.application_port
}

output "health_check_port" {
  description = "Port used for health checks"
  value       = var.health_check_port
}

output "health_check_path" {
  description = "Path used for health checks"
  value       = var.health_check_path
}

# ============================================================================
# Testing and Validation
# ============================================================================

output "edge_application_test_url" {
  description = "URL to test the edge application directly"
  value       = "http://${aws_lb.wavelength_alb.dns_name}/health"
}

output "static_content_test_url" {
  description = "URL to test static content delivery through CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/index.html"
}

output "api_test_url" {
  description = "URL to test API routing through CloudFront to Wavelength"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/api/health"
}

# ============================================================================
# Connection Information
# ============================================================================

output "wavelength_instance_connect_command" {
  description = "AWS Systems Manager Session Manager command to connect to Wavelength instance"
  value       = "aws ssm start-session --target ${aws_instance.wavelength_server.id} --region ${data.aws_region.current.name}"
}

output "regional_instance_connect_commands" {
  description = "AWS Systems Manager Session Manager commands to connect to regional instances"
  value       = var.deploy_regional_backend ? [for instance in aws_instance.regional_server : "aws ssm start-session --target ${instance.id} --region ${data.aws_region.current.name}"] : []
}

# ============================================================================
# Cost Information
# ============================================================================

output "estimated_monthly_cost_note" {
  description = "Note about estimated monthly costs"
  value       = "Estimated monthly cost: $150-200 USD (includes EC2, data transfer, and CloudFront). Actual costs depend on usage patterns and data transfer volumes."
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = [
    "Use CloudWatch to monitor data transfer costs",
    "Implement intelligent caching strategies to reduce origin requests",
    "Consider using reserved instances for production workloads",
    "Monitor and optimize CloudFront price class based on user geography",
    "Set up billing alerts to track spending"
  ]
}

# ============================================================================
# Security and Compliance
# ============================================================================

output "security_considerations" {
  description = "Important security considerations"
  value = [
    "Regularly update AMIs and apply security patches",
    "Review and rotate IAM credentials periodically",
    "Monitor CloudTrail logs for suspicious activity",
    "Implement AWS WAF rules for CloudFront protection",
    "Use VPC Flow Logs for network monitoring",
    "Enable GuardDuty for threat detection"
  ]
}

output "compliance_resources" {
  description = "Resources created for compliance and governance"
  value = {
    cloudwatch_logs = aws_cloudwatch_log_group.application.name
    encrypted_storage = "All EBS volumes use encryption"
    iam_roles = aws_iam_role.ec2_role.name
    vpc_isolation = aws_vpc.main.id
  }
}

# ============================================================================
# Architecture Validation
# ============================================================================

output "architecture_validation" {
  description = "Architecture validation checklist"
  value = {
    wavelength_zone_enabled = local.wavelength_zone != ""
    carrier_gateway_configured = aws_ec2_carrier_gateway.main.id != ""
    alb_health_checks_enabled = aws_lb_target_group.wavelength_targets.health_check[0].enabled
    cloudfront_origins_configured = length(aws_cloudfront_distribution.main.origin) >= 2
    s3_encryption_enabled = true
    iam_least_privilege = "EC2 instances use minimal required permissions"
  }
}

# ============================================================================
# Next Steps
# ============================================================================

output "deployment_verification_steps" {
  description = "Steps to verify the deployment"
  value = [
    "1. Check Wavelength instance health: curl ${aws_lb.wavelength_alb.dns_name}/health",
    "2. Test static content delivery: curl -I https://${aws_cloudfront_distribution.main.domain_name}/index.html",
    "3. Test API routing to edge: curl https://${aws_cloudfront_distribution.main.domain_name}/api/health",
    "4. Monitor CloudWatch dashboard: ${aws_cloudwatch_dashboard.main.dashboard_name}",
    "5. Review application logs in CloudWatch: ${aws_cloudwatch_log_group.application.name}"
  ]
}

output "scaling_recommendations" {
  description = "Recommendations for scaling the solution"
  value = [
    "Add Auto Scaling Groups for automatic capacity management",
    "Implement multiple Wavelength Zones for geographic coverage",
    "Use Application Load Balancer cross-zone load balancing",
    "Consider containerization with ECS or EKS for better resource utilization",
    "Implement caching layers with ElastiCache for session management"
  ]
}