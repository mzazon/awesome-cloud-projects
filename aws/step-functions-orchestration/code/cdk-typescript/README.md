# Microservices Step Functions - CDK TypeScript

This CDK TypeScript application deploys a complete microservices orchestration solution using AWS Step Functions, Lambda, and EventBridge.

## Architecture

The application creates:

- **5 Lambda Functions**: User Service, Order Service, Payment Service, Inventory Service, and Notification Service
- **Step Functions State Machine**: Orchestrates microservices with parallel processing and error handling
- **EventBridge Rule**: Triggers workflows based on business events
- **IAM Roles**: Proper permissions for Step Functions and EventBridge
- **CloudWatch Logs**: Comprehensive logging and monitoring

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript installed: `npm install -g typescript`

## Quick Start

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (first time only):
   ```bash
   npm run bootstrap
   ```

3. **Deploy the Stack**:
   ```bash
   npm run deploy
   ```

4. **Test the Workflow**:
   ```bash
   # Use the test command from the deployment outputs
   aws events put-events --entries Source=microservices.orders,DetailType="Order Submitted",Detail='{"userId":"12345","orderData":{"items":[{"productId":"PROD001","quantity":1,"price":99.99}]}}'
   ```

## Available Scripts

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and recompile
- `npm run test` - Run unit tests
- `npm run deploy` - Deploy the CDK stack
- `npm run destroy` - Destroy the CDK stack
- `npm run diff` - Show differences between deployed and current stack
- `npm run synth` - Synthesize CloudFormation template
- `npm run lint` - Run ESLint
- `npm run format` - Format code with Prettier

## Testing the Solution

### Manual Testing via Step Functions Console

1. Open the AWS Step Functions console
2. Find the state machine named `microservices-stepfn-{stack-name}-workflow`
3. Click "Start execution"
4. Use this test input:
   ```json
   {
     "userId": "12345",
     "orderData": {
       "items": [
         {"productId": "PROD001", "quantity": 2, "price": 29.99},
         {"productId": "PROD002", "quantity": 1, "price": 49.99}
       ]
     }
   }
   ```

### Testing via EventBridge

Send events to trigger the workflow automatically:

```bash
aws events put-events --entries Source=microservices.orders,DetailType="Order Submitted",Detail='{"userId":"67890","orderData":{"items":[{"productId":"PROD003","quantity":3,"price":15.99}]}}'
```

### Testing Individual Lambda Functions

```bash
# Test User Service
aws lambda invoke \
  --function-name microservices-stepfn-{stack-name}-user-service \
  --payload '{"userId": "test123"}' \
  response.json

# Test Order Service
aws lambda invoke \
  --function-name microservices-stepfn-{stack-name}-order-service \
  --payload '{"orderData":{"items":[{"productId":"PROD001","quantity":1,"price":99.99}]},"userData":{"userId":"test123"}}' \
  response.json
```

## Monitoring and Observability

### CloudWatch Logs

The application creates detailed logs in:
- `/aws/stepfunctions/microservices-stepfn-{stack-name}-workflow` - Step Functions execution logs
- `/aws/lambda/microservices-stepfn-{stack-name}-*` - Individual Lambda function logs

### Step Functions Console

Use the AWS Step Functions console to:
- Monitor workflow executions
- View execution history and status
- Debug failed executions
- Analyze performance metrics

### X-Ray Tracing

The state machine has X-Ray tracing enabled to provide detailed execution traces across the distributed system.

## Error Handling

The solution implements several error handling patterns:

1. **Retry Logic**: Payment and user services have automatic retry with exponential backoff
2. **Parallel Processing**: Order, payment, and inventory operations run in parallel for efficiency
3. **Error Propagation**: Failed services will cause the entire workflow to fail appropriately
4. **Logging**: Comprehensive logging for debugging and monitoring

## Customization

### Environment Variables

You can customize the deployment by setting context variables:

```bash
cdk deploy -c environment=prod -c projectName=my-microservices
```

### Lambda Function Code

To modify the Lambda function logic:

1. Edit the inline code in `lib/microservices-step-functions-stack.ts`
2. For complex functions, consider using external files with `lambda.Code.fromAsset()`
3. Redeploy with `npm run deploy`

### State Machine Definition

The workflow definition is constructed programmatically in the CDK code. To modify:

1. Edit the state machine construction in the `createStateMachine` method
2. Add new states, modify transitions, or update error handling
3. Redeploy to apply changes

## Cost Optimization

- Lambda functions use Python 3.9 runtime for optimal cold start performance
- Step Functions Standard Workflows are used for visibility and debugging
- Consider Express Workflows for high-volume, short-duration workloads
- CloudWatch logs have a 1-week retention period to control costs

## Security Best Practices

- IAM roles follow least privilege principle
- Lambda functions are isolated with minimal permissions
- Step Functions execution role has only necessary permissions
- No hardcoded credentials or sensitive data in code

## Cleanup

To remove all resources:

```bash
npm run destroy
```

This will delete all AWS resources created by this stack.

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Function Timeouts**: Check CloudWatch logs for Lambda execution errors
3. **State Machine Failures**: Use Step Functions console to trace execution flow
4. **EventBridge Not Triggering**: Verify event pattern matches your test events

### Debug Commands

```bash
# Check stack status
cdk list

# View synthesized CloudFormation
npm run synth

# Compare with deployed stack
npm run diff

# View stack outputs
aws cloudformation describe-stacks --stack-name MicroservicesStepFunctionsStack --query 'Stacks[0].Outputs'
```

## Additional Resources

- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)