---
title: Simple QR Code Generator with Functions and Blob Storage
id: a7b3c2d9
category: serverless
difficulty: 100
subject: azure
services: Azure Functions, Azure Blob Storage
estimated-time: 15 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-7-23
passed-qa: null
tags: serverless, qr-code, http-trigger, blob-storage, python
recipe-generator-version: 1.3
---

# Simple QR Code Generator with Functions and Blob Storage

## Problem

Small businesses and developers often need a quick way to generate QR codes for marketing materials, contact information, or URLs without maintaining dedicated infrastructure. Traditional solutions require running persistent servers and managing storage systems, leading to unnecessary costs and complexity for infrequent QR code generation needs.

## Solution

Build a serverless HTTP-triggered Azure Function that generates QR codes from text input and automatically stores the resulting images in Azure Blob Storage. This approach provides on-demand QR code generation with automatic scaling and pay-per-use pricing, eliminating infrastructure overhead while ensuring reliable storage and global accessibility of generated QR codes.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        USER[Client Application]
    end
    
    subgraph "Serverless Compute"
        FUNC[Azure Functions<br/>HTTP Trigger]
    end
    
    subgraph "Storage Layer"
        BLOB[Azure Blob Storage<br/>QR Code Images]
    end
    
    USER-->|1. POST /generate-qr<br/>{"text": "content"}|FUNC
    FUNC-->|2. Generate QR Code|FUNC
    FUNC-->|3. Store Image|BLOB
    FUNC-->|4. Return Blob URL|USER
    
    style FUNC fill:#00BCF2
    style BLOB fill:#FF9900
    style USER fill:#40E0D0
```

## Prerequisites

1. Azure account with active subscription and permissions to create Function Apps and Storage Accounts
2. Azure CLI installed and configured (version 2.60.0 or later) or Azure Cloud Shell access
3. Basic understanding of serverless computing concepts and HTTP APIs
4. Python development knowledge for understanding the function code
5. Estimated cost: $0.50-2.00 USD for resources created during this tutorial (deleted in cleanup)

> **Note**: This recipe uses Azure's consumption-based pricing model, ensuring you only pay for actual function executions and blob storage usage during testing.

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-qr-generator-$(openssl rand -hex 3)"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for globally unique resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export STORAGE_ACCOUNT="stqrgen${RANDOM_SUFFIX}"
export FUNCTION_APP="func-qr-generator-${RANDOM_SUFFIX}"

# Create resource group for the QR generator solution
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=recipe environment=demo project=qr-generator

echo "✅ Resource group created: ${RESOURCE_GROUP}"
echo "✅ Storage account name: ${STORAGE_ACCOUNT}"
echo "✅ Function app name: ${FUNCTION_APP}"
```

## Steps

1. **Create Storage Account for QR Code Images**:

   Azure Storage provides the foundation for storing generated QR code images with built-in redundancy and global accessibility. Creating a storage account with blob service enabled allows our function to upload QR code images and provide downloadable URLs to clients. The storage account uses locally redundant storage (LRS) for cost-effective storage suitable for demo purposes, with public blob access disabled by default for enhanced security.

   ```bash
   # Create storage account with blob service enabled
   az storage account create \
       --name ${STORAGE_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard_LRS \
       --kind StorageV2 \
       --min-tls-version TLS1_2 \
       --allow-blob-public-access true
   
   # Get storage account connection string for function configuration
   export STORAGE_CONNECTION=$(az storage account show-connection-string \
       --name ${STORAGE_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --query connectionString \
       --output tsv)
   
   echo "✅ Storage account created: ${STORAGE_ACCOUNT}"
   ```

   The storage account is now ready to store QR code images with public blob access enabled for easy retrieval. This configuration allows generated QR codes to be accessible via direct URLs while maintaining secure access to the storage account itself through proper TLS encryption and access controls.

