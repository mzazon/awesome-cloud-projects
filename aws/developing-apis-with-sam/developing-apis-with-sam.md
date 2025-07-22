---
title: Developing APIs with SAM and API Gatewayexisting_folder_name
id: f7ad8d96
category: serverless
difficulty: 300
subject: aws
services: AWS SAM, API Gateway, Lambda, CloudFormation
estimated-time: 180 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: serverless, api-gateway, lambda, sam, infrastructure-as-code
recipe-generator-version: 1.3
---

# Developing APIs with SAM and API Gatewayexisting_folder_name

## Problem

Software development teams struggle to build, test, and deploy serverless APIs efficiently, often spending excessive time on infrastructure setup and configuration management. Traditional API development requires manual coordination between multiple AWS services, complex deployment pipelines, and time-consuming local testing environments. Development teams need a streamlined approach that accelerates serverless API development while maintaining production-ready standards and enabling rapid iteration cycles.

## Solution

AWS Serverless Application Model (SAM) provides a simplified infrastructure-as-code framework that streamlines serverless API development by automatically provisioning and configuring API Gateway, Lambda functions, and supporting resources. SAM's shorthand syntax reduces boilerplate code while enabling local development and testing capabilities that accelerate the development lifecycle from code to production deployment.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[API Clients]
    end
    
    subgraph "AWS Cloud"
        subgraph "API Gateway"
            API[REST API]
            STAGE[Stage: dev/prod]
        end
        
        subgraph "Lambda Functions"
            GET_FUNC[GET /users Function]
            POST_FUNC[POST /users Function]
            PUT_FUNC[PUT /users/{id} Function]
            DELETE_FUNC[DELETE /users/{id} Function]
        end
        
        subgraph "Storage"
            DYNAMO[DynamoDB Table]
        end
        
        subgraph "Monitoring"
            LOGS[CloudWatch Logs]
            METRICS[CloudWatch Metrics]
        end
        
        subgraph "Development"
            SAM_CLI[SAM CLI]
            LOCAL_API[Local API Gateway]
            LOCAL_LAMBDA[Local Lambda]
        end
    end
    
    CLIENT --> API
    API --> STAGE
    STAGE --> GET_FUNC
    STAGE --> POST_FUNC
    STAGE --> PUT_FUNC
    STAGE --> DELETE_FUNC
    
    GET_FUNC --> DYNAMO
    POST_FUNC --> DYNAMO
    PUT_FUNC --> DYNAMO
    DELETE_FUNC --> DYNAMO
    
    GET_FUNC --> LOGS
    POST_FUNC --> LOGS
    PUT_FUNC --> LOGS
    DELETE_FUNC --> LOGS
    
    GET_FUNC --> METRICS
    POST_FUNC --> METRICS
    PUT_FUNC --> METRICS
    DELETE_FUNC --> METRICS
    
    SAM_CLI --> LOCAL_API
    SAM_CLI --> LOCAL_LAMBDA
    LOCAL_API --> LOCAL_LAMBDA
    
    style API fill:#FF9900
    style DYNAMO fill:#FF9900
    style SAM_CLI fill:#3F8624
    style LOCAL_API fill:#3F8624
```

## Prerequisites

1. AWS account with appropriate permissions for Lambda, API Gateway, DynamoDB, CloudFormation, and IAM
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. SAM CLI installed and configured
4. Python 3.9+ installed locally for development and testing
5. Basic knowledge of REST API design and serverless architecture
6. Estimated cost: $5-10 for DynamoDB, Lambda, and API Gateway usage during development

> **Note**: SAM CLI installation varies by operating system. See the [SAM CLI installation guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) for detailed instructions.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifier for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export PROJECT_NAME="sam-api-${RANDOM_SUFFIX}"
export DYNAMO_TABLE_NAME="users-${RANDOM_SUFFIX}"

# Create project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

echo "✅ Environment prepared with project: $PROJECT_NAME"
```

