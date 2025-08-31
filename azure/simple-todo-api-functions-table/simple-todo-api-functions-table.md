---
title: Simple Todo API with Functions and Table Storage
id: a7b8c9d0
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
tags: serverless, api, storage, beginner, crud, javascript
recipe-generator-version: 1.3
---

# Simple Todo API with Functions and Table Storage

## Problem

Development teams need to quickly build and deploy REST APIs for simple data management tasks without managing server infrastructure. Traditional server-based approaches require provisioning, configuring, and maintaining virtual machines or containers, which adds complexity and cost for basic CRUD operations. Teams want to focus on business logic rather than infrastructure management while building scalable APIs that handle variable workloads.

## Solution

Build a serverless REST API using Azure Functions with HTTP triggers connected to Azure Table Storage for data persistence. Azure Functions provides event-driven compute that automatically scales based on demand, while Table Storage offers a cost-effective NoSQL solution for structured data. This combination delivers a fully managed, pay-per-execution API that handles CRUD operations without infrastructure overhead.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[REST API Clients]
    end
    
    subgraph "Azure Functions"
        CREATE[Create Todo Function]
        READ[Get Todos Function]
        UPDATE[Update Todo Function]
        DELETE[Delete Todo Function]
    end
    
    subgraph "Storage Layer"
        TABLE[Azure Table Storage]
    end
    
    CLIENT -->|POST /api/todos| CREATE
    CLIENT -->|GET /api/todos| READ
    CLIENT -->|PUT /api/todos/{id}| UPDATE
    CLIENT -->|DELETE /api/todos/{id}| DELETE
    
    CREATE --> TABLE
    READ --> TABLE
    UPDATE --> TABLE
    DELETE --> TABLE
    
    style CREATE fill:#0078d4
    style READ fill:#0078d4
    style UPDATE fill:#0078d4
    style DELETE fill:#0078d4
    style TABLE fill:#FF9900
```

## Prerequisites

1. Azure account with appropriate permissions to create Function Apps and Storage Accounts
2. Azure CLI installed and configured (or use Azure Cloud Shell)
3. Basic knowledge of REST APIs and JavaScript
4. Understanding of NoSQL data concepts
5. Estimated cost: $0.10-$2.00 per month for development/testing workloads

> **Note**: Azure Functions Consumption plan charges only for execution time and requests. Table Storage costs are minimal for development use cases with low data volumes.

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-todo-api-$(openssl rand -hex 3)"
export LOCATION="eastus"
export STORAGE_ACCOUNT="todostorage$(openssl rand -hex 3)"
export FUNCTION_APP="todo-api-$(openssl rand -hex 3)"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

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

# Get storage account connection string
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --query connectionString \
    --output tsv)

echo "✅ Storage connection string retrieved"
```

## Steps

1. **Create Function App with Consumption Plan**:

   Azure Functions Consumption plan provides serverless compute that automatically scales based on incoming requests. This plan charges only for actual execution time and memory usage, making it cost-effective for APIs with variable or unpredictable traffic patterns. The Functions runtime manages all scaling decisions automatically.

   ```bash
   # Create Function App with Node.js runtime
   az functionapp create \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --storage-account ${STORAGE_ACCOUNT} \
       --consumption-plan-location ${LOCATION} \
       --runtime node \
       --runtime-version 18 \
       --functions-version 4
   
   echo "✅ Function App created: ${FUNCTION_APP}"
   ```

   The Function App is now configured with the latest Node.js 18 runtime and Functions v4 host, providing access to the most current features including improved cold start performance and enhanced debugging capabilities.

2. **Configure Application Settings for Table Storage**:

   Azure Functions can securely access Table Storage using connection strings stored as application settings. This approach follows Azure security best practices by keeping sensitive configuration data separate from application code and accessible only to the Function App runtime.

   ```bash
   # Set storage connection string as app setting
   az functionapp config appsettings set \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --settings "AZURE_STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}"
   
   echo "✅ Storage connection string configured"
   ```

   The connection string is now available to all functions within the app through the environment variable, enabling secure access to Table Storage operations.

