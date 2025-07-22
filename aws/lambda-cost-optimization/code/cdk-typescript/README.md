# Lambda Cost Optimizer - CDK TypeScript Implementation

This CDK TypeScript application implements the AWS Lambda Cost Optimization solution using AWS Compute Optimizer. It provides infrastructure for analyzing Lambda function performance, retrieving optimization recommendations, and optionally applying them automatically.

## Architecture

The CDK application deploys:

- **Optimizer Lambda Function**: Analyzes Compute Optimizer recommendations and optionally applies optimizations
- **Test Lambda Functions**: Sample functions with different memory configurations for testing optimization
- **SNS Topic**: Notifications for optimization results and alerts
- **CloudWatch Monitoring**: Alarms and dashboard for tracking optimization impact
- **EventBridge Rule**: Scheduled execution of optimization analysis
- **IAM Roles**: Appropriate permissions for Compute Optimizer and Lambda management

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- AWS account with appropriate permissions for:
  - Lambda functions
  - IAM roles and policies
  - Compute Optimizer
  - CloudWatch metrics and alarms
  - SNS topics
  - EventBridge rules

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if first time)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default configuration
cdk deploy

# Deploy with custom configuration
cdk deploy --context environment=prod --context notificationEmail=your-email@example.com
```

### 4. Enable Compute Optimizer

After deployment, enable Compute Optimizer in your AWS account:

```bash
aws compute-optimizer put-enrollment-status --status Active
```

## Configuration Options

You can customize the deployment using CDK context parameters:

```bash
# Deploy with custom settings
cdk deploy \
  --context environment=production \
  --context notificationEmail=alerts@company.com \
  --context savingsThreshold=2.0 \
  --context enableAutoOptimization=true
```

### Available Context Parameters

- `environment`: Environment name (default: "dev")
- `notificationEmail`: Email address for SNS notifications
- `savingsThreshold`: Minimum monthly savings threshold for optimization (default: 1.0)
- `enableAutoOptimization`: Whether to automatically apply optimizations (default: false)

## Usage

### Manual Optimization Analysis

Invoke the optimizer function manually:

```bash
# Get the function name from stack outputs
OPTIMIZER_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name lambda-cost-optimizer-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`OptimizerFunctionName`].OutputValue' \
  --output text)

# Run optimization analysis
aws lambda invoke \
  --function-name $OPTIMIZER_FUNCTION \
  --payload '{}' \
  response.json

cat response.json
```

### Test Function Invocations

Generate metrics for the test functions to enable optimization analysis:

```bash
# Get test function names
TEST_FUNCTIONS=(
  "high-memory-test-function"
  "low-memory-test-function"
  "medium-memory-test-function"
)

# Invoke test functions with different workload types
for function in "${TEST_FUNCTIONS[@]}"; do
  echo "Testing $function..."
  
  # CPU-bound workload
  aws lambda invoke \
    --function-name $function \
    --payload '{"workload_type": "cpu_bound"}' \
    /tmp/response_cpu.json
  
  # Memory-bound workload
  aws lambda invoke \
    --function-name $function \
    --payload '{"workload_type": "memory_bound"}' \
    /tmp/response_memory.json
  
  # Lightweight workload
  aws lambda invoke \
    --function-name $function \
    --payload '{"workload_type": "lightweight"}' \
    /tmp/response_light.json
  
  sleep 1
done
```

### Scheduled Optimization

The EventBridge rule automatically runs optimization analysis every Monday at 9 AM UTC. You can modify the schedule by updating the CDK code:

```typescript
schedule: events.Schedule.cron({
  minute: '0',
  hour: '9',
  weekDay: 'MON'  // Modify as needed
})
```

### Monitoring

#### CloudWatch Dashboard

Access the cost optimization dashboard in the AWS Console:
- Navigate to CloudWatch > Dashboards
- Open "lambda-cost-optimization-dashboard"

#### CloudWatch Alarms

The stack creates alarms for:
- Lambda error rate increases
- Lambda duration increases

These alarms send notifications to the SNS topic when triggered.

#### CloudWatch Logs

Monitor optimizer function execution:

```bash
# Get log group name
LOG_GROUP="/aws/lambda/lambda-cost-optimizer"

# View recent logs
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Customization

### Modifying Savings Threshold

Update the savings threshold for automatic optimization:

```typescript
// In lib/lambda-cost-optimizer-stack.ts
const savingsThreshold = props?.savingsThreshold ?? 5.0; // Changed from 1.0 to 5.0
```

### Adding Custom Test Functions

Create additional test functions with different characteristics:

```typescript
// Add to testConfigs array in createTestFunctions()
{
  name: 'custom-test-function',
  memorySize: 256,
  description: 'Custom test function with specific memory allocation'
}
```

### Modifying Notification Schedule

Change the optimization analysis schedule:

```typescript
// Modify the schedule in the constructor
schedule: events.Schedule.rate(cdk.Duration.days(7)) // Weekly
// or
schedule: events.Schedule.cron({
  minute: '0',
  hour: '8',
  weekDay: 'FRI'  // Every Friday at 8 AM
})
```

## Cost Considerations

This solution creates several AWS resources that may incur costs:

- **Lambda Functions**: Pay per invocation and execution time
- **CloudWatch**: Log storage and custom metrics
- **SNS**: Notifications (minimal cost)
- **EventBridge**: Rule evaluations (minimal cost)

Estimated monthly cost for development/testing: $5-15 USD

## Security Best Practices

The CDK implementation follows security best practices:

- **Least Privilege IAM**: Roles have minimum required permissions
- **Resource-Level Permissions**: Lambda functions can only modify specific resources
- **Encryption**: CloudWatch logs are encrypted by default
- **Network Security**: No public endpoints created

## Troubleshooting

### Common Issues

1. **Compute Optimizer Not Enabled**
   ```bash
   aws compute-optimizer get-enrollment-status
   # Should return "Active"
   ```

2. **Insufficient Permissions**
   ```bash
   # Check IAM role permissions
   aws iam get-role --role-name lambda-cost-optimizer-role
   ```

3. **No Recommendations Available**
   - Wait at least 14 days after enabling Compute Optimizer
   - Ensure Lambda functions have sufficient invocation history (50+ invocations)

4. **CloudWatch Alarms Triggering**
   - Check optimization results in function logs
   - Verify performance impact of memory changes
   - Consider reverting optimizations if performance degrades

### Debug Mode

Enable debug logging by updating the Lambda function environment:

```bash
aws lambda update-function-configuration \
  --function-name lambda-cost-optimizer \
  --environment Variables='{
    "LOG_LEVEL": "DEBUG",
    "SNS_TOPIC_ARN": "arn:aws:sns:region:account:topic",
    "SAVINGS_THRESHOLD": "1.0",
    "AUTO_OPTIMIZATION_ENABLED": "false"
  }'
```

## Cleanup

Remove all resources created by this stack:

```bash
cdk destroy
```

This will delete:
- All Lambda functions
- SNS topic and subscriptions
- CloudWatch alarms and dashboard
- EventBridge rule
- IAM roles and policies
- CloudWatch log groups

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues with this implementation:
- Check CloudWatch logs for detailed error messages
- Review AWS Compute Optimizer documentation
- Consult the original recipe documentation

## Related AWS Documentation

- [AWS Compute Optimizer User Guide](https://docs.aws.amazon.com/compute-optimizer/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)