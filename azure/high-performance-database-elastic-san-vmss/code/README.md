# Infrastructure as Code for High-Performance Database Workloads with Elastic SAN and VMSS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Performance Database Workloads with Elastic SAN and VMSS".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for creating:
  - Azure Elastic SAN resources
  - Virtual Machine Scale Sets
  - Azure Database for PostgreSQL Flexible Server
  - Azure Load Balancer
  - Azure Monitor resources
  - Virtual Networks and subnets
- PowerShell 7.0+ (for Bicep deployment) or Bash (for Terraform/scripts)
- Terraform v1.5.0 or later (for Terraform deployment)

## Architecture Overview

This infrastructure creates a high-performance database solution combining:
- **Azure Elastic SAN**: Centralized, scalable block storage with enterprise-grade performance
- **VM Scale Sets**: Auto-scaling compute resources for database workloads
- **Azure Load Balancer**: High availability and traffic distribution
- **PostgreSQL Flexible Server**: Managed database service with built-in HA
- **Azure Monitor**: Comprehensive monitoring and alerting

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-elastic-san-demo" \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters adminUsername=azureuser \
    --parameters adminPassword="SecurePassword123!" \
    --parameters vmssInstanceCount=2

# Monitor deployment status
az deployment group show \
    --resource-group "rg-elastic-san-demo" \
    --name "main" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourceGroupName` | Name of the resource group | `rg-elastic-san-demo` | Yes |
| `adminUsername` | VM administrator username | `azureuser` | Yes |
| `adminPassword` | VM administrator password | - | Yes |
| `vmssInstanceCount` | Initial VMSS instance count | `2` | No |
| `elasticSanBaseSizeTiB` | Base size for Elastic SAN in TiB | `1` | No |
| `elasticSanExtendedSizeTiB` | Extended capacity in TiB | `2` | No |
| `postgresVersion` | PostgreSQL version | `14` | No |
| `postgresSkuName` | PostgreSQL SKU | `Standard_D2s_v3` | No |

### Terraform Variables

| Variable | Description | Default Value | Required |
|----------|-------------|---------------|----------|
| `location` | Azure region for deployment | `East US` | Yes |
| `resource_group_name` | Name of the resource group | `rg-elastic-san-demo` | Yes |
| `admin_username` | VM administrator username | `azureuser` | Yes |
| `admin_password` | VM administrator password | - | Yes |
| `vmss_instance_count` | Initial VMSS instance count | `2` | No |
| `elastic_san_base_size_tib` | Base size for Elastic SAN in TiB | `1` | No |
| `elastic_san_extended_size_tib` | Extended capacity in TiB | `2` | No |
| `postgres_version` | PostgreSQL version | `14` | No |
| `postgres_sku_name` | PostgreSQL SKU | `Standard_D2s_v3` | No |

## Deployed Resources

The infrastructure creates the following Azure resources:

### Core Infrastructure
- **Resource Group**: Container for all resources
- **Virtual Network**: Network foundation with subnet
- **Network Security Group**: Security rules for database access

### Storage Layer
- **Azure Elastic SAN**: High-performance storage area network
- **Volume Groups**: Logical organization of storage volumes
- **Storage Volumes**: Separate volumes for data and transaction logs

### Compute Layer
- **Virtual Machine Scale Set**: Auto-scaling VM instances
- **Azure Load Balancer**: Traffic distribution and high availability
- **Public IP**: External access to load balancer

### Database Layer
- **PostgreSQL Flexible Server**: Managed database service
- **High Availability Configuration**: Cross-zone redundancy

### Monitoring and Management
- **Log Analytics Workspace**: Centralized logging
- **Azure Monitor Autoscale**: Automatic scaling policies
- **Metric Alerts**: Performance monitoring and alerting
- **Action Groups**: Alert notification handling

## Post-Deployment Configuration

### 1. Verify Elastic SAN Connectivity

```bash
# Check Elastic SAN status
az elastic-san show \
    --name "esan-db-${RANDOM_SUFFIX}" \
    --resource-group "rg-elastic-san-demo" \
    --query "{name:name,provisioningState:provisioningState}"

# List volume groups
az elastic-san volume-group list \
    --elastic-san-name "esan-db-${RANDOM_SUFFIX}" \
    --resource-group "rg-elastic-san-demo"
```

### 2. Test Database Connectivity

```bash
# Get load balancer public IP
LB_IP=$(az network public-ip show \
    --resource-group "rg-elastic-san-demo" \
    --name "lb-db-${RANDOM_SUFFIX}PublicIP" \
    --query ipAddress --output tsv)

# Test PostgreSQL connection
psql -h ${LB_IP} -U pgadmin -d postgres
```

### 3. Monitor Auto-Scaling

```bash
# Check autoscale profile
az monitor autoscale show \
    --resource-group "rg-elastic-san-demo" \
    --name "vmss-autoscale-profile" \
    --query "{enabled:enabled,profiles:profiles[0].capacity}"
