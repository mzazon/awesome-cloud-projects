# Infrastructure as Code for Enterprise API Protection with Premium Management and WAF

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise API Protection with Premium Management and WAF".

## Overview

This solution deploys a comprehensive enterprise-grade API security and performance platform using Azure API Management Premium, Azure Web Application Firewall, Azure Cache for Redis Enterprise, and Azure Application Insights. The architecture provides multi-layered threat protection, intelligent caching, and advanced monitoring capabilities for enterprise API ecosystems.

## Architecture Components

- **Azure Front Door Premium** - Global load balancing and edge security
- **Azure Web Application Firewall (WAF)** - OWASP-compliant threat protection
- **Azure API Management Premium** - Enterprise API gateway with advanced policies
- **Azure Cache for Redis Enterprise** - High-performance caching layer
- **Azure Application Insights** - Application performance monitoring
- **Azure Log Analytics Workspace** - Centralized logging and analytics

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** installed and configured (version 2.50.0 or later)
2. **Azure subscription** with Contributor or Owner permissions
3. **Resource quota** for premium-tier services in your target region
4. **Understanding** of API security concepts and enterprise networking
5. **Budget awareness** - Premium services incur significant costs ($300-500 USD for 24-48 hours)

### Required Azure Permissions

- `Microsoft.ApiManagement/*` - API Management operations
- `Microsoft.Cdn/*` - Front Door and CDN operations
- `Microsoft.Network/*` - WAF policy and networking operations
- `Microsoft.Cache/*` - Redis Enterprise operations
- `Microsoft.Insights/*` - Application Insights and Log Analytics
- `Microsoft.Resources/*` - Resource group and deployment operations

> **Warning**: This solution uses premium-tier Azure services that incur significant costs. Monitor your Azure billing dashboard and delete resources promptly after testing to avoid unexpected charges.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone the repository and navigate to the code directory
cd azure/enterprise-api-protection-premium-waf/code

# Deploy using Bicep
az deployment group create \
    --resource-group rg-enterprise-api-security \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 4)
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# Note: API Management Premium deployment takes 30-45 minutes
```

## Deployment Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `uniqueSuffix` | Unique suffix for resource names | Auto-generated | No |
| `publisherName` | API Management publisher name | `Enterprise APIs` | No |
| `publisherEmail` | API Management publisher email | `api-admin@company.com` | No |
| `redisSku` | Redis Enterprise SKU | `Premium` | No |
| `apimSku` | API Management SKU | `Premium` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Name of the resource group | `rg-enterprise-api-security` | No |
| `location` | Azure region | `eastus` | No |
| `unique_suffix` | Unique suffix for resources | Auto-generated | No |
| `publisher_name` | API Management publisher name | `Enterprise APIs` | No |
| `publisher_email` | API Management publisher email | `api-admin@company.com` | No |

## Post-Deployment Configuration

After successful deployment, complete these configuration steps:

### 1. Configure API Management Policies

```bash
# Get API Management instance name
APIM_NAME=$(az apim list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv)

# Apply security policies to your APIs
az apim api policy create \
    --resource-group rg-enterprise-api-security \
    --service-name $APIM_NAME \
    --api-id your-api-id \
    --policy-file path/to/your/policy.xml
```

### 2. Configure Custom WAF Rules

```bash
# Get WAF policy name
WAF_POLICY_NAME=$(az network front-door waf-policy list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv)

# Add custom WAF rules as needed
az network front-door waf-policy rule create \
    --resource-group rg-enterprise-api-security \
    --policy-name $WAF_POLICY_NAME \
    --rule-name custom-rule-1 \
    --action Block \
    --priority 100
```

### 3. Configure Application Insights Alerts

```bash
# Get Application Insights name
AI_NAME=$(az monitor app-insights component list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv)

# Create performance alert
az monitor metrics alert create \
    --resource-group rg-enterprise-api-security \
    --name "API Response Time Alert" \
    --target-resource-id $(az monitor app-insights component show --resource-group rg-enterprise-api-security --app $AI_NAME --query id -o tsv) \
    --condition "avg requests/duration > 5000"
```

## Validation and Testing

### 1. Verify Infrastructure Deployment

```bash
# Check Front Door status
az afd profile list --resource-group rg-enterprise-api-security --output table

# Verify WAF policy
az network front-door waf-policy list --resource-group rg-enterprise-api-security --output table

# Check API Management status
az apim list --resource-group rg-enterprise-api-security --output table

# Verify Redis Enterprise status
az redis list --resource-group rg-enterprise-api-security --output table
```

Expected output: Front Door should show "Succeeded" deployment status and WAF policy should show "Prevention" mode.

### 2. Test API Endpoint Security

```bash
# Get Front Door endpoint URL
FD_ENDPOINT=$(az afd endpoint list --resource-group rg-enterprise-api-security --profile-name $(az afd profile list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv) --query '[0].hostName' -o tsv)

# Test legitimate API request
curl -v https://$FD_ENDPOINT/api/v1/status

# Test malicious request (should be blocked by WAF)
curl -v "https://$FD_ENDPOINT/api/v1/test?id=1' OR 1=1"
```

Expected output: API should respond through Front Door with appropriate security headers and WAF protection active.

### 3. Verify Redis Cache Integration

```bash
# Check Redis connectivity and status
az redis show \
    --resource-group rg-enterprise-api-security \
    --name $(az redis list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv) \
    --query "{status: redisStatus, sku: sku.name}" --output table

# Verify cache policies are active in API Management
az apim api policy show \
    --resource-group rg-enterprise-api-security \
    --service-name $(az apim list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv) \
    --api-id sample-api \
    --query "value" --output tsv
