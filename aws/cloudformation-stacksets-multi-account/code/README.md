# Infrastructure as Code for CloudFormation StackSets Multi-Account Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CloudFormation StackSets Multi-Account Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with management account credentials
- AWS Organizations set up with management account and member accounts
- IAM permissions for CloudFormation StackSets administration
- Multiple AWS accounts for testing (minimum 2-3 target accounts)
- Understanding of AWS Organizations, IAM cross-account roles, and CloudFormation
- Appropriate permissions for resource creation including:
  - CloudFormation StackSets operations
  - IAM role creation and policy attachment
  - S3 bucket creation and management
  - SNS topic creation
  - Lambda function deployment
  - CloudWatch dashboard and alarm creation

## Architecture Overview

This implementation creates:

- **StackSet Administration Infrastructure**: IAM roles and policies for centralized management
- **Cross-Account Execution Roles**: Automated deployment of execution roles to target accounts
- **Organization-Wide Governance Policies**: Security policies, audit logging, and compliance controls
- **Monitoring and Alerting**: CloudWatch dashboards, alarms, and SNS notifications
- **Drift Detection**: Automated Lambda function for continuous compliance monitoring

## Quick Start

### Using CloudFormation

```bash
# Deploy the main StackSet infrastructure
aws cloudformation create-stack \
    --stack-name stackset-management-infrastructure \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=OrganizationId,ParameterValue=YOUR_ORG_ID \
                ParameterKey=TargetAccounts,ParameterValue="account1,account2,account3" \
                ParameterKey=TargetRegions,ParameterValue="us-east-1,us-west-2,eu-west-1"
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install

# Configure your deployment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the infrastructure
cdk deploy StackSetManagementStack
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt

# Configure your deployment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the infrastructure
cdk deploy StackSetManagementStack
```

### Using Terraform

```bash
cd terraform/
terraform init

# Configure your deployment
terraform plan -var="organization_id=YOUR_ORG_ID" \
               -var="target_accounts=[\"account1\",\"account2\",\"account3\"]" \
               -var="target_regions=[\"us-east-1\",\"us-west-2\",\"eu-west-1\"]"

terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| OrganizationId | AWS Organizations ID | - | Yes |
| TargetAccounts | Comma-separated list of target account IDs | - | Yes |
| TargetRegions | Comma-separated list of target regions | us-east-1,us-west-2 | No |
| ComplianceLevel | Compliance level for security policies | standard | No |
| Environment | Environment designation | all | No |
| StackSetName | Name prefix for the StackSet | org-governance-stackset | No |

### CDK Configuration

Configure the following environment variables:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
export ORGANIZATION_ID="o-1234567890"
export TARGET_ACCOUNTS="123456789012,123456789013,123456789014"
export TARGET_REGIONS="us-east-1,us-west-2,eu-west-1"
```

### Terraform Variables

```hcl
organization_id = "o-1234567890"
target_accounts = ["123456789012", "123456789013", "123456789014"]
target_regions = ["us-east-1", "us-west-2", "eu-west-1"]
compliance_level = "standard"
environment = "all"
```

## Deployment Process

The deployment follows these phases:

1. **Prerequisites Setup**: Creates IAM roles and S3 buckets for templates
2. **Execution Role Deployment**: Deploys cross-account execution roles
3. **StackSet Creation**: Creates the organization-wide governance StackSet
4. **Policy Deployment**: Deploys governance policies to target accounts/regions
5. **Monitoring Setup**: Creates CloudWatch dashboards and alarms
6. **Drift Detection**: Deploys Lambda function for automated compliance monitoring

## Monitoring and Operations

### CloudWatch Dashboards

The implementation creates comprehensive dashboards for:

- StackSet operation success/failure rates
- Recent operation history and status
- Drift detection results
- Cross-account deployment status

### Automated Alerting

SNS notifications are configured for:

- Failed StackSet operations
- Drift detection alerts
- Compliance violations
- Operation completion status

### Drift Detection

The automated Lambda function provides:

- Continuous compliance monitoring
- Automated drift detection across all accounts
- Detailed reporting of configuration changes
- Integration with CloudWatch and SNS for alerting

## Security Considerations

### IAM Roles and Permissions

- **StackSet Administrator Role**: Minimal permissions for cross-account operations
- **Execution Roles**: Least privilege access in target accounts
- **Lambda Execution Role**: Specific permissions for drift detection only

### Compliance Controls

