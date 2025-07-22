---
title: Asynchronous API Patterns with SQS
id: j4p8q7r3
category: serverless
difficulty: 300
subject: aws
services: API Gateway, SQS, Lambda, IAM
estimated-time: 180 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: serverless, api-gateway, sqs, asynchronous, patterns
recipe-generator-version: 1.3
---

# Asynchronous API Patterns with SQS

## Problem

Modern applications often need to handle long-running tasks such as image processing, data analytics, or third-party API integrations that can take several minutes to complete. Traditional synchronous API calls timeout after 30 seconds in API Gateway, causing client timeouts and poor user experience. When handling high-volume requests or unpredictable workloads, synchronous processing can overwhelm backend systems and create bottlenecks. Applications need a way to decouple API requests from long-running processing tasks while providing clients with immediate acknowledgment and a mechanism to check job status.

## Solution

This solution implements an asynchronous API pattern using Amazon API Gateway and Amazon SQS to decouple request processing from response delivery. API Gateway receives client requests and immediately queues them in SQS for background processing, returning a job identifier to the client. Lambda functions process messages from the queue asynchronously, and clients can poll a status endpoint or receive notifications via webhooks. This architecture provides immediate response times, handles traffic spikes gracefully, and enables reliable processing of long-running tasks without client timeouts.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        CLIENT[Client Application]
        WEBHOOK[Webhook Endpoint]
    end
    
    subgraph "API Gateway"
        API_SUBMIT[POST /submit]
        API_STATUS[GET /status/{jobId}]
        API_WEBHOOK[POST /webhook]
    end
    
    subgraph "Message Queue"
        SQS_MAIN[Main Processing Queue]
        SQS_DLQ[Dead Letter Queue]
    end
    
    subgraph "Processing Layer"
        LAMBDA_PROCESSOR[Job Processor Lambda]
        LAMBDA_STATUS[Status Check Lambda]
        LAMBDA_WEBHOOK[Webhook Lambda]
    end
    
    subgraph "Storage"
        DYNAMODB[DynamoDB Jobs Table]
        S3[S3 Results Bucket]
    end
    
    CLIENT -->|1. Submit Job| API_SUBMIT
    API_SUBMIT -->|2. Queue Message| SQS_MAIN
    SQS_MAIN -->|3. Process Job| LAMBDA_PROCESSOR
    LAMBDA_PROCESSOR -->|4. Update Status| DYNAMODB
    LAMBDA_PROCESSOR -->|5. Store Results| S3
    LAMBDA_PROCESSOR -->|6. Send Notification| LAMBDA_WEBHOOK
    LAMBDA_WEBHOOK -->|7. Notify Client| WEBHOOK
    
    CLIENT -->|8. Check Status| API_STATUS
    API_STATUS -->|9. Query Status| LAMBDA_STATUS
    LAMBDA_STATUS -->|10. Read Status| DYNAMODB
    
    SQS_MAIN -->|Failed Messages| SQS_DLQ
    
    style SQS_MAIN fill:#FF9900
    style API_SUBMIT fill:#3F8624
    style LAMBDA_PROCESSOR fill:#FF9900
    style DYNAMODB fill:#3F8624
```

## Prerequisites

1. AWS account with appropriate permissions for API Gateway, SQS, Lambda, DynamoDB, and IAM
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic understanding of REST APIs and message queues
4. Knowledge of Lambda functions and DynamoDB
5. Estimated cost: $5-10/month for development usage (includes API Gateway calls, SQS messages, Lambda invocations, and DynamoDB storage)

> **Note**: This solution uses pay-per-use pricing. Costs scale with actual usage of API calls, message processing, and storage. For detailed cost optimization strategies, see the [AWS Cost Optimization documentation](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-pillar/design-principles.html).

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

export PROJECT_NAME="async-api-${RANDOM_SUFFIX}"
export MAIN_QUEUE_NAME="${PROJECT_NAME}-main-queue"
export DLQ_NAME="${PROJECT_NAME}-dlq"
export JOBS_TABLE_NAME="${PROJECT_NAME}-jobs"
export RESULTS_BUCKET_NAME="${PROJECT_NAME}-results"
export API_NAME="${PROJECT_NAME}-api"

# Create S3 bucket for storing results
aws s3 mb s3://${RESULTS_BUCKET_NAME} \
    --region ${AWS_REGION}

echo "✅ Created S3 bucket: ${RESULTS_BUCKET_NAME}"
```

