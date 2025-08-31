---
title: Governed Cross-Tenant Data Collaboration with Data Share and Purview
id: 4f8c2a9d
category: analytics
difficulty: 200
subject: azure
services: Azure Data Share, Microsoft Purview, Azure Storage, Azure Active Directory
estimated-time: 120 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: data-governance, cross-tenant, data-collaboration, lineage-tracking
recipe-generator-version: 1.3
---

# Governed Cross-Tenant Data Collaboration with Data Share and Purview

## Problem

Organizations increasingly need to share datasets across business boundaries while maintaining strict governance, compliance, and visibility requirements. Traditional file-sharing methods lack proper access controls, audit trails, and data lineage tracking, creating security risks and making it difficult to demonstrate compliance with data regulations when collaborating with external partners or subsidiaries.

## Solution

Azure Data Share combined with Microsoft Purview creates a secure, governed data collaboration platform that enables organizations to share datasets across Azure tenants with full lineage tracking, access control, and unified data cataloging. This architecture provides snapshot-based or in-place sharing capabilities while maintaining complete visibility of data flows through Purview's data governance features.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Provider Tenant"
        A[Data Provider Admin]
        B[Azure Storage Account]
        C[Azure Data Share Provider]
        D[Provider Microsoft Purview]
    end
    
    subgraph "Cross-Tenant Identity"
        E[Azure AD B2B Guest Users]
        F[Cross-Tenant Access Settings]
    end
    
    subgraph "Consumer Tenant"
        G[Data Consumer Admin]
        H[Azure Storage Account]
        I[Azure Data Share Consumer]
        J[Consumer Microsoft Purview]
    end
    
    subgraph "Data Governance"
        K[Unified Data Catalog]
        L[Lineage Tracking]
        M[Classification & Labels]
    end
    
    A-->C
    C-->|1. Create Share|B
    C-->|2. Invite Consumer|E
    E-->F
    F-->I
    G-->I
    I-->|3. Accept Share|H
    D-->|4. Scan & Catalog|K
    J-->|5. Scan & Catalog|K
    K-->L
    K-->M
    
    style C fill:#50E6FF
    style I fill:#50E6FF
    style D fill:#FFB900
    style J fill:#FFB900
    style K fill:#00BCF2
```

## Prerequisites

1. Two Azure subscriptions (one for provider, one for consumer) with Owner or Contributor permissions
2. Azure CLI version 2.50.0 or later installed and configured
3. Azure AD permissions to configure B2B collaboration and cross-tenant access
4. Basic understanding of Azure storage services and data governance concepts
5. Estimated cost: ~$50-100/month for Purview instances plus storage and Data Share costs

> **Note**: Microsoft Purview requires a minimum of 1 capacity unit (CU) which incurs hourly charges. Plan your deployment schedule to minimize costs during testing.

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP_PROVIDER="rg-datashare-provider-${RANDOM_SUFFIX}"
export RESOURCE_GROUP_CONSUMER="rg-datashare-consumer-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export PROVIDER_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export CONSUMER_SUBSCRIPTION_ID="your-consumer-subscription-id"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export PROVIDER_STORAGE="stprovider${RANDOM_SUFFIX}"
export CONSUMER_STORAGE="stconsumer${RANDOM_SUFFIX}"
export PROVIDER_SHARE="share-provider-${RANDOM_SUFFIX}"
export CONSUMER_SHARE="share-consumer-${RANDOM_SUFFIX}"
export PROVIDER_PURVIEW="purview-provider-${RANDOM_SUFFIX}"
export CONSUMER_PURVIEW="purview-consumer-${RANDOM_SUFFIX}"

# Login to Azure and set provider subscription
az login
az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}

# Register required resource providers
az provider register --name "Microsoft.DataShare"
az provider register --name "Microsoft.Purview"

# Create provider resource group
az group create \
    --name ${RESOURCE_GROUP_PROVIDER} \
    --location ${LOCATION} \
    --tags purpose=datashare-demo environment=provider

echo "✅ Provider resource group created: ${RESOURCE_GROUP_PROVIDER}"
```

