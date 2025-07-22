# Infrastructure as Code for Enterprise Authentication with Amplify

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Authentication with Amplify".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Amplify, Cognito, and IAM resource creation
- Node.js 14+ and npm installed (for CDK TypeScript and Amplify development)
- Python 3.8+ and pip installed (for CDK Python)
- Terraform 1.0+ installed (for Terraform implementation)
- Access to external identity provider (SAML or OIDC) with admin privileges
- Basic understanding of authentication protocols and AWS security concepts

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name enterprise-auth-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=enterprise-auth-demo \
                 ParameterKey=SAMLMetadataURL,ParameterValue=https://your-idp.example.com/metadata \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name enterprise-auth-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name enterprise-auth-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required environment variables
export SAML_METADATA_URL="https://your-idp.example.com/metadata"
export APP_NAME="enterprise-auth-demo"

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required environment variables
export SAML_METADATA_URL="https://your-idp.example.com/metadata"
export APP_NAME="enterprise-auth-demo"

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
app_name = "enterprise-auth-demo"
saml_metadata_url = "https://your-idp.example.com/metadata"
aws_region = "us-east-1"
environment = "dev"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export SAML_METADATA_URL="https://your-idp.example.com/metadata"
export APP_NAME="enterprise-auth-demo"
export AWS_REGION="us-east-1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important configuration details
# Save these for configuring your external identity provider
```

## Configuration Requirements

### External Identity Provider Setup

After deploying the infrastructure, configure your SAML identity provider with these details (provided in deployment outputs):

1. **Entity ID**: `urn:amazon:cognito:sp:{USER_POOL_ID}`
2. **Reply URL**: `https://{COGNITO_DOMAIN}/saml2/idpresponse`
3. **Sign-on URL**: `https://{COGNITO_DOMAIN}/login?response_type=code&client_id={APP_CLIENT_ID}&redirect_uri={CALLBACK_URL}`

### Required SAML Attribute Mappings

Configure your identity provider to send these attributes:

- **Email**: `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress`
- **Given Name**: `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname`
- **Family Name**: `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname`

### Sample Application Setup

After infrastructure deployment, set up the sample React application:

```bash
# Create React application
npx create-react-app frontend --template typescript
cd frontend

# Install Amplify libraries
npm install aws-amplify @aws-amplify/ui-react

# Configure Amplify with outputs from infrastructure deployment
# (Replace values with actual outputs from your deployment)
cat > src/aws-exports.js << EOF
const awsconfig = {
  Auth: {
    region: '{AWS_REGION}',
    userPoolId: '{USER_POOL_ID}',
    userPoolWebClientId: '{APP_CLIENT_ID}',
    oauth: {
      domain: '{COGNITO_DOMAIN}',
      scope: ['openid', 'email', 'profile'],
      redirectSignIn: 'http://localhost:3000/auth/callback',
      redirectSignOut: 'http://localhost:3000/auth/logout',
      responseType: 'code'
    }
  }
};
export default awsconfig;
EOF

# Start the application
npm start
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Cognito User Pool
aws cognito-idp describe-user-pool --user-pool-id {USER_POOL_ID}

# Verify identity provider configuration
aws cognito-idp list-identity-providers --user-pool-id {USER_POOL_ID}

# Test authentication domain
curl -I https://{COGNITO_DOMAIN}/login

# Verify OAuth endpoints
curl -s https://{COGNITO_DOMAIN}/.well-known/openid_configuration
```

### Test Authentication Flow

1. Navigate to your application URL (typically `http://localhost:3000`)
2. Click the sign-in button
3. Verify that both enterprise SSO and Cognito authentication options are available
4. Test the enterprise SSO flow with your corporate credentials
5. Verify successful authentication and token receipt

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name enterprise-auth-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name enterprise-auth-stack
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy --require-approval never