## Steps

1. **Initialize SAM Application**:

   SAM CLI provides project templates that accelerate serverless application development by generating boilerplate code, configuration files, and directory structures. The "hello-world" template creates a foundational serverless application with Lambda function examples and a basic SAM template, providing the starting point for our API development.

   ```bash
   # Initialize new SAM application with API template
   sam init --runtime python3.9 --name "$PROJECT_NAME" \
       --app-template "hello-world" --no-interactive
   
   # Navigate to project directory
   cd "$PROJECT_NAME"
   
   echo "✅ SAM application initialized"
   ```

   The SAM project structure is now established with template.yaml for infrastructure definition and source code directories. This foundation enables rapid development by providing pre-configured build settings, deployment parameters, and local testing capabilities that mirror AWS production environments.

2. **Configure SAM Template for API Development**:

   SAM templates use CloudFormation syntax with serverless-specific transforms that simplify API Gateway and Lambda configuration. By defining our API structure declaratively, we ensure consistent deployments across environments while leveraging SAM's automatic generation of IAM policies, API Gateway resources, and Lambda triggers. This approach eliminates manual resource coordination and reduces configuration errors.

   ```bash
   # Backup original template
   cp template.yaml template.yaml.backup
   
   # Create comprehensive SAM template
   cat > template.yaml << 'EOF'
   AWSTemplateFormatVersion: '2010-09-09'
   Transform: AWS::Serverless-2016-10-31
   Description: Serverless API Development with SAM and API Gateway
   
   Globals:
     Function:
       Timeout: 30
       MemorySize: 128
       Runtime: python3.9
       Environment:
         Variables:
           DYNAMODB_TABLE: !Ref UsersTable
           CORS_ALLOW_ORIGIN: '*'
   
   Resources:
     UsersApi:
       Type: AWS::Serverless::Api
       Properties:
         StageName: dev
         Cors:
           AllowMethods: "'GET,POST,PUT,DELETE,OPTIONS'"
           AllowHeaders: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
           AllowOrigin: "'*'"
   
     # GET /users - List all users
     ListUsersFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: src/list_users/
         Handler: app.lambda_handler
         Events:
           Api:
             Type: Api
             Properties:
               RestApiId: !Ref UsersApi
               Path: /users
               Method: GET
         Policies:
           - DynamoDBReadPolicy:
               TableName: !Ref UsersTable
   
     # POST /users - Create new user
     CreateUserFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: src/create_user/
         Handler: app.lambda_handler
         Events:
           Api:
             Type: Api
             Properties:
               RestApiId: !Ref UsersApi
               Path: /users
               Method: POST
         Policies:
           - DynamoDBWritePolicy:
               TableName: !Ref UsersTable
   
     # GET /users/{id} - Get specific user
     GetUserFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: src/get_user/
         Handler: app.lambda_handler
         Events:
           Api:
             Type: Api
             Properties:
               RestApiId: !Ref UsersApi
               Path: /users/{id}
               Method: GET
         Policies:
           - DynamoDBReadPolicy:
               TableName: !Ref UsersTable
   
     # PUT /users/{id} - Update user
     UpdateUserFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: src/update_user/
         Handler: app.lambda_handler
         Events:
           Api:
             Type: Api
             Properties:
               RestApiId: !Ref UsersApi
               Path: /users/{id}
               Method: PUT
         Policies:
           - DynamoDBWritePolicy:
               TableName: !Ref UsersTable
   
     # DELETE /users/{id} - Delete user
     DeleteUserFunction:
       Type: AWS::Serverless::Function
       Properties:
         CodeUri: src/delete_user/
         Handler: app.lambda_handler
         Events:
           Api:
             Type: Api
             Properties:
               RestApiId: !Ref UsersApi
               Path: /users/{id}
               Method: DELETE
         Policies:
           - DynamoDBWritePolicy:
               TableName: !Ref UsersTable
   
     # DynamoDB Table
     UsersTable:
       Type: AWS::DynamoDB::Table
       Properties:
         TableName: !Sub "${AWS::StackName}-users"
         AttributeDefinitions:
           - AttributeName: id
             AttributeType: S
         KeySchema:
           - AttributeName: id
             KeyType: HASH
         BillingMode: PAY_PER_REQUEST
   
   Outputs:
     ApiGatewayUrl:
       Description: API Gateway endpoint URL
       Value: !Sub "https://${UsersApi}.execute-api.${AWS::Region}.amazonaws.com/dev/"
       Export:
         Name: !Sub "${AWS::StackName}-ApiUrl"
     
     UsersTableName:
       Description: DynamoDB table name
       Value: !Ref UsersTable
       Export:
         Name: !Sub "${AWS::StackName}-TableName"
   EOF
   
   echo "✅ SAM template configured with API Gateway and DynamoDB"
   ```

   The SAM template now defines a complete serverless API architecture with API Gateway for request routing, Lambda functions for business logic, and DynamoDB for data persistence. SAM's policy templates automatically generate least-privilege IAM permissions, while the Globals section ensures consistent function configurations across all Lambda functions.

