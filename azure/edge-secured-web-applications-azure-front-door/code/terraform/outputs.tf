# outputs.tf
# Output values for Azure Static Web Apps with Front Door WAF deployment

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Static Web App Information
output "static_web_app_name" {
  description = "Name of the Static Web App"
  value       = azurerm_static_web_app.main.name
}

output "static_web_app_default_host_name" {
  description = "Default hostname of the Static Web App"
  value       = azurerm_static_web_app.main.default_host_name
}

output "static_web_app_id" {
  description = "ID of the Static Web App"
  value       = azurerm_static_web_app.main.id
}

output "static_web_app_url" {
  description = "URL of the Static Web App"
  value       = "https://${azurerm_static_web_app.main.default_host_name}"
}

output "static_web_app_api_key" {
  description = "API key for the Static Web App"
  value       = azurerm_static_web_app.main.api_key
  sensitive   = true
}

# Front Door Information
output "front_door_profile_name" {
  description = "Name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.name
}

output "front_door_profile_id" {
  description = "ID of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.id
}

output "front_door_endpoint_hostname" {
  description = "Hostname of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "front_door_endpoint_url" {
  description = "URL of the Front Door endpoint"
  value       = "https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}

output "front_door_endpoint_id" {
  description = "ID of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.id
}

output "front_door_resource_guid" {
  description = "Resource GUID of the Front Door profile (used for Static Web App configuration)"
  value       = azurerm_cdn_frontdoor_profile.main.resource_guid
}

# WAF Policy Information
output "waf_policy_name" {
  description = "Name of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.name
}

output "waf_policy_id" {
  description = "ID of the WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.id
}

output "waf_policy_mode" {
  description = "Mode of the WAF policy (Detection or Prevention)"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.mode
}

output "waf_policy_enabled" {
  description = "Whether the WAF policy is enabled"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.enabled
}

# Origin Group Information
output "origin_group_name" {
  description = "Name of the origin group"
  value       = azurerm_cdn_frontdoor_origin_group.main.name
}

output "origin_group_id" {
  description = "ID of the origin group"
  value       = azurerm_cdn_frontdoor_origin_group.main.id
}

# Security Configuration
output "security_policy_id" {
  description = "ID of the security policy"
  value       = azurerm_cdn_frontdoor_security_policy.main.id
}

# Rule Sets Information
output "caching_rule_set_id" {
  description = "ID of the caching rule set"
  value       = azurerm_cdn_frontdoor_rule_set.caching.id
}

output "compression_rule_set_id" {
  description = "ID of the compression rule set"
  value       = azurerm_cdn_frontdoor_rule_set.compression.id
}

# Log Analytics Workspace (if created)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if created)"
  value       = var.enable_diagnostic_logs && var.log_analytics_workspace_name == null ? azurerm_log_analytics_workspace.main[0].name : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value = var.enable_diagnostic_logs ? (
    var.log_analytics_workspace_name != null ? 
    data.azurerm_log_analytics_workspace.existing[0].id : 
    azurerm_log_analytics_workspace.main[0].id
  ) : null
}

# Configuration Information
output "static_web_app_config_json" {
  description = "Configuration JSON for Static Web App integration with Front Door"
  value       = jsonencode(local.static_web_app_config)
}

# Rate Limiting Configuration
output "rate_limit_threshold" {
  description = "Configured rate limit threshold (requests per minute per IP)"
  value       = var.rate_limit_threshold
}

output "allowed_countries" {
  description = "List of allowed countries for geo-filtering"
  value       = var.allowed_countries
}

# Cache Configuration
output "static_cache_duration" {
  description = "Cache duration configured for static assets"
  value       = var.static_cache_duration
}

# Random Suffix for Reference
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    test_front_door_endpoint = "curl -I https://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
    test_waf_sql_injection   = "curl -X GET 'https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/?id=1%27%20OR%20%271%27=%271'"
    test_waf_xss            = "curl -X GET 'https://${azurerm_cdn_frontdoor_endpoint.main.host_name}/?search=%3Cscript%3Ealert(%27xss%27)%3C/script%3E'"
    test_rate_limiting      = "for i in {1..150}; do curl -s -o /dev/null -w '%{http_code}\\n' https://${azurerm_cdn_frontdoor_endpoint.main.host_name}; done | sort | uniq -c"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Deploy the staticwebapp.config.json file to your Static Web App repository root",
    "2. Configure your GitHub repository for automated deployments",
    "3. Test WAF protection using the verification commands",
    "4. Configure custom domain and SSL certificate if needed",
    "5. Review WAF logs in Azure Monitor for security events",
    "6. Set up alerts for security incidents and performance monitoring"
  ]
}

# Important Security Notes
output "security_notes" {
  description = "Important security considerations"
  value = [
    "WAF is configured in ${var.waf_mode} mode - ensure this meets your security requirements",
    "Rate limiting is set to ${var.rate_limit_threshold} requests per minute per IP",
    "Geo-filtering allows only these countries: ${join(", ", var.allowed_countries)}",
    "HTTPS redirect is ${var.enable_https_redirect ? "enabled" : "disabled"}",
    "Static Web App API key is sensitive - store securely",
    "Review and customize WAF rules based on your application requirements"
  ]
}