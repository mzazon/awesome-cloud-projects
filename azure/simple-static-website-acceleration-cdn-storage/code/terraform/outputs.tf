# Output Values for Static Website Acceleration with CDN and Storage
# These outputs provide essential information about the deployed infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "Full resource ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Static Website Endpoints
output "static_website_url" {
  description = "Primary endpoint URL for the static website"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

output "static_website_host" {
  description = "Hostname of the static website endpoint"
  value       = azurerm_storage_account.main.primary_web_host
}

# CDN Information
output "cdn_profile_name" {
  description = "Name of the CDN profile"
  value       = azurerm_cdn_profile.main.name
}

output "cdn_profile_id" {
  description = "Full resource ID of the CDN profile"
  value       = azurerm_cdn_profile.main.id
}

output "cdn_profile_sku" {
  description = "SKU/pricing tier of the CDN profile"
  value       = azurerm_cdn_profile.main.sku
}

# CDN Endpoint Information
output "cdn_endpoint_name" {
  description = "Name of the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.name
}

output "cdn_endpoint_id" {
  description = "Full resource ID of the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.id
}

output "cdn_endpoint_url" {
  description = "Primary URL for accessing content via CDN"
  value       = "https://${azurerm_cdn_endpoint.main.host_name}"
}

output "cdn_endpoint_hostname" {
  description = "Hostname of the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.host_name
}

output "cdn_endpoint_origin_host_header" {
  description = "Origin host header configured for the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.origin_host_header
}

# Performance and Configuration Information
output "compression_enabled" {
  description = "Whether compression is enabled on the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.is_compression_enabled
}

output "optimization_type" {
  description = "Optimization type configured for the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.optimization_type
}

output "query_string_caching_behavior" {
  description = "Query string caching behavior for the CDN endpoint"
  value       = azurerm_cdn_endpoint.main.query_string_caching_behaviour
}

# Website Configuration
output "index_document" {
  description = "Index document configured for the static website"
  value       = var.index_document
}

output "error_404_document" {
  description = "404 error document configured for the static website"
  value       = var.error_404_document
}

# Sample Content Information
output "sample_content_created" {
  description = "Whether sample website content was created and uploaded"
  value       = var.create_sample_content
}

# Testing and Validation URLs
output "testing_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    test_storage_direct = "curl -I ${azurerm_storage_account.main.primary_web_endpoint}"
    test_cdn_endpoint   = "curl -I https://${azurerm_cdn_endpoint.main.host_name}"
    test_compression    = "curl -H 'Accept-Encoding: gzip' -I https://${azurerm_cdn_endpoint.main.host_name}"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources"
  value       = var.tags
}

# Cost and Management Information
output "deployment_summary" {
  description = "Summary of deployed resources and estimated monthly costs"
  value = {
    resource_group = azurerm_resource_group.main.name
    storage_account = {
      name = azurerm_storage_account.main.name
      tier = azurerm_storage_account.main.account_tier
      replication = azurerm_storage_account.main.account_replication_type
      estimated_monthly_cost = "~$1-3 USD (depending on storage and bandwidth usage)"
    }
    cdn_profile = {
      name = azurerm_cdn_profile.main.name
      sku = azurerm_cdn_profile.main.sku
      estimated_monthly_cost = "~$1-2 USD (depending on data transfer and requests)"
    }
    total_estimated_monthly_cost = "~$2-5 USD"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled on the deployment"
  value = {
    https_only_enabled = azurerm_storage_account.main.https_traffic_only_enabled
    min_tls_version = azurerm_storage_account.main.min_tls_version
    cors_enabled = "Yes - configured for web applications"
    cdn_origin_verification = "Enabled via origin host header"
  }
}

# Next Steps and Recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the static website: ${azurerm_storage_account.main.primary_web_endpoint}",
    "Test the CDN endpoint: https://${azurerm_cdn_endpoint.main.host_name}",
    "Upload your own content to the '$web' container in the storage account",
    "Configure a custom domain for production use",
    "Set up monitoring and alerts for performance tracking",
    "Consider adding Azure Front Door for additional features like WAF"
  ]
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting information"
  value = {
    cdn_propagation_time = "CDN configuration may take 5-10 minutes to fully propagate"
    cache_behavior = "Initial requests may be slower while content is cached at edge locations"
    sample_content_location = var.create_sample_content ? "Sample content uploaded to '$web' container" : "No sample content created - upload your own files"
    monitoring_recommendation = "Use Azure Monitor and CDN analytics to track performance metrics"
  }
}