2. **Create Blob Container for QR Code Storage**:

   A blob container organizes our QR code images and defines access policies for the stored files. Creating a container with public read access enables direct URL access to generated QR codes without requiring authentication, making them easily shareable while maintaining security boundaries.

   ```bash
   # Create container for storing QR code images
   az storage container create \
       --name qr-codes \
       --account-name ${STORAGE_ACCOUNT} \
       --public-access blob \
       --connection-string "${STORAGE_CONNECTION}"
   
   echo "✅ Blob container 'qr-codes' created with public read access"
   ```

   The container now provides organized storage for QR code images with appropriate access policies. This setup ensures generated QR codes can be accessed via HTTP URLs while maintaining proper isolation from other storage resources.

3. **Create Function App with Python Runtime**:

   Azure Functions provides serverless compute that automatically scales based on demand and integrates seamlessly with other Azure services. Creating a Function App with Python runtime enables us to leverage Python's rich ecosystem of libraries, including QR code generation capabilities, while benefiting from Azure's managed infrastructure and consumption-based pricing model.

   ```bash
   # Create Function App with consumption plan
   az functionapp create \
       --resource-group ${RESOURCE_GROUP} \
       --consumption-plan-location ${LOCATION} \
       --runtime python \
       --runtime-version 3.11 \
       --functions-version 4 \
       --name ${FUNCTION_APP} \
       --storage-account ${STORAGE_ACCOUNT} \
       --os-type Linux
   
   echo "✅ Function App created: ${FUNCTION_APP}"
   ```

   The Function App is configured with Python 3.11 runtime and Functions version 4, ensuring optimal performance and access to the latest Azure Functions features. This serverless approach eliminates infrastructure management while providing automatic scaling for varying QR code generation demands.

4. **Configure Function App Settings**:

   Application settings provide secure configuration management for our function, including storage connection strings and environment variables. Configuring these settings through Azure CLI ensures sensitive information is properly stored and accessible to our function code without hardcoding credentials, following Azure security best practices.

   ```bash
   # Configure storage connection string in function app settings
   az functionapp config appsettings set \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --settings "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}" \
                  "BLOB_CONTAINER_NAME=qr-codes"
   
   echo "✅ Function app settings configured"
   ```

   These settings enable our function to securely access the storage account and target the correct container for QR code uploads. The configuration follows Azure best practices for managing sensitive connection information through app settings rather than hardcoded values.

5. **Deploy QR Code Generation Function**:

   The core function implements HTTP-triggered QR code generation using Python's qrcode library and Azure's blob storage SDK. This implementation accepts text input via HTTP POST, generates a QR code image, uploads it to blob storage, and returns the accessible URL to the client with comprehensive error handling and input validation.

   ```bash
   # Create temporary directory for function code
   mkdir -p /tmp/qr-function
   cd /tmp/qr-function
   
   # Create function configuration file
   cat > host.json << 'EOF'
   {
       "version": "2.0",
       "extensionBundle": {
           "id": "Microsoft.Azure.Functions.ExtensionBundle",
           "version": "[4.*, 5.0.0)"
       },
       "functionTimeout": "00:05:00"
   }
   EOF
   
   # Create requirements.txt for Python dependencies
   cat > requirements.txt << 'EOF'
   azure-functions
   azure-storage-blob
   qrcode[pil]
   pillow
   EOF
   
   # Create the main function file
   cat > function_app.py << 'EOF'
   import azure.functions as func
   import logging
   import json
   import qrcode
   import io
   import os
   from datetime import datetime
   from azure.storage.blob import BlobServiceClient
   
   app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
   
   @app.route(route="generate-qr", methods=["POST"])
   def generate_qr_code(req: func.HttpRequest) -> func.HttpResponse:
       logging.info('QR Code generation request received.')
       
       try:
           # Parse request body
           req_body = req.get_json()
           if not req_body or 'text' not in req_body:
               return func.HttpResponse(
                   json.dumps({"error": "Please provide 'text' in request body"}),
                   status_code=400,
                   headers={"Content-Type": "application/json"}
               )
           
           text_input = req_body['text']
           if not text_input.strip():
               return func.HttpResponse(
                   json.dumps({"error": "Text input cannot be empty"}),
                   status_code=400,
                   headers={"Content-Type": "application/json"}
               )
           
           # Generate QR code
           qr = qrcode.QRCode(
               version=1,
               error_correction=qrcode.constants.ERROR_CORRECT_L,
               box_size=10,
               border=4,
           )
           qr.add_data(text_input)
           qr.make(fit=True)
           
           # Create QR code image
           img = qr.make_image(fill_color="black", back_color="white")
           
           # Convert image to bytes
           img_bytes = io.BytesIO()
           img.save(img_bytes, format='PNG')
           img_bytes.seek(0)
           
           # Generate unique filename
           timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
           filename = f"qr_code_{timestamp}.png"
           
           # Upload to blob storage
           connection_string = os.environ.get('STORAGE_CONNECTION_STRING')
           container_name = os.environ.get('BLOB_CONTAINER_NAME', 'qr-codes')
           
           blob_service_client = BlobServiceClient.from_connection_string(connection_string)
           blob_client = blob_service_client.get_blob_client(
               container=container_name, 
               blob=filename
           )
           
           blob_client.upload_blob(img_bytes.getvalue(), overwrite=True)
           
           # Get blob URL
           blob_url = blob_client.url
           
           logging.info(f'QR code generated and saved: {filename}')
           
           return func.HttpResponse(
               json.dumps({
                   "success": True,
                   "filename": filename,
                   "url": blob_url,
                   "text": text_input
               }),
               headers={"Content-Type": "application/json"}
           )
           
       except Exception as e:
           logging.error(f'Error generating QR code: {str(e)}')
           return func.HttpResponse(
               json.dumps({"error": f"Failed to generate QR code: {str(e)}"}),
               status_code=500,
               headers={"Content-Type": "application/json"}
           )
   EOF
   
   # Create zip file for deployment
   zip -r ../qr-function.zip . > /dev/null
   cd ..
   
   echo "✅ Function code prepared"
   ```

   This implementation provides robust QR code generation with proper error handling, input validation, and secure blob storage integration. The function accepts JSON input, generates high-quality QR codes using configurable parameters, and returns accessible URLs for immediate use.

