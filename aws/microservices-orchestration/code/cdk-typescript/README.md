# Event-Driven Microservices with EventBridge and Step Functions - CDK TypeScript

This directory contains a complete CDK TypeScript implementation for the event-driven microservices architecture recipe using Amazon EventBridge and AWS Step Functions.

## Architecture Overview

This solution deploys a production-ready event-driven microservices architecture with the following components:

- **EventBridge Custom Event Bus**: Decoupled messaging between microservices
- **Step Functions State Machine**: Orchestrates complex order processing workflows
- **Lambda Functions**: Four microservices (Order, Payment, Inventory, Notification)
- **DynamoDB Table**: Persistent storage for order data with GSI for customer queries
- **CloudWatch Dashboard**: Real-time monitoring and observability
- **IAM Roles**: Least privilege security for cross-service communication

## Prerequisites

Before deploying this solution, ensure you have:

- **AWS CLI v2** installed and configured with appropriate credentials
- **Node.js 16+** and npm installed
- **AWS CDK v2** installed (`npm install -g aws-cdk`)
- **TypeScript** installed (`npm install -g typescript`)
- AWS account with permissions for:
  - EventBridge (create custom event buses, rules, targets)
  - Step Functions (create state machines, executions)
  - Lambda (create functions, invoke functions)
  - DynamoDB (create tables, read/write items)
  - CloudWatch (create dashboards, log groups)
  - IAM (create roles, attach policies)

## Quick Start

### 1. Install Dependencies

```bash
# Install npm dependencies
npm install

# Build the TypeScript code
npm run build
```

### 2. Bootstrap CDK (first time only)

```bash
# Bootstrap CDK in your AWS account/region
npm run bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default configuration
npm run deploy

# Deploy with custom environment
npm run deploy -- -c environment=prod -c projectName=my-microservices
```

### 4. Test the Architecture

After deployment, test the event-driven workflow:

```bash
# Get the Order Service function name from the stack outputs
ORDER_SERVICE_NAME=$(aws cloudformation describe-stacks \
    --stack-name EventDrivenMicroservicesStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderServiceName`].OutputValue' \
    --output text)

# Submit a test order
aws lambda invoke \
    --function-name $ORDER_SERVICE_NAME \
    --payload '{
        "customerId": "customer-123",
        "items": [
            {"productId": "prod-001", "quantity": 2, "price": 29.99},
            {"productId": "prod-002", "quantity": 1, "price": 49.99}
        ],
        "totalAmount": 109.97
    }' \
    test-response.json

# View the response
cat test-response.json
```

## Available Commands

```bash
# Development commands
npm run build          # Compile TypeScript to JavaScript
npm run watch          # Watch for changes and compile automatically
npm run test           # Run Jest tests
npm run lint           # Run ESLint code linting
npm run lint:fix       # Fix ESLint issues automatically

# CDK commands
npm run synth          # Synthesize CloudFormation template
npm run deploy         # Deploy the stack to AWS
npm run destroy        # Destroy the stack and all resources
npm run diff           # Show differences between local and deployed stack
```

## Configuration Options

You can customize the deployment using CDK context variables:

```bash
# Custom project name and environment
cdk deploy -c projectName=my-project -c environment=staging

# Deploy to specific AWS account/region
cdk deploy --profile my-profile --region us-west-2
```

### Available Context Variables

- `projectName`: Base name for all resources (default: "microservices-demo")
- `environment`: Environment suffix for resources (default: "dev")

## Architecture Details

### Event Flow

1. **Order Creation**: Client invokes Order Service Lambda function
2. **Event Publishing**: Order Service publishes "Order Created" event to EventBridge
3. **Workflow Trigger**: EventBridge rule triggers Step Functions state machine
4. **Payment Processing**: State machine invokes Payment Service with retry logic
5. **Inventory Reservation**: On payment success, invokes Inventory Service
6. **Notifications**: Success or failure notifications sent via Notification Service
7. **Error Handling**: Comprehensive error handling with exponential backoff retries

### Lambda Functions

#### Order Service
- **Purpose**: Creates orders and publishes events
- **Runtime**: Python 3.9
- **Timeout**: 30 seconds
- **Memory**: 256 MB
- **Events**: Publishes "Order Created" to EventBridge

#### Payment Service
- **Purpose**: Processes payments with 90% success simulation
- **Runtime**: Python 3.9
- **Timeout**: 30 seconds
- **Memory**: 256 MB
- **Events**: Publishes "Payment Processed/Failed" to EventBridge

#### Inventory Service
- **Purpose**: Manages inventory with 95% availability simulation
- **Runtime**: Python 3.9
- **Timeout**: 30 seconds
- **Memory**: 256 MB
- **Events**: Publishes "Inventory Reserved/Unavailable" to EventBridge

#### Notification Service
- **Purpose**: Handles notifications and logging
- **Runtime**: Python 3.9
- **Timeout**: 30 seconds
- **Memory**: 256 MB

### Step Functions Workflow

The state machine implements a sophisticated order processing workflow:

```
ProcessPayment → CheckPaymentStatus → ReserveInventory → CheckInventoryStatus → SendNotification
     ↓                    ↓                    ↓                    ↓
