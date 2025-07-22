# Infrastructure as Code for Centralized Hybrid Cloud Governance with Arc and Policy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Hybrid Cloud Governance with Arc and Policy".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- kubectl CLI tool installed for Kubernetes cluster management
- Access to on-premises or multi-cloud Kubernetes clusters (version 1.27+)
- Access to on-premises or multi-cloud servers (Windows Server 2012 R2+ or Linux)
- Network connectivity from hybrid resources to Azure endpoints
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Architecture Overview

This solution implements a unified governance framework that:

- Connects on-premises and multi-cloud Kubernetes clusters to Azure Arc
- Connects on-premises and multi-cloud servers to Azure Arc
- Enforces Azure Policy across hybrid infrastructure
- Provides centralized monitoring via Azure Monitor
- Enables compliance reporting through Azure Resource Graph
- Implements automated remediation for policy violations

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters workspaceName=<unique-workspace-name> \
                location=<azure-region>

# The deployment will output workspace ID and key for agent installation
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Note the outputs for agent installation
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Configuration Options

### Bicep Parameters

- `workspaceName`: Log Analytics workspace name (must be globally unique)
- `location`: Azure region for resource deployment
- `clusterName`: Name prefix for Arc-enabled Kubernetes clusters
- `serverResourceGroup`: Resource group for Arc-enabled servers
- `enableMonitoring`: Enable Azure Monitor integration (default: true)
- `enablePolicy`: Enable Azure Policy enforcement (default: true)

### Terraform Variables

- `resource_group_name`: Resource group for Arc resources
- `location`: Azure region
- `workspace_name`: Log Analytics workspace name
- `cluster_name`: Arc-enabled Kubernetes cluster name
- `enable_monitoring`: Enable monitoring extensions
- `enable_policy`: Enable policy extensions
- `tags`: Common tags for all resources

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export RESOURCE_GROUP="rg-arc-governance"
export LOCATION="eastus"
export WORKSPACE_NAME="law-arc-governance"
export CLUSTER_NAME="arc-k8s-cluster"
```

## Post-Deployment Steps

### 1. Connect Kubernetes Clusters

After infrastructure deployment, connect your Kubernetes clusters:

```bash
# Get the service principal details from deployment outputs
# Then run on each cluster:
az connectedk8s connect \
    --name <cluster-name> \
    --resource-group <resource-group> \
    --location <location>
```

### 2. Connect Servers

For each server to be managed by Arc:

```bash
# Linux servers
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh
bash ~/install_linux_azcmagent.sh
azcmagent connect \
    --service-principal-id '<sp-id>' \
    --service-principal-secret '<sp-secret>' \
    --tenant-id '<tenant-id>' \
    --subscription-id '<subscription-id>' \
    --resource-group '<resource-group>' \
    --location '<location>'

# Windows servers
Invoke-WebRequest -Uri https://aka.ms/azcmagent -OutFile AzureConnectedMachineAgent.msi
msiexec /i AzureConnectedMachineAgent.msi /l*v installationlog.txt /qn
& "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id '<sp-id>' `
    --service-principal-secret '<sp-secret>' `
    --tenant-id '<tenant-id>' `
    --subscription-id '<subscription-id>' `
    --resource-group '<resource-group>' `
    --location '<location>'
```

### 3. Verify Policy Compliance

```bash
# Check policy compliance status
az policy state list \
    --resource-group <resource-group> \
    --query '[].{Resource:resourceId,Compliance:complianceState,Policy:policyDefinitionName}' \
    --output table

# Query compliance via Resource Graph
az graph query -q "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'arc' | summarize count() by tostring(properties.complianceState)"
```

## Monitoring and Governance

### Azure Monitor Integration

The solution automatically configures:

- Container insights for Arc-enabled Kubernetes clusters
- Performance monitoring for Arc-enabled servers
- Centralized log collection in Log Analytics workspace
- Custom data collection rules for hybrid resources

### Policy Enforcement

Built-in policy assignments include:

- Security baseline for Arc-enabled servers
- Kubernetes container security policies
- Compliance with industry standards (CIS, NIST)
- Custom organizational policies

### Compliance Reporting

Use Azure Resource Graph queries to generate compliance reports:

```bash
# Overall compliance percentage
az graph query -q "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'arc' | summarize Total = count(), Compliant = countif(properties.complianceState =~ 'Compliant') | project CompliancePercentage = (todouble(Compliant) / todouble(Total)) * 100"

