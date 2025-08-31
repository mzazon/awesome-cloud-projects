---
title: Simple Random Data API with Lambda and API Gateway
id: a1f3d9e7
category: serverless
difficulty: 100
subject: aws
services: Lambda, API Gateway
estimated-time: 25 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: serverless, api, lambda, beginners, rest
recipe-generator-version: 1.3
---

# Simple Random Data API with Lambda and API Gateway

## Problem

New developers learning cloud development need a straightforward way to understand serverless APIs without complex infrastructure management. Traditional server-based APIs require provisioning, scaling, and maintaining infrastructure, creating barriers for beginners who want to focus on API functionality rather than server administration.

## Solution

Create a serverless REST API using AWS Lambda for compute and API Gateway for HTTP routing that generates random data including quotes, numbers, and colors. This approach eliminates server management while providing a scalable, cost-effective API that automatically handles traffic spikes and scales to zero when not in use.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[API Client/Browser]
    end
    
    subgraph "AWS API Gateway"
        GATEWAY[REST API Gateway]
        RESOURCE[/random Resource]
        METHOD[GET Method]
    end
    
    subgraph "AWS Lambda"
        FUNCTION[Random Data Function<br/>Python 3.12]
        LOGIC[Random Generation Logic]
    end
    
    subgraph "AWS CloudWatch"
        LOGS[Function Logs]
        METRICS[API Metrics]
    end
    
    CLIENT-->GATEWAY
    GATEWAY-->RESOURCE
    RESOURCE-->METHOD
    METHOD-->FUNCTION
    FUNCTION-->LOGIC
    FUNCTION-->LOGS
    GATEWAY-->METRICS
    
    FUNCTION-.->CLIENT
    
    style FUNCTION fill:#FF9900
    style GATEWAY fill:#FF4B4B
    style CLIENT fill:#4B8BFF
```

## Prerequisites

1. AWS account with Lambda and API Gateway permissions
2. AWS CLI v2 installed and configured with appropriate credentials
3. Basic understanding of REST APIs and JSON responses
4. Text editor or IDE for writing Python code
5. Estimated cost: $0.00-$0.20 for testing (within AWS Free Tier limits)

> **Note**: This recipe uses AWS Free Tier resources. Lambda provides 1 million free requests per month, and API Gateway provides 1 million free API calls per month for the first 12 months.

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

# Set resource names
export FUNCTION_NAME="random-data-api-${RANDOM_SUFFIX}"
export ROLE_NAME="lambda-random-api-role-${RANDOM_SUFFIX}"
export API_NAME="random-data-api-${RANDOM_SUFFIX}"

echo "✅ AWS environment configured"
echo "Function Name: ${FUNCTION_NAME}"
echo "Role Name: ${ROLE_NAME}"
echo "API Name: ${API_NAME}"
```

## Steps

1. **Create IAM Role for Lambda Function**:

   Lambda functions require an IAM role to execute and write logs to CloudWatch. This role follows the principle of least privilege by granting only the basic execution permissions needed for serverless function operation, adhering to AWS security best practices.

   ```bash
   # Create trust policy for Lambda service
   cat > trust-policy.json << EOF
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
   
   # Create IAM role
   aws iam create-role \
       --role-name ${ROLE_NAME} \
       --assume-role-policy-document file://trust-policy.json
   
   # Attach basic execution policy
   aws iam attach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Get role ARN for later use
   export ROLE_ARN=$(aws iam get-role \
       --role-name ${ROLE_NAME} \
       --query Role.Arn --output text)
   
   echo "✅ IAM role created: ${ROLE_ARN}"
   ```

