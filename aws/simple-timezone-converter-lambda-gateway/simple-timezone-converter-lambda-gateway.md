---
title: Simple Time Zone Converter with Lambda and API Gateway
id: b2c4e8f1
category: serverless
difficulty: 100
subject: aws
services: Lambda, API Gateway
estimated-time: 25 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-7-23
passed-qa: null
tags: serverless, api, timezone, rest, beginners, python
recipe-generator-version: 1.3
---

# Simple Time Zone Converter with Lambda and API Gateway

## Problem

Distributed applications often need to display timestamps in different time zones for users across the globe, but handling timezone conversions manually leads to inconsistent formatting and potential errors. Many developers struggle with timezone math, daylight saving time transitions, and maintaining accurate conversion logic across multiple services.

## Solution

Build a serverless REST API using AWS Lambda and API Gateway that accepts timestamps and target timezones, returning properly converted datetime strings. This solution provides a centralized, scalable timezone conversion service that automatically handles daylight saving time transitions and timezone abbreviations while eliminating server management overhead.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[Web/Mobile App]
    end
    
    subgraph "AWS API Gateway"
        APIGW[REST API Endpoint]
        RESOURCE[/convert Resource]
        METHOD[POST Method]
    end
    
    subgraph "AWS Lambda"
        FUNCTION[Timezone Converter Function]
        HANDLER[Python Handler]
    end
    
    subgraph "AWS IAM"
        ROLE[Lambda Execution Role]
        POLICY[CloudWatch Logs Policy]
    end
    
    CLIENT-->APIGW
    APIGW-->RESOURCE
    RESOURCE-->METHOD
    METHOD-->FUNCTION
    FUNCTION-->HANDLER
    ROLE-->FUNCTION
    POLICY-->ROLE
    
    style FUNCTION fill:#FF9900
    style APIGW fill:#3F8624
    style ROLE fill:#FF4444
```

## Prerequisites

1. AWS account with appropriate permissions for Lambda, API Gateway, and IAM
2. AWS CLI installed and configured (or AWS CloudShell)
3. Basic knowledge of REST APIs and HTTP methods
4. Understanding of JSON request/response formats
5. Estimated cost: $0.01-$0.50 for testing (within free tier limits)

> **Note**: This recipe uses AWS Free Tier eligible services. Lambda provides 1M free requests monthly, and API Gateway provides 1M API calls monthly for new accounts.

## Preparation

```bash
# Set environment variables for AWS resources
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Set resource names with unique suffixes
export FUNCTION_NAME="timezone-converter-${RANDOM_SUFFIX}"
export ROLE_NAME="timezone-converter-role-${RANDOM_SUFFIX}"
export API_NAME="timezone-converter-api-${RANDOM_SUFFIX}"

echo "✅ Environment configured for region: ${AWS_REGION}"
echo "✅ Account ID: ${AWS_ACCOUNT_ID}"
echo "✅ Function name: ${FUNCTION_NAME}"
```

## Steps

1. **Create IAM Role for Lambda Execution**:

   AWS Lambda requires an execution role with permissions to write logs to CloudWatch. This role follows the principle of least privilege, granting only the minimum permissions necessary for the function to operate. The AWSLambdaBasicExecutionRole managed policy provides standard logging permissions that enable monitoring and troubleshooting through CloudWatch Logs.

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
   
   # Create the IAM role
   aws iam create-role \
       --role-name ${ROLE_NAME} \
       --assume-role-policy-document file://trust-policy.json
   
   # Attach basic execution policy for CloudWatch Logs
   aws iam attach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Store role ARN for later use
   ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} \
       --query 'Role.Arn' --output text)
   
   echo "✅ IAM role created: ${ROLE_ARN}"
   ```

