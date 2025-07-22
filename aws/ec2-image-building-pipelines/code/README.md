# Infrastructure as Code for EC2 Image Building Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EC2 Image Building Pipelines".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - EC2 Image Builder (all actions)
  - EC2 (create instances, security groups, AMIs)
  - IAM (create roles, policies, instance profiles)
  - S3 (create buckets, upload objects)
  - SNS (create topics)
  - CloudWatch (logging)
- Understanding of AMI concepts and EC2 instance management
- Estimated cost: $5-15 for compute instances, storage, and data transfer during builds

## Architecture Overview

This IaC deploys a complete EC2 Image Builder pipeline including:

- **Build Component**: Web server setup with Apache and security hardening
- **Test Component**: Comprehensive validation of web server configuration
- **Image Recipe**: Combines base Amazon Linux 2 with custom components
- **Infrastructure Configuration**: Secure build environment with monitoring
- **Distribution Configuration**: Multi-region AMI distribution
- **Image Pipeline**: Automated orchestration with scheduled builds
- **Supporting Resources**: IAM roles, S3 bucket, SNS notifications, security groups

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-image-builder-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=PipelineName,ParameterValue=my-web-server-pipeline

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name ec2-image-builder-pipeline \
    --query 'Stacks[0].StackStatus'

# Trigger a manual build (after stack creation)
aws imagebuilder start-image-pipeline-execution \
    --image-pipeline-arn $(aws cloudformation describe-stacks \
        --stack-name ec2-image-builder-pipeline \
        --query 'Stacks[0].Outputs[?OutputKey==`PipelineArn`].OutputValue' \
        --output text)
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Trigger a manual build
npm run trigger-build
```

### Using CDK Python

```bash
# Set up Python virtual environment
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Trigger a manual build
python trigger_build.py
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# Trigger a manual build
aws imagebuilder start-image-pipeline-execution \
    --image-pipeline-arn $(terraform output -raw pipeline_arn)
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor build progress (optional)
./scripts/monitor-build.sh

# Clean up when done
./scripts/destroy.sh
```

## Configuration Options

### CloudFormation Parameters

- `PipelineName`: Name for the Image Builder pipeline (default: web-server-pipeline)
- `ComponentVersion`: Version for build components (default: 1.0.0)
- `InstanceType`: EC2 instance type for builds (default: t3.medium)
- `ScheduleExpression`: Cron expression for automated builds (default: weekly)
- `EnableSchedule`: Whether to enable automatic scheduling (default: true)

### CDK Configuration

Configure the deployment by modifying the stack parameters in the CDK app:

```typescript
// CDK TypeScript
const pipeline = new ImageBuilderPipeline(this, 'WebServerPipeline', {
  pipelineName: 'my-web-server-pipeline',
  instanceType: InstanceType.of(InstanceClass.T3, InstanceSize.MEDIUM),
  schedule: 'cron(0 2 * * SUN)',
  enableTesting: true
});
```

### Terraform Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
pipeline_name = "my-web-server-pipeline"
instance_type = "t3.medium"
schedule_expression = "cron(0 2 * * SUN)"
enable_schedule = true
aws_region = "us-west-2"
```

## Monitoring and Validation

### Check Pipeline Status

```bash
# List all pipelines
aws imagebuilder list-image-pipelines

# Get specific pipeline details
aws imagebuilder get-image-pipeline --image-pipeline-arn <pipeline-arn>

# List builds for a pipeline
aws imagebuilder list-image-pipeline-images --image-pipeline-arn <pipeline-arn>
```

### Monitor Build Progress

```bash
# Check build status
aws imagebuilder get-image --image-build-version-arn <build-arn>

# View build logs in CloudWatch
aws logs describe-log-groups --log-group-name-prefix /aws/imagebuilder

# Check S3 build logs
aws s3 ls s3://<bucket-name>/build-logs/ --recursive
```

### Test Generated AMI

```bash
# Get the latest AMI ID
AMI_ID=$(aws imagebuilder list-image-pipeline-images \
    --image-pipeline-arn <pipeline-arn> \
    --query 'images[0].outputResources.amis[0].image' \
    --output text)

# Launch a test instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --key-name your-key-pair
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will clean up all resources)
aws cloudformation delete-stack --stack-name ec2-image-builder-pipeline

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name ec2-image-builder-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Troubleshooting

### Common Issues

1. **Build Failures**:
   - Check CloudWatch logs for detailed error messages
   - Verify component YAML syntax
   - Ensure base AMI is available in your region

2. **Permission Errors**:
   - Verify IAM roles have required permissions
   - Check instance profile attachment
   - Ensure S3 bucket policies allow Image Builder access

3. **Network Issues**:
   - Verify security group allows outbound HTTPS (443) and HTTP (80)
   - Check subnet routing for internet access
   - Ensure NAT Gateway/Internet Gateway configuration

4. **Schedule Not Triggering**:
   - Verify pipeline status is ENABLED
   - Check schedule expression syntax
   - Ensure dependency update conditions are met

### Debug Commands

```bash
# Check Image Builder service status
aws imagebuilder list-components
aws imagebuilder list-image-recipes
aws imagebuilder list-infrastructure-configurations

# Validate component syntax
aws imagebuilder get-component --component-build-version-arn <component-arn>

# Check build instance logs
aws ssm describe-instance-information
aws ssm get-command-invocation --command-id <command-id> --instance-id <instance-id>
```

## Cost Optimization

### Build Cost Factors

- **Compute**: EC2 instances during build execution
- **Storage**: EBS volumes and AMI storage
- **Data Transfer**: Multi-region AMI copying
- **Logging**: CloudWatch Logs and S3 storage

### Cost Reduction Strategies

1. Use smaller instance types for simple builds
2. Implement AMI lifecycle policies to delete old images
3. Optimize component execution time
4. Use regional builds only when necessary
5. Enable detailed cost allocation tags

## Security Considerations

### Implemented Security Measures

- **Least Privilege IAM**: Minimal permissions for build execution
- **Network Isolation**: Restricted security groups
- **Session Manager**: No SSH access required
- **Encrypted Storage**: EBS volumes encrypted by default
- **Audit Logging**: Comprehensive CloudWatch logging

### Additional Security Enhancements

1. Enable AWS CloudTrail for API auditing
2. Implement VPC Flow Logs for network monitoring
3. Use AWS Config for configuration compliance
4. Enable GuardDuty for threat detection
5. Implement least privilege principle for cross-account sharing

## Best Practices

### Component Development

- Keep components focused on single responsibilities
- Use semantic versioning for component updates
- Test components thoroughly before production use
- Document component requirements and dependencies

### Pipeline Management

- Use descriptive naming conventions
- Implement proper tagging strategies
- Monitor build success rates and duration
- Maintain component and recipe documentation

### AMI Lifecycle

- Implement automated testing of generated AMIs
- Use consistent naming conventions with timestamps
- Establish retention policies for old AMIs
- Tag AMIs with environment and purpose metadata

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../ec2-image-building-pipelines-ec2-image-builder.md)
- [AWS EC2 Image Builder User Guide](https://docs.aws.amazon.com/imagebuilder/latest/userguide/)
- [AWS Image Builder API Reference](https://docs.aws.amazon.com/imagebuilder/latest/APIReference/)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

## License

This infrastructure code is provided as-is under the same license as the parent repository.