# Project and region outputs
output "project_id" {
  description = "The GCP project ID used for deployment"
  value       = var.project_id
}

output "region" {
  description = "The GCP region used for deployment"
  value       = var.region
}

# Storage bucket outputs
output "bucket_name" {
  description = "Name of the Cloud Storage bucket hosting the website"
  value       = google_storage_bucket.website_bucket.name
}

output "bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.website_bucket.url
}

output "bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.website_bucket.self_link
}

output "website_storage_url" {
  description = "Direct Google Cloud Storage URL for the website"
  value       = "https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/index.html"
}

# DNS outputs
output "dns_zone_name" {
  description = "Name of the Cloud DNS managed zone"
  value       = google_dns_managed_zone.website_zone.name
}

output "dns_zone_id" {
  description = "ID of the Cloud DNS managed zone"
  value       = google_dns_managed_zone.website_zone.id
}

output "name_servers" {
  description = "Name servers for the DNS zone - configure these with your domain registrar"
  value       = google_dns_managed_zone.website_zone.name_servers
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone"
  value       = google_dns_managed_zone.website_zone.dns_name
}

# Website access outputs
output "domain_name" {
  description = "Domain name for the website"
  value       = var.domain_name
}

output "website_url" {
  description = "Primary website URL (available after DNS propagation)"
  value       = "http://${var.domain_name}"
}

output "website_https_url" {
  description = "HTTPS website URL (requires additional SSL configuration)"
  value       = "https://${var.domain_name}"
}

# DNS record outputs
output "cname_record" {
  description = "CNAME record configuration"
  value = {
    name    = google_dns_record_set.website_cname.name
    type    = google_dns_record_set.website_cname.type
    ttl     = google_dns_record_set.website_cname.ttl
    rrdatas = google_dns_record_set.website_cname.rrdatas
  }
}

# File outputs
output "index_html_url" {
  description = "Direct URL to the index.html file"
  value       = "https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/${google_storage_bucket_object.index_html.name}"
}

output "error_html_url" {
  description = "Direct URL to the 404.html error page"
  value       = "https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/${google_storage_bucket_object.error_html.name}"
}

# Deployment status outputs
output "apis_enabled" {
  description = "List of APIs enabled for this deployment"
  value = [
    google_project_service.storage_api.service,
    google_project_service.dns_api.service
  ]
}

output "public_access_enabled" {
  description = "Whether public access is enabled for the bucket"
  value       = var.enable_public_access
}

output "bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.website_bucket.location
}

output "bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.website_bucket.storage_class
}

# Advanced configuration outputs
output "cors_enabled" {
  description = "Whether CORS is enabled for the bucket"
  value       = var.enable_cors
}

output "versioning_enabled" {
  description = "Whether object versioning is enabled for the bucket"
  value       = var.enable_versioning
}

output "cache_control_max_age" {
  description = "Cache-Control max-age setting for website content"
  value       = var.cache_control_max_age
}

# Resource identifiers for integration
output "bucket_id" {
  description = "Full resource ID of the storage bucket"
  value       = google_storage_bucket.website_bucket.id
}

output "dns_zone_managed_zone_id" {
  description = "Managed zone ID for use in other resources"
  value       = google_dns_managed_zone.website_zone.managed_zone_id
}

# Deployment instructions
output "deployment_instructions" {
  description = "Instructions for completing the website setup"
  value = <<-EOT
Website deployment completed! Follow these steps to finish setup:

1. Configure DNS with your domain registrar:
   - Update your domain's name servers to use these Google Cloud DNS name servers:
     ${join("\n     ", google_dns_managed_zone.website_zone.name_servers)}

2. Wait for DNS propagation (typically 24-48 hours)

3. Test your website:
   - Direct storage URL: https://storage.googleapis.com/${google_storage_bucket.website_bucket.name}/index.html
   - Domain URL (after DNS): http://${var.domain_name}

4. For HTTPS support, consider:
   - Setting up Cloud Load Balancer with SSL certificates
   - Using Firebase Hosting for automatic SSL
   - Configuring Cloud CDN for global performance

5. Monitor your website:
   - Use Cloud Monitoring for performance metrics
   - Set up uptime checks and alerting
   - Review access logs in Cloud Storage

Note: The website is publicly accessible via the storage URL immediately.
Custom domain access requires DNS configuration with your registrar.
EOT
}

# Cost estimation output
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    storage_gb     = "~$0.020 per GB stored"
    dns_zone       = "~$0.20 per hosted zone"
    dns_queries    = "~$0.40 per million queries"
    data_egress    = "~$0.12 per GB (varies by region)"
    total_estimate = "$0.50-$2.00 for small websites"
    note          = "Actual costs depend on traffic and storage usage"
  }
}

# Security and compliance outputs
output "security_considerations" {
  description = "Security and compliance information"
  value = {
    bucket_access    = var.enable_public_access ? "Public read access enabled" : "Private access only"
    encryption       = "Google-managed encryption at rest (default)"
    access_control   = "Uniform bucket-level access enabled"
    audit_logging    = "Enable Cloud Audit Logs for compliance tracking"
    recommendations  = [
      "Enable Cloud Security Command Center for security monitoring",
      "Configure Cloud Armor for DDoS protection (if using Load Balancer)",
      "Set up Cloud Monitoring alerts for unusual access patterns",
      "Regular security reviews of bucket permissions"
    ]
  }
}