3. **Create Table in Storage Account**:

   Azure Table Storage provides a NoSQL key-value store optimized for fast queries and cost-effective storage. Tables are schema-less, allowing flexible data structures while maintaining high performance for simple queries using partition keys and row keys.

   ```bash
   # Create table for todo items
   az storage table create \
       --name todos \
       --connection-string "${STORAGE_CONNECTION_STRING}"
   
   echo "✅ Table 'todos' created in storage account"
   ```

   The table is ready to store todo entities with automatic indexing on PartitionKey and RowKey properties, enabling efficient queries and updates.

4. **Initialize Function Project Structure**:

   Modern Azure Functions support multiple programming models. We'll use the newer v4 programming model for Node.js, which provides a more intuitive developer experience with simplified function definitions and better TypeScript support.

   ```bash
   # Create local function project structure
   mkdir -p ~/todo-functions
   cd ~/todo-functions
   
   # Initialize package.json for Node.js dependencies
   cat > package.json << 'EOF'
   {
     "name": "todo-api-functions",
     "version": "1.0.0",
     "description": "Simple Todo API using Azure Functions and Table Storage",
     "main": "src/functions/*.js",
     "scripts": {
       "start": "func start",
       "test": "echo \"Error: no test specified\" && exit 1"
     },
     "dependencies": {
       "@azure/functions": "^4.0.0",
       "@azure/data-tables": "^13.3.1"
     },
     "devDependencies": {
       "azure-functions-core-tools": "^4.0.0"
     }
   }
   EOF
   
   echo "✅ Function project initialized"
   ```

   This configuration specifies the latest Azure Functions SDK and Table Storage client library, ensuring access to current features and security updates.

