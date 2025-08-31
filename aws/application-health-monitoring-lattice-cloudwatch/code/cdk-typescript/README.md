# Application Health Monitoring with VPC Lattice and CloudWatch - CDK TypeScript

This CDK TypeScript application implements a comprehensive application health monitoring system using AWS VPC Lattice service metrics, CloudWatch alarms, and Lambda functions to detect unhealthy services and trigger auto-remediation workflows.

## Architecture

The solution creates:

- **VPC Lattice Service Network**: Logical boundary for service-to-service communication with centralized monitoring
- **VPC Lattice Service**: Entry point for client requests with automatic CloudWatch metrics generation
- **Target Group**: Backend service definitions with aggressive health check configuration
- **CloudWatch Alarms**: Monitor HTTP error rates, request timeouts, and response times
- **Lambda Function**: Auto-remediation logic for different health issue types
- **SNS Topic**: Centralized notification system for operations teams
- **CloudWatch Dashboard**: Real-time visibility into service health metrics and alarm states

## Prerequisites

1. **AWS Account**: With permissions for VPC Lattice, CloudWatch, Lambda, SNS, and IAM
2. **AWS CLI**: Version 2.x installed and configured
3. **Node.js**: Version 18.x or later
4. **AWS CDK**: Version 2.170.0 or later
5. **TypeScript**: Version 5.7.x or later
6. **Existing VPC**: With at least two subnets in different Availability Zones

> **Note**: VPC Lattice is available in most AWS regions. Verify regional availability before deployment.

## Installation

1. **Clone or navigate to this directory**:
   ```bash
   cd aws/application-health-monitoring-lattice-cloudwatch/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

The application supports several configuration options:

### Environment Variables

```bash
# Optional: Specify VPC ID (uses default VPC if not set)
export VPC_ID="vpc-xxxxxxxxx"

# Optional: Email for SNS notifications
export NOTIFICATION_EMAIL="your-email@example.com"

# Optional: Environment name for tagging
export ENVIRONMENT="production"
```

### CDK Context Parameters

Alternatively, use CDK context parameters:

```bash
# Deploy with specific VPC
cdk deploy -c vpcId=vpc-xxxxxxxxx

# Deploy with email notifications
cdk deploy -c notificationEmail=your-email@example.com

# Deploy with custom environment
cdk deploy -c environment=production
```

## Deployment

### Quick Start

```bash
# Synthesize and review CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Deploy with email notifications
cdk deploy -c notificationEmail=your-email@example.com

# Deploy with specific VPC
cdk deploy -c vpcId=vpc-xxxxxxxxx -c notificationEmail=your-email@example.com
```

### Advanced Deployment Options

```bash
# Deploy with all configuration options
cdk deploy \
  -c vpcId=vpc-xxxxxxxxx \
  -c notificationEmail=operations@company.com \
  -c environment=production

# Deploy with approval for security changes
cdk deploy --require-approval any-change

# Deploy with detailed output
cdk deploy --verbose
```

## Validation and Testing

### 1. Verify VPC Lattice Resources

```bash
# Get stack outputs
aws cloudformation describe-stacks \
  --stack-name ApplicationHealthMonitoringStack \
  --query "Stacks[0].Outputs"

# Check service network status
aws vpc-lattice get-service-network \
  --service-network-identifier <SERVICE_NETWORK_ID>

# Verify service configuration
aws vpc-lattice get-service \
  --service-identifier <SERVICE_ID>
```

### 2. Test CloudWatch Metrics

```bash
# List VPC Lattice metrics
aws cloudwatch list-metrics \
  --namespace "AWS/VpcLattice" \
  --dimensions "Name=Service,Value=<SERVICE_ID>"

# Get recent metric data
aws cloudwatch get-metric-statistics \
  --namespace "AWS/VpcLattice" \
  --metric-name "TotalRequestCount" \
  --dimensions "Name=Service,Value=<SERVICE_ID>" \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 300 \
  --statistics "Sum"
```

### 3. Test Auto-Remediation Function

```bash
# Invoke Lambda function with test payload
aws lambda invoke \
  --function-name <FUNCTION_NAME> \
  --payload '{
    "Records": [{
      "Sns": {
        "Message": "{\"AlarmName\":\"Test-5XX-Alarm\",\"NewStateValue\":\"ALARM\",\"StateChangeTime\":\"'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'\"}"
      }
    }]
  }' \
  response.json

# Check execution result
cat response.json
```

### 4. Test SNS Notifications

```bash
# Send test notification
aws sns publish \
  --topic-arn <TOPIC_ARN> \
  --subject "Health Monitoring Test" \
  --message "Testing health monitoring notification system at $(date)"
```

## Monitoring and Operations

### CloudWatch Dashboard

Access the monitoring dashboard at:
```
https://<AWS_REGION>.console.aws.amazon.com/cloudwatch/home?region=<AWS_REGION>#dashboards:name=VPCLattice-Health-<SUFFIX>
```

The dashboard provides:
- HTTP response code trends
- Request response time metrics
- Request volume and timeout counts
- Target health status

### CloudWatch Alarms

The solution creates three critical alarms:

1. **High 5XX Error Rate**: Triggers when >10 server errors in 10 minutes
2. **Request Timeouts**: Triggers when >5 timeouts in 10 minutes  
3. **High Response Time**: Triggers when average response time >2 seconds for 15 minutes

### SNS Notifications

Subscribe additional endpoints:

```bash
# Email subscription
aws sns subscribe \
  --topic-arn <TOPIC_ARN> \
  --protocol email \
  --notification-endpoint operations@company.com

