# Database Performance Monitoring with RDS Performance Insights - CDK TypeScript

This CDK TypeScript application deploys a comprehensive database performance monitoring solution using RDS Performance Insights, CloudWatch monitoring, and automated analysis capabilities.

## Architecture Overview

The solution creates:

- **RDS MySQL Instance** with Performance Insights enabled
- **Lambda Function** for automated performance analysis
- **CloudWatch Dashboard** for performance visualization
- **CloudWatch Alarms** for proactive monitoring
- **SNS Topic** for alert notifications
- **S3 Bucket** for storing performance reports
- **EventBridge Rule** for automated analysis scheduling
- **IAM Roles** with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 16.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)
- Appropriate AWS permissions for creating RDS, Lambda, CloudWatch, and IAM resources

## Quick Start

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Configure Environment** (optional):
   ```bash
   # Set your preferred AWS region
   export CDK_DEFAULT_REGION=us-east-1
   export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   ```

3. **Build the Application**:
   ```bash
   npm run build
   ```

4. **Deploy the Stack**:
   ```bash
   cdk deploy
   ```

   Or with custom configuration:
   ```bash
   cdk deploy \
     --context notificationEmail=your-email@example.com \
     --context environment=production \
     --context dbInstanceClass=db.t3.medium
   ```

## Configuration Options

You can customize the deployment using CDK context parameters:

### Database Configuration
```bash
cdk deploy \
  --context dbInstanceClass=db.t3.medium \
  --context dbEngine=mysql \
  --context dbEngineVersion=8.0.35 \
  --context allocatedStorage=100
```

### Performance Insights Configuration
```bash
cdk deploy \
  --context performanceInsightsRetentionPeriod=7 \
  --context monitoringInterval=60
```

### Lambda Configuration
```bash
cdk deploy \
  --context lambdaMemorySize=1024 \
  --context lambdaTimeout=600
```

### Monitoring Configuration
```bash
cdk deploy \
  --context analysisSchedule="rate(15 minutes)" \
  --context createDashboard=true \
  --context enableAnomalyDetection=true
```

### Notification Configuration
```bash
cdk deploy \
  --context notificationEmail=admin@example.com
```

### Security Configuration
```bash
cdk deploy \
  --context enableCloudWatchLogs=true \
  --context enableEncryption=true
```

## Available Commands

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for file changes and recompile
- `npm run test` - Run unit tests
- `cdk deploy` - Deploy the stack
- `cdk diff` - Compare deployed stack with current state
- `cdk synth` - Synthesize CloudFormation template
- `cdk destroy` - Delete the stack

## Stack Outputs

After deployment, the stack provides these outputs:

- **DatabaseEndpoint** - RDS database endpoint
- **DatabaseResourceId** - Performance Insights resource ID
- **ReportsBucketName** - S3 bucket for performance reports
- **SNSTopicArn** - SNS topic for alerts
- **LambdaFunctionName** - Performance analysis function name
- **PerformanceInsightsUrl** - Direct link to Performance Insights dashboard

## Features

### Automated Performance Analysis
- **Lambda Function** analyzes Performance Insights data every 15 minutes
- **Intelligent Detection** of high-load events and problematic queries
- **Custom Metrics** published to CloudWatch for advanced monitoring
- **Automated Reports** stored in S3 with timestamp-based organization

### Comprehensive Monitoring
- **CloudWatch Dashboard** with real-time performance visualization
- **CloudWatch Alarms** for proactive issue detection
- **Anomaly Detection** using machine learning for baseline establishment
- **Performance Insights** integration for database-specific metrics

### Alert Management
- **SNS Integration** for multi-channel notifications
- **Email Alerts** for critical performance issues
- **Intelligent Filtering** to reduce alert noise
- **Detailed Context** in alert messages for faster resolution

### Security Features
- **VPC Isolation** for database security
- **IAM Roles** with least privilege access
- **Encryption** for data at rest and in transit
- **CloudWatch Logs** for audit trails

## Performance Insights Features

The solution leverages AWS Performance Insights to provide:

- **Database Load Monitoring** - Track database load over time
- **Wait Event Analysis** - Identify performance bottlenecks
- **SQL Statement Analysis** - Find problematic queries
- **Dimension Breakdowns** - Analyze performance by multiple dimensions
- **Historical Trending** - Compare performance over time

## Monitoring Capabilities

### CloudWatch Metrics
- Database connections
- CPU utilization
- Read/write latency
- IOPS performance
- Custom Performance Insights metrics

### CloudWatch Alarms
- High database connections (threshold: 80)
- High CPU utilization (threshold: 75%)
- High load events (threshold: 5)
- Problematic queries (threshold: 3)

### CloudWatch Dashboard
- Real-time performance visualization
- Historical trend analysis
- Slow query log integration
- Custom metrics display

## Cost Optimization

The solution includes several cost optimization features:

- **S3 Lifecycle Rules** - Automatic deletion of old reports
- **Performance Insights** - Free tier (7 days retention)
- **Lambda Optimization** - Efficient resource allocation
- **CloudWatch Logs** - Configurable retention periods

## Customization

### Extending the Lambda Function
The analysis Lambda function can be extended with:
- Additional Performance Insights metrics
- Machine learning-based anomaly detection
- Integration with external monitoring systems
- Custom alerting logic

### Adding Custom Metrics
```typescript
// Add custom CloudWatch metrics
const customMetric = new cloudwatch.Metric({
  namespace: 'RDS/PerformanceInsights',
  metricName: 'CustomMetric',
  dimensionsMap: {
    DBInstanceIdentifier: database.instanceIdentifier,
  },
});
```

### Modifying Alarms
```typescript
// Customize alarm thresholds
const customAlarm = new cloudwatch.Alarm(this, 'CustomAlarm', {
  metric: customMetric,
  threshold: 100,
  evaluationPeriods: 3,
  // ... other properties
});
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeout**
   - Increase `lambdaTimeout` context parameter
   - Check VPC configuration for subnet routing

2. **Performance Insights Access**
   - Verify IAM permissions for Performance Insights API
   - Check resource ID mapping

3. **CloudWatch Logs**
   - Ensure log groups exist before dashboard creation
   - Verify log stream permissions

4. **Database Connection Issues**
   - Check security group rules
   - Verify VPC subnet configuration
   - Confirm database endpoint accessibility

### Debug Commands

```bash
# View CloudFormation events
aws cloudformation describe-stack-events --stack-name YourStackName

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/YourFunctionName"

# Test Lambda function manually
aws lambda invoke --function-name YourFunctionName --payload '{}' response.json
```

## Security Considerations

- **Database Access** - Restricted to VPC-internal resources
- **IAM Permissions** - Least privilege principle applied
- **Encryption** - Data encrypted at rest and in transit
- **Network Security** - Security groups restrict access
- **Audit Logging** - CloudTrail integration for API calls

## Migration to CloudWatch Database Insights

This solution is designed to be compatible with the upcoming CloudWatch Database Insights migration. The architecture supports:

- **API Compatibility** - Uses Performance Insights APIs that will be maintained
- **Metric Continuity** - Custom metrics will continue to work
- **Dashboard Migration** - Easy transition to Database Insights dashboards
- **Enhanced Features** - Ready for advanced Database Insights capabilities

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review the [RDS Performance Insights documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
3. Consult the [CloudWatch documentation](https://docs.aws.amazon.com/cloudwatch/)
4. Use AWS Support for production issues

## Contributing

To contribute to this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This CDK application is licensed under the Apache License 2.0. See the LICENSE file for details.