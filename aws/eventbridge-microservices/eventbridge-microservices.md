---
title: Event-Driven Microservices with EventBridge Routing
id: dc3446dc
category: serverless
difficulty: 300
subject: aws
services: eventbridge, lambda, sqs, sns
estimated-time: 90 minutes
recipe-version: 1.3
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: eventbridge, lambda, sqs, sns, microservices, event-driven
recipe-generator-version: 1.3
---

# Event-Driven Microservices with EventBridge Routing

## Problem

Your organization is building a modern e-commerce platform with multiple microservices that need to communicate asynchronously. You have an order service, inventory service, payment service, and notification service that must coordinate complex workflows without tight coupling. Traditional point-to-point integrations create a web of dependencies that are difficult to maintain, monitor, and scale, leading to cascading failures and reduced system reliability when any single service becomes unavailable.

## Solution

Implement a scalable event-driven architecture using Amazon EventBridge as the central event router that enables loose coupling between microservices. This solution creates custom event buses for domain isolation, establishes intelligent event patterns for content-based routing, and integrates with AWS services for reliable event processing with comprehensive error handling and monitoring capabilities.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Event Producers"
        ORDER[Order Service]
        PAYMENT[Payment Service]
        INVENTORY[Inventory Service]
        API[API Gateway]
    end
    
    subgraph "EventBridge Architecture"
        DEFAULT[Default Event Bus]
        CUSTOM[Custom Event Bus<br/>E-commerce Domain]
        RULES[Event Rules & Patterns]
    end
    
    subgraph "Event Consumers"
        LAMBDA1[Order Processing<br/>Lambda]
        LAMBDA2[Inventory Update<br/>Lambda]
        SQS[SQS Queue<br/>Async Processing]
        SNS[SNS Topic<br/>Notifications]
        S3[S3 Bucket<br/>Event Archive]
    end
    
    subgraph "External Systems"
        CRM[CRM System]
        EMAIL[Email Service]
        SLACK[Slack Notifications]
    end
    
    ORDER --> CUSTOM
    PAYMENT --> CUSTOM
    INVENTORY --> CUSTOM
    API --> DEFAULT
    
    CUSTOM --> RULES
    DEFAULT --> RULES
    
    RULES --> LAMBDA1
    RULES --> LAMBDA2
    RULES --> SQS
    RULES --> SNS
    RULES --> S3
    RULES --> CRM
    RULES --> EMAIL
    RULES --> SLACK
    
    style CUSTOM fill:#87CEEB
    style RULES fill:#FFD700
    style LAMBDA1 fill:#98FB98
    style LAMBDA2 fill:#98FB98
```

## Prerequisites

1. AWS account with permissions to create EventBridge resources, Lambda functions, SQS queues, and IAM roles
2. Understanding of event-driven architecture concepts and microservices patterns
3. Familiarity with JSON for event structure and pattern matching
4. AWS CLI v2 installed and configured
5. Basic knowledge of Lambda functions and serverless architectures
6. Estimated cost: $5-15 per month for moderate usage (100K events, Lambda executions)

> **Note**: EventBridge charges $1.00 per million custom events published and $1.00 per million rule evaluations. Review [EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/) for detailed cost considerations. The service has quotas including 100 custom event buses and 300 rules per event bus per region.

## Preparation

Set up environment variables and create foundational resources:

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export CUSTOM_BUS_NAME="ecommerce-events-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_PREFIX="eventbridge-demo-${RANDOM_SUFFIX}"

echo "Custom Event Bus: $CUSTOM_BUS_NAME"
echo "Lambda Function Prefix: $LAMBDA_FUNCTION_PREFIX"
```

Create IAM role for Lambda functions with proper EventBridge permissions:

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

# Create Lambda execution role
LAMBDA_ROLE_ARN=$(aws iam create-role \
    --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX} \
    --assume-role-policy-document file://lambda-trust-policy.json \
    --query 'Role.Arn' --output text)

