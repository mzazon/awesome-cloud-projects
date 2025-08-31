# Azure Cost Budget Tracking Infrastructure
# This Terraform configuration creates a comprehensive cost monitoring solution
# using Azure Cost Management and Azure Monitor services

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for calculated dates and resource naming
locals {
  random_suffix = random_id.suffix.hex
  
  # Calculate budget start date (first day of current month if not provided)
  budget_start_date = var.budget_start_date != null ? var.budget_start_date : formatdate("YYYY-MM-01", timestamp())
  
  # Calculate budget end date (10 years from start date if not provided)
  budget_end_date = var.budget_end_date != null ? var.budget_end_date : formatdate("YYYY-MM-01", timeadd(
    "${local.budget_start_date}T00:00:00Z", 
    "8760h"  # 10 years in hours (365 * 24 * 10)
  ))
  
  # Resource names with unique suffix
  resource_group_name = "${var.resource_group_name}-${local.random_suffix}"
  action_group_name   = "${var.action_group_name}-${local.random_suffix}"
  budget_name         = "${var.budget_name}-${local.random_suffix}"
  filtered_budget_name = "rg-${var.budget_name}-${local.random_suffix}"
}

# Create Resource Group for monitoring resources
resource "azurerm_resource_group" "cost_tracking" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Azure Monitor Action Group for email notifications
# This provides the notification infrastructure for budget alerts
resource "azurerm_monitor_action_group" "cost_alerts" {
  name                = local.action_group_name
  resource_group_name = azurerm_resource_group.cost_tracking.name
  short_name          = var.action_group_short_name
  location            = "global"  # Action groups are global resources
  tags                = var.tags

  # Configure email receivers for budget notifications
  dynamic "email_receiver" {
    for_each = toset(var.email_addresses)
    content {
      name                    = "budget-admin-${md5(email_receiver.value)}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# Create subscription-level cost budget with automated alerting
# This monitors all costs across the entire subscription
resource "azurerm_consumption_budget_subscription" "main_budget" {
  name            = local.budget_name
  subscription_id = data.azurerm_subscription.current.id
  
  # Budget configuration
  amount     = var.budget_amount
  time_grain = var.budget_time_grain
  
  # Budget time period configuration
  time_period {
    start_date = "${local.budget_start_date}T00:00:00Z"
    end_date   = "${local.budget_end_date}T00:00:00Z"
  }
  
  # Configure multiple alert thresholds for progressive warnings
  dynamic "notification" {
    for_each = var.alert_thresholds
    content {
      enabled        = true
      threshold      = notification.value.threshold
      operator       = notification.value.operator
      threshold_type = notification.value.threshold_type
      
      # Email notifications
      contact_emails = var.email_addresses
      
      # Action Group integration for enhanced notification delivery
      contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
      
      # Optional role-based notifications
      contact_roles = var.contact_roles
    }
  }
}

# Create resource group-filtered budget (conditional based on variable)
# This enables targeted cost monitoring for specific resource groups
resource "azurerm_consumption_budget_subscription" "filtered_budget" {
  count           = var.enable_resource_group_filter ? 1 : 0
  name            = local.filtered_budget_name
  subscription_id = data.azurerm_subscription.current.id
  
  # Budget configuration
  amount     = var.budget_amount
  time_grain = var.budget_time_grain
  
  # Budget time period configuration
  time_period {
    start_date = "${local.budget_start_date}T00:00:00Z"
    end_date   = "${local.budget_end_date}T00:00:00Z"
  }
  
  # Filter configuration for specific resource groups
  filter {
    dimension {
      name   = "ResourceGroupName"
      values = length(var.filter_resource_groups) > 0 ? var.filter_resource_groups : [azurerm_resource_group.cost_tracking.name]
    }
  }
  
  # Configure alert thresholds for filtered budget
  dynamic "notification" {
    for_each = var.alert_thresholds
    content {
      enabled        = true
      threshold      = notification.value.threshold
      operator       = notification.value.operator
      threshold_type = notification.value.threshold_type
      
      # Email notifications
      contact_emails = var.email_addresses
      
      # Action Group integration
      contact_groups = [azurerm_monitor_action_group.cost_alerts.id]
      
      # Optional role-based notifications
      contact_roles = var.contact_roles
    }
  }
}