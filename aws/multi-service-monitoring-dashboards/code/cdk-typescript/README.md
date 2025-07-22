# Advanced Multi-Service Monitoring Dashboards CDK Application

This CDK TypeScript application creates a comprehensive monitoring solution with custom metrics collection, anomaly detection, and intelligent dashboards across multiple AWS services.

## Architecture Overview

This solution implements:

- **Custom Metrics Collection**: Lambda functions collecting business metrics, infrastructure health, and cost data
- **Anomaly Detection**: Machine learning-based anomaly detection for key metrics
- **Intelligent Alerting**: Tiered SNS topics for different alert severities
- **Multi-Dashboard System**: Role-specific dashboards for different audiences
- **Automated Scheduling**: EventBridge rules for scheduled metric collection

## Features

### Lambda Functions
- **Business Metrics Function**: Collects revenue, user engagement, and performance metrics
- **Infrastructure Health Function**: Monitors RDS, ElastiCache, and EC2 health
- **Cost Monitoring Function**: Tracks AWS costs and spending trends

### CloudWatch Dashboards
- **Infrastructure Dashboard**: Technical service health and performance metrics
- **Business Dashboard**: Revenue, transactions, and customer metrics
- **Executive Dashboard**: High-level business and system health overview
- **Operations Dashboard**: Cost monitoring and operational metrics

### Anomaly Detection
- Revenue anomaly detection with machine learning
- API response time anomaly detection
- Error rate anomaly detection  
- Infrastructure health anomaly detection

### Intelligent Alerting
- Critical alerts for immediate attention
- Warning alerts for operations team
- Info alerts for notifications
- Anomaly-based alarms with adaptive thresholds

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18.x or later
- AWS CDK CLI v2.x installed globally
- TypeScript compiler

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if not already done):
   ```bash
   npm run bootstrap
   ```

3. **Build the application**:
   ```bash
   npm run build
   ```

## Configuration

The application accepts configuration through CDK context parameters. You can set these via:

- Command line: `cdk deploy -c alertEmail=your-email@example.com`
- cdk.json context section
- Environment variables

### Available Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `alertEmail` | `your-email@example.com` | Email address for critical alerts |
| `environment` | `production` | Environment name for resource tagging |
| `projectName` | `advanced-monitoring` | Project name prefix for resources |
| `enableCostMonitoring` | `true` | Enable cost monitoring Lambda function |
| `anomalyDetectionSensitivity` | `2` | Anomaly detection sensitivity (1-5) |

## Deployment

### Quick Deploy
```bash
npm run deploy
```

### Deploy with Custom Configuration
```bash
cdk deploy \
  -c alertEmail=ops@yourcompany.com \
  -c environment=staging \
  -c projectName=monitoring-system \
  -c anomalyDetectionSensitivity=3
```

### Deploy to Specific Region
```bash
export CDK_DEFAULT_REGION=us-west-2
npm run deploy
```

## Usage

After deployment, the application will output URLs for all dashboards:

1. **Infrastructure Dashboard**: Monitor service health and performance
2. **Business Dashboard**: Track revenue and customer metrics  
3. **Executive Dashboard**: High-level business and system health
4. **Operations Dashboard**: Cost trends and operational metrics

### Accessing Dashboards

Dashboard URLs are provided in the CloudFormation outputs:
- `InfrastructureDashboardUrl`
- `BusinessDashboardUrl`
- `ExecutiveDashboardUrl`
- `OperationsDashboardUrl`

### Monitoring Custom Metrics

The application creates several custom metric namespaces:

- **Business/Metrics**: Revenue, transactions, user engagement
- **Business/Health**: Composite health scores
- **Infrastructure/Health**: Service-specific health scores
- **Cost/Management**: Cost tracking and trends

### Alert Management

Critical alerts are automatically sent to the configured email address. You can:

1. **Add more subscribers**: Modify the SNS topic subscriptions
2. **Configure alert routing**: Use SNS message filtering
3. **Integrate with external systems**: Add webhook endpoints or PagerDuty

## Customization

### Adding New Metrics

1. **Modify Lambda Functions**: Update the Python code in the Lambda function definitions
2. **Add New Dashboards**: Create additional dashboard methods in the stack
3. **Configure Anomaly Detection**: Add new anomaly detectors for custom metrics

### Extending Alerting

1. **Add New SNS Topics**: Create topic for different alert types
2. **Configure Alarm Actions**: Link alarms to appropriate SNS topics
3. **Implement Alert Routing**: Use SNS message attributes for routing

### Custom Business Logic

Replace the simulated metrics in the Lambda functions with your actual business logic:

```python
# Replace simulation with real data collection
hourly_revenue = get_actual_revenue_data()
transaction_count = get_actual_transaction_count()
active_users = get_actual_active_users()
```

## Cost Optimization

### Monitoring Costs

- Custom metrics: $0.30 per metric per month
- Lambda invocations: Included in free tier for normal usage
- CloudWatch dashboards: $3 per dashboard per month
- SNS notifications: $0.50 per 1M notifications

### Cost Optimization Tips

1. **Reduce metric frequency**: Adjust EventBridge schedules for less critical metrics
2. **Use metric filters**: Filter high-volume metrics to reduce costs
3. **Optimize Lambda runtime**: Reduce function execution time
4. **Cleanup unused resources**: Remove unnecessary alarms and dashboards

## Development

### Build Commands

```bash
# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm run test

# Generate CloudFormation template
npm run synth

# Show differences
npm run diff
```

### Testing

```bash
# Run unit tests
npm test

# Run with coverage
npm run test:coverage
```

## Monitoring Best Practices

1. **Establish Baselines**: Allow anomaly detection to learn normal patterns
2. **Regular Review**: Review and adjust alert thresholds periodically
3. **Documentation**: Document custom metrics and their business meaning
4. **Access Control**: Use IAM to control dashboard and metric access
5. **Backup Configuration**: Version control your monitoring configuration

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**: Check CloudWatch Logs for detailed error messages
2. **Missing Metrics**: Verify Lambda function execution and permissions
3. **Alarm State Issues**: Check metric availability and alarm configuration
4. **Dashboard Not Loading**: Verify metric names and dimensions

### Debugging

```bash
# Check deployment status
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name <stack-name>

# Check Lambda function logs
aws logs tail /aws/lambda/<function-name> --follow
```

## Security

### IAM Permissions

The application creates IAM roles with least privilege access:

- **Lambda Execution Role**: CloudWatch metrics, RDS read-only, ElastiCache read-only, Cost Explorer
- **EventBridge**: Lambda function invocation permissions
- **SNS**: Topic publishing permissions

### Security Best Practices

1. **Use IAM roles**: Avoid hard-coded credentials
2. **Encrypt at rest**: Enable encryption for sensitive data
3. **Network isolation**: Use VPC endpoints where appropriate
4. **Audit access**: Monitor CloudTrail for access patterns

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Or using CDK directly:
```bash
cdk destroy --force
```

## Support

For issues and questions:

1. **Check the logs**: CloudWatch Logs provide detailed error information
2. **Review the documentation**: AWS service documentation for specific issues
3. **Community support**: AWS CDK GitHub repository and forums

## Contributing

When contributing improvements:

1. **Follow TypeScript best practices**
2. **Add appropriate error handling**
3. **Include proper type definitions**
4. **Update documentation**
5. **Test thoroughly**

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.