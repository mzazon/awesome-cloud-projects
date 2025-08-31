# Infrastructure as Code for Simple File Sharing with Transfer Family Web Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Sharing with Transfer Family Web Apps".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a secure, browser-based file sharing system using:

- **AWS Transfer Family Web Apps**: Managed web interface for file operations
- **Amazon S3**: Secure object storage with encryption and versioning
- **IAM Identity Center**: Centralized authentication and user management
- **S3 Access Grants**: Fine-grained access controls with temporary credentials
- **CORS Configuration**: Secure cross-origin resource sharing

## Prerequisites

### General Requirements

- AWS account with administrative permissions
- AWS CLI v2 installed and configured (or AWS CloudShell access)
- IAM Identity Center enabled in your AWS account
- Basic understanding of file permissions and user management

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript compiler: `npm install -g typescript`

#### CDK Python
- Python 3.8+ installed
- pip package manager
- AWS CDK v2 installed: `pip install aws-cdk-lib`

#### Terraform
- Terraform 1.5+ installed
- AWS provider configured

### Required Permissions

Your AWS credentials must have permissions for:
- Transfer Family (create web apps, assignments)
- S3 (create buckets, configure CORS, manage objects)
- IAM Identity Center (list instances, create users)
- S3 Control (manage access grants)
- IAM (create and manage roles)

### Cost Considerations

Estimated cost for testing: $0.05-$0.25 including:
- S3 storage charges
- Transfer Family web app units
- Minimal data transfer costs

> **Note**: Transfer Family Web Apps are available in all Transfer Family supported regions except Mexico (Central). Verify region support before deployment.

## Quick Start

### Using CloudFormation

```bash
# Create stack with CloudFormation
aws cloudformation create-stack \
    --stack-name transfer-family-file-sharing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DemoUserName,ParameterValue=demo-user-$(date +%s) \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name transfer-family-file-sharing

# Get outputs
aws cloudformation describe-stacks \
    --stack-name transfer-family-file-sharing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for any required inputs
# and display progress throughout deployment
```

## Post-Deployment Configuration

After successful deployment, complete these steps:

### 1. Set User Password

```bash
# Get the demo user ID from outputs
DEMO_USER_ID="<user-id-from-outputs>"
IDENTITY_STORE_ID="<identity-store-id-from-outputs>"

# Or manually in AWS Console:
# 1. Go to IAM Identity Center console
# 2. Navigate to Users
# 3. Find the demo user
# 4. Set a password
```

### 2. Access the Web App

```bash
# Get access endpoint from outputs
ACCESS_ENDPOINT="<access-endpoint-from-outputs>"

# Open in browser and login with demo user credentials
echo "Access your file sharing app at: ${ACCESS_ENDPOINT}"
```

### 3. Test File Operations

- Upload files through the web interface
- Download files to verify access
- Test folder creation and organization
- Verify permissions and access controls

## Validation Commands

### Verify Infrastructure

```bash
# Check Transfer Family Web App status
aws transfer describe-web-app --web-app-id <web-app-id>

# Verify S3 bucket configuration
aws s3api get-bucket-versioning --bucket <bucket-name>
aws s3api get-bucket-cors --bucket <bucket-name>

# Check S3 Access Grants
aws s3control list-access-grants --account-id <account-id>

# Test file upload
echo "Test file content" > test.txt
aws s3 cp test.txt s3://<bucket-name>/test.txt
```

### Monitor Usage

```bash
# View CloudTrail logs for Transfer Family events
aws logs filter-log-events \
    --log-group-name aws-transfer-family-web-app \
    --start-time $(date -d '1 hour ago' +%s)000

# Check S3 access logs (if configured)
aws s3 ls s3://<access-logs-bucket>/
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name transfer-family-file-sharing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name transfer-family-file-sharing
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy --force

# Deactivate virtual environment (Python only)
deactivate  # If using Python virtual environment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will handle cleanup in proper order
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

```bash
# 1. Remove web app assignments
aws transfer delete-web-app-assignment \
    --web-app-id <web-app-id> \
    --grantee '{"Type":"USER","Identifier":"<user-id>"}'

# 2. Delete web app
aws transfer delete-web-app --web-app-id <web-app-id>

# 3. Remove S3 Access Grants
aws s3control delete-access-grant \
    --account-id <account-id> \
    --access-grant-id <grant-id>

# 4. Empty and delete S3 bucket
aws s3 rm s3://<bucket-name> --recursive
aws s3 rb s3://<bucket-name>