## Steps

1. **Create Provider Infrastructure**:

   Azure Data Share requires a storage account to host the datasets that will be shared. The provider maintains full control over access permissions and can revoke sharing at any time. Creating the storage infrastructure first establishes the foundation for secure data collaboration across tenant boundaries.

   ```bash
   # Create provider storage account
   az storage account create \
       --name ${PROVIDER_STORAGE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --location ${LOCATION} \
       --sku Standard_LRS \
       --kind StorageV2 \
       --hierarchical-namespace true
   
   # Create container for shared data
   az storage container create \
       --name shared-datasets \
       --account-name ${PROVIDER_STORAGE} \
       --auth-mode login
   
   # Create Azure Data Share account
   az datashare account create \
       --name ${PROVIDER_SHARE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --location ${LOCATION}
   
   echo "✅ Provider infrastructure created successfully"
   ```

   The provider infrastructure is now ready to host and share datasets. The hierarchical namespace enables Azure Data Lake Storage Gen2 features, providing better performance and access control for large-scale data sharing scenarios.

2. **Deploy Provider Microsoft Purview Instance**:

   Microsoft Purview provides comprehensive data governance capabilities including automated discovery, classification, and lineage tracking. Deploying Purview in the provider tenant enables centralized visibility of all shared datasets while maintaining compliance with data regulations through built-in classification and sensitivity labeling.

   ```bash
   # Create Purview account (this may take 5-10 minutes)
   az purview account create \
       --name ${PROVIDER_PURVIEW} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --location ${LOCATION} \
       --sku Standard \
       --capacity 4 \
       --identity-type SystemAssigned
   
   # Get Purview managed identity
   PROVIDER_PURVIEW_IDENTITY=$(az purview account show \
       --name ${PROVIDER_PURVIEW} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --query identity.principalId -o tsv)
   
   # Grant Purview access to storage account
   az role assignment create \
       --role "Storage Blob Data Reader" \
       --assignee ${PROVIDER_PURVIEW_IDENTITY} \
       --scope /subscriptions/${PROVIDER_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_PROVIDER}/providers/Microsoft.Storage/storageAccounts/${PROVIDER_STORAGE}
   
   echo "✅ Provider Purview instance deployed"
   ```

   The Purview instance uses system-assigned managed identity for secure authentication with storage resources. This ensures the governance platform can automatically discover and catalog shared datasets without requiring additional credential management.

3. **Configure Consumer Infrastructure**:

   The consumer tenant requires its own storage and Data Share infrastructure to receive shared datasets. This separation ensures data sovereignty and allows each organization to maintain independent control over their data infrastructure while still enabling secure collaboration through Azure's managed services.

   ```bash
   # Switch to consumer subscription
   az account set --subscription ${CONSUMER_SUBSCRIPTION_ID}
   
   # Create consumer resource group
   az group create \
       --name ${RESOURCE_GROUP_CONSUMER} \
       --location ${LOCATION} \
       --tags purpose=datashare-demo environment=consumer
   
   # Create consumer storage account
   az storage account create \
       --name ${CONSUMER_STORAGE} \
       --resource-group ${RESOURCE_GROUP_CONSUMER} \
       --location ${LOCATION} \
       --sku Standard_LRS \
       --kind StorageV2 \
       --hierarchical-namespace true
   
   # Create consumer Data Share account
   az datashare account create \
       --name ${CONSUMER_SHARE} \
       --resource-group ${RESOURCE_GROUP_CONSUMER} \
       --location ${LOCATION}
   
   echo "✅ Consumer infrastructure created successfully"
   ```

   The consumer infrastructure mirrors the provider setup to ensure compatibility and consistent management across both tenants. Data Lake Storage Gen2 capabilities are enabled on both sides to support advanced analytics workloads.