2. **Create Lambda Function Code**:

   The Lambda function uses Python's built-in `datetime` and `zoneinfo` modules for accurate timezone conversion. This approach leverages the IANA timezone database included in Python 3.9+ runtime, ensuring proper handling of daylight saving time transitions and timezone rules without external dependencies.

   ```bash
   # Create the Lambda function code
   cat > lambda_function.py << 'EOF'
   import json
   import logging
   from datetime import datetime
   from zoneinfo import ZoneInfo
   
   # Configure logging
   logger = logging.getLogger()
   logger.setLevel(logging.INFO)
   
   def lambda_handler(event, context):
       """
       Convert timestamp between timezones
       
       Expected event format:
       {
         "timestamp": "2025-07-12T15:30:00",
         "from_timezone": "UTC",
         "to_timezone": "America/New_York"
       }
       """
       try:
           # Parse the request body
           if 'body' in event:
               body = json.loads(event['body'])
           else:
               body = event
           
           # Extract required parameters
           timestamp_str = body.get('timestamp')
           from_tz = body.get('from_timezone', 'UTC')
           to_tz = body.get('to_timezone')
           
           # Validate required parameters
           if not timestamp_str or not to_tz:
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*'
                   },
                   'body': json.dumps({
                       'error': 'Missing required parameters: timestamp and to_timezone'
                   })
               }
           
           # Parse the timestamp
           try:
               # Try parsing with timezone info first
               if 'T' in timestamp_str and ('+' in timestamp_str or 'Z' in timestamp_str):
                   dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
               else:
                   # Parse as naive datetime and assign source timezone
                   dt_naive = datetime.fromisoformat(timestamp_str)
                   dt = dt_naive.replace(tzinfo=ZoneInfo(from_tz))
           except ValueError as e:
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*'
                   },
                   'body': json.dumps({
                       'error': f'Invalid timestamp format: {str(e)}'
                   })
               }
           
           # Convert to target timezone
           try:
               target_tz = ZoneInfo(to_tz)
               converted_dt = dt.astimezone(target_tz)
           except Exception as e:
               return {
                   'statusCode': 400,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*'
                   },
                   'body': json.dumps({
                       'error': f'Invalid timezone: {str(e)}'
                   })
               }
           
           # Format response
           response_data = {
               'original_timestamp': timestamp_str,
               'original_timezone': from_tz,
               'converted_timestamp': converted_dt.isoformat(),
               'target_timezone': to_tz,
               'timezone_offset': converted_dt.strftime('%z'),
               'timezone_name': converted_dt.tzname()
           }
           
           logger.info(f"Converted {timestamp_str} from {from_tz} to {to_tz}")
           
           return {
               'statusCode': 200,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*'
               },
               'body': json.dumps(response_data)
           }
           
       except Exception as e:
           logger.error(f"Unexpected error: {str(e)}")
           return {
               'statusCode': 500,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*'
               },
               'body': json.dumps({
                   'error': 'Internal server error'
               })
           }
   EOF
   
   echo "✅ Lambda function code created"
   ```

3. **Package and Deploy Lambda Function**:

   AWS Lambda requires function code to be packaged as a ZIP file. The Python 3.12 runtime includes the `zoneinfo` module with current IANA timezone data, eliminating the need for external timezone libraries and reducing package size for faster cold starts. Python 3.12 is the current recommended runtime with support until 2028.

   ```bash
   # Create deployment package
   zip lambda-deployment.zip lambda_function.py
   
   # Wait for IAM role to propagate (required for new roles)
   echo "⏳ Waiting for IAM role propagation..."
   sleep 10
   
   # Create the Lambda function with Python 3.12 runtime
   aws lambda create-function \
       --function-name ${FUNCTION_NAME} \
       --runtime python3.12 \
       --role ${ROLE_ARN} \
       --handler lambda_function.lambda_handler \
       --zip-file fileb://lambda-deployment.zip \
       --timeout 30 \
       --memory-size 128 \
       --description "Simple timezone converter API"
   
   # Store function ARN for later use
   FUNCTION_ARN=$(aws lambda get-function --function-name ${FUNCTION_NAME} \
       --query 'Configuration.FunctionArn' --output text)
   
   echo "✅ Lambda function deployed: ${FUNCTION_ARN}"
   ```

