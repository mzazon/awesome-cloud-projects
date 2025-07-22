# Infrastructure as Code for Monitor Distributed Cassandra Databases with Managed Grafana

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitor Distributed Cassandra Databases with Managed Grafana".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40+ installed and configured
- Azure subscription with appropriate permissions (Contributor role)
- Basic understanding of NoSQL databases and monitoring concepts
- Familiarity with Grafana dashboards and visualization

### Tool-Specific Prerequisites

#### For Bicep
- Bicep CLI installed (included with Azure CLI v2.20+)
- Azure PowerShell (optional, for advanced scenarios)

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated or Service Principal configured

#### For Bash Scripts
- OpenSSL installed (for generating random suffixes)
- jq installed (for JSON processing)

## Architecture Overview

This infrastructure deploys a comprehensive monitoring solution including:

- Azure Managed Instance for Apache Cassandra (3-node cluster)
- Azure Managed Grafana for visualization
- Azure Monitor and Log Analytics for metrics collection
- Azure Virtual Network with dedicated subnet
- Diagnostic settings and alerting rules

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-cassandra-monitoring --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-cassandra-monitoring \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters adminPassword='P@ssw0rd123!'
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply -auto-approve
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration values
```

## Configuration Options

### Required Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `adminPassword`: Administrator password for Cassandra cluster (min 12 characters)

### Optional Parameters

- `resourceGroupName`: Name of the resource group (default: rg-cassandra-monitoring)
- `cassandraNodeCount`: Number of Cassandra nodes (default: 3)
- `cassandraNodeSku`: VM SKU for Cassandra nodes (default: Standard_DS14_v2)
- `grafanaSku`: Grafana instance SKU (default: Standard)

### Environment Variables (for scripts)

```bash
export RESOURCE_GROUP="rg-cassandra-monitoring"
export LOCATION="eastus"
export CASSANDRA_ADMIN_PASSWORD="P@ssw0rd123!"
```

## Deployment Details

### Resource Creation Order

1. Resource Group and Virtual Network
2. Log Analytics Workspace
3. Azure Managed Instance for Apache Cassandra
4. Cassandra Data Center (3 nodes)
5. Azure Managed Grafana
6. Diagnostic Settings and Monitoring Configuration
7. Alert Rules and Action Groups

### Expected Deployment Time

- **Total Time**: 25-35 minutes
- **Cassandra Cluster**: 15-20 minutes
- **Grafana Instance**: 3-5 minutes
- **Supporting Resources**: 5-10 minutes

### Cost Estimates

- **Azure Managed Instance for Apache Cassandra**: $300-400/month (3 Standard_DS14_v2 nodes)
- **Azure Managed Grafana**: $50-100/month (Standard tier)
- **Log Analytics Workspace**: $10-50/month (depending on ingestion volume)
- **Azure Monitor**: $5-20/month (metrics and alerting)

## Post-Deployment Configuration

### Access Grafana Dashboard

1. Navigate to the Azure portal
2. Find your Grafana instance: `grafana-{random-suffix}`
3. Click "Endpoint" to access the Grafana interface
4. Log in with your Azure AD credentials

### Configure Data Sources

The deployment automatically creates an Azure Monitor data source. To verify:

1. In Grafana, go to Configuration > Data Sources
2. Verify "Azure Monitor - Cassandra" is configured
3. Test the connection using the "Test" button

### Import Dashboard

1. In Grafana, click the "+" icon and select "Import"
2. Use the dashboard JSON configuration provided in the recipe
3. Configure panels to display your specific metrics

### Verify Monitoring

```bash
# Check Cassandra cluster status
az managed-cassandra cluster show \
    --cluster-name cassandra-{suffix} \
    --resource-group rg-cassandra-monitoring

# View available metrics
az monitor metrics list-definitions \
    --resource "/subscriptions/{subscription-id}/resourceGroups/rg-cassandra-monitoring/providers/Microsoft.DocumentDB/cassandraClusters/cassandra-{suffix}"