4. **Deploy Consumer Microsoft Purview Instance**:

   Deploying Purview in the consumer tenant enables the receiving organization to maintain their own data governance policies while participating in cross-tenant collaboration. This dual-Purview architecture supports federated governance models where each organization maintains autonomy while sharing common data assets.

   ```bash
   # Create consumer Purview account
   az purview account create \
       --name ${CONSUMER_PURVIEW} \
       --resource-group ${RESOURCE_GROUP_CONSUMER} \
       --location ${LOCATION} \
       --sku Standard \
       --capacity 4 \
       --identity-type SystemAssigned
   
   # Get consumer Purview managed identity
   CONSUMER_PURVIEW_IDENTITY=$(az purview account show \
       --name ${CONSUMER_PURVIEW} \
       --resource-group ${RESOURCE_GROUP_CONSUMER} \
       --query identity.principalId -o tsv)
   
   # Grant Purview access to consumer storage
   az role assignment create \
       --role "Storage Blob Data Reader" \
       --assignee ${CONSUMER_PURVIEW_IDENTITY} \
       --scope /subscriptions/${CONSUMER_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_CONSUMER}/providers/Microsoft.Storage/storageAccounts/${CONSUMER_STORAGE}
   
   echo "✅ Consumer Purview instance deployed"
   ```

   Each organization maintains independent Purview instances to ensure data governance policies can be customized according to organizational requirements while supporting collaborative data sharing scenarios.

5. **Configure Cross-Tenant B2B Collaboration**:

   Azure AD B2B collaboration enables secure guest user access across tenant boundaries. Configuring cross-tenant access settings establishes the trust relationship required for Data Share invitations while maintaining security through conditional access policies and multi-factor authentication requirements.

   ```bash
   # Switch back to provider subscription
   az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}
   
   # Get provider tenant ID
   PROVIDER_TENANT_ID=$(az account show --query tenantId -o tsv)
   
   # Get consumer tenant ID
   az account set --subscription ${CONSUMER_SUBSCRIPTION_ID}
   CONSUMER_TENANT_ID=$(az account show --query tenantId -o tsv)
   
   echo "Provider Tenant ID: ${PROVIDER_TENANT_ID}"
   echo "Consumer Tenant ID: ${CONSUMER_TENANT_ID}"
   echo ""
   echo "⚠️  Manual step required:"
   echo "1. Navigate to Azure Portal > Microsoft Entra ID > External Identities"
   echo "2. Configure Cross-tenant access settings"
   echo "3. Add ${CONSUMER_TENANT_ID} as allowed tenant"
   echo "4. Enable B2B collaboration for Data Share service"
   echo "5. Configure appropriate conditional access policies"
   ```

   Cross-tenant collaboration requires manual configuration through the Azure Portal to ensure proper security controls are established. This includes setting up conditional access policies and defining trust boundaries between organizations.

6. **Create and Configure Data Share**:

   Creating a data share establishes the sharing relationship and defines which datasets will be made available to consumers. The provider maintains full control over the share lifecycle, including the ability to add or remove datasets, set synchronization schedules, and revoke access when needed.

   ```bash
   # Switch to provider subscription
   az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}
   
   # Upload sample data to storage container
   echo "Creating sample dataset..."
   echo "Sample data for cross-tenant sharing" > sample-data.csv
   az storage blob upload \
       --account-name ${PROVIDER_STORAGE} \
       --container-name shared-datasets \
       --name sample-data.csv \
       --file sample-data.csv \
       --auth-mode login
   
   # Create a share in provider account
   az datashare create \
       --account-name ${PROVIDER_SHARE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --name "cross-tenant-dataset" \
       --description "Cross-tenant collaborative dataset" \
       --terms "Standard data sharing terms apply"
   
   # Create dataset in the share (pointing to blob container)
   az datashare dataset blob-container create \
       --account-name ${PROVIDER_SHARE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --share-name "cross-tenant-dataset" \
       --name "shared-container-dataset" \
       --container-name "shared-datasets" \
       --storage-account-name ${PROVIDER_STORAGE} \
       --subscription-id ${PROVIDER_SUBSCRIPTION_ID} \
       --resource-group ${RESOURCE_GROUP_PROVIDER}
   
   echo "✅ Data share created and configured"
   ```

   The data share is configured with a blob container dataset that includes sample data. This establishes the foundation for cross-tenant data collaboration with full provider control over access and synchronization.