5. **Create HTTP Trigger Functions for CRUD Operations**:

   Azure Functions HTTP triggers expose REST endpoints that automatically handle HTTP routing, request parsing, and response formatting. Each function will handle a specific CRUD operation while maintaining separation of concerns and enabling independent scaling.

   ```bash
   # Create src directory structure
   mkdir -p src/functions
   
   # Create main function app file
   cat > src/functions/todoApi.js << 'EOF'
   const { app } = require('@azure/functions');
   const { TableClient } = require('@azure/data-tables');
   
   // Initialize Table Storage client
   const connectionString = process.env.AZURE_STORAGE_CONNECTION_STRING;
   const tableClient = TableClient.fromConnectionString(connectionString, 'todos');
   
   // Helper function to generate unique ID
   function generateId() {
       return Date.now().toString() + Math.random().toString(36).substr(2, 9);
   }
   
   // CREATE - Add new todo
   app.http('createTodo', {
       methods: ['POST'],
       route: 'todos',
       handler: async (request, context) => {
           try {
               const body = await request.json();
               
               // Input validation
               if (!body.title || body.title.trim() === '') {
                   return { 
                       status: 400, 
                       jsonBody: { error: 'Title is required' } 
                   };
               }
               
               const todo = {
                   partitionKey: 'todos',
                   rowKey: generateId(),
                   title: body.title.trim(),
                   description: body.description || '',
                   completed: body.completed || false,
                   createdAt: new Date().toISOString()
               };
   
               await tableClient.createEntity(todo);
               
               return { 
                   status: 201,
                   jsonBody: {
                       id: todo.rowKey,
                       title: todo.title,
                       description: todo.description,
                       completed: todo.completed,
                       createdAt: todo.createdAt
                   }
               };
           } catch (error) {
               context.error('Error creating todo:', error);
               return { 
                   status: 500, 
                   jsonBody: { error: 'Failed to create todo' } 
               };
           }
       }
   });
   
   // READ - Get all todos
   app.http('getTodos', {
       methods: ['GET'],
       route: 'todos',
       handler: async (request, context) => {
           try {
               const entities = tableClient.listEntities({
                   filter: "PartitionKey eq 'todos'"
               });
               
               const todos = [];
               for await (const entity of entities) {
                   todos.push({
                       id: entity.rowKey,
                       title: entity.title,
                       description: entity.description,
                       completed: entity.completed,
                       createdAt: entity.createdAt
                   });
               }
               
               return { 
                   status: 200,
                   jsonBody: todos 
               };
           } catch (error) {
               context.error('Error fetching todos:', error);
               return { 
                   status: 500, 
                   jsonBody: { error: 'Failed to fetch todos' } 
               };
           }
       }
   });
   
   // UPDATE - Update existing todo
   app.http('updateTodo', {
       methods: ['PUT'],
       route: 'todos/{id}',
       handler: async (request, context) => {
           try {
               const id = request.params.id;
               const body = await request.json();
               
               // Input validation
               if (!body.title || body.title.trim() === '') {
                   return { 
                       status: 400, 
                       jsonBody: { error: 'Title is required' } 
                   };
               }
               
               const entity = {
                   partitionKey: 'todos',
                   rowKey: id,
                   title: body.title.trim(),
                   description: body.description || '',
                   completed: body.completed || false,
                   updatedAt: new Date().toISOString()
               };
               
               await tableClient.updateEntity(entity, 'Merge');
               
               return { 
                   status: 200,
                   jsonBody: {
                       id: entity.rowKey,
                       title: entity.title,
                       description: entity.description,
                       completed: entity.completed,
                       updatedAt: entity.updatedAt
                   }
               };
           } catch (error) {
               if (error.statusCode === 404) {
                   return { 
                       status: 404, 
                       jsonBody: { error: 'Todo not found' } 
                   };
               }
               context.error('Error updating todo:', error);
               return { 
                   status: 500, 
                   jsonBody: { error: 'Failed to update todo' } 
               };
           }
       }
   });
   
   // DELETE - Remove todo
   app.http('deleteTodo', {
       methods: ['DELETE'],
       route: 'todos/{id}',
       handler: async (request, context) => {
           try {
               const id = request.params.id;
               
               await tableClient.deleteEntity('todos', id);
               
               return { 
                   status: 204 
               };
           } catch (error) {
               if (error.statusCode === 404) {
                   return { 
                       status: 404, 
                       jsonBody: { error: 'Todo not found' } 
                   };
               }
               context.error('Error deleting todo:', error);
               return { 
                   status: 500, 
                   jsonBody: { error: 'Failed to delete todo' } 
               };
           }
       }
   });
   EOF
   
   echo "✅ CRUD functions created"
   ```

   These functions implement a complete REST API following standard HTTP conventions, with proper error handling, input validation, and JSON response formatting for seamless client integration.

6. **Deploy Functions to Azure**:

   Azure Functions deployment packages the application code and dependencies, uploads them to the Function App, and configures the runtime environment. The deployment process handles dependency resolution and environment setup automatically.

   ```bash
   # Install dependencies locally
   npm install
   
   # Create deployment package
   zip -r todo-functions.zip . -x "*.git*" "node_modules/*"
   
   # Deploy using Azure CLI
   az functionapp deployment source config-zip \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --src todo-functions.zip
   
   echo "✅ Functions deployed to Azure"
   
   # Get Function App URL
   FUNCTION_APP_URL=$(az functionapp show \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --query defaultHostName \
       --output tsv)
   
   echo "✅ Function App URL: https://${FUNCTION_APP_URL}"
   ```

   The functions are now running in Azure with automatic scaling capabilities and integrated monitoring through Application Insights.

## Validation & Testing

1. **Verify Function App Deployment**:

   ```bash
   # Check Function App status
   az functionapp show \
       --name ${FUNCTION_APP} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{name:name, state:state, hostNames:hostNames}" \
       --output table
   ```

   Expected output: Function App should show "Running" state with assigned hostname.

2. **Test Create Todo Operation**:

   ```bash
   # Create a new todo item
   curl -X POST "https://${FUNCTION_APP_URL}/api/todos" \
       -H "Content-Type: application/json" \
       -d '{
           "title": "Learn Azure Functions",
           "description": "Complete the serverless tutorial",
           "completed": false
       }'
   ```

   Expected output: JSON response with created todo including generated ID and timestamp.

