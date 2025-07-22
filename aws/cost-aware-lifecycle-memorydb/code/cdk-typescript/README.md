# Cost-Aware Resource Lifecycle CDK TypeScript Application

This CDK application deploys a cost-aware resource lifecycle management solution using EventBridge Scheduler and MemoryDB for Redis. The solution automatically manages MemoryDB cluster scaling based on usage patterns, cost thresholds, and business hours to achieve 30-50% cost savings.

## Architecture Overview

The application creates the following AWS resources:

- **MemoryDB Cluster**: Redis-compatible in-memory database with microsecond latency
- **Lambda Function**: Intelligent cost optimization engine with Cost Explorer API integration
- **EventBridge Scheduler**: Reliable scheduling for business hours automation
- **CloudWatch Dashboard**: Comprehensive monitoring and cost tracking
- **AWS Budgets**: Proactive cost monitoring and alerts
- **IAM Roles**: Least-privilege security for all components

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK v2.100.0+ installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating MemoryDB, Lambda, EventBridge, and monitoring resources

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Context (Optional)

You can customize the deployment by setting context values in `cdk.json` or via command line:

```bash
# Set custom cluster name and cost threshold
cdk deploy -c clusterName=my-redis-cluster -c costThreshold=150
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (recommended first)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with confirmation skip
cdk deploy --require-approval never
```

### 4. Verify Deployment

After deployment, check the outputs for important resource information:

- MemoryDB cluster endpoint
- Lambda function name and ARN
- CloudWatch dashboard URL

## Configuration Options

### Context Parameters

You can configure the following parameters via CDK context:

```json
{
  "clusterName": "cost-aware-memorydb",
  "costThreshold": 100,
  "environment": "development",
  "costCenter": "devops",
  "stackName": "CostAwareResourceLifecycleStack",
  "enableCdkNag": "true"
}
```

### Environment Variables

The Lambda function uses the following environment variables:

- `LOG_LEVEL`: Logging level (default: INFO)

## Scheduled Operations

The solution includes three automated schedules:

1. **Business Hours Start** (8 AM weekdays): Scale up for performance
2. **Business Hours End** (6 PM weekdays): Scale down for cost savings
3. **Weekly Analysis** (9 AM Mondays): Comprehensive cost review

## Cost Optimization Features

### Intelligent Scaling

- **Vertical Scaling**: Automatically adjusts node types based on business hours
- **Cost Analysis**: Uses Cost Explorer API for data-driven decisions
- **Performance Monitoring**: Maintains service quality during optimizations

### Monitoring and Alerting

- **Cost Metrics**: Custom CloudWatch metrics for cost tracking
- **Performance Metrics**: MemoryDB CPU, network, and throughput monitoring
- **Budget Alerts**: Proactive notifications at 80% and 90% thresholds

## Security Best Practices

This application implements AWS security best practices:

- **Least Privilege IAM**: Minimal required permissions for each role
- **VPC Security Groups**: Restricted network access for MemoryDB
- **CloudTrail Integration**: All API calls are logged for auditing
- **Encryption**: MemoryDB encryption at rest and in transit
- **CDK Nag**: Security validation during synthesis

## Testing the Solution

### Manual Testing

```bash
# Invoke the cost optimizer Lambda function directly
aws lambda invoke \
    --function-name <function-name> \
    --payload '{"cluster_name":"<cluster-name>","action":"analyze","cost_threshold":100}' \
    response.json

cat response.json
```

### Viewing Monitoring Data

1. Open the CloudWatch dashboard URL from the deployment outputs
2. Monitor cost optimization metrics and MemoryDB performance
3. Check EventBridge Scheduler execution history
4. Review AWS Budgets for cost tracking

## Customization

### Modifying Schedules

To change the automation schedule, modify the cron expressions in `cost-aware-resource-lifecycle-stack.ts`:

```typescript
scheduleExpression: 'cron(0 8 ? * MON-FRI *)', // 8 AM weekdays
```

### Adding Custom Metrics

Extend the Lambda function to send additional metrics:

```python
cloudwatch.put_metric_data(
    Namespace='MemoryDB/CostOptimization',
    MetricData=[
        {
            'MetricName': 'CustomMetric',
            'Value': value,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'ClusterName', 'Value': cluster_name}
            ]
        }
    ]
)
```

### Scaling Policies

Modify the scaling logic in the Lambda function to implement custom policies:

```python
def analyze_scaling_needs(cost: float, threshold: float, node_type: str, action: str):
    # Custom scaling logic here
    pass
```

## Cleanup

To avoid ongoing costs, destroy the stack when no longer needed:

```bash
cdk destroy
```

This will remove all created resources including:
- MemoryDB cluster
- Lambda function
- EventBridge schedules
- CloudWatch dashboard and alarms
- AWS Budget
- IAM roles and policies

## Troubleshooting

### Common Issues

1. **MemoryDB Cluster Creation Fails**
   - Check VPC and subnet configuration
   - Verify security group settings
   - Ensure sufficient IP addresses in subnets

2. **Lambda Function Errors**
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM permissions for Cost Explorer API
   - Ensure MemoryDB cluster exists and is available

3. **EventBridge Scheduler Not Triggering**
   - Verify IAM permissions for Lambda invocation
   - Check schedule expressions are valid
   - Ensure schedules are in ENABLED state

### Debugging

Enable detailed logging by setting the Lambda function's LOG_LEVEL to DEBUG:

```bash
aws lambda update-function-configuration \
    --function-name <function-name> \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

## Cost Considerations

This solution is designed for cost optimization, with estimated monthly costs:

- **MemoryDB**: $20-80/month (depending on node type and scaling)
- **Lambda**: $5-15/month (based on executions)
- **EventBridge Scheduler**: $1-5/month
- **CloudWatch**: $5-10/month (metrics and dashboard)
- **Other Services**: <$5/month

Total estimated cost: $30-115/month, with potential savings of 30-50% on MemoryDB costs.

## Support and Contributing

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review CloudWatch Logs for detailed error information
3. Consult the original recipe documentation
4. Refer to AWS CDK and service-specific documentation

## License

This CDK application is provided under the MIT license.