2. **Create Lambda Function Code**:

   The Lambda function generates three types of random data using Python's built-in libraries. This demonstrates serverless compute capabilities while providing educational value for API response formatting, error handling, and proper logging practices integrated with CloudWatch.

   ```bash
   # Create function code directory
   mkdir lambda-function
   cd lambda-function
   
   # Create the main function file
   cat > lambda_function.py << 'EOF'
   import json
   import random
   import logging
   
   # Configure logging
   logger = logging.getLogger()
   logger.setLevel(logging.INFO)
   
   def lambda_handler(event, context):
       """
       AWS Lambda handler for random data API
       Returns random quotes, numbers, or colors based on query parameter
       """
       
       try:
           # Log the incoming request
           logger.info(f"Received event: {json.dumps(event)}")
           
           # Parse query parameters
           query_params = event.get('queryStringParameters') or {}
           data_type = query_params.get('type', 'quote').lower()
           
           # Random data collections
           quotes = [
               "The only way to do great work is to love what you do. - Steve Jobs",
               "Innovation distinguishes between a leader and a follower. - Steve Jobs",
               "Life is what happens to you while you're busy making other plans. - John Lennon",
               "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
               "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill"
           ]
           
           colors = [
               {"name": "Ocean Blue", "hex": "#006994", "rgb": "rgb(0, 105, 148)"},
               {"name": "Sunset Orange", "hex": "#FF6B35", "rgb": "rgb(255, 107, 53)"},
               {"name": "Forest Green", "hex": "#2E8B57", "rgb": "rgb(46, 139, 87)"},
               {"name": "Purple Haze", "hex": "#9370DB", "rgb": "rgb(147, 112, 219)"},
               {"name": "Golden Yellow", "hex": "#FFD700", "rgb": "rgb(255, 215, 0)"}
           ]
           
           # Generate response based on type
           if data_type == 'quote':
               data = random.choice(quotes)
           elif data_type == 'number':
               data = random.randint(1, 1000)
           elif data_type == 'color':
               data = random.choice(colors)
           else:
               # Default to quote for unknown types
               data = random.choice(quotes)
               data_type = 'quote'
           
           # Create response
           response_body = {
               'type': data_type,
               'data': data,
               'timestamp': context.aws_request_id,
               'message': f'Random {data_type} generated successfully'
           }
           
           # Return successful response with CORS headers
           return {
               'statusCode': 200,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*',
                   'Access-Control-Allow-Methods': 'GET',
                   'Access-Control-Allow-Headers': 'Content-Type'
               },
               'body': json.dumps(response_body)
           }
           
       except Exception as e:
           logger.error(f"Error processing request: {str(e)}")
           
           # Return error response
           return {
               'statusCode': 500,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*'
               },
               'body': json.dumps({
                   'error': 'Internal server error',
                   'message': 'Failed to generate random data'
               })
           }
   EOF
   
   echo "✅ Lambda function code created"
   ```

3. **Package and Deploy Lambda Function**:

   Lambda deployment packages contain your code and dependencies. For simple Python functions, a ZIP archive provides an efficient deployment method that enables quick updates and version management while maintaining compatibility with AWS Lambda's execution environment.

   ```bash
   # Create deployment package
   zip -r function.zip lambda_function.py
   
   # Create Lambda function with latest Python runtime
   aws lambda create-function \
       --function-name ${FUNCTION_NAME} \
       --runtime python3.12 \
       --role ${ROLE_ARN} \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://function.zip \
       --timeout 30 \
       --memory-size 128 \
       --description "Random data API generator"
   
   # Wait for function to be active
   aws lambda wait function-active \
       --function-name ${FUNCTION_NAME}
   
   cd ..
   echo "✅ Lambda function deployed: ${FUNCTION_NAME}"
   ```

4. **Create API Gateway REST API**:

   API Gateway acts as the front door for your serverless application, handling HTTP requests, request routing, and response formatting. Creating a REST API establishes the foundation for exposing your Lambda function as a web service with built-in features like throttling, monitoring, and caching.

   ```bash
   # Create REST API
   API_ID=$(aws apigateway create-rest-api \
       --name ${API_NAME} \
       --description "Random data API using Lambda" \
       --endpoint-configuration types=REGIONAL \
       --query id --output text)
   
   # Get root resource ID
   ROOT_RESOURCE_ID=$(aws apigateway get-resources \
       --rest-api-id ${API_ID} \
       --query 'items[?path==`/`].id' \
       --output text)
   
   echo "✅ API Gateway created: ${API_ID}"
   echo "Root Resource ID: ${ROOT_RESOURCE_ID}"
   ```

5. **Create API Resource and Method**:

   API Gateway resources define URL paths, while methods specify HTTP verbs (GET, POST, etc.). This configuration creates a /random endpoint that accepts GET requests and routes them to your Lambda function, following RESTful API design principles.

   ```bash
   # Create /random resource
   RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id ${API_ID} \
       --parent-id ${ROOT_RESOURCE_ID} \
       --path-part random \
       --query id --output text)
   
   # Create GET method
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${RESOURCE_ID} \
       --http-method GET \
       --authorization-type NONE
   
   echo "✅ API resource and method created"
   echo "Resource ID: ${RESOURCE_ID}"
   ```

6. **Configure Lambda Integration**:

   Lambda proxy integration allows API Gateway to pass all request data to your Lambda function and return the function's response directly to the client. This simplifies request/response handling while maintaining full control over HTTP responses and enables seamless integration between services.

   ```bash
   # Get Lambda function ARN
   FUNCTION_ARN=$(aws lambda get-function \
       --function-name ${FUNCTION_NAME} \
       --query Configuration.FunctionArn --output text)
   
   # Configure Lambda proxy integration
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${RESOURCE_ID} \
       --http-method GET \
       --type AWS_PROXY \
       --integration-http-method POST \
       --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations
   
   echo "✅ Lambda integration configured"
   ```

