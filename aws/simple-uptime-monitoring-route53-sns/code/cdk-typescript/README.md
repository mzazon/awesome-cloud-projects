# Simple Website Uptime Monitoring CDK TypeScript

This CDK TypeScript application deploys a complete website uptime monitoring solution using Route53 health checks, CloudWatch alarms, and SNS email notifications.

## Architecture

The application creates:

- **Route53 Health Check**: Monitor website availability from multiple global locations
- **SNS Topic**: Email notification system for alerts
- **CloudWatch Alarms**: Monitor health check status and trigger notifications
- **Email Subscription**: Automatic email alerts for downtime and recovery

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Valid email address for receiving alerts
- Website URL to monitor (must be publicly accessible)

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

Configure the monitoring target using one of these methods:

### Method 1: Environment Variables
```bash
export WEBSITE_URL="https://your-website.com"
export ADMIN_EMAIL="admin@your-domain.com"
```

### Method 2: CDK Context
```bash
cdk deploy -c websiteUrl=https://your-website.com -c adminEmail=admin@your-domain.com
```

### Method 3: cdk.json Context
Add to the `context` section in `cdk.json`:
```json
{
  "context": {
    "websiteUrl": "https://your-website.com",
    "adminEmail": "admin@your-domain.com",
    "environment": "Production"
  }
}
```

## Deployment

1. **Synthesize CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm email subscription**:
   - Check your email for an SNS subscription confirmation
   - Click the confirmation link to receive alerts

## Usage

After deployment, the system will:

- Monitor your website every 30 seconds from multiple AWS locations
- Trigger alerts after 3 consecutive failures (90 seconds)
- Send email notifications for both downtime and recovery
- Provide detailed metrics in CloudWatch

## Monitoring

### View Health Check Status
```bash
aws route53 get-health-check-status --health-check-id <HEALTH_CHECK_ID>
```

### View CloudWatch Metrics
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Route53 \
  --metric-name HealthCheckStatus \
  --dimensions Name=HealthCheckId,Value=<HEALTH_CHECK_ID> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Minimum,Maximum
```

## Customization

### Health Check Settings

Modify the health check configuration in `lib/uptime-monitoring-stack.ts`:

```typescript
this.healthCheck = new route53.HealthCheck(this, 'WebsiteHealthCheck', {
  type: route53.HealthCheckType.HTTPS,
  fqdn: domain,
  port: 443,
  resourcePath: '/',
  requestInterval: cdk.Duration.seconds(30), // Check every 30 seconds
  failureThreshold: 3, // Fail after 3 consecutive failures
  enableSni: true,
});
```

### Alarm Thresholds

Adjust alarm sensitivity in the CloudWatch alarm configuration:

```typescript
this.alarmDown = new cloudwatch.Alarm(this, 'WebsiteDownAlarm', {
  // ... other properties
  evaluationPeriods: 1, // Number of periods to evaluate
  threshold: 1, // Threshold value
});
```

### Additional Notification Channels

Add SMS notifications:

```typescript
this.snsTopic.addSubscription(
  new snsSubscriptions.SmsSubscription('+1234567890')
);
```

Add Slack webhook:

```typescript
this.snsTopic.addSubscription(
  new snsSubscriptions.UrlSubscription('https://hooks.slack.com/...')
);
```

## Cost Optimization

The solution uses serverless, pay-per-use services:

- **Route53 Health Check**: ~$0.50/month per health check
- **CloudWatch Alarms**: $0.10/month per alarm (2 alarms = $0.20)
- **SNS Notifications**: $0.50 per 1M email notifications
- **Total estimated cost**: ~$0.70-$2.00/month depending on usage

## Troubleshooting

### Common Issues

1. **Email not received**:
   - Check spam folder
   - Verify email address is correct
   - Confirm SNS subscription in AWS Console

2. **False positive alerts**:
   - Increase `failureThreshold` in health check config
   - Check website SSL certificate validity
   - Verify website is accessible from AWS IP ranges

3. **Health check failing**:
   - Verify website URL is publicly accessible
   - Check firewall and security group settings
   - Ensure SSL certificate is valid for HTTPS sites

### Debug Commands

```bash
# Check stack status
cdk list

# View stack outputs
aws cloudformation describe-stacks --stack-name UptimeMonitoringStack

# Check SNS subscriptions
aws sns list-subscriptions

# View alarm history
aws cloudwatch describe-alarm-history --alarm-name Website-Down-*
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete:
- Route53 health check
- CloudWatch alarms
- SNS topic and subscriptions
- All associated resources

## Security Considerations

- SNS topic enforces SSL/TLS encryption
- Health checks use AWS's secure, managed infrastructure
- No sensitive data is stored or transmitted
- Follows AWS security best practices

## Extending the Solution

Consider these enhancements:

1. **Multi-region monitoring**: Deploy health checks from multiple regions
2. **Custom metrics**: Add response time and availability percentage metrics
3. **Dashboard**: Create CloudWatch dashboard for visualization
4. **Automated response**: Integrate with Lambda for automated remediation
5. **Integration**: Connect with ticketing systems or chat platforms

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [Route53 health check documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-types.html)
3. Consult [CloudWatch alarms guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)

## License

This sample code is licensed under the MIT License.