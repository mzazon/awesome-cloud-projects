# Infrastructure as Code for Cross-Account Compliance Monitoring with Security Hub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account Compliance Monitoring with Security Hub".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Systems Manager, Security Hub, CloudTrail, and IAM
- AWS Organizations setup with multiple member accounts (recommended)
- At least 2 AWS accounts (1 security hub administrator, 1+ member accounts)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Important**: This recipe requires cross-account access. Ensure you have sufficient permissions to create IAM roles and policies across accounts.

## Architecture Overview

This solution creates:
- Security Hub as organization administrator for centralized findings
- Cross-account IAM roles for compliance data access
- Systems Manager compliance monitoring across member accounts
- CloudTrail for comprehensive audit logging
- Lambda functions for automated compliance processing
- EventBridge rules for real-time event-driven automation
- Custom compliance rules and organizational policies

## Quick Start

### Using CloudFormation

```bash
# Deploy in Security Hub administrator account
aws cloudformation create-stack \
    --stack-name compliance-monitoring-hub \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=MemberAccount1,ParameterValue=123456789013 \
                 ParameterKey=MemberAccount2,ParameterValue=123456789014 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Deploy member account roles (repeat for each member account)
aws cloudformation create-stack \
    --stack-name compliance-monitoring-member \
    --template-body file://member-account-template.yaml \
    --parameters ParameterKey=SecurityAccountId,ParameterValue=123456789012 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment
export SECURITY_ACCOUNT_ID="123456789012"
export MEMBER_ACCOUNT_1="123456789013"
export MEMBER_ACCOUNT_2="123456789014"
export CDK_DEFAULT_REGION="us-east-1"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the solution
cdk deploy ComplianceMonitoringStack

# Deploy to member accounts
cdk deploy MemberAccountStack --context account=${MEMBER_ACCOUNT_1}
cdk deploy MemberAccountStack --context account=${MEMBER_ACCOUNT_2}
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export SECURITY_ACCOUNT_ID="123456789012"
export MEMBER_ACCOUNT_1="123456789013"
export MEMBER_ACCOUNT_2="123456789014"
export CDK_DEFAULT_REGION="us-east-1"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the solution
cdk deploy ComplianceMonitoringStack

# Deploy to member accounts
cdk deploy MemberAccountStack --context account=${MEMBER_ACCOUNT_1}
cdk deploy MemberAccountStack --context account=${MEMBER_ACCOUNT_2}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
security_account_id = "123456789012"
member_accounts = [
  "123456789013",
  "123456789014"
]
aws_region = "us-east-1"
environment = "production"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export SECURITY_ACCOUNT_ID="123456789012"
export MEMBER_ACCOUNT_1="123456789013"
export MEMBER_ACCOUNT_2="123456789014"
export AWS_REGION="us-east-1"

# Deploy the solution
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Configuration Options

### CloudFormation Parameters

- `SecurityAccountId`: AWS account ID for Security Hub administrator
- `MemberAccount1`: First member account ID
- `MemberAccount2`: Second member account ID
- `ComplianceRolePrefix`: Prefix for cross-account role names
- `Environment`: Environment tag (dev/staging/prod)

### CDK Context Variables

- `securityAccountId`: Security Hub administrator account
- `memberAccounts`: Array of member account IDs
- `environment`: Deployment environment
- `complianceRolePrefix`: Cross-account role naming prefix

### Terraform Variables

- `security_account_id`: Security Hub administrator account
- `member_accounts`: List of member account IDs
- `aws_region`: AWS region for deployment
- `environment`: Environment identifier
- `compliance_role_prefix`: Role naming prefix
- `enable_custom_compliance`: Enable custom compliance rules

## Post-Deployment Configuration

### Accept Security Hub Invitations

After deployment, member accounts must accept Security Hub invitations:

```bash
# Run in each member account
aws securityhub accept-administrator-invitation \
    --administrator-id ${SECURITY_ACCOUNT_ID} \
    --invitation-id $(aws securityhub list-invitations \
        --query 'Invitations[0].InvitationId' --output text)
```

### Enable Systems Manager Associations

Configure Systems Manager compliance associations in member accounts:

```bash
# Run in each member account
aws ssm create-association \
    --name "AWS-RunPatchBaseline" \
    --targets "Key=tag:Environment,Values=Production" \
    --parameters "Operation=Scan" \
    --schedule-expression "rate(1 day)"
