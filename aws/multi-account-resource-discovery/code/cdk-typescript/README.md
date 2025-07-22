# Automated Multi-Account Resource Discovery - CDK TypeScript

This AWS CDK TypeScript application creates a comprehensive solution for automated resource discovery and compliance monitoring across multiple AWS accounts using AWS Resource Explorer, AWS Config, EventBridge, and Lambda.

## Architecture Overview

The solution implements an event-driven architecture that provides:

- **AWS Resource Explorer** - Aggregated index for organization-wide resource search
- **AWS Config** - Organizational aggregator for compliance monitoring with comprehensive rules
- **EventBridge** - Event-driven automation with multiple rule patterns
- **Lambda Function** - Intelligent event processing with structured logging and metrics
- **S3 Bucket** - Secure Config data storage with lifecycle policies and encryption
- **IAM Roles** - Least privilege access with comprehensive permissions for multi-account operations

## Features

### Resource Discovery
- Cross-account resource search using Resource Explorer aggregated index
- Automatic resource categorization and inventory management
- Support for all AWS services and resource types

### Compliance Monitoring
- Organizational Config aggregator for centralized compliance view
- Six comprehensive Config rules covering security best practices:
  - S3 bucket public access prohibited
  - EC2 security group attachment validation
  - Root access key monitoring
  - EBS volume encryption enforcement
  - IAM password policy compliance
  - Lambda function public access prohibited

### Event-Driven Automation
- Real-time compliance violation processing
- Scheduled daily resource discovery scans
- Resource Explorer event processing
- Intelligent event routing and response

### Security & Compliance
- CDK Nag integration for security best practices
- Encryption at rest for all data storage
- Least privilege IAM policies
- Comprehensive audit logging

## Prerequisites

- AWS CDK v2.133.0 or later
- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- AWS Organizations enabled with management account access
- TypeScript 5.4.x

### Required AWS Permissions

The deploying user/role needs the following permissions:
- CloudFormation full access
- IAM role/policy creation and management
- Lambda function management
- S3 bucket creation and management
- Resource Explorer configuration
- Config service configuration
- EventBridge rule management
- Organizations trusted access management

## Installation & Deployment

### 1. Install Dependencies

```bash
cd cdk-typescript/
npm install
```

### 2. Configure Environment

```bash
# Set required environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export PROJECT_NAME="multi-account-discovery"  # Optional: customize project name
export ENVIRONMENT="development"  # Optional: set environment (development/staging/production)
```

### 3. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/${CDK_DEFAULT_REGION}
```

### 4. Synthesize and Deploy

```bash
# Generate CloudFormation template
cdk synth

# Preview changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never
```

### 5. Verify Deployment

```bash
# Check Lambda function
aws lambda get-function --function-name ${PROJECT_NAME}-processor

# Verify Resource Explorer index
aws resource-explorer-2 get-index --region ${CDK_DEFAULT_REGION}

# Check Config aggregator
aws configservice describe-configuration-aggregators
```

## Configuration Options

### Environment Variables

- `PROJECT_NAME`: Custom project name for resource naming (default: "multi-account-discovery")
- `ENVIRONMENT`: Deployment environment (development/staging/production)
- `CDK_DEFAULT_ACCOUNT`: AWS account ID for deployment
- `CDK_DEFAULT_REGION`: AWS region for deployment

### Stack Properties

The stack accepts the following properties:

- `projectName`: String - Custom project name for resource naming
- `env`: Environment - AWS account and region configuration
- `terminationProtection`: Boolean - Enable termination protection for production

## Usage Examples

### Search Resources Across Accounts

```bash
# Search for EC2 instances across all accounts
aws resource-explorer-2 search \
    --query-string "resourcetype:AWS::EC2::Instance" \
    --region ${CDK_DEFAULT_REGION}

# Search for S3 buckets in specific account
aws resource-explorer-2 search \
    --query-string "service:s3 AND owningaccountid:123456789012" \
    --region ${CDK_DEFAULT_REGION}
```

### Monitor Compliance Status

```bash
# Get organizational compliance summary
aws configservice get-aggregate-compliance-summary \
    --configuration-aggregator-name ${PROJECT_NAME}-aggregator

