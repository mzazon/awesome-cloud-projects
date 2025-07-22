# Infrastructure as Code for Sharing Files Securely with Web Portals

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Sharing Files Securely with Web Portals".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a secure file sharing portal using:
- AWS Transfer Family Web Apps for browser-based file access
- S3 for secure, encrypted file storage
- IAM Identity Center for centralized authentication
- CloudTrail for comprehensive audit logging
- IAM roles with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured
- Administrative permissions for IAM Identity Center, Transfer Family, S3, and CloudTrail
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.8+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)
- Basic understanding of AWS identity services and S3 storage concepts

## Cost Estimation

Estimated monthly costs for development/testing workloads: $10-25
- Transfer Family Web App: ~$216/month (1 web app unit)
- S3 storage: Variable based on usage
- CloudTrail: Data events may incur additional charges
- IAM Identity Center: No additional charges for basic usage

> **Note**: Actual costs may vary based on usage patterns, storage requirements, and data transfer volumes.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name secure-file-sharing-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-secure-files-$(date +%s) \
                 ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name secure-file-sharing-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name secure-file-sharing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters bucketName=my-secure-files-$(date +%s) \
           --parameters environment=dev

# Get outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters bucketName=my-secure-files-$(date +%s) \
           --parameters environment=dev

# Get outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="bucket_name=my-secure-files-$(date +%s)" \
               -var="environment=dev"

# Apply the configuration
terraform apply -var="bucket_name=my-secure-files-$(date +%s)" \
                -var="environment=dev"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters:
# - S3 bucket name (must be globally unique)
# - Environment tag (dev, staging, prod)
# - AWS region (defaults to current configured region)
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| BucketName | S3 bucket name for file storage | N/A | Yes |
| Environment | Environment tag for resources | dev | No |
| EnableCloudTrail | Enable CloudTrail audit logging | true | No |
| WebAppUnits | Number of web app units | 1 | No |

### CloudFormation Parameters

Additional CloudFormation-specific parameters are available in the template's Parameters section.

### CDK Context Values

Configure CDK-specific settings in `cdk.json`:

```json
{
  "app": "npx ts-node app.ts",
  "context": {
    "bucketName": "my-secure-files-bucket",
    "environment": "dev",
    "enableCloudTrail": true
  }
}
```

### Terraform Variables

Customize deployment using `terraform.tfvars`:

```hcl
bucket_name = "my-secure-files-bucket"
environment = "dev"
enable_cloudtrail = true
web_app_units = 1
```

## Post-Deployment Configuration

### 1. Set Up Identity Center Users

```bash
# Get Identity Center details from outputs
IDENTITY_STORE_ID="<from-outputs>"

# Create a test user
aws identitystore create-user \
    --identity-store-id $IDENTITY_STORE_ID \
    --user-name "testuser" \
    --display-name "Test User" \
    --name '{"FamilyName":"User","GivenName":"Test"}' \
    --emails '[{"Value":"testuser@company.com","Type":"Work","Primary":true}]'
```

### 2. Configure Transfer Family Users

```bash
# Get server ID from outputs
SERVER_ID="<from-outputs>"
ROLE_ARN="<from-outputs>"
BUCKET_NAME="<from-outputs>"

# Create Transfer Family user
aws transfer create-user \
    --server-id $SERVER_ID \
    --user-name testuser \
    --role $ROLE_ARN \
    --home-directory /$BUCKET_NAME \
    --home-directory-type LOGICAL
```

### 3. Access the Web App

Use the web app endpoint from the deployment outputs to access the secure file sharing portal.

## Validation & Testing

### Test S3 Bucket Security

```bash
# Verify encryption is enabled
aws s3api get-bucket-encryption --bucket <bucket-name>

# Check public access block
aws s3api get-public-access-block --bucket <bucket-name>
```

### Test Transfer Family Configuration

```bash
# Check server status
aws transfer describe-server --server-id <server-id>

# Verify web app status
aws transfer describe-web-app --web-app-id <web-app-id>
```

### Test CloudTrail Logging

```bash
# Verify CloudTrail is logging
aws cloudtrail get-trail-status --name <trail-name>

# Check recent events
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=CreateUser
```

## Security Best Practices

### Implemented Security Features

1. **Encryption**: S3 bucket encryption enabled by default
2. **Access Control**: Public access blocked on S3 bucket
3. **Audit Logging**: CloudTrail captures all file access events
4. **Identity Management**: IAM Identity Center for centralized authentication
5. **Least Privilege**: IAM roles with minimal required permissions

### Additional Security Recommendations

1. **Enable MFA**: Configure multi-factor authentication in Identity Center
2. **Network Security**: Consider VPC endpoints for enhanced network isolation
3. **Monitoring**: Set up CloudWatch alarms for suspicious activities
4. **Compliance**: Configure additional logging for regulatory requirements

## Troubleshooting

### Common Issues

1. **Identity Center Not Available**: Ensure Identity Center is enabled in your AWS account
2. **IAM Permission Errors**: Verify administrative permissions for deployment
3. **Bucket Name Conflicts**: Use a globally unique bucket name
4. **Web App Access Issues**: Check security groups and endpoint configuration

### Debug Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Verify service availability in region
aws transfer describe-servers
aws sso-admin list-instances

# Check CloudFormation stack events
aws cloudformation describe-stack-events --stack-name <stack-name>
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name secure-file-sharing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name secure-file-sharing-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
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

> **Warning**: The cleanup process will permanently delete all files in the S3 bucket and cannot be reversed. Ensure you have backups of any important data before proceeding.

## Customization

### Extending the Solution

1. **Custom Branding**: Modify Transfer Family web app appearance
2. **Advanced Authentication**: Integrate with external identity providers
3. **File Processing**: Add Lambda functions for automated file processing
4. **Monitoring**: Implement custom CloudWatch dashboards
5. **Compliance**: Add additional audit and compliance features

### Modifying the Infrastructure

- **CloudFormation**: Edit the template parameters and resources
- **CDK**: Modify the stack classes and construct configurations
- **Terraform**: Update the resource definitions and variables
- **Scripts**: Customize the deployment logic and parameters

## Support

### Resources

- [AWS Transfer Family Documentation](https://docs.aws.amazon.com/transfer/)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [IAM Identity Center User Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)
- [CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services
4. Review AWS CloudFormation/CDK/Terraform documentation for syntax issues

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Ensure security best practices are maintained
4. Update documentation for any changes

## License

This infrastructure code is provided as-is for educational and development purposes. Review and modify according to your organization's security and compliance requirements before using in production environments.