# 5. Delete demo user
aws identitystore delete-user \
    --identity-store-id <identity-store-id> \
    --user-id <user-id>
```

## Customization

### Common Configuration Options

#### CloudFormation Parameters
- `DemoUserName`: Name for the demo user account
- `BucketNamePrefix`: Prefix for S3 bucket naming
- `EnableVersioning`: Enable S3 object versioning (default: true)
- `EnableEncryption`: Enable S3 server-side encryption (default: true)

#### CDK/Terraform Variables
- `region`: AWS region for deployment
- `projectName`: Project name for resource naming
- `environment`: Environment tag (dev/staging/prod)
- `enableCloudTrail`: Enable CloudTrail logging
- `corsAllowedOrigins`: Additional CORS origins

### Advanced Customizations

#### Custom Domain Configuration
```bash
# Add custom domain with CloudFront (requires additional setup)
# 1. Create ACM certificate
# 2. Configure CloudFront distribution
# 3. Update DNS records
```

#### Integration with External Identity Providers
```bash
# Configure external SAML/OIDC provider with IAM Identity Center
# Modify the identity provider configuration in IaC templates
```

#### Enhanced Security Settings
```bash
# Add bucket policies for additional access restrictions
# Configure VPC endpoints for private access
# Enable GuardDuty and Security Hub monitoring
```

## Troubleshooting

### Common Issues

#### IAM Identity Center Not Enabled
```bash
# Error: Identity Center instance not found
# Solution: Enable IAM Identity Center in AWS Console
# Navigate to: https://console.aws.amazon.com/singlesignon/
```

#### Web App Creation Fails
```bash
# Check Transfer Family service availability in region
aws transfer describe-web-app --web-app-id test 2>&1 | grep -i "not available"

# Verify required IAM roles exist
aws iam get-role --role-name TransferFamily-S3AccessGrants-WebAppRole
```

#### CORS Configuration Issues
```bash
# Verify CORS rules are properly applied
aws s3api get-bucket-cors --bucket <bucket-name>

# Test CORS from browser developer tools
# Check for Access-Control-Allow-Origin headers
```

#### Access Grant Permission Errors
```bash
# Verify S3 Access Grants instance exists
aws s3control get-access-grants-instance --account-id <account-id>

# Check access grant permissions
aws s3control list-access-grants --account-id <account-id>
```

### Debug Commands

```bash
# Enable AWS CLI debug output
export AWS_CLI_DEBUG=1

# Check CloudTrail for API calls
aws logs filter-log-events \
    --log-group-name CloudTrail/TransferFamily

# Test S3 permissions with temporary credentials
aws sts assume-role \
    --role-arn <access-grants-role-arn> \
    --role-session-name debug-session
```

### Getting Help

- **AWS Documentation**: [Transfer Family Web Apps User Guide](https://docs.aws.amazon.com/transfer/latest/userguide/web-app.html)
- **AWS Support**: Create a support case for deployment issues
- **Community Forums**: AWS Developer Forums and Stack Overflow
- **Recipe Documentation**: Refer to the original recipe markdown file

## Security Best Practices

### Access Control
- Follow principle of least privilege for all IAM roles
- Regularly review and audit S3 Access Grants
- Use strong passwords for Identity Center users
- Enable MFA for administrative accounts

### Data Protection
- Ensure S3 bucket encryption is enabled
- Configure appropriate retention policies
- Enable S3 access logging for audit trails
- Use VPC endpoints for private network access

### Monitoring
- Enable CloudTrail for all API activities
- Set up CloudWatch alarms for unusual activity
- Monitor failed login attempts in Identity Center
- Configure GuardDuty for threat detection

### Compliance
- Tag all resources appropriately for cost allocation
- Document access procedures for audit purposes
- Implement data classification schemes
- Regular security assessments and penetration testing

## Performance Optimization

### S3 Configuration
- Use S3 Transfer Acceleration for large files
- Configure multipart upload thresholds
- Implement S3 Intelligent Tiering for cost optimization
- Use appropriate storage classes for different access patterns

### Web App Performance
- Consider CloudFront integration for global users
- Monitor web app usage through CloudWatch metrics
- Optimize CORS configuration for your use case
- Implement connection pooling for high-volume scenarios

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS service documentation
4. Contact AWS Support for service-specific issues

For enhancement requests or bug reports, please refer to the repository maintainers.