## Steps

1. **Create the Dead Letter Queue**:

   Dead letter queues are essential for building fault-tolerant distributed systems. When SQS messages fail processing multiple times (due to code errors, service timeouts, or other issues), they're automatically moved to the DLQ for investigation and potential reprocessing. This prevents problematic messages from blocking the main queue indefinitely and provides visibility into system failures.

   ```bash
   # Create dead letter queue for failed messages
   aws sqs create-queue \
       --queue-name ${DLQ_NAME} \
       --attributes '{
           "MessageRetentionPeriod": "1209600",
           "VisibilityTimeoutSeconds": "300"
       }'
   
   # Get DLQ URL and ARN
   export DLQ_URL=$(aws sqs get-queue-url \
       --queue-name ${DLQ_NAME} \
       --query QueueUrl --output text)
   
   export DLQ_ARN=$(aws sqs get-queue-attributes \
       --queue-url ${DLQ_URL} \
       --attribute-names QueueArn \
       --query Attributes.QueueArn --output text)
   
   echo "✅ Created Dead Letter Queue: ${DLQ_NAME}"
   ```

   The DLQ is now configured with a 14-day message retention period, providing ample time to investigate and resolve processing issues. This foundational safety net ensures your asynchronous processing pipeline remains resilient under failure conditions.

2. **Create the Main Processing Queue**:

   Amazon SQS provides the core decoupling mechanism that enables asynchronous processing. The main queue receives job requests from API Gateway and holds them until Lambda functions are available to process them. This eliminates the tight coupling between request submission and processing, allowing the system to handle traffic spikes gracefully and providing natural backpressure when processing capacity is exceeded.

   ```bash
   # Create main queue with dead letter queue configuration
   aws sqs create-queue \
       --queue-name ${MAIN_QUEUE_NAME} \
       --attributes '{
           "MessageRetentionPeriod": "1209600",
           "VisibilityTimeoutSeconds": "300",
           "RedrivePolicy": "{\"deadLetterTargetArn\":\"'${DLQ_ARN}'\",\"maxReceiveCount\":3}"
       }'
   
   # Get main queue URL and ARN
   export MAIN_QUEUE_URL=$(aws sqs get-queue-url \
       --queue-name ${MAIN_QUEUE_NAME} \
       --query QueueUrl --output text)
   
   export MAIN_QUEUE_ARN=$(aws sqs get-queue-attributes \
       --queue-url ${MAIN_QUEUE_URL} \
       --attribute-names QueueArn \
       --query Attributes.QueueArn --output text)
   
   echo "✅ Created Main Queue: ${MAIN_QUEUE_NAME}"
   ```

   The redrive policy configuration ensures that messages failing processing three times are automatically moved to the dead letter queue. The 5-minute visibility timeout provides sufficient time for job processing while preventing duplicate processing of the same message. This queue now serves as the reliable backbone for your asynchronous job processing system.

3. **Create DynamoDB Table for Job Tracking**:

   DynamoDB provides the fast, scalable storage layer essential for real-time job status tracking in asynchronous systems. Unlike traditional relational databases, DynamoDB's single-digit millisecond latency and automatic scaling make it ideal for high-throughput status update patterns. The pay-per-request billing model ensures cost efficiency during variable workloads typical of job processing systems.

   ```bash
   # Create DynamoDB table for job status tracking
   aws dynamodb create-table \
       --table-name ${JOBS_TABLE_NAME} \
       --attribute-definitions \
           AttributeName=jobId,AttributeType=S \
       --key-schema \
           AttributeName=jobId,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST \
       --stream-specification StreamEnabled=false
   
   # Wait for table to be active
   aws dynamodb wait table-exists \
       --table-name ${JOBS_TABLE_NAME}
   
   echo "✅ Created DynamoDB table: ${JOBS_TABLE_NAME}"
   ```

   The table uses jobId as the partition key, ensuring efficient lookups and updates for individual job statuses. This NoSQL design pattern enables the status checking API to respond instantly to client queries, providing excellent user experience even under high load conditions.

