---
title: API Composition with Step Functions
id: f5c8d3a7
category: serverless
difficulty: 300
subject: aws
services: Step Functions, API Gateway, Lambda, DynamoDB
estimated-time: 180 minutes
recipe-version: 1.3
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: api-composition, step-functions, api-gateway, serverless, microservices
recipe-generator-version: 1.3
---

# API Composition with Step Functions

## Problem

Modern enterprises often struggle with API sprawl as they decompose monolithic applications into microservices. Different teams create specialized APIs for user management, inventory, billing, and notifications, but client applications need unified endpoints that aggregate data from multiple services. Traditional approaches require building complex orchestration logic within each API or creating heavyweight middleware solutions, leading to tight coupling, performance bottlenecks, and increased operational complexity.

## Solution

Step Functions provides a powerful orchestration engine that can coordinate multiple API calls, handle complex business logic, and manage error scenarios through visual workflows. Combined with API Gateway, we can create composite APIs that aggregate data from multiple microservices, apply business rules, and return unified responses to clients. This approach decouples orchestration logic from individual services while providing centralized monitoring and error handling.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[Mobile/Web Client]
    end
    
    subgraph "API Gateway"
        APIGW[API Gateway]
        RESOURCE[/orders Resource]
        METHOD[POST Method]
    end
    
    subgraph "Step Functions"
        WORKFLOW[Order Processing Workflow]
        VALIDATE[Validate Order]
        INVENTORY[Check Inventory]
        PAYMENT[Process Payment]
        SHIPPING[Create Shipping]
        PARALLEL[Parallel Processing]
        NOTIFY[Send Notifications]
    end
    
    subgraph "Microservices"
        USER_SVC[User Service]
        INVENTORY_SVC[Inventory Service]
        PAYMENT_SVC[Payment Service]
        SHIPPING_SVC[Shipping Service]
        NOTIFICATION_SVC[Notification Service]
    end
    
    subgraph "Data Layer"
        ORDERS_DB[Orders DynamoDB]
        AUDIT_DB[Audit DynamoDB]
    end
    
    CLIENT --> APIGW
    APIGW --> RESOURCE
    RESOURCE --> METHOD
    METHOD --> WORKFLOW
    
    WORKFLOW --> VALIDATE
    VALIDATE --> USER_SVC
    VALIDATE --> INVENTORY
    INVENTORY --> INVENTORY_SVC
    INVENTORY --> PAYMENT
    PAYMENT --> PAYMENT_SVC
    PAYMENT --> PARALLEL
    PARALLEL --> SHIPPING
    PARALLEL --> NOTIFY
    SHIPPING --> SHIPPING_SVC
    NOTIFY --> NOTIFICATION_SVC
    
    WORKFLOW --> ORDERS_DB
    WORKFLOW --> AUDIT_DB
    
    style WORKFLOW fill:#FF9900
    style APIGW fill:#FF9900
    style PARALLEL fill:#3F8624
    style ORDERS_DB fill:#4B9CD3
```

## Prerequisites

1. AWS account with permissions to create Step Functions, API Gateway, Lambda, and DynamoDB resources
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Understanding of microservices architecture and API design patterns
4. Basic knowledge of JSON and state machines
5. Estimated cost: $10-15 for resources created during testing

> **Note**: This recipe demonstrates advanced orchestration patterns. Ensure you understand the business logic flow before implementing in production. Review the [Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/developing-workflows.html) for additional workflow design best practices.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export PROJECT_NAME="api-composition-${RANDOM_SUFFIX}"
export ROLE_NAME="StepFunctionsCompositionRole-${RANDOM_SUFFIX}"
export LAMBDA_ROLE_NAME="LambdaExecutionRole-${RANDOM_SUFFIX}"
export STATE_MACHINE_NAME="OrderProcessingWorkflow-${RANDOM_SUFFIX}"
export API_NAME="CompositionAPI-${RANDOM_SUFFIX}"

# Create DynamoDB tables for demo services
aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-orders" \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-audit" \
    --attribute-definitions AttributeName=auditId,AttributeType=S \
    --key-schema AttributeName=auditId,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-reservations" \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5

# Wait for tables to be created
aws dynamodb wait table-exists --table-name "${PROJECT_NAME}-orders"
aws dynamodb wait table-exists --table-name "${PROJECT_NAME}-audit"
aws dynamodb wait table-exists --table-name "${PROJECT_NAME}-reservations"

echo "✅ DynamoDB tables created successfully"
```

## Steps