> **Warning**: Using CORS origin '*' allows requests from any domain. In production environments, restrict CORS origins to specific domains for enhanced security.

3. **Create Lambda Function Source Code Structure**:

   Organizing Lambda functions in separate directories promotes code maintainability and enables independent function deployment. This microservices-oriented structure aligns with serverless best practices by keeping each function focused on a single responsibility, reducing deployment risk, and enabling granular scaling based on individual function usage patterns.

   ```bash
   # Remove default hello_world directory
   rm -rf hello_world/
   
   # Create function directories
   mkdir -p src/{list_users,create_user,get_user,update_user,delete_user}
   
   # Create shared utilities
   mkdir -p src/shared
   
   echo "✅ Lambda function directories created"
   ```

   The modular directory structure now supports independent function development and deployment. The shared utilities directory promotes code reuse while maintaining separation of concerns, enabling teams to work on different API endpoints simultaneously without conflicts.

4. **Implement Shared Utilities**:

   Centralizing common functionality in shared utilities reduces code duplication and ensures consistent error handling, response formatting, and database operations across all Lambda functions. This approach simplifies maintenance, improves code quality, and provides standardized API responses that enhance client application development.

   ```bash
   # Create shared utilities for DynamoDB operations
   cat > src/shared/dynamodb_utils.py << 'EOF'
   import json
   import boto3
   from botocore.exceptions import ClientError
   
   dynamodb = boto3.resource('dynamodb')
   
   def get_table():
       import os
       table_name = os.environ.get('DYNAMODB_TABLE')
       return dynamodb.Table(table_name)
   
   def create_response(status_code, body, headers=None):
       default_headers = {
           'Content-Type': 'application/json',
           'Access-Control-Allow-Origin': '*',
           'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
           'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
       }
       
       if headers:
           default_headers.update(headers)
       
       return {
           'statusCode': status_code,
           'headers': default_headers,
           'body': json.dumps(body) if isinstance(body, (dict, list)) else body
       }
   
   def handle_dynamodb_error(error):
       if error.response['Error']['Code'] == 'ResourceNotFoundException':
           return create_response(404, {'error': 'Resource not found'})
       else:
           return create_response(500, {'error': 'Internal server error'})
   EOF
   
   echo "✅ Shared utilities created"
   ```

   The shared utilities now provide standardized DynamoDB operations, HTTP response formatting, and error handling patterns. These utilities ensure consistent API behavior across all endpoints while implementing security best practices like CORS headers and proper error message sanitization.

