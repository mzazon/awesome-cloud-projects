# Infrastructure as Code for Strengthening Authentication Security with IAM and MFA Devices

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Strengthening Authentication Security with IAM and MFA Devices".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrator access or sufficient IAM permissions
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Mobile device or authenticator app for virtual MFA testing
- Understanding of IAM policies and MFA concepts

> **Warning**: MFA enforcement can lock users out if not configured properly. Always test MFA policies with non-administrative users first and ensure you have emergency access procedures.

## Quick Start

### Using CloudFormation

```bash
# Deploy the MFA infrastructure
aws cloudformation create-stack \
    --stack-name mfa-security-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=TestUserName,ParameterValue=test-mfa-user \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name mfa-security-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name mfa-security-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy MfaSecurityStack

# View stack outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy MfaSecurityStack

# View stack outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Configuration Options

### CloudFormation Parameters

- `TestUserName`: Name for the test IAM user (default: test-mfa-user)
- `MfaPolicyName`: Name for the MFA enforcement policy
- `AdminGroupName`: Name for the MFA administrators group
- `EnableCloudTrail`: Whether to enable CloudTrail logging (default: true)

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// For TypeScript
const config = {
  testUserName: 'test-mfa-user',
  mfaPolicyName: 'EnforceMFA-Policy',
  adminGroupName: 'MFAAdmins-Group'
};
```

```python
# For Python
config = {
    "test_user_name": "test-mfa-user",
    "mfa_policy_name": "EnforceMFA-Policy",
    "admin_group_name": "MFAAdmins-Group"
}
```

### Terraform Variables

Customize the deployment by creating a `terraform.tfvars` file:

```hcl
test_user_name = "test-mfa-user"
mfa_policy_name = "EnforceMFA-Policy"
admin_group_name = "MFAAdmins-Group"
enable_cloudtrail = true
cloudwatch_dashboard_name = "MFA-Security-Dashboard"
```

## Post-Deployment Steps

1. **Set up MFA for test user**:
   ```bash
   # Get the QR code for MFA setup (created by deployment)
   aws iam get-virtual-mfa-device \
       --serial-number arn:aws:iam::ACCOUNT-ID:mfa/test-mfa-user
   ```

2. **Test MFA enforcement**:
   - Login to AWS Console with test user credentials
   - Attempt to access services (should be denied without MFA)
   - Set up MFA device using authenticator app
   - Verify full access after MFA authentication

3. **Monitor MFA usage**:
   ```bash
   # View CloudWatch dashboard
   aws cloudwatch get-dashboard \
       --dashboard-name MFA-Security-Dashboard
   
   # Check CloudTrail logs for MFA events
   aws logs describe-log-groups \
       --log-group-name-prefix CloudTrail
   ```

## Validation

### Verify MFA Policy Enforcement

```bash
# Test policy simulation
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::ACCOUNT-ID:user/test-mfa-user \
    --action-names "s3:ListBuckets" \
    --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=false,ContextKeyType=boolean
```

### Check MFA Device Status

```bash
# List MFA devices for user
aws iam list-mfa-devices --user-name test-mfa-user

# Get virtual MFA device details
aws iam list-virtual-mfa-devices \
    --assignment-status Assigned
```

### Monitor Authentication Events

```bash
# Query recent authentication events
aws logs start-query \
    --log-group-name CloudTrail/AWSLogs \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, sourceIPAddress, userIdentity.userName, additionalEventData.MFAUsed | filter eventName = "ConsoleLogin" | sort @timestamp desc'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name mfa-security-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name mfa-security-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy MfaSecurityStack

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

# Follow prompts to confirm resource deletion
```

## Security Considerations

- **Emergency Access**: Ensure you have alternative access methods before implementing MFA enforcement
- **Break-glass Procedures**: Document emergency procedures for MFA device loss or failure
- **Backup Codes**: Generate and securely store backup authentication codes
- **Hardware MFA**: Consider hardware MFA devices for highly privileged accounts
- **Regular Audits**: Monitor MFA usage and compliance regularly

## Troubleshooting

### Common Issues

1. **MFA Lockout**: If locked out, use root account or administrative access to reset MFA
2. **Policy Conflicts**: Review IAM policy evaluation logic and condition conflicts
3. **Time Synchronization**: Ensure authenticator app time is synchronized
4. **CloudTrail Delays**: Authentication events may take 5-15 minutes to appear in logs

### Support Commands

```bash
# Check IAM user status
aws iam get-user --user-name test-mfa-user

# Verify policy attachments
aws iam list-attached-user-policies --user-name test-mfa-user
aws iam list-attached-group-policies --group-name MFAAdmins-Group

# Check CloudTrail status
aws cloudtrail describe-trails
aws cloudtrail get-trail-status --name MFA-Trail
```

## Customization

### Extending MFA Policies

- Modify IAM policies to include additional services or actions
- Implement conditional access based on IP addresses or time
- Add support for hardware MFA devices
- Create role-based MFA requirements

### Enhanced Monitoring

- Add custom CloudWatch metrics for MFA compliance
- Implement automated alerting for policy violations
- Create compliance reports using AWS Config
- Integrate with AWS Security Hub for centralized monitoring

## Cost Optimization

- MFA devices are free to use
- CloudTrail charges apply for event logging
- CloudWatch charges for custom metrics and dashboards
- Consider AWS CloudTrail Insights for advanced analysis

## Compliance

This implementation supports compliance with:
- SOC 2 Type II requirements
- PCI DSS multi-factor authentication requirements
- NIST Cybersecurity Framework guidelines
- AWS Security Best Practices

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- AWS IAM documentation: https://docs.aws.amazon.com/iam/
- AWS MFA documentation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html
- AWS CloudTrail documentation: https://docs.aws.amazon.com/cloudtrail/