# Event Sourcing Architecture with EventBridge and DynamoDB - Terraform Implementation

This Terraform configuration deploys a complete event sourcing architecture using Amazon EventBridge and DynamoDB, implementing the CQRS (Command Query Responsibility Segregation) pattern for building scalable, auditable event-driven systems.

## Architecture Overview

The infrastructure creates:
- **EventBridge Custom Bus**: Central event routing with archiving for replay
- **DynamoDB Event Store**: Immutable event storage with DynamoDB Streams
- **DynamoDB Read Model**: Materialized views for fast queries
- **Lambda Functions**: Command processing, event projection, and querying
- **SQS Dead Letter Queue**: Failed event handling
- **CloudWatch Monitoring**: Alarms and observability

## Components

### Core Infrastructure
- **Custom EventBridge Bus**: Isolated event routing with pattern matching
- **Event Archive**: 365-day retention for event replay capabilities
- **Event Store Table**: Composite primary key (AggregateId, EventSequence) with GSI
- **Read Model Table**: Optimized projections for query performance

### Lambda Functions
- **Command Handler**: Processes commands and generates events
- **Projection Handler**: Materializes read models from event stream
- **Query Handler**: Provides various query capabilities

### Monitoring & Reliability
- **CloudWatch Alarms**: DynamoDB throttling, Lambda errors, EventBridge failures
- **Dead Letter Queue**: Captures failed events for manual processing
- **Comprehensive Logging**: CloudWatch logs for all components

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - EventBridge (create bus, rules, targets)
  - DynamoDB (create tables, streams)
  - Lambda (create functions, permissions)
  - IAM (create roles, policies)
  - SQS (create queues)
  - CloudWatch (create alarms)

## Quick Start

### 1. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 2. Test the System

After deployment, you can test the system using the provided sample payloads:

```bash
# Test command processing
aws lambda invoke \
    --function-name $(terraform output -raw command_handler_function_name) \
    --payload '$(terraform output -raw test_command_payload)' \
    response.json

# Check the response
cat response.json

# Test query processing
aws lambda invoke \
    --function-name $(terraform output -raw query_handler_function_name) \
    --payload '$(terraform output -raw test_query_payload)' \
    query_response.json

# Check query response
cat query_response.json
```

### 3. Verify Event Storage

```bash
# Check events in the event store
aws dynamodb query \
    --table-name $(terraform output -raw event_store_table_name) \
    --key-condition-expression "AggregateId = :aid" \
    --expression-attribute-values '{":aid": {"S": "account-123"}}'

# Check read model projections
aws dynamodb get-item \
    --table-name $(terraform output -raw read_model_table_name) \
    --key '{
        "AccountId": {"S": "account-123"},
        "ProjectionType": {"S": "AccountSummary"}
    }'
```

## Configuration Variables

### Required Variables
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment name (dev/staging/prod)

### Optional Variables
- `resource_suffix`: Custom suffix for resource names
- `event_store_read_capacity`: DynamoDB read capacity for event store
- `event_store_write_capacity`: DynamoDB write capacity for event store
- `lambda_timeout`: Lambda function timeout in seconds
- `lambda_memory_size`: Lambda function memory allocation
- `enable_cloudwatch_alarms`: Enable/disable CloudWatch alarms

### Example terraform.tfvars

```hcl
aws_region = "us-west-2"
environment = "production"
resource_suffix = "prod"
event_store_read_capacity = 20
event_store_write_capacity = 20
lambda_timeout = 60
lambda_memory_size = 256
enable_cloudwatch_alarms = true
```

## Outputs

The configuration provides comprehensive outputs including:
- Resource names and ARNs
- Testing instructions and sample payloads
- Monitoring and validation commands

Key outputs:
- `event_bus_name`: EventBridge bus name
- `event_store_table_name`: Event store table name
- `read_model_table_name`: Read model table name
- `command_handler_function_name`: Command handler function name
- `testing_instructions`: Complete testing guide

## Event Types and Patterns

### Supported Event Types
- **AccountCreated**: Initial account creation
- **TransactionProcessed**: Financial transaction processing
- **AccountClosed**: Account closure