5. **Implement Lambda Functions**:

   Each Lambda function implements a specific API endpoint with proper error handling, input validation, and business logic. By separating CRUD operations into individual functions, we achieve fine-grained scalability where each endpoint can scale independently based on usage patterns, optimizing cost and performance for different API operations.

   ```bash
   # List Users Function
   cat > src/list_users/app.py << 'EOF'
   import json
   import sys
   import os
   
   # Add shared directory to path
   sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))
   
   from dynamodb_utils import get_table, create_response, handle_dynamodb_error
   from botocore.exceptions import ClientError
   
   def lambda_handler(event, context):
       try:
           table = get_table()
           
           # Scan table for all users
           response = table.scan()
           users = response.get('Items', [])
           
           # Handle pagination if needed
           while 'LastEvaluatedKey' in response:
               response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
               users.extend(response.get('Items', []))
           
           return create_response(200, users)
           
       except ClientError as e:
           return handle_dynamodb_error(e)
       except Exception as e:
           return create_response(500, {'error': str(e)})
   EOF
   
   # Create User Function
   cat > src/create_user/app.py << 'EOF'
   import json
   import sys
   import os
   import uuid
   from datetime import datetime
   
   # Add shared directory to path
   sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))
   
   from dynamodb_utils import get_table, create_response, handle_dynamodb_error
   from botocore.exceptions import ClientError
   
   def lambda_handler(event, context):
       try:
           # Parse request body
           body = json.loads(event.get('body', '{}'))
           
           # Validate required fields
           if not body.get('name') or not body.get('email'):
               return create_response(400, {'error': 'Name and email are required'})
           
           # Generate user ID and timestamp
           user_id = str(uuid.uuid4())
           timestamp = datetime.utcnow().isoformat()
           
           # Create user item
           user_item = {
               'id': user_id,
               'name': body['name'],
               'email': body['email'],
               'created_at': timestamp,
               'updated_at': timestamp
           }
           
           # Optional fields
           if body.get('age'):
               user_item['age'] = int(body['age'])
           
           # Put item in DynamoDB
           table = get_table()
           table.put_item(Item=user_item)
           
           return create_response(201, user_item)
           
       except ClientError as e:
           return handle_dynamodb_error(e)
       except ValueError as e:
           return create_response(400, {'error': 'Invalid JSON in request body'})
       except Exception as e:
           return create_response(500, {'error': str(e)})
   EOF
   
   # Get User Function
   cat > src/get_user/app.py << 'EOF'
   import json
   import sys
   import os
   
   # Add shared directory to path
   sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))
   
   from dynamodb_utils import get_table, create_response, handle_dynamodb_error
   from botocore.exceptions import ClientError
   
   def lambda_handler(event, context):
       try:
           # Get user ID from path parameters
           user_id = event['pathParameters']['id']
           
           # Get item from DynamoDB
           table = get_table()
           response = table.get_item(Key={'id': user_id})
           
           if 'Item' not in response:
               return create_response(404, {'error': 'User not found'})
           
           return create_response(200, response['Item'])
           
       except ClientError as e:
           return handle_dynamodb_error(e)
       except Exception as e:
           return create_response(500, {'error': str(e)})
   EOF
   
   # Update User Function
   cat > src/update_user/app.py << 'EOF'
   import json
   import sys
   import os
   from datetime import datetime
   
   # Add shared directory to path
   sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))
   
   from dynamodb_utils import get_table, create_response, handle_dynamodb_error
   from botocore.exceptions import ClientError
   
   def lambda_handler(event, context):
       try:
           # Get user ID from path parameters
           user_id = event['pathParameters']['id']
           
           # Parse request body
           body = json.loads(event.get('body', '{}'))
           
           # Check if user exists
           table = get_table()
           response = table.get_item(Key={'id': user_id})
           
           if 'Item' not in response:
               return create_response(404, {'error': 'User not found'})
           
           # Build update expression
           update_expression = "SET updated_at = :timestamp"
           expression_values = {':timestamp': datetime.utcnow().isoformat()}
           
           if body.get('name'):
               update_expression += ", #name = :name"
               expression_values[':name'] = body['name']
           
           if body.get('email'):
               update_expression += ", email = :email"
               expression_values[':email'] = body['email']
           
           if body.get('age'):
               update_expression += ", age = :age"
               expression_values[':age'] = int(body['age'])
           
           # Update item
           response = table.update_item(
               Key={'id': user_id},
               UpdateExpression=update_expression,
               ExpressionAttributeNames={'#name': 'name'} if body.get('name') else {},
               ExpressionAttributeValues=expression_values,
               ReturnValues='ALL_NEW'
           )
           
           return create_response(200, response['Attributes'])
           
       except ClientError as e:
           return handle_dynamodb_error(e)
       except ValueError as e:
           return create_response(400, {'error': 'Invalid JSON in request body'})
       except Exception as e:
           return create_response(500, {'error': str(e)})
   EOF
   
   # Delete User Function
   cat > src/delete_user/app.py << 'EOF'
   import json
   import sys
   import os
   
   # Add shared directory to path
   sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))
   
   from dynamodb_utils import get_table, create_response, handle_dynamodb_error
   from botocore.exceptions import ClientError
   
   def lambda_handler(event, context):
       try:
           # Get user ID from path parameters
           user_id = event['pathParameters']['id']
           
           # Check if user exists
           table = get_table()
           response = table.get_item(Key={'id': user_id})
           
           if 'Item' not in response:
               return create_response(404, {'error': 'User not found'})
           
           # Delete item
           table.delete_item(Key={'id': user_id})
           
           return create_response(204, '')
           
       except ClientError as e:
           return handle_dynamodb_error(e)
       except Exception as e:
           return create_response(500, {'error': str(e)})
   EOF
   
   echo "✅ Lambda functions implemented"
   ```

   All CRUD operations are now implemented with comprehensive error handling, input validation, and consistent response formatting. Each function demonstrates serverless best practices including proper exception handling, DynamoDB pagination for large datasets, and atomic operations for data consistency.

