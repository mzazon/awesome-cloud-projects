# Infrastructure as Code for Infrastructure Policy Validation with CloudFormation Guard

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Policy Validation with CloudFormation Guard".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- CloudFormation Guard CLI installed ([Installation Guide](https://docs.aws.amazon.com/cfn-guard/latest/ug/setting-up-guard.html))
- Administrative permissions for CloudFormation, S3, and IAM services
- `jq` command-line JSON processor for report analysis
- Git for version control (optional but recommended)

### Tool-specific Prerequisites

#### For CDK TypeScript
- Node.js 18+ and npm
- AWS CDK CLI: `npm install -g aws-cdk`

#### For CDK Python
- Python 3.8+ and pip
- AWS CDK CLI: `npm install -g aws-cdk`

#### For Terraform
- Terraform 1.0+
- AWS provider configuration

## Architecture Overview

This infrastructure creates:
- S3 bucket for centralized Guard rules storage with versioning and encryption
- IAM roles and policies for Guard validation processes
- Sample CloudFormation templates (compliant and non-compliant)
- Local validation environment setup
- CI/CD integration scripts
- Comprehensive testing framework

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cfn-guard-policy-validation \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=your-guard-rules-bucket-$(date +%s) \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name cfn-guard-policy-validation

# Get outputs
aws cloudformation describe-stacks \
    --stack-name cfn-guard-policy-validation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
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

# View deployment status
echo "Check AWS Console or use AWS CLI to verify resources"
```

## Post-Deployment Setup

After deploying the infrastructure, complete the setup:

### 1. Upload Guard Rules

```bash
# Set your bucket name (from deployment outputs)
export BUCKET_NAME="your-deployed-bucket-name"

# Upload sample Guard rules
aws s3 cp guard-rules/ s3://${BUCKET_NAME}/guard-rules/ --recursive --include "*.guard"
aws s3 cp test-cases/ s3://${BUCKET_NAME}/test-cases/ --recursive --include "*.yaml"
```

### 2. Set Up Local Validation

```bash
# Download Guard rules for local validation
mkdir -p local-validation
aws s3 cp s3://${BUCKET_NAME}/guard-rules/ local-validation/rules/ --recursive

# Test local validation
cfn-guard validate \
    --data sample-templates/compliant-template.yaml \
    --rules local-validation/rules/security/s3-security.guard \
    --show-summary
```

### 3. Integrate with CI/CD Pipeline

```bash
# Use the generated CI/CD validation script
./scripts/ci-cd-validation.sh your-template.yaml ${BUCKET_NAME}
```

## Validation and Testing

### Test Compliant Template

```bash
# Validate a compliant template
cfn-guard validate \
    --data sample-templates/compliant-template.yaml \
    --rules local-validation/rules/security/s3-security.guard \
    --output-format json --show-summary
```

### Test Non-Compliant Template

```bash
# Validate a non-compliant template (should fail)
cfn-guard validate \
    --data sample-templates/non-compliant-template.yaml \
    --rules local-validation/rules/security/s3-security.guard \
    --show-summary || echo "Expected validation failure"
```

### Run Unit Tests

```bash
# Test Guard rules with test cases
cfn-guard test \
    --rules-file local-validation/rules/security/s3-security.guard \
    --test-data local-validation/tests/security/s3-security-tests.yaml
```

## Customization

### Environment Variables

Customize the deployment by setting these environment variables before deployment:

```bash
export AWS_REGION="us-east-1"                    # Target AWS region
export BUCKET_NAME="my-guard-rules-bucket"       # S3 bucket name
export VALIDATION_ROLE_NAME="GuardValidationRole" # IAM role name
export ENABLE_MFA_DELETE="true"                  # Enable MFA delete for production
export COST_CENTER="CC-1001"                     # Cost center tag
export ENVIRONMENT="Production"                  # Environment tag
```

### Guard Rules Customization

Modify Guard rules in the `guard-rules/` directory:

- **Security Rules**: `guard-rules/security/` - S3 encryption, IAM policies, etc.
- **Compliance Rules**: `guard-rules/compliance/` - Tagging, naming conventions
- **Cost Optimization**: `guard-rules/cost-optimization/` - Instance types, retention policies

### Template Customization

Each implementation supports customization:

#### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --parameters ParameterKey=Environment,ParameterValue=Development \
                 ParameterKey=EnableMfaDelete,ParameterValue=false \
    # ... other parameters
```

