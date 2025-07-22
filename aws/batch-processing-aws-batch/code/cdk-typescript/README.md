# AWS CDK TypeScript - Batch Processing Workloads

This directory contains the AWS CDK TypeScript implementation for Batch Processing Workloads with AWS Batch.

## Architecture Overview

This CDK application creates a complete AWS Batch infrastructure including:

- **ECR Repository**: Container registry for batch processing images with vulnerability scanning
- **IAM Roles**: Service roles and instance roles with least privilege permissions
- **Compute Environment**: Managed EC2-based compute environment with auto-scaling and Spot instance optimization
- **Job Queue**: Priority-based job scheduling queue
- **Job Definition**: Container-based job definition template
- **CloudWatch Logging**: Centralized logging for job execution
- **CloudWatch Alarms**: Monitoring and alerting for job failures and queue utilization
- **Security Group**: Network security configuration for compute instances

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Docker installed (for building container images)
- Appropriate AWS permissions for creating IAM roles, EC2 resources, and AWS Batch components

## Quick Start

### 1. Install Dependencies

```bash
cd cdk-typescript/
npm install
```

### 2. Bootstrap CDK (first time only)

```bash
cdk bootstrap
```

### 3. Deploy the Infrastructure

```bash
# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Deploy with custom parameters
cdk deploy \
  -c environment=production \
  -c owner=data-team \
  -c costCenter=analytics
```

### 4. Build and Push Container Image

After deployment, build and push your batch processing container:

```bash
# Get ECR repository URI from stack outputs
ECR_URI=$(aws cloudformation describe-stacks \
  --stack-name BatchProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`EcrRepositoryUri`].OutputValue' \
  --output text)

# Create sample Dockerfile and application
cat > Dockerfile << 'EOF'
FROM python:3.9-slim
WORKDIR /app
RUN pip install numpy pandas boto3
COPY batch_processor.py .
CMD ["python", "batch_processor.py"]
EOF

# Build and push image
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URI

docker build -t batch-processing .
docker tag batch-processing:latest $ECR_URI:latest
docker push $ECR_URI:latest
```

### 5. Submit a Batch Job

```bash
# Get stack outputs
JOB_QUEUE=$(aws cloudformation describe-stacks \
  --stack-name BatchProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
  --output text)

JOB_DEFINITION=$(aws cloudformation describe-stacks \
  --stack-name BatchProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionArn`].OutputValue' \
  --output text)

# Submit a job
aws batch submit-job \
  --job-name "sample-batch-job" \
  --job-queue $JOB_QUEUE \
  --job-definition $JOB_DEFINITION \
  --parameters DATA_SIZE=1000,PROCESSING_TIME=60
```

## Configuration

### Context Parameters

You can customize the deployment using CDK context parameters:

```bash
cdk deploy -c environment=production -c owner=your-team
```

Available context parameters:
- `environment`: Deployment environment (development, staging, production)
- `owner`: Team or individual responsible for the resources
- `costCenter`: Cost allocation identifier
- `stackName`: Custom stack name (default: BatchProcessingStack)

### Environment Variables

Set these environment variables before deployment:
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region

## Project Structure

```
cdk-typescript/
├── app.ts                     # CDK application entry point
├── lib/
│   └── batch-processing-stack.ts  # Main stack implementation
├── package.json               # Node.js dependencies and scripts
├── tsconfig.json             # TypeScript configuration
├── cdk.json                  # CDK configuration
└── README.md                 # This file
```

## Key Components

### BatchProcessingStack

The main CDK stack that creates all AWS resources:

- **ECR Repository**: Stores container images with lifecycle policies
- **Compute Environment**: Auto-scaling EC2 instances with Spot integration
- **Job Queue**: Prioritized job scheduling
- **Job Definition**: Container specifications and resource requirements
- **CloudWatch Resources**: Logging and monitoring

### Security Features

- **IAM Roles**: Least privilege access for Batch service and EC2 instances
- **Security Groups**: Network isolation for compute instances
- **ECR Scanning**: Automatic vulnerability scanning for container images
- **VPC Integration**: Secure networking within your VPC

### Cost Optimization

- **Spot Instances**: Up to 50% cost reduction with Spot instance integration
- **Auto Scaling**: Scale to zero when no jobs are running
- **Resource Limits**: Configurable minimum and maximum compute capacity
- **Lifecycle Policies**: Automatic cleanup of old container images

## Monitoring and Troubleshooting

### CloudWatch Logs

All job logs are centralized in CloudWatch Logs:

```bash
# View job logs
LOG_GROUP="/aws/batch/job"
aws logs describe-log-streams --log-group-name $LOG_GROUP
```

### CloudWatch Alarms

The stack creates alarms for:
- Job failures (threshold: 1 failed job)
- Queue utilization (threshold: 10 runnable jobs)

### Job Monitoring

```bash
# List jobs in queue
aws batch list-jobs --job-queue $JOB_QUEUE

# Describe specific job
aws batch describe-jobs --jobs JOB_ID
```

## Cleanup

### Destroy Infrastructure

```bash
# Cancel running jobs first
aws batch list-jobs --job-queue $JOB_QUEUE --job-status RUNNING \
  --query 'jobSummaryList[*].jobId' --output text | \
  xargs -I {} aws batch cancel-job --job-id {} --reason "Cleanup"

# Destroy the stack
cdk destroy
```

## Advanced Configuration

### Custom Instance Types

Modify the `createComputeEnvironment` method in `batch-processing-stack.ts`:

```typescript
instanceTypes: [
  ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
  ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
],
```

### Multi-AZ Deployment

The stack automatically uses all available subnets in the default VPC for high availability.

### Custom VPC

To use a custom VPC, modify the `createOrGetVpc` method:

```typescript
const vpc = ec2.Vpc.fromLookup(this, 'CustomVpc', {
  vpcId: 'vpc-12345678',
});
```

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# Lint code
npm run lint

# Format code
npm run format
```

### CDK Commands

```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# Deploy to specific account/region
cdk deploy --profile my-profile --region us-west-2
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
2. **Compute Environment Failed**: Check VPC configuration and subnet availability
3. **Job Stuck in RUNNABLE**: Verify compute environment has available capacity
4. **Container Pull Errors**: Ensure ECR repository permissions are configured

### Debug Mode

Enable CDK debug logging:

```bash
cdk deploy --debug
```

## Security Best Practices

- Use least privilege IAM policies
- Enable VPC Flow Logs for network monitoring
- Regularly update container base images
- Use AWS Config for compliance monitoring
- Enable AWS CloudTrail for audit logging

## Support

For issues with this CDK implementation:
1. Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review AWS Batch documentation: https://docs.aws.amazon.com/batch/
3. Submit issues to the project repository

## License

This code is provided under the MIT License. See LICENSE file for details.