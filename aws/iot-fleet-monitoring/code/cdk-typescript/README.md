# IoT Device Fleet Monitoring with CloudWatch and Device Defender - CDK TypeScript

This CDK TypeScript application deploys a comprehensive IoT device fleet monitoring solution using AWS IoT Device Defender for security monitoring and CloudWatch for operational metrics and automated alerting.

## Architecture Overview

The solution creates:

- **IoT Core Resources**: Thing Groups, Security Profiles, and Topic Rules
- **Security Monitoring**: AWS IoT Device Defender with behavioral analysis
- **Automated Response**: Lambda functions for security remediation
- **Monitoring & Alerting**: CloudWatch dashboards, alarms, and custom metrics
- **Messaging**: SNS topics for alerts and SQS queues for message processing
- **Storage**: S3 bucket for IoT data and DynamoDB table for device metadata
- **Logging**: CloudWatch Log Groups for audit trails

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)
- Appropriate AWS permissions for IoT Core, Device Defender, CloudWatch, Lambda, and related services

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (if not already done)**:
   ```bash
   npm run bootstrap
   ```

## Configuration

The stack accepts the following parameters:

- `EmailEndpoint`: Email address for security alerts (default: admin@example.com)
- `DeviceCount`: Number of test devices to create (default: 5, range: 1-20)
- `SecurityViolationThreshold`: Threshold for security violation alarms (default: 5, range: 1-50)

## Deployment

### Quick Deployment

Deploy with default parameters:
```bash
npm run deploy
```

### Custom Parameters

Deploy with custom parameters:
```bash
cdk deploy --parameters EmailEndpoint=security@yourcompany.com --parameters DeviceCount=10 --parameters SecurityViolationThreshold=3
```

### Deployment Verification

After deployment, the stack outputs will include:
- Fleet Name
- Security Profile Name
- Dashboard URL
- SNS Topic ARN
- Lambda Function ARN
- IoT Console URL

## Usage

### Monitoring Dashboard

Access the CloudWatch dashboard using the URL provided in the stack outputs. The dashboard displays:

- **IoT Fleet Overview**: Device connectivity and message statistics
- **Security Violations**: Real-time security alerts and cleared alarms
- **Message Processing**: Success/error rates for IoT rules
- **Security Violation Logs**: Recent security events from Lambda function

### Security Monitoring

The solution monitors five critical behavioral patterns:

1. **Authorization Failures**: Detects repeated authentication failures
2. **Message Byte Size**: Identifies unusually large messages
3. **Messages Received/Sent**: Monitors message volume anomalies
4. **Connection Attempts**: Tracks excessive connection attempts

### Automated Remediation

The Lambda function automatically:
- Logs security violations to DynamoDB
- Sends custom metrics to CloudWatch
- Queues alerts for further processing
- Implements configurable remediation actions

### Testing Security Profiles

Test the security monitoring by:

1. **Viewing Device Defender Console**:
   ```bash
   aws iot list-security-profiles
   aws iot describe-security-profile --security-profile-name <SECURITY_PROFILE_NAME>
   ```

2. **Triggering Test Alarms**:
   ```bash
   aws cloudwatch put-metric-data \
     --namespace "AWS/IoT/FleetMonitoring" \
     --metric-data MetricName=SecurityViolations,Value=10,Unit=Count
   ```

3. **Checking Lambda Logs**:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/iot-fleet-remediation"
   ```

## Customization

### Security Behaviors

Modify security thresholds in `app.ts`:
```typescript
behaviors: [
  {
    name: 'AuthorizationFailures',
    metric: 'aws:num-authorization-failures',
    criteria: {
      comparisonOperator: 'greater-than',
      value: { count: 5 }, // Adjust threshold
      durationSeconds: 300,
      consecutiveDatapointsToAlarm: 2,
      consecutiveDatapointsToClear: 2
    }
  }
  // Add more behaviors as needed
]
```

### Lambda Remediation Logic

Enhance the Lambda function in `app.ts` to implement custom remediation actions:
```typescript
if (behavior_name == 'AuthorizationFailures') {
  // Implement certificate revocation
  // Quarantine device
  // Send escalation alerts
}
```

### CloudWatch Alarms

Add custom alarms for specific metrics:
```typescript
const customAlarm = new cloudwatch.Alarm(this, 'CustomAlarm', {
  alarmName: 'Custom-IoT-Metric-Alarm',
  metric: new cloudwatch.Metric({
    namespace: 'AWS/IoT/FleetMonitoring',
    metricName: 'CustomMetric',
    statistic: 'Sum'
  }),
  threshold: 10,
  evaluationPeriods: 2
});
```

## Security Best Practices

The solution implements several security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Encryption**: S3 bucket and DynamoDB table use encryption at rest
- **Network Security**: All resources use secure communication protocols
- **Monitoring**: Comprehensive logging and alerting for security events
- **Compliance**: Automated audit trails and compliance reporting

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure the deployment role has appropriate permissions
2. **Resource Limits**: Check AWS service limits for IoT Core and Lambda
3. **Email Subscription**: Confirm email subscription to SNS topic
4. **Lambda Timeouts**: Increase timeout if processing large volumes

### Debug Commands

```bash
# View stack events
cdk events IoTDeviceFleetMonitoringStack

# Check CloudFormation template
npm run synth

# View differences before deployment
npm run diff

# Enable verbose logging
cdk deploy --debug
```

### Log Analysis

Monitor Lambda function logs:
```bash
aws logs tail /aws/lambda/iot-fleet-remediation-XXXXXX --follow
```

Check IoT device logs:
```bash
aws logs tail /aws/iot/fleet-monitoring --follow
```

## Cleanup

To remove all resources:
```bash
npm run destroy
```

**Warning**: This will delete all resources including stored data in S3 and DynamoDB.

## Cost Optimization

- **Lambda**: Pay-per-execution model scales with security events
- **IoT Core**: Charges based on message volume and device connections
- **CloudWatch**: Optimize retention periods and alarm configurations
- **S3**: Implement lifecycle policies for data archival
- **DynamoDB**: Use on-demand billing for variable workloads

## Support

For issues and questions:
- Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- Review AWS IoT Device Defender documentation: https://docs.aws.amazon.com/iot-device-defender/
- Submit issues to the repository

## License

This project is licensed under the MIT License. See the LICENSE file for details.