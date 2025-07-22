# Infrastructure as Code for CQRS and Event Sourcing with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CQRS and Event Sourcing with EventBridge".

## Overview

This infrastructure implements a complete CQRS (Command Query Responsibility Segregation) and Event Sourcing architecture using AWS services. The solution separates write commands from read queries, stores all state changes as immutable events, and enables building multiple optimized read models from the same event stream.

## Architecture Components

- **Event Store**: DynamoDB table with streams for immutable event storage
- **Read Models**: Separate DynamoDB tables optimized for query patterns
- **EventBridge**: Custom event bus for event distribution and routing
- **Lambda Functions**: Command handlers, query handlers, and projection processors
- **IAM Roles**: Least-privilege security configuration for each component

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - DynamoDB (CreateTable, Query, PutItem, UpdateItem, DeleteItem)
  - Lambda (CreateFunction, UpdateFunctionCode, InvokeFunction)
  - EventBridge (CreateEventBus, PutRule, PutTargets)
  - IAM (CreateRole, AttachRolePolicy, CreatePolicy)
  - CloudWatch Logs (CreateLogGroup, PutLogEvents)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

> **Note**: Estimated cost for testing: $10-15. Remember to clean up resources after testing to avoid ongoing charges.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cqrs-event-sourcing-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-cqrs-demo

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cqrs-event-sourcing-demo

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cqrs-event-sourcing-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters projectName=my-cqrs-demo

# Get stack outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=my-cqrs-demo

# Get stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_name=my-cqrs-demo"

# Apply the configuration
terraform apply -var="project_name=my-cqrs-demo"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh my-cqrs-demo

# The script will create all resources and provide output values
```

## Testing the Deployment

After successful deployment, test the CQRS system:

### 1. Create a User Command

```bash
# Get the command handler function name from outputs
COMMAND_HANDLER=$(aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `command-handler`)].FunctionName' \
    --output text)

# Create a user
aws lambda invoke \
    --function-name $COMMAND_HANDLER \
    --payload '{
        "commandType": "CreateUser",
        "email": "john.doe@example.com",
        "name": "John Doe",
        "commandId": "cmd-001"
    }' \
    response.json

# Extract the user ID
USER_ID=$(cat response.json | jq -r '.aggregateId')
echo "Created user: $USER_ID"
```

### 2. Create an Order Command

```bash
# Create an order for the user
aws lambda invoke \
    --function-name $COMMAND_HANDLER \
    --payload "{
        \"commandType\": \"CreateOrder\",
        \"userId\": \"$USER_ID\",
        \"items\": [{\"product\": \"laptop\", \"quantity\": 1, \"price\": 999.99}],
        \"totalAmount\": 999.99
    }" \
    order_response.json

ORDER_ID=$(cat order_response.json | jq -r '.aggregateId')
echo "Created order: $ORDER_ID"
```

### 3. Query Read Models

```bash
# Get the query handler function name
QUERY_HANDLER=$(aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `query-handler`)].FunctionName' \
    --output text)

# Wait for eventual consistency
sleep 10

# Query user profile
aws lambda invoke \
    --function-name $QUERY_HANDLER \
    --payload "{
        \"queryType\": \"GetUserProfile\",
        \"userId\": \"$USER_ID\"
    }" \
    user_query.json

echo "User Profile:"
cat user_query.json | jq '.body | fromjson'

# Query orders by user
aws lambda invoke \
    --function-name $QUERY_HANDLER \
    --payload "{
        \"queryType\": \"GetOrdersByUser\",
        \"userId\": \"$USER_ID\"
    }" \
    orders_query.json

echo "User Orders:"
cat orders_query.json | jq '.body | fromjson'
```

### 4. Verify Event Store

```bash
# Get the event store table name
EVENT_STORE_TABLE=$(aws dynamodb list-tables \
    --query 'TableNames[?contains(@, `event-store`)]' \
    --output text)

# Query events for the user
aws dynamodb query \
    --table-name $EVENT_STORE_TABLE \
    --key-condition-expression "AggregateId = :id" \
    --expression-attribute-values "{\":id\":{\"S\":\"$USER_ID\"}}"
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# List log groups
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/cqrs" \
    --query 'logGroups[*].logGroupName'

# View recent logs for command handler
aws logs tail /aws/lambda/your-command-handler-function --follow
```

### EventBridge Monitoring

Check event flow through EventBridge:

```bash
# List custom event buses
aws events list-event-buses \
    --query 'EventBuses[?Name != `default`]'

# Check event rules
aws events list-rules \
    --event-bus-name your-event-bus-name
