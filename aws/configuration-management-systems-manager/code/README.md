# Infrastructure as Code for Configuration Management with Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Configuration Management with Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Systems Manager, EC2, CloudWatch, IAM, and SNS
- At least 2 EC2 instances running with SSM Agent installed
- Email address for SNS notifications
- Understanding of AWS IAM roles and policies

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Systems Manager (SSM) operations
- EC2 instance management
- CloudWatch logs and metrics
- SNS topic and subscription management
- IAM role and policy management

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ssm-state-manager-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name ssm-state-manager-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ssm-state-manager-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --parameters NotificationEmail=$NOTIFICATION_EMAIL

# View deployed resources
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --parameters NotificationEmail=$NOTIFICATION_EMAIL

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your settings
cat > terraform.tfvars << EOF
region = "us-east-1"
notification_email = "your-email@example.com"
environment = "demo"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export AWS_REGION="us-east-1"
export NOTIFICATION_EMAIL="your-email@example.com"
export ENVIRONMENT="demo"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws ssm describe-associations \
    --query 'Associations[*].{Name:Name,Status:Overview.Status}'
```

## Architecture Overview

This solution deploys:

1. **IAM Resources**:
   - IAM role for Systems Manager State Manager
   - Custom IAM policy with required permissions
   - Managed policy attachment for SSM operations

2. **Systems Manager Resources**:
   - Custom SSM document for security configuration
   - State Manager associations for SSM Agent updates
   - State Manager associations for security configuration
   - Automation document for remediation

3. **Monitoring Resources**:
   - CloudWatch log group for State Manager logs
   - CloudWatch alarms for association failures
   - CloudWatch dashboard for compliance monitoring
   - SNS topic for notifications

4. **Security Configuration**:
   - Firewall enablement
   - SSH root login restriction
   - Automated compliance monitoring

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for compliance notifications
- `Environment`: Environment tag for resources (default: demo)
- `ScheduleExpression`: How often to run associations (default: rate(1 day))

### CDK Parameters

- `NotificationEmail`: Email address for compliance notifications
- `Environment`: Environment tag for resources
- `EnableFirewall`: Whether to enable firewall (default: true)
- `DisableRootLogin`: Whether to disable root SSH login (default: true)

### Terraform Variables

- `region`: AWS region for deployment
- `notification_email`: Email address for compliance notifications
- `environment`: Environment tag for resources
- `schedule_expression`: How often to run associations
- `enable_firewall`: Whether to enable firewall
- `disable_root_login`: Whether to disable root SSH login

### Bash Script Environment Variables

- `AWS_REGION`: AWS region for deployment
- `NOTIFICATION_EMAIL`: Email address for compliance notifications
- `ENVIRONMENT`: Environment tag for resources

## Validation

After deployment, verify the solution:

1. **Check Association Status**:
   ```bash
   aws ssm describe-associations \
       --query 'Associations[*].{Name:Name,Status:Overview.Status,LastExecutionDate:LastExecutionDate}'
   ```

2. **Monitor Compliance**:
   ```bash
   aws ssm list-compliance-items \
       --resource-types "ManagedInstance" \
       --filters Key=ComplianceType,Values=Association \
       --query 'ComplianceItems[*].{InstanceId:ResourceId,Status:Status}'
   ```

3. **Check CloudWatch Dashboard**:
   - Navigate to CloudWatch Console
   - View the SSM State Manager dashboard
   - Monitor association execution metrics

4. **Test Notifications**:
   - Check your email for SNS subscription confirmation
   - Confirm the subscription to receive alerts

## Monitoring and Troubleshooting

### CloudWatch Logs

State Manager execution logs are stored in:
- Log Group: `/aws/ssm/state-manager-[random-suffix]`
- Log Streams: Individual execution logs

### Common Issues

1. **Association Failures**:
   - Check SSM Agent is running on target instances
   - Verify instances have proper IAM roles
   - Review CloudWatch logs for error details

2. **Compliance Issues**:
   - Ensure target instances have correct tags
   - Verify document parameters are valid
   - Check instance operating system compatibility

3. **Permission Errors**:
   - Verify IAM role has necessary permissions
   - Check trust relationship allows SSM service
   - Ensure managed instances are registered

### Useful Commands

```bash
# Check SSM Agent status
aws ssm describe-instance-information \
    --query 'InstanceInformationList[*].{InstanceId:InstanceId,AgentVersion:AgentVersion,LastPingDateTime:LastPingDateTime}'

# View association execution history
aws ssm describe-association-executions \
    --association-id <association-id> \
    --query 'AssociationExecutions[*].{Status:Status,ExecutionId:ExecutionId,CreatedTime:CreatedTime}'

# Check compliance summary
aws ssm list-compliance-summaries \
    --query 'ComplianceSummaryItems[*].{ComplianceType:ComplianceType,CompliantCount:CompliantCount,NonCompliantCount:NonCompliantCount}'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ssm-state-manager-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ssm-state-manager-stack
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

1. **IAM Permissions**: The solution uses least-privilege IAM policies
2. **Encryption**: CloudWatch logs are encrypted at rest
3. **Network Security**: No additional network resources are created
4. **Access Control**: SNS topics are restricted to authorized publishers

## Cost Optimization

- CloudWatch logs retention can be configured to reduce costs
- SNS notifications are charged per message
- State Manager associations are free for managed instances
- Consider using CloudWatch log insights for analysis instead of exporting logs

## Customization

### Adding Custom Security Configurations

1. Modify the SSM document to include additional security checks
2. Update association parameters for your environment
3. Add additional CloudWatch alarms for specific compliance requirements

### Extending to Multiple Regions

1. Deploy the solution in each required region
2. Configure cross-region CloudWatch dashboards
3. Set up centralized SNS topics for notifications

### Integration with Other Services

1. **AWS Config**: Add Config rules for additional compliance monitoring
2. **Security Hub**: Integrate findings with Security Hub for centralized security management
3. **EventBridge**: Use EventBridge to trigger automated responses to compliance violations

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS Systems Manager documentation
3. Consult CloudFormation/CDK/Terraform provider documentation
4. Check CloudWatch logs for detailed error information

## Additional Resources

- [AWS Systems Manager State Manager Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html)
- [AWS Systems Manager Documents](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-ssm-docs.html)
- [AWS CloudWatch Monitoring](https://docs.aws.amazon.com/cloudwatch/latest/monitoring/)
- [AWS CDK Best Practices](https://docs.aws.amazon.com/cdk/latest/guide/best-practices.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)