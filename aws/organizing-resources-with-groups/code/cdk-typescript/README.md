# AWS Resource Groups Automated Resource Management - CDK TypeScript

This directory contains the AWS CDK TypeScript implementation for the **Organizing Resources with Groups and Automated Management** recipe. This CDK application deploys a comprehensive resource management solution that automatically organizes, monitors, and manages AWS resources using Resource Groups, Systems Manager, CloudWatch, and other AWS services.

## Architecture Overview

The CDK application creates:

- **Resource Groups**: Tag-based logical organization of AWS resources
- **Systems Manager Automation**: Automated maintenance and tagging workflows
- **CloudWatch Monitoring**: Custom dashboards and alarms for resource health
- **SNS Notifications**: Multi-channel alerting system
- **Cost Management**: AWS Budgets and Cost Anomaly Detection
- **EventBridge Rules**: Automated resource tagging on creation
- **Lambda Functions**: Custom business logic for resource processing

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured
2. **Node.js 18+** and **npm** installed
3. **AWS CDK v2** installed globally: `npm install -g aws-cdk`
4. **Appropriate AWS permissions** for creating:
   - IAM roles and policies
   - Resource Groups
   - Systems Manager documents
   - CloudWatch dashboards and alarms
   - SNS topics and subscriptions
   - AWS Budgets
   - Lambda functions
   - EventBridge rules
   - Cost Explorer anomaly detectors

5. **Estimated cost**: $15-25/month for CloudWatch metrics, SNS notifications, and Lambda executions

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Configure your deployment** (optional):
   Edit the configuration in `app.ts` or use CDK context:
   ```bash
   # Set notification email
   export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export CDK_DEFAULT_REGION=$(aws configure get region)
   ```

3. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Quick Deployment

Deploy with default configuration:
```bash
cdk deploy
```

### Custom Configuration

Deploy with custom parameters:
```bash
cdk deploy \
  --context resourceGroupName="my-production-resources" \
  --context notificationEmail="admin@example.com" \
  --context budgetAmount=200
```

### Deployment Options

```bash
# Preview changes before deployment
cdk diff

# Deploy with approval for security changes
cdk deploy --require-approval=any-change

# Deploy with specific stack name
cdk deploy --stack-name MyResourceGroupStack

# Deploy and show CloudFormation template
cdk synth && cdk deploy
```

## Configuration

### Environment Variables

