# Event-Driven Architecture with EventBridge - CDK TypeScript

This CDK TypeScript application deploys a complete event-driven architecture using Amazon EventBridge, demonstrating microservices communication patterns for an e-commerce platform.

## Architecture Overview

The solution creates:

- **Custom EventBridge Bus**: Dedicated event bus for e-commerce domain events
- **Lambda Functions**: Order processor, inventory manager, and event generator
- **SQS Queue**: Asynchronous payment processing with delivery delay
- **EventBridge Rules**: Intelligent event routing with content-based patterns
- **CloudWatch Logs**: Comprehensive event monitoring and auditing
- **IAM Roles**: Least-privilege security for all components

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript installed: `npm install -g typescript`

### Required AWS Permissions

Your AWS credentials must have permissions to create:
- EventBridge custom buses and rules
- Lambda functions and execution roles
- SQS queues
- CloudWatch log groups
- IAM roles and policies

## Quick Start

### 1. Install Dependencies

```bash
cd cdk-typescript/
npm install
```

### 2. Bootstrap CDK (first time only)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default settings
cdk deploy

# Deploy with custom environment and suffix
cdk deploy --context environment=prod --context uniqueSuffix=demo123
```

### 4. Test the Event-Driven Architecture

After deployment, use the test command from the stack outputs:

```bash
# The exact command will be shown in the stack outputs
aws lambda invoke --function-name [FUNCTION-NAME] --payload '{}' response.json && cat response.json
```

## Customization

### Environment Variables

Set these context variables to customize the deployment:

```bash
# Custom environment name (default: dev)
cdk deploy --context environment=production

# Custom unique suffix (default: random)
cdk deploy --context uniqueSuffix=mycompany

# Custom AWS region
export CDK_DEFAULT_REGION=us-west-2
cdk deploy
```

### Code Customization

The Lambda function code is embedded inline for simplicity. For production use, consider:

1. **External Code Files**: Move Lambda code to separate files
2. **Lambda Layers**: Share common dependencies
3. **Environment-Specific Configurations**: Use different settings per environment
4. **Error Handling**: Add comprehensive error handling and retry logic
5. **Monitoring**: Add custom CloudWatch metrics and alarms

### Advanced Configuration

Modify the stack in `lib/event-driven-architecture-stack.ts`:

```typescript
// Example: Add custom event patterns
eventPattern: {
  source: ['ecommerce.api'],
  detailType: ['Order Created'],
  detail: {
    totalAmount: [{ numeric: ['>', 100] }], // Only orders > $100
    region: ['us-east-1', 'us-west-2']      // Only specific regions
  }
}

// Example: Add Step Functions workflow
const orderWorkflow = new sfn.StateMachine(this, 'OrderWorkflow', {
  definition: // ... state machine definition
});

// Add workflow as EventBridge target
rule.addTarget(new targets.SfnStateMachine(orderWorkflow));
```

## Event Flow Testing

### 1. Generate Test Events

The event generator Lambda creates realistic order events:

```bash
# Invoke the event generator multiple times
for i in {1..5}; do
  aws lambda invoke \
    --function-name [EVENT-GENERATOR-FUNCTION-NAME] \
    --payload '{}' \
    response-$i.json
done
```

### 2. Monitor Event Processing

Check CloudWatch logs for each Lambda function:

```bash
# Order processor logs
aws logs describe-log-streams \
  --log-group-name /aws/lambda/[ORDER-PROCESSOR-FUNCTION-NAME] \
  --order-by LastEventTime --descending --max-items 1

# Inventory manager logs
aws logs describe-log-streams \
  --log-group-name /aws/lambda/[INVENTORY-MANAGER-FUNCTION-NAME] \
  --order-by LastEventTime --descending --max-items 1
```

### 3. Check SQS Queue Messages

Monitor the payment processing queue:

```bash
aws sqs receive-message \
  --queue-url [PAYMENT-QUEUE-URL] \
  --max-number-of-messages 10
```

### 4. View All Events

Check the monitoring log group for complete event history:

```bash
aws logs filter-log-events \
  --log-group-name /aws/events/[EVENT-BUS-NAME] \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Performance Considerations

### Scaling

- **Lambda Concurrency**: Configure reserved concurrency for predictable performance
- **SQS Batch Processing**: Enable batch processing for high-volume scenarios
- **EventBridge Quotas**: Monitor rule evaluations and event volume
- **CloudWatch Costs**: Set appropriate log retention periods

### Cost Optimization

```typescript
// Example: Configure cost-optimized settings
const eventLogGroup = new logs.LogGroup(this, 'EventLogGroup', {
  retention: logs.RetentionDays.THREE_DAYS,  // Shorter retention
  removalPolicy: cdk.RemovalPolicy.DESTROY
});

const orderFunction = new lambda.Function(this, 'OrderFunction', {
  memorySize: 256,  // Right-size memory allocation
  timeout: cdk.Duration.seconds(15),  // Optimize timeout
  reservedConcurrentExecutions: 10  // Control concurrency
});
```