# SMS subscription
aws sns subscribe \
  --topic-arn <TOPIC_ARN> \
  --protocol sms \
  --notification-endpoint +1234567890

# Webhook subscription
aws sns subscribe \
  --topic-arn <TOPIC_ARN> \
  --protocol https \
  --notification-endpoint https://hooks.slack.com/your-webhook
```

## Customization

### Alarm Thresholds

Modify alarm thresholds in `app.ts`:

```typescript
// Example: Lower 5XX error threshold for production
threshold: 5, // Instead of 10

// Example: Reduce response time threshold
threshold: 1000, // 1 second instead of 2 seconds
```

### Health Check Configuration

Adjust target group health checks:

```typescript
config: {
  healthCheck: {
    healthCheckIntervalSeconds: 15, // More frequent checks
    healthyThresholdCount: 1,       // Faster recovery
    unhealthyThresholdCount: 3      // More tolerance
  }
}
```

### Auto-Remediation Logic

Extend the Lambda function for advanced remediation:

```python
def remediate_error_rate(alarm_data):
    """Enhanced error rate remediation"""
    # Get unhealthy targets
    unhealthy_targets = get_unhealthy_targets()
    
    # Remove from target group
    for target in unhealthy_targets:
        deregister_target(target)
    
    # Trigger Auto Scaling replacement
    trigger_instance_replacement()
    
    # Monitor recovery
    schedule_recovery_check()
```

## Cost Optimization

### Resource Costs

Estimated monthly costs for monitoring resources:

- **VPC Lattice Service Network**: $0 (no additional charge)
- **VPC Lattice Service**: Based on processed requests
- **Lambda Function**: $0.50-2.00 (based on alarm frequency)
- **CloudWatch Alarms**: $3.00 (3 alarms × $1.00)
- **SNS Topic**: $0.50-1.00 (based on notification volume)
- **CloudWatch Dashboard**: $3.00

**Total Estimated Cost**: $7-9/month (excluding VPC Lattice request charges)

### Cost Optimization Tips

1. **Alarm Thresholds**: Tune thresholds to reduce false positives
2. **Lambda Memory**: Use minimum required memory (256MB is often sufficient)
3. **CloudWatch Logs**: Set log retention policies (default: 7 days)
4. **SNS Filtering**: Use message filtering to reduce notification volume

## Security Best Practices

### IAM Permissions

The Lambda function uses least privilege permissions:
- VPC Lattice: Read access and target management
- CloudWatch: Metrics read access
- EC2: Instance describe and reboot (for remediation)
- SNS: Publish to specific topic only

### Network Security

- VPC Lattice uses AWS IAM for authentication
- All communications use AWS internal networks
- No internet gateway required for basic functionality

### Data Protection

- CloudWatch logs are encrypted at rest
- SNS messages support encryption in transit
- Lambda environment variables are encrypted

## Troubleshooting

### Common Issues

1. **VPC Lattice Not Available**:
   ```
   Error: VPC Lattice is not available in this region
   Solution: Deploy in supported regions (us-east-1, us-west-2, eu-west-1, etc.)
   ```

2. **Default VPC Not Found**:
   ```
   Error: No default VPC found
   Solution: Specify VPC ID using -c vpcId=vpc-xxxxxxxxx
   ```

3. **Lambda Permission Errors**:
   ```
   Error: Access denied when calling VPC Lattice APIs
   Solution: Verify IAM role has correct permissions
   ```

4. **No Metrics Data**:
   ```
   Issue: CloudWatch shows no VPC Lattice metrics
   Solution: Generate traffic to the service or wait for metrics to appear (up to 5 minutes)
   ```

### Debug Commands

```bash
# Check CDK context
cdk context

# Validate CloudFormation template
cdk synth --validate

# View deployment differences
cdk diff

# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name ApplicationHealthMonitoringStack
```

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
# This will remove all created resources including:
# - VPC Lattice Service Network and Service
# - Target Group
# - Lambda function and IAM role
# - CloudWatch alarms and dashboard
# - SNS topic and subscriptions
```

### Selective Cleanup

If you need to remove specific resources:

```bash
# Remove CloudWatch alarms only
aws cloudwatch delete-alarms \
  --alarm-names \
  "VPCLattice-health-monitor-service-<SUFFIX>-High5XXRate" \
  "VPCLattice-health-monitor-service-<SUFFIX>-RequestTimeouts" \
  "VPCLattice-health-monitor-service-<SUFFIX>-HighResponseTime"

# Remove SNS subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn <TOPIC_ARN> \
  --query "Subscriptions[].SubscriptionArn" \
  --output text | xargs -I {} aws sns unsubscribe --subscription-arn {}
```

## Support

For issues with this CDK implementation:

1. **Check CloudFormation Events**: Review deployment events in AWS Console
2. **CDK Documentation**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
3. **VPC Lattice Documentation**: [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/)
4. **CloudWatch Documentation**: [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

## Contributing

To extend this solution:

1. **Add New Alarms**: Create additional CloudWatch alarms for other metrics
2. **Enhanced Remediation**: Implement more sophisticated auto-remediation logic
3. **Multi-Region Support**: Extend to monitor across multiple AWS regions
4. **Integration**: Add integration with incident management systems
5. **Custom Metrics**: Implement custom application metrics for enhanced monitoring

## License

This CDK application is provided under the MIT License. See the LICENSE file for details.