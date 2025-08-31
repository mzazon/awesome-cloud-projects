---
title: Simple URL Shortener with Functions and Table Storage
id: 7a8b9c2d
category: serverless
difficulty: 100
subject: azure
services: Azure Functions, Azure Table Storage
estimated-time: 20 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: serverless, url-shortener, http-api, nosql, beginner
recipe-generator-version: 1.3
---

# Simple URL Shortener with Functions and Table Storage

## Problem

Small businesses and content creators need to share long, complex URLs on social media and in marketing materials, but character limits and user experience concerns make this challenging. They require a simple, cost-effective URL shortening service that doesn't involve managing servers or complex infrastructure, while ensuring reliable redirection and basic analytics capabilities.

## Solution

Build a serverless URL shortening service using Azure Functions for HTTP endpoints and Azure Table Storage for data persistence. This approach provides automatic scaling, minimal operational overhead, and pay-per-use pricing while delivering the core functionality needed for URL shortening and redirection.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        USER[Web Browser/Client]
    end
    
    subgraph "Azure Functions"
        SHORTEN[Shorten Function<br/>HTTP POST]
        REDIRECT[Redirect Function<br/>HTTP GET]
    end
    
    subgraph "Storage Layer"
        TABLE[Azure Table Storage<br/>URL Mappings]
    end
    
    USER -->|1. POST /api/shorten| SHORTEN
    USER -->|3. GET /{shortCode}| REDIRECT
    
    SHORTEN -->|2. Store mapping| TABLE
    REDIRECT -->|4. Lookup URL| TABLE
    REDIRECT -->|5. HTTP 302 Redirect| USER
    
    style SHORTEN fill:#FF9900
    style REDIRECT fill:#FF9900
    style TABLE fill:#3F8624
```

## Prerequisites

1. Azure account with active subscription and permissions to create Function Apps and Storage Accounts
2. Azure CLI installed and configured (version 2.60.0 or later)
3. Basic understanding of HTTP APIs and NoSQL concepts
4. Node.js 18+ for local development (optional but recommended)
5. Estimated cost: $0.10-$0.50 per month for development/testing usage

> **Note**: This recipe uses Azure's consumption-based pricing model, making it ideal for low-volume applications and learning scenarios.

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-url-shortener-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set specific resource names
export STORAGE_ACCOUNT="urlstore${RANDOM_SUFFIX}"
export FUNCTION_APP="url-shortener-${RANDOM_SUFFIX}"
export TABLE_NAME="urlmappings"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=recipe environment=demo

echo "✅ Resource group created: ${RESOURCE_GROUP}"

# Create storage account for both Function App and Table Storage
az storage account create \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Standard_LRS \
    --kind StorageV2

echo "✅ Storage account created: ${STORAGE_ACCOUNT}"
```

## Steps

1. **Create Function App with Consumption Plan**:

   Azure Functions provides serverless compute that automatically scales based on demand, making it perfect for URL shortening services with unpredictable traffic patterns. The consumption plan ensures you only pay for actual function executions, with generous free tier allowances (1 million requests monthly) for development and low-volume scenarios.

   ```bash
   # Create Function App using consumption plan
   az functionapp create \
       --resource-group ${RESOURCE_GROUP} \
       --consumption-plan-location ${LOCATION} \
       --runtime node \
       --runtime-version 20 \
       --functions-version 4 \
       --name ${FUNCTION_APP} \
       --storage-account ${STORAGE_ACCOUNT} \
       --disable-app-insights false
   
   echo "✅ Function App created: ${FUNCTION_APP}"
   ```

   The Function App is now provisioned with Application Insights for monitoring and uses the latest Node.js 20 LTS runtime. This configuration provides optimal performance and built-in observability for debugging and performance optimization.

2. **Configure Storage Account Connection**:

   Azure Table Storage provides a NoSQL key-value store that's ideal for simple URL mapping scenarios. Unlike relational databases, Table Storage offers schema-less design and automatic scaling, making it perfect for storing URL mappings with minimal configuration overhead. Table Storage uses partition and row keys for efficient data distribution and fast point queries.

   ```bash
   # Get storage account connection string
   STORAGE_CONNECTION=$(az storage account show-connection-string \
       --name ${STORAGE_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --query connectionString \
       --output tsv)
   
   # Configure Function App with storage connection
   az functionapp config appsettings set \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --settings "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}"
   
   echo "✅ Storage connection configured"
   ```

3. **Create URL Mappings Table**:

   ```bash
   # Create table for storing URL mappings
   az storage table create \
       --name ${TABLE_NAME} \
       --connection-string "${STORAGE_CONNECTION}"
   
   echo "✅ Table created: ${TABLE_NAME}"
   ```