4. **Create API Gateway REST API**:

   API Gateway provides a managed HTTP endpoint that automatically handles request routing, authentication, throttling, and monitoring. The REST API type offers comprehensive features for production applications including request/response transformation, caching, and detailed CloudWatch metrics.

   ```bash
   # Create the REST API
   API_ID=$(aws apigateway create-rest-api \
       --name ${API_NAME} \
       --description "Timezone converter REST API" \
       --endpoint-configuration types=REGIONAL \
       --query 'id' --output text)
   
   # Get the root resource ID
   ROOT_RESOURCE_ID=$(aws apigateway get-resources \
       --rest-api-id ${API_ID} \
       --query 'items[0].id' --output text)
   
   echo "✅ API Gateway created: ${API_ID}"
   echo "✅ Root resource ID: ${ROOT_RESOURCE_ID}"
   ```

5. **Create API Resource and Method**:

   The `/convert` resource with a POST method provides a RESTful interface for timezone conversion requests. This design follows REST conventions where POST operations perform data transformations, and the specific resource path clearly indicates the API's purpose.

   ```bash
   # Create the /convert resource
   RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id ${API_ID} \
       --parent-id ${ROOT_RESOURCE_ID} \
       --path-part convert \
       --query 'id' --output text)
   
   # Create POST method on /convert resource
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${RESOURCE_ID} \
       --http-method POST \
       --authorization-type NONE
   
   # Configure method integration with Lambda
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${RESOURCE_ID} \
       --http-method POST \
       --type AWS_PROXY \
       --integration-http-method POST \
       --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations
   
   echo "✅ API resource and method configured"
   ```

6. **Grant API Gateway Permission to Invoke Lambda**:

   AWS service-to-service communication requires explicit permissions through resource-based policies. This permission allows API Gateway to invoke the Lambda function while maintaining security boundaries and enabling proper AWS service integration logging and monitoring.

   ```bash
   # Grant API Gateway permission to invoke Lambda function
   aws lambda add-permission \
       --function-name ${FUNCTION_NAME} \
       --statement-id apigateway-invoke-permission \
       --action lambda:InvokeFunction \
       --principal apigateway.amazonaws.com \
       --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
   
   echo "✅ API Gateway invoke permission granted"
   ```

7. **Deploy API to Stage**:

   API Gateway requires deployment to a stage before endpoints become accessible. The `prod` stage represents a production environment with its own configuration, throttling limits, and caching settings. Each deployment creates an immutable snapshot enabling rollback capabilities.

   ```bash
   # Deploy API to production stage
   aws apigateway create-deployment \
       --rest-api-id ${API_ID} \
       --stage-name prod \
       --description "Production deployment of timezone converter API"
   
   # Store the API endpoint URL
   API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
   
   echo "✅ API deployed to production stage"
   echo "✅ API endpoint: ${API_ENDPOINT}/convert"
   ```

## Validation & Testing

1. Verify Lambda function was created successfully:

   ```bash
   # Check Lambda function status
   aws lambda get-function --function-name ${FUNCTION_NAME} \
       --query 'Configuration.[State,LastModified,Runtime]' \
       --output table
   ```

   Expected output: Function should show "Active" state with Python 3.12 runtime

2. Test Lambda function directly:

   ```bash
   # Test function with sample timezone conversion
   aws lambda invoke \
       --function-name ${FUNCTION_NAME} \
       --payload '{"timestamp":"2025-07-12T15:30:00","from_timezone":"UTC","to_timezone":"America/New_York"}' \
       response.json
   
   # Display the response
   cat response.json | python -m json.tool
   ```

   Expected output: JSON with converted timestamp in Eastern time

3. Test API Gateway endpoint:

   ```bash
   # Test API endpoint with curl
   curl -X POST ${API_ENDPOINT}/convert \
       -H "Content-Type: application/json" \
       -d '{
         "timestamp": "2025-07-12T15:30:00",
         "from_timezone": "UTC", 
         "to_timezone": "America/Los_Angeles"
       }' | python -m json.tool
   ```

   Expected output: JSON response showing Pacific time conversion

