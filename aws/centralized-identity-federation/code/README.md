# Infrastructure as Code for Centralized Identity Federation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Identity Federation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive identity federation solution using AWS IAM Identity Center (formerly AWS SSO) that includes:

- IAM Identity Center instance configuration
- External identity provider integration (SAML/OIDC)
- Permission sets with role-based access control
- Multi-account access assignments
- Application integration for single sign-on
- Automated user provisioning with SCIM
- Session and security controls
- Comprehensive audit logging
- High availability and disaster recovery
- CloudWatch monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured with administrative permissions
- AWS Organizations set up with management account and member accounts
- External identity provider (Active Directory, Okta, Azure AD, etc.) for federation
- Appropriate IAM permissions for:
  - AWS Organizations management
  - IAM Identity Center administration
  - CloudTrail management
  - CloudWatch logs and metrics
  - S3 bucket creation and management
- Understanding of SAML/OIDC protocols and identity federation concepts
- Knowledge of IAM roles, policies, and cross-account access patterns

### Cost Considerations

- IAM Identity Center: $15-25/month for typical usage
- CloudTrail: $2.00 per 100,000 events
- S3 storage: Variable based on log retention
- CloudWatch logs: $0.50 per GB ingested

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name identity-federation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ExternalIdPMetadataUrl,ParameterValue=https://your-idp.example.com/metadata \
                 ParameterKey=DevelopmentAccountId,ParameterValue=123456789012 \
                 ParameterKey=ProductionAccountId,ParameterValue=234567890123 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name identity-federation-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name identity-federation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Set required context values
cdk context --set externalIdpMetadataUrl=https://your-idp.example.com/metadata
cdk context --set developmentAccountId=123456789012
cdk context --set productionAccountId=234567890123

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export EXTERNAL_IDP_METADATA_URL=https://your-idp.example.com/metadata
export DEVELOPMENT_ACCOUNT_ID=123456789012
export PRODUCTION_ACCOUNT_ID=234567890123

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
external_idp_metadata_url = "https://your-idp.example.com/metadata"
development_account_id = "123456789012"
production_account_id = "234567890123"
aws_region = "us-east-1"
environment = "production"
project_name = "identity-federation"
EOF

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export EXTERNAL_IDP_METADATA_URL=https://your-idp.example.com/metadata
export DEVELOPMENT_ACCOUNT_ID=123456789012
export PRODUCTION_ACCOUNT_ID=234567890123
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and wait for resources to be ready
```

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `external_idp_metadata_url` | SAML metadata URL for your identity provider | `https://your-idp.example.com/metadata` |
| `development_account_id` | AWS Account ID for development environment | `123456789012` |
| `production_account_id` | AWS Account ID for production environment | `234567890123` |
| `aws_region` | AWS region for deployment | `us-east-1` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment` | Environment name (dev, staging, prod) | `production` |
| `project_name` | Project name for resource naming | `identity-federation` |
| `session_duration` | Maximum session duration | `PT8H` |
| `idle_timeout` | Session idle timeout | `PT1H` |
| `require_mfa` | Require multi-factor authentication | `true` |

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual configuration steps:

### 1. Configure Identity Provider

```bash
# Get the IAM Identity Center SAML metadata
aws sso-admin describe-instance --instance-arn <SSO_INSTANCE_ARN>

# Configure your external IdP with:
# - SSO ACS URL: https://<region>.signin.aws/saml
# - Entity ID: https://<region>.signin.aws/saml/metadata/<instance-id>
# - Attribute mappings as defined in the template
```

### 2. Create User Groups

```bash
# Create groups in IAM Identity Center or sync from external IdP
aws identitystore create-group \
    --identity-store-id <IDENTITY_STORE_ID> \
    --display-name "Developers" \
    --description "Development team members"

aws identitystore create-group \
    --identity-store-id <IDENTITY_STORE_ID> \
    --display-name "Administrators" \
    --description "System administrators"

aws identitystore create-group \
    --identity-store-id <IDENTITY_STORE_ID> \
    --display-name "Business-Users" \
    --description "Business users with read-only access"
```

### 3. Assign Users to Groups

```bash
# Add users to appropriate groups
aws identitystore create-group-membership \
    --identity-store-id <IDENTITY_STORE_ID> \
    --group-id <GROUP_ID> \
    --member-id <USER_ID>
```

### 4. Test Authentication

1. Access the AWS access portal URL (provided in outputs)
2. Sign in with your external identity provider credentials
3. Verify access to assigned AWS accounts and applications
4. Test permission boundaries and access controls

## Validation

### Verify Infrastructure Deployment

```bash
# Check IAM Identity Center status
aws sso-admin list-instances

# Verify permission sets
aws sso-admin list-permission-sets --instance-arn <SSO_INSTANCE_ARN>

# Check account assignments
aws sso-admin list-account-assignments \
    --instance-arn <SSO_INSTANCE_ARN> \
    --account-id <ACCOUNT_ID>

