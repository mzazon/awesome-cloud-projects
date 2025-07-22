# Terraform Infrastructure for Intelligent Database Scaling

This directory contains Terraform infrastructure as code for deploying an intelligent database scaling solution using Azure SQL Database Hyperscale and Logic Apps.

## Architecture Overview

The solution creates:

- **Azure SQL Database Hyperscale** - High-performance database with autonomous scaling capabilities
- **Azure Logic Apps** - Serverless workflow orchestration for scaling automation
- **Azure Monitor** - Real-time performance monitoring and alerting
- **Azure Key Vault** - Secure credential and configuration management
- **Azure Log Analytics** - Centralized logging and monitoring workspace

## Prerequisites

1. **Azure CLI** - Install and configure Azure CLI
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Terraform** - Install Terraform >= 1.5.0
   ```bash
   # Download from https://terraform.io/downloads
   terraform --version
   ```

3. **Azure Permissions** - Ensure you have:
   - Contributor access to the target subscription
   - User Access Administrator (for role assignments)
   - Key Vault Administrator (for Key Vault operations)

## Quick Start

1. **Clone and Navigate**
   ```bash
   git clone <repository-url>
   cd azure/intelligent-database-scaling/code/terraform
   ```

2. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Plan Deployment**
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**
   ```bash
   terraform apply
   ```

## Configuration

### Required Variables

Edit `terraform.tfvars` to set these essential variables:

```hcl
# Basic Configuration
location           = "East US"
environment        = "dev"
project_name       = "intelligent-scaling"

# Alert Recipients
alert_email_recipients = [
  "admin@yourcompany.com"
]
```

### Key Configuration Options

#### Database Configuration
- `sql_database_initial_sku`: Starting SKU (e.g., "HS_Gen5_2")
- `max_vcores`: Maximum vCores for scaling (default: 40)
- `min_vcores`: Minimum vCores to maintain (default: 2)
- `scaling_step_size`: vCores to add/remove per scaling operation

#### Scaling Thresholds
- `cpu_scale_up_threshold`: CPU % to trigger scale-up (default: 80%)
- `cpu_scale_down_threshold`: CPU % to trigger scale-down (default: 30%)
- `scale_up_evaluation_window_minutes`: Time window for scale-up evaluation
- `scale_down_evaluation_window_minutes`: Time window for scale-down evaluation

#### Security Settings
- `sql_server_public_access_enabled`: Allow public access to SQL Server
- `allowed_ip_ranges`: List of IP ranges for SQL Server access
- `enable_key_vault_rbac`: Use RBAC for Key Vault access

## Deployment Process

### 1. Infrastructure Creation

The deployment creates resources in this order:

1. **Resource Group** - Container for all resources
2. **Storage Account** - Required for Logic Apps and diagnostics
3. **Key Vault** - Secure credential storage
4. **Log Analytics Workspace** - Centralized monitoring
5. **SQL Server and Database** - Hyperscale database
6. **Logic Apps Workflow** - Scaling automation
7. **Monitor Alerts** - CPU-based scaling triggers
8. **Role Assignments** - Managed identity permissions

### 2. Automatic Configuration

The deployment automatically:

- Generates secure passwords if not provided
- Creates unique resource names with random suffixes
- Configures managed identities and role assignments
- Sets up monitoring and alerting
- Establishes scaling automation workflows

### 3. Validation

After deployment, verify:

```bash
# Check deployment status
terraform show

# Verify database is online
az sql db show --resource-group <rg-name> --server <server-name> --name <db-name>

# Check Logic App status
az logic workflow show --resource-group <rg-name> --name <logic-app-name>
```

## Monitoring and Troubleshooting

### Key Outputs

The deployment provides these important outputs:

- `sql_server_fqdn`: Database connection endpoint
- `logic_app_callback_url`: HTTP trigger URL for scaling
- `azure_portal_links`: Direct links to resources
- `troubleshooting_info`: Debugging information

### Monitoring Resources

- **Azure Portal**: Monitor all resources from the resource group
- **Log Analytics**: Query scaling operation logs
- **Application Insights**: Logic Apps performance monitoring
- **SQL Database Metrics**: Real-time performance data

### Common Issues

1. **Permission Errors**
   - Ensure managed identity has required role assignments
   - Check Key Vault access policies or RBAC permissions

2. **Scaling Not Triggered**
   - Verify alert rules are enabled
   - Check Logic App webhook URL in action groups
   - Review CPU metrics in Azure Monitor

3. **Database Connection Issues**
   - Verify firewall rules allow your IP
   - Check SQL Server public access settings
   - Ensure credentials are correct in Key Vault

## Cost Management

### Cost Factors

- **SQL Database Hyperscale**: Major cost component (scales with vCores)
- **Logic Apps**: Consumption-based pricing per execution
- **Log Analytics**: Data ingestion and retention costs
- **Storage**: Minimal cost for diagnostics and backups

### Cost Optimization

1. **Set Appropriate Limits**
   ```hcl
   max_vcores = 16  # Limit maximum scaling
   monthly_budget_limit = 200  # Set cost alerts
   ```

2. **Adjust Retention Periods**
   ```hcl
   log_analytics_retention_days = 30  # Reduce for lower costs
   backup_retention_days = 7  # Minimum retention
   ```

3. **Monitor Usage**
   - Enable cost alerts in terraform.tfvars
   - Review monthly spending in Azure Cost Management
   - Set up budget alerts for cost control

## Security Best Practices

### Network Security
- Configure IP allowlists for SQL Server access
- Use private endpoints for production deployments
- Enable Azure Firewall for additional protection

### Identity and Access
- Use managed identities for service authentication
- Implement principle of least privilege
- Enable Key Vault audit logging

### Data Protection
- Enable Transparent Data Encryption (TDE)
- Configure backup retention policies
- Use Azure AD authentication for SQL access

## Customization

### Adding Custom Metrics

Extend the solution with additional scaling metrics:

```hcl
# Add memory-based scaling alert
resource "azurerm_monitor_metric_alert" "memory_scale_up" {
  name = "memory-scale-up-alert"
  # ... configuration
}
```

### Multi-Region Deployment

For high availability across regions:

```hcl
# Additional variables for multi-region
variable "secondary_location" {
  description = "Secondary Azure region"
  type        = string
  default     = "West US"
}
```

### Integration with Existing Infrastructure

Connect to existing resources:

```hcl
# Use existing Log Analytics workspace
data "azurerm_log_analytics_workspace" "existing" {
  name                = "existing-workspace"
  resource_group_name = "existing-rg"
}
```

## Cleanup

To remove all resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

**Note**: This will permanently delete all resources and data. Ensure you have backups of any important data before running destroy.

## Support

For issues with this Terraform deployment:

1. Check the [troubleshooting outputs](#monitoring-and-troubleshooting)
2. Review Azure portal for resource status
3. Check Terraform state file for resource information
4. Consult Azure documentation for service-specific issues

## Contributing

To improve this infrastructure:

1. Follow Terraform best practices
2. Update variable validation rules
3. Add comprehensive comments
4. Test changes in development environments
5. Update documentation for new features