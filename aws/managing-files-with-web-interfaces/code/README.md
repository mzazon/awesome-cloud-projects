# Infrastructure as Code for Managing Files with Web Interfaces

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Managing Files with Web Interfaces".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete self-service file management system using:

- **AWS Transfer Family Web Apps**: Browser-based file transfer interface
- **Amazon S3**: Secure file storage with versioning and encryption
- **IAM Identity Center**: Centralized identity management and SSO
- **S3 Access Grants**: Fine-grained access control for S3 resources
- **IAM Roles**: Identity bearer and grantee roles for secure access

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - IAM Identity Center management
  - S3 bucket creation and management
  - Transfer Family resource creation
  - IAM role and policy management
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform deployment)
- Appropriate IAM permissions including:
  - `iam:CreateRole`, `iam:AttachRolePolicy`
  - `s3:CreateBucket`, `s3:PutBucketPolicy`
  - `transfer:CreateWebApp`, `transfer:CreateServer`
  - `sso-admin:*` (for Identity Center)
  - `s3control:*` (for Access Grants)

> **Note**: This solution requires IAM Identity Center to be enabled in your AWS organization. Coordinate with your AWS organization administrator if needed.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name file-management-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-file-management-bucket \
                 ParameterKey=WebAppName,ParameterValue=my-file-webapp \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name file-management-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name file-management-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy FileManagementStack

# Get stack outputs
cdk deploy FileManagementStack --outputs-file outputs.json
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy FileManagementStack

# Get stack outputs
cdk deploy FileManagementStack --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# Follow prompts for configuration values
# The script will create all necessary resources and output access information
```

## Configuration Options

### Environment Variables

The following environment variables can be set to customize the deployment:

```bash
export AWS_REGION="us-east-1"                    # AWS region for deployment
export BUCKET_NAME="my-file-management-bucket"   # S3 bucket name
export WEBAPP_NAME="my-file-webapp"              # Transfer Family Web App name
export GRANTS_INSTANCE_NAME="my-grants-instance" # Access Grants instance name
export ENABLE_VERSIONING="true"                  # Enable S3 versioning
export ENABLE_ENCRYPTION="true"                  # Enable S3 encryption
```

### Terraform Variables

Create a `terraform.tfvars` file to customize the Terraform deployment:

```hcl
aws_region              = "us-east-1"
bucket_name            = "my-file-management-bucket"
webapp_name            = "my-file-webapp"
grants_instance_name   = "my-grants-instance"
enable_s3_versioning   = true
enable_s3_encryption   = true
test_user_email        = "testuser@example.com"

# Optional: Custom VPC configuration
vpc_id        = "vpc-12345678"
subnet_ids    = ["subnet-12345678", "subnet-87654321"]

# Optional: Branding configuration
webapp_title       = "Secure File Management Portal"
webapp_description = "Upload, download, and manage your files securely"
webapp_logo_url    = "https://example.com/logo.png"
```

## Post-Deployment Configuration

### 1. Configure Test User Password

```bash
# Get Identity Center instance details
IDC_INSTANCE_ARN=$(aws sso-admin list-instances \
    --query 'Instances[0].InstanceArn' --output text)

# Set temporary password for test user (via AWS Console)
echo "Set password for test user in IAM Identity Center console:"
echo "https://console.aws.amazon.com/singlesignon/"
```

### 2. Access the Web Application

```bash
# Get Web App URL from outputs
WEBAPP_URL=$(terraform output -raw webapp_url)  # For Terraform
# OR
WEBAPP_URL=$(aws cloudformation describe-stacks \
    --stack-name file-management-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`WebAppUrl`].OutputValue' \
    --output text)  # For CloudFormation

echo "Access your file management portal at: ${WEBAPP_URL}"
```

### 3. Create Additional Users and Access Grants

```bash
# Create additional user
aws identitystore create-user \
    --identity-store-id ${IDC_IDENTITY_STORE_ID} \
    --user-name "newuser" \
    --display-name "New User" \
    --emails '[{"Value":"newuser@example.com","Type":"Work","Primary":true}]'

# Create access grant for new user
aws s3control create-access-grant \
    --account-id ${AWS_ACCOUNT_ID} \
    --access-grants-location-id ${LOCATION_ID} \
    --grantee GranteeType=IAM_IDENTITY_CENTER_USER,GranteeIdentifier=${NEW_USER_ID} \
    --permission READWRITE
```

## Validation and Testing

### 1. Verify Infrastructure

```bash
# Check S3 bucket
aws s3 ls s3://${BUCKET_NAME}/user-files/ --recursive

# Verify Access Grants configuration
aws s3control get-access-grants-instance --account-id ${AWS_ACCOUNT_ID}

# Check Transfer Family Web App
aws transfer describe-web-app --web-app-id ${WEBAPP_ARN}
```

### 2. Test File Operations

1. Navigate to the Web App URL
2. Log in with the test user credentials
3. Upload a test file to verify upload functionality
4. Download the file to verify download functionality
5. Create folders to test organization capabilities

### 3. Security Validation

```bash
# Verify S3 bucket encryption
aws s3api get-bucket-encryption --bucket ${BUCKET_NAME}