7. **Configure Purview Data Scanning**:

   Purview's automated scanning capabilities discover and catalog data assets across your storage infrastructure. Configuring regular scans ensures that shared datasets are automatically discovered, classified, and tracked for lineage, providing complete visibility into data movement across tenant boundaries.

   ```bash
   # Get Purview endpoint URLs
   PROVIDER_PURVIEW_ENDPOINT="https://${PROVIDER_PURVIEW}.purview.azure.com"
   CONSUMER_PURVIEW_ENDPOINT="https://${CONSUMER_PURVIEW}.purview.azure.com"
   
   echo "Manual configuration required in Purview Studio:"
   echo "1. Open Purview Studio for ${PROVIDER_PURVIEW}"
   echo "2. Navigate to Data Map > Sources"
   echo "3. Register ${PROVIDER_STORAGE} as a data source"
   echo "4. Create a scan with weekly schedule"
   echo "5. Enable automatic classification and sensitivity labeling"
   echo ""
   echo "Provider Purview URL: ${PROVIDER_PURVIEW_ENDPOINT}"
   echo "Consumer Purview URL: ${CONSUMER_PURVIEW_ENDPOINT}"
   ```

   Purview scanning must be configured through the governance portal to establish data source connections and enable automated discovery of shared datasets with appropriate classification and labeling.

8. **Set Up Data Lineage Tracking**:

   Data lineage tracking provides end-to-end visibility of data movement from source to destination across tenant boundaries. This capability is essential for regulatory compliance and helps organizations understand the complete lifecycle of their shared data assets.

   ```bash
   echo "Configuring data lineage tracking..."
   echo ""
   echo "To enable comprehensive lineage tracking:"
   echo "1. In Provider Purview: Create lineage for source datasets"
   echo "2. In Consumer Purview: Create lineage for received datasets"
   echo "3. Use Purview REST API to establish cross-tenant lineage links"
   echo "4. Configure automated lineage updates through Data Factory"
   echo ""
   echo "REST API endpoints for lineage:"
   echo "Provider: ${PROVIDER_PURVIEW_ENDPOINT}/catalog/api/atlas/v2/lineage"
   echo "Consumer: ${CONSUMER_PURVIEW_ENDPOINT}/catalog/api/atlas/v2/lineage"
   ```

   Cross-tenant lineage tracking requires API-based configuration to establish data flow relationships between provider and consumer environments, enabling complete visibility across organizational boundaries.

## Validation & Testing

1. Verify Data Share account creation:

   ```bash
   # Check provider Data Share account
   az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}
   az datashare account show \
       --name ${PROVIDER_SHARE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --output table
   
   # Check consumer Data Share account  
   az account set --subscription ${CONSUMER_SUBSCRIPTION_ID}
   az datashare account show \
       --name ${CONSUMER_SHARE} \
       --resource-group ${RESOURCE_GROUP_CONSUMER} \
       --output table
   ```

   Expected output: Both Data Share accounts should show "Succeeded" provisioning state with active status.

2. Test Purview connectivity:

   ```bash
   # Test provider Purview endpoint
   curl -s -o /dev/null -w "%{http_code}" \
       ${PROVIDER_PURVIEW_ENDPOINT}/catalog/api/atlas/v2/types/typedefs
   
   # Test consumer Purview endpoint
   curl -s -o /dev/null -w "%{http_code}" \
       ${CONSUMER_PURVIEW_ENDPOINT}/catalog/api/atlas/v2/types/typedefs
   ```

   Expected output: HTTP 401 (requires authentication but confirms endpoint is accessible and responsive).

3. Validate storage account configuration:

   ```bash
   # Check provider storage configuration
   az storage account show \
       --name ${PROVIDER_STORAGE} \
       --resource-group ${RESOURCE_GROUP_PROVIDER} \
       --query "{name:name,location:location,sku:sku.name,kind:kind,hierarchicalNamespace:isHnsEnabled}"
   ```

   Expected output: Storage account with hierarchical namespace enabled and Standard_LRS SKU.