PaymentFailed      PaymentFailed      InventoryFailed      InventoryFailed
```

**Error Handling Features**:
- Exponential backoff retry policies
- Service exception handling
- Comprehensive error logging
- Graceful failure notifications

### DynamoDB Schema

**Orders Table**:
- **Partition Key**: `orderId` (String)
- **Sort Key**: `customerId` (String)
- **GSI**: `CustomerId-Index` for customer-based queries
- **Attributes**: items, totalAmount, status, createdAt, updatedAt, paymentId

### Security

**IAM Roles and Policies**:
- **Lambda Execution Role**: DynamoDB access, EventBridge publish permissions
- **Step Functions Role**: Lambda invoke permissions
- **Least Privilege**: Minimal required permissions for each service

## Monitoring and Observability

### CloudWatch Dashboard

The deployment creates a comprehensive dashboard with:
- Lambda function invocations and errors
- Step Functions execution success/failure rates
- Real-time metrics with 5-minute granularity

### Logging

- **Lambda Logs**: Automatic CloudWatch Logs integration
- **Step Functions Logs**: Detailed execution logging with 14-day retention
- **Structured Logging**: JSON format for easy parsing and analysis

### Metrics

Key metrics automatically tracked:
- Lambda invocations, errors, duration
- Step Functions executions, successes, failures
- DynamoDB read/write capacity utilization
- EventBridge rule matches and failures

## Cost Optimization

**Estimated Monthly Costs** (development usage):
- Lambda: $2-5 (based on executions)
- Step Functions: $1-3 (standard workflows)
- DynamoDB: $2-4 (provisioned capacity)
- EventBridge: $1-2 (custom events)
- CloudWatch: $1-3 (logs and metrics)

**Total**: $7-17/month for development workloads

**Production Optimization Tips**:
- Use DynamoDB On-Demand for variable workloads
- Consider Step Functions Express workflows for high-throughput scenarios
- Implement Lambda provisioned concurrency for consistent performance
- Use CloudWatch Log retention policies to manage costs

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Ensure your AWS credentials have sufficient permissions
   aws sts get-caller-identity
   ```

2. **CDK Bootstrap Issues**
   ```bash
   # Re-bootstrap if needed
   cdk bootstrap --force
   ```

3. **TypeScript Compilation Errors**
   ```bash
   # Clean and rebuild
   rm -rf node_modules dist
   npm install
   npm run build
   ```

### Debugging Steps

1. **Check Stack Status**
   ```bash
   aws cloudformation describe-stacks --stack-name EventDrivenMicroservicesStack-dev
   ```

2. **View Lambda Logs**
   ```bash
   aws logs tail /aws/lambda/microservices-demo-order-service-xxxxx --follow
   ```

3. **Monitor Step Functions**
   ```bash
   aws stepfunctions list-executions --state-machine-arn <state-machine-arn>
   ```

## Extensions and Customizations

### Adding New Microservices

1. Create new Lambda function in the stack
2. Add EventBridge rules for new event types
3. Update Step Functions workflow if needed
4. Add monitoring widgets to dashboard

### Implementing Additional Patterns

- **Saga Pattern**: Add compensating transactions for rollbacks
- **Event Sourcing**: Store all events for replay and analytics
- **Circuit Breaker**: Add failure detection and isolation
- **CQRS**: Separate read/write models for better scalability

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Destroy the entire stack
npm run destroy

# Confirm deletion when prompted
```

**Warning**: This will permanently delete all data in DynamoDB tables and Lambda function logs.

## Support and Contributions

For issues or questions:
1. Check AWS CloudFormation stack events for deployment issues
2. Review CloudWatch logs for runtime errors
3. Consult AWS documentation for service-specific guidance
4. Open GitHub issues for recipe-specific problems

## References

- [AWS CDK TypeScript Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-typescript.html)
- [Amazon EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)