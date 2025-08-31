# Output values for the Simple Contact Form infrastructure
# These outputs provide essential information for integration and management

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group containing all contact form resources"
  value       = azurerm_resource_group.contact_form.name
}

output "resource_group_location" {
  description = "Azure region where the resource group and all resources are deployed"
  value       = azurerm_resource_group.contact_form.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account used for Function App backend and Table Storage"
  value       = azurerm_storage_account.contact_form.name
}

output "storage_account_id" {
  description = "Full resource ID of the storage account for ARM template references"
  value       = azurerm_storage_account.contact_form.id
}

output "storage_account_primary_endpoint" {
  description = "Primary endpoint URL for the storage account"
  value       = azurerm_storage_account.contact_form.primary_blob_endpoint
}

output "storage_connection_string" {
  description = "Primary connection string for the storage account (sensitive - use with caution)"
  value       = azurerm_storage_account.contact_form.primary_connection_string
  sensitive   = true
}

# Table Storage Information
output "contact_table_name" {
  description = "Name of the Azure Storage Table storing contact form submissions"
  value       = azurerm_storage_table.contacts.name
}

output "contact_table_url" {
  description = "URL endpoint for the contact storage table"
  value       = "${azurerm_storage_account.contact_form.primary_table_endpoint}${azurerm_storage_table.contacts.name}"
}

# Function App Information
output "function_app_name" {
  description = "Name of the Azure Function App processing contact form submissions"
  value       = azurerm_windows_function_app.contact_form.name
}

output "function_app_id" {
  description = "Full resource ID of the Function App for ARM template references"
  value       = azurerm_windows_function_app.contact_form.id
}

output "function_app_default_hostname" {
  description = "Default hostname (FQDN) of the Function App for HTTP requests"
  value       = azurerm_windows_function_app.contact_form.default_hostname
}

output "function_app_url" {
  description = "Complete HTTPS URL of the Function App for web integration"
  value       = "https://${azurerm_windows_function_app.contact_form.default_hostname}"
}

output "function_app_identity_principal_id" {
  description = "Principal ID of the Function App's system-assigned managed identity for role assignments"
  value       = azurerm_windows_function_app.contact_form.identity[0].principal_id
}

# Contact Processing Function Information
output "contact_function_name" {
  description = "Name of the contact processing function within the Function App"
  value       = azurerm_function_app_function.contact_processor.name
}

output "contact_endpoint_url" {
  description = "Complete URL endpoint for submitting contact forms via HTTP POST"
  value       = "https://${azurerm_windows_function_app.contact_form.default_hostname}/api/contact"
}

# Service Plan Information
output "service_plan_name" {
  description = "Name of the App Service Plan hosting the Function App"
  value       = azurerm_service_plan.contact_form.name
}

output "service_plan_sku" {
  description = "SKU name of the App Service Plan (consumption, premium, etc.)"
  value       = azurerm_service_plan.contact_form.sku_name
}

output "service_plan_kind" {
  description = "Kind of App Service Plan indicating the hosting model"
  value       = azurerm_service_plan.contact_form.kind
}

# Application Insights Information (conditional)
output "application_insights_name" {
  description = "Name of Application Insights instance for monitoring (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.contact_form[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key for telemetry (sensitive - if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.contact_form[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for modern SDK integration (sensitive - if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.contact_form[0].connection_string : null
  sensitive   = true
}

output "application_insights_app_id" {
  description = "Application Insights application ID for API access (if enabled)"
  value       = var.enable_application_insights ? azurerm_application_insights.contact_form[0].app_id : null
}

# Security Information
output "function_keys_url" {
  description = "Azure REST API URL to retrieve function keys for authentication"
  value       = "https://management.azure.com${azurerm_windows_function_app.contact_form.id}/functions/${azurerm_function_app_function.contact_processor.name}/listkeys?api-version=2022-03-01"
}

# Cost and Management Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for minimal usage (actual costs may vary based on usage)"
  value       = var.function_app_sku == "Y1" ? "$1-5 for consumption plan + storage costs" : "$20+ for premium plans + storage costs"
}

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resource_group  = "Container for all contact form resources"
    storage_account = "Backend storage for Function App and contact data table"
    contact_table   = "NoSQL storage for contact form submissions"
    function_app    = "Serverless compute for processing HTTP requests"
    service_plan    = "Hosting plan with automatic scaling capabilities"
    app_insights    = var.enable_application_insights ? "Monitoring and logging for observability" : "Not enabled"
    security        = "System-assigned identity with function-level authentication"
  }
}

# Integration Examples
output "curl_test_example" {
  description = "Example curl command to test the contact form endpoint (requires function key)"
  value = <<-EOT
    # First, get the function key from Azure Portal or Azure CLI:
    # az functionapp keys list --name ${azurerm_windows_function_app.contact_form.name} --resource-group ${azurerm_resource_group.contact_form.name}
    
    # Then use this curl command to test:
    curl -X POST "${azurerm_windows_function_app.contact_form.default_hostname}/api/contact?code=YOUR_FUNCTION_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "John Doe",
        "email": "john@example.com",
        "message": "Hello from the contact form!"
      }'
  EOT
}

output "javascript_integration_example" {
  description = "Example JavaScript code for web page integration"
  value = <<-EOT
    // Example fetch request for web page integration
    const submitContactForm = async (formData) => {
      try {
        const response = await fetch('${azurerm_windows_function_app.contact_form.default_hostname}/api/contact?code=YOUR_FUNCTION_KEY', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            name: formData.name,
            email: formData.email,
            message: formData.message
          })
        });
        
        const result = await response.json();
        if (response.ok) {
          console.log('Form submitted successfully:', result);
          return { success: true, data: result };
        } else {
          console.error('Form submission failed:', result);
          return { success: false, error: result.error };
        }
      } catch (error) {
        console.error('Network error:', error);
        return { success: false, error: 'Network error occurred' };
      }
    };
  EOT
}

# Management Commands
output "management_commands" {
  description = "Useful Azure CLI commands for managing the deployed resources"
  value = {
    view_function_logs    = "az webapp log tail --name ${azurerm_windows_function_app.contact_form.name} --resource-group ${azurerm_resource_group.contact_form.name}"
    list_function_keys    = "az functionapp keys list --name ${azurerm_windows_function_app.contact_form.name} --resource-group ${azurerm_resource_group.contact_form.name}"
    query_contact_data    = "az storage entity query --table-name ${azurerm_storage_table.contacts.name} --connection-string '${azurerm_storage_account.contact_form.primary_connection_string}'"
    restart_function_app  = "az functionapp restart --name ${azurerm_windows_function_app.contact_form.name} --resource-group ${azurerm_resource_group.contact_form.name}"
  }
}