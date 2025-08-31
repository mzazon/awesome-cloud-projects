# Infrastructure as Code for Basic Database Web App with SQL Database and App Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Database Web App with SQL Database and App Service".

## Overview

This solution demonstrates deploying a fully managed web application stack on Azure using Platform-as-a-Service offerings. The architecture includes:

- **Azure SQL Database**: Managed relational database with enterprise-grade security and performance
- **Azure App Service**: Fully managed web hosting platform with built-in scaling and security
- **System-Assigned Managed Identity**: Secure authentication mechanism eliminating hardcoded credentials
- **Firewall Configuration**: Network security controls for database access

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

### Common Requirements
- Azure account with appropriate permissions for creating resources
- Azure CLI installed and configured (version 2.37.0 or later)
- Basic understanding of web applications and database concepts

### Tool-Specific Requirements

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell or Bash environment

#### For Terraform
- Terraform CLI installed (version 1.0 or later)
- Azure CLI authenticated with appropriate subscription access

#### For Bash Scripts
- Bash shell environment (Linux, macOS, or WSL on Windows)
- OpenSSL installed for generating random values

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters sqlAdminPassword='SecurePass123!' \
                 location='eastus'

# Get deployment outputs
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="sql_admin_password=SecurePass123!" \
               -var="location=eastus"

# Apply the configuration
terraform apply -var="sql_admin_password=SecurePass123!" \
                -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# or you can set environment variables:
export LOCATION="eastus"
export SQL_ADMIN_PASSWORD="SecurePass123!"
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `location` | Azure region for resource deployment | `eastus` |
| `sqlAdminPassword` | Password for SQL Server admin account | `SecurePass123!` |

### Optional Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `resourceGroupName` | Name of the resource group | `rg-webapp-demo-${random}` | `my-webapp-rg` |
| `sqlServerName` | Name of the SQL Server | `sql-server-${random}` | `my-sql-server` |
| `databaseName` | Name of the SQL Database | `TasksDB` | `MyAppDB` |
| `appServicePlanName` | Name of the App Service Plan | `asp-webapp-${random}` | `my-app-plan` |
| `webAppName` | Name of the Web App | `webapp-demo-${random}` | `my-web-app` |
| `sqlServerSku` | SQL Database service tier | `Basic` | `Standard` |
| `appServiceSku` | App Service Plan SKU | `B1` | `S1` |

## Architecture Details

The deployed infrastructure includes:

1. **Resource Group**: Container for all related resources
2. **Azure SQL Database Server**: Logical server for database management
3. **Azure SQL Database**: Managed database with sample schema
4. **Firewall Rules**: Allow Azure services to access the database
5. **App Service Plan**: Compute resources for the web application
6. **Web App**: Hosting environment with managed identity enabled
7. **Connection String**: Secure database connection configuration

## Security Features

- **Managed Identity**: Eliminates need for hardcoded credentials
- **SQL Database Firewall**: Restricts access to Azure services only
- **Encrypted Connections**: All database connections use TLS encryption
- **Secure Configuration**: Sensitive values stored in Azure configuration

## Cost Considerations

The default configuration uses cost-optimized tiers:

- **SQL Database**: Basic tier (~$5/month)
- **App Service Plan**: B1 tier (~$13/month)
- **Total Estimated Cost**: ~$18/month

> **Note**: Costs may vary by region and actual usage. Consider deleting resources after testing to avoid ongoing charges.

## Validation & Testing

After deployment, verify the solution:

1. **Check Web App Status**:
   ```bash
   # Using Azure CLI
   az webapp show --name <webapp-name> --resource-group <resource-group> \
                  --query state --output tsv
   
   # Expected output: Running
   ```

2. **Test Database Connection**:
   ```bash
   # Query the sample data
   az sql query --server <sql-server-name> \
                --database <database-name> \
                --auth-type SqlPassword \
                --username sqladmin \
                --password '<password>' \
                --query "SELECT COUNT(*) as TaskCount FROM Tasks;"
   ```

3. **Access Web Application**:
   ```bash
   # Get the web app URL
   az webapp show --name <webapp-name> --resource-group <resource-group> \
                  --query defaultHostName --output tsv
   
   # Visit https://<returned-hostname> in your browser
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name <resource-group-name> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="sql_admin_password=SecurePass123!" \
                  -var="location=eastus"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# This will prompt for confirmation before deleting resources
```

## Customization Examples

### Scaling Configuration

To deploy with higher performance tiers:

```bash
# Bicep
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters sqlServerSku='S1' \
                 appServiceSku='S1' \
                 sqlAdminPassword='SecurePass123!'

# Terraform
terraform apply -var="sql_server_sku=S1" \
                -var="app_service_sku=S1" \
                -var="sql_admin_password=SecurePass123!"
```

### Multi-Environment Deployment

```bash
# Development environment
terraform apply -var="environment=dev" \
                -var="sql_server_sku=Basic" \
                -var="app_service_sku=B1"

# Production environment
terraform apply -var="environment=prod" \
                -var="sql_server_sku=S2" \
                -var="app_service_sku=P1v2"
```

## Troubleshooting

### Common Issues

1. **SQL Server Name Already Exists**:
   - SQL Server names must be globally unique
   - The templates include random suffixes to avoid conflicts
   - If deployment fails, try again or specify a custom name

2. **Insufficient Permissions**:
   - Ensure your account has Contributor access to the subscription
   - Required permissions: create resources, assign roles, manage networking

3. **Password Policy Violations**:
   - SQL password must be at least 8 characters
   - Must contain characters from at least 3 categories: uppercase, lowercase, numbers, symbols

4. **Region Availability**:
   - Ensure all services are available in your chosen region
   - Some older regions may not support the latest service tiers

### Deployment Logs

For Bicep and Terraform deployments, check logs:

```bash
# Bicep deployment logs
az deployment group show --resource-group <rg-name> --name main

# Terraform detailed logs
export TF_LOG=DEBUG
terraform apply
```

## Next Steps

After successful deployment, consider these enhancements:

1. **Enable Application Insights**: Add monitoring and analytics
2. **Configure Custom Domains**: Set up production DNS and SSL certificates
3. **Implement CI/CD**: Automate deployments with Azure DevOps or GitHub Actions
4. **Add Azure Key Vault**: Secure secrets management
5. **Configure Auto-scaling**: Handle traffic spikes automatically

## Support

- For infrastructure deployment issues, check the Azure Activity Log in the portal
- For application-specific problems, refer to the original recipe documentation
- For Azure service questions, consult the [Azure documentation](https://docs.microsoft.com/azure/)

## Version History

- **v1.0**: Initial implementation with basic web app and database
- **v1.1**: Added managed identity and improved security configuration

---

*This infrastructure code was generated from the Azure recipe "Basic Database Web App with SQL Database and App Service" following Azure best practices and security guidelines.*