### Event Pattern
```json
{
  "source": ["event-sourcing.financial"],
  "detail-type": ["AccountCreated", "TransactionProcessed", "AccountClosed"]
}
```

## Query Capabilities

The query handler supports multiple query types:

### 1. Current State Queries (Fast)
```json
{
  "queryType": "getAccountSummary",
  "accountId": "account-123"
}
```

### 2. Historical State Reconstruction
```json
{
  "queryType": "reconstructState",
  "aggregateId": "account-123",
  "upToSequence": 10
}
```

### 3. Event History Queries
```json
{
  "queryType": "getAggregateEvents",
  "aggregateId": "account-123"
}
```

### 4. Event Type Queries
```json
{
  "queryType": "getEventsByType",
  "eventType": "TransactionProcessed",
  "startTime": "2024-01-01T00:00:00Z",
  "endTime": "2024-01-31T23:59:59Z"
}
```

## Event Replay

The system supports event replay using EventBridge archives:

```bash
# Create a replay for the last hour
aws events start-replay \
    --replay-name "financial-replay-$(date +%s)" \
    --event-source-arn $(terraform output -raw event_bus_arn) \
    --event-start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --event-end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --destination '{
        "Arn": "$(terraform output -raw event_bus_arn)",
        "FilterArns": []
    }'
```

## Monitoring

### CloudWatch Metrics
- **DynamoDB**: Read/write capacity, throttling events
- **Lambda**: Duration, errors, invocations
- **EventBridge**: Successful/failed invocations

### CloudWatch Alarms
- Event store write throttles (threshold: 5 events)
- Command handler errors (threshold: 10 errors)
- EventBridge failed invocations (threshold: 5 failures)

### Viewing Logs
```bash
# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# View specific function logs
aws logs tail /aws/lambda/$(terraform output -raw command_handler_function_name) --follow
```

## Security Considerations

### IAM Permissions
- Lambda functions use least privilege IAM roles
- DynamoDB access restricted to specific tables
- EventBridge permissions limited to custom bus

### Data Encryption
- DynamoDB encryption at rest (default AWS managed keys)
- Lambda environment variables encrypted
- EventBridge events encrypted in transit

## Cost Optimization

### DynamoDB
- Use provisioned capacity for predictable workloads
- Enable DynamoDB Auto Scaling for variable workloads
- Consider on-demand billing for unpredictable patterns

### Lambda
- Right-size memory allocation based on actual usage
- Use provisioned concurrency for consistent performance
- Monitor duration and optimize code performance

### EventBridge
- Use event pattern filtering to reduce unnecessary invocations
- Archive events selectively based on retention requirements

## Troubleshooting

### Common Issues

1. **Lambda Timeout Errors**
   - Increase `lambda_timeout` variable
   - Optimize Lambda function code
   - Check DynamoDB performance

2. **DynamoDB Throttling**
   - Increase read/write capacity
   - Enable auto-scaling
   - Implement exponential backoff

3. **EventBridge Rule Not Triggering**
   - Verify event pattern matching
   - Check Lambda permissions
   - Review CloudWatch logs

### Debugging Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/$(terraform output -raw command_handler_function_name)

# Check DynamoDB table status
aws dynamodb describe-table --table-name $(terraform output -raw event_store_table_name)

# Check EventBridge rule targets
aws events list-targets-by-rule --rule financial-events-rule --event-bus-name $(terraform output -raw event_bus_name)
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data in DynamoDB tables and remove all infrastructure components.

## Next Steps

1. **Production Readiness**:
   - Enable DynamoDB Point-in-Time Recovery
   - Configure cross-region replication
   - Implement encryption with customer-managed keys

2. **Monitoring Enhancement**:
   - Add custom CloudWatch dashboards
   - Implement distributed tracing with X-Ray
   - Set up SNS notifications for alarms

3. **Advanced Features**:
   - Implement event schema validation
   - Add event transformation capabilities
   - Create snapshot projections for performance

## Support

For issues with this Terraform configuration:
1. Check the troubleshooting section
2. Review CloudWatch logs for error details
3. Consult the original recipe documentation
4. Refer to AWS service documentation

## License

This infrastructure code is provided as-is for educational and development purposes.