4. **Create IAM Role for API Gateway**:

   IAM roles enable secure, cross-service communication without hardcoded credentials. API Gateway needs specific permissions to send messages to SQS, implementing the principle of least privilege that grants only the minimum permissions required for functionality. This security pattern ensures that API Gateway can enqueue job requests while preventing unauthorized access to other AWS resources.

   ```bash
   # Create trust policy for API Gateway
   cat > /tmp/api-gateway-trust-policy.json << EOF
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
   
   # Create IAM role for API Gateway
   aws iam create-role \
       --role-name ${PROJECT_NAME}-api-gateway-role \
       --assume-role-policy-document file:///tmp/api-gateway-trust-policy.json
   
   # Create policy for SQS access
   cat > /tmp/sqs-policy.json << EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "sqs:SendMessage",
                   "sqs:GetQueueAttributes"
               ],
               "Resource": "${MAIN_QUEUE_ARN}"
           }
       ]
   }
   EOF
   
   # Attach policy to role
   aws iam put-role-policy \
       --role-name ${PROJECT_NAME}-api-gateway-role \
       --policy-name SQSAccessPolicy \
       --policy-document file:///tmp/sqs-policy.json
   
   export API_GATEWAY_ROLE_ARN=$(aws iam get-role \
       --role-name ${PROJECT_NAME}-api-gateway-role \
       --query Role.Arn --output text)
   
   echo "✅ Created API Gateway IAM role"
   ```

   The role is now configured with precise SQS permissions, enabling API Gateway to submit job requests securely. This establishes the secure integration foundation that allows API Gateway to act as the reliable entry point for your asynchronous processing pipeline.

5. **Create Lambda Execution Role**:

   Lambda functions require comprehensive permissions to orchestrate the complete job processing workflow. This role enables Lambda to receive messages from SQS, update job statuses in DynamoDB, store results in S3, and write execution logs to CloudWatch. The multi-service permissions reflect Lambda's central role as the processing engine that coordinates data flow across the entire asynchronous architecture.

   ```bash
   # Create trust policy for Lambda
   cat > /tmp/lambda-trust-policy.json << EOF
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
   
   # Create IAM role for Lambda
   aws iam create-role \
       --role-name ${PROJECT_NAME}-lambda-role \
       --assume-role-policy-document file:///tmp/lambda-trust-policy.json
   
   # Attach basic execution policy
   aws iam attach-role-policy \
       --role-name ${PROJECT_NAME}-lambda-role \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   # Create policy for DynamoDB and S3 access
   cat > /tmp/lambda-policy.json << EOF
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
               "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${JOBS_TABLE_NAME}"
           },
           {
               "Effect": "Allow",
               "Action": [
                   "s3:PutObject",
                   "s3:GetObject",
                   "s3:DeleteObject"
               ],
               "Resource": "arn:aws:s3:::${RESULTS_BUCKET_NAME}/*"
           },
           {
               "Effect": "Allow",
               "Action": [
                   "sqs:ReceiveMessage",
                   "sqs:DeleteMessage",
                   "sqs:GetQueueAttributes"
               ],
               "Resource": "${MAIN_QUEUE_ARN}"
           }
       ]
   }
   EOF
   
   # Attach policy to role
   aws iam put-role-policy \
       --role-name ${PROJECT_NAME}-lambda-role \
       --policy-name LambdaAccessPolicy \
       --policy-document file:///tmp/lambda-policy.json
   
   export LAMBDA_ROLE_ARN=$(aws iam get-role \
       --role-name ${PROJECT_NAME}-lambda-role \
       --query Role.Arn --output text)
   
   echo "✅ Created Lambda IAM role"
   ```

   The role now provides Lambda functions with all necessary permissions while maintaining security boundaries. This enables seamless operation of the job processing pipeline with appropriate access controls that support both functionality and compliance requirements.

