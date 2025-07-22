# Infrastructure as Code for Building File Portals with Transfer Family

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building File Portals with Transfer Family".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a secure, self-service file portal using AWS Transfer Family Web Apps with the following components:

- **S3 Bucket**: Encrypted storage with versioning and access logging
- **IAM Identity Center**: Centralized identity management with SAML/OIDC integration
- **S3 Access Grants**: Fine-grained permission control for S3 resources
- **Transfer Family Web App**: Managed web interface for file operations
- **IAM Roles**: Service roles for secure operations
- **CORS Configuration**: Secure cross-origin resource sharing

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with administrative permissions for:
  - AWS Transfer Family
  - Amazon S3
  - IAM Identity Center
  - S3 Access Grants
  - IAM (for role management)
- Existing IAM Identity Center instance (account or organization level)
- Basic understanding of identity management concepts (SAML, OIDC)
- Estimated cost: $10-25 per month for resources created (varies by usage)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI configured with CloudFormation permissions
- IAM permissions to create stacks and resources

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript compiler

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI installed (`pip install aws-cdk-lib`)
- pip package manager

#### Terraform
- Terraform 1.0 or later
- AWS provider configuration

## Quick Start

### Using CloudFormation
```bash
# Validate the template
aws cloudformation validate-template \
    --template-body file://cloudformation.yaml

# Deploy the stack
aws cloudformation create-stack \
    --stack-name transfer-family-portal \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=my-portal \
                 ParameterKey=WebAppNamePrefix,ParameterValue=my-webapp \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name transfer-family-portal

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name transfer-family-portal \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
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
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# The script will prompt for required parameters
# and guide you through the deployment process
```

## Configuration Options

### Key Parameters

- **BucketNamePrefix**: Prefix for the S3 bucket name (default: "file-portal")
- **WebAppNamePrefix**: Prefix for the Transfer Family web app name (default: "file-portal-webapp")
- **UserNamePrefix**: Prefix for the test IAM Identity Center user (default: "portal-user")
- **EnableVersioning**: Enable S3 bucket versioning (default: true)
- **EnableAccessLogging**: Enable S3 access logging (default: true)
- **WebAppUnits**: Number of web app units for capacity (default: 1)

### Environment Variables (Bash Scripts)

```bash
# Optional: Set custom values before running deploy.sh
export BUCKET_NAME_PREFIX="my-company-portal"
export WEBAPP_NAME_PREFIX="my-company-webapp"
export USER_NAME_PREFIX="test-user"
export AWS_REGION="us-east-1"
```

## Post-Deployment Steps

1. **Access the Web Portal**:
   - Retrieve the web app access endpoint from the stack outputs
   - Navigate to the URL in your browser
   - Authenticate using the created IAM Identity Center user

2. **Configure Additional Users** (Optional):
   - Add users to IAM Identity Center through the AWS Console
   - Create additional S3 Access Grants for new users
   - Assign appropriate permissions based on business requirements

3. **Customize Branding** (Optional):
   - Update the web app configuration to include custom logos and themes
   - Configure custom domain names with SSL certificates

4. **Set Up Monitoring**:
   - Enable CloudTrail logging for audit trails
   - Configure CloudWatch alerts for security events
   - Set up cost monitoring and budgets

## Testing the Deployment

### Verify Infrastructure
```bash
# Check S3 bucket configuration
aws s3api get-bucket-versioning --bucket <bucket-name>
aws s3api get-bucket-encryption --bucket <bucket-name>

# Verify Transfer Family web app status
aws transfer describe-web-app --web-app-id <web-app-id>

# Check IAM Identity Center user
aws identitystore list-users --identity-store-id <identity-store-id>

# Verify S3 Access Grants
aws s3control list-access-grants --account-id <account-id>
```

### Test File Operations
1. Navigate to the web app URL
2. Sign in with the created test user credentials
3. Upload a test file to verify write permissions
4. Download the file to verify read permissions
5. Check the S3 bucket for the uploaded file

## Cleanup

### Using CloudFormation
```bash
# Empty the S3 bucket before deletion (if not handled by stack)
aws s3 rm s3://<bucket-name> --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name transfer-family-portal

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name transfer-family-portal
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
cd scripts/

# Run the cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

- **IAM Permissions**: All roles follow the principle of least privilege
- **Data Encryption**: S3 bucket uses server-side encryption (AES-256)
- **Access Control**: S3 Access Grants provide fine-grained permissions
- **Authentication**: IAM Identity Center provides centralized identity management
- **CORS**: Configured to allow access only from the web app domain
- **Audit Trails**: S3 access logging enabled for compliance

## Troubleshooting

### Common Issues

1. **IAM Identity Center Not Available**:
   - Ensure you have an IAM Identity Center instance configured
   - Check that your account has the necessary permissions

2. **CORS Errors**:
   - Verify the CORS configuration includes the correct web app endpoint
   - Check browser developer tools for specific CORS error messages

3. **Access Denied Errors**:
   - Verify S3 Access Grants are configured correctly
   - Check that the user has the appropriate permissions
   - Ensure the IAM roles have the necessary policies attached

4. **Web App Not Loading**:
   - Check the Transfer Family web app status
   - Verify the access endpoint is accessible
   - Check for any networking restrictions

### Debug Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Verify IAM Identity Center instance
aws sso-admin list-instances

# Check S3 bucket permissions
aws s3api get-bucket-policy --bucket <bucket-name>

# List all Transfer Family web apps
aws transfer list-web-apps
```

## Customization

### Adding Custom Users

To add additional users after deployment:

1. Create users in IAM Identity Center
2. Create corresponding S3 Access Grants
3. Assign appropriate permissions based on business requirements

### Custom Branding

Update the Transfer Family web app configuration to include:
- Custom logos and color schemes
- Corporate branding elements
- Custom domain names with SSL certificates

### Advanced Access Controls

Implement additional security measures:
- Time-based access grants with automatic expiration
- IP address restrictions
- Device-based access controls
- Multi-factor authentication requirements

## Monitoring and Logging

### CloudWatch Integration

- Monitor file upload/download activities
- Set up alerts for security events
- Track user access patterns

### AWS CloudTrail

- Enable CloudTrail logging for audit trails
- Monitor API calls related to file operations
- Maintain compliance logs for regulatory requirements

## Cost Optimization

- Monitor Transfer Family web app usage and adjust units as needed
- Implement S3 Intelligent-Tiering for cost-effective storage
- Use S3 lifecycle policies for archival
- Regular review of Access Grants to remove unused permissions

## Support

For issues with this infrastructure code:
- Refer to the original recipe documentation
- Consult AWS Transfer Family documentation: https://docs.aws.amazon.com/transfer/
- Review IAM Identity Center documentation: https://docs.aws.amazon.com/singlesignon/
- Check S3 Access Grants documentation: https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html

## Related Resources

- [AWS Transfer Family User Guide](https://docs.aws.amazon.com/transfer/latest/userguide/)
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [S3 Access Grants User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)