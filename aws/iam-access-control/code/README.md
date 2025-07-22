# Infrastructure as Code for Fine-Grained Access Control with IAM

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fine-Grained Access Control with IAM".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for IAM, S3, CloudWatch, and EC2
- Appropriate IAM permissions for resource creation:
  - `iam:CreatePolicy`
  - `iam:CreateUser`
  - `iam:CreateRole`
  - `iam:AttachUserPolicy`
  - `iam:AttachRolePolicy`
  - `iam:TagUser`
  - `iam:TagRole`
  - `s3:CreateBucket`
  - `s3:PutBucketPolicy`
  - `logs:CreateLogGroup`
- Understanding of IAM policies, JSON syntax, and AWS resource ARNs
- Estimated cost: Under $5 (primarily CloudWatch Logs and S3 storage)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name fine-grained-access-control \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=finegrained-access

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name fine-grained-access-control \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fine-grained-access-control \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Get stack outputs
cdk output
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Get stack outputs
cdk output
```

### Using Terraform
```bash
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

# View deployment status
echo "Deployment completed. Check AWS console for created resources."
```

## Deployed Resources

This infrastructure deploys the following AWS resources:

### IAM Policies
- **Business Hours Policy**: S3 access restricted to 9 AM - 5 PM UTC
- **IP Restriction Policy**: CloudWatch Logs access from specific IP ranges only
- **Tag-Based Policy**: S3 access based on user and resource tags (ABAC)
- **MFA Required Policy**: S3 write operations require multi-factor authentication
- **Session Policy**: Session-based access control with duration limits

### IAM Principals
- **Test User**: IAM user with Department=Engineering tag for testing
- **Test Role**: IAM role with conditional assume role policy

### S3 Resources
- **Test Bucket**: S3 bucket with resource-based policy enforcing encryption
- **Test Objects**: Sample objects with appropriate tags and metadata

### CloudWatch Resources
- **Log Group**: CloudWatch log group for testing log-based policies

### Policy Features Demonstrated
- Time-based access controls using date/time conditions
- IP address restrictions for network-based security
- Attribute-based access control (ABAC) using tags
- Multi-factor authentication requirements
- Session duration limits and constraints
- Resource-based policies with encryption requirements
- Cross-account access with conditional trust policies

## Testing the Deployment

After deployment, you can test the fine-grained access controls:

### Test Policy Simulator
```bash
# Test business hours policy (replace with actual role ARN)
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::ACCOUNT-ID:role/PROJECT-NAME-test-role" \
    --action-names "s3:GetObject" \
    --resource-arns "arn:aws:s3:::BUCKET-NAME/test-file.txt" \
    --context-entries ContextKeyName=aws:CurrentTime,ContextKeyValues="14:00:00Z",ContextKeyType=date

# Test IP-based access control
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::ACCOUNT-ID:policy/PROJECT-NAME-ip-restriction-policy" \
    --action-names "logs:PutLogEvents" \
    --resource-arns "arn:aws:logs:REGION:ACCOUNT-ID:log-group:LOG-GROUP-NAME" \
    --context-entries ContextKeyName=aws:SourceIp,ContextKeyValues="203.0.113.100",ContextKeyType=ip
```

### Verify Resource-Based Policies
```bash
# Check S3 bucket policy
aws s3api get-bucket-policy --bucket BUCKET-NAME

# List created IAM policies
aws iam list-policies --scope Local --query 'Policies[?contains(PolicyName, `PROJECT-NAME`)]'
```

## Customization

### Variables and Parameters

Each implementation provides customizable variables:

- **Project Name**: Prefix for all resource names
- **IP Address Ranges**: CIDR blocks for IP-based access control
- **Business Hours**: Time range for temporal access controls
- **AWS Region**: Target region for deployment
- **Department Tags**: User and resource department tags

### CloudFormation Parameters
Edit the parameter values in the CloudFormation template or provide them during stack creation.

### CDK Configuration
Modify the context values in `cdk.json` or provide them as environment variables.

### Terraform Variables
Edit `terraform.tfvars` or provide values via environment variables:

```bash
export TF_VAR_project_name="my-access-control"
export TF_VAR_allowed_ip_ranges='["198.51.100.0/24", "203.0.113.0/24"]'
```

## Security Considerations

This infrastructure implements several security best practices:

- **Least Privilege**: All policies follow the principle of least privilege
- **Defense in Depth**: Multiple layers of access controls (identity-based and resource-based policies)
- **Encryption**: S3 bucket policy enforces server-side encryption
- **Secure Transport**: Bucket policy denies non-HTTPS requests
- **Time-based Controls**: Business hours restrictions reduce attack surface
- **Network Controls**: IP-based restrictions limit access to trusted networks
- **Strong Authentication**: MFA requirements for sensitive operations

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name fine-grained-access-control

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name fine-grained-access-control \
    --query 'Stacks[0].StackStatus'
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
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**: Ensure your AWS credentials have sufficient permissions for IAM, S3, and CloudWatch operations.

2. **Resource Already Exists**: If resources already exist, either delete them manually or modify the resource names in the configuration.

3. **Policy Simulation Errors**: Ensure you're using the correct ARNs and context values when testing with the policy simulator.

4. **S3 Bucket Name Conflicts**: S3 bucket names must be globally unique. The templates use random suffixes to avoid conflicts.

### Policy Testing

Use AWS IAM Access Analyzer to validate your policies:

```bash
# Validate a policy document
aws accessanalyzer validate-policy \
    --policy-document file://policy.json \
    --policy-type IDENTITY_BASED
```

## Additional Resources

- [AWS IAM User Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/)
- [IAM Policy Language Reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html)
- [AWS IAM Policy Simulator](https://policysim.aws.amazon.com/)
- [AWS IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- AWS documentation for specific services
- AWS Support (if you have a support plan)
- AWS re:Post community forums

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure you review and test thoroughly before using in production environments.