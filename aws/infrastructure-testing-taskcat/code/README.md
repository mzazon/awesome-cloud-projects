# Infrastructure as Code for Infrastructure Testing with TaskCat and CloudFormation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Testing with TaskCat and CloudFormation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - S3 buckets
  - CloudFormation stacks
  - IAM roles and policies
  - VPC and networking resources
  - EC2 resources
- Python 3.7+ installed (for TaskCat)
- Node.js 16+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

Deploy the TaskCat testing infrastructure with CloudFormation templates:

```bash
# Create the S3 bucket for TaskCat artifacts
aws cloudformation create-stack \
    --stack-name taskcat-testing-infrastructure \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-taskcat-demo \
                 ParameterKey=Environment,ParameterValue=testing \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name taskcat-testing-infrastructure \
    --region us-east-1
```

### Using CDK TypeScript

Deploy using AWS CDK with TypeScript:

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy TaskCatTestingStack \
    --parameters ProjectName=my-taskcat-demo \
    --parameters Environment=testing

# View outputs
cdk ls
```

### Using CDK Python

Deploy using AWS CDK with Python:

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
cdk deploy TaskCatTestingStack \
    -c project_name=my-taskcat-demo \
    -c environment=testing

# View stack outputs
cdk ls
```

### Using Terraform

Deploy using Terraform:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_name=my-taskcat-demo" \
    -var="environment=testing" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="project_name=my-taskcat-demo" \
    -var="environment=testing" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

Deploy using the provided bash scripts:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="my-taskcat-demo"
export ENVIRONMENT="testing"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
aws cloudformation describe-stacks \
    --stack-name taskcat-testing-infrastructure \
    --query 'Stacks[0].Outputs'
```

## Post-Deployment Setup

After deploying the infrastructure, set up TaskCat for testing:

### 1. Install TaskCat

```bash
# Install TaskCat
pip install taskcat

# Verify installation
taskcat --version
```

### 2. Configure TaskCat Project

```bash
# Get the S3 bucket name from stack outputs
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name taskcat-testing-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskCatS3Bucket`].OutputValue' \
    --output text)

# Create TaskCat configuration
cat > .taskcat.yml << EOF
project:
  name: ${PROJECT_NAME:-taskcat-demo}
  owner: 'taskcat-demo@example.com'
  regions:
    - us-east-1
    - us-west-2
    - eu-west-1

tests:
  vpc-basic-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '10.0.0.0/16'
      EnvironmentName: 'TaskCatBasic'
      CreateNatGateway: 'true'
  
  vpc-no-nat-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '10.1.0.0/16'
      EnvironmentName: 'TaskCatNoNat'
      CreateNatGateway: 'false'
EOF
```

### 3. Create Test Templates

Create your CloudFormation templates to test in the `templates/` directory. The infrastructure provides the S3 bucket and IAM roles needed for TaskCat operations.

### 4. Run TaskCat Tests

```bash
# Validate templates
taskcat lint

# Run tests
taskcat test run --output-directory ./taskcat_outputs

# Generate reports
taskcat test run --output-directory ./reports --enable-sig-v2
```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Bucket**: For storing TaskCat test artifacts and reports
- **IAM Role**: For TaskCat execution with necessary permissions
- **VPC Template**: Sample CloudFormation template for testing
- **Test Configuration**: TaskCat configuration files
- **Validation Scripts**: Custom validation logic for testing

## Customization

### Configuration Variables

Customize the deployment by modifying these variables:

#### CloudFormation Parameters
- `ProjectName`: Name prefix for all resources
- `Environment`: Environment tag (dev, test, prod)
- `VpcCidr`: CIDR block for test VPC
- `CreateNatGateway`: Whether to create NAT Gateway in tests

#### CDK Context Variables
- `project_name`: Project name for resource naming
- `environment`: Environment designation
- `vpc_cidr`: VPC CIDR block for testing
- `multi_region_testing`: Enable testing across multiple regions

