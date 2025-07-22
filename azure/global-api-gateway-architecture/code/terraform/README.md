# Multi-Region API Gateway with Azure API Management and Cosmos DB - Terraform

This Terraform configuration deploys a comprehensive multi-region API gateway solution using Azure API Management and Cosmos DB, providing global load balancing, intelligent traffic routing, and distributed rate limiting capabilities.

## Architecture Overview

The solution creates a globally distributed API gateway architecture with:

- **Azure API Management Premium** deployed across multiple regions (East US, West Europe, Southeast Asia)
- **Azure Cosmos DB** with multi-region writes for storing API configurations and rate limiting data
- **Azure Traffic Manager** for DNS-based global load balancing with performance routing
- **Centralized monitoring** using Azure Monitor, Log Analytics, and Application Insights
- **Global rate limiting** policies using Cosmos DB for cross-region synchronization

## Features

- ✅ **Multi-region deployment** with automatic failover
- ✅ **Global rate limiting** synchronized across all regions
- ✅ **Performance-based routing** using Traffic Manager
- ✅ **Comprehensive monitoring** and alerting
- ✅ **Managed identity** authentication for security
- ✅ **Zone redundancy** for high availability
- ✅ **Custom policies** for advanced API management

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** version 2.50.0 or later installed and configured
2. **Terraform** version 1.5 or later installed
3. An **Azure subscription** with appropriate permissions to create resources
4. **Owner or Contributor** role on the subscription for creating role assignments

### Required Azure Resource Providers

Ensure the following resource providers are registered in your subscription:

```bash
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.OperationalInsights
```

## Cost Considerations

This solution uses Premium tier services for production-grade capabilities:

- **API Management Premium**: ~$2,700/month per region (3 regions = ~$8,100/month)
- **Cosmos DB**: ~$25-50/month per region depending on usage
- **Traffic Manager**: ~$1/month per profile
- **Log Analytics**: ~$3-10/month depending on data ingestion
- **Application Insights**: ~$2-5/month depending on usage

**Total estimated cost**: ~$5,000-8,200/month for 3 regions

> **Note**: Use Developer tier for API Management during testing to reduce costs significantly.

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/implementing-multi-region-api-gateway-with-azure-api-management-and-cosmos-db/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
# Core Configuration
project_name        = "my-global-api"
environment        = "prod"
location           = "East US"
secondary_regions  = ["West Europe", "Southeast Asia"]

# API Management
apim_publisher_name  = "My Company API Platform"
apim_publisher_email = "api-team@mycompany.com"
apim_sku_capacity   = 1

# Cosmos DB
cosmos_throughput = 10000
cosmos_enable_free_tier = false

# Monitoring
log_retention_days = 30
enable_application_insights = true

# Tagging
tags = {
  Environment = "production"
  Project     = "global-api-gateway"
  Owner       = "platform-team"
  CostCenter  = "engineering"
}
```

### 4. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

The deployment will take approximately 60-90 minutes due to API Management provisioning time.

### 5. Verify Deployment

After deployment completes, verify the resources:

```bash
# Get global endpoint
terraform output global_api_endpoint

# Test the global endpoint
curl -I $(terraform output -raw global_api_endpoint)/weather/weather?q=Seattle

# Check Traffic Manager routing
nslookup $(terraform output -raw traffic_manager_dns_name)
```

## Configuration Reference

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `global-api` | No |
| `location` | Primary Azure region | `East US` | No |
| `secondary_regions` | List of secondary regions | `["West Europe", "Southeast Asia"]` | No |
| `environment` | Environment name (dev/staging/prod) | `prod` | No |

### API Management Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `apim_sku_name` | API Management SKU (must be Premium) | `Premium` | No |
| `apim_sku_capacity` | Scale units per region | `1` | No |
| `apim_publisher_name` | Publisher name | `Contoso API Platform` | No |
| `apim_publisher_email` | Publisher email | `api-team@contoso.com` | No |
| `apim_enable_zone_redundancy` | Enable zone redundancy | `true` | No |

### Cosmos DB Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cosmos_consistency_level` | Consistency level | `Session` | No |
| `cosmos_enable_multi_region_writes` | Enable multi-region writes | `true` | No |
| `cosmos_throughput` | Throughput in RU/s | `10000` | No |
| `cosmos_enable_free_tier` | Enable free tier | `false` | No |

### Traffic Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `traffic_manager_routing_method` | Routing method | `Performance` | No |
| `traffic_manager_ttl` | DNS TTL in seconds | `30` | No |

### Monitoring Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `log_analytics_sku` | Log Analytics SKU | `PerGB2018` | No |
| `log_retention_days` | Log retention period | `30` | No |
| `enable_application_insights` | Enable App Insights | `true` | No |

## Outputs

After deployment, Terraform provides important information through outputs:

### Key Outputs