3. **Test Get All Todos Operation**:

   ```bash
   # Retrieve all todo items
   curl -X GET "https://${FUNCTION_APP_URL}/api/todos"
   ```

   Expected output: JSON array containing all todo items in the table.

4. **Test Update Todo Operation**:

   ```bash
   # Update existing todo (replace {id} with actual ID from create response)
   TODO_ID="your-todo-id-here"
   curl -X PUT "https://${FUNCTION_APP_URL}/api/todos/${TODO_ID}" \
       -H "Content-Type: application/json" \
       -d '{
           "title": "Learn Azure Functions",
           "description": "Complete the serverless tutorial",
           "completed": true
       }'
   ```

   Expected output: JSON response with updated todo showing completed status change.

5. **Test Delete Todo Operation**:

   ```bash
   # Delete todo item (replace {id} with actual ID)
   curl -X DELETE "https://${FUNCTION_APP_URL}/api/todos/${TODO_ID}"
   ```

   Expected output: HTTP 204 No Content response indicating successful deletion.

6. **Test Input Validation**:

   ```bash
   # Test validation with empty title
   curl -X POST "https://${FUNCTION_APP_URL}/api/todos" \
       -H "Content-Type: application/json" \
       -d '{
           "title": "",
           "description": "This should fail validation"
       }'
   ```

   Expected output: HTTP 400 Bad Request with validation error message.

## Cleanup

1. **Remove Resource Group and All Resources**:

   ```bash
   # Delete resource group and all contained resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
   echo "Note: Deletion may take several minutes to complete"
   ```

2. **Clean Up Local Files**:

   ```bash
   # Remove local function project
   cd ~
   rm -rf todo-functions
   rm -f todo-functions.zip
   
   echo "✅ Local project files cleaned up"
   ```

3. **Verify Resource Deletion**:

   ```bash
   # Check if resource group still exists
   az group exists --name ${RESOURCE_GROUP}
   ```

   Expected output: "false" when deletion is complete.

## Discussion

This serverless Todo API demonstrates the power of Azure's pay-per-execution model, where you only pay for actual function invocations and storage consumed. Azure Functions automatically handles scaling, load balancing, and availability, while Table Storage provides a cost-effective NoSQL solution for structured data with sub-millisecond latency for key-based lookups.

The architecture follows Azure Well-Architected Framework principles by implementing operational excellence through Infrastructure as Code, reliability through managed services with built-in redundancy, performance efficiency through automatic scaling, and cost optimization through consumption-based pricing. Security is enhanced through managed identities and connection string encryption at rest.

Azure Functions HTTP triggers provide native support for REST API patterns with automatic request routing, content negotiation, and response formatting. The v4 programming model simplifies function development while maintaining compatibility with existing tooling and deployment processes. Table Storage's partition key and row key design enables horizontal scaling across multiple storage nodes while maintaining consistent performance characteristics.

For production workloads, consider implementing additional patterns such as input validation using middleware, structured logging with Application Insights, circuit breaker patterns for external dependencies, and API versioning strategies. The serverless architecture naturally supports microservices patterns and can integrate with Azure API Management for advanced routing, authentication, and rate limiting capabilities. For more information on Azure Functions best practices, see the [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/).

> **Tip**: Enable Application Insights integration to gain detailed performance metrics, request tracing, and error monitoring across all function executions.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add Input Validation**: Implement request validation middleware using JSON schemas to ensure data integrity and provide meaningful error messages for invalid requests.

2. **Implement Authentication**: Integrate Azure Active Directory authentication using Easy Auth to secure API endpoints and associate todos with specific users.

3. **Add Pagination and Filtering**: Enhance the GET endpoint with query parameters for pagination, sorting, and filtering by completion status or creation date.

4. **Create Frontend Interface**: Build a static web application using Azure Static Web Apps to provide a user interface for the Todo API with real-time updates.

5. **Implement Caching Strategy**: Add Azure Cache for Redis to cache frequently accessed todo lists and improve response times for read operations.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*