#### CDK Context Variables

```bash
# cdk.context.json
{
  "environment": "Development",
  "enableMfaDelete": false,
  "bucketRetentionDays": 30
}
```

#### Terraform Variables

```bash
# terraform.tfvars
environment = "Development"
enable_mfa_delete = false
bucket_retention_days = 30
cost_center = "CC-1001"
```

## Monitoring and Reporting

### View Validation Reports

```bash
# List reports in S3
aws s3 ls s3://${BUCKET_NAME}/reports/

# Download latest report
aws s3 cp s3://${BUCKET_NAME}/reports/$(aws s3 ls s3://${BUCKET_NAME}/reports/ --query 'reverse(sort_by(Contents, &LastModified))[0].Key' --output text) latest-report.json

# View report summary
cat latest-report.json | jq '.summary'
```

### CloudWatch Integration

Monitor Guard validation metrics:

```bash
# View CloudWatch logs (if configured)
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/guard-validation"

# View recent log events
aws logs tail /aws/lambda/guard-validation-function --follow
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 bucket first
aws s3 rm s3://your-bucket-name --recursive

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name cfn-guard-policy-validation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name cfn-guard-policy-validation
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Empty S3 buckets first
aws s3 rm s3://$(cdk list --json | jq -r '.[0].metadata.bucketName') --recursive

# Destroy the stack
cdk destroy --force
```

### Using Terraform

```bash
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

# Clean up local files
rm -rf local-validation/ guard-rules/ sample-templates/
rm -f *.json *.yaml validation-*.txt
```

## Troubleshooting

### Common Issues

1. **CloudFormation Guard Not Found**
   ```bash
   # Install CloudFormation Guard
   curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/aws-cloudformation/cloudformation-guard/main/install-guard.sh | sh
   ```

2. **S3 Bucket Access Denied**
   ```bash
   # Check bucket policy and IAM permissions
   aws s3api get-bucket-policy --bucket your-bucket-name
   aws iam get-user --query 'User.Arn'
   ```

3. **Validation Script Permissions**
   ```bash
   # Make scripts executable
   chmod +x scripts/*.sh
   find . -name "*.sh" -exec chmod +x {} \;
   ```

4. **CDK Bootstrap Issues**
   ```bash
   # Re-bootstrap CDK
   cdk bootstrap --force
   ```

### Validation Errors

- **Rule Syntax Errors**: Check Guard rule syntax using `cfn-guard parse --rules your-rule.guard`
- **Template Format**: Ensure CloudFormation templates are valid YAML/JSON
- **Missing Dependencies**: Verify all required CLI tools are installed

### Performance Optimization

- Use parallel validation for multiple rule files
- Cache downloaded rules locally to reduce S3 API calls
- Implement rule indexing for faster lookup in large rule sets

## Security Considerations

### IAM Permissions

The infrastructure creates least-privilege IAM roles:
- Guard validation execution role with minimal S3 and CloudWatch permissions
- Cross-account validation role for multi-account scenarios

### S3 Security

- Bucket encryption enabled by default
- Public access blocked
- Versioning enabled for audit trails
- Access logging configured

### Network Security

- All resources deployed within VPC when applicable
- Security groups with minimal required access
- VPC endpoints for AWS service access

## Support and Documentation

### Resources

- [AWS CloudFormation Guard Documentation](https://docs.aws.amazon.com/cfn-guard/latest/ug/)
- [AWS CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [CloudFormation Guard GitHub Repository](https://github.com/aws-cloudformation/cloudformation-guard)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudFormation/CDK/Terraform documentation
3. Consult the original recipe documentation
4. Check AWS service status and limits

### Contributing

To contribute improvements:
1. Follow AWS best practices for IaC
2. Test all changes thoroughly
3. Update documentation as needed
4. Ensure backward compatibility

## Cost Estimation

Expected monthly costs (us-east-1 region):
- S3 storage: $1-5 (depending on rule repository size)
- CloudFormation operations: $0-2
- Lambda execution (if using functions): $0-1
- CloudWatch logs: $0-3

Total estimated cost: $5-15 per month for typical usage.

> **Note**: Costs may vary based on usage patterns, region, and AWS pricing changes. Use the AWS Pricing Calculator for detailed estimates.