- **Password Policies**: Enforced across all accounts
- **CloudTrail Logging**: Comprehensive audit logging
- **GuardDuty**: Threat detection enabled
- **AWS Config**: Configuration compliance monitoring
- **S3 Security**: Public access blocked, encryption enabled

### Cross-Account Security

- Trust relationships established through AWS Organizations
- Service-managed permissions for automatic role provisioning
- Encrypted communication and data storage
- Audit logging for all cross-account activities

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   - Ensure AWS Organizations trusted access is enabled
   - Verify management account has necessary permissions
   - Check execution role deployment status

2. **StackSet Operation Failures**:
   - Review CloudWatch logs for detailed error messages
   - Check target account permissions and status
   - Verify regional service availability

3. **Drift Detection Issues**:
   - Ensure Lambda function has necessary permissions
   - Check SNS topic configuration
   - Verify CloudWatch log group settings

### Validation Commands

```bash
# Check StackSet status
aws cloudformation describe-stack-set --stack-set-name YOUR_STACKSET_NAME

# List stack instances
aws cloudformation list-stack-instances --stack-set-name YOUR_STACKSET_NAME

# Check operation history
aws cloudformation list-stack-set-operations --stack-set-name YOUR_STACKSET_NAME

# Test drift detection
aws cloudformation detect-stack-set-drift --stack-set-name YOUR_STACKSET_NAME
```

## Cleanup

### Using CloudFormation

```bash
# Delete stack instances first
aws cloudformation delete-stack-instances \
    --stack-set-name YOUR_STACKSET_NAME \
    --accounts "account1,account2,account3" \
    --regions "us-east-1,us-west-2,eu-west-1" \
    --retain-stacks false

# Wait for completion, then delete the stack
aws cloudformation delete-stack --stack-name stackset-management-infrastructure
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy StackSetManagementStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Adding New Governance Policies

1. Modify the governance template in your chosen IaC tool
2. Update StackSet with new template
3. Monitor deployment across all accounts
4. Validate compliance through drift detection

### Extending to Additional Regions

1. Update the target regions parameter/variable
2. Re-deploy the StackSet configuration
3. Monitor regional deployment status
4. Update monitoring dashboards for new regions

### Custom Compliance Levels

The implementation supports three compliance levels:

- **Basic**: Minimum security requirements
- **Standard**: Recommended enterprise settings
- **Strict**: High-security environments

Modify the compliance mappings in the governance template to customize policies.

## Cost Optimization

### Resource Costs

- **CloudFormation StackSets**: No additional cost
- **IAM Roles**: No cost for role creation
- **S3 Storage**: Minimal cost for template storage
- **CloudWatch**: Dashboard and alarm costs vary by usage
- **Lambda**: Minimal cost for drift detection function
- **SNS**: Message delivery costs

### Cost Management

- Use S3 lifecycle policies for template versioning
- Monitor CloudWatch usage and optimize retention
- Consider regional deployment strategies to minimize data transfer

## Performance Optimization

### Deployment Strategies

- **Parallel Deployment**: Faster rollouts across regions
- **Sequential Deployment**: Safer for critical updates
- **Failure Tolerance**: Configurable thresholds for operation success

### Operational Preferences

Customize deployment behavior:

```yaml
OperationPreferences:
  RegionConcurrencyType: PARALLEL
  MaxConcurrentPercentage: 50
  FailureTolerancePercentage: 10
```

## Integration with CI/CD

### GitOps Workflow

1. Store templates in version control
2. Implement automated testing
3. Use CodePipeline for deployment
4. Monitor through CloudWatch

### Automated Updates

- Template versioning and rollback capabilities
- Automated drift detection and remediation
- Integration with AWS Config for compliance automation

## Best Practices

### StackSet Management

- Use descriptive naming conventions
- Implement proper tagging strategies
- Monitor operation success rates
- Regular compliance audits

### Security Best Practices

- Regular review of IAM permissions
- Audit logging analysis
- Compliance policy updates
- Security incident response procedures

### Operational Excellence

- Comprehensive monitoring and alerting
- Regular backup and disaster recovery testing
- Documentation maintenance
- Team training and knowledge sharing

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS CloudFormation StackSets documentation
3. Consult AWS Organizations best practices
4. Review CloudWatch logs for detailed error information
5. Contact AWS Support for service-specific issues

## Additional Resources

- [AWS CloudFormation StackSets User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_introduction.html)
- [AWS IAM Cross-Account Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)
- [AWS Config Multi-Account Management](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [AWS CloudTrail Multi-Account Logging](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-sharing-logs.html)