```

Expected output: Redis should show "Running" status with Premium SKU, and API policies should include cache-lookup and cache-store configurations.

### 4. Test Security Features and Monitoring

```bash
# Send malicious request to test WAF protection
curl -v "https://$FD_ENDPOINT/api/v1/get?id=1%27%20OR%201=1" \
    -H "Accept: application/json"

# Check Application Insights data collection
az monitor app-insights metrics show \
    --resource-group rg-enterprise-api-security \
    --app $(az monitor app-insights component list --resource-group rg-enterprise-api-security --query '[0].name' -o tsv) \
    --metric requests/count \
    --interval 1h
```

Expected output: WAF should block malicious requests with appropriate error codes, and Application Insights should show telemetry data collection.

## Security Considerations

### Default Security Features

This deployment includes enterprise-grade security features:

- **OWASP Core Rule Set 3.2** - Protection against common web attacks
- **Bot protection** - Automatic detection and blocking of malicious bots
- **Rate limiting** - Prevents API abuse and ensures fair usage
- **TLS 1.2 enforcement** - Secure communication protocols
- **Managed identities** - Secure service-to-service authentication
- **Network isolation** - Premium tier supports virtual network integration

### Additional Security Hardening

Consider implementing these additional security measures:

1. **Custom WAF rules** based on your application patterns
2. **IP allowlisting** for administrative access
3. **Conditional access policies** integrated with Azure AD
4. **API versioning** with deprecation policies
5. **Certificate-based authentication** for high-security scenarios

## Performance Optimization

### Caching Strategy

The deployed Redis Enterprise cache provides:

- **Sub-millisecond latency** for cached responses
- **Automatic failover** with high availability
- **Intelligent eviction** with optimized memory policies
- **SSL/TLS encryption** for data in transit

### Monitoring and Alerting

Application Insights provides comprehensive monitoring:

- **Real-time performance metrics** for all API endpoints
- **Custom dashboards** for executive reporting
- **Automated alerting** for performance degradation
- **User behavior analytics** for usage optimization

## Cost Management

### Cost Optimization Tips

1. **Monitor usage** regularly through Azure Cost Management
2. **Implement auto-scaling** based on demand patterns
3. **Use Azure Reserved Instances** for predictable workloads
4. **Configure cache TTL** appropriately to reduce backend calls
5. **Review WAF logs** to optimize rule sets and reduce false positives

### Estimated Monthly Costs

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| API Management Premium | 1 unit | $2,800-$3,000 |
| Front Door Premium | Standard usage | $200-$400 |
| Redis Enterprise P1 | 6GB cache | $600-$800 |
| Application Insights | Pay-as-you-go | $50-$200 |
| **Total** | | **$3,650-$4,400** |

> **Note**: Costs vary based on usage patterns, data transfer, and regional pricing. Use Azure Pricing Calculator for accurate estimates.

## Troubleshooting

### Common Issues

1. **API Management deployment timeout**
   - Premium tier deployment takes 30-45 minutes
   - Check deployment status: `az deployment group show`

2. **Front Door routing issues**
   - Verify origin health: `az afd origin show`
   - Check WAF policy association: `az network front-door waf-policy show`

3. **Redis connectivity problems**
   - Verify firewall rules and network security groups
   - Check Redis keys: `az redis list-keys`

4. **Application Insights data not appearing**
   - Verify instrumentation key configuration
   - Check sampling settings in diagnostic configuration

### Debug Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-enterprise-api-security \
    --name main-deployment

# View resource health
az resource list \
    --resource-group rg-enterprise-api-security \
    --output table

# Check Activity Log for errors
az monitor activity-log list \
    --resource-group rg-enterprise-api-security \
    --max-events 50
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-enterprise-api-security \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name rg-enterprise-api-security 2>/dev/null || echo "Resource group successfully deleted"
```

### Manual Cleanup Verification

```bash
# List any remaining resources
az resource list \
    --resource-group rg-enterprise-api-security \
    --output table

# Check for any remaining deployments
az deployment group list \
    --resource-group rg-enterprise-api-security \
    --output table
```

## Customization

### Environment-Specific Configurations

1. **Development Environment**: Use Standard tiers to reduce costs
2. **Production Environment**: Enable geo-replication and multi-region deployment
3. **Staging Environment**: Configure blue-green deployment strategies

### Integration Examples

```bash
# Integrate with Azure DevOps
az devops configure --defaults organization=https://dev.azure.com/yourorg project=yourproject

# Set up CI/CD pipeline for API deployment
az pipelines create --name api-deployment --repository-url https://github.com/yourorg/api-repo

# Configure automated testing
az pipelines variable create --name APIM_ENDPOINT --value https://your-apim-instance.azure-api.net
```

## Support and Resources

### Documentation Links

- [Azure API Management Premium Documentation](https://docs.microsoft.com/en-us/azure/api-management/)
- [Azure Web Application Firewall Guide](https://docs.microsoft.com/en-us/azure/web-application-firewall/)
- [Azure Cache for Redis Enterprise](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Azure Front Door Configuration](https://docs.microsoft.com/en-us/azure/frontdoor/)

### Community Resources

- [Azure API Management GitHub Repository](https://github.com/Azure/api-management-developer-portal)
- [Azure Security Community](https://techcommunity.microsoft.com/t5/azure-security/ct-p/AzureSecurity)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)

### Getting Help

For issues with this infrastructure code:

1. Check the [original recipe documentation](../enterprise-api-protection-premium-waf.md)
2. Review Azure service documentation links above
3. Submit issues to the recipe repository
4. Engage with the Azure community forums

---

**Note**: This infrastructure deploys premium-tier services that incur significant costs. Always monitor your Azure billing and clean up resources when no longer needed.