7. **Grant API Gateway Permission to Invoke Lambda**:

   AWS services require explicit permissions to interact with each other following the principle of least privilege. This resource-based policy allows API Gateway to invoke your Lambda function, completing the serverless API connection while maintaining security boundaries.

   ```bash
   # Add invoke permission for API Gateway
   aws lambda add-permission \
       --function-name ${FUNCTION_NAME} \
       --statement-id apigateway-invoke \
       --action lambda:InvokeFunction \
       --principal apigateway.amazonaws.com \
       --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
   
   echo "✅ API Gateway permissions configured"
   ```

8. **Deploy API to Stage**:

   API Gateway stages represent different environments (dev, test, prod) for your API, enabling environment-specific configurations and promoting changes through your development lifecycle. Deploying to a stage makes your API publicly accessible and provides a stable endpoint URL for client applications.

   ```bash
   # Deploy API to 'dev' stage
   aws apigateway create-deployment \
       --rest-api-id ${API_ID} \
       --stage-name dev \
       --description "Initial deployment of random data API"
   
   # Get API endpoint URL
   export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/dev/random"
   
   echo "✅ API deployed successfully"
   echo "API Endpoint: ${API_URL}"
   ```

## Validation & Testing

1. **Test Random Quote Generation**:

   ```bash
   # Test quote endpoint (default behavior)
   curl -X GET "${API_URL}" | jq .
   
   # Test with explicit quote parameter
   curl -X GET "${API_URL}?type=quote" | jq .
   ```

   Expected output: JSON response with random quote and metadata

2. **Test Random Number Generation**:

   ```bash
   # Test number generation
   curl -X GET "${API_URL}?type=number" | jq .
   ```

   Expected output: JSON response with random number between 1-1000

3. **Test Random Color Generation**:

   ```bash
   # Test color generation
   curl -X GET "${API_URL}?type=color" | jq .
   ```

   Expected output: JSON response with color name, hex value, and RGB values

4. **Verify Lambda Function Logs**:

   ```bash
   # Check recent Lambda function logs
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/${FUNCTION_NAME}"
   
   # View recent log events
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
       --start-time $(date -d '5 minutes ago' +%s)000
   ```

## Cleanup

1. **Delete API Gateway**:

   ```bash
   # Delete API Gateway
   aws apigateway delete-rest-api --rest-api-id ${API_ID}
   
   echo "✅ API Gateway deleted"
   ```

2. **Delete Lambda Function**:

   ```bash
   # Delete Lambda function
   aws lambda delete-function --function-name ${FUNCTION_NAME}
   
   echo "✅ Lambda function deleted"
   ```

3. **Delete IAM Role**:

   ```bash
   # Detach policy from role
   aws iam detach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Delete IAM role
   aws iam delete-role --role-name ${ROLE_NAME}
   
   echo "✅ IAM role deleted"
   ```

4. **Clean up local files**:

   ```bash
   # Remove temporary files
   rm -f trust-policy.json
   rm -rf lambda-function/
   
   echo "✅ Local files cleaned up"
   ```

## Discussion

This serverless API demonstrates the core principles of AWS's event-driven architecture, where compute resources are allocated dynamically based on incoming requests. Lambda's automatic scaling means your API can handle anything from a single request to thousands of concurrent requests without manual intervention. The pay-per-invocation pricing model ensures you only pay for actual usage, making this approach extremely cost-effective for APIs with variable or unpredictable traffic patterns.

API Gateway serves as more than just a routing layer—it provides essential features like request validation, response transformation, caching, and security controls. The proxy integration pattern used in this recipe simplifies development by passing all request details to your Lambda function, allowing you to handle routing logic in code rather than gateway configuration. This approach follows AWS Well-Architected principles by separating concerns and maintaining loose coupling between services.

The random data generation showcases common API patterns including query parameter processing, structured JSON responses, and error handling. The function demonstrates proper logging practices that integrate with CloudWatch, enabling monitoring and troubleshooting in production environments. Cross-Origin Resource Sharing (CORS) headers allow browser-based applications to consume your API, expanding its utility for web development projects.

For more comprehensive serverless development guidance, consult the [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html), [API Gateway REST API documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html), [Lambda function handler best practices](https://docs.aws.amazon.com/lambda/latest/dg/python-handler.html), [API Gateway Lambda integration patterns](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-integrations.html), and [AWS serverless application development guide](https://docs.aws.amazon.com/serverless/latest/devguide/welcome.html).

> **Tip**: Enable API Gateway access logging and Lambda function insights for production APIs to gain visibility into request patterns, error rates, and performance metrics that inform optimization decisions.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add request rate limiting** using API Gateway usage plans and API keys to prevent abuse and manage costs
2. **Implement response caching** in API Gateway to improve performance and reduce Lambda invocations for frequently requested data
3. **Create additional endpoints** for different data types (jokes, facts, weather) using separate Lambda functions or routing logic
4. **Add input validation** using API Gateway request validators to ensure query parameters meet expected formats before reaching Lambda
5. **Deploy using AWS SAM** or AWS CDK to enable infrastructure as code and simplify future deployments and updates

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*