6. **Create Job Processor Lambda Function**:

   The job processor Lambda function serves as the core processing engine that transforms queued requests into completed jobs. Lambda's serverless model provides automatic scaling, built-in fault tolerance, and cost efficiency by charging only for actual execution time. This function demonstrates the complete job lifecycle: receiving messages from SQS, updating status in DynamoDB, performing processing work, storing results in S3, and handling errors gracefully.

   ```bash
   # Create Lambda function code
   cat > /tmp/job-processor.py << 'EOF'
   import json
   import boto3
   import uuid
   import time
   from datetime import datetime, timezone
   
   dynamodb = boto3.resource('dynamodb')
   s3 = boto3.client('s3')
   
   def lambda_handler(event, context):
       table_name = os.environ['JOBS_TABLE_NAME']
       results_bucket = os.environ['RESULTS_BUCKET_NAME']
       
       table = dynamodb.Table(table_name)
       
       for record in event['Records']:
           try:
               # Parse message from SQS
               message_body = json.loads(record['body'])
               job_id = message_body['jobId']
               job_data = message_body['data']
               
               # Update job status to processing
               table.update_item(
                   Key={'jobId': job_id},
                   UpdateExpression='SET #status = :status, #updatedAt = :timestamp',
                   ExpressionAttributeNames={
                       '#status': 'status',
                       '#updatedAt': 'updatedAt'
                   },
                   ExpressionAttributeValues={
                       ':status': 'processing',
                       ':timestamp': datetime.now(timezone.utc).isoformat()
                   }
               )
               
               # Simulate processing work (replace with actual processing logic)
               time.sleep(10)  # Simulate work
               
               # Generate result
               result = {
                   'jobId': job_id,
                   'result': f'Processed data: {job_data}',
                   'processedAt': datetime.now(timezone.utc).isoformat()
               }
               
               # Store result in S3
               s3.put_object(
                   Bucket=results_bucket,
                   Key=f'results/{job_id}.json',
                   Body=json.dumps(result),
                   ContentType='application/json'
               )
               
               # Update job status to completed
               table.update_item(
                   Key={'jobId': job_id},
                   UpdateExpression='SET #status = :status, #result = :result, #updatedAt = :timestamp',
                   ExpressionAttributeNames={
                       '#status': 'status',
                       '#result': 'result',
                       '#updatedAt': 'updatedAt'
                   },
                   ExpressionAttributeValues={
                       ':status': 'completed',
                       ':result': f's3://{results_bucket}/results/{job_id}.json',
                       ':timestamp': datetime.now(timezone.utc).isoformat()
                   }
               )
               
               print(f"Successfully processed job {job_id}")
               
           except Exception as e:
               print(f"Error processing job: {str(e)}")
               # Update job status to failed
               table.update_item(
                   Key={'jobId': job_id},
                   UpdateExpression='SET #status = :status, #error = :error, #updatedAt = :timestamp',
                   ExpressionAttributeNames={
                       '#status': 'status',
                       '#error': 'error',
                       '#updatedAt': 'updatedAt'
                   },
                   ExpressionAttributeValues={
                       ':status': 'failed',
                       ':error': str(e),
                       ':timestamp': datetime.now(timezone.utc).isoformat()
                   }
               )
               raise
   
       return {'statusCode': 200, 'body': 'Processing complete'}
   EOF
   
   # Create deployment package
   cd /tmp && zip job-processor.zip job-processor.py
   
   # Create Lambda function
   aws lambda create-function \
       --function-name ${PROJECT_NAME}-job-processor \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler job-processor.lambda_handler \
       --zip-file fileb://job-processor.zip \
       --timeout 300 \
       --memory-size 512 \
       --environment Variables='{
           "JOBS_TABLE_NAME": "'${JOBS_TABLE_NAME}'",
           "RESULTS_BUCKET_NAME": "'${RESULTS_BUCKET_NAME}'"
       }'
   
   echo "✅ Created Job Processor Lambda function"
   ```

   The job processor is now deployed and ready to handle incoming job requests. The function's error handling, status tracking, and result storage patterns provide a robust foundation for processing any type of long-running task in your asynchronous architecture.