```

### Verify Deployment

```bash
# Check Security Hub status
aws securityhub describe-hub

# List member accounts
aws securityhub list-members

# Verify EventBridge rules
aws events list-rules --name-prefix "ComplianceMonitoring"

# Test Lambda function
aws lambda invoke \
    --function-name ComplianceAutomation-* \
    --payload '{"source":"test","detail":{"eventName":"PutComplianceItems"}}' \
    response.json
```

## Monitoring and Validation

### Security Hub Dashboard

Access the Security Hub console to view:
- Compliance findings across all member accounts
- Security standards compliance scores
- Failed controls and remediation guidance
- Trends and insights

### CloudWatch Metrics

Monitor key metrics:
- Lambda function execution count and duration
- EventBridge rule invocations
- Systems Manager compliance item counts
- Security Hub finding import rates

### Custom Compliance Checks

The solution includes custom compliance rules for:
- Required resource tagging policies
- Configuration drift detection
- Organizational security policies
- Operational best practices

## Troubleshooting

### Common Issues

1. **Cross-Account Role Assumption Failures**
   ```bash
   # Verify role trust policy
   aws iam get-role --role-name ComplianceMonitoringRole-*
   
   # Check external ID configuration
   aws sts assume-role \
       --role-arn "arn:aws:iam::ACCOUNT:role/ROLE-NAME" \
       --role-session-name "test" \
       --external-id "EXTERNAL-ID"
   ```

2. **Security Hub Integration Issues**
   ```bash
   # Verify Security Hub is enabled
   aws securityhub describe-hub
   
   # Check member account status
   aws securityhub list-members
   
   # Verify findings import
   aws securityhub get-findings --max-results 10
   ```

3. **EventBridge Rule Not Triggering**
   ```bash
   # Check rule status
   aws events describe-rule --name ComplianceMonitoringRule-*
   
   # Verify Lambda permissions
   aws lambda get-policy --function-name ComplianceAutomation-*
   ```

### Debug Commands

```bash
# Check CloudTrail logs
aws logs describe-log-groups --log-group-name-prefix "/aws/cloudtrail"

# Review Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/ComplianceAutomation"

# Verify Systems Manager compliance
aws ssm list-compliance-summaries --max-results 10
```

## Cleanup

### Using CloudFormation

```bash
# Delete member account stacks
aws cloudformation delete-stack --stack-name compliance-monitoring-member

# Delete main stack
aws cloudformation delete-stack --stack-name compliance-monitoring-hub
```

### Using CDK

```bash
# Destroy member account stacks
cdk destroy MemberAccountStack --context account=${MEMBER_ACCOUNT_1}
cdk destroy MemberAccountStack --context account=${MEMBER_ACCOUNT_2}

# Destroy main stack
cdk destroy ComplianceMonitoringStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Steps

1. **Empty S3 buckets** before deletion:
   ```bash
   aws s3 rm s3://compliance-audit-trail-* --recursive
   ```

2. **Disable Security Hub** organization integration:
   ```bash
   aws securityhub disable-organization-admin-account
   ```

3. **Remove Systems Manager associations**:
   ```bash
   aws ssm delete-association --association-id "ASSOCIATION-ID"
   ```

## Cost Optimization

### Estimated Monthly Costs

- Security Hub: $0.0010 per finding (first 10,000 free)
- CloudTrail: $2.00 per 100,000 events
- Lambda: $0.20 per 1M requests + compute time
- Systems Manager: No additional charges for compliance
- EventBridge: $1.00 per million events

### Cost Reduction Tips

1. Use CloudTrail data events selectively
2. Implement Lambda function timeout optimization
3. Configure EventBridge filtering to reduce noise
4. Use S3 Intelligent Tiering for CloudTrail logs
5. Monitor Security Hub finding volumes

## Security Considerations

- Cross-account roles use external ID for additional security
- All data encrypted in transit and at rest
- Least privilege IAM policies implemented
- CloudTrail provides comprehensive audit logging
- Security Hub findings include remediation guidance

## Support and Resources

- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [Systems Manager Compliance Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-compliance.html)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [Cross-Account IAM Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)

For issues with this infrastructure code, refer to the original recipe documentation or contact your AWS support team.