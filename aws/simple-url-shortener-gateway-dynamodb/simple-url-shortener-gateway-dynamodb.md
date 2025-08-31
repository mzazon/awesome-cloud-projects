---
title: Simple URL Shortener with API Gateway and DynamoDB
id: a7b8c9d0
category: serverless
difficulty: 100
subject: aws
services: API Gateway, DynamoDB, Lambda
estimated-time: 25 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: serverless, api, url-shortener, rest-api, nosql
recipe-generator-version: 1.3
---

# Simple URL Shortener with API Gateway and DynamoDB

## Problem

Marketing teams and social media managers need to share long, complex URLs in character-limited environments like Twitter or SMS campaigns, but manually creating short links through third-party services creates workflow friction and dependency risks. These external services can become unavailable, change pricing models, or lack integration with existing AWS infrastructure, leading to broken links and lost traffic that directly impacts campaign effectiveness and customer experience.

## Solution

Build a serverless URL shortening service using AWS API Gateway, Lambda functions, and DynamoDB that creates compact short links and seamlessly redirects users to original URLs. This approach leverages AWS managed services to provide automatic scaling, built-in security, and cost-effective pay-per-use pricing while maintaining full control over the URL shortening infrastructure and analytics.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        USER[Users/Applications]
    end
    
    subgraph "API Layer"
        APIGW[API Gateway<br/>REST API]
    end
    
    subgraph "Compute Layer"
        CREATE[Lambda Function<br/>Create Short URL]
        REDIRECT[Lambda Function<br/>URL Redirect]
    end
    
    subgraph "Storage Layer"
        DDB[DynamoDB Table<br/>URL Mappings]
    end
    
    USER -->|POST /shorten| APIGW
    USER -->|GET /{shortCode}| APIGW
    APIGW -->|Create Request| CREATE
    APIGW -->|Redirect Request| REDIRECT
    CREATE --> DDB
    REDIRECT --> DDB
    
    style APIGW fill:#FF9900
    style CREATE fill:#FF9900
    style REDIRECT fill:#FF9900
    style DDB fill:#3F8624
```

## Prerequisites

1. AWS account with permissions for API Gateway, Lambda, DynamoDB, and IAM
2. AWS CLI v2 installed and configured (or AWS CloudShell access)
3. Basic understanding of REST APIs and HTTP status codes
4. Familiarity with JSON data structures
5. Estimated cost: $0.10-0.50 for testing (within AWS Free Tier limits)

> **Note**: This solution follows AWS Well-Architected Framework serverless principles for automatic scaling and cost optimization.

## Preparation

```bash
# Set environment variables for AWS configuration
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Set resource names with unique suffix
export TABLE_NAME="url-shortener-${RANDOM_SUFFIX}"
export ROLE_NAME="url-shortener-lambda-role-${RANDOM_SUFFIX}"
export CREATE_FUNCTION_NAME="url-shortener-create-${RANDOM_SUFFIX}"
export REDIRECT_FUNCTION_NAME="url-shortener-redirect-${RANDOM_SUFFIX}"
export API_NAME="url-shortener-api-${RANDOM_SUFFIX}"