# Compliance by resource type
az graph query -q "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'arc' | summarize count() by tostring(properties.resourceType), tostring(properties.complianceState)"
```

## Security Considerations

### Network Security

- Arc agents use outbound HTTPS connections only
- No inbound firewall rules required
- All communications are encrypted in transit
- Authentication via Azure Active Directory

### Identity and Access

- Service principal with minimal required permissions
- Managed identity for Azure resources
- Role-based access control (RBAC) enforcement
- Regular credential rotation recommended

### Data Protection

- Log data encrypted at rest in Log Analytics
- Policy definitions stored securely in Azure
- Compliance data retention policies configurable
- Data sovereignty maintained in chosen Azure region

## Troubleshooting

### Common Issues

1. **Agent Installation Failures**
   - Verify network connectivity to Azure endpoints
   - Check service principal permissions
   - Validate resource group access

2. **Policy Compliance Issues**
   - Allow time for policy evaluation (up to 30 minutes)
   - Check policy assignment scope
   - Verify resource compatibility with policies

3. **Monitoring Data Missing**
   - Confirm Log Analytics workspace permissions
   - Check data collection rule configuration
   - Verify agent health status

### Diagnostic Commands

```bash
# Check Arc agent status
azcmagent check

# View Arc agent logs
azcmagent logs

# Test connectivity
azcmagent connect --dry-run

# Check policy extension status
kubectl get pods -n azure-policy-system
```

## Cost Optimization

### Pricing Considerations

- Azure Arc connection is free for servers and Kubernetes
- Log Analytics ingestion charges apply (~$2.30/GB)
- Policy evaluation is included at no extra cost
- Monitor data retention settings to control costs

### Cost Management

```bash
# Query log ingestion volume
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "Usage | where TimeGenerated > ago(30d) | summarize sum(Quantity) by DataType"

# Optimize data collection rules
az monitor data-collection rule update \
    --name <dcr-name> \
    --resource-group <resource-group> \
    --sampling-frequency 300  # Reduce sampling frequency
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <resource-group> --yes --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group <resource-group> \
    --name <deployment-name>
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup

If automated cleanup fails, manually disconnect Arc resources:

```bash
# Disconnect Kubernetes clusters
az connectedk8s delete \
    --name <cluster-name> \
    --resource-group <resource-group> \
    --yes

# On each server, disconnect Arc agent
azcmagent disconnect

# Delete service principal
az ad sp delete --id <service-principal-id>
```

## Customization

### Adding Custom Policies

1. Create custom policy definitions in the IaC templates
2. Modify policy assignments to include custom policies
3. Update remediation tasks for custom policy violations

### Extended Monitoring

1. Add custom performance counters to data collection rules
2. Create custom Log Analytics queries and alerts
3. Integrate with third-party monitoring tools

### Multi-Region Deployment

1. Deploy resources in multiple Azure regions
2. Configure geo-redundant Log Analytics workspaces
3. Implement cross-region policy consistency

## Advanced Configuration

### GitOps Integration

```bash
# Enable GitOps on Arc-enabled Kubernetes
az k8s-configuration create \
    --name gitops-config \
    --cluster-name <cluster-name> \
    --resource-group <resource-group> \
    --cluster-type connectedClusters \
    --repository-url <git-repo-url> \
    --scope cluster \
    --operator-params "--git-poll-interval 3m"
```

### Integration with Azure Security Center

```bash
# Enable Defender for Arc-enabled servers
az security auto-provisioning-setting update \
    --name default \
    --auto-provision on

# Configure security policies
az security assessment-metadata create \
    --name custom-assessment \
    --display-name "Custom Security Assessment" \
    --severity Medium
```

## Support and Resources

### Documentation

- [Azure Arc documentation](https://docs.microsoft.com/azure/azure-arc/)
- [Azure Policy documentation](https://docs.microsoft.com/azure/governance/policy/)
- [Azure Monitor documentation](https://docs.microsoft.com/azure/azure-monitor/)

### Community Resources

- [Azure Arc Community](https://techcommunity.microsoft.com/t5/azure-arc/bd-p/AzureArc)
- [Azure Policy Samples](https://github.com/Azure/azure-policy)
- [Azure Arc Jumpstart](https://azurearcjumpstart.io/)

### Support Channels

- Azure Support tickets for production issues
- GitHub issues for community resources
- Stack Overflow for technical questions

For issues with this infrastructure code, refer to the original recipe documentation or the Azure Arc troubleshooting guide.