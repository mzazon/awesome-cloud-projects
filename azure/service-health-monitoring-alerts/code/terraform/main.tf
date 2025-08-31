# Azure Service Health Monitoring with Alerts
# This Terraform configuration creates a comprehensive service health monitoring solution
# including action groups and activity log alert rules for various service health events

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current Azure subscription information
data "azurerm_client_config" "current" {}

# Data source to get current subscription details
data "azurerm_subscription" "current" {}

# Resource Group for Service Health Monitoring Resources
# Contains all monitoring and alerting resources for service health
resource "azurerm_resource_group" "service_health" {
  name     = "${var.resource_group_name}-${random_id.suffix.hex}"
  location = var.location

  tags = merge(var.tags, {
    Environment = var.environment
    CreatedBy   = "terraform"
    Purpose     = "service-health-monitoring"
  })
}

# Action Group for Service Health Notifications
# Defines how alerts are delivered to stakeholders when service health events occur
# Supports multiple notification channels including email, SMS, voice calls, and webhooks
resource "azurerm_monitor_action_group" "service_health_alerts" {
  name                = "ServiceHealthAlerts"
  resource_group_name = azurerm_resource_group.service_health.name
  short_name          = var.action_group_short_name

  # Email notification configuration
  email_receiver {
    name          = "admin-email"
    email_address = var.notification_email
  }

  # SMS notification configuration (only if phone number provided)
  dynamic "sms_receiver" {
    for_each = var.notification_phone != "" ? [1] : []
    content {
      name         = "admin-sms"
      country_code = substr(var.notification_phone, 1, length(split(var.notification_phone, "")[1]) == "1" ? 1 : 2)
      phone_number = substr(var.notification_phone, length(split(var.notification_phone, "")[1]) == "1" ? 2 : 3, -1)
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Component   = "action-group"
  })
}

# Activity Log Alert Rule for Service Issues
# Monitors for unplanned disruptions to Azure services that could impact resources
# Enables immediate awareness of ongoing problems for proactive incident response
resource "azurerm_monitor_activity_log_alert" "service_issues" {
  count               = var.enable_service_issues_alert ? 1 : 0
  name                = "ServiceIssueAlert"
  resource_group_name = azurerm_resource_group.service_health.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for Azure service issues affecting subscription resources"

  criteria {
    category = "ServiceHealth"
    
    # Service Health event criteria for service issues
    service_health {
      events    = ["Incident"]
      locations = ["Global"]  # Monitor all regions
      services  = ["ActivityLogAlerts", "ActionGroups"]  # Monitor core monitoring services
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health_alerts.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    AlertType   = "service-issues"
    Component   = "alert-rule"
  })
}

# Activity Log Alert Rule for Planned Maintenance
# Provides advanced warning of scheduled Azure service updates
# Enables proactive preparation and scheduling of maintenance windows
resource "azurerm_monitor_activity_log_alert" "planned_maintenance" {
  count               = var.enable_planned_maintenance_alert ? 1 : 0
  name                = "PlannedMaintenanceAlert"
  resource_group_name = azurerm_resource_group.service_health.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for planned Azure maintenance events affecting subscription"

  criteria {
    category = "ServiceHealth"
    
    # Service Health event criteria for planned maintenance
    service_health {
      events    = ["Maintenance"]
      locations = ["Global"]  # Monitor all regions
      services  = ["ActivityLogAlerts", "ActionGroups"]  # Monitor core monitoring services
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health_alerts.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    AlertType   = "planned-maintenance"
    Component   = "alert-rule"
  })
}

# Activity Log Alert Rule for Health Advisories
# Communicates important information about potential service impacts
# Provides proactive guidance for maintaining optimal security and performance
resource "azurerm_monitor_activity_log_alert" "health_advisory" {
  count               = var.enable_health_advisory_alert ? 1 : 0
  name                = "HealthAdvisoryAlert"
  resource_group_name = azurerm_resource_group.service_health.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for Azure health advisories and recommendations"

  criteria {
    category = "ServiceHealth"
    
    # Service Health event criteria for health advisories
    service_health {
      events    = ["Informational"]
      locations = ["Global"]  # Monitor all regions
      services  = ["ActivityLogAlerts", "ActionGroups"]  # Monitor core monitoring services
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health_alerts.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    AlertType   = "health-advisory"
    Component   = "alert-rule"
  })
}

# Activity Log Alert Rule for Security Advisories
# Monitors for security-related service health notifications
# Critical for maintaining security posture and compliance requirements
resource "azurerm_monitor_activity_log_alert" "security_advisory" {
  count               = var.enable_security_advisory_alert ? 1 : 0
  name                = "SecurityAdvisoryAlert"
  resource_group_name = azurerm_resource_group.service_health.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert for Azure security advisories and critical security updates"

  criteria {
    category = "ServiceHealth"
    
    # Service Health event criteria for security advisories
    service_health {
      events    = ["Security"]
      locations = ["Global"]  # Monitor all regions
      services  = ["ActivityLogAlerts", "ActionGroups"]  # Monitor core monitoring services
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health_alerts.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    AlertType   = "security-advisory"
    Component   = "alert-rule"
  })
}

# Comprehensive Service Health Alert Rule
# Monitors all service health event types for critical Azure services
# Provides comprehensive coverage while maintaining manageable alert volumes
resource "azurerm_monitor_activity_log_alert" "comprehensive_service_health" {
  name                = "ComprehensiveServiceHealthAlert"
  resource_group_name = azurerm_resource_group.service_health.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Comprehensive monitoring for all service health events affecting critical Azure services"

  criteria {
    category = "ServiceHealth"
    
    # Monitor all service health event types
    service_health {
      events = ["Incident", "Maintenance", "Informational", "ActionRequired", "Security"]
      
      # Monitor all global and regional locations
      locations = ["Global"]
      
      # Monitor critical Azure services that most organizations depend on
      services = [
        "Virtual Machines",
        "Azure Storage",
        "Virtual Network",
        "Azure Active Directory",
        "Azure Monitor",
        "Key Vault",
        "Load Balancer",
        "Application Gateway",
        "Azure SQL Database",
        "App Service",
        "Azure Functions",
        "Container Instances",
        "Kubernetes Service",
        "Cosmos DB"
      ]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.service_health_alerts.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    AlertType   = "comprehensive"
    Component   = "alert-rule"
    Scope       = "critical-services"
  })
}