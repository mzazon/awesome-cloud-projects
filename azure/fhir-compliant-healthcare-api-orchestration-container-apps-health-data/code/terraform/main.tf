# Main Terraform configuration for FHIR-compliant healthcare API orchestration
# This configuration deploys a complete healthcare API platform with:
# - Azure Health Data Services with FHIR R4 support
# - Container Apps for microservices architecture
# - API Management for gateway and security
# - Communication Services for real-time notifications
# - Comprehensive monitoring and logging

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
  numeric = true
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Create resource group for healthcare resources
resource "azurerm_resource_group" "healthcare" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    "Data-Classification" = "phi"
    "Purpose"            = "fhir-orchestration"
  })
}

# Create Log Analytics workspace for healthcare monitoring and compliance
resource "azurerm_log_analytics_workspace" "healthcare" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.healthcare.location
  resource_group_name = azurerm_resource_group.healthcare.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  tags = merge(var.tags, {
    "Service" = "monitoring"
  })
}

# Create Application Insights for healthcare application monitoring
resource "azurerm_application_insights" "healthcare" {
  name                = "${var.application_insights_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.healthcare.location
  resource_group_name = azurerm_resource_group.healthcare.name
  workspace_id        = azurerm_log_analytics_workspace.healthcare.id
  application_type    = var.application_insights_type

  tags = merge(var.tags, {
    "Service" = "monitoring"
  })
}

# Create Azure Health Data Services workspace
# This provides the foundation for FHIR-compliant healthcare data management
resource "azurerm_healthcare_workspace" "main" {
  name                = "${var.health_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.healthcare.location
  resource_group_name = azurerm_resource_group.healthcare.name

  tags = merge(var.tags, {
    "Service"             = "healthcare-apis"
    "Compliance"          = "hipaa-hitrust"
    "Data-Classification" = "phi"
  })
}

# Create FHIR service with R4 support and SMART on FHIR authentication
resource "azurerm_healthcare_fhir_service" "main" {
  name                = "${var.fhir_service_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.healthcare.location
  resource_group_name = azurerm_resource_group.healthcare.name
  workspace_id        = azurerm_healthcare_workspace.main.id
  kind                = var.fhir_version

  # Configure authentication with Azure AD and SMART on FHIR
  authentication {
    authority = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}"
    audience  = "https://${var.health_workspace_name}-${random_string.suffix.result}-${var.fhir_service_name}-${random_string.suffix.result}.fhir.azurehealthcareapis.com"
    smart_proxy_enabled = var.enable_smart_proxy
  }

  # Configure CORS for healthcare applications
  cors {
    allowed_origins     = ["https://localhost:3000", "https://localhost:8080"]
    allowed_headers     = ["*"]
    allowed_methods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    max_age_in_seconds  = 3600
    allow_credentials   = true
  }

  tags = merge(var.tags, {
    "Service" = "fhir-service"
  })
}

# Create Container Apps environment for microservices
resource "azurerm_container_app_environment" "healthcare" {
  name                       = "${var.container_environment_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.healthcare.location
  resource_group_name        = azurerm_resource_group.healthcare.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.healthcare.id

  tags = merge(var.tags, {
    "Service" = "container-apps"
  })
}

