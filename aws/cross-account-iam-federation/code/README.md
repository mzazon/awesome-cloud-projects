# Infrastructure as Code for Cross-Account IAM Role Federation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account IAM Role Federation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive cross-account IAM role federation architecture that includes:

- Master cross-account role in security account with SAML federation support
- Production account role with strict security controls and external ID validation
- Development account role with expanded permissions and IP restrictions
- Session tagging for attribute-based access control (ABAC)
- Comprehensive audit trail with CloudTrail
- Automated role validation using Lambda functions
- Advanced trust policies with MFA enforcement

## Prerequisites

### AWS Account Requirements
- **Security Account**: Central identity management account
- **Production Account**: Business-critical resources account
- **Development Account**: Development and testing resources account
- AWS Organizations configured with cross-account trust (recommended)

### Access Requirements
- AWS CLI v2 installed and configured
- Administrative permissions in all three accounts
- IAM Identity Center configured (for SAML federation)
- External identity provider configured (SAML/OIDC)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Cross-account deployment capabilities

#### CDK (TypeScript)
- Node.js 16.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript compiler (`npm install -g typescript`)

#### CDK (Python)
- Python 3.8 or later
- AWS CDK CLI installed (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or later
- AWS provider 5.0 or later
- Multiple AWS provider configurations for cross-account deployment

### Estimated Costs
- CloudTrail logging: $2-10/month (depending on API call volume)
- Lambda execution: $1-5/month (minimal usage)
- S3 storage for audit logs: $1-20/month (depending on retention)
- Config rules (if implemented): $2-5/month per account

## Quick Start

### Using CloudFormation

Deploy to each account in sequence:

```bash
# 1. Deploy to Security Account (Master Role)
aws cloudformation create-stack \
    --stack-name cross-account-security-master \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AccountType,ParameterValue=security \
                ParameterKey=ProductionAccountId,ParameterValue=222222222222 \
                ParameterKey=DevelopmentAccountId,ParameterValue=333333333333 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# 2. Deploy to Production Account
aws cloudformation create-stack \
    --stack-name cross-account-production-role \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AccountType,ParameterValue=production \
                ParameterKey=SecurityAccountId,ParameterValue=111111111111 \
                ParameterKey=ProductionExternalId,ParameterValue=your-prod-external-id \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# 3. Deploy to Development Account
aws cloudformation create-stack \
    --stack-name cross-account-development-role \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AccountType,ParameterValue=development \
                ParameterKey=SecurityAccountId,ParameterValue=111111111111 \
                ParameterKey=DevelopmentExternalId,ParameterValue=your-dev-external-id \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment context
export SECURITY_ACCOUNT_ID="111111111111"
export PRODUCTION_ACCOUNT_ID="222222222222"
export DEVELOPMENT_ACCOUNT_ID="333333333333"
export PROD_EXTERNAL_ID="$(openssl rand -hex 16)"
export DEV_EXTERNAL_ID="$(openssl rand -hex 16)"

# Bootstrap CDK in all accounts (if not already done)
cdk bootstrap aws://$SECURITY_ACCOUNT_ID/us-east-1
cdk bootstrap aws://$PRODUCTION_ACCOUNT_ID/us-east-1
cdk bootstrap aws://$DEVELOPMENT_ACCOUNT_ID/us-east-1

# Deploy to all accounts
cdk deploy --all --require-approval never
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment context
export SECURITY_ACCOUNT_ID="111111111111"
export PRODUCTION_ACCOUNT_ID="222222222222"
export DEVELOPMENT_ACCOUNT_ID="333333333333"
export PROD_EXTERNAL_ID="$(openssl rand -hex 16)"
export DEV_EXTERNAL_ID="$(openssl rand -hex 16)"

# Bootstrap CDK in all accounts (if not already done)
cdk bootstrap aws://$SECURITY_ACCOUNT_ID/us-east-1
cdk bootstrap aws://$PRODUCTION_ACCOUNT_ID/us-east-1
cdk bootstrap aws://$DEVELOPMENT_ACCOUNT_ID/us-east-1

# Deploy to all accounts
cdk deploy --all --require-approval never
```

### Using Terraform

```bash
cd terraform/

# Generate external IDs
export PROD_EXTERNAL_ID="$(openssl rand -hex 16)"
export DEV_EXTERNAL_ID="$(openssl rand -hex 16)"

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
security_account_id    = "111111111111"
production_account_id  = "222222222222"
development_account_id = "333333333333"
prod_external_id      = "$PROD_EXTERNAL_ID"
dev_external_id       = "$DEV_EXTERNAL_ID"
aws_region            = "us-east-1"

# Optional customizations
allowed_ip_ranges = ["203.0.113.0/24", "198.51.100.0/24"]
max_session_duration_hours = 1
enable_audit_trail = true
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export SECURITY_ACCOUNT_ID="111111111111"
export PRODUCTION_ACCOUNT_ID="222222222222"
export DEVELOPMENT_ACCOUNT_ID="333333333333"

# Deploy the solution
./scripts/deploy.sh

# The script will:
# 1. Generate external IDs automatically
# 2. Deploy roles in the correct sequence
# 3. Set up audit trail and monitoring
# 4. Configure session tagging
# 5. Deploy validation Lambda function
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `AccountType` | Type of account (security/production/development) | - | Yes |
| `SecurityAccountId` | ID of the central security account | - | Yes |
| `ProductionAccountId` | ID of the production account | - | Conditional |
| `DevelopmentAccountId` | ID of the development account | - | Conditional |
| `ProductionExternalId` | External ID for production role | - | Conditional |
| `DevelopmentExternalId` | External ID for development role | - | Conditional |
| `AllowedIPRanges` | IP ranges for conditional access | - | No |
| `MaxSessionDuration` | Maximum session duration in seconds | 3600 | No |

### CDK Context Variables

Configure in `cdk.json` or via environment variables:

```json
{
  "context": {
    "security-account-id": "111111111111",
    "production-account-id": "222222222222", 
    "development-account-id": "333333333333",
    "prod-external-id": "generated-external-id",
    "dev-external-id": "generated-external-id",
    "allowed-ip-ranges": ["203.0.113.0/24"],
    "enable-audit-trail": true
  }
}
```

### Terraform Variables

Key variables in `variables.tf`:

```hcl
variable "security_account_id" {
  description = "AWS Account ID for the security/identity account"
  type        = string
}

variable "production_account_id" {
  description = "AWS Account ID for the production account"
  type        = string
}

variable "development_account_id" {
  description = "AWS Account ID for the development account" 
  type        = string
}

variable "prod_external_id" {
  description = "External ID for production account role"
  type        = string
  sensitive   = true
}

variable "dev_external_id" {
  description = "External ID for development account role"
  type        = string
  sensitive   = true
}
```

## Post-Deployment Configuration

### 1. Configure SAML Identity Provider

After deploying the master role, configure your SAML identity provider:

```bash
# Create SAML identity provider (if not exists)
aws iam create-saml-provider \
    --name CorporateIdP \
    --saml-metadata-document file://saml-metadata.xml
```

### 2. Test Cross-Account Access

```bash
# Test role assumption with generated external IDs
aws sts assume-role \
    --role-arn "arn:aws:iam::PRODUCTION_ACCOUNT:role/CrossAccount-ProductionAccess" \
    --role-session-name "TestSession" \
    --external-id "YOUR_PROD_EXTERNAL_ID"
```

### 3. Configure Session Tags

Update your identity provider to include session tags:

```xml
<!-- Example SAML assertion attributes -->
<saml:Attribute Name="https://aws.amazon.com/SAML/Attributes/PrincipalTag:Department">
    <saml:AttributeValue>Engineering</saml:AttributeValue>
</saml:Attribute>
<saml:Attribute Name="https://aws.amazon.com/SAML/Attributes/PrincipalTag:Project">
    <saml:AttributeValue>CrossAccountDemo</saml:AttributeValue>
</saml:Attribute>
```

## Monitoring and Validation

### Check Deployment Status

```bash
# CloudFormation
aws cloudformation describe-stacks \
    --stack-name cross-account-security-master \
    --query 'Stacks[0].StackStatus'

# CDK
cdk list

# Terraform
terraform state list
```

### Validate Role Configuration

```bash
# Invoke the validation Lambda function
aws lambda invoke \
    --function-name CrossAccountRoleValidator \
    --payload '{}' \
    response.json && cat response.json
```

### Monitor Audit Trail

```bash
# Check recent cross-account activities
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail/cross-account-audit" \
    --filter-pattern '{ $.eventName = "AssumeRole" }' \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Security Considerations

### External ID Management

- **Production**: Store external IDs in AWS Secrets Manager
- **Development**: Rotate external IDs regularly (monthly recommended)
- **Automation**: Use Lambda functions for automated rotation

### Access Controls

- **MFA Enforcement**: All cross-account access requires MFA
- **IP Restrictions**: Development access restricted to corporate IP ranges
- **Session Duration**: Limited session duration for security (1-2 hours max)
- **Audit Logging**: Comprehensive CloudTrail logging with log file validation

### Best Practices

1. **Principle of Least Privilege**: Roles grant minimum required permissions
2. **Defense in Depth**: Multiple validation layers (external ID, MFA, IP)
3. **Audit Trail**: Complete logging of all cross-account activities
4. **Automated Validation**: Continuous compliance monitoring
5. **Regular Review**: Quarterly access review and external ID rotation

## Troubleshooting

### Common Issues

#### Access Denied Errors

```bash
# Check role trust policy
aws iam get-role --role-name CrossAccount-ProductionAccess

# Verify external ID
aws sts get-caller-identity

# Check MFA status
aws sts get-session-token --duration-seconds 3600
```

#### Session Tag Issues

```bash
# Verify session tags are being passed correctly
aws sts assume-role \
    --role-arn "arn:aws:iam::ACCOUNT:role/ROLE_NAME" \
    --role-session-name "TestSession" \
    --tags Key=Department,Value=Engineering \
    --query 'AssumedRoleUser.Arn'
```

#### CloudTrail Logging Issues

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name CrossAccountAuditTrail

# Verify S3 bucket permissions
aws s3api get-bucket-policy --bucket cross-account-audit-trail
```

### Support Resources

- [AWS IAM Cross-Account Access Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)
- [AWS Session Tags Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html)
- [AWS External ID Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html)

## Cleanup

### Using CloudFormation

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name cross-account-development-role
aws cloudformation delete-stack --stack-name cross-account-production-role
aws cloudformation delete-stack --stack-name cross-account-security-master
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --all
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

## Customization Examples

### Adding New Accounts

To add additional accounts (e.g., staging):

1. **Terraform**: Add new variables and provider configurations
2. **CDK**: Extend the stack to include staging account resources
3. **CloudFormation**: Create additional parameter sets for staging deployment
4. **Scripts**: Update deploy.sh to include staging account deployment

### Custom Permission Sets

Modify the IAM policies to include additional AWS services:

```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:Query"
  ],
  "Resource": "arn:aws:dynamodb:*:*:table/shared-*"
}
```

### Advanced Conditional Access

Add time-based restrictions:

```json
{
  "DateGreaterThan": {
    "aws:CurrentTime": "2024-01-01T00:00:00Z"
  },
  "DateLessThan": {
    "aws:CurrentTime": "2024-12-31T23:59:59Z"
  }
}
```

## Advanced Features

### Automated External ID Rotation

The solution includes Lambda functions for automated external ID rotation:

```bash
# Trigger external ID rotation
aws lambda invoke \
    --function-name ExternalIdRotationFunction \
    --payload '{"account": "production"}' \
    response.json
```

### Integration with AWS SSO

For organizations using AWS SSO:

```bash
# Configure permission sets for cross-account access
aws sso-admin create-permission-set \
    --instance-arn "arn:aws:sso:::instance/ssoins-example" \
    --name CrossAccountAccess \
    --description "Cross-account access permission set"
```

### Cost Optimization

Monitor and optimize costs:

- Use CloudWatch to monitor Lambda execution costs
- Implement S3 lifecycle policies for CloudTrail logs
- Set up billing alerts for unexpected costs
- Regular review of unused roles and permissions

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service quotas and limits
3. Verify account permissions and trust relationships
4. Consult the original recipe documentation
5. Reference AWS support documentation

## Contributing

When modifying this infrastructure code:

1. Follow AWS security best practices
2. Test changes in non-production environments
3. Update documentation accordingly
4. Validate with multiple deployment methods
5. Consider backward compatibility

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production usage.