4. **Deploy URL Shortening Function**:

   The shortening function generates unique short codes and stores URL mappings in Table Storage. This function implements best practices for NoSQL design by using the short code as both partition key and row key, ensuring optimal query performance for URL lookups. The Azure Functions v4 programming model uses a code-first approach, eliminating the need for separate function.json configuration files.

   ```bash
   # Create temporary directory for function code
   mkdir -p /tmp/url-shortener-functions
   cd /tmp/url-shortener-functions
   
   # Create package.json with updated dependencies
   cat > package.json << 'EOF'
   {
     "name": "url-shortener-functions",
     "version": "1.0.0",
     "main": "src/functions/*.js",
     "dependencies": {
       "@azure/functions": "^4.5.1",
       "@azure/data-tables": "^13.3.1"
     },
     "devDependencies": {}
   }
   EOF
   
   # Create source directory structure
   mkdir -p src/functions
   
   # Create shorten function using v4 programming model
   cat > src/functions/shorten.js << 'EOF'
   const { app } = require('@azure/functions');
   const { TableClient } = require('@azure/data-tables');
   
   app.http('shorten', {
       methods: ['POST'],
       authLevel: 'anonymous',
       handler: async (request, context) => {
           try {
               const body = await request.json();
               const originalUrl = body.url;
   
               if (!originalUrl) {
                   return {
                       status: 400,
                       jsonBody: { error: 'URL is required' }
                   };
               }
   
               // Validate URL format
               try {
                   new URL(originalUrl);
               } catch {
                   return {
                       status: 400,
                       jsonBody: { error: 'Invalid URL format' }
                   };
               }
   
               // Generate short code (6 characters)
               const shortCode = Math.random().toString(36).substring(2, 8);
   
               // Initialize Table client
               const tableClient = TableClient.fromConnectionString(
                   process.env.STORAGE_CONNECTION_STRING,
                   'urlmappings'
               );
   
               // Store URL mapping
               const entity = {
                   partitionKey: shortCode,
                   rowKey: shortCode,
                   originalUrl: originalUrl,
                   createdAt: new Date().toISOString(),
                   clickCount: 0
               };
   
               await tableClient.createEntity(entity);
   
               return {
                   status: 201,
                   jsonBody: {
                       shortCode: shortCode,
                       shortUrl: `https://${request.headers.get('host')}/api/${shortCode}`,
                       originalUrl: originalUrl
                   }
               };
           } catch (error) {
               context.error('Error in shorten function:', error);
               return {
                   status: 500,
                   jsonBody: { error: 'Internal server error' }
               };
           }
       }
   });
   EOF
   
   echo "✅ Shorten function created"
   ```

5. **Deploy URL Redirect Function**:

   The redirect function performs efficient point queries against Table Storage using the short code as the key. This design pattern ensures minimal latency for URL lookups and automatic HTTP redirection to the original URL. The function also implements basic analytics by incrementing a click counter, demonstrating atomic update operations in Table Storage.

   ```bash
   # Create redirect function using v4 programming model
   cat > src/functions/redirect.js << 'EOF'
   const { app } = require('@azure/functions');
   const { TableClient } = require('@azure/data-tables');
   
   app.http('redirect', {
       methods: ['GET'],
       authLevel: 'anonymous',
       route: '{shortCode}',
       handler: async (request, context) => {
           try {
               const shortCode = request.params.shortCode;
   
               if (!shortCode) {
                   return {
                       status: 400,
                       jsonBody: { error: 'Short code is required' }
                   };
               }
   
               // Initialize Table client
               const tableClient = TableClient.fromConnectionString(
                   process.env.STORAGE_CONNECTION_STRING,
                   'urlmappings'
               );
   
               // Lookup URL mapping
               const entity = await tableClient.getEntity(shortCode, shortCode);
   
               if (!entity) {
                   return {
                       status: 404,
                       jsonBody: { error: 'Short URL not found' }
                   };
               }
   
               // Increment click count (optional analytics)
               entity.clickCount = (entity.clickCount || 0) + 1;
               await tableClient.updateEntity(entity, 'Replace');
   
               // Redirect to original URL
               return {
                   status: 302,
                   headers: {
                       'Location': entity.originalUrl,
                       'Cache-Control': 'no-cache'
                   }
               };
           } catch (error) {
               if (error.statusCode === 404) {
                   return {
                       status: 404,
                       jsonBody: { error: 'Short URL not found' }
                   };
               }
               
               context.error('Error in redirect function:', error);
               return {
                   status: 500,
                   jsonBody: { error: 'Internal server error' }
               };
           }
       }
   });
   EOF
   
   echo "✅ Redirect function created"
   ```

6. **Create Host Configuration**:

   The host.json file configures Function App runtime settings including timeout, logging, and extension bundles. This configuration enables Application Insights telemetry sampling and sets appropriate timeouts for HTTP-triggered functions.

   ```bash
   # Create host.json for Function App configuration
   cat > host.json << 'EOF'
   {
     "version": "2.0",
     "functionTimeout": "00:05:00",
     "logging": {
       "applicationInsights": {
         "samplingSettings": {
           "isEnabled": true
         }
       }
     },
     "extensionBundle": {
       "id": "Microsoft.Azure.Functions.ExtensionBundle",
       "version": "[4.*, 5.0.0)"
     }
   }
   EOF
   
   echo "✅ Host configuration created"
   ```

7. **Deploy Functions to Azure**:

   ```bash
   # Create deployment package
   zip -r function-app.zip . -x "*.git*" "node_modules/*"
   
   # Deploy to Function App
   az functionapp deployment source config-zip \
       --resource-group ${RESOURCE_GROUP} \
       --name ${FUNCTION_APP} \
       --src function-app.zip
   
   # Wait for deployment to complete
   sleep 30
   
   echo "✅ Functions deployed successfully"
   
   # Get Function App URL
   FUNCTION_URL=$(az functionapp show \
       --resource-group ${RESOURCE_GROUP} \
       --name ${FUNCTION_APP} \
       --query defaultHostName \
       --output tsv)
   
   echo "Function App URL: https://${FUNCTION_URL}"
   ```

## Validation & Testing

1. **Test URL Shortening Function**:

   ```bash
   # Test creating a short URL
   curl -X POST "https://${FUNCTION_URL}/api/shorten" \
        -H "Content-Type: application/json" \
        -d '{"url": "https://learn.microsoft.com/en-us/azure/azure-functions/"}'
   ```

   Expected output: JSON response with shortCode, shortUrl, and originalUrl fields.

2. **Test URL Redirection**:

   ```bash
   # Extract short code from previous response and test redirect
   # Replace 'abc123' with actual short code from step 1
   curl -I "https://${FUNCTION_URL}/api/abc123"
   ```

   Expected output: HTTP 302 redirect response with Location header pointing to original URL.

3. **Verify Table Storage Data**:

   ```bash
   # List entities in the URL mappings table
   az storage entity query \
       --table-name ${TABLE_NAME} \
       --connection-string "${STORAGE_CONNECTION}"
   ```

   Expected output: Table entities showing URL mappings with click counts.

## Cleanup

1. **Remove Function App and associated resources**:

   ```bash
   # Delete the entire resource group and all contained resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
   echo "Note: Deletion may take several minutes to complete"
   ```

2. **Clean up local files**:

   ```bash
   # Remove temporary function code directory
   rm -rf /tmp/url-shortener-functions
   
   # Unset environment variables
   unset RESOURCE_GROUP LOCATION STORAGE_ACCOUNT FUNCTION_APP TABLE_NAME STORAGE_CONNECTION
   
   echo "✅ Local cleanup completed"
   ```

## Discussion

This URL shortener implementation demonstrates the power of serverless architecture using Azure Functions and Table Storage. The solution follows Azure Well-Architected Framework principles by leveraging managed services that automatically handle scaling, availability, and maintenance overhead. Azure Functions provides event-driven compute that scales from zero to handle traffic spikes, while Table Storage offers a cost-effective NoSQL solution optimized for key-value lookups.

The architecture uses efficient Table Storage design patterns by implementing the short code as both partition key and row key, enabling optimal point queries with minimal latency. This NoSQL approach is particularly well-suited for URL shortening services because it eliminates the overhead of relational database schemas while providing the fast lookups required for redirect operations. The solution also includes basic analytics through click counting, demonstrating how NoSQL entities can be updated atomically.

The updated implementation uses Azure Functions v4 programming model, which provides a code-first approach that eliminates the need for separate function.json configuration files. This modern approach simplifies development and deployment while maintaining full compatibility with the Azure Functions runtime. The Node.js 20 LTS runtime ensures long-term support and optimal performance for production workloads.

From a cost perspective, this serverless approach is highly economical for variable workloads. Azure Functions consumption plan provides 1 million free requests monthly, while Table Storage charges only for actual storage used and operations performed. This makes the solution ideal for startups, side projects, or applications with unpredictable traffic patterns.

For more information on Azure Functions best practices, see [Azure Functions best practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices). Table Storage design guidance is available in the [Performance and scalability checklist for Table storage](https://learn.microsoft.com/en-us/azure/storage/tables/storage-performance-checklist).

> **Tip**: Use Azure Monitor and Application Insights to track performance metrics and optimize resource allocation based on actual usage patterns and Azure Advisor recommendations.

## Challenge

Extend this solution by implementing these enhancements:

1. **Custom Short Codes**: Allow users to specify custom short codes instead of random generation, with validation to prevent conflicts and reserved keywords using Table Storage conditional operations.

2. **Expiration Dates**: Add TTL (Time-To-Live) functionality to automatically expire short URLs after a specified period, implementing cleanup using Azure Functions timer triggers and Table Storage batch operations.

3. **Analytics Dashboard**: Create a separate function to retrieve click statistics and build a simple web interface using Azure Static Web Apps to display URL performance metrics with real-time updates.

4. **Rate Limiting**: Implement rate limiting using Azure API Management or custom middleware with Redis cache to prevent abuse and manage API quotas per client IP address.

5. **QR Code Generation**: Integrate Azure Cognitive Services or third-party APIs to generate QR codes for shortened URLs, storing them in Azure Blob Storage for efficient retrieval and caching.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Bicep](code/bicep/) - Azure Bicep templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using Azure CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files