## Security Best Practices

### IAM Least Privilege

The stack implements least-privilege IAM policies:

```typescript
// Custom IAM policy for EventBridge interactions
inlinePolicies: {
  EventBridgeInteractionPolicy: new iam.PolicyDocument({
    statements: [
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'events:PutEvents',
          'events:ListRules',
          'events:DescribeRule'
        ],
        resources: ['*']  // Consider restricting to specific resources
      })
    ]
  })
}
```

### Production Security Enhancements

1. **Resource-Specific Permissions**: Restrict IAM policies to specific EventBridge buses
2. **VPC Integration**: Deploy Lambda functions in private VPC subnets
3. **Encryption**: Enable encryption for SQS queues and CloudWatch logs
4. **Secrets Management**: Use AWS Secrets Manager for sensitive configuration

## Monitoring and Observability

### CloudWatch Metrics

Key metrics to monitor:

- `AWS/Events/MatchedEvents`: Number of events matching rules
- `AWS/Events/SuccessfulInvocations`: Successful target invocations
- `AWS/Events/FailedInvocations`: Failed target invocations
- `AWS/Lambda/Duration`: Lambda execution duration
- `AWS/Lambda/Errors`: Lambda function errors

### Custom Alarms

```typescript
// Example: Add CloudWatch alarm for failed invocations
new cloudwatch.Alarm(this, 'FailedInvocationsAlarm', {
  metric: rule.metricFailedInvocations(),
  threshold: 5,
  evaluationPeriods: 2,
  treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
});
```

### X-Ray Tracing

Enable distributed tracing for Lambda functions:

```typescript
const orderFunction = new lambda.Function(this, 'OrderFunction', {
  tracing: lambda.Tracing.ACTIVE,
  // ... other properties
});
```

## Cleanup

### Destroy the Stack

```bash
# Remove all resources
cdk destroy

# Force destruction without confirmation
cdk destroy --force
```

### Manual Cleanup

If needed, manually clean up resources:

```bash
# Delete CloudWatch log groups (if retention is set to RETAIN)
aws logs delete-log-group --log-group-name /aws/events/[BUS-NAME]
aws logs delete-log-group --log-group-name /aws/lambda/[FUNCTION-NAME]

# Empty and delete S3 buckets (if any were created)
aws s3 rm s3://[BUCKET-NAME] --recursive
aws s3 rb s3://[BUCKET-NAME]
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: If you get bootstrap errors, run `cdk bootstrap`
2. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
3. **Region Mismatch**: Verify CDK_DEFAULT_REGION matches your AWS CLI region
4. **Resource Limits**: Check AWS service quotas for your account

### Debug Commands

```bash
# View the generated CloudFormation template
cdk synth

# Check differences before deployment
cdk diff

# View stack events during deployment
aws cloudformation describe-stack-events --stack-name [STACK-NAME]
```

### Enable CDK Debug Logging

```bash
export CDK_DEBUG=true
cdk deploy
```

## Extensions

### Adding Step Functions

```typescript
import * as sfn from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';

// Define order processing workflow
const orderWorkflow = new sfn.StateMachine(this, 'OrderWorkflow', {
  definition: sfn.Chain.start(
    new sfnTasks.LambdaInvoke(this, 'ProcessOrder', {
      lambdaFunction: orderProcessorFunction
    })
  )
});

// Add as EventBridge target
orderProcessingRule.addTarget(new targets.SfnStateMachine(orderWorkflow));
```

### Adding API Gateway

```typescript
import * as apigateway from 'aws-cdk-lib/aws-apigateway';

// Create REST API for event submission
const api = new apigateway.RestApi(this, 'EventAPI', {
  restApiName: 'Event Submission API'
});

// Add integration with event generator Lambda
const integration = new apigateway.LambdaIntegration(eventGeneratorFunction);
api.root.addMethod('POST', integration);
```

### Adding DynamoDB

```typescript
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';

// Create table for order tracking
const orderTable = new dynamodb.Table(this, 'OrderTable', {
  tableName: `orders-${props.uniqueSuffix}`,
  partitionKey: { name: 'orderId', type: dynamodb.AttributeType.STRING },
  billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
  removalPolicy: cdk.RemovalPolicy.DESTROY
});

// Grant Lambda functions read/write access
orderTable.grantReadWriteData(orderProcessorFunction);
orderTable.grantReadWriteData(inventoryManagerFunction);
```

## Support

For issues with this CDK implementation:

1. Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review EventBridge documentation: https://docs.aws.amazon.com/eventbridge/
3. Check the original recipe documentation for architecture details
4. AWS re:Post community: https://repost.aws/

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.