7. **Create Status Check Lambda Function**:

   The status checker Lambda function provides real-time job status visibility to clients through a simple REST API. This function demonstrates efficient DynamoDB query patterns and proper API response formatting, including CORS headers for web application integration. The stateless design ensures consistent performance regardless of load levels.

   ```bash
   # Create Lambda function code
   cat > /tmp/status-checker.py << 'EOF'
   import json
   import boto3
   import os
   
   dynamodb = boto3.resource('dynamodb')
   
   def lambda_handler(event, context):
       table_name = os.environ['JOBS_TABLE_NAME']
       table = dynamodb.Table(table_name)
       
       job_id = event['pathParameters']['jobId']
       
       try:
           response = table.get_item(Key={'jobId': job_id})
           
           if 'Item' not in response:
               return {
                   'statusCode': 404,
                   'headers': {
                       'Content-Type': 'application/json',
                       'Access-Control-Allow-Origin': '*'
                   },
                   'body': json.dumps({'error': 'Job not found'})
               }
           
           job = response['Item']
           
           return {
               'statusCode': 200,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*'
               },
               'body': json.dumps({
                   'jobId': job['jobId'],
                   'status': job['status'],
                   'createdAt': job['createdAt'],
                   'updatedAt': job.get('updatedAt', job['createdAt']),
                   'result': job.get('result'),
                   'error': job.get('error')
               })
           }
           
       except Exception as e:
           return {
               'statusCode': 500,
               'headers': {
                   'Content-Type': 'application/json',
                   'Access-Control-Allow-Origin': '*'
               },
               'body': json.dumps({'error': str(e)})
           }
   EOF
   
   # Create deployment package
   cd /tmp && zip status-checker.zip status-checker.py
   
   # Create Lambda function
   aws lambda create-function \
       --function-name ${PROJECT_NAME}-status-checker \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler status-checker.lambda_handler \
       --zip-file fileb://status-checker.zip \
       --timeout 30 \
       --memory-size 256 \
       --environment Variables='{
           "JOBS_TABLE_NAME": "'${JOBS_TABLE_NAME}'"
       }'
   
   echo "✅ Created Status Checker Lambda function"
   ```

   The status checker function enables clients to poll job progress efficiently, providing transparency into the asynchronous processing pipeline. This completes the core Lambda function deployment required for your job processing system.

8. **Create API Gateway REST API**:

   API Gateway provides the client-facing interface that transforms HTTP requests into asynchronous job submissions. The regional endpoint configuration optimizes latency for clients in your primary region while supporting edge optimization through CloudFront if needed. API Gateway's integration capabilities enable direct SQS message submission without requiring intermediate Lambda functions, reducing latency and cost.

   ```bash
   # Create REST API
   export API_ID=$(aws apigateway create-rest-api \
       --name ${API_NAME} \
       --description "Asynchronous API with SQS integration" \
       --endpoint-configuration types=REGIONAL \
       --query id --output text)
   
   # Get root resource ID
   export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
       --rest-api-id ${API_ID} \
       --query 'items[0].id' --output text)
   
   echo "✅ Created API Gateway: ${API_ID}"
   ```

   The API Gateway foundation is now established, providing the entry point for client applications to submit asynchronous job requests. This RESTful interface abstracts the underlying message queue complexity from clients while maintaining standard HTTP semantics.

