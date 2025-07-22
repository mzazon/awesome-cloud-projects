# Infrastructure as Code for Global Web Application Performance Acceleration with Redis Cache and CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global Web Application Performance Acceleration with Redis Cache and CDN".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Terraform installed (if using Terraform implementation)
- Appropriate permissions for resource creation:
  - Contributor role on subscription or resource group
  - User Access Administrator (for role assignments)

## Quick Start

### Using Bicep (Recommended)
```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-webapp-perf \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters appName=webapp-perf-demo
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This IaC deploys a high-performance web application architecture including:

- **Azure App Service**: Hosts the web application with auto-scaling capabilities
- **Azure Cache for Redis**: Provides sub-millisecond caching for database queries
- **Azure CDN**: Delivers static content from global edge locations
- **Azure Database for PostgreSQL**: Stores application data with high availability
- **Application Insights**: Monitors performance and provides analytics
- **Custom caching rules**: Optimizes content delivery based on content type

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `appName` | Unique application name prefix | `webapp-perf` | Yes |
| `environment` | Environment tag (dev/staging/prod) | `dev` | No |
| `appServicePlanSku` | App Service plan SKU | `S1` | No |
| `redisCacheSku` | Redis cache SKU | `Standard` | No |
| `redisCapacity` | Redis cache capacity (0-6) | `1` | No |
| `postgresqlSku` | PostgreSQL server SKU | `Standard_B1ms` | No |
| `cdnSku` | CDN profile SKU | `Standard_Microsoft` | No |

### Terraform Variables

| Variable | Description | Default Value | Required |
|----------|-------------|---------------|----------|
| `resource_group_name` | Resource group name | `rg-webapp-perf` | Yes |
| `location` | Azure region | `East US` | Yes |
| `app_name` | Application name prefix | `webapp-perf` | Yes |
| `environment` | Environment tag | `dev` | No |
| `app_service_plan_sku` | App Service plan size | `S1` | No |
| `redis_cache_capacity` | Redis cache capacity | `1` | No |
| `postgresql_administrator_login` | Database admin username | `dbadmin` | No |
| `postgresql_administrator_password` | Database admin password | Generated | No |

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Create resource group (if not exists)
az group create \
    --name rg-webapp-perf \
    --location eastus

# Set default resource group (optional)
az configure --defaults group=rg-webapp-perf
```

### 2. Deploy Infrastructure

#### Using Bicep
```bash
# Validate the template
az deployment group validate \
    --resource-group rg-webapp-perf \
    --template-file bicep/main.bicep \
    --parameters appName=myapp

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-webapp-perf \
    --template-file bicep/main.bicep \
    --parameters appName=myapp \
    --parameters location=eastus
```

#### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Plan the deployment
terraform plan -var="app_name=myapp" -var="location=East US"

# Apply the configuration
terraform apply -var="app_name=myapp" -var="location=East US"
```

### 3. Deploy Application Code

After infrastructure deployment, deploy the sample application:

```bash
# Clone or prepare your application code
mkdir webapp-sample && cd webapp-sample

# Create package.json and application files
# (See recipe for complete application code)

# Deploy to Azure App Service
az webapp deployment source config-zip \
    --resource-group rg-webapp-perf \
    --name webapp-myapp \
    --src webapp-sample.zip
```

### 4. Configure Application Settings

```bash
# Get Redis connection details
REDIS_HOSTNAME=$(az redis show \
    --resource-group rg-webapp-perf \
    --name cache-myapp \
    --query hostName --output tsv)

REDIS_KEY=$(az redis list-keys \
    --resource-group rg-webapp-perf \
    --name cache-myapp \
    --query primaryKey --output tsv)

# Configure application settings
az webapp config appsettings set \
    --resource-group rg-webapp-perf \
    --name webapp-myapp \
    --settings \
    REDIS_HOSTNAME=${REDIS_HOSTNAME} \
    REDIS_KEY=${REDIS_KEY} \
    REDIS_PORT=6380 \
    REDIS_SSL=true
```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check resource group resources
az resource list \
    --resource-group rg-webapp-perf \
    --output table

# Test Redis connectivity
az redis ping \
    --resource-group rg-webapp-perf \
    --name cache-myapp

# Check CDN endpoint status
az cdn endpoint show \
    --resource-group rg-webapp-perf \
    --profile-name cdn-profile-myapp \
    --name cdn-myapp
```

