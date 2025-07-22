# CloudFormation StackSets Multi-Account Multi-Region CDK TypeScript Application

This CDK TypeScript application deploys a comprehensive CloudFormation StackSets solution for organization-wide governance and security policy management across multiple AWS accounts and regions.

## Architecture Overview

The application consists of four main stacks:

1. **ExecutionRoleStack**: Creates CloudFormation templates and StackSets for deploying execution roles to target accounts
2. **GovernanceTemplateStack**: Creates and manages governance policy templates with different compliance levels
3. **StackSetsMultiAccountStack**: Main stack that creates StackSets for organization-wide governance deployment
4. **MonitoringStack**: Provides monitoring, alerting, and automated drift detection for StackSets operations

## Features

### Core StackSets Functionality
- **Service-managed permissions** with AWS Organizations integration
- **Automatic deployment** to new accounts joining organizational units
- **Multi-region deployment** with configurable concurrency and failure tolerance
- **Drift detection** and remediation capabilities
- **Template versioning** and update management

### Governance Policies
- **IAM password policies** with configurable compliance levels
- **CloudTrail logging** for audit trails across all accounts
- **GuardDuty threat detection** with configurable frequencies
- **AWS Config** for compliance monitoring
- **S3 bucket policies** for secure audit log storage
- **KMS encryption** for enhanced security (v2 template)

### Monitoring and Alerting
- **CloudWatch dashboards** for real-time monitoring
- **SNS notifications** for operation failures and drift detection
- **CloudWatch alarms** for failure rates and drift detection
- **Automated drift detection** with Lambda functions
- **EventBridge rules** for StackSets state changes

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- AWS Organizations set up with management account
- Appropriate IAM permissions for CloudFormation StackSets

## Installation

1. Clone the repository and navigate to the CDK TypeScript directory:
```bash
cd aws/cloudformation-stacksets-multi-account-multi-region/code/cdk-typescript/
```

2. Install dependencies:
```bash
npm install
```

3. Build the project:
```bash
npm run build
```

## Configuration

### Environment Variables

Set the following environment variables or provide them as CDK context:

```bash
# Required
export MANAGEMENT_ACCOUNT_ID="123456789012"
export ORGANIZATION_ID="o-example123456"

# Optional
export TARGET_REGIONS="us-east-1,us-west-2,eu-west-1"
export TARGET_ACCOUNTS="111111111111,222222222222"
export COMPLIANCE_LEVEL="standard"  # basic, standard, strict
export ENVIRONMENT="all"  # development, staging, production, all
export STACKSET_NAME="org-governance-stackset"
export TEMPLATE_BUCKET="my-templates-bucket"
```

### CDK Context

Alternatively, you can provide configuration via CDK context:

```bash
cdk deploy --context managementAccountId=123456789012 \
           --context organizationId=o-example123456 \
           --context complianceLevel=strict
```

## Deployment

### Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### Deploy All Stacks

```bash
npm run deploy
```

### Deploy Individual Stacks

```bash
# Deploy execution role stack first
cdk deploy ExecutionRoleStack

# Deploy governance template stack
cdk deploy GovernanceTemplateStack

# Deploy main StackSets stack
cdk deploy StackSetsMultiAccountStack

# Deploy monitoring stack
cdk deploy MonitoringStack
```

## Usage

### Deploying to New Accounts

When new accounts join your organization, the StackSets will automatically deploy governance policies if auto-deployment is enabled.

### Manual Drift Detection

Trigger drift detection manually:

```bash
aws lambda invoke \
    --function-name stackset-drift-detection-YOUR_STACKSET_NAME \
    --payload '{"source": "manual-trigger"}' \
    response.json
```

### Viewing Monitoring Dashboard

Access the CloudWatch dashboard:
- Navigate to CloudWatch in the AWS Console
- Go to Dashboards
- Select the dashboard named `StackSet-Monitoring-YOUR_STACKSET_NAME`

### Updating Governance Policies

To update governance policies:

1. Modify the governance template in `lib/governance-template-stack.ts`
2. Rebuild and deploy:
```bash
npm run build
cdk deploy GovernanceTemplateStack
```

3. Update the StackSet with new template:
```bash
aws cloudformation update-stack-set \
    --stack-set-name YOUR_STACKSET_NAME \
    --template-body file://new-template.yaml
```

## Compliance Levels

The application supports three compliance levels:

### Basic
- Password minimum length: 8 characters
- MFA required: No
- CloudTrail logging: Read-only events
- GuardDuty frequency: 6 hours
- Log retention: 30 days

### Standard
- Password minimum length: 12 characters
- MFA required: Yes
- CloudTrail logging: All events
- GuardDuty frequency: 15 minutes
- Log retention: 365 days

### Strict
- Password minimum length: 16 characters
- MFA required: Yes
- CloudTrail logging: All events with insights
- GuardDuty frequency: 15 minutes
- Log retention: 7 years
- KMS encryption enabled

## Monitoring

### CloudWatch Metrics

The application creates custom metrics:
- `Custom/StackSets/StackInstancesCount`
- `Custom/StackSets/DriftDetectionOperations`
- `Custom/StackSets/DriftDetected`

### Alarms

Three CloudWatch alarms are created:
- **StackSetOperationFailure**: Triggers when operations fail
- **StackSetDriftDetected**: Triggers when drift is detected
- **StackSetHighFailureRate**: Triggers when failure rate exceeds 10%

### Automated Drift Detection

Drift detection runs automatically:
- **Scheduled**: Daily at 9 AM UTC
- **Event-driven**: Triggered by StackSet operation changes
- **Manual**: Can be invoked via Lambda function

## Testing

Run the test suite:

```bash
npm run test
```

Run linting:

```bash
npm run lint
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

**Warning**: This will delete all StackSets, stack instances, and associated resources. Make sure you want to remove governance policies from all accounts before proceeding.

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   - Ensure the management account has StackSets administrator permissions
   - Verify trusted access is enabled for CloudFormation StackSets

2. **StackSet Operation Failures**:
   - Check CloudWatch logs for detailed error messages
   - Verify execution roles are properly deployed to target accounts

3. **Drift Detection Not Working**:
   - Ensure Lambda function has required permissions
   - Check CloudWatch logs for the drift detection function

### Debugging

Enable debug logging:

```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

View CloudFormation events:

```bash
aws cloudformation describe-stack-events \
    --stack-name StackSetsMultiAccountStack
```

## Security Considerations

- All S3 buckets have public access blocked
- CloudTrail logs are encrypted at rest
- IAM roles follow least privilege principle
- KMS encryption is used for enhanced security in strict mode
- All resources are tagged for governance and cost tracking

## Cost Optimization

- CloudWatch log retention is configured based on compliance level
- S3 lifecycle policies manage audit log storage costs
- Lambda functions have appropriate timeout settings
- Unused resources are automatically cleaned up

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For issues and questions:
- Check the AWS CloudFormation StackSets documentation
- Review CloudWatch logs for detailed error messages
- Consult the AWS CDK documentation for CDK-specific issues

## References

- [AWS CloudFormation StackSets User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/)