6. **Create Function Dependencies**:

   Managing dependencies at the function level enables precise control over package versions and deployment package sizes. SAM automatically installs these dependencies during the build process, creating optimized Lambda deployment packages that include only necessary libraries, reducing cold start times and deployment complexity.

   ```bash
   # Create requirements.txt for each function
   for func in list_users create_user get_user update_user delete_user; do
       cat > "src/${func}/requirements.txt" << 'EOF'
   boto3==1.26.137
   botocore==1.29.137
   EOF
   done
   
   echo "✅ Function dependencies configured"
   ```

   Function-specific dependencies are now configured with pinned versions for consistent deployments. This approach prevents dependency conflicts and ensures reproducible builds across development, staging, and production environments.

7. **Build and Test Locally**:

   SAM's local development environment replicates AWS Lambda and API Gateway behavior on your local machine, enabling rapid development cycles without cloud resource costs. The `sam build` command packages functions with their dependencies, while `sam local start-api` creates a local API Gateway that routes requests to containerized Lambda functions running locally.

   ```bash
   # Build the SAM application
   sam build
   
   # Start local API Gateway and Lambda
   sam local start-api --port 3000 &
   LOCAL_API_PID=$!
   
   # Wait for local API to start
   sleep 5
   
   # Test local API endpoints
   echo "Testing local API endpoints..."
   
   # Test GET /users (should return empty array)
   curl -s http://localhost:3000/users | python3 -m json.tool
   
   # Kill local API process
   kill $LOCAL_API_PID 2>/dev/null
   
   echo "✅ Local build and testing completed"
   ```

   Local testing validates API functionality before cloud deployment, reducing development costs and accelerating feedback loops. The local environment accurately simulates Lambda execution context, API Gateway request/response transformation, and environment variables, ensuring high fidelity between local and production behavior.

> **Note**: SAM local testing requires Docker to be installed and running. The local environment creates containerized Lambda functions that mirror the AWS execution environment. See [SAM Local documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-cli-command-reference-sam-local.html) for troubleshooting guidance.