# Check IAM roles and policies
aws iam get-role --role-name TransferIdentityBearerRole-*
aws iam get-role --role-name S3AccessGrantsRole-*

# Verify access grants permissions
aws s3control list-access-grants --account-id ${AWS_ACCOUNT_ID}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name file-management-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name file-management-stack
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy FileManagementStack
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

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. Delete Transfer Family Web App
2. Remove S3 Access Grants and locations
3. Delete Access Grants instance
4. Remove IAM roles and policies
5. Empty and delete S3 bucket
6. Delete IAM Identity Center test users

## Cost Optimization

### Expected Costs

- **Transfer Family Web App**: ~$0.30/hour when active
- **S3 Storage**: ~$0.023/GB/month (Standard storage class)
- **S3 Requests**: $0.0004/1000 requests (PUT/COPY/POST/LIST)
- **IAM Identity Center**: No additional cost
- **S3 Access Grants**: No additional cost

### Cost Reduction Strategies

1. **S3 Lifecycle Policies**: Automatically transition files to cheaper storage classes
2. **Intelligent Tiering**: Enable S3 Intelligent-Tiering for automatic cost optimization
3. **Web App Scheduling**: Stop web app during non-business hours if applicable
4. **Monitoring**: Set up CloudWatch billing alarms

## Security Best Practices

### Implemented Security Features

- **Encryption**: S3 bucket encryption at rest (AES-256)
- **Access Control**: Fine-grained permissions via S3 Access Grants
- **Identity Management**: Integration with IAM Identity Center for SSO
- **Network Security**: VPC endpoint deployment for private access
- **Audit Logging**: All actions logged via CloudTrail

### Additional Security Recommendations

1. **Enable MFA**: Require multi-factor authentication in Identity Center
2. **VPC Configuration**: Deploy in private subnets with NAT Gateway
3. **Monitoring**: Set up CloudWatch alerts for unusual access patterns
4. **Compliance**: Enable AWS Config for compliance monitoring
5. **Backup**: Implement cross-region replication for critical files

## Troubleshooting

### Common Issues

#### 1. IAM Identity Center Not Enabled

```bash
# Error: Identity Center instance not found
# Solution: Enable IAM Identity Center in your AWS organization
echo "Enable IAM Identity Center in AWS Organizations console"
```

#### 2. Permission Denied Errors

```bash
# Check current user permissions
aws sts get-caller-identity
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
```

#### 3. Web App Access Issues

```bash
# Verify web app status
aws transfer describe-web-app --web-app-id ${WEBAPP_ARN}

# Check VPC and subnet configuration
aws ec2 describe-subnets --subnet-ids ${SUBNET_ID}
```

#### 4. S3 Access Grants Issues

```bash
# Verify grants configuration
aws s3control list-access-grants --account-id ${AWS_ACCOUNT_ID}

# Check grants instance status
aws s3control get-access-grants-instance --account-id ${AWS_ACCOUNT_ID}
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:

- **Transfer Family**: Active connections, data transferred
- **S3**: Request metrics, error rates, storage utilization
- **IAM Identity Center**: Sign-in events, failed authentications

### CloudTrail Events

Key events to monitor:

- `CreateWebApp`, `DeleteWebApp`
- `CreateAccessGrant`, `DeleteAccessGrant`
- `PutObject`, `GetObject` (S3 operations)
- `AssumeRoleWithWebIdentity` (authentication events)

### Setting Up Monitoring

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "FileManagementDashboard" \
    --dashboard-body file://monitoring/dashboard.json

# Set up billing alerts
aws cloudwatch put-metric-alarm \
    --alarm-name "FileManagementCostAlert" \
    --alarm-description "Alert when costs exceed threshold" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold
```

## Customization

### Branding Customization

Update the web app branding by modifying the configuration:

```json
{
    "Title": "Your Company File Portal",
    "Description": "Secure file management for Your Company",
    "LogoUrl": "https://your-company.com/logo.png",
    "FaviconUrl": "https://your-company.com/favicon.ico"
}
```

### Access Control Customization

Create department-specific access patterns:

```bash
# Create department-specific grants
aws s3control create-access-grant \
    --account-id ${AWS_ACCOUNT_ID} \
    --access-grants-location-configuration LocationScope=s3://${BUCKET_NAME}/hr/* \
    --grantee GranteeType=IAM_IDENTITY_CENTER_GROUP,GranteeIdentifier=${HR_GROUP_ID} \
    --permission READWRITE
```

### Integration with External Systems

Extend the solution with:

- **API Gateway**: REST API for programmatic access
- **Lambda Functions**: Automated file processing workflows
- **Step Functions**: Complex approval workflows
- **EventBridge**: Integration with external systems

## Support

### Documentation References

- [AWS Transfer Family User Guide](https://docs.aws.amazon.com/transfer/latest/userguide/)
- [S3 Access Grants Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-grants.html)
- [IAM Identity Center Documentation](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/)

### Getting Help

1. **AWS Support**: Open a support case for infrastructure issues
2. **AWS Forums**: Community support for general questions
3. **AWS Documentation**: Comprehensive guides and API references
4. **Recipe Documentation**: Refer to the original recipe for implementation details

For issues specific to this infrastructure code, review the deployment logs and verify that all prerequisites are met before deployment.