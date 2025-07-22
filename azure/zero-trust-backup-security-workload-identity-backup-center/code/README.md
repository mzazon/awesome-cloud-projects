# Infrastructure as Code for Zero-Trust Backup Security with Workload Identity and Backup Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Trust Backup Security with Workload Identity and Backup Center".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI version 2.45.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- PowerShell Core 7.0+ (for some advanced features)
- OpenSSL for generating random values
- Understanding of zero-trust security principles and Azure identity management
- Familiarity with Azure Backup services and Recovery Services Vaults

### Required Azure Resource Providers

Ensure the following resource providers are registered in your subscription:

```bash
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.RecoveryServices
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
```

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-zerotrust-backup \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                 environment=demo \
                 randomSuffix=$(openssl rand -hex 3)

# Verify deployment
az deployment group show \
    --resource-group rg-zerotrust-backup \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the planned changes
terraform plan -var="location=eastus" -var="environment=demo"

# Apply the configuration
terraform apply -var="location=eastus" -var="environment=demo"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment (optional)
./scripts/verify.sh
```

## Architecture Overview

This infrastructure deploys a comprehensive zero-trust backup security solution including:

- **Azure Key Vault**: Secure storage for backup secrets and certificates
- **User-Assigned Managed Identity**: Workload identity for secretless authentication
- **Recovery Services Vault**: Centralized backup infrastructure with advanced security
- **Azure Backup Center**: Unified backup management and monitoring
- **Test Virtual Machine**: Demonstration of backup protection capabilities
- **Network Security**: Virtual network with proper security controls
- **Storage Account**: Backup reports and monitoring data storage

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `environment` | Environment tag (demo, dev, prod) | `demo` | Yes |
| `randomSuffix` | Unique suffix for resource names | Generated | No |
| `keyVaultSku` | Key Vault pricing tier | `premium` | No |
| `vmSize` | Virtual machine size | `Standard_B2s` | No |
| `backupRetentionDays` | Backup retention period | `30` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `environment` | Environment tag | `demo` | Yes |
| `resource_group_name` | Resource group name | Generated | No |
| `key_vault_sku` | Key Vault pricing tier | `premium` | No |
| `vm_size` | Virtual machine size | `Standard_B2s` | No |
| `backup_retention_days` | Backup retention period | `30` | No |

### Bash Script Environment Variables

Set these environment variables before running the deployment script:

```bash
export LOCATION="eastus"
export ENVIRONMENT="demo"
export RESOURCE_GROUP="rg-zerotrust-backup-$(openssl rand -hex 3)"
```

## Security Features

### Zero-Trust Implementation

- **Secretless Authentication**: Uses workload identity federation instead of stored credentials
- **Least Privilege Access**: RBAC-based permissions with minimal required access
- **Network Isolation**: Private endpoints and firewall rules where applicable
- **Encryption**: All data encrypted at rest and in transit
- **Audit Logging**: Comprehensive logging for all backup operations

### Key Security Controls

- Key Vault with purge protection and soft delete enabled
- Recovery Services Vault with geo-redundant storage and cross-region restore
- User-assigned managed identity with federated credentials
- Network security groups with restricted access
- Immutable backup policies with long-term retention

## Post-Deployment Configuration

### Enable Workload Identity Federation

After deployment, configure federated credentials for your external identity providers:

```bash
# For GitHub Actions
az identity federated-credential create \
    --name "github-actions-fed-cred" \
    --identity-name "${WORKLOAD_IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:organization/repository:ref:refs/heads/main" \
    --audience "api://AzureADTokenExchange"

# For Kubernetes workloads
az identity federated-credential create \
    --name "k8s-backup-fed-cred" \
    --identity-name "${WORKLOAD_IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --issuer "https://kubernetes.default.svc.cluster.local" \
    --subject "system:serviceaccount:backup-system:backup-operator" \
    --audience "api://AzureADTokenExchange"
```

### Configure Backup Policies

The infrastructure creates default backup policies. Customize them based on your requirements:

```bash
# List available backup policies
az backup policy list \
    --vault-name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}"

# Modify backup policy if needed
az backup policy set \
    --vault-name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --policy-name "ZeroTrustVMPolicy" \
    --policy @updated-policy.json
```

## Monitoring and Validation

### Health Checks

```bash
# Check Key Vault status
az keyvault show \
    --name "${KEY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query properties.provisioningState

# Verify backup protection
az backup item list \
    --vault-name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output table

# Check workload identity status
az identity show \
    --name "${WORKLOAD_IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query provisioningState
```

### Test Backup Operations

```bash
# Trigger on-demand backup
az backup protection backup-now \
    --vault-name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --container-name "${VM_NAME}" \
    --item-name "${VM_NAME}" \
    --backup-management-type AzureIaasVM \
    --workload-type VM

# Monitor backup job
az backup job list \
    --vault-name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --operation Backup \
    --status InProgress
```

## Troubleshooting

### Common Issues

1. **Key Vault Access Denied**
   - Verify RBAC permissions are correctly assigned
   - Check if the user has Key Vault Administrator role
   - Ensure the managed identity has proper permissions

2. **Backup Job Failures**
   - Verify VM is running and accessible
   - Check backup policy configuration
   - Review Recovery Services Vault permissions

3. **Workload Identity Federation Issues**
   - Validate federated credential configuration
   - Check issuer and subject claim mappings
   - Verify audience configuration

### Debugging Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "main" \
    --query properties.provisioningState

# Review activity logs
az monitor activity-log list \
    --resource-group "${RESOURCE_GROUP}" \
    --max-events 50 \
    --output table

# Check Key Vault access policies
az keyvault show \
    --name "${KEY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query properties.accessPolicies
```