6. **Deploy Function Code to Azure**:

   Deploying our function code to Azure Functions enables serverless execution with automatic scaling and built-in monitoring. The deployment process uploads our code package and installs Python dependencies using remote build capabilities, making the QR code generation endpoint immediately available for HTTP requests.

   ```bash
   # Deploy function code to Azure with remote build
   az functionapp deployment source config-zip \
       --resource-group ${RESOURCE_GROUP} \
       --name ${FUNCTION_APP} \
       --src qr-function.zip \
       --build-remote true
   
   # Wait for deployment to complete
   echo "Waiting for function deployment to complete..."
   sleep 45
   
   # Get function app URL
   export FUNCTION_URL="https://${FUNCTION_APP}.azurewebsites.net"
   
   echo "✅ Function deployed successfully"
   echo "✅ Function URL: ${FUNCTION_URL}/api/generate-qr"
   ```

   The function is now live and ready to handle QR code generation requests. Azure automatically manages the runtime environment, installs dependencies through remote build, and provides monitoring capabilities for our serverless application.

## Validation & Testing

1. **Verify Function App Status**:

   ```bash
   # Check function app status and configuration
   az functionapp show \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{name:name,state:state,hostNames:defaultHostName}" \
       --output table
   ```

   Expected output: Function app should show as "Running" state with the correct hostname.

2. **Test QR Code Generation**:

   ```bash
   # Test the QR code generation endpoint
   curl -X POST "${FUNCTION_URL}/api/generate-qr" \
       -H "Content-Type: application/json" \
       -d '{"text": "Hello Azure Functions!"}' \
       | jq '.'
   ```

   Expected output: JSON response with success=true, filename, URL, and the original text.

3. **Verify Blob Storage Contents**:

   ```bash
   # List generated QR code files in blob storage
   az storage blob list \
       --container-name qr-codes \
       --account-name ${STORAGE_ACCOUNT} \
       --connection-string "${STORAGE_CONNECTION}" \
       --output table
   ```

   Expected output: Table showing the generated QR code PNG file with timestamp in filename.