8. **Deploy to AWS**:

   SAM deployment leverages CloudFormation to create and manage all AWS resources as a single stack, ensuring atomic deployments and consistent resource lifecycle management. The guided deployment prompts for configuration parameters and stores them in samconfig.toml for subsequent deployments, streamlining the deployment process for CI/CD pipelines.

   ```bash
   # Deploy using guided deployment
   sam deploy --guided --stack-name "$PROJECT_NAME"
   
   # Store API Gateway URL for testing
   API_URL=$(aws cloudformation describe-stacks \
       --stack-name "$PROJECT_NAME" \
       --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
       --output text)
   
   echo "API Gateway URL: $API_URL"
   echo "✅ Application deployed successfully"
   ```

   The serverless API is now live in AWS with all resources properly configured and secured. CloudFormation outputs provide access to key resource identifiers like the API Gateway URL, enabling automated testing and integration with external systems.

9. **Create Test Data and Validate API**:

   Post-deployment validation ensures all API endpoints function correctly in the production environment. Creating test data through the API validates the complete request flow from API Gateway through Lambda to DynamoDB, confirming proper service integration and data persistence capabilities.

   ```bash
   # Create test users
   USER1_ID=$(curl -s -X POST "${API_URL}users" \
       -H "Content-Type: application/json" \
       -d '{"name": "John Doe", "email": "john@example.com", "age": 30}' \
       | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
   
   USER2_ID=$(curl -s -X POST "${API_URL}users" \
       -H "Content-Type: application/json" \
       -d '{"name": "Jane Smith", "email": "jane@example.com", "age": 25}' \
       | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
   
   echo "Created test users with IDs: $USER1_ID, $USER2_ID"
   echo "✅ Test data created"
   ```

   Test data creation confirms that the entire serverless stack operates correctly, from API Gateway request validation through Lambda function execution to DynamoDB data storage. The captured user IDs enable comprehensive testing of all CRUD operations.

10. **Configure API Monitoring**:

    CloudWatch monitoring provides essential observability into API performance, error rates, and usage patterns. Establishing monitoring infrastructure from the start enables proactive issue detection, performance optimization, and capacity planning, ensuring optimal user experience and operational excellence.

    ```bash
    # Create CloudWatch dashboard for API monitoring
    cat > api-dashboard.json << EOF
    {
        "widgets": [
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/ApiGateway", "Count", "ApiName", "${PROJECT_NAME}"],
                        ["AWS/ApiGateway", "Latency", "ApiName", "${PROJECT_NAME}"],
                        ["AWS/ApiGateway", "4XXError", "ApiName", "${PROJECT_NAME}"],
                        ["AWS/ApiGateway", "5XXError", "ApiName", "${PROJECT_NAME}"]
                    ],
                    "period": 300,
                    "stat": "Sum",
                    "region": "${AWS_REGION}",
                    "title": "API Gateway Metrics"
                }
            }
        ]
    }
    EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-api-monitoring" \
        --dashboard-body file://api-dashboard.json
    
    echo "✅ API monitoring dashboard created"
    ```

    Comprehensive monitoring is now in place to track API performance metrics, error rates, and usage patterns. The CloudWatch dashboard provides real-time visibility into system health and enables data-driven optimization decisions for the serverless API architecture.

## Validation & Testing

1. **Test API Gateway endpoints**:

   ```bash
   # Test GET /users - List all users
   echo "Testing GET /users..."
   curl -s "${API_URL}users" | python3 -m json.tool
   ```

   Expected output: JSON array with two user objects

2. **Test individual user retrieval**:

   ```bash
   # Test GET /users/{id} - Get specific user
   echo "Testing GET /users/{id}..."
   curl -s "${API_URL}users/${USER1_ID}" | python3 -m json.tool
   ```

   Expected output: JSON object with user details