echo "✅ AWS environment configured with unique identifiers"
```

## Steps

1. **Create DynamoDB Table for URL Storage**:

   DynamoDB provides single-digit millisecond latency and automatic scaling, making it ideal for URL lookup operations that require fast response times. The table design uses a simple primary key structure optimized for both creating new short URLs and retrieving original URLs during redirects.

   ```bash
   # Create DynamoDB table with on-demand billing
   aws dynamodb create-table \
       --table-name ${TABLE_NAME} \
       --attribute-definitions \
           AttributeName=shortCode,AttributeType=S \
       --key-schema \
           AttributeName=shortCode,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST \
       --tags Key=Project,Value=URLShortener
   
   # Wait for table creation to complete
   aws dynamodb wait table-exists --table-name ${TABLE_NAME}
   
   echo "✅ DynamoDB table ${TABLE_NAME} created successfully"
   ```

   The table uses on-demand billing mode, which automatically scales read and write capacity based on traffic patterns without requiring capacity planning. This approach aligns with serverless principles and provides cost optimization for variable workloads.

2. **Create IAM Role for Lambda Functions**:

   AWS Lambda requires an execution role with appropriate permissions to interact with DynamoDB and write logs to CloudWatch. This role follows the principle of least privilege by granting only the minimum permissions necessary for the URL shortener functionality.

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
   
   # Create IAM role for Lambda functions
   aws iam create-role \
       --role-name ${ROLE_NAME} \
       --assume-role-policy-document file://trust-policy.json
   
   # Attach basic Lambda execution policy
   aws iam attach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   echo "✅ IAM role ${ROLE_NAME} created with basic permissions"
   ```

3. **Create DynamoDB Access Policy**:

   ```bash
   # Create policy for DynamoDB access
   cat > dynamodb-policy.json << EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "dynamodb:GetItem",
                   "dynamodb:PutItem"
               ],
               "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
           }
       ]
   }
   EOF
   
   # Create and attach DynamoDB policy
   aws iam create-policy \
       --policy-name ${ROLE_NAME}-dynamodb-policy \
       --policy-document file://dynamodb-policy.json
   
   aws iam attach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy
   
   echo "✅ DynamoDB access policy attached to Lambda role"
   ```

4. **Create Lambda Function for URL Creation**:

   This Lambda function handles POST requests to create new short URLs by generating unique short codes and storing the URL mappings in DynamoDB. The function includes comprehensive error handling, URL validation, and CORS support to ensure data integrity and provide meaningful error responses.

   ```bash
   # Create Lambda function code for URL creation
   cat > create-function.py << 'EOF'
   import json
   import boto3
   import string
   import random
   import os
   import logging
   from urllib.parse import urlparse
   
   logger = logging.getLogger()
   logger.setLevel(logging.INFO)
   
   dynamodb = boto3.resource('dynamodb')
   table = dynamodb.Table(os.environ['TABLE_NAME'])
   
   def lambda_handler(event, context):
       try:
           logger.info(f"Received event: {json.dumps(event)}")
           
           # Parse request body
           if not event.get('body'):
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*',
                       'Access-Control-Allow-Headers': 'Content-Type',
                       'Access-Control-Allow-Methods': 'POST, OPTIONS'
                   },
                   'body': json.dumps({'error': 'Request body is required'})
               }
           
           body = json.loads(event['body'])
           original_url = body.get('url')
           
           # Validate URL presence
           if not original_url:
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*',
                       'Access-Control-Allow-Headers': 'Content-Type',
                       'Access-Control-Allow-Methods': 'POST, OPTIONS'
                   },
                   'body': json.dumps({'error': 'URL is required'})
               }
           
           # Validate URL format
           try:
               parsed_url = urlparse(original_url)
               if not all([parsed_url.scheme, parsed_url.netloc]):
                   return {
                       'statusCode': 400,
                       'headers': {
                           'Content-Type': 'application/json',
                           'Access-Control-Allow-Origin': '*',
                           'Access-Control-Allow-Headers': 'Content-Type',
                           'Access-Control-Allow-Methods': 'POST, OPTIONS'
                       },
                       'body': json.dumps({'error': 'Invalid URL format'})
                   }
           except Exception:
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*',
                       'Access-Control-Allow-Headers': 'Content-Type',
                       'Access-Control-Allow-Methods': 'POST, OPTIONS'
                   },
                   'body': json.dumps({'error': 'Invalid URL format'})
               }
           
           # Generate short code (retry if collision occurs)
           max_retries = 5
           for attempt in range(max_retries):
               short_code = ''.join(random.choices(string.ascii_letters + string.digits, k=6))
               
               try:
                   # Use conditional write to prevent overwriting existing codes
                   table.put_item(
                       Item={
                           'shortCode': short_code,
                           'originalUrl': original_url
                       },
                       ConditionExpression='attribute_not_exists(shortCode)'
                   )
                   break
               except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                   if attempt == max_retries - 1:
                       raise Exception("Unable to generate unique short code after multiple attempts")
                   continue
           
           logger.info(f"Created short URL: {short_code} -> {original_url}")
           
           return {
               'statusCode': 201,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*',
                   'Access-Control-Allow-Headers': 'Content-Type',
                   'Access-Control-Allow-Methods': 'POST, OPTIONS'
               },
               'body': json.dumps({
                   'shortCode': short_code,
                   'shortUrl': f"https://your-api-gateway-url/{short_code}",
                   'originalUrl': original_url
               })
           }
           
       except Exception as e:
           logger.error(f"Error creating short URL: {str(e)}")
           return {
               'statusCode': 500,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*',
                   'Access-Control-Allow-Headers': 'Content-Type',
                   'Access-Control-Allow-Methods': 'POST, OPTIONS'
               },
               'body': json.dumps({'error': 'Internal server error'})
           }
   EOF
   
   # Package and create Lambda function
   zip create-function.zip create-function.py
   
   aws lambda create-function \
       --function-name ${CREATE_FUNCTION_NAME} \
       --runtime python3.12 \
       --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} \
       --handler create-function.lambda_handler \
       --zip-file fileb://create-function.zip \
       --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
       --timeout 10
   
   echo "✅ Lambda function ${CREATE_FUNCTION_NAME} created for URL creation"
   ```