9. **Create API Gateway Submit Job Endpoint**:

   The /submit endpoint implements the crucial job submission workflow that immediately acknowledges client requests while queuing them for asynchronous processing. The direct SQS integration eliminates Lambda cold starts and reduces submission latency to under 100ms. The request template transformation enriches incoming requests with unique job identifiers and timestamps, providing complete job traceability.

   ```bash
   # Create /submit resource
   export SUBMIT_RESOURCE_ID=$(aws apigateway create-resource \
       --rest-api-id ${API_ID} \
       --parent-id ${ROOT_RESOURCE_ID} \
       --path-part submit \
       --query id --output text)
   
   # Create POST method for /submit
   aws apigateway put-method \
       --rest-api-id ${API_ID} \
       --resource-id ${SUBMIT_RESOURCE_ID} \
       --http-method POST \
       --authorization-type NONE \
       --request-parameters '{}'
   
   # Create SQS integration
   aws apigateway put-integration \
       --rest-api-id ${API_ID} \
       --resource-id ${SUBMIT_RESOURCE_ID} \
       --http-method POST \
       --type AWS \
       --integration-http-method POST \
       --uri "arn:aws:apigateway:${AWS_REGION}:sqs:path/${AWS_ACCOUNT_ID}/${MAIN_QUEUE_NAME}" \
       --credentials ${API_GATEWAY_ROLE_ARN} \
       --request-parameters '{
           "integration.request.header.Content-Type": "'"'"'application/x-amz-json-1.0'"'"'",
           "integration.request.querystring.Action": "'"'"'SendMessage'"'"'",
           "integration.request.querystring.MessageBody": "method.request.body"
       }' \
       --request-templates '{
           "application/json": "{\"jobId\": \"$context.requestId\", \"data\": $input.json(\"$\"), \"timestamp\": \"$context.requestTime\"}"
       }'
   
   # Create method response
   aws apigateway put-method-response \
       --rest-api-id ${API_ID} \
       --resource-id ${SUBMIT_RESOURCE_ID} \
       --http-method POST \
       --status-code 200 \
       --response-models '{
           "application/json": "Empty"
       }'
   
   # Create integration response
   aws apigateway put-integration-response \
       --rest-api-id ${API_ID} \
       --resource-id ${SUBMIT_RESOURCE_ID} \
       --http-method POST \
       --status-code 200 \
       --response-templates '{
           "application/json": "{\"jobId\": \"$context.requestId\", \"status\": \"queued\", \"message\": \"Job submitted successfully\"}"
       }'
   
   echo "✅ Created /submit endpoint"
   ```

   The submit endpoint now provides clients with immediate job acknowledgment and unique tracking identifiers. This establishes the high-performance entry point that enables clients to submit thousands of jobs per second while maintaining excellent response times.

10. **Create API Gateway Status Check Endpoint**:

    The status endpoint provides real-time visibility into job processing progress, enabling clients to build responsive user interfaces that display current job states. The RESTful design with path parameters follows standard HTTP conventions, making the API intuitive for developers. The Lambda proxy integration ensures flexible response formatting while maintaining consistent error handling patterns.

    ```bash
    # Create /status resource
    export STATUS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id ${API_ID} \
        --parent-id ${ROOT_RESOURCE_ID} \
        --path-part status \
        --query id --output text)
    
    # Create {jobId} resource under /status
    export STATUS_JOB_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id ${API_ID} \
        --parent-id ${STATUS_RESOURCE_ID} \
        --path-part '{jobId}' \
        --query id --output text)
    
    # Create GET method for /status/{jobId}
    aws apigateway put-method \
        --rest-api-id ${API_ID} \
        --resource-id ${STATUS_JOB_RESOURCE_ID} \
        --http-method GET \
        --authorization-type NONE \
        --request-parameters '{
            "method.request.path.jobId": true
        }'
    
    # Get Lambda function ARN
    export STATUS_LAMBDA_ARN=$(aws lambda get-function \
        --function-name ${PROJECT_NAME}-status-checker \
        --query Configuration.FunctionArn --output text)
    
    # Create Lambda integration
    aws apigateway put-integration \
        --rest-api-id ${API_ID} \
        --resource-id ${STATUS_JOB_RESOURCE_ID} \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${STATUS_LAMBDA_ARN}/invocations"
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${PROJECT_NAME}-status-checker \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    echo "✅ Created /status/{jobId} endpoint"
    ```

    The status endpoint now enables clients to query job progress efficiently using simple HTTP GET requests. This completes the API surface that provides both job submission and status checking capabilities through standard REST operations.