```

## Validation

### Health Checks

1. **Cassandra Cluster**: Verify all 3 nodes are healthy and operational
2. **Grafana Access**: Confirm you can access the Grafana endpoint
3. **Metrics Collection**: Validate metrics are flowing from Cassandra to Azure Monitor
4. **Dashboard Functionality**: Test dashboard queries and visualizations
5. **Alert Rules**: Verify alert rules are active and properly configured

### Testing Commands

```bash
# Test Cassandra connectivity
az managed-cassandra cluster show \
    --name cassandra-{suffix} \
    --resource-group rg-cassandra-monitoring \
    --query "properties.provisioningState"

# Verify Grafana status
az grafana show \
    --name grafana-{suffix} \
    --resource-group rg-cassandra-monitoring \
    --query "properties.provisioningState"

# Check metrics availability
az monitor metrics list \
    --resource "{cassandra-resource-id}" \
    --metric "CPUUsage" \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-cassandra-monitoring --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group show --name rg-cassandra-monitoring --query "properties.provisioningState" 2>/dev/null || echo "Resource group successfully deleted"
```

## Customization

### Scaling the Cassandra Cluster

To modify the number of Cassandra nodes:

**Bicep**: Update the `cassandraNodeCount` parameter
**Terraform**: Modify the `node_count` variable
**Scripts**: Change the `--node-count` parameter in deploy.sh

### Changing Instance Sizes

To modify VM sizes for better performance or cost optimization:

**Bicep**: Update the `cassandraNodeSku` parameter
**Terraform**: Modify the `sku` variable
**Scripts**: Change the `--sku` parameter in deploy.sh

### Adding Custom Metrics

1. Modify diagnostic settings to include additional log categories
2. Update Grafana dashboard configuration
3. Add custom alert rules for new metrics

### Multi-Region Deployment

For multi-region deployments:

1. Deploy infrastructure in multiple regions
2. Configure cross-region monitoring in Grafana
3. Set up global alerting policies

## Troubleshooting

### Common Issues

1. **Cassandra Deployment Timeout**: Cluster creation can take 15-20 minutes
2. **Grafana Access Issues**: Ensure proper Azure AD permissions
3. **Missing Metrics**: Verify diagnostic settings are properly configured
4. **Alert Rule Failures**: Check action group email configuration

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-cassandra-monitoring \
    --name {deployment-name}

# View activity logs
az monitor activity-log list \
    --resource-group rg-cassandra-monitoring \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)"

# Check Cassandra logs
az monitor diagnostic-settings list \
    --resource "{cassandra-resource-id}"
```

## Security Considerations

### Network Security

- Cassandra cluster is deployed in a dedicated subnet
- Network security groups restrict access
- Private endpoints can be configured for enhanced security

### Authentication

- Grafana uses Azure AD authentication
- Managed identities for service-to-service communication
- Certificate-based authentication for Cassandra

### Data Protection

- Encryption at rest enabled for all storage
- Encryption in transit for all communications
- Backup and restore capabilities built-in

## Monitoring Best Practices

### Key Metrics to Monitor

1. **Performance**: Read/write latency, throughput, query patterns
2. **Resource Utilization**: CPU, memory, disk I/O, network
3. **Cluster Health**: Node status, replication lag, compaction
4. **Application**: Connection counts, error rates, timeout rates

### Alerting Strategy

1. **Critical**: Node failures, high error rates, connectivity issues
2. **Warning**: High resource utilization, performance degradation
3. **Informational**: Capacity planning, maintenance windows

### Dashboard Organization

1. **Overview**: High-level cluster health and performance
2. **Node Details**: Individual node metrics and status
3. **Query Analysis**: Query performance and patterns
4. **Capacity Planning**: Long-term trends and forecasting

## Support

### Documentation Links

- [Azure Managed Instance for Apache Cassandra](https://docs.microsoft.com/en-us/azure/managed-instance-apache-cassandra/)
- [Azure Managed Grafana](https://docs.microsoft.com/en-us/azure/managed-grafana/)
- [Azure Monitor](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status and known issues
3. Consult provider documentation for specific services
4. Use Azure support channels for service-specific issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Ensure compatibility with all supported deployment methods
4. Update documentation for any configuration changes