5. **Create Lambda Function for URL Redirection**:

   This function handles GET requests with short codes, performs DynamoDB lookups to find the original URL, and returns HTTP 302 redirects to send users to their intended destination. It includes proper error handling for invalid or expired short codes and comprehensive logging for monitoring.

   ```bash
   # Create Lambda function code for URL redirection
   cat > redirect-function.py << 'EOF'
   import json
   import boto3
   import os
   import logging
   from botocore.exceptions import ClientError
   
   logger = logging.getLogger()
   logger.setLevel(logging.INFO)
   
   dynamodb = boto3.resource('dynamodb')
   table = dynamodb.Table(os.environ['TABLE_NAME'])
   
   def lambda_handler(event, context):
       try:
           logger.info(f"Received event: {json.dumps(event)}")
           
           # Get short code from path parameters
           if not event.get('pathParameters') or not event['pathParameters'].get('shortCode'):
               return {
                   'statusCode': 400,
                   'headers': {'Content-Type': 'text/html'},
                   'body': '<h1>400 - Bad Request</h1><p>Short code parameter is required</p>'
               }
           
           short_code = event['pathParameters']['shortCode']
           
           # Validate short code format (basic validation)
           if not short_code or len(short_code) != 6 or not short_code.isalnum():
               return {
                   'statusCode': 400,
                   'headers': {'Content-Type': 'text/html'},
                   'body': '<h1>400 - Bad Request</h1><p>Invalid short code format</p>'
               }
           
           # Lookup original URL in DynamoDB
           response = table.get_item(
               Key={'shortCode': short_code}
           )
           
           if 'Item' in response:
               original_url = response['Item']['originalUrl']
               logger.info(f"Redirecting {short_code} to {original_url}")
               return {
                   'statusCode': 302,
                   'headers': {
                       'Location': original_url,
                       'Cache-Control': 'no-cache, no-store, must-revalidate'
                   }
               }
           else:
               logger.warning(f"Short code not found: {short_code}")
               return {
                   'statusCode': 404,
                   'headers': {'Content-Type': 'text/html'},
                   'body': '<h1>404 - Short URL not found</h1><p>The requested short URL does not exist or has expired.</p>'
               }
               
       except ClientError as e:
           logger.error(f"DynamoDB error: {str(e)}")
           return {
               'statusCode': 500,
               'headers': {'Content-Type': 'text/html'},
               'body': '<h1>500 - Internal Server Error</h1><p>Database error occurred</p>'
           }
       except Exception as e:
           logger.error(f"Unexpected error: {str(e)}")
           return {
               'statusCode': 500,
               'headers': {'Content-Type': 'text/html'},
               'body': '<h1>500 - Internal Server Error</h1><p>An unexpected error occurred</p>'
           }
   EOF
   
   # Package and create Lambda function
   zip redirect-function.zip redirect-function.py
   
   aws lambda create-function \
       --function-name ${REDIRECT_FUNCTION_NAME} \
       --runtime python3.12 \
       --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} \
       --handler redirect-function.lambda_handler \
       --zip-file fileb://redirect-function.zip \
       --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
       --timeout 10
   
   echo "✅ Lambda function ${REDIRECT_FUNCTION_NAME} created for URL redirection"
   ```