# Verify audit logging
aws logs describe-log-groups --log-group-name-prefix "/aws/sso"

# Check CloudWatch dashboard
aws cloudwatch list-dashboards
```

### Test Authentication Flow

```bash
# Test SAML metadata accessibility
curl -s "<EXTERNAL_IDP_METADATA_URL>" | head -10

# Verify CloudTrail logging
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail" \
    --filter-pattern "{ $.eventSource = \"sso.amazonaws.com\" }"
```

## Monitoring and Alerts

The implementation includes comprehensive monitoring:

- **CloudWatch Dashboard**: Identity federation metrics and sign-in activity
- **CloudWatch Alarms**: Service health monitoring and failure alerts
- **CloudTrail Logging**: Complete audit trail of all identity operations
- **CloudWatch Logs**: Detailed SSO audit logs with retention policies

### Key Metrics to Monitor

- Sign-in success/failure rates
- Session duration patterns
- Permission set usage
- Account access patterns
- Failed authentication attempts
- Geographic access patterns

## Security Considerations

### Implemented Security Controls

- **Multi-Factor Authentication**: Required for all users
- **Session Timeouts**: Configurable session and idle timeouts
- **Trusted Device Management**: Device registration and trust levels
- **Permission Set Isolation**: Least privilege access patterns
- **Audit Logging**: Comprehensive logging for compliance
- **Cross-Account Access**: Secure role assumption patterns

### Security Best Practices

1. **Regular Access Reviews**: Periodically review user access and permissions
2. **Conditional Access**: Implement location and device-based access controls
3. **Emergency Access**: Maintain break-glass administrative access
4. **Monitoring**: Set up alerts for suspicious authentication patterns
5. **Backup Access**: Ensure alternative authentication methods for emergencies

## Troubleshooting

### Common Issues

**SAML Configuration Errors**
```bash
# Verify SAML metadata
curl -s "<EXTERNAL_IDP_METADATA_URL>"

# Check attribute mappings
aws sso-admin describe-identity-provider \
    --instance-arn <SSO_INSTANCE_ARN> \
    --identity-provider-arn <IDP_ARN>
```

**Permission Set Issues**
```bash
# Check permission set provisioning status
aws sso-admin describe-permission-set-provisioning-status \
    --instance-arn <SSO_INSTANCE_ARN> \
    --provision-request-id <REQUEST_ID>

# Verify policies attached to permission sets
aws sso-admin list-managed-policies-in-permission-set \
    --instance-arn <SSO_INSTANCE_ARN> \
    --permission-set-arn <PERMISSION_SET_ARN>
```

**Authentication Failures**
```bash
# Check CloudWatch logs for errors
aws logs filter-log-events \
    --log-group-name "/aws/sso/audit-logs" \
    --filter-pattern "ERROR"

# Review CloudTrail for failed events
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail" \
    --filter-pattern "{ $.errorCode exists }"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name identity-federation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name identity-federation-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name identity-federation-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm resource deletion when prompted
# The script will handle dependencies and cleanup order
```

### Manual Cleanup (if needed)

```bash
# Clean up any remaining S3 buckets
aws s3 ls | grep identity-audit-logs
aws s3 rm s3://bucket-name --recursive
aws s3 rb s3://bucket-name

# Remove any remaining CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/sso"
aws logs delete-log-group --log-group-name "/aws/sso/audit-logs"

# Clean up any remaining CloudTrail trails
aws cloudtrail describe-trails --trail-name-list identity-federation-audit-trail
aws cloudtrail delete-trail --name identity-federation-audit-trail
```

## Customization

### Adding Additional Permission Sets

```bash
# Create new permission set
aws sso-admin create-permission-set \
    --instance-arn <SSO_INSTANCE_ARN> \
    --name "CustomRole" \
    --description "Custom role for specific use case" \
    --session-duration "PT4H"

# Attach policies and create assignments as needed
```

### Integrating Additional Applications

```bash
# Add new application
aws sso-admin create-application \
    --instance-arn <SSO_INSTANCE_ARN> \
    --name "NewBusinessApp" \
    --description "Additional business application"

# Configure SAML attributes and assignments
```

### Modifying Session Controls

Edit the session configuration parameters in your chosen IaC template to adjust:
- Session duration limits
- Idle timeout values
- MFA requirements
- Device trust settings

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../identity-federation-aws-sso.md)
2. Consult the [AWS IAM Identity Center documentation](https://docs.aws.amazon.com/singlesignon/)
3. Check the [AWS Organizations documentation](https://docs.aws.amazon.com/organizations/)
4. Review CloudWatch logs and CloudTrail events for detailed error information

## Contributing

When modifying this infrastructure code:

1. Test changes in a non-production environment first
2. Follow AWS security best practices
3. Update documentation for any parameter changes
4. Validate that all IaC implementations remain synchronized
5. Test both deployment and cleanup procedures