# Infrastructure as Code for Authenticating Users with Cognito User Pools

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Authenticating Users with Cognito User Pools".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for Cognito, IAM, SES, and SNS
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.5+ installed
- Appropriate IAM permissions for resource creation:
  - cognito-idp:*
  - iam:CreateRole, iam:AttachRolePolicy, iam:GetRole
  - ses:* (for email configuration)
  - sns:* (for SMS configuration)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cognito-user-pools-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=UserPoolName,ParameterValue=ecommerce-users \
                 ParameterKey=DomainPrefix,ParameterValue=ecommerce-auth-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name cognito-user-pools-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name cognito-user-pools-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

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
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
cat deployment-outputs.json
```

## Configuration Options

### CloudFormation Parameters
- `UserPoolName`: Name for the Cognito User Pool (default: ecommerce-users)
- `ClientName`: Name for the User Pool Client (default: ecommerce-web-client)
- `DomainPrefix`: Prefix for the hosted UI domain (must be unique)
- `EmailSourceArn`: SES identity ARN for email delivery (optional)
- `EnableAdvancedSecurity`: Enable advanced security features (default: true)

### CDK Configuration
Both TypeScript and Python CDK implementations support:
- Environment-specific configurations through context variables
- Custom user pool settings via constructor parameters
- Optional social identity provider configurations
- Configurable password policies and MFA settings

### Terraform Variables
- `user_pool_name`: Name for the Cognito User Pool
- `client_name`: Name for the User Pool Client
- `domain_prefix`: Prefix for the hosted UI domain
- `aws_region`: AWS region for deployment
- `enable_mfa`: Enable multi-factor authentication (default: true)
- `password_minimum_length`: Minimum password length (default: 12)

## Deployment Outputs

All implementations provide the following outputs:

- **UserPoolId**: The ID of the created Cognito User Pool
- **UserPoolClientId**: The client ID for application integration
- **UserPoolDomain**: The hosted UI domain URL
- **LoginUrl**: Pre-configured login URL for testing
- **LogoutUrl**: Pre-configured logout URL for testing
- **HostedUIUrl**: Base hosted UI URL

## Testing the Deployment

After deployment, you can test the authentication flow:

1. **Access the Hosted UI**:
   ```bash
   # Open the login URL from outputs in a browser
   echo "Login URL: $(terraform output -raw login_url)"
   ```

2. **Test with CLI**:
   ```bash
   # Create a test user
   aws cognito-idp admin-create-user \
       --user-pool-id $(terraform output -raw user_pool_id) \
       --username test@example.com \
       --user-attributes Name=email,Value=test@example.com \
       --temporary-password "TempPass123!" \
       --message-action SUPPRESS
   ```

3. **Verify User Groups**:
   ```bash
   # List available groups
   aws cognito-idp list-groups \
       --user-pool-id $(terraform output -raw user_pool_id)
   ```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cognito-user-pools-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cognito-user-pools-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Customization

### Adding Social Identity Providers
To add Google or Facebook authentication:

1. **CloudFormation**: Update the `IdentityProviders` section in the template
2. **CDK**: Add identity provider constructs to the stack
3. **Terraform**: Use the `aws_cognito_identity_provider` resource
4. **Scripts**: Add CLI commands to create identity providers

### Custom Email Templates
Customize verification and invitation emails by:

1. Modifying the `VerificationMessageTemplate` configuration
2. Setting up custom email templates through SES
3. Configuring custom domains for email delivery

### Lambda Triggers
Integrate Lambda functions for custom authentication flows:

1. Create Lambda functions for pre-sign-up, post-confirmation, etc.
2. Configure trigger associations in the user pool
3. Set appropriate IAM permissions for Lambda execution

## Security Considerations

This implementation includes several security best practices:

- **Strong Password Policies**: 12-character minimum with complexity requirements
- **Advanced Security Features**: Adaptive authentication and threat detection
- **Multi-Factor Authentication**: Support for TOTP and SMS
- **Device Tracking**: Challenge users on new devices
- **Encryption**: All data encrypted in transit and at rest
- **Least Privilege IAM**: Minimal required permissions for service roles

## Cost Optimization

- First 50,000 Monthly Active Users (MAUs) are free
- SMS costs apply for MFA and verification messages
- Advanced security features may incur additional charges
- Monitor usage through AWS Cost Explorer

## Troubleshooting

### Common Issues

1. **Domain Already Exists**: Ensure the domain prefix is unique across all AWS accounts
2. **SES Not Configured**: Verify SES identity and move out of sandbox if needed
3. **SNS Permissions**: Ensure the SNS role has proper permissions for SMS delivery
4. **Client Secret**: Note that client secrets are only available for confidential clients

### Validation Commands

```bash
# Check user pool status
aws cognito-idp describe-user-pool --user-pool-id <USER_POOL_ID>

# Verify domain availability
aws cognito-idp describe-user-pool-domain --domain <DOMAIN_PREFIX>

# List users in a group
aws cognito-idp list-users-in-group \
    --user-pool-id <USER_POOL_ID> \
    --group-name <GROUP_NAME>
```

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../user-authentication-cognito-user-pools.md)
2. Check the [AWS Cognito documentation](https://docs.aws.amazon.com/cognito/)
3. Validate IAM permissions and service limits
4. Review CloudWatch logs for authentication events

## Next Steps

After successful deployment, consider:

1. Integrating with your web or mobile application using AWS SDKs
2. Setting up custom domains for the hosted UI
3. Configuring additional identity providers (Google, Facebook, SAML)
4. Implementing Lambda triggers for custom business logic
5. Setting up monitoring and alerting for authentication metrics