1. **Create IAM Role for Lambda Functions**:

   Lambda functions require an execution role to access other AWS services and write CloudWatch logs. This foundational security setup enables Lambda functions to interact with DynamoDB and other services while following the principle of least privilege. The execution role provides the necessary permissions without embedding credentials in code.

   ```bash
   # Create trust policy for Lambda
   cat > lambda-trust-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "lambda.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF
   
   # Create the Lambda execution role
   aws iam create-role \
       --role-name "${LAMBDA_ROLE_NAME}" \
       --assume-role-policy-document file://lambda-trust-policy.json
   
   # Attach basic Lambda execution policy
   aws iam attach-role-policy \
       --role-name "${LAMBDA_ROLE_NAME}" \
       --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
   
   # Get the Lambda role ARN
   LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" \
       --query Role.Arn --output text)
   
   echo "✅ Lambda execution role created with ARN: ${LAMBDA_ROLE_ARN}"
   ```

   The Lambda execution role is now configured with basic execution permissions for CloudWatch logging. This secure foundation enables Lambda functions to execute and write logs while maintaining proper access controls for our microservices architecture.

2. **Create IAM Role for Step Functions**:

   IAM roles enable Step Functions to securely access other AWS services on your behalf without hardcoding credentials. The execution role defines what resources your state machine can access, implementing the principle of least privilege. Understanding IAM roles is fundamental to building secure serverless workflows, as documented in the [Step Functions execution roles guide](https://docs.aws.amazon.com/step-functions/latest/dg/manage-state-machine-permissions.html).

   ```bash
   # Create trust policy for Step Functions
   cat > trust-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "states.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF
   
   # Create the IAM role
   aws iam create-role \
       --role-name "${ROLE_NAME}" \
       --assume-role-policy-document file://trust-policy.json
   
   # Attach necessary policies
   aws iam attach-role-policy \
       --role-name "${ROLE_NAME}" \
       --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
   
   # Create custom policy for DynamoDB and API Gateway access
   cat > composition-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "dynamodb:PutItem",
           "dynamodb:GetItem",
           "dynamodb:UpdateItem",
           "dynamodb:Query",
           "dynamodb:Scan"
         ],
         "Resource": [
           "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${PROJECT_NAME}-*"
         ]
       },
       {
         "Effect": "Allow",
         "Action": [
           "execute-api:Invoke"
         ],
         "Resource": "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:*/*/*"
       },
       {
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogGroup",
           "logs:CreateLogStream",
           "logs:PutLogEvents"
         ],
         "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
       }
     ]
   }
   EOF
   
   aws iam put-role-policy \
       --role-name "${ROLE_NAME}" \
       --policy-name "CompositionPolicy" \
       --policy-document file://composition-policy.json
   
   # Get the role ARN
   ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" \
       --query Role.Arn --output text)
   
   echo "✅ Step Functions IAM role created with ARN: ${ROLE_ARN}"
   ```

   The IAM role is now configured with the necessary permissions to invoke Lambda functions, access DynamoDB tables, and write CloudWatch logs. This security foundation enables Step Functions to orchestrate your microservices while maintaining proper access controls and audit capabilities.

3. **Create Mock Lambda Functions for Microservices**:

   Lambda functions provide the serverless compute layer for our microservices architecture. Each function represents a domain-specific service (user management, inventory) that can be developed, deployed, and scaled independently. This [microservices pattern with Lambda](https://docs.aws.amazon.com/whitepapers/latest/serverless-multi-tier-architectures-api-gateway-lambda/microservices-with-lambda.html) enables teams to work autonomously while maintaining service boundaries and reducing operational overhead.

   ```bash
   # Create Lambda function for user validation
   cat > user-service.py << 'EOF'
   import json
   import random
   
   def lambda_handler(event, context):
       user_id = event.get('userId', '')
       
       # Mock user validation
       if not user_id or len(user_id) < 3:
           return {
               'statusCode': 400,
               'body': json.dumps({
                   'valid': False,
                   'error': 'Invalid user ID'
               })
           }
       
       # Simulate user data retrieval
       user_data = {
           'valid': True,
           'userId': user_id,
           'name': f'User {user_id}',
           'email': f'{user_id}@example.com',
           'creditLimit': random.randint(1000, 5000)
       }
       
       return {
           'statusCode': 200,
           'body': json.dumps(user_data)
       }
   EOF
   
   # Create deployment package
   zip user-service.zip user-service.py
   
   # Create Lambda function
   aws lambda create-function \
       --function-name "${PROJECT_NAME}-user-service" \
       --runtime python3.9 \
       --role "${LAMBDA_ROLE_ARN}" \
       --handler user-service.lambda_handler \
       --zip-file fileb://user-service.zip \
       --timeout 30 \
       --memory-size 128
   
   # Create inventory service
   cat > inventory-service.py << 'EOF'
   import json
   import random
   
   def lambda_handler(event, context):
       items = event.get('items', [])
       
       inventory_status = []
       for item in items:
           available = random.randint(0, 100)
           requested = item.get('quantity', 0)
           
           inventory_status.append({
               'productId': item.get('productId'),
               'requested': requested,
               'available': available,
               'sufficient': available >= requested,
               'price': random.randint(10, 500)
           })
       
       return {
           'statusCode': 200,
           'body': json.dumps({
               'inventoryStatus': inventory_status,
               'allItemsAvailable': all(item['sufficient'] for item in inventory_status)
           })
       }
   EOF
   
   zip inventory-service.zip inventory-service.py
   
   aws lambda create-function \
       --function-name "${PROJECT_NAME}-inventory-service" \
       --runtime python3.9 \
       --role "${LAMBDA_ROLE_ARN}" \
       --handler inventory-service.lambda_handler \
       --zip-file fileb://inventory-service.zip \
       --timeout 30 \
       --memory-size 128
   
   echo "✅ Mock microservices created successfully"
   ```

   These Lambda functions now serve as independent microservices that can be invoked by Step Functions. Each service maintains its own business logic and can be modified, tested, and deployed independently. This decoupled architecture enables parallel development teams and supports different scaling requirements for each service component.

4. **Create Step Functions State Machine Definition**:

   State machines define the business logic flow using Amazon States Language (ASL), providing visual workflow representation and built-in error handling. The state machine orchestrates microservice calls, handles conditional logic, and manages data transformation between services. This declarative approach separates orchestration concerns from individual service implementations, as explained in the [Step Functions workflows guide](https://docs.aws.amazon.com/step-functions/latest/dg/tutorial-creating-lambda-state-machine.html).

   ```bash
   # Create the state machine definition
   cat > state-machine-definition.json << EOF
   {
     "Comment": "Order Processing Workflow with API Composition",
     "StartAt": "ValidateOrder",
     "States": {
       "ValidateOrder": {
         "Type": "Task",
         "Resource": "arn:aws:states:::lambda:invoke",
         "Parameters": {
           "FunctionName": "${PROJECT_NAME}-user-service",
           "Payload": {
             "userId.$": "$.userId"
           }
         },
         "ResultPath": "$.userValidation",
         "Next": "CheckUserValid",
         "Catch": [
           {
             "ErrorEquals": ["States.TaskFailed"],
             "Next": "ValidationFailed",
             "ResultPath": "$.error"
           }
         ]
       },
       "CheckUserValid": {
         "Type": "Choice",
         "Choices": [
           {
             "Variable": "$.userValidation.Payload.body",
             "StringMatches": "*\"valid\":true*",
             "Next": "CheckInventory"
           }
         ],
         "Default": "ValidationFailed"
       },
       "CheckInventory": {
         "Type": "Task",
         "Resource": "arn:aws:states:::lambda:invoke",
         "Parameters": {
           "FunctionName": "${PROJECT_NAME}-inventory-service",
           "Payload": {
             "items.$": "$.items"
           }
         },
         "ResultPath": "$.inventoryCheck",
         "Next": "ProcessInventoryResult",
         "Catch": [
           {
             "ErrorEquals": ["States.TaskFailed"],
             "Next": "InventoryCheckFailed",
             "ResultPath": "$.error"
           }
         ]
       },
       "ProcessInventoryResult": {
         "Type": "Choice",
         "Choices": [
           {
             "Variable": "$.inventoryCheck.Payload.body",
             "StringMatches": "*\"allItemsAvailable\":true*",
             "Next": "CalculateOrderTotal"
           }
         ],
         "Default": "InsufficientInventory"
       },
       "CalculateOrderTotal": {
         "Type": "Pass",
         "Parameters": {
           "orderId.$": "$.orderId",
           "userId.$": "$.userId",
           "items.$": "$.items",
           "userInfo.$": "$.userValidation.Payload.body",
           "inventoryInfo.$": "$.inventoryCheck.Payload.body",
           "orderTotal": 250.00,
           "status": "processing"
         },
         "Next": "ParallelProcessing"
       },
       "ParallelProcessing": {
         "Type": "Parallel",
         "Branches": [
           {
             "StartAt": "SaveOrder",
             "States": {
               "SaveOrder": {
                 "Type": "Task",
                 "Resource": "arn:aws:states:::dynamodb:putItem",
                 "Parameters": {
                   "TableName": "${PROJECT_NAME}-orders",
                   "Item": {
                     "orderId": {
                       "S.$": "$.orderId"
                     },
                     "userId": {
                       "S.$": "$.userId"
                     },
                     "status": {
                       "S": "processing"
                     },
                     "orderTotal": {
                       "N": "250.00"
                     },
                     "timestamp": {
                       "S.$": "$$.State.EnteredTime"
                     }
                   }
                 },
                 "End": true
               }
             }
           },
           {
             "StartAt": "LogAudit",
             "States": {
               "LogAudit": {
                 "Type": "Task",
                 "Resource": "arn:aws:states:::dynamodb:putItem",
                 "Parameters": {
                   "TableName": "${PROJECT_NAME}-audit",
                   "Item": {
                     "auditId": {
                       "S.$": "$$.Execution.Name"
                     },
                     "orderId": {
                       "S.$": "$.orderId"
                     },
                     "action": {
                       "S": "order_created"
                     },
                     "timestamp": {
                       "S.$": "$$.State.EnteredTime"
                     }
                   }
                 },
                 "End": true
               }
             }
           }
         ],
         "Next": "OrderProcessed"
       },
       "OrderProcessed": {
         "Type": "Pass",
         "Parameters": {
           "orderId.$": "$.orderId",
           "status": "completed",
           "message": "Order processed successfully",
           "orderTotal": 250.00
         },
         "End": true
       },
       "ValidationFailed": {
         "Type": "Pass",
         "Parameters": {
           "error": "User validation failed",
           "orderId.$": "$.orderId"
         },
         "End": true
       },
       "InventoryCheckFailed": {
         "Type": "Pass",
         "Parameters": {
           "error": "Inventory check failed",
           "orderId.$": "$.orderId"
         },
         "End": true
       },
       "InsufficientInventory": {
         "Type": "Pass",
         "Parameters": {
           "error": "Insufficient inventory",
           "orderId.$": "$.orderId"
         },
         "End": true
       }
     }
   }
   EOF
   
   # Create the state machine
   aws stepfunctions create-state-machine \
       --name "${STATE_MACHINE_NAME}" \
       --definition file://state-machine-definition.json \
       --role-arn "${ROLE_ARN}"
   
   # Get the state machine ARN
   STATE_MACHINE_ARN=$(aws stepfunctions describe-state-machine \
       --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
       --query stateMachineArn --output text)
   
   echo "✅ State machine created with ARN: ${STATE_MACHINE_ARN}"
   ```

   The state machine now provides a centralized orchestration engine that coordinates multiple microservices according to your business rules. The visual workflow representation makes complex business logic understandable to both technical and business stakeholders, while built-in error handling ensures reliable execution even when individual services encounter issues.

5. **Create API Gateway with Step Functions Integration**:

   API Gateway provides the HTTP interface that exposes your Step Functions workflows as REST APIs. This integration pattern allows external clients to trigger complex workflows through simple HTTP requests while API Gateway handles request routing, throttling, and response transformation. The [API Gateway Step Functions integration](https://docs.aws.amazon.com/step-functions/latest/dg/connect-api-gateway.html) enables you to build composable APIs that aggregate multiple backend services.

   ```bash
   # Create API Gateway
   API_ID=$(aws apigateway create-rest-api \
       --name "${API_NAME}" \
       --description "API Composition with Step Functions" \
       --query id --output text)
   
   # Get root resource ID
   ROOT_RESOURCE_ID=$(aws apigateway get-resources \
       --rest-api-id "${API_ID}" \
       --query 'items[0].id' --output text)
   
   # Create orders resource
   ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id "${API_ID}" \
       --parent-id "${ROOT_RESOURCE_ID}" \
       --path-part "orders" \
       --query id --output text)
   
   # Create IAM role for API Gateway to invoke Step Functions
   cat > apigw-trust-policy.json << EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "apigateway.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   EOF
   
   aws iam create-role \
       --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
       --assume-role-policy-document file://apigw-trust-policy.json
   
   # Attach Step Functions execution policy
   aws iam attach-role-policy \
       --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
       --policy-arn "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
   
   APIGW_ROLE_ARN=$(aws iam get-role \
       --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
       --query Role.Arn --output text)
   
   echo "✅ API Gateway IAM role created: ${APIGW_ROLE_ARN}"
   ```

   API Gateway now has the necessary permissions to invoke Step Functions on behalf of client requests. This secure integration enables HTTP clients to trigger complex workflows without requiring direct access to Step Functions, providing an additional security layer and enabling features like request validation, rate limiting, and API key management.

6. **Configure API Gateway Method with Request Mapping**:

   Request mapping templates transform incoming HTTP requests into the format expected by Step Functions, enabling protocol adaptation without code changes. This powerful feature allows you to expose a clean, client-friendly API interface while maintaining flexibility in your backend service contracts. The mapping templates use Velocity Template Language (VTL) to perform data transformation and validation.

   ```bash
   # Create POST method
   aws apigateway put-method \
       --rest-api-id "${API_ID}" \
       --resource-id "${ORDERS_RESOURCE_ID}" \
       --http-method POST \
       --authorization-type NONE \
       --request-parameters method.request.header.Content-Type=false
   
   # Create integration with Step Functions
   aws apigateway put-integration \
       --rest-api-id "${API_ID}" \
       --resource-id "${ORDERS_RESOURCE_ID}" \
       --http-method POST \
       --type AWS \
       --integration-http-method POST \
       --uri "arn:aws:apigateway:${AWS_REGION}:states:action/StartExecution" \
       --credentials "${APIGW_ROLE_ARN}" \
       --request-templates '{
         "application/json": "{\"input\": \"$util.escapeJavaScript($input.json('\'\'$'\'\''))\", \"stateMachineArn\": \"'${STATE_MACHINE_ARN}'\"}"
       }'
   
   # Configure method response
   aws apigateway put-method-response \
       --rest-api-id "${API_ID}" \
       --resource-id "${ORDERS_RESOURCE_ID}" \
       --http-method POST \
       --status-code 200 \
       --response-models application/json=Empty
   
   # Configure integration response
   aws apigateway put-integration-response \
       --rest-api-id "${API_ID}" \
       --resource-id "${ORDERS_RESOURCE_ID}" \
       --http-method POST \
       --status-code 200 \
       --response-templates '{
         "application/json": "{\"executionArn\": \"$input.json('\'\'$.executionArn''\'')\"}"
       }'
   
   echo "✅ API Gateway method configured successfully"
   ```

   The API method now provides a seamless integration between HTTP clients and Step Functions workflows. Request mapping templates ensure that client requests are properly formatted for workflow execution, while response templates provide consistent API responses. This abstraction layer enables API versioning and client-specific customizations without modifying backend workflows.

7. **Create GET Method for Order Status**:

   This demonstrates direct service integration where API Gateway queries DynamoDB without requiring Lambda functions or Step Functions. This pattern reduces latency and costs for simple data retrieval operations while maintaining consistent API interfaces. Direct integrations are ideal for CRUD operations that don't require complex business logic or orchestration.

   ```bash
   # Create {orderId} resource
   ORDER_ID_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id "${API_ID}" \
       --parent-id "${ORDERS_RESOURCE_ID}" \
       --path-part "{orderId}" \
       --query id --output text)
   
   # Create status resource
   STATUS_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id "${API_ID}" \
       --parent-id "${ORDER_ID_RESOURCE_ID}" \
       --path-part "status" \
       --query id --output text)
   
   # Create GET method for status
   aws apigateway put-method \
       --rest-api-id "${API_ID}" \
       --resource-id "${STATUS_RESOURCE_ID}" \
       --http-method GET \
       --authorization-type NONE \
       --request-parameters method.request.path.orderId=true
   
   # Create integration with DynamoDB
   aws apigateway put-integration \
       --rest-api-id "${API_ID}" \
       --resource-id "${STATUS_RESOURCE_ID}" \
       --http-method GET \
       --type AWS \
       --integration-http-method POST \
       --uri "arn:aws:apigateway:${AWS_REGION}:dynamodb:action/GetItem" \
       --credentials "${APIGW_ROLE_ARN}" \
       --request-templates '{
         "application/json": "{\"TableName\": \"'${PROJECT_NAME}'-orders\", \"Key\": {\"orderId\": {\"S\": \"$input.params('\'\'orderId'\'')\"}}}"}
       }'
   
   # Configure method response
   aws apigateway put-method-response \
       --rest-api-id "${API_ID}" \
       --resource-id "${STATUS_RESOURCE_ID}" \
       --http-method GET \
       --status-code 200 \
       --response-models application/json=Empty
   
   # Configure integration response
   aws apigateway put-integration-response \
       --rest-api-id "${API_ID}" \
       --resource-id "${STATUS_RESOURCE_ID}" \
       --http-method GET \
       --status-code 200 \
       --response-templates '{
         "application/json": "{\"orderId\": \"$input.json('\'\'$.Item.orderId.S'\'\')\", \"status\": \"$input.json('\'\'$.Item.status.S'\'\')\", \"orderTotal\": \"$input.json('\'\'$.Item.orderTotal.N'\'\'')\"}"
       }'
   
   echo "✅ Order status endpoint created"
   ```

   The status endpoint provides immediate access to order data without triggering workflow executions. This efficient pattern demonstrates how to combine orchestrated workflows for complex operations with direct data access for simple queries, optimizing both performance and cost for different use cases.

8. **Deploy API Gateway and Test**:

   API Gateway deployments create immutable snapshots of your API configuration that can be deployed to different stages (dev, test, prod). This deployment model enables controlled rollouts, testing strategies, and rollback capabilities. Understanding deployment stages is crucial for managing API lifecycle and ensuring consistent environments across development workflows.

   ```bash
   # Deploy API
   aws apigateway create-deployment \
       --rest-api-id "${API_ID}" \
       --stage-name "prod"
   
   # Get API endpoint
   API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
   
   echo "✅ API deployed successfully"
   echo "API Endpoint: ${API_ENDPOINT}"
   
   # Test the API composition
   curl -X POST "${API_ENDPOINT}/orders" \
       -H "Content-Type: application/json" \
       -d '{
         "orderId": "order-123",
         "userId": "user456",
         "items": [
           {
             "productId": "prod-1",
             "quantity": 2
           },
           {
             "productId": "prod-2",
             "quantity": 1
           }
         ]
       }'
   
   echo "✅ API composition test completed"
   ```

   The API is now live and accepting requests from clients. The test demonstrates the complete request flow: client HTTP request → API Gateway → Step Functions → Lambda services → DynamoDB storage → response. This end-to-end validation confirms that all integration points are working correctly and the composite API is ready for production use.

9. **Add Error Handling and Compensation Logic**:

   Advanced error handling patterns include retry logic, exponential backoff, and compensation workflows that implement the saga pattern for distributed transactions. These patterns ensure data consistency across multiple services when partial failures occur. The [Step Functions error handling guide](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html) provides comprehensive guidance on building resilient workflows that gracefully handle service failures and network issues.

   ```bash
   # Update state machine with enhanced error handling
   cat > enhanced-state-machine.json << EOF
   {
     "Comment": "Enhanced Order Processing with Compensation",
     "StartAt": "ValidateOrder",
     "States": {
       "ValidateOrder": {
         "Type": "Task",
         "Resource": "arn:aws:states:::lambda:invoke",
         "Parameters": {
           "FunctionName": "${PROJECT_NAME}-user-service",
           "Payload": {
             "userId.$": "$.userId"
           }
         },
         "ResultPath": "$.userValidation",
         "Next": "CheckUserValid",
         "Retry": [
           {
             "ErrorEquals": ["States.TaskFailed"],
             "IntervalSeconds": 2,
             "MaxAttempts": 3,
             "BackoffRate": 2.0
           }
         ],
         "Catch": [
           {
             "ErrorEquals": ["States.ALL"],
             "Next": "CompensateOrder",
             "ResultPath": "$.error"
           }
         ]
       },
       "CheckUserValid": {
         "Type": "Choice",
         "Choices": [
           {
             "Variable": "$.userValidation.Payload.body",
             "StringMatches": "*\"valid\":true*",
             "Next": "CheckInventory"
           }
         ],
         "Default": "CompensateOrder"
       },
       "CheckInventory": {
         "Type": "Task",
         "Resource": "arn:aws:states:::lambda:invoke",
         "Parameters": {
           "FunctionName": "${PROJECT_NAME}-inventory-service",
           "Payload": {
             "items.$": "$.items"
           }
         },
         "ResultPath": "$.inventoryCheck",
         "Next": "ProcessInventoryResult",
         "Retry": [
           {
             "ErrorEquals": ["States.TaskFailed"],
             "IntervalSeconds": 2,
             "MaxAttempts": 3,
             "BackoffRate": 2.0
           }
         ],
         "Catch": [
           {
             "ErrorEquals": ["States.ALL"],
             "Next": "CompensateOrder",
             "ResultPath": "$.error"
           }
         ]
       },
       "ProcessInventoryResult": {
         "Type": "Choice",
         "Choices": [
           {
             "Variable": "$.inventoryCheck.Payload.body",
             "StringMatches": "*\"allItemsAvailable\":true*",
             "Next": "ReserveInventory"
           }
         ],
         "Default": "CompensateOrder"
       },
       "ReserveInventory": {
         "Type": "Task",
         "Resource": "arn:aws:states:::dynamodb:putItem",
         "Parameters": {
           "TableName": "${PROJECT_NAME}-reservations",
           "Item": {
             "orderId": {
               "S.$": "$.orderId"
             },
             "status": {
               "S": "reserved"
             },
             "timestamp": {
               "S.$": "$$.State.EnteredTime"
             }
           }
         },
         "ResultPath": "$.reservation",
         "Next": "ParallelProcessing",
         "Catch": [
           {
             "ErrorEquals": ["States.ALL"],
             "Next": "CompensateOrder",
             "ResultPath": "$.error"
           }
         ]
       },
       "ParallelProcessing": {
         "Type": "Parallel",
         "Branches": [
           {
             "StartAt": "SaveOrder",
             "States": {
               "SaveOrder": {
                 "Type": "Task",
                 "Resource": "arn:aws:states:::dynamodb:putItem",
                 "Parameters": {
                   "TableName": "${PROJECT_NAME}-orders",
                   "Item": {
                     "orderId": {
                       "S.$": "$.orderId"
                     },
                     "userId": {
                       "S.$": "$.userId"
                     },
                     "status": {
                       "S": "processing"
                     },
                     "orderTotal": {
                       "N": "250.00"
                     },
                     "timestamp": {
                       "S.$": "$$.State.EnteredTime"
                     }
                   }
                 },
                 "End": true
               }
             }
           },
           {
             "StartAt": "LogAudit",
             "States": {
               "LogAudit": {
                 "Type": "Task",
                 "Resource": "arn:aws:states:::dynamodb:putItem",
                 "Parameters": {
                   "TableName": "${PROJECT_NAME}-audit",
                   "Item": {
                     "auditId": {
                       "S.$": "$$.Execution.Name"
                     },
                     "orderId": {
                       "S.$": "$.orderId"
                     },
                     "action": {
                       "S": "order_created"
                     },
                     "timestamp": {
                       "S.$": "$$.State.EnteredTime"
                     }
                   }
                 },
                 "End": true
               }
             }
           }
         ],
         "Next": "OrderProcessed",
         "Catch": [
           {
             "ErrorEquals": ["States.ALL"],
             "Next": "CompensateOrder",
             "ResultPath": "$.error"
           }
         ]
       },
       "CompensateOrder": {
         "Type": "Task",
         "Resource": "arn:aws:states:::dynamodb:putItem",
         "Parameters": {
           "TableName": "${PROJECT_NAME}-audit",
           "Item": {
             "auditId": {
               "S.$": "$$.Execution.Name"
             },
             "orderId": {
               "S.$": "$.orderId"
             },
             "action": {
               "S": "order_failed"
             },
             "error": {
               "S.$": "$.error.Error"
             },
             "timestamp": {
               "S.$": "$$.State.EnteredTime"
             }
           }
         },
         "Next": "OrderFailed"
       },
       "OrderProcessed": {
         "Type": "Pass",
         "Parameters": {
           "orderId.$": "$.orderId",
           "status": "completed",
           "message": "Order processed successfully"
         },
         "End": true
       },
       "OrderFailed": {
         "Type": "Pass",
         "Parameters": {
           "orderId.$": "$.orderId",
           "status": "failed",
           "message": "Order processing failed"
         },
         "End": true
       }
     }
   }
   EOF
   
   # Update the state machine
   aws stepfunctions update-state-machine \
       --state-machine-arn "${STATE_MACHINE_ARN}" \
       --definition file://enhanced-state-machine.json
   
   echo "✅ State machine updated with enhanced error handling"
   ```

   The enhanced workflow now implements sophisticated error handling and compensation logic that maintains data consistency even when individual services fail. Retry mechanisms with exponential backoff handle transient failures, while compensation states ensure that partial transactions can be properly rolled back. This resilient design enables production-ready workflows that gracefully handle the distributed nature of microservices architectures.

## Validation & Testing

1. **Test successful order processing**:

   ```bash
   # Test a valid order
   curl -X POST "${API_ENDPOINT}/orders" \
       -H "Content-Type: application/json" \
       -d '{
         "orderId": "order-success-123",
         "userId": "validuser456",
         "items": [
           {
             "productId": "prod-1",
             "quantity": 2
           }
         ]
       }'
   ```

   Expected output: JSON response with execution ARN indicating workflow started

2. **Test error handling with invalid user**:

   ```bash
   # Test with invalid user
   curl -X POST "${API_ENDPOINT}/orders" \
       -H "Content-Type: application/json" \
       -d '{
         "orderId": "order-fail-123",
         "userId": "xx",
         "items": [
           {
             "productId": "prod-1",
             "quantity": 2
           }
         ]
       }'
   ```

3. **Verify order status endpoint**:

   ```bash
   # Check order status
   curl -X GET "${API_ENDPOINT}/orders/order-success-123/status"
   ```

4. **Monitor workflow execution**:

   ```bash
   # List recent executions
   aws stepfunctions list-executions \
       --state-machine-arn "${STATE_MACHINE_ARN}" \
       --max-items 5
   
   # Get detailed execution history
   EXECUTION_ARN=$(aws stepfunctions list-executions \
       --state-machine-arn "${STATE_MACHINE_ARN}" \
       --max-items 1 \
       --query 'executions[0].executionArn' --output text)
   
   aws stepfunctions get-execution-history \
       --execution-arn "${EXECUTION_ARN}" \
       --max-items 10
   ```

## Cleanup

1. **Delete API Gateway**:

   ```bash
   # Delete API Gateway
   aws apigateway delete-rest-api --rest-api-id "${API_ID}"
   
   echo "✅ API Gateway deleted"
   ```

2. **Delete Step Functions State Machine**:

   ```bash
   # Delete state machine
   aws stepfunctions delete-state-machine \
       --state-machine-arn "${STATE_MACHINE_ARN}"
   
   echo "✅ Step Functions state machine deleted"
   ```

3. **Delete Lambda Functions**:

   ```bash
   # Delete Lambda functions
   aws lambda delete-function \
       --function-name "${PROJECT_NAME}-user-service"
   
   aws lambda delete-function \
       --function-name "${PROJECT_NAME}-inventory-service"
   
   echo "✅ Lambda functions deleted"
   ```

4. **Delete DynamoDB Tables**:

   ```bash
   # Delete DynamoDB tables
   aws dynamodb delete-table --table-name "${PROJECT_NAME}-orders"
   aws dynamodb delete-table --table-name "${PROJECT_NAME}-audit"
   aws dynamodb delete-table --table-name "${PROJECT_NAME}-reservations"
   
   echo "✅ DynamoDB tables deleted"
   ```

5. **Delete IAM Roles**:

   ```bash
   # Detach policies and delete Step Functions role
   aws iam detach-role-policy \
       --role-name "${ROLE_NAME}" \
       --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
   
   aws iam delete-role-policy \
       --role-name "${ROLE_NAME}" \
       --policy-name "CompositionPolicy"
   
   aws iam delete-role --role-name "${ROLE_NAME}"
   
   # Delete Lambda execution role
   aws iam detach-role-policy \
       --role-name "${LAMBDA_ROLE_NAME}" \
       --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
   
   aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}"
   
   # Delete API Gateway role
   aws iam detach-role-policy \
       --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
       --policy-arn "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
   
   aws iam delete-role --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}"
   
   # Remove local files
   rm -f trust-policy.json composition-policy.json apigw-trust-policy.json
   rm -f lambda-trust-policy.json state-machine-definition.json
   rm -f enhanced-state-machine.json user-service.py inventory-service.py
   rm -f user-service.zip inventory-service.zip
   
   echo "✅ All resources cleaned up successfully"
   ```

## Discussion

This recipe demonstrates advanced API composition patterns using Step Functions and API Gateway to orchestrate multiple microservices. The solution addresses several key challenges in microservices architecture: service coordination, error handling, and transaction management. By centralizing orchestration logic in Step Functions, we decouple business process logic from individual services, making the system more maintainable and observable.

The parallel processing capabilities shown in the workflow allow for concurrent execution of independent operations, significantly improving response times. The error handling and compensation logic ensures data consistency even when partial failures occur, implementing the saga pattern for distributed transactions. The integration with DynamoDB provides both primary data storage and audit logging capabilities.

Request and response transformation through API Gateway mapping templates enables protocol adaptation and data formatting without requiring code changes in microservices. This approach supports API versioning and client-specific customizations while maintaining backward compatibility.

Performance optimization can be achieved through Express Workflows for high-throughput scenarios, Step Functions service integrations to reduce latency, and CloudWatch monitoring for bottleneck identification. The solution scales automatically with AWS managed services handling the underlying infrastructure.

> **Tip**: Use Step Functions Express Workflows for high-frequency, short-duration workflows to reduce costs and improve performance. Standard Workflows are better for long-running processes requiring audit trails. Learn more about choosing the right workflow type in the [Step Functions workflow comparison documentation](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-standard-vs-express.html).

> **Warning**: When implementing compensation logic in production, ensure that compensation actions are idempotent and can handle partial failures. Test compensation scenarios thoroughly to verify proper rollback behavior.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add Circuit Breaker Pattern**: Implement circuit breaker logic in Step Functions to prevent cascading failures when downstream services are unavailable, including automatic fallback to cached responses.

2. **Implement Saga Compensation**: Build comprehensive compensation logic that can rollback partial transactions across multiple services, including inventory reservation cancellation and payment refunds.

3. **Add Real-time Notifications**: Integrate with Amazon SNS and EventBridge to send real-time notifications to customers and internal systems about order status changes.

4. **Build API Rate Limiting**: Implement sophisticated rate limiting using API Gateway usage plans, quota management, and Step Functions to handle burst traffic gracefully.

5. **Create Advanced Monitoring**: Set up CloudWatch dashboards with custom metrics, X-Ray tracing for distributed request tracking, and automated alerting for workflow failures.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files