6. **Create API Gateway REST API**:

   API Gateway provides a managed service for creating RESTful APIs with built-in security, throttling, and monitoring capabilities. The REST API will expose endpoints for creating short URLs and handling redirects while managing all HTTP request/response processing.

   ```bash
   # Create REST API
   API_ID=$(aws apigateway create-rest-api \
       --name ${API_NAME} \
       --description "Serverless URL Shortener API" \
       --query 'id' --output text)
   
   # Get root resource ID
   ROOT_RESOURCE_ID=$(aws apigateway get-resources \
       --rest-api-id ${API_ID} \
       --query 'items[0].id' --output text)
   
   echo "✅ API Gateway REST API ${API_NAME} created with ID: ${API_ID}"
   ```

7. **Configure API Gateway Resources and Methods**:

   ```bash
   # Create /shorten resource for URL creation
   SHORTEN_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id ${API_ID} \
       --parent-id ${ROOT_RESOURCE_ID} \
       --path-part shorten \
       --query 'id' --output text)
   
   # Create POST method for /shorten
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method POST \
       --authorization-type NONE
   
   # Add OPTIONS method for CORS support
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method OPTIONS \
       --authorization-type NONE
   
   # Create /{shortCode} resource for redirects
   SHORTCODE_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id ${API_ID} \
       --parent-id ${ROOT_RESOURCE_ID} \
       --path-part '{shortCode}' \
       --query 'id' --output text)
   
   # Create GET method for /{shortCode}
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTCODE_RESOURCE_ID} \
       --http-method GET \
       --authorization-type NONE \
       --request-parameters method.request.path.shortCode=true
   
   echo "✅ API Gateway resources and methods configured"
   ```

8. **Connect Lambda Functions to API Gateway**:

   ```bash
   # Integrate POST /shorten with create Lambda function
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method POST \
       --type AWS_PROXY \
       --integration-http-method POST \
       --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${CREATE_FUNCTION_NAME}/invocations
   
   # Add CORS integration for OPTIONS method
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method OPTIONS \
       --type MOCK \
       --request-templates '{"application/json":"{\"statusCode\": 200}"}' \
       --passthrough-behavior WHEN_NO_MATCH
   
   # Configure OPTIONS method response
   aws apigateway put-method-response \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method OPTIONS \
       --status-code 200 \
       --response-parameters method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false
   
   aws apigateway put-integration-response \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTEN_RESOURCE_ID} \
       --http-method OPTIONS \
       --status-code 200 \
       --response-parameters method.response.header.Access-Control-Allow-Headers="'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",method.response.header.Access-Control-Allow-Methods="'POST,OPTIONS'",method.response.header.Access-Control-Allow-Origin="'*'"
   
   # Integrate GET /{shortCode} with redirect Lambda function
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${SHORTCODE_RESOURCE_ID} \
       --http-method GET \
       --type AWS_PROXY \
       --integration-http-method POST \
       --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${REDIRECT_FUNCTION_NAME}/invocations
   
   # Grant API Gateway permission to invoke Lambda functions
   aws lambda add-permission \
       --function-name ${CREATE_FUNCTION_NAME} \
       --statement-id api-gateway-invoke-create \
       --action lambda:InvokeFunction \
       --principal apigateway.amazonaws.com \
       --source-arn arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*
   
   aws lambda add-permission \
       --function-name ${REDIRECT_FUNCTION_NAME} \
       --statement-id api-gateway-invoke-redirect \
       --action lambda:InvokeFunction \
       --principal apigateway.amazonaws.com \
       --source-arn arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*
   
   # Deploy API to stage
   aws apigateway create-deployment \
       --rest-api-id ${API_ID} \
       --stage-name prod
   
   # Get API endpoint URL
   API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
   echo "✅ API deployed successfully at: ${API_URL}"
   ```