```

## Performance Optimization

### Storage Performance

The Elastic SAN configuration provides:
- **Base Performance**: 1 TiB with guaranteed IOPS
- **Extended Performance**: Additional 2 TiB for burst capacity
- **Protocol**: iSCSI for high-performance block storage
- **Redundancy**: Premium LRS for durability

### Compute Scaling

Auto-scaling configuration:
- **Minimum Instances**: 2 (for high availability)
- **Maximum Instances**: 10 (for peak workload handling)
- **Scale-out Trigger**: CPU > 70% for 5 minutes
- **Scale-in Trigger**: CPU < 30% for 5 minutes
- **Cooldown Period**: 5 minutes between scaling actions

### Database Optimization

PostgreSQL Flexible Server features:
- **High Availability**: Cross-zone redundancy
- **Storage Type**: Premium SSD for consistent performance
- **Backup**: Automated with point-in-time recovery
- **Monitoring**: Integrated with Azure Monitor

## Security Considerations

### Network Security

- **Virtual Network**: Isolated network environment
- **Network Security Groups**: Restrictive inbound/outbound rules
- **Private Endpoints**: Secure database connectivity
- **Load Balancer**: Internal load balancing for security

### Access Control

- **Azure RBAC**: Role-based access control for resources
- **Database Authentication**: PostgreSQL user authentication
- **SSH Keys**: Secure VM access (password authentication disabled)
- **Network ACLs**: Elastic SAN network access controls

### Data Protection

- **Encryption**: Data at rest and in transit
- **Backup**: Automated PostgreSQL backups
- **Monitoring**: Security event logging
- **Compliance**: Azure compliance frameworks

## Monitoring and Alerting

### Available Metrics

- **Elastic SAN**: IOPS, throughput, latency
- **VMSS**: CPU, memory, disk utilization
- **PostgreSQL**: Connection count, query performance
- **Load Balancer**: Request distribution, health probes

### Alert Rules

Pre-configured alerts for:
- High CPU usage (>80%)
- Memory pressure
- Storage performance degradation
- Database connection failures
- Auto-scaling events

### Log Analytics

Centralized logging includes:
- **System logs**: OS-level events
- **Application logs**: Database and application events
- **Performance logs**: Metrics and performance counters
- **Security logs**: Authentication and authorization events

## Troubleshooting

### Common Issues

**Elastic SAN Volume Mount Failures**
```bash
# Check iSCSI service status
sudo systemctl status open-iscsi

# Verify network connectivity to Elastic SAN
sudo iscsiadm -m discovery -t sendtargets -p <elastic-san-endpoint>
```

**VMSS Scaling Issues**
```bash
# Check autoscale profile configuration
az monitor autoscale show \
    --resource-group "rg-elastic-san-demo" \
    --name "vmss-autoscale-profile"

# Review scaling history
az monitor autoscale show \
    --resource-group "rg-elastic-san-demo" \
    --name "vmss-autoscale-profile" \
    --query "profiles[0].rules"
```

**Database Connection Problems**
```bash
# Check PostgreSQL server status
az postgres flexible-server show \
    --resource-group "rg-elastic-san-demo" \
    --name "pg-db-${RANDOM_SUFFIX}"

# Test network connectivity
telnet <postgres-server-endpoint> 5432
```

### Log Analysis

```bash
# Query Log Analytics for performance issues
az monitor log-analytics query \
    --workspace "law-db-monitoring-${RANDOM_SUFFIX}" \
    --analytics-query "Perf | where CounterName == 'Processor(_Total)\\% Processor Time' | summarize avg(CounterValue) by bin(TimeGenerated, 5m)"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-elastic-san-demo" \
    --yes \
    --no-wait

# Verify deletion
az group exists --name "rg-elastic-san-demo"
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow the prompts for confirmation
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group "rg-elastic-san-demo" \
    --query "length([*])"

# Check for any remaining Elastic SAN resources
az elastic-san list \
    --query "[?contains(name, 'esan-db')]"
```

## Cost Optimization

### Estimated Monthly Costs

- **Azure Elastic SAN**: $150-300 (depends on size and IOPS)
- **VMSS Instances**: $100-400 (depends on instance count and size)
- **PostgreSQL Flexible Server**: $50-150 (depends on SKU and storage)
- **Load Balancer**: $20-50 (depends on traffic)
- **Monitoring**: $10-30 (depends on log retention)

**Total Estimated Range**: $330-930 per month

### Cost Reduction Strategies

1. **Use Azure Reserved Instances** for predictable workloads
2. **Configure auto-scaling** to minimize idle resources
3. **Optimize Elastic SAN sizing** based on actual usage
4. **Use Azure Hybrid Benefit** for Windows Server licenses
5. **Monitor and adjust** PostgreSQL SKU based on performance needs

## Support and Documentation

### Azure Documentation

- [Azure Elastic SAN Overview](https://docs.microsoft.com/en-us/azure/storage/elastic-san/)
- [Virtual Machine Scale Sets](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [Azure Database for PostgreSQL](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Azure Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/)

### Best Practices

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/)
- [Database Performance Tuning](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-performance-recommendations)

### Community Resources

- [Azure Community Support](https://azure.microsoft.com/en-us/support/community/)
- [Stack Overflow Azure Tags](https://stackoverflow.com/questions/tagged/azure)
- [Azure Updates](https://azure.microsoft.com/en-us/updates/)

## Customization

### Extending the Solution

1. **Add Azure Site Recovery** for disaster recovery
2. **Implement Azure Key Vault** for secrets management
3. **Configure Azure Private Link** for enhanced security
4. **Add Application Insights** for application monitoring
5. **Implement backup automation** with Azure Automation

### Advanced Configurations

- **Multi-region deployment** for global availability
- **Custom metrics** for application-specific monitoring
- **Advanced auto-scaling** with custom rules
- **Integration with Azure DevOps** for CI/CD pipelines
- **Compliance scanning** with Azure Policy

For issues with this infrastructure code, refer to the original recipe documentation or submit an issue to the repository.