4. Test error handling:

   ```bash
   # Test with invalid timezone
   curl -X POST ${API_ENDPOINT}/convert \
       -H "Content-Type: application/json" \
       -d '{
         "timestamp": "2025-07-12T15:30:00",
         "to_timezone": "Invalid/Timezone"
       }' | python -m json.tool
   ```

   Expected output: HTTP 400 error with descriptive message

## Cleanup

1. Remove API Gateway:

   ```bash
   # Delete the REST API (removes all resources)
   aws apigateway delete-rest-api --rest-api-id ${API_ID}
   
   echo "✅ API Gateway deleted"
   ```

2. Remove Lambda function:

   ```bash
   # Delete Lambda function
   aws lambda delete-function --function-name ${FUNCTION_NAME}
   
   echo "✅ Lambda function deleted"
   ```

3. Remove IAM role:

   ```bash
   # Detach managed policy from role
   aws iam detach-role-policy \
       --role-name ${ROLE_NAME} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Delete the IAM role
   aws iam delete-role --role-name ${ROLE_NAME}
   
   echo "✅ IAM role deleted"
   ```

4. Clean up local files:

   ```bash
   # Remove temporary files
   rm -f lambda_function.py lambda-deployment.zip trust-policy.json response.json
   
   echo "✅ Local files cleaned up"
   ```

## Discussion

This serverless timezone converter demonstrates the power of AWS Lambda and API Gateway for building lightweight, scalable APIs without server management overhead. The solution leverages Python's built-in `zoneinfo` module, which provides access to the IANA timezone database with accurate daylight saving time transitions and historical timezone changes. This approach eliminates external dependencies while ensuring reliability and reducing cold start latency.

The architecture follows AWS Well-Architected Framework principles by implementing proper error handling, using least privilege IAM permissions, and enabling comprehensive logging through CloudWatch. The API Gateway integration provides automatic request/response transformation, built-in throttling, and monitoring capabilities that would require significant custom development in traditional server-based deployments. The serverless approach ensures cost efficiency through pay-per-request pricing and automatic scaling from zero to thousands of concurrent requests.

One key architectural decision involves using the `AWS_PROXY` integration type, which passes the complete HTTP request context to the Lambda function. This pattern provides maximum flexibility for request processing and response formatting while maintaining the standard HTTP semantics that client applications expect. The function handles both naive and timezone-aware timestamps, making it compatible with various client implementations and timestamp formats commonly found in web applications.

Security considerations include enabling CORS headers for web browser compatibility while maintaining API security through AWS service integration rather than custom authentication logic. For production deployments, consider implementing API key authentication, request rate limiting, and input validation middleware to prevent abuse and ensure service reliability. The updated Python 3.12 runtime provides enhanced performance and security features compared to older versions.

> **Tip**: Monitor Lambda function performance using CloudWatch metrics like Duration, Error Count, and Throttles to optimize memory allocation and identify performance bottlenecks. The [AWS Lambda monitoring documentation](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-functions.html) provides comprehensive guidance for production deployments.

For more information on timezone handling best practices, see the [Python datetime documentation](https://docs.python.org/3/library/datetime.html) and [AWS Lambda Python runtime documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html). The [API Gateway Lambda integration guide](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html) provides additional details on request/response transformation patterns.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add batch conversion support** - Modify the API to accept arrays of timestamps for bulk conversion operations, improving efficiency for applications requiring multiple timezone calculations.

2. **Implement timezone abbreviation support** - Add functionality to accept common timezone abbreviations (EST, PST, GMT) in addition to IANA timezone identifiers, making the API more user-friendly.

3. **Add response caching** - Configure API Gateway caching to improve response times and reduce Lambda invocations for frequently requested timezone conversions.

4. **Create timezone list endpoint** - Build a GET endpoint that returns available timezone identifiers and abbreviations, enabling dynamic timezone selection in client applications.

5. **Implement API authentication** - Add API key or JWT token authentication using API Gateway authorizers to secure the endpoint for production use while maintaining performance.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*