#### Terraform Variables
- `project_name`: Project identifier
- `environment`: Environment name
- `aws_region`: Primary AWS region
- `test_regions`: List of regions for multi-region testing
- `vpc_cidr`: CIDR block for test VPC

### Adding Custom Templates

To add your own CloudFormation templates for testing:

1. Place templates in the `templates/` directory
2. Update `.taskcat.yml` configuration with new test definitions
3. Add any required parameters to the test configuration
4. Run TaskCat validation and testing

### Extending Validation

Add custom validation scripts in the `tests/validation/` directory:

```bash
# Create custom validation script
cat > tests/validation/custom_test.py << 'EOF'
#!/usr/bin/env python3
import boto3
import sys

def validate_custom_resources(stack_name, region):
    # Add your custom validation logic here
    print(f"✅ Custom validation passed for {stack_name} in {region}")
    return True

if __name__ == "__main__":
    stack_name, region = sys.argv[1], sys.argv[2]
    success = validate_custom_resources(stack_name, region)
    sys.exit(0 if success else 1)
EOF

chmod +x tests/validation/custom_test.py
```

## Monitoring and Troubleshooting

### View TaskCat Logs

```bash
# View detailed logs
tail -f ~/.taskcat/logs/taskcat.log

# Check test results
ls -la ./taskcat_outputs/
```

### Common Issues

1. **Insufficient Permissions**: Ensure the IAM role has necessary permissions for all resources in your templates
2. **Region Limitations**: Some AWS services may not be available in all regions
3. **Resource Limits**: Check AWS service quotas for the resources being tested
4. **Template Errors**: Use `taskcat lint` to validate templates before testing

### Debugging Failed Tests

```bash
# Get detailed stack events
aws cloudformation describe-stack-events \
    --stack-name <failed-stack-name> \
    --region <region>

# Check CloudFormation console for detailed error messages
echo "Check CloudFormation console at:"
echo "https://console.aws.amazon.com/cloudformation/home?region=<region>"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the infrastructure stack
aws cloudformation delete-stack \
    --stack-name taskcat-testing-infrastructure \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name taskcat-testing-infrastructure \
    --region us-east-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy TaskCatTestingStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy TaskCatTestingStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_name=my-taskcat-demo" \
    -var="environment=testing" \
    -var="aws_region=us-east-1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `taskcat`)].StackName'
```

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Clean up TaskCat test stacks
taskcat test clean --project-root .

# Empty and delete S3 bucket
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name taskcat-testing-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskCatS3Bucket`].OutputValue' \
    --output text)

aws s3 rm s3://$S3_BUCKET --recursive
aws s3 rb s3://$S3_BUCKET
```

## Best Practices

1. **Version Control**: Keep TaskCat configurations and templates in version control
2. **Parameterization**: Use dynamic parameters (`$[taskcat_autobucket]`, `$[taskcat_genpass_16A]`) to avoid conflicts
3. **Multi-Region Testing**: Test templates in all regions where they will be deployed
4. **Validation Scripts**: Add custom validation beyond basic CloudFormation deployment success
5. **CI/CD Integration**: Integrate TaskCat into your CI/CD pipeline for automated testing
6. **Cost Management**: Use `taskcat test clean` regularly to remove test resources

## Security Considerations

- The IAM role created has permissions necessary for TaskCat operations
- S3 bucket is configured with encryption and public access blocking
- Review and adjust permissions based on your specific testing requirements
- Use least privilege principle for test environments

## Support

For issues with this infrastructure code:

1. Check the [TaskCat documentation](https://aws-quickstart.github.io/taskcat/)
2. Review the [CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
3. Refer to the original recipe documentation
4. Check AWS CloudFormation console for detailed error messages

## Additional Resources

- [AWS TaskCat GitHub Repository](https://github.com/aws-quickstart/taskcat)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)