## Validation & Testing

1. Verify DynamoDB table and Lambda functions are active:

   ```bash
   # Check DynamoDB table status
   aws dynamodb describe-table --table-name ${TABLE_NAME} \
       --query 'Table.TableStatus' --output text
   
   # Check Lambda functions
   aws lambda get-function --function-name ${CREATE_FUNCTION_NAME} \
       --query 'Configuration.State' --output text
   aws lambda get-function --function-name ${REDIRECT_FUNCTION_NAME} \
       --query 'Configuration.State' --output text
   ```

   Expected output: `ACTIVE` for DynamoDB and `Active` for Lambda functions

2. Test URL shortening by creating a short link:

   ```bash
   # Create a short URL
   RESPONSE=$(curl -s -X POST ${API_URL}/shorten \
       -H "Content-Type: application/json" \
       -d '{"url": "https://aws.amazon.com/lambda/"}')
   
   echo "Response: $RESPONSE"
   
   # Extract short code from response
   SHORT_CODE=$(echo $RESPONSE | grep -o '"shortCode":"[^"]*"' \
       | cut -d'"' -f4)
   echo "Generated short code: $SHORT_CODE"
   ```

   Expected output: JSON response with shortCode, shortUrl, and originalUrl

3. Test URL redirection using the short code:

   ```bash
   # Test redirect using the generated short code
   if [ ! -z "$SHORT_CODE" ]; then
       curl -I ${API_URL}/${SHORT_CODE}
   else
       echo "No short code available from previous test"
   fi
   ```

   Expected output: HTTP 302 status with Location header pointing to original URL

4. Test error handling with invalid inputs:

   ```bash
   # Test with missing URL
   curl -X POST ${API_URL}/shorten \
       -H "Content-Type: application/json" \
       -d '{}'
   
   # Test with invalid URL format
   curl -X POST ${API_URL}/shorten \
       -H "Content-Type: application/json" \
       -d '{"url": "not-a-valid-url"}'
   
   # Test with non-existent short code
   curl -I ${API_URL}/invalid
   ```

5. Verify DynamoDB contains the URL mapping:

   ```bash
   # Scan DynamoDB table to see stored URLs
   aws dynamodb scan --table-name ${TABLE_NAME} \
       --select COUNT
   
   # View specific item if short code is available
   if [ ! -z "$SHORT_CODE" ]; then
       aws dynamodb get-item \
           --table-name ${TABLE_NAME} \
           --key '{"shortCode":{"S":"'$SHORT_CODE'"}}'
   fi
   ```

## Cleanup

1. Delete API Gateway REST API:

   ```bash
   # Delete API Gateway
   aws apigateway delete-rest-api --rest-api-id ${API_ID}
   
   echo "✅ Deleted API Gateway ${API_NAME}"
   ```

2. Delete Lambda functions:

   ```bash
   # Delete Lambda functions
   aws lambda delete-function --function-name ${CREATE_FUNCTION_NAME}
   aws lambda delete-function --function-name ${REDIRECT_FUNCTION_NAME}
   
   echo "✅ Deleted Lambda functions"
   ```