### 2. Test Application Performance

```bash
# Get application and CDN URLs
WEB_APP_URL=$(az webapp show \
    --resource-group rg-webapp-perf \
    --name webapp-myapp \
    --query defaultHostName --output tsv)

CDN_URL=$(az cdn endpoint show \
    --resource-group rg-webapp-perf \
    --profile-name cdn-profile-myapp \
    --name cdn-myapp \
    --query hostName --output tsv)

# Test direct application access
curl -I https://${WEB_APP_URL}

# Test CDN access
curl -I https://${CDN_URL}

# Test caching headers
curl -H "Cache-Control: no-cache" https://${CDN_URL}/api/products
```

### 3. Monitor Performance Metrics

```bash
# View Application Insights metrics
az monitor app-insights metrics show \
    --resource-group rg-webapp-perf \
    --app webapp-myapp-insights \
    --metric "requests/duration"

# Check Redis cache metrics
az monitor metrics list \
    --resource /subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/rg-webapp-perf/providers/Microsoft.Cache/Redis/cache-myapp \
    --metric "CacheHits,CacheMisses,UsedMemory"
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-webapp-perf \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Delete individual resources
az webapp delete --resource-group rg-webapp-perf --name webapp-myapp
az redis delete --resource-group rg-webapp-perf --name cache-myapp --yes
az cdn endpoint delete --resource-group rg-webapp-perf --profile-name cdn-profile-myapp --name cdn-myapp
az cdn profile delete --resource-group rg-webapp-perf --name cdn-profile-myapp
az postgres flexible-server delete --resource-group rg-webapp-perf --name db-server-myapp --yes
az appservice plan delete --resource-group rg-webapp-perf --name asp-webapp-myapp --yes
```

## Customization

### Performance Optimization

1. **Redis Cache Scaling**: Adjust `redisCapacity` parameter (0-6) based on expected load
2. **App Service Plan**: Scale to Premium tiers for production workloads
3. **CDN Rules**: Modify caching rules in the Bicep template for specific content types
4. **Database Performance**: Upgrade PostgreSQL SKU for higher performance requirements

### Security Enhancements

1. **Private Endpoints**: Enable private endpoints for Redis and PostgreSQL
2. **Key Vault Integration**: Store connection strings and keys in Azure Key Vault
3. **WAF Integration**: Add Web Application Firewall rules for additional security
4. **Network Security**: Implement VNet integration and network security groups

### Monitoring Enhancements

1. **Custom Alerts**: Configure Application Insights alerts for performance thresholds
2. **Log Analytics**: Set up Log Analytics workspace for centralized logging
3. **Dashboards**: Create custom dashboards for performance monitoring
4. **Availability Tests**: Configure availability tests for uptime monitoring

## Cost Optimization

- **App Service Plan**: Use Consumption tier for development/testing
- **Redis Cache**: Use Basic tier for non-production environments
- **CDN**: Monitor bandwidth usage and optimize caching rules
- **Database**: Use Burstable tier for variable workloads

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- [Azure App Service documentation](https://docs.microsoft.com/en-us/azure/app-service/)
- [Azure Cache for Redis documentation](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Azure CDN documentation](https://docs.microsoft.com/en-us/azure/cdn/)
- [Azure Database for PostgreSQL documentation](https://docs.microsoft.com/en-us/azure/postgresql/)

## Troubleshooting

### Common Issues

1. **Redis Connection Failures**: Verify firewall rules and SSL configuration
2. **CDN Cache Not Working**: Check origin server configuration and caching rules
3. **Database Connection Issues**: Verify connection string and firewall settings
4. **Application Performance**: Monitor Application Insights for bottlenecks

### Debugging Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group rg-webapp-perf \
    --name main

# View application logs
az webapp log tail \
    --resource-group rg-webapp-perf \
    --name webapp-myapp

# Check Redis metrics
az redis show \
    --resource-group rg-webapp-perf \
    --name cache-myapp \
    --query "{status:provisioningState,hostname:hostName,port:port,sslPort:sslPort}"
```

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment
2. Validate templates before deployment
3. Update documentation for any parameter changes
4. Follow Azure naming conventions and best practices