## Cost Optimization

### Estimated Monthly Costs

- Key Vault Premium: ~$1.25/month
- Recovery Services Vault: ~$5-20/month (depends on backup storage)
- Virtual Machine (B2s): ~$30/month
- Storage Account: ~$2-5/month
- Managed Identity: Free
- **Total Estimated**: $40-60/month for lab environment

### Cost Optimization Tips

1. **Right-size Resources**: Use appropriate VM sizes for your workload
2. **Backup Storage**: Consider backup retention policies and storage redundancy
3. **Dev/Test Environments**: Use Azure Dev/Test pricing for non-production workloads
4. **Auto-shutdown**: Configure VM auto-shutdown for development environments

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-zerotrust-backup \
    --yes \
    --no-wait

# Purge Key Vault (required due to purge protection)
az keyvault purge \
    --name "${KEY_VAULT_NAME}" \
    --location "${LOCATION}"
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" -var="environment=demo"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
az group list --query "[?name=='rg-zerotrust-backup']" --output table
```

## Security Best Practices

### Production Deployment Recommendations

1. **Network Security**
   - Use private endpoints for Key Vault and Storage Account
   - Implement network security groups with minimal required access
   - Consider Azure Firewall for additional network protection

2. **Identity and Access Management**
   - Use conditional access policies for administrative access
   - Implement privileged identity management (PIM)
   - Regular review of federated credentials and permissions

3. **Backup Security**
   - Enable cross-region restore for disaster recovery
   - Implement backup encryption with customer-managed keys
   - Regular testing of backup and restore procedures

4. **Monitoring and Alerting**
   - Configure Azure Monitor alerts for backup failures
   - Implement security monitoring with Azure Sentinel
   - Regular review of audit logs and access patterns

## Advanced Configuration

### Custom Backup Policies

Create custom backup policies for specific workload requirements:

```json
{
  "schedulePolicy": {
    "schedulePolicyType": "SimpleSchedulePolicy",
    "scheduleRunFrequency": "Weekly",
    "scheduleRunDays": ["Sunday", "Wednesday"],
    "scheduleRunTimes": ["2024-01-01T02:00:00Z"]
  },
  "retentionPolicy": {
    "retentionPolicyType": "LongTermRetentionPolicy",
    "weeklySchedule": {
      "daysOfTheWeek": ["Sunday"],
      "retentionTimes": ["2024-01-01T02:00:00Z"],
      "retentionDuration": {
        "count": 52,
        "durationType": "Weeks"
      }
    },
    "monthlySchedule": {
      "retentionScheduleFormatType": "Weekly",
      "retentionScheduleWeekly": {
        "daysOfTheWeek": ["Sunday"],
        "weeksOfTheMonth": ["First"]
      },
      "retentionTimes": ["2024-01-01T02:00:00Z"],
      "retentionDuration": {
        "count": 24,
        "durationType": "Months"
      }
    }
  }
}
```

### Cross-Region Backup Configuration

Enable cross-region restore for disaster recovery:

```bash
# Enable cross-region restore
az backup vault backup-properties set \
    --name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --cross-region-restore-flag true

# Configure geo-redundant storage
az backup vault backup-properties set \
    --name "${RECOVERY_VAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --backup-storage-redundancy GeoRedundant
```

## Integration Examples

### GitHub Actions Integration

```yaml
name: Zero-Trust Backup Operations
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  backup-operations:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Trigger Backup
        run: |
          az backup protection backup-now \
            --vault-name "${RECOVERY_VAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --container-name "${VM_NAME}" \
            --item-name "${VM_NAME}" \
            --backup-management-type AzureIaasVM \
            --workload-type VM
```

### Kubernetes Integration

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-operator
  namespace: backup-system
  annotations:
    azure.workload.identity/client-id: "${WORKLOAD_IDENTITY_CLIENT_ID}"
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-operations
  namespace: backup-system
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            azure.workload.identity/use: "true"
        spec:
          serviceAccountName: backup-operator
          containers:
          - name: backup-operator
            image: mcr.microsoft.com/azure-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              az backup protection backup-now \
                --vault-name "${RECOVERY_VAULT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --container-name "${VM_NAME}" \
                --item-name "${VM_NAME}" \
                --backup-management-type AzureIaasVM \
                --workload-type VM
```

## Support and Documentation

### Additional Resources

- [Azure Backup Center Documentation](https://docs.microsoft.com/en-us/azure/backup/backup-center-overview)
- [Azure Workload Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation)
- [Azure Key Vault Security Guide](https://docs.microsoft.com/en-us/azure/key-vault/general/security-overview)
- [Azure Zero Trust Implementation Guide](https://docs.microsoft.com/en-us/security/zero-trust/azure-infrastructure-overview)

### Community Support

- [Azure Backup Community Forum](https://docs.microsoft.com/en-us/answers/topics/azure-backup.html)
- [Azure Security Community](https://techcommunity.microsoft.com/t5/azure-security/ct-p/AzureSecurityCommunity)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)

For issues with this infrastructure code, refer to the original recipe documentation or submit an issue to the repository.