# Patient Management Microservice
# Handles FHIR Patient resources and related operations
resource "azurerm_container_app" "patient_service" {
  name                         = "patient-service"
  container_app_environment_id = azurerm_container_app_environment.healthcare.id
  resource_group_name          = azurerm_resource_group.healthcare.name
  revision_mode                = "Single"

  template {
    container {
      name   = "patient-service"
      image  = var.patient_service_config.image
      cpu    = var.patient_service_config.cpu
      memory = var.patient_service_config.memory

      env {
        name  = "FHIR_ENDPOINT"
        value = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = data.azurerm_client_config.current.client_id
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = data.azurerm_client_config.current.tenant_id
      }

      env {
        name  = "SERVICE_NAME"
        value = "patient-service"
      }

      env {
        name  = "COMPLIANCE_MODE"
        value = "hipaa"
      }

      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
    }

    min_replicas = var.patient_service_config.min_replicas
    max_replicas = var.patient_service_config.max_replicas
  }

  ingress {
    allow_insecure_connections = false
    external_enabled          = var.patient_service_config.ingress_external
    target_port               = var.patient_service_config.target_port

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = merge(var.tags, {
    "Service"   = "patient-management"
    "Workload"  = "microservice"
  })
}

# Provider Notification Service
# Manages healthcare provider communications and alerts
resource "azurerm_container_app" "provider_notification_service" {
  name                         = "provider-notification-service"
  container_app_environment_id = azurerm_container_app_environment.healthcare.id
  resource_group_name          = azurerm_resource_group.healthcare.name
  revision_mode                = "Single"

  template {
    container {
      name   = "provider-notification-service"
      image  = var.provider_notification_config.image
      cpu    = var.provider_notification_config.cpu
      memory = var.provider_notification_config.memory

      env {
        name  = "FHIR_ENDPOINT"
        value = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
      }

      env {
        name  = "COMM_CONNECTION_STRING"
        value = azurerm_communication_service.healthcare.primary_connection_string
      }

      env {
        name  = "SERVICE_NAME"
        value = "provider-notification"
      }

      env {
        name  = "NOTIFICATION_MODE"
        value = "realtime"
      }

      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
    }

    min_replicas = var.provider_notification_config.min_replicas
    max_replicas = var.provider_notification_config.max_replicas
  }

  ingress {
    allow_insecure_connections = false
    external_enabled          = var.provider_notification_config.ingress_external
    target_port               = var.provider_notification_config.target_port

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = merge(var.tags, {
    "Service"   = "provider-notification"
    "Workload"  = "microservice"
  })
}

# Workflow Orchestration Service
# Coordinates complex healthcare processes and workflows
resource "azurerm_container_app" "workflow_orchestration_service" {
  name                         = "workflow-orchestration-service"
  container_app_environment_id = azurerm_container_app_environment.healthcare.id
  resource_group_name          = azurerm_resource_group.healthcare.name
  revision_mode                = "Single"

  template {
    container {
      name   = "workflow-orchestration-service"
      image  = var.workflow_orchestration_config.image
      cpu    = var.workflow_orchestration_config.cpu
      memory = var.workflow_orchestration_config.memory

      env {
        name  = "FHIR_ENDPOINT"
        value = "https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com"
      }

      env {
        name  = "COMM_CONNECTION_STRING"
        value = azurerm_communication_service.healthcare.primary_connection_string
      }

      env {
        name  = "SERVICE_NAME"
        value = "workflow-orchestration"
      }

      env {
        name  = "WORKFLOW_ENGINE"
        value = "healthcare"
      }

      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
    }

    min_replicas = var.workflow_orchestration_config.min_replicas
    max_replicas = var.workflow_orchestration_config.max_replicas
  }

  ingress {
    allow_insecure_connections = false
    external_enabled          = var.workflow_orchestration_config.ingress_external
    target_port               = var.workflow_orchestration_config.target_port

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = merge(var.tags, {
    "Service"   = "workflow-orchestration"
    "Workload"  = "microservice"
  })
}

# Azure Communication Services for real-time healthcare communications
resource "azurerm_communication_service" "healthcare" {
  name                = "${var.communication_service_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.healthcare.name
  data_location       = var.communication_data_location

  tags = merge(var.tags, {
    "Service"    = "healthcare-notifications"
    "Compliance" = "hipaa"
  })
}

# API Management instance for healthcare API gateway
resource "azurerm_api_management" "healthcare" {
  name                = "${var.api_management_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.healthcare.location
  resource_group_name = azurerm_resource_group.healthcare.name
  publisher_name      = var.organization_name
  publisher_email     = var.admin_email
  sku_name            = "${var.api_management_sku}_${var.api_management_capacity}"

  # Configure identity for healthcare compliance
  identity {
    type = "SystemAssigned"
  }

  # Configure security policies
  security {
    enable_backend_ssl30                                = false
    enable_backend_tls10                                = false
    enable_backend_tls11                                = false
    enable_frontend_ssl30                               = false
    enable_frontend_tls10                               = false
    enable_frontend_tls11                               = false
    tls_ecdhe_ecdsa_with_aes128_cbc_sha_ciphers_enabled = false
    tls_ecdhe_ecdsa_with_aes256_cbc_sha_ciphers_enabled = false
    tls_ecdhe_rsa_with_aes128_cbc_sha_ciphers_enabled   = false
    tls_ecdhe_rsa_with_aes256_cbc_sha_ciphers_enabled   = false
    tls_rsa_with_aes128_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes128_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_aes256_cbc_sha256_ciphers_enabled      = false
    tls_rsa_with_aes256_cbc_sha_ciphers_enabled         = false
    tls_rsa_with_3des_ede_cbc_sha_ciphers_enabled       = false
    triple_des_ciphers_enabled                          = false
  }

  tags = merge(var.tags, {
    "Service"    = "healthcare-api-gateway"
    "Compliance" = "hipaa-hitrust"
  })
}

# API Management Logger for healthcare audit trails
resource "azurerm_api_management_logger" "healthcare" {
  name                = "healthcare-logger"
  api_management_name = azurerm_api_management.healthcare.name
  resource_group_name = azurerm_resource_group.healthcare.name
  resource_id         = azurerm_application_insights.healthcare.id

  application_insights {
    instrumentation_key = azurerm_application_insights.healthcare.instrumentation_key
  }
}

# API Management API for Patient Service
resource "azurerm_api_management_api" "patient_api" {
  name                = "patient-api"
  resource_group_name = azurerm_resource_group.healthcare.name
  api_management_name = azurerm_api_management.healthcare.name
  revision            = "1"
  display_name        = "Patient Management API"
  path                = "patient"
  protocols           = ["https"]
  service_url         = "https://${azurerm_container_app.patient_service.latest_revision_fqdn}"

  description = "FHIR-compliant patient management API for healthcare applications"

  subscription_required = true
  
  import {
    content_format = "swagger-json"
    content_value  = jsonencode({
      swagger = "2.0"
      info = {
        title   = "Patient Management API"
        version = "1.0"
      }
      paths = {
        "/Patient" = {
          get = {
            summary = "Get patients"
            responses = {
              "200" = {
                description = "Success"
              }
            }
          }
          post = {
            summary = "Create patient"
            responses = {
              "201" = {
                description = "Created"
              }
            }
          }
        }
      }
    })
  }
}

# API Management API for Provider Notification Service
resource "azurerm_api_management_api" "provider_notification_api" {
  name                = "provider-notification-api"
  resource_group_name = azurerm_resource_group.healthcare.name
  api_management_name = azurerm_api_management.healthcare.name
  revision            = "1"
  display_name        = "Provider Notification API"
  path                = "notifications"
  protocols           = ["https"]
  service_url         = "https://${azurerm_container_app.provider_notification_service.latest_revision_fqdn}"

  description = "Real-time healthcare provider notification API"

  subscription_required = true
  
  import {
    content_format = "swagger-json"
    content_value  = jsonencode({
      swagger = "2.0"
      info = {
        title   = "Provider Notification API"
        version = "1.0"
      }
      paths = {
        "/notifications" = {
          post = {
            summary = "Send notification"
            responses = {
              "200" = {
                description = "Success"
              }
            }
          }
        }
      }
    })
  }
}

# API Management API for Workflow Orchestration Service
resource "azurerm_api_management_api" "workflow_api" {
  name                = "workflow-api"
  resource_group_name = azurerm_resource_group.healthcare.name
  api_management_name = azurerm_api_management.healthcare.name
  revision            = "1"
  display_name        = "Workflow Orchestration API"
  path                = "workflows"
  protocols           = ["https"]
  service_url         = "https://${azurerm_container_app.workflow_orchestration_service.latest_revision_fqdn}"

  description = "Healthcare workflow orchestration and automation API"

  subscription_required = true
  
  import {
    content_format = "swagger-json"
    content_value  = jsonencode({
      swagger = "2.0"
      info = {
        title   = "Workflow Orchestration API"
        version = "1.0"
      }
      paths = {
        "/workflows" = {
          get = {
            summary = "Get workflows"
            responses = {
              "200" = {
                description = "Success"
              }
            }
          }
          post = {
            summary = "Create workflow"
            responses = {
              "201" = {
                description = "Created"
              }
            }
          }
        }
      }
    })
  }
}

# API Management Policy for healthcare compliance and security
resource "azurerm_api_management_api_policy" "healthcare_policy" {
  api_name            = azurerm_api_management_api.patient_api.name
  api_management_name = azurerm_api_management.healthcare.name
  resource_group_name = azurerm_resource_group.healthcare.name

  xml_content = <<XML
<policies>
  <inbound>
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Access token is missing or invalid.">
      <openid-config url="https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/.well-known/openid-configuration" />
      <required-claims>
        <claim name="aud">
          <value>https://${azurerm_healthcare_fhir_service.main.name}.fhir.azurehealthcareapis.com</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <rate-limit calls="300" renewal-period="60" />
    <quota calls="5000" renewal-period="86400" />
    <set-header name="X-Request-ID" exists-action="override">
      <value>@(Guid.NewGuid().ToString())</value>
    </set-header>
    <log-to-eventhub logger-id="healthcare-logger" partition-id="1">
      @{
        return new JObject(
          new JProperty("timestamp", DateTime.UtcNow.ToString()),
          new JProperty("request-id", context.Variables["X-Request-ID"]),
          new JProperty("client-ip", context.Request.IpAddress),
          new JProperty("method", context.Request.Method),
          new JProperty("url", context.Request.Url.ToString()),
          new JProperty("user-agent", context.Request.Headers.GetValueOrDefault("User-Agent","")),
          new JProperty("compliance", "hipaa-audit")
        ).ToString();
      }
    </log-to-eventhub>
  </inbound>
  <backend>
    <forward-request />
  </backend>
  <outbound>
    <set-header name="X-Response-ID" exists-action="override">
      <value>@(context.Variables["X-Request-ID"])</value>
    </set-header>
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
  <on-error>
    <log-to-eventhub logger-id="healthcare-logger" partition-id="1">
      @{
        return new JObject(
          new JProperty("timestamp", DateTime.UtcNow.ToString()),
          new JProperty("request-id", context.Variables["X-Request-ID"]),
          new JProperty("error", context.LastError.Message),
          new JProperty("status-code", context.Response.StatusCode),
          new JProperty("compliance", "hipaa-audit-error")
        ).ToString();
      }
    </log-to-eventhub>
  </on-error>
</policies>
XML
}

# Diagnostic settings for healthcare compliance and audit
resource "azurerm_monitor_diagnostic_setting" "healthcare_workspace" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "healthcare-workspace-diagnostics"
  target_resource_id         = azurerm_healthcare_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.healthcare.id

  enabled_log {
    category = "AuditLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "fhir_service" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "fhir-service-diagnostics"
  target_resource_id         = azurerm_healthcare_fhir_service.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.healthcare.id

  enabled_log {
    category = "AuditLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "api_management" {
  count                      = var.enable_diagnostic_logs ? 1 : 0
  name                       = "api-management-diagnostics"
  target_resource_id         = azurerm_api_management.healthcare.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.healthcare.id

  enabled_log {
    category = "GatewayLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}