# Attach basic execution policy
aws iam attach-role-policy \
    --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create custom policy for EventBridge interactions
cat > lambda-eventbridge-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents",
                "events:ListRules",
                "events:DescribeRule"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX} \
    --policy-name EventBridgeInteractionPolicy \
    --policy-document file://lambda-eventbridge-policy.json

export LAMBDA_ROLE_ARN
echo "✅ Lambda IAM role created: $LAMBDA_ROLE_ARN"

# Wait for IAM role propagation
echo "Waiting 10 seconds for IAM role propagation..."
sleep 10
```

## Steps

1. **Create a custom event bus for the e-commerce domain**:

   Amazon EventBridge custom event buses provide domain isolation and organizational boundaries for different business contexts. Unlike the default event bus, custom buses enable you to implement specific security policies, monitoring, and access controls for distinct application domains. This separation is crucial for microservices architectures where different teams manage different business capabilities while maintaining clear boundaries.

   ```bash
   # Create custom event bus with tags
   aws events create-event-bus \
       --name $CUSTOM_BUS_NAME \
       --tags Key=Purpose,Value=EcommerceDemoIntegration,Key=Environment,Value=Demo
   
   # Verify event bus creation
   aws events describe-event-bus \
       --name $CUSTOM_BUS_NAME \
       --query 'Name' --output text
   
   echo "✅ Custom event bus created: $CUSTOM_BUS_NAME"
   ```

   The custom event bus now serves as the central nervous system for our e-commerce platform, providing a dedicated communication channel that isolates e-commerce events from other application domains. This foundation enables loose coupling between services while maintaining clear domain boundaries and supporting the AWS Well-Architected Framework's reliability pillar.

2. **Create Lambda function for order processing**:

   AWS Lambda functions serve as event consumers in our event-driven architecture, providing serverless compute that automatically scales based on event volume with no server management overhead. The order processing function demonstrates the producer-consumer pattern by both consuming "Order Created" events and producing "Order Processed" or "Order Processing Failed" events. This pattern enables resilient workflows with proper error handling and event propagation across the microservices ecosystem.

   ```bash
   # Create order processing Lambda function code
   cat > order_processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing order event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate order processing logic
        print(f"Processing order {order_id} for customer {customer_id}")
        print(f"Order total: ${total_amount}")
        
        # Emit order processed event
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'totalAmount': total_amount,
                        'status': 'processed',
                        'timestamp': datetime.utcnow().isoformat(),
                        'processedBy': 'order-processor-service'
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        print(f"Emitted order processed event: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order {order_id} processed successfully',
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        
        # Emit order failed event for error handling
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processing Failed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat(),
                        'failedBy': 'order-processor-service'
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

   # Package and deploy order processing Lambda
   zip order-processor.zip order_processor.py

   ORDER_LAMBDA_ARN=$(aws lambda create-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-order-processor \
       --runtime python3.12 \
       --role $LAMBDA_ROLE_ARN \
       --handler order_processor.lambda_handler \
       --zip-file fileb://order-processor.zip \
       --timeout 30 \
       --memory-size 256 \
       --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
       --query 'FunctionArn' --output text)

   export ORDER_LAMBDA_ARN
   echo "✅ Order processing Lambda created: $ORDER_LAMBDA_ARN"
   ```

   The order processing Lambda is now deployed and ready to handle incoming order events with automatic scaling capabilities. This function implements the event-driven pattern where each service responsibility is clearly defined - it processes orders and emits status events that other services can consume. The function's ability to emit both success and failure events enables comprehensive workflow orchestration and supports proper error handling throughout the system.

3. **Create Lambda function for inventory management**:

   The inventory management function demonstrates how event-driven architectures handle complex business logic through event reactions and state management. This Lambda consumes order processing events and makes inventory decisions, then emits appropriate events based on availability. The simulated inventory availability demonstrates real-world scenarios where inventory checks might succeed or fail, showcasing how event-driven systems handle variable outcomes gracefully while maintaining system resilience.

   ```bash
   # Create inventory management Lambda function code
   cat > inventory_manager.py << 'EOF'
import json
import boto3
import os
import random
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing inventory event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate inventory check and reservation
        print(f"Checking inventory for order {order_id}")
        
        # Simulate inventory availability (75% success rate for demo)
        inventory_available = random.choice([True, True, True, False])
        
        if inventory_available:
            # Emit inventory reserved event
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'customerId': customer_id,
                            'totalAmount': total_amount,
                            'status': 'reserved',
                            'reservationId': f"res-{order_id}-{int(datetime.now().timestamp())}",
                            'timestamp': datetime.utcnow().isoformat(),
                            'reservedBy': 'inventory-manager-service'
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory reserved for order {order_id}',
                    'eventId': response['Entries'][0]['EventId']
                })
            }
        else:
            # Emit inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'customerId': customer_id,
                            'status': 'unavailable',
                            'reason': 'Insufficient stock',
                            'timestamp': datetime.utcnow().isoformat(),
                            'checkedBy': 'inventory-manager-service'
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory unavailable for order {order_id}'
                })
            }
        
    except Exception as e:
        print(f"Error managing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

   # Package and deploy inventory management Lambda
   zip inventory-manager.zip inventory_manager.py

   INVENTORY_LAMBDA_ARN=$(aws lambda create-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-inventory-manager \
       --runtime python3.12 \
       --role $LAMBDA_ROLE_ARN \
       --handler inventory_manager.lambda_handler \
       --zip-file fileb://inventory-manager.zip \
       --timeout 30 \
       --memory-size 256 \
       --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
       --query 'FunctionArn' --output text)

   export INVENTORY_LAMBDA_ARN
   echo "✅ Inventory management Lambda created: $INVENTORY_LAMBDA_ARN"
   ```

   The inventory management function is now operational and ready to process order events with intelligent decision-making capabilities. This service demonstrates the event-driven principle of single responsibility - it focuses solely on inventory decisions while communicating results through events. The function's dual-outcome approach (reserved vs unavailable) shows how event-driven systems can branch workflows based on business conditions while maintaining loose coupling.

4. **Create SQS queue for asynchronous payment processing**:

   Amazon SQS provides reliable, asynchronous message processing that decouples payment processing from the immediate order flow, improving system resilience and fault tolerance. The 30-second delay ensures inventory reservation is fully committed before payment processing begins, while the 5-minute visibility timeout provides sufficient time for payment processing operations. This approach prevents race conditions and ensures proper order sequencing in distributed systems following AWS Well-Architected reliability principles.

   ```bash
   # Create SQS queue for payment processing with proper configuration
   PAYMENT_QUEUE_URL=$(aws sqs create-queue \
       --queue-name ${LAMBDA_FUNCTION_PREFIX}-payment-processing \
       --attributes DelaySeconds=30,VisibilityTimeoutSeconds=300,MessageRetentionPeriod=1209600 \
       --query 'QueueUrl' --output text)
   
   PAYMENT_QUEUE_ARN=$(aws sqs get-queue-attributes \
       --queue-url $PAYMENT_QUEUE_URL \
       --attribute-names QueueArn \
       --query 'Attributes.QueueArn' --output text)
   
   export PAYMENT_QUEUE_URL
   export PAYMENT_QUEUE_ARN
   
   echo "✅ Payment processing queue created: $PAYMENT_QUEUE_URL"
   ```

   The SQS queue now serves as a reliable buffer for payment processing, enabling asynchronous workflows that improve system resilience and scalability. This pattern prevents payment processing bottlenecks from impacting upstream services and provides automatic retry capabilities for failed payment operations, supporting high availability and fault tolerance requirements.

5. **Create EventBridge rules with intelligent event patterns**:

   EventBridge rules define the intelligent routing logic that connects event producers to consumers through sophisticated pattern matching capabilities. These rules enable content-based routing where events are delivered to targets based on their structure, source, and metadata. The pattern matching capability eliminates the need for custom routing code and provides a declarative approach to event flow management that scales automatically with your system.

   ```bash
   # Rule 1: Route new orders to order processing Lambda
   cat > order-rule-pattern.json << EOF
{
    "source": ["ecommerce.api"],
    "detail-type": ["Order Created"],
    "detail": {
        "totalAmount": [{"numeric": [">", 0]}]
    }
}
EOF

   aws events put-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-order-processing-rule \
       --event-pattern file://order-rule-pattern.json \
       --state ENABLED \
       --event-bus-name $CUSTOM_BUS_NAME \
       --description "Route new orders to processing Lambda"

   # Add Lambda permission and target
   aws lambda add-permission \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-order-processor \
       --statement-id allow-eventbridge-order-rule \
       --action lambda:InvokeFunction \
       --principal events.amazonaws.com \
       --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${LAMBDA_FUNCTION_PREFIX}-order-processing-rule

   aws events put-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-order-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --targets "Id"="1","Arn"="$ORDER_LAMBDA_ARN"

   echo "✅ Order processing rule created"
   ```

   ```bash
   # Rule 2: Route processed orders to inventory management
   cat > inventory-rule-pattern.json << EOF
{
    "source": ["ecommerce.order"],
    "detail-type": ["Order Processed"],
    "detail": {
        "status": ["processed"]
    }
}
EOF

   aws events put-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule \
       --event-pattern file://inventory-rule-pattern.json \
       --state ENABLED \
       --event-bus-name $CUSTOM_BUS_NAME \
       --description "Route processed orders to inventory check"

   # Add Lambda permission and target
   aws lambda add-permission \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-inventory-manager \
       --statement-id allow-eventbridge-inventory-rule \
       --action lambda:InvokeFunction \
       --principal events.amazonaws.com \
       --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule

   aws events put-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --targets "Id"="1","Arn"="$INVENTORY_LAMBDA_ARN"

   echo "✅ Inventory check rule created"
   ```

   ```bash
   # Rule 3: Route inventory reserved events to payment processing
   cat > payment-rule-pattern.json << EOF
{
    "source": ["ecommerce.inventory"],
    "detail-type": ["Inventory Reserved"],
    "detail": {
        "status": ["reserved"]
    }
}
EOF

   aws events put-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule \
       --event-pattern file://payment-rule-pattern.json \
       --state ENABLED \
       --event-bus-name $CUSTOM_BUS_NAME \
       --description "Route inventory reserved events to payment"

   # Add SQS permission for EventBridge to send messages
   aws sqs add-permission \
       --queue-url $PAYMENT_QUEUE_URL \
       --label allow-eventbridge-payment-rule \
       --aws-account-ids $AWS_ACCOUNT_ID \
       --actions SendMessage

   aws events put-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --targets "Id"="1","Arn"="$PAYMENT_QUEUE_ARN"

   echo "✅ Payment processing rule created"
   ```

   The EventBridge rules now provide intelligent event routing based on content and metadata, enabling sophisticated workflow orchestration. These rules demonstrate how event-driven architectures can implement complex business logic through declarative patterns rather than imperative code, making the system more maintainable, scalable, and easier to understand for development teams.

6. **Create comprehensive monitoring and debugging capabilities**:

   Comprehensive event monitoring is essential for production event-driven systems, providing observability, debugging capabilities, and audit trails. This monitoring rule captures all e-commerce events for centralized logging and analysis. CloudWatch Logs integration provides the foundation for troubleshooting, performance analysis, and compliance reporting across the entire event-driven architecture, supporting operational excellence principles.

   ```bash
   # Rule 4: Archive all events to CloudWatch Logs for monitoring
   cat > monitoring-rule-pattern.json << EOF
{
    "source": [{"prefix": "ecommerce."}]
}
EOF

   # Create CloudWatch log group with retention policy
   aws logs create-log-group \
       --log-group-name /aws/events/${CUSTOM_BUS_NAME} \
       --retention-in-days 30

   LOG_GROUP_ARN=$(aws logs describe-log-groups \
       --log-group-name-prefix /aws/events/${CUSTOM_BUS_NAME} \
       --query 'logGroups[0].arn' --output text)

   aws events put-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-monitoring-rule \
       --event-pattern file://monitoring-rule-pattern.json \
       --state ENABLED \
       --event-bus-name $CUSTOM_BUS_NAME \
       --description "Archive all ecommerce events for monitoring"

   aws events put-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-monitoring-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --targets "Id"="1","Arn"="$LOG_GROUP_ARN"

   echo "✅ Monitoring rule created"
   ```

   The monitoring infrastructure is now in place to provide complete visibility into event flows and system behavior. This observability layer is crucial for production systems, enabling teams to track event processing, identify bottlenecks, debug issues across the distributed architecture, and maintain compliance with audit requirements.

7. **Create event generator for testing and validation**:

   The event generator function simulates API Gateway or application events that initiate order workflows, providing a realistic testing mechanism. This function demonstrates how external systems integrate with EventBridge by publishing events to custom buses. The realistic order data generation helps validate the complete event flow and ensures that all components work together correctly in an end-to-end scenario.

   ```bash
   # Create event generator Lambda function
   cat > event_generator.py << 'EOF'
import json
import boto3
import os
import random
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    # Generate realistic sample order data
    order_id = f"ord-{int(datetime.now().timestamp())}-{random.randint(1000, 9999)}"
    customer_id = f"cust-{random.randint(1000, 9999)}"
    total_amount = round(random.uniform(25.99, 299.99), 2)
    
    # Create order event with comprehensive details
    order_event = {
        'Source': 'ecommerce.api',
        'DetailType': 'Order Created',
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'currency': 'USD',
            'items': [
                {
                    'productId': f'prod-{random.randint(100, 999)}',
                    'quantity': random.randint(1, 3),
                    'price': round(total_amount / random.randint(1, 3), 2),
                    'category': random.choice(['electronics', 'books', 'clothing'])
                }
            ],
            'customerEmail': f'customer-{customer_id}@example.com',
            'timestamp': datetime.utcnow().isoformat(),
            'source': 'web-application'
        }),
        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
    }
    
    try:
        response = eventbridge.put_events(Entries=[order_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Order event generated successfully',
                'orderId': order_id,
                'totalAmount': total_amount,
                'eventId': response['Entries'][0]['EventId'],
                'failedEntryCount': response['FailedEntryCount']
            })
        }
        
    except Exception as e:
        print(f"Error generating event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

   # Package and deploy event generator Lambda
   zip event-generator.zip event_generator.py

   EVENT_GENERATOR_ARN=$(aws lambda create-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-event-generator \
       --runtime python3.12 \
       --role $LAMBDA_ROLE_ARN \
       --handler event_generator.lambda_handler \
       --zip-file fileb://event-generator.zip \
       --timeout 30 \
       --memory-size 256 \
       --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
       --query 'FunctionArn' --output text)

   export EVENT_GENERATOR_ARN
   echo "✅ Event generator Lambda created: $EVENT_GENERATOR_ARN"
   ```

   The event generator is now ready to create realistic test events that flow through our entire architecture, enabling comprehensive testing and validation. This function enables end-to-end testing and demonstrates how external systems can integrate with EventBridge to initiate complex business workflows while providing observability into system behavior.

## Validation & Testing

1. Verify custom event bus and rules are configured correctly:

   ```bash
   # List event buses
   echo "Event Buses:"
   aws events list-event-buses --query 'EventBuses[*].Name' --output table

   # List rules for custom event bus
   echo "Rules on custom event bus:"
   aws events list-rules --event-bus-name $CUSTOM_BUS_NAME \
       --query 'Rules[*].[Name, State, Description]' --output table

   # Verify Lambda functions are ready
   echo "Lambda Functions:"
   aws lambda list-functions \
       --query "Functions[?contains(FunctionName, '${LAMBDA_FUNCTION_PREFIX}')].[FunctionName, Runtime, LastModified]" \
       --output table
   ```

2. Test the event-driven architecture by generating a sample order:

   ```bash
   # Generate a test order event
   echo "Generating test order event..."
   RESULT=$(aws lambda invoke \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-event-generator \
       --payload '{}' \
       --cli-binary-format raw-in-base64-out \
       response.json)

   echo "Event generator response:"
   cat response.json | jq '.'

   echo "✅ Test order event generated"
   ```

3. Wait for event processing and check CloudWatch logs:

   ```bash
   echo "Waiting 45 seconds for event processing..."
   sleep 45

   # Check order processor logs
   echo "Order Processor Logs:"
   aws logs describe-log-streams \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-order-processor \
       --order-by LastEventTime --descending --max-items 1 \
       --query 'logStreams[0].logStreamName' --output text | \
   xargs -I {} aws logs get-log-events \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-order-processor \
       --log-stream-name {} --limit 10 \
       --query 'events[*].message' --output text

   # Check inventory manager logs
   echo "Inventory Manager Logs:"
   aws logs describe-log-streams \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-inventory-manager \
       --order-by LastEventTime --descending --max-items 1 \
       --query 'logStreams[0].logStreamName' --output text | \
   xargs -I {} aws logs get-log-events \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-inventory-manager \
       --log-stream-name {} --limit 10 \
       --query 'events[*].message' --output text
   ```

4. Check SQS queue for payment processing messages:

   ```bash
   # Check for messages in payment processing queue
   echo "Payment Queue Messages:"
   aws sqs receive-message --queue-url $PAYMENT_QUEUE_URL \
       --max-number-of-messages 5 \
       --query 'Messages[*].Body' --output text

   # Check EventBridge monitoring logs
   echo "EventBridge Event Archive Logs:"
   aws logs get-log-events \
       --log-group-name /aws/events/${CUSTOM_BUS_NAME} \
       --start-time $(date -d '10 minutes ago' +%s)000 \
       --query 'events[*].message' --output text
   ```

> **Tip**: Use EventBridge's built-in monitoring through CloudWatch metrics to track rule matches, failed invocations, and successful deliveries. Key metrics include `MatchedEvents`, `SuccessfulInvocations`, and `FailedInvocations`. For comprehensive monitoring guidance, see [EventBridge monitoring events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring.html).

## Cleanup

1. Delete EventBridge rules and targets:

   ```bash
   # Remove targets from rules
   aws events remove-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-order-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --ids "1"

   aws events remove-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --ids "1"

   aws events remove-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --ids "1"

   aws events remove-targets \
       --rule ${LAMBDA_FUNCTION_PREFIX}-monitoring-rule \
       --event-bus-name $CUSTOM_BUS_NAME \
       --ids "1"

   # Delete rules
   aws events delete-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-order-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME

   aws events delete-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule \
       --event-bus-name $CUSTOM_BUS_NAME

   aws events delete-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule \
       --event-bus-name $CUSTOM_BUS_NAME

   aws events delete-rule \
       --name ${LAMBDA_FUNCTION_PREFIX}-monitoring-rule \
       --event-bus-name $CUSTOM_BUS_NAME

   echo "✅ EventBridge rules deleted"
   ```

2. Delete Lambda functions:

   ```bash
   aws lambda delete-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-order-processor

   aws lambda delete-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-inventory-manager

   aws lambda delete-function \
       --function-name ${LAMBDA_FUNCTION_PREFIX}-event-generator

   echo "✅ Lambda functions deleted"
   ```

3. Delete SQS queue and CloudWatch log groups:

   ```bash
   aws sqs delete-queue --queue-url $PAYMENT_QUEUE_URL

   aws logs delete-log-group \
       --log-group-name /aws/events/${CUSTOM_BUS_NAME}

   aws logs delete-log-group \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-order-processor

   aws logs delete-log-group \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-inventory-manager

   aws logs delete-log-group \
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-event-generator

   echo "✅ SQS queue and CloudWatch log groups deleted"
   ```

4. Delete custom event bus and IAM resources:

   ```bash
   aws events delete-event-bus --name $CUSTOM_BUS_NAME

   # Delete IAM role and policies
   aws iam delete-role-policy \
       --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX} \
       --policy-name EventBridgeInteractionPolicy

   aws iam detach-role-policy \
       --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX} \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

   aws iam delete-role --role-name EventBridgeDemoLambdaRole-${RANDOM_SUFFIX}

   echo "✅ Event bus and IAM resources deleted"
   ```

5. Clean up local files:

   ```bash
   rm -f lambda-trust-policy.json lambda-eventbridge-policy.json
   rm -f order-rule-pattern.json inventory-rule-pattern.json
   rm -f payment-rule-pattern.json monitoring-rule-pattern.json
   rm -f order_processor.py inventory_manager.py event_generator.py
   rm -f order-processor.zip inventory-manager.zip event-generator.zip
   rm -f response.json

   echo "✅ Local files cleaned up"
   ```

## Discussion

[Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html) serves as a serverless event bus that enables loosely coupled, event-driven architectures at scale, supporting the AWS Well-Architected Framework's reliability and performance efficiency pillars. Unlike traditional message queues or pub/sub systems, EventBridge provides intelligent event routing through sophisticated pattern matching, allowing complex conditional logic without custom code. This capability is essential for modern microservices architectures where services need to communicate asynchronously while maintaining independence, resilience, and the ability to evolve independently.

The custom event bus pattern demonstrated in this recipe provides domain isolation and better organization than using only the default event bus, supporting organizational boundaries and team autonomy. By creating domain-specific buses (e-commerce, user management, analytics), organizations can implement clear boundaries between different business contexts, apply different security policies, and manage event flow more effectively. [Event patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html) enable sophisticated filtering and routing logic, allowing multiple consumers to process the same events differently based on content, metadata, or business rules, supporting the microservices principle of loose coupling.

EventBridge's integration capabilities extend beyond AWS services to include third-party SaaS applications through partner event sources and custom applications through [API destinations](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-api-destinations.html). This makes it an ideal choice for hybrid architectures where on-premises systems, cloud services, and external APIs must work together seamlessly. The service's built-in monitoring through CloudWatch, event replay capabilities for debugging, and [schema registry](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-schema-registry.html) for event governance provide enterprise-grade operational features that are essential for production systems. Organizations should consider implementing dead letter queues, event archiving, and cross-region replication for comprehensive event-driven architectures that can handle failures gracefully, maintain audit trails, and support disaster recovery requirements following AWS best practices.

> **Warning**: When implementing production EventBridge architectures, ensure proper IAM permissions are configured for cross-account event delivery and consider implementing [resource-based policies](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html) for proper resource isolation and security boundaries. Follow the principle of least privilege for all EventBridge interactions.

## Challenge

Extend this event-driven architecture by implementing these enhancements: 1) Create a comprehensive order fulfillment workflow using AWS Step Functions as an EventBridge target to coordinate order validation, payment processing, inventory reservation, and shipping notification steps with proper error handling and compensation logic. 2) Implement event schema validation using EventBridge Schema Registry to ensure event consistency across all producers and consumers while enabling schema evolution. 3) Add cross-region event replication for disaster recovery using EventBridge replication rules and implement custom API destinations to integrate with external CRM and analytics systems. 4) Create a dead letter queue pattern for failed events and implement event replay capabilities for debugging and recovery scenarios. 5) Add comprehensive monitoring and alerting using CloudWatch alarms and SNS notifications for system health and performance metrics.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*