## Cleanup

1. Remove consumer resources:

   ```bash
   # Switch to consumer subscription
   az account set --subscription ${CONSUMER_SUBSCRIPTION_ID}
   
   # Delete consumer resource group
   az group delete \
       --name ${RESOURCE_GROUP_CONSUMER} \
       --yes \
       --no-wait
   
   echo "✅ Consumer resource group deletion initiated"
   ```

2. Remove provider resources:

   ```bash
   # Switch to provider subscription
   az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}
   
   # Delete provider resource group
   az group delete \
       --name ${RESOURCE_GROUP_PROVIDER} \
       --yes \
       --no-wait
   
   echo "✅ Provider resource group deletion initiated"
   echo "Note: Purview deletion may take 10-15 minutes to complete"
   ```

3. Clean up cross-tenant access settings:

   ```bash
   echo "Manual cleanup required:"
   echo "1. Navigate to Microsoft Entra ID > External Identities > Cross-tenant access"
   echo "2. Remove the configured tenant access settings"
   echo "3. Review and remove any guest users created during testing"
   echo "4. Clean up any conditional access policies created for B2B collaboration"
   ```

## Discussion

Azure Data Share combined with Microsoft Purview creates a comprehensive data collaboration platform that addresses the complex requirements of cross-organizational data sharing. This architecture leverages Azure's native B2B collaboration capabilities to enable secure data exchange while maintaining complete governance oversight. The solution follows the [Azure Well-Architected Framework security pillar](https://docs.microsoft.com/en-us/azure/architecture/framework/security/overview) by implementing defense-in-depth security through multiple layers of access control and encryption.

The dual-Purview deployment model supports federated governance scenarios where each organization maintains autonomous control over their data assets while participating in collaborative data sharing. This approach aligns with [Microsoft Purview unified data governance principles](https://docs.microsoft.com/en-us/purview/governance-solutions-overview) by providing centralized visibility without compromising organizational boundaries. The snapshot-based sharing mechanism ensures data consistency and provides point-in-time recovery capabilities essential for regulatory compliance.

From a security perspective, this solution implements Microsoft's Zero Trust architecture principles through Azure AD conditional access, storage-level encryption, and Purview's sensitivity labeling capabilities. Organizations can enhance security further by implementing Azure Private Endpoints for both Purview and Data Share services, ensuring that data governance traffic remains within Microsoft's backbone network. For detailed guidance on cross-tenant collaboration security, refer to the [Azure External Identities documentation](https://docs.microsoft.com/en-us/azure/active-directory/external-identities/cross-tenant-access-overview).

Cost optimization is achieved through Purview's consumption-based pricing model and Data Share's pay-per-snapshot approach. Organizations should carefully plan their scanning schedules and share synchronization frequencies to balance data freshness requirements with operational costs. The new pay-as-you-go billing model for Microsoft Purview, effective January 2025, provides more granular cost control for data governance operations. For comprehensive cost management strategies, refer to the [Azure cost optimization documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-best-practices).

> **Tip**: Use Microsoft Purview's business glossary feature to establish common data terminology across organizations, improving collaboration effectiveness and reducing miscommunication in cross-tenant scenarios. This becomes especially valuable when dealing with different industry standards or regulatory requirements.

## Challenge

Extend this solution by implementing these enhancements:

1. Implement automated data quality validation using Microsoft Purview's data quality rules before sharing datasets across tenants, ensuring only high-quality data is shared
2. Create a Power BI dashboard that visualizes cross-tenant data lineage and sharing patterns using Purview's REST APIs and Microsoft Graph
3. Add Azure Key Vault integration to manage encryption keys for sensitive datasets with customer-managed key (CMK) support for both storage accounts
4. Implement event-driven notifications using Azure Event Grid when new datasets are shared, lineage is updated, or data quality issues are detected
5. Build a custom approval workflow using Azure Logic Apps that requires management sign-off before sensitive data can be shared externally, with integration to Microsoft Teams for notifications

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*