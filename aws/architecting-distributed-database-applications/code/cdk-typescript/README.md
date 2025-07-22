# Multi-Region Distributed Applications with Aurora DSQL - CDK TypeScript

This CDK TypeScript application implements a multi-region distributed application architecture using Amazon Aurora DSQL, AWS Lambda, and Amazon EventBridge. It demonstrates how to build resilient, scalable applications that can handle regional failures while maintaining strong consistency and zero downtime.

## Architecture Overview

The solution deploys infrastructure across multiple AWS regions with the following components:

### Core Components

- **Aurora DSQL Clusters**: Serverless, distributed SQL database with active-active architecture
- **Lambda Functions**: Serverless compute for business logic and database operations  
- **EventBridge Custom Buses**: Event-driven coordination across regions
- **IAM Roles & Policies**: Secure access controls following least privilege principle

### Multi-Region Configuration

- **Primary Region**: `us-east-1` - Handles primary application traffic
- **Secondary Region**: `us-west-2` - Provides active-active redundancy
- **Witness Region**: `eu-west-1` - Stores transaction logs for consensus

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for Aurora DSQL, Lambda, and EventBridge
- Access to Aurora DSQL preview (if still in preview)

## Installation and Setup

1. **Clone and Navigate to Project**:
   ```bash
   cd aws/multi-region-distributed-applications-aurora-dsql/code/cdk-typescript
   ```

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Configure AWS Environment**:
   ```bash
   # Set AWS account and region
   export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export CDK_DEFAULT_REGION=us-east-1
   ```

4. **Bootstrap CDK (if not done previously)**:
   ```bash
   # Bootstrap primary region
   cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-east-1

   # Bootstrap secondary region  
   cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-west-2
   ```

## Deployment

### Deploy All Stacks

Deploy both primary and secondary region stacks:

```bash
npm run deploy-all
```

### Deploy Individual Stacks

Deploy primary region first:
```bash
cdk deploy MultiRegionDistributedApp-Primary
```

Then deploy secondary region:
```bash
cdk deploy MultiRegionDistributedApp-Secondary
```

### Verify Deployment

Check stack outputs:
```bash
aws cloudformation describe-stacks \
    --stack-name MultiRegionDistributedApp-Primary \
    --query 'Stacks[0].Outputs'
```

## Usage Examples

### Testing Lambda Functions

1. **Test Read Operation**:
   ```bash
   aws lambda invoke \
       --function-name $(aws cloudformation describe-stacks \
           --stack-name MultiRegionDistributedApp-Primary \
           --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
           --output text) \
       --payload '{"operation":"read"}' \
       --cli-binary-format raw-in-base64-out \
       response.json && cat response.json
   ```

2. **Test Create Transaction**:
   ```bash
   aws lambda invoke \
       --function-name $(aws cloudformation describe-stacks \
           --stack-name MultiRegionDistributedApp-Primary \
           --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
           --output text) \
       --payload '{"operation":"create","transactionId":"test-001","amount":100.50}' \
       --cli-binary-format raw-in-base64-out \
       create-response.json && cat create-response.json
   ```

3. **Test Multi-Region Consistency**:
   ```bash
   # Create transaction in primary region
   aws lambda invoke --region us-east-1 \
       --function-name MultiRegionDistributedApp-Primary-DSQLProcessor \
       --payload '{"operation":"create","amount":250.75}' \
       --cli-binary-format raw-in-base64-out primary-write.json
   
   # Read from secondary region to verify consistency
   aws lambda invoke --region us-west-2 \
       --function-name MultiRegionDistributedApp-Secondary-DSQLProcessor \
       --payload '{"operation":"count"}' \
       --cli-binary-format raw-in-base64-out secondary-read.json
   
   echo "Primary region write:" && cat primary-write.json
   echo "Secondary region read:" && cat secondary-read.json
   ```

### Monitoring and Observability

1. **View Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/MultiRegionDistributedApp-Primary-DSQLProcessor --follow
   ```

2. **Monitor EventBridge Events**:
   ```bash
   aws events list-rules --event-bus-name dsql-events-$(echo $RANDOM | tr -d '0-9' | head -c 8)
   ```

3. **Check Aurora DSQL Cluster Status**:
   ```bash
   aws dsql describe-clusters --region us-east-1
   aws dsql describe-clusters --region us-west-2
   ```

## Supported Operations

The Lambda functions support the following operations:

| Operation | Description | Example Payload |
|-----------|-------------|-----------------|
| `create` / `write` | Create new transaction | `{"operation":"create","amount":100.50}` |
| `read` / `count` | Get transaction count | `{"operation":"read"}` |
| `list` / `recent` | List recent transactions | `{"operation":"list","limit":10}` |

## Database Schema

The application uses the following Aurora DSQL schema:

```sql
-- Transactions table
CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR(255) PRIMARY KEY,
    amount DECIMAL(10,2) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    region VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending'
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX IF NOT EXISTS idx_transactions_region ON transactions(region);