3. Delete IAM role and policies:

   ```bash
   # Detach policies from role
   aws iam detach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam detach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy
   
   # Delete custom policy
   aws iam delete-policy \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy
   
   # Delete IAM role
   aws iam delete-role --role-name ${ROLE_NAME}
   
   echo "✅ Deleted IAM role and policies"
   ```

4. Delete DynamoDB table:

   ```bash
   # Delete DynamoDB table
   aws dynamodb delete-table --table-name ${TABLE_NAME}
   
   echo "✅ Deleted DynamoDB table ${TABLE_NAME}"
   ```

5. Clean up local files:

   ```bash
   # Remove temporary files
   rm -f trust-policy.json dynamodb-policy.json
   rm -f create-function.py redirect-function.py
   rm -f create-function.zip redirect-function.zip
   
   echo "✅ Cleaned up temporary files"
   ```

## Discussion

This serverless URL shortener demonstrates key AWS architectural patterns that provide scalability, reliability, and cost efficiency. The solution leverages the AWS Well-Architected Framework by using managed services that automatically handle infrastructure concerns while focusing on business logic.

**DynamoDB Design Considerations**: The table design uses a simple primary key structure optimized for single-item lookups, which aligns with DynamoDB best practices for high-performance applications. The `shortCode` serves as the partition key, providing even distribution of data across partitions and enabling consistent single-digit millisecond response times. According to the [DynamoDB Best Practices Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html), this access pattern is ideal for key-value lookups where you know the exact key.

**Serverless Architecture Benefits**: The combination of API Gateway, Lambda, and DynamoDB creates a fully managed serverless stack that scales automatically from zero to thousands of requests per second without capacity planning. The [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html) documentation emphasizes keeping functions stateless and small, which this solution demonstrates through focused single-purpose functions that handle URL creation and redirection separately.

**Security and Access Control**: The IAM role configuration follows the principle of least privilege by granting only the minimum permissions required for DynamoDB operations. The [API Gateway Security Best Practices](https://docs.aws.amazon.com/apigateway/latest/developerguide/security-best-practices.html) guide recommends this approach for production deployments, along with additional security measures like API keys, usage plans, and request validation. The enhanced Lambda functions include comprehensive input validation and proper error handling to prevent common security vulnerabilities.

> **Tip**: Consider implementing custom domain names and SSL certificates through AWS Certificate Manager to create branded short URLs that enhance trust and user experience.

**Cost Optimization**: The on-demand billing mode for DynamoDB and pay-per-invocation pricing for Lambda ensure you only pay for actual usage, making this solution cost-effective for variable workloads. The [AWS Serverless Multi-Tier Architectures](https://docs.aws.amazon.com/whitepapers/latest/serverless-multi-tier-architectures-api-gateway-lambda/welcome.html) whitepaper highlights how this pricing model eliminates the need for capacity planning and reduces operational overhead while maintaining high availability.

## Challenge

Extend this solution by implementing these enhancements:

1. **Analytics and Tracking**: Add click tracking by updating DynamoDB items with access counts and timestamps, then create a CloudWatch dashboard to visualize URL usage patterns and popular links.

2. **Custom Short Codes**: Modify the creation function to accept optional custom short codes, implement validation to prevent duplicates, and add business logic for handling conflicts with existing codes.

3. **URL Expiration**: Implement time-based URL expiration by adding TTL (Time To Live) attributes to DynamoDB items, allowing users to specify expiration dates when creating short URLs.

4. **Rate Limiting and Security**: Add API Gateway usage plans with rate limiting, implement request validation to prevent malicious URLs, and integrate with AWS WAF for additional security protection.

5. **Advanced Features**: Create a web interface using S3 static hosting and CloudFront distribution, implement QR code generation for short URLs, and add user authentication with Amazon Cognito for personalized URL management.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files