11. **Configure SQS Lambda Trigger**:

    Event source mapping creates the connection between SQS messages and Lambda function execution, enabling automatic job processing without manual intervention. The batch configuration optimizes processing efficiency by allowing Lambda to process up to 10 messages per invocation while maintaining low latency through the 5-second maximum batching window. This configuration balances throughput with responsiveness for typical job processing workloads.

    ```bash
    # Create event source mapping for SQS to Lambda
    aws lambda create-event-source-mapping \
        --event-source-arn ${MAIN_QUEUE_ARN} \
        --function-name ${PROJECT_NAME}-job-processor \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5
    
    echo "✅ Configured SQS Lambda trigger"
    ```

    The event source mapping activates the automatic job processing pipeline, enabling Lambda to poll SQS and process jobs as they arrive. This completes the core integration that transforms queued requests into executed jobs without manual intervention.

12. **Deploy API Gateway**:

    API Gateway deployment makes your configured endpoints accessible to clients over HTTPS. The production stage provides a stable endpoint URL for client applications while enabling future deployments to different stages for testing and gradual rollouts. The deployment process validates all integration configurations and makes the complete asynchronous API immediately available for job submission and status checking.

    ```bash
    # Create deployment
    aws apigateway create-deployment \
        --rest-api-id ${API_ID} \
        --stage-name prod \
        --stage-description "Production stage" \
        --description "Initial deployment"
    
    # Get API endpoint URL
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    echo "✅ API deployed at: ${API_ENDPOINT}"
    ```

    Your asynchronous API is now live and ready to accept job requests from client applications. The complete end-to-end processing pipeline is operational, providing scalable job submission, reliable processing, and real-time status tracking capabilities.

## Validation & Testing

1. **Test Job Submission**:

   ```bash
   # Submit a test job
   SUBMIT_RESPONSE=$(curl -s -X POST \
       -H "Content-Type: application/json" \
       -d '{"task": "process_data", "data": {"input": "test data"}}' \
       ${API_ENDPOINT}/submit)
   
   echo "Submit Response: ${SUBMIT_RESPONSE}"
   
   # Extract job ID from response
   JOB_ID=$(echo ${SUBMIT_RESPONSE} | \
       python3 -c "import json,sys; print(json.load(sys.stdin)['jobId'])")
   
   echo "Job ID: ${JOB_ID}"
   ```

   Expected output: JSON response with jobId, status "queued", and success message.

2. **Test Status Checking**:

   ```bash
   # Check job status immediately (should be queued)
   curl -s "${API_ENDPOINT}/status/${JOB_ID}" | \
       python3 -m json.tool
   
   # Wait for processing to complete
   sleep 15
   
   # Check job status again (should be completed)
   curl -s "${API_ENDPOINT}/status/${JOB_ID}" | \
       python3 -m json.tool
   ```

   Expected output: Job status progression from "queued" to "processing" to "completed".

3. **Verify DynamoDB Job Record**:

   ```bash
   # Check DynamoDB record
   aws dynamodb get-item \
       --table-name ${JOBS_TABLE_NAME} \
       --key '{"jobId": {"S": "'${JOB_ID}'"}}' \
       --query Item
   ```

4. **Verify S3 Result Storage**:

   ```bash
   # List results in S3
   aws s3 ls s3://${RESULTS_BUCKET_NAME}/results/
   
   # Download and view result
   aws s3 cp s3://${RESULTS_BUCKET_NAME}/results/${JOB_ID}.json /tmp/
   cat /tmp/${JOB_ID}.json
   ```

## Cleanup

1. **Delete API Gateway**:

   ```bash
   # Delete API Gateway
   aws apigateway delete-rest-api \
       --rest-api-id ${API_ID}
   
   echo "✅ Deleted API Gateway"
   ```

2. **Delete Lambda Functions**:

   ```bash
   # Delete Lambda functions
   aws lambda delete-function \
       --function-name ${PROJECT_NAME}-job-processor
   
   aws lambda delete-function \
       --function-name ${PROJECT_NAME}-status-checker
   
   echo "✅ Deleted Lambda functions"
   ```

3. **Delete SQS Queues**:

   ```bash
   # Delete SQS queues
   aws sqs delete-queue --queue-url ${MAIN_QUEUE_URL}
   aws sqs delete-queue --queue-url ${DLQ_URL}
   
   echo "✅ Deleted SQS queues"
   ```