# Clean up CDK bootstrap (optional, only if not used by other projects)
# cdk bootstrap --toolkit-stack-name CDKToolkit --termination-protection false
# aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -auto-approve

# Clean up Terraform state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# and will clean up all created infrastructure components
```

## Customization

### Available Parameters/Variables

Each implementation supports customization through variables:

- **app_name**: Name prefix for all resources (default: "enterprise-auth")
- **environment**: Environment name (dev, staging, prod)
- **aws_region**: AWS region for deployment
- **saml_metadata_url**: URL of your SAML identity provider metadata
- **callback_urls**: List of allowed callback URLs for OAuth
- **logout_urls**: List of allowed logout URLs for OAuth
- **identity_provider_name**: Name for the SAML identity provider
- **enable_advanced_security**: Enable Cognito advanced security features
- **mfa_configuration**: Multi-factor authentication configuration

### Advanced Configuration

For production deployments, consider these customizations:

1. **Custom Domain**: Configure a custom domain for Cognito instead of the default Amazon domain
2. **Advanced Security**: Enable Cognito advanced security features for threat detection
3. **Multi-Factor Authentication**: Configure MFA requirements for enhanced security
4. **Attribute Mapping**: Customize SAML attribute mappings for your organization
5. **Session Configuration**: Adjust session timeout and refresh token settings
6. **Branding**: Customize the hosted UI with your corporate branding

### Environment-Specific Configurations

Create separate parameter files for different environments:

```bash
# development.tfvars
app_name = "enterprise-auth-dev"
environment = "development"
enable_advanced_security = false

# production.tfvars
app_name = "enterprise-auth-prod"
environment = "production"
enable_advanced_security = true
mfa_configuration = "OPTIONAL"
```

## Troubleshooting

### Common Issues

1. **SAML Metadata Issues**
   - Ensure metadata URL is accessible from AWS
   - Verify certificates are valid and not expired
   - Check attribute mapping configuration

2. **Authentication Failures**
   - Verify callback URLs match exactly
   - Check identity provider configuration
   - Review Cognito logs in CloudWatch

3. **Permission Errors**
   - Ensure AWS credentials have necessary permissions
   - Verify IAM roles and policies are correctly configured
   - Check resource-based policies

4. **Deployment Failures**
   - Verify all prerequisites are installed
   - Check AWS service limits and quotas
   - Review CloudFormation/CDK/Terraform error logs

### Debugging

Enable debug logging for troubleshooting:

```bash
# CloudFormation
aws logs describe-log-groups --log-group-name-prefix "/aws/cloudformation"

# Cognito
aws logs describe-log-groups --log-group-name-prefix "/aws/cognito"

# Application logs
aws logs tail /aws/amplify/{APP_ID} --follow
```

## Cost Considerations

### Estimated Monthly Costs

- **Amazon Cognito**: $0.0055 per monthly active user (first 50,000 users free)
- **AWS Amplify**: $0.01 per build minute + $0.15 per GB served
- **Application Load Balancer**: $16.20 per month (if using custom domain)
- **Route 53**: $0.50 per hosted zone per month (if using custom domain)

### Cost Optimization Tips

1. Use Cognito's free tier for development and testing
2. Implement proper session management to reduce token refresh frequency
3. Monitor usage patterns and adjust session timeouts accordingly
4. Consider using Cognito Identity Pools for temporary AWS credentials

## Security Best Practices

1. **Certificate Management**: Regularly rotate SAML signing certificates
2. **Session Configuration**: Implement appropriate session timeouts
3. **Monitoring**: Enable CloudTrail and CloudWatch logging
4. **Access Control**: Use least privilege principles for IAM roles
5. **Network Security**: Implement proper VPC and security group configurations
6. **Compliance**: Regular security audits and penetration testing

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../enterprise-authentication-amplify-external-identity-providers.md)
- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Update documentation to reflect changes
3. Verify compatibility across all IaC implementations
4. Follow provider-specific best practices
5. Update cost estimates if resources change