Set these environment variables for configuration:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"  # Your AWS account ID
export CDK_DEFAULT_REGION="us-east-1"      # Your preferred region
export NODE_ENV="production"               # Enables termination protection
```

### Context Configuration

Configure via `cdk.json` or command line:

```json
{
  "context": {
    "resourceGroupName": "production-web-app",
    "notificationEmail": "alerts@example.com",
    "budgetAmount": 100
  }
}
```

### Stack Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `resourceGroupName` | Name for the resource group | `production-web-app` | No |
| `notificationEmail` | Email for SNS notifications | None | Recommended |
| `budgetAmount` | Monthly budget in USD | 100 | No |

## Post-Deployment Steps

After successful deployment:

1. **Confirm email subscription**:
   Check your email for SNS subscription confirmation

2. **Tag existing resources**:
   Apply tags to existing resources to include them in the resource group:
   ```bash
   # Example: Tag an EC2 instance
   aws ec2 create-tags \
     --resources i-1234567890abcdef0 \
     --tags Key=Environment,Value=production Key=Application,Value=web-app
   ```

3. **Verify resource group**:
   ```bash
   # Check resource group contents
   aws resource-groups list-group-resources \
     --group-name production-web-app
   ```

4. **Test automation**:
   ```bash
   # Execute maintenance automation
   aws ssm start-automation-execution \
     --document-name "ResourceGroupMaintenance-[suffix]" \
     --parameters "ResourceGroupName=production-web-app"
   ```

## Monitoring and Dashboards

### CloudWatch Dashboard

Access your custom dashboard at:
```
https://[region].console.aws.amazon.com/cloudwatch/home?region=[region]#dashboards:name=resource-dashboard-[suffix]
```

The dashboard includes:
- Resource count trends
- CPU utilization metrics
- Cost tracking
- Custom business metrics

### CloudWatch Alarms

The stack creates several alarms:
- **High CPU Usage**: Triggers when CPU > 80% for 2 periods
- **Resource Health**: Monitors EC2 status check failures
- **Budget Alerts**: Notifies at 80% and 100% budget thresholds

### Cost Monitoring

- **AWS Budgets**: Monthly cost tracking with email alerts
- **Cost Anomaly Detection**: Machine learning-based cost spike detection
- **Cost Dashboard**: Visual cost trends and forecasting

## Automation Features

### Systems Manager Documents

1. **Resource Maintenance** (`ResourceGroupMaintenance-[suffix]`):
   - Inventories all resources in the group
   - Publishes custom CloudWatch metrics
   - Runs health checks

2. **Automated Tagging** (`AutomatedResourceTagging-[suffix]`):
   - Applies consistent tags to resources
   - Ensures resource group inclusion
   - Maintains organizational standards

### EventBridge Integration

- **Automatic Tagging**: New resources are automatically tagged
- **Supported Services**: EC2, S3, RDS, Lambda
- **Tag Consistency**: Enforces organizational tagging standards

## Customization

### Adding New Resource Types

To monitor additional resource types, modify the resource group query in `resource-groups-automation-stack.ts`:

```typescript
resourceQuery: {
  type: 'TAG_FILTERS_1_0',
  query: {
    resourceTypeFilters: [
      'AWS::EC2::Instance',
      'AWS::S3::Bucket',
      'AWS::RDS::DBInstance',
      'AWS::Lambda::Function',
      // Add your resource types here
    ],
    tagFilters: [
      // Your tag filters
    ],
  },
},
```

### Custom Metrics

Add custom CloudWatch metrics in the Lambda function or Systems Manager documents:

```python
# Example custom metric
cloudwatch = boto3.client('cloudwatch')
cloudwatch.put_metric_data(
    Namespace='ResourceGroups/Custom',
    MetricData=[
        {
            'MetricName': 'CustomBusinessMetric',
            'Value': metric_value,
            'Unit': 'Count',
            'Dimensions': [
                {
                    'Name': 'ResourceGroup',
                    'Value': resource_group_name
                }
            ]
        }
    ]
)
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Check your AWS credentials
   aws sts get-caller-identity
   
   # Verify required permissions
   aws iam get-role --role-name ResourceGroupAutomationRole-[suffix]
   ```

2. **Resource Group Empty**:
   - Verify resources have correct tags: `Environment=production` and `Application=web-app`
   - Check tag case sensitivity
   - Allow time for resource discovery (up to 15 minutes)

3. **Automation Failures**:
   ```bash
   # Check automation execution status
   aws ssm describe-automation-executions \
     --filters Key=DocumentName,Values=ResourceGroupMaintenance-[suffix]
   ```

4. **Budget Notifications Not Working**:
   - Confirm email subscription in SNS
   - Check budget thresholds are appropriate
   - Verify cost allocation tags

### Debugging

Enable debug logging:
```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

View CloudWatch logs:
```bash
# Lambda function logs
aws logs tail /aws/lambda/resource-auto-tagger-[suffix] --follow

# Systems Manager execution logs
aws ssm get-automation-execution \
  --automation-execution-id [execution-id]
```

## Cleanup

### Option 1: Using CDK
```bash
cdk destroy
```

### Option 2: Manual Cleanup
If CDK destroy fails:

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
  --stack-name ResourceGroupsAutomationStack

# Clean up any remaining resources
aws resource-groups delete-group \
  --group-name production-web-app
```

### Post-Cleanup Verification
```bash
# Verify all resources are deleted
aws cloudformation describe-stacks \
  --stack-name ResourceGroupsAutomationStack

# Should return: Stack with id ResourceGroupsAutomationStack does not exist
```

## Development

### Building
```bash
npm run build
```

### Testing
```bash
npm test
```

### Linting
```bash
npm run lint
```

### CDK Commands
```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# List all stacks
cdk list
```

## Security Considerations

- **IAM Roles**: All automation uses least-privilege IAM roles
- **Encryption**: SNS topics use AWS managed encryption
- **Network**: No public endpoints created
- **Monitoring**: All API calls logged via CloudTrail
- **Tags**: Consistent tagging for security and compliance

## Cost Optimization

- **Resource Lifecycle**: Automated identification of unused resources
- **Right-sizing**: CloudWatch metrics help identify over-provisioned resources
- **Cost Alerts**: Proactive budget monitoring prevents overruns
- **Tagging**: Detailed cost allocation by application and environment

## Support

For issues with this CDK implementation:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review the [original recipe](../../resource-groups-automated-resource-management.md)
3. Consult AWS service documentation for specific services
4. Check CloudWatch logs for detailed error information

## Contributing

To contribute improvements to this CDK implementation:

1. Test changes thoroughly in a development environment
2. Follow TypeScript and CDK best practices
3. Update documentation for any new features
4. Ensure backward compatibility

---

**Note**: This infrastructure code implements the complete solution described in the "Organizing Resources with Groups and Automated Management" recipe using AWS CDK TypeScript best practices.