- `global_api_endpoint`: Global API endpoint URL via Traffic Manager
- `api_management_gateway_url`: Primary API Management gateway URL
- `cosmos_db_endpoint`: Cosmos DB endpoint URL
- `traffic_manager_dns_name`: Traffic Manager FQDN
- `sample_api_details`: Information about the created sample API

### Connection Information

Use these outputs to configure applications:

```bash
# Get all connection information
terraform output connection_info

# Get specific values
GLOBAL_ENDPOINT=$(terraform output -raw global_api_endpoint)
PRIMARY_ENDPOINT=$(terraform output -raw api_management_gateway_url)
COSMOS_ENDPOINT=$(terraform output -raw cosmos_db_endpoint)
```

## Security Features

### Managed Identity

The solution uses system-assigned managed identities for secure authentication:

- API Management uses managed identity to access Cosmos DB
- No connection strings or keys stored in configuration
- RBAC controls provide fine-grained access permissions

### Network Security

- API Management supports VNet integration (configurable)
- Cosmos DB uses private endpoints (when VNet is configured)
- Traffic Manager provides DDoS protection
- WAF capabilities available through API Management policies

### Data Protection

- All data encrypted at rest and in transit
- Cosmos DB supports customer-managed keys
- API Management supports custom certificates
- Comprehensive audit logging enabled

## Monitoring and Observability

### Built-in Monitoring

The solution includes comprehensive monitoring:

- **Azure Monitor** for metrics and alerts
- **Log Analytics** for centralized logging
- **Application Insights** for distributed tracing
- **Custom dashboards** for operational visibility

### Key Metrics

Monitor these critical metrics:

- API request latency across regions
- API error rates and status codes
- Cosmos DB RU consumption
- Traffic Manager endpoint health
- Rate limiting violations

### Alerts

Pre-configured alerts for:

- High API error rates (>100 failed requests in 5 minutes)
- Regional endpoint failures
- Cosmos DB throttling
- Unusual traffic patterns

## Advanced Configuration

### Custom Domains

To configure custom domains:

1. Set `custom_domain_name` variable
2. Configure SSL certificates in Azure Key Vault
3. Update DNS CNAME records

```hcl
custom_domain_name = "api.mycompany.com"
certificate_source = "KeyVault"
```

### VNet Integration

For private connectivity:

```hcl
virtual_network_type = "Internal"
```

This requires additional VNet and subnet configuration.

### Rate Limiting Customization

Modify the rate limiting policy in `templates/rate-limit-policy.xml.tpl`:

- Adjust rate limits (currently 1000 requests/hour)
- Change time windows
- Add different limits per API or subscription

## Operations Guide

### Scaling

To scale the solution:

```bash
# Increase API Management capacity
terraform apply -var="apim_sku_capacity=2"

# Increase Cosmos DB throughput
terraform apply -var="cosmos_throughput=20000"
```

### Adding Regions

To add new regions:

```bash
terraform apply -var='secondary_regions=["West Europe", "Southeast Asia", "Japan East"]'
```

### Backup and Recovery

- **Cosmos DB**: Automatic backups with point-in-time recovery
- **API Management**: Configuration automatically replicated
- **Traffic Manager**: Configuration stored in Azure Resource Manager

### Disaster Recovery

The solution provides automatic disaster recovery:

1. **Regional Failures**: Traffic Manager automatically routes to healthy regions
2. **Cosmos DB Failover**: Automatic failover to secondary regions
3. **API Management**: Each region operates independently

## Troubleshooting

### Common Issues

**1. Deployment Timeout**
```bash
# API Management takes 45-60 minutes to deploy
# Increase timeout if needed
export TF_VAR_timeout="90m"
```

**2. Permission Errors**
```bash
# Ensure proper RBAC roles
az role assignment create --assignee <user-id> --role "Contributor" --scope <subscription-id>
```

**3. Rate Limiting Not Working**
```bash
# Check managed identity permissions
az cosmosdb sql role assignment list --account-name <cosmos-account> --resource-group <rg>
```

**4. Traffic Manager Not Routing**
```bash
# Verify endpoint health
az network traffic-manager endpoint show --name <endpoint> --profile-name <profile> --resource-group <rg>
```

### Diagnostic Commands

```bash
# Check API Management status
az apim show --name <apim-name> --resource-group <rg> --query provisioningState

# Test Cosmos DB connectivity
az cosmosdb check-name-exists --name <cosmos-name>

# Verify Traffic Manager configuration
az network traffic-manager profile show --name <tm-name> --resource-group <rg>
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

> **Warning**: This will permanently delete all resources including data in Cosmos DB. Ensure you have backups if needed.

## Support and Contributing

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review Azure service documentation
3. Open an issue in the repository

## License

This Terraform configuration is provided under the MIT License. See LICENSE file for details.

## References

- [Azure API Management Documentation](https://docs.microsoft.com/en-us/azure/api-management/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Traffic Manager Documentation](https://docs.microsoft.com/en-us/azure/traffic-manager/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)