3. **Test user update**:

   ```bash
   # Test PUT /users/{id} - Update user
   echo "Testing PUT /users/{id}..."
   curl -s -X PUT "${API_URL}users/${USER1_ID}" \
       -H "Content-Type: application/json" \
       -d '{"name": "John Updated", "age": 31}' \
       | python3 -m json.tool
   ```

   Expected output: JSON object with updated user details

4. **Verify DynamoDB table**:

   ```bash
   # Check DynamoDB table contents
   TABLE_NAME=$(aws cloudformation describe-stacks \
       --stack-name "$PROJECT_NAME" \
       --query 'Stacks[0].Outputs[?OutputKey==`UsersTableName`].OutputValue' \
       --output text)
   
   aws dynamodb scan --table-name "$TABLE_NAME"
   ```

   Expected output: DynamoDB scan results showing user items

5. **Test error handling**:

   ```bash
   # Test 404 error for non-existent user
   curl -s "${API_URL}users/nonexistent-id" | python3 -m json.tool
   
   # Test 400 error for invalid JSON
   curl -s -X POST "${API_URL}users" \
       -H "Content-Type: application/json" \
       -d '{"invalid": "json"' | python3 -m json.tool
   ```

## Cleanup

1. **Delete CloudFormation stack**:

   ```bash
   # Delete the SAM application stack
   aws cloudformation delete-stack --stack-name "$PROJECT_NAME"
   
   # Wait for stack deletion
   aws cloudformation wait stack-delete-complete \
       --stack-name "$PROJECT_NAME"
   
   echo "✅ CloudFormation stack deleted"
   ```

2. **Remove CloudWatch dashboard**:

   ```bash
   # Delete CloudWatch dashboard
   aws cloudwatch delete-dashboards \
       --dashboard-names "${PROJECT_NAME}-api-monitoring"
   
   echo "✅ CloudWatch dashboard deleted"
   ```

3. **Clean up local files**:

   ```bash
   # Remove project directory
   cd ..
   rm -rf "$PROJECT_NAME"
   
   # Clean up environment variables
   unset PROJECT_NAME DYNAMO_TABLE_NAME API_URL USER1_ID USER2_ID TABLE_NAME
   
   echo "✅ Local cleanup completed"
   ```

## Discussion

AWS SAM dramatically simplifies serverless API development by providing infrastructure-as-code templates that automatically provision and configure API Gateway, Lambda functions, and supporting AWS services. The framework's shorthand syntax reduces the complexity of CloudFormation templates while maintaining full compatibility with AWS CloudFormation, enabling developers to focus on business logic rather than infrastructure management.

SAM's local development capabilities are particularly valuable for API development workflows. The `sam local start-api` command creates a local API Gateway environment that mirrors the production configuration, allowing developers to test API endpoints, debug Lambda functions, and validate request/response patterns before deployment. This local-first approach accelerates development cycles and reduces cloud resource costs during development.

The template-driven approach ensures consistency across environments and simplifies CI/CD pipeline integration. SAM automatically handles complex configurations like CORS settings, IAM policies, and service integrations, while providing granular control when needed. The framework's built-in best practices, such as automatic CloudWatch logging and X-Ray tracing integration, promote operational excellence from the start.

> **Tip**: Use SAM's built-in policy templates like `DynamoDBReadPolicy` and `DynamoDBWritePolicy` to automatically generate least-privilege IAM policies for your Lambda functions.

## Challenge

Extend this serverless API solution by implementing these enhancements:

1. **Add Authentication**: Integrate Amazon Cognito User Pools for JWT-based authentication and implement request validation middleware
2. **Implement Caching**: Add ElastiCache Redis integration for user data caching and implement cache invalidation strategies
3. **Add Advanced Monitoring**: Implement distributed tracing with X-Ray, custom CloudWatch metrics, and automated alerting for API performance degradation
4. **Create CI/CD Pipeline**: Build a CodePipeline workflow that automatically tests, builds, and deploys API changes across multiple environments
5. **Add API Versioning**: Implement API versioning strategies using API Gateway stages and Lambda function versioning with traffic shifting capabilities

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*