4. **Delete DynamoDB Table**:

   ```bash
   # Delete DynamoDB table
   aws dynamodb delete-table \
       --table-name ${JOBS_TABLE_NAME}
   
   echo "✅ Deleted DynamoDB table"
   ```

5. **Delete S3 Bucket**:

   ```bash
   # Empty and delete S3 bucket
   aws s3 rm s3://${RESULTS_BUCKET_NAME} --recursive
   aws s3 rb s3://${RESULTS_BUCKET_NAME}
   
   echo "✅ Deleted S3 bucket"
   ```

6. **Delete IAM Roles**:

   ```bash
   # Delete IAM role policies and roles
   aws iam delete-role-policy \
       --role-name ${PROJECT_NAME}-api-gateway-role \
       --policy-name SQSAccessPolicy
   
   aws iam delete-role-policy \
       --role-name ${PROJECT_NAME}-lambda-role \
       --policy-name LambdaAccessPolicy
   
   aws iam detach-role-policy \
       --role-name ${PROJECT_NAME}-lambda-role \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam delete-role \
       --role-name ${PROJECT_NAME}-api-gateway-role
   
   aws iam delete-role \
       --role-name ${PROJECT_NAME}-lambda-role
   
   echo "✅ Deleted IAM roles"
   ```

## Discussion

This asynchronous API pattern addresses several critical challenges in modern application development. The decoupling of request acceptance from processing enables applications to handle variable workloads gracefully while providing immediate feedback to clients. [API Gateway's direct SQS integration](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/integrate-amazon-api-gateway-with-amazon-sqs-to-handle-asynchronous-rest-apis.html) eliminates the need for an intermediate Lambda function, reducing latency and cost for job submission.

The architecture implements several best practices for reliable message processing. The dead letter queue captures failed messages for analysis and potential reprocessing, while the SQS visibility timeout and retry mechanism handle transient failures automatically. [DynamoDB's NoSQL design patterns](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-general-nosql-design.html) provide fast, scalable storage for job status tracking, enabling real-time status updates without impacting processing performance.

Status polling represents a simple but effective approach for client-side job tracking. For applications requiring real-time updates, this pattern can be extended with WebSocket APIs or Server-Sent Events to push status changes to clients immediately. The webhook pattern demonstrated in the architecture diagram provides another option for server-initiated notifications.

> **Tip**: Configure appropriate SQS message retention periods based on your processing SLAs. The default 14-day retention ensures messages aren't lost during extended outages, but shorter periods may be suitable for time-sensitive operations. Learn more about [SQS visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html) and [dead letter queue best practices](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/setting-up-dead-letter-queue-retention.html).

> **Warning**: This pattern implements a polling-based status checking mechanism. For high-frequency status checks, consider implementing WebSocket connections or push notifications to reduce API Gateway costs and improve user experience.

Performance optimization opportunities include implementing SQS FIFO queues for ordered processing, using Lambda reserved concurrency to control processing rates, and implementing exponential backoff for status polling to reduce API calls. Cost optimization can be achieved by using SQS batch operations, optimizing Lambda memory allocation based on actual usage patterns, and implementing DynamoDB on-demand billing for variable workloads.

The pattern scales naturally with increased load. SQS handles millions of messages per second, Lambda scales automatically up to account limits, and DynamoDB scales seamlessly with demand. For extreme scale requirements, consider partitioning jobs across multiple queues or implementing priority-based processing using separate high and low priority queues.

## Challenge

Extend this solution by implementing these enhancements:

1. **Add webhook notifications** by creating a Lambda function that sends HTTP POST requests to client-specified webhook URLs when jobs complete, with exponential backoff retry logic for failed deliveries.

2. **Implement job priorities** using separate SQS queues for high and low priority jobs, with dedicated Lambda functions processing high-priority jobs first.

3. **Add batch job processing** by modifying the processor to handle multiple related jobs as a single batch, storing batch results in S3 and updating individual job statuses.

4. **Create a WebSocket API** using API Gateway WebSocket APIs to push real-time status updates to connected clients, eliminating the need for polling.

5. **Implement job scheduling** by integrating with Amazon EventBridge to support delayed job execution and recurring job patterns.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*