```

### DynamoDB Monitoring

Monitor table metrics and streams:

```bash
# Check table status
aws dynamodb describe-table \
    --table-name your-event-store-table \
    --query 'Table.TableStatus'

# Check stream status
aws dynamodb describe-table \
    --table-name your-event-store-table \
    --query 'Table.StreamSpecification'
```

## Customization

### Configuration Parameters

All implementations support these customization options:

- **project_name**: Prefix for all resource names (default: cqrs-demo)
- **environment**: Environment identifier (default: dev)
- **retention_days**: EventBridge archive retention (default: 30)
- **lambda_timeout**: Lambda function timeout in seconds (default: 30)
- **dynamodb_capacity**: Read/write capacity units (default: 5-10)

### Terraform Variables

```hcl
# terraform/variables.tf
variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "cqrs-demo"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}
```

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: cqrs-demo
    Description: Project name prefix for resources
    
  Environment:
    Type: String
    Default: dev
    Description: Environment identifier
    
  RetentionDays:
    Type: Number
    Default: 30
    Description: EventBridge archive retention in days
```

## Security Considerations

### IAM Roles and Policies

The infrastructure implements least-privilege access:

- **Command Handler Role**: Write access to event store only
- **Projection Handler Role**: Read access to event store, write access to specific read models
- **Query Handler Role**: Read access to read models only

### Encryption

- DynamoDB tables use AWS managed encryption
- Lambda environment variables are encrypted
- EventBridge events are encrypted in transit

### Network Security

- All Lambda functions use VPC configuration (optional)
- Security groups restrict access to necessary ports only
- NAT Gateway for private subnet Lambda functions (if VPC is used)

## Performance Optimization

### DynamoDB Optimization

- Event store uses composite primary key for efficient querying
- Global Secondary Indexes on event type and timestamp
- Proper capacity planning based on expected load
- Consider DynamoDB On-Demand for variable workloads

### Lambda Optimization

- Appropriate memory allocation for each function type
- Connection pooling for DynamoDB clients
- Proper timeout configuration
- Consider Provisioned Concurrency for critical functions

### EventBridge Optimization

- Content-based routing to minimize unnecessary invocations
- Event archives for replay capabilities
- Proper error handling and dead letter queues

## Troubleshooting Common Issues

### Event Processing Delays

If read models are not updating:

1. Check DynamoDB Streams configuration
2. Verify Lambda function permissions
3. Monitor CloudWatch logs for errors
4. Check EventBridge rule configurations

### Command Failures

If commands are failing:

1. Verify DynamoDB table exists and is active
2. Check IAM permissions for command handler
3. Review CloudWatch logs for detailed errors
4. Validate command payload format

### Query Inconsistencies

If queries return unexpected results:

1. Allow time for eventual consistency (5-10 seconds)
2. Check projection handler logs
3. Verify EventBridge event delivery
4. Review read model table contents

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack \
    --stack-name cqrs-event-sourcing-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cqrs-event-sourcing-demo
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy

# Confirm deletion when prompted
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_name=my-cqrs-demo"

# Type 'yes' when prompted to confirm
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh my-cqrs-demo

# Confirm deletion when prompted
```

### Manual Cleanup Verification

After running cleanup, verify all resources are deleted:

```bash
# Check for remaining Lambda functions
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `cqrs`) || contains(FunctionName, `my-cqrs-demo`)]'

# Check for remaining DynamoDB tables
aws dynamodb list-tables \
    --query 'TableNames[?contains(@, `cqrs`) || contains(@, `my-cqrs-demo`)]'

# Check for remaining EventBridge resources
aws events list-event-buses \
    --query 'EventBuses[?contains(Name, `cqrs`) || contains(Name, `my-cqrs-demo`)]'

# Check for remaining IAM roles
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `cqrs`) || contains(RoleName, `my-cqrs-demo`)]'
```

## Support and Documentation

### Additional Resources

- [AWS DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [AWS EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [CQRS Pattern Documentation](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/decompose-monoliths-into-microservices-by-using-cqrs-and-event-sourcing.html)

### Getting Help

- For infrastructure issues, check the CloudFormation/CDK/Terraform documentation
- For application logic issues, refer to the original recipe documentation
- For AWS service issues, consult the AWS documentation and support

### Contributing

To improve this infrastructure code:

1. Test thoroughly in a development environment
2. Follow the established patterns and conventions
3. Update documentation for any changes
4. Ensure security best practices are maintained

---

**Note**: This infrastructure implements a production-ready CQRS and Event Sourcing pattern with proper security, monitoring, and error handling. Always test in a development environment before deploying to production.