-- Sequence for transaction numbering
CREATE SEQUENCE IF NOT EXISTS transaction_seq START 1;
```

## Event-Driven Architecture

### EventBridge Integration

The application uses EventBridge for cross-region coordination:

- **Custom Event Bus**: `dsql-events-{uniqueId}`
- **Event Sources**: `dsql.application`
- **Event Types**: Transaction Created, Updated, Deleted

### Event Schema

```json
{
  "Source": "dsql.application",
  "DetailType": "Transaction Created",
  "Detail": {
    "transactionId": "txn-1234567890",
    "amount": 100.50,
    "region": "us-east-1",
    "operation": "create",
    "timestamp": "2025-01-21T10:30:00.000Z"
  }
}
```

## Troubleshooting

### Common Issues

1. **Aurora DSQL Access Denied**:
   - Verify Aurora DSQL is available in your region
   - Check IAM permissions for DSQL operations
   - Ensure cluster is in `available` status

2. **Lambda Function Timeout**:
   - Increase timeout in stack configuration (current: 30 seconds)
   - Check CloudWatch logs for performance bottlenecks
   - Verify network connectivity to Aurora DSQL

3. **EventBridge Events Not Processing**:
   - Check EventBridge rule configuration
   - Verify custom event bus permissions
   - Monitor EventBridge metrics in CloudWatch

### Debugging Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name MultiRegionDistributedApp-Primary-DSQLProcessor

# View CloudFormation stack events
aws cloudformation describe-stack-events --stack-name MultiRegionDistributedApp-Primary

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=MultiRegionDistributedApp-Primary-DSQLProcessor \
    --start-time 2025-01-21T00:00:00Z \
    --end-time 2025-01-21T23:59:59Z \
    --period 300 \
    --statistics Average
```

## Security Considerations

### IAM Permissions

The application follows least privilege principles:

- Lambda execution role has minimal Aurora DSQL permissions
- EventBridge permissions scoped to specific custom bus
- CloudWatch logs access for observability only

### Network Security

- All communications use AWS service-to-service encryption
- No public endpoints exposed
- VPC integration available for enhanced security (not implemented in this example)

### Data Encryption

- Aurora DSQL provides encryption at rest by default
- EventBridge events encrypted in transit
- Lambda environment variables can use KMS encryption

## Cost Optimization

### Serverless Benefits

- **Aurora DSQL**: Pay per request with automatic scaling
- **Lambda**: Pay per execution with sub-second billing
- **EventBridge**: Pay per published event

### Cost Monitoring

Monitor costs using:
- AWS Cost Explorer
- CloudWatch billing alarms
- Resource tagging for cost allocation

## Performance Optimization

### Aurora DSQL

- Uses multi-region active-active for low latency
- Automatic scaling based on workload demand
- Strong consistency across regions

### Lambda Functions

- Optimized bundle size with external modules exclusion
- Memory allocation: 256MB (adjustable based on workload)
- Connection pooling for database connections

### EventBridge

- Custom event bus for improved performance
- Event filtering to reduce unnecessary processing
- Batch processing capabilities

## Development and Testing

### Local Development

```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# Synthesize CloudFormation
npm run synth
```

### Testing Strategies

1. **Unit Tests**: Test Lambda function logic independently
2. **Integration Tests**: Test cross-service interactions
3. **Multi-Region Tests**: Verify consistency across regions
4. **Chaos Testing**: Simulate regional failures

## Cleanup

### Remove All Resources

```bash
# Destroy secondary region first
cdk destroy MultiRegionDistributedApp-Secondary

# Then destroy primary region
cdk destroy MultiRegionDistributedApp-Primary

# Or destroy all at once
npm run destroy-all
```

### Verify Cleanup

```bash
# Check remaining resources
aws cloudformation list-stacks --stack-status-filter DELETE_COMPLETE
aws dsql list-clusters --region us-east-1
aws dsql list-clusters --region us-west-2
```

## Contributing

When contributing to this project:

1. Follow TypeScript best practices
2. Maintain CDK construct patterns
3. Update documentation for new features
4. Add appropriate error handling
5. Include comprehensive logging

## Support

For issues related to this implementation:

1. Check CloudWatch logs for Lambda functions
2. Review CDK synthesis output for configuration issues
3. Verify AWS service availability in target regions
4. Consult AWS documentation for Aurora DSQL limitations

## References

- [Amazon Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)
- [AWS Multi-Region Architecture Patterns](https://aws.amazon.com/solutions/implementations/)