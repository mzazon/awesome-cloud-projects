# Output Values for Simple Website Hosting with Lightsail
# These outputs provide important information for accessing and managing the WordPress site

# WordPress Instance Information
output "instance_name" {
  description = "Name of the created Lightsail instance"
  value       = aws_lightsail_instance.wordpress.name
}

output "instance_id" {
  description = "Unique identifier of the Lightsail instance"
  value       = aws_lightsail_instance.wordpress.id
}

output "instance_arn" {
  description = "Amazon Resource Name (ARN) of the Lightsail instance"
  value       = aws_lightsail_instance.wordpress.arn
}

output "instance_blueprint_id" {
  description = "Blueprint (application stack) used for the instance"
  value       = aws_lightsail_instance.wordpress.blueprint_id
}

output "instance_bundle_id" {
  description = "Bundle (pricing plan) used for the instance"
  value       = aws_lightsail_instance.wordpress.bundle_id
}

output "availability_zone" {
  description = "Availability zone where the instance is located"
  value       = aws_lightsail_instance.wordpress.availability_zone
}

# Network and Access Information
output "public_ip_address" {
  description = "Public IP address of the WordPress instance"
  value       = var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].ip_address : data.aws_lightsail_instance.wordpress.public_ip_address
}

output "private_ip_address" {
  description = "Private IP address of the WordPress instance"
  value       = data.aws_lightsail_instance.wordpress.private_ip_address
}

output "static_ip_name" {
  description = "Name of the static IP address (if created)"
  value       = var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].name : null
}

output "static_ip_arn" {
  description = "ARN of the static IP address (if created)"
  value       = var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].arn : null
}

# Website Access URLs
output "website_url" {
  description = "Primary URL to access the WordPress website"
  value       = var.custom_domain != "" ? "https://${var.custom_domain}" : "http://${var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].ip_address : data.aws_lightsail_instance.wordpress.public_ip_address}"
}

output "wordpress_admin_url" {
  description = "URL to access WordPress admin dashboard"
  value       = "${var.custom_domain != "" ? "https://${var.custom_domain}" : "http://${var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].ip_address : data.aws_lightsail_instance.wordpress.public_ip_address}"}/wp-admin"
}

output "direct_ip_access" {
  description = "Direct IP access URL (useful for testing before DNS setup)"
  value       = "http://${var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].ip_address : data.aws_lightsail_instance.wordpress.public_ip_address}"
}

# SSH Connection Information
output "ssh_connection_command" {
  description = "SSH command to connect to the instance (requires key pair)"
  value       = var.instance_key_pair_name != "" ? "ssh -i ~/.ssh/${var.instance_key_pair_name}.pem bitnami@${var.enable_static_ip ? aws_lightsail_static_ip.wordpress[0].ip_address : data.aws_lightsail_instance.wordpress.public_ip_address}" : "Key pair required for SSH access"
}

output "wordpress_credentials_command" {
  description = "Command to retrieve WordPress admin password via SSH"
  value       = "sudo cat /home/bitnami/bitnami_application_password"
}

# DNS Configuration (if using custom domain)
output "dns_zone_name" {
  description = "Name of the DNS zone (if created)"
  value       = var.custom_domain != "" && var.create_dns_zone ? aws_lightsail_domain.wordpress[0].domain_name : null
}

output "dns_zone_arn" {
  description = "ARN of the DNS zone (if created)"
  value       = var.custom_domain != "" && var.create_dns_zone ? aws_lightsail_domain.wordpress[0].arn : null
}

output "dns_nameservers" {
  description = "Nameservers to configure with your domain registrar (if DNS zone created)"
  value       = var.custom_domain != "" && var.create_dns_zone ? "Configure these nameservers with your domain registrar: Check Lightsail console for nameserver details" : null
}

# Backup Information
output "initial_snapshot_name" {
  description = "Name of the initial instance snapshot (if created)"
  value       = var.enable_automatic_backups ? aws_lightsail_instance_snapshot.wordpress_initial[0].name : null
}

output "initial_snapshot_arn" {
  description = "ARN of the initial instance snapshot (if created)"
  value       = var.enable_automatic_backups ? aws_lightsail_instance_snapshot.wordpress_initial[0].arn : null
}

# Monitoring Information
output "cloudwatch_log_group" {
  description = "CloudWatch log group name for instance monitoring"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.wordpress[0].name : null
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the WordPress hosting configuration"
  value = {
    instance_plan    = var.instance_bundle_id
    blueprint       = var.blueprint_id
    static_ip       = var.enable_static_ip
    custom_domain   = var.custom_domain != "" ? var.custom_domain : "none"
    dns_managed     = var.create_dns_zone
    backups_enabled = var.enable_automatic_backups
    monitoring      = var.enable_monitoring
    environment     = var.environment
  }
}

# Security and Access Notes
output "security_notes" {
  description = "Important security and access information"
  value = {
    wordpress_admin_username = "user"
    password_location        = "/home/bitnami/bitnami_application_password"
    ssh_user                = "bitnami"
    ssl_certificate         = "Configure Let's Encrypt via Bitnami tools or Lightsail console"
    firewall_ports          = "HTTP (80), HTTPS (443), SSH (22)"
    admin_access_note       = "Change default WordPress admin password after first login"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait 2-3 minutes for instance to fully initialize",
    "2. Access website at the provided URL to verify WordPress is running",
    "3. SSH to instance and retrieve WordPress admin password",
    "4. Login to WordPress admin and change default password",
    "5. Configure SSL certificate via Lightsail console or Bitnami tools",
    "6. If using custom domain, update nameservers with your registrar",
    "7. Install security plugins and configure WordPress settings",
    "8. Set up regular backups and monitoring"
  ]
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost based on selected bundle"
  value = {
    nano_3_0   = "$5 USD/month"
    micro_3_0  = "$10 USD/month"
    small_3_0  = "$20 USD/month"
    medium_3_0 = "$40 USD/month"
    large_3_0  = "$80 USD/month"
    xlarge_3_0 = "$160 USD/month"
    selected   = var.instance_bundle_id
    note       = "Prices include compute, storage, and data transfer. Additional charges may apply for DNS zones and backups."
  }
}