# Check specific rule compliance
aws configservice get-aggregate-compliance-details-by-config-rule \
    --configuration-aggregator-name ${PROJECT_NAME}-aggregator \
    --config-rule-name ${PROJECT_NAME}-s3-bucket-public-access-prohibited \
    --account-id ${CDK_DEFAULT_ACCOUNT} \
    --aws-region ${CDK_DEFAULT_REGION}
```

### Monitor Lambda Function

```bash
# View recent logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/${PROJECT_NAME}-processor \
    --start-time $(date -d '1 hour ago' +%s)000

# Check function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=${PROJECT_NAME}-processor \
    --statistics Sum \
    --start-time $(date -d '1 day ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 3600
```

## Customization

### Adding Custom Config Rules

To add additional Config rules, modify the `createConfigRules` method in the stack:

```typescript
// Add new custom rule
rules.push(new config.CfnConfigRule(this, 'CustomRule', {
  configRuleName: `${projectName}-custom-rule`,
  description: 'Custom compliance rule description',
  source: {
    owner: 'AWS',
    sourceIdentifier: 'CUSTOM_RULE_IDENTIFIER',
  },
}));
```

### Extending Lambda Function

The Lambda function code is inline and can be customized for specific use cases:

- Add custom event processing logic
- Integrate with external ITSM systems
- Implement automated remediation workflows
- Add custom metrics and monitoring

### Adding EventBridge Rules

Create additional EventBridge rules for specific event patterns:

```typescript
const customRule = new events.Rule(this, 'CustomEventRule', {
  ruleName: `${projectName}-custom-rule`,
  eventPattern: {
    source: ['custom.application'],
    detailType: ['Custom Event Type'],
  },
});

customRule.addTarget(new targets.LambdaFunction(lambdaFunction));
```

## Monitoring & Troubleshooting

### CloudWatch Logs

- Lambda function logs: `/aws/lambda/${PROJECT_NAME}-processor`
- Config service logs: Available in CloudTrail
- EventBridge rule executions: Available in EventBridge console

### Common Issues

1. **Permission Errors**: Ensure Organizations trusted access is enabled
2. **Config Rules Failing**: Verify Config service is enabled in target accounts
3. **Lambda Timeouts**: Check function timeout configuration (default: 5 minutes)
4. **Resource Explorer Not Finding Resources**: Ensure indexes are created in member accounts

### Health Checks

```bash
# Check stack status
aws cloudformation describe-stacks \
    --stack-name MultiAccountResourceDiscoveryStack

# Verify EventBridge rules
aws events list-rules --name-prefix ${PROJECT_NAME}

# Check Config aggregator status
aws configservice describe-configuration-aggregation-authorizations
```

## Security Considerations

### Data Protection
- All S3 buckets use encryption at rest
- Lambda function uses secure environment variables
- IAM roles follow least privilege principle

### Network Security
- No public network access for any resources
- VPC endpoints can be configured for enhanced security
- CloudTrail logging for all API calls

### Compliance
- CDK Nag integration ensures security best practices
- Config rules monitor security compliance
- Audit logs retained according to compliance requirements

## Cost Optimization

### Resource Lifecycle
- S3 lifecycle policies for Config data (IA after 30 days, Glacier after 90 days)
- CloudWatch log retention (1 month default)
- Lambda reserved concurrency to control costs

### Cost Monitoring
- Resource tagging for cost allocation
- Regular review of Resource Explorer query costs
- Config rule evaluation cost monitoring

## Cleanup

To remove all resources:

```bash
# Destroy the stack
cdk destroy

# Clean up CDK bootstrap (optional)
aws cloudformation delete-stack --stack-name CDKToolkit
```

**Warning**: This will delete all Config data and compliance history. Ensure you have proper backups if needed.

## Support & Contributing

### Getting Help
- Check AWS Config documentation for rule configuration
- Review Lambda function logs for error details
- Consult Resource Explorer documentation for search patterns

### Best Practices
- Run `cdk diff` before deployment
- Test Config rules in development environment first
- Monitor Lambda function performance and costs
- Regularly review and update compliance rules

### Extensions
This solution can be extended with:
- Custom Config rules for organization-specific policies
- Integration with AWS Security Hub
- Automated remediation workflows
- Cost optimization recommendations
- Custom dashboards and reporting

## Related Resources

- [AWS Resource Explorer Documentation](https://docs.aws.amazon.com/resource-explorer/)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/typescript/)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/)