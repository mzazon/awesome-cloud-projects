# TaskCat Infrastructure Testing - CDK TypeScript

This CDK TypeScript application deploys a comprehensive infrastructure testing framework using TaskCat and CloudFormation. The solution provides automated testing capabilities for CloudFormation templates across multiple AWS regions.

## Architecture Overview

The CDK application creates:

- **VPC Infrastructure**: Multi-AZ VPC with public and private subnets
- **S3 Bucket**: Secure storage for TaskCat artifacts and test results
- **IAM Role**: Comprehensive permissions for TaskCat testing operations
- **CodeCommit Repository**: Source control for CloudFormation templates
- **CodeBuild Project**: Automated TaskCat testing pipeline
- **EventBridge Rules**: Automated testing triggers (optional)
- **Security Groups**: Network security for testing resources

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for resource creation
- Basic understanding of TypeScript and AWS CDK

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy with default configuration
cdk deploy

# Deploy with custom parameters
cdk deploy --parameters vpcCidr=10.1.0.0/16 --parameters environmentName=MyTaskCatDemo
```

### 4. Verify Deployment

```bash
# List stack outputs
aws cloudformation describe-stacks --stack-name TaskCatInfrastructureStack --query 'Stacks[0].Outputs'

# Check S3 bucket
aws s3 ls | grep taskcat-artifacts

# Verify CodeCommit repository
aws codecommit list-repositories
```

## Configuration Options

The stack accepts several configuration parameters through the CDK context or constructor props:

```typescript
new TaskCatInfrastructureStack(app, 'TaskCatInfrastructureStack', {
  vpcCidr: '10.0.0.0/16',              // VPC CIDR block
  environmentName: 'TaskCatDemo',       // Environment name for tagging
  createNatGateway: true,               // Enable NAT Gateway for private subnets
  enableAutomatedTesting: false,       // Enable automated testing on code changes
});
```

## Using the Infrastructure

### 1. Clone the CloudFormation Repository

```bash
# Get repository URL from stack outputs
REPO_URL=$(aws cloudformation describe-stacks \
  --stack-name TaskCatInfrastructureStack \
  --query 'Stacks[0].Outputs[?OutputKey==`CodeRepositoryCloneUrl`].OutputValue' \
  --output text)

# Clone the repository
git clone $REPO_URL cloudformation-templates
cd cloudformation-templates
```

### 2. Add CloudFormation Templates

```bash
# Create templates directory
mkdir -p templates

# Add your CloudFormation templates
cp your-template.yaml templates/

# Create TaskCat configuration
cat > .taskcat.yml << EOF
project:
  name: my-taskcat-project
  regions:
    - us-east-1
    - us-west-2

tests:
  template-test:
    template: templates/your-template.yaml
    parameters:
      ParameterName: ParameterValue
EOF
```

### 3. Run TaskCat Tests

#### Manual Testing

```bash
# Install TaskCat
pip install taskcat

# Run tests locally
taskcat test run

# Generate reports
taskcat test run --output-directory ./reports
```

#### Automated Testing via CodeBuild

```bash
# Commit and push templates
git add .
git commit -m "Add CloudFormation templates"
git push origin main

# Trigger build manually
BUILD_PROJECT=$(aws cloudformation describe-stacks \
  --stack-name TaskCatInfrastructureStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BuildProjectName`].OutputValue' \
  --output text)

aws codebuild start-build --project-name $BUILD_PROJECT
```

## Advanced Features

### 1. Multi-Region Testing

The infrastructure supports testing across multiple AWS regions:

```yaml
# .taskcat.yml
project:
  regions:
    - us-east-1
    - us-west-2
    - eu-west-1
    - ap-southeast-1

tests:
  multi-region-test:
    template: templates/vpc-template.yaml
    regions:
      - us-east-1
      - eu-west-1
```

### 2. Dynamic Parameters

TaskCat supports dynamic parameter generation:

```yaml
# .taskcat.yml
tests:
  dynamic-test:
    template: templates/advanced-template.yaml
    parameters:
      BucketName: $[taskcat_autobucket]
      Password: $[taskcat_genpass_16A]
      KeyPair: $[taskcat_getkeypair]
```

### 3. Custom Validation Scripts

Add custom validation scripts to your repository:

```bash
mkdir -p tests/validation
cat > tests/validation/test_resources.py << 'EOF'
#!/usr/bin/env python3
import boto3
import sys

def validate_resources(stack_name, region):
    # Add your validation logic here
    pass

if __name__ == "__main__":
    validate_resources(sys.argv[1], sys.argv[2])
EOF
```

## Development

### Building and Testing

```bash
# Build TypeScript
npm run build

# Run tests
npm test

# Lint code
npm run lint

# Format code
npm run format

# Watch for changes
npm run watch
```

### Customizing the Stack

Extend the stack by modifying `lib/taskcat-infrastructure-stack.ts`:

```typescript
// Add additional resources
const additionalBucket = new s3.Bucket(this, 'AdditionalBucket', {
  // configuration
});

// Modify existing resources
this.vpc.addInterfaceEndpoint('S3Endpoint', {
  service: ec2.InterfaceVpcEndpointAwsService.S3,
});
```

## Security Considerations

- The TaskCat role has broad permissions for testing purposes
- S3 bucket blocks all public access
- VPC uses private subnets with NAT Gateway for outbound access
- Security groups restrict inbound access to VPC CIDR only
- CodeBuild runs in VPC for network isolation

## Cost Optimization

- NAT Gateway can be disabled for cost savings (`createNatGateway: false`)
- S3 bucket includes lifecycle policies for automatic cleanup
- CodeBuild uses SMALL compute type for cost efficiency
- Automated testing can be disabled to prevent unexpected charges

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Region Not Supported**: Verify TaskCat supports your target regions
3. **Template Errors**: Use `taskcat lint` to validate templates before testing
4. **Build Failures**: Check CodeBuild logs for detailed error messages

### Useful Commands

```bash
# Check stack events
aws cloudformation describe-stack-events --stack-name TaskCatInfrastructureStack

# View CodeBuild logs
aws logs describe-log-groups --log-group-name-prefix /aws/codebuild/taskcat

# List S3 bucket contents
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name TaskCatInfrastructureStack \
  --query 'Stacks[0].Outputs[?OutputKey==`TaskCatBucketName`].OutputValue' \
  --output text)
aws s3 ls s3://$BUCKET_NAME --recursive
```

## Cleanup

To remove all resources:

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

## Support

For issues and questions:

- Check the [TaskCat documentation](https://aws-taskcat.readthedocs.io/)
- Review AWS CloudFormation best practices
- Consult the AWS CDK documentation

## License

This project is licensed under the MIT License - see the LICENSE file for details.