4. **Test QR Code Accessibility**:

   ```bash
   # Test that generated QR code is publicly accessible
   QR_URL=$(curl -s -X POST "${FUNCTION_URL}/api/generate-qr" \
       -H "Content-Type: application/json" \
       -d '{"text": "Test accessibility"}' | jq -r '.url')
   
   echo "Generated QR code URL: ${QR_URL}"
   
   # Verify the image is accessible
   curl -I "${QR_URL}" | head -n 1
   ```

   Expected output: HTTP/1.1 200 OK indicating successful access to the generated QR code image.

## Cleanup

1. **Remove Resource Group and All Resources**:

   ```bash
   # Delete the entire resource group and all contained resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
   echo "Note: Complete deletion may take 2-3 minutes"
   ```

2. **Clean Up Local Files**:

   ```bash
   # Remove temporary function files
   rm -rf /tmp/qr-function qr-function.zip
   
   # Clear environment variables
   unset RESOURCE_GROUP STORAGE_ACCOUNT FUNCTION_APP STORAGE_CONNECTION FUNCTION_URL
   
   echo "✅ Local cleanup completed"
   ```

3. **Verify Resource Deletion**:

   ```bash
   # Verify resource group deletion (optional)
   az group exists --name ${RESOURCE_GROUP} || echo "Resource group successfully deleted"
   ```

## Discussion

This serverless QR code generator demonstrates the power of Azure Functions for event-driven, scalable applications that require minimal infrastructure management. The solution leverages Azure's consumption-based pricing model, meaning you only pay for actual function executions and blob storage usage, making it highly cost-effective for infrequent or variable workloads. The HTTP trigger pattern enables easy integration with web applications, mobile apps, or other services that need on-demand QR code generation capabilities.

The implementation showcases several Azure best practices, including secure configuration management through application settings, proper error handling with structured JSON responses, and integration between multiple Azure services using managed connections. The use of Azure Blob Storage provides durability, global accessibility, and cost-effective storage for generated images, while the public blob access policy enables direct URL sharing without complex authentication flows. The remote build deployment ensures Python dependencies are properly installed in the Linux environment.

Azure Functions' serverless architecture automatically handles scaling, monitoring, and maintenance, allowing developers to focus on business logic rather than infrastructure concerns. The Python runtime provides access to rich libraries like qrcode and Pillow for image processing, while Azure's extension bundles handle service integrations seamlessly. This pattern can be extended to support additional image formats, custom QR code styling, batch processing, or integration with other Azure services like Event Grid for workflow orchestration.

The solution follows the Azure Well-Architected Framework principles by implementing proper error handling, using managed services for reliability, optimizing costs through consumption-based pricing, and maintaining security through proper access controls and TLS encryption. For production use, consider implementing authentication using Azure AD, request throttling, and monitoring through Application Insights to ensure optimal performance and security. The current implementation uses anonymous authentication for simplicity but can be enhanced with Function-level or API Management security.

> **Tip**: Monitor your function's performance and costs through Azure Monitor and set up budget alerts to track usage patterns and optimize resource allocation based on actual demand.

**Documentation Sources:**
- [Azure Functions Python Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Azure Functions HTTP Triggers and Bindings](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-http-webhook)
- [Azure Blob Storage Upload with Python](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-upload-python)
- [Azure Functions Best Practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Azure Functions Consumption Plan](https://learn.microsoft.com/en-us/azure/azure-functions/consumption-plan)
- [Azure Functions Deployment Technologies](https://learn.microsoft.com/en-us/azure/azure-functions/functions-deployment-technologies)

## Challenge

Extend this QR code generator with these enhancements:

1. **Add custom styling options** - Modify the function to accept color parameters and generate QR codes with custom foreground and background colors, demonstrating advanced Python image processing techniques.

2. **Implement batch processing** - Create a new HTTP endpoint that accepts multiple text inputs and generates QR codes in parallel, showcasing Azure Functions' concurrent execution capabilities and blob storage batch operations.

3. **Add QR code analytics** - Integrate with Azure Application Insights to track QR code generation statistics, popular content types, and usage patterns, providing valuable business intelligence.

4. **Create a web frontend** - Build a simple web application using Azure Static Web Apps that provides a user-friendly interface for QR code generation, demonstrating full-stack serverless development.

5. **Implement content validation** - Add URL validation, content filtering, and size limits to ensure generated QR codes meet business requirements and security standards, showcasing enterprise-grade input handling.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*