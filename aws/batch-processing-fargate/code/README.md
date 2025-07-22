# Infrastructure as Code for Serverless Batch Processing with Fargate

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Batch Processing with Fargate".

## Recipe Overview

This infrastructure implements a serverless batch processing solution using AWS Batch with Fargate orchestration. The solution provides automatic compute provisioning, scaling, and resource management without server infrastructure overhead.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure creates the following AWS resources:

- **AWS Batch Compute Environment** (Fargate-based)
- **AWS Batch Job Queue** with priority configuration
- **AWS Batch Job Definition** for containerized workloads
- **Amazon ECR Repository** for container image storage
- **IAM Execution Role** for Fargate task permissions
- **CloudWatch Log Group** for centralized logging
- **Security Groups** and VPC networking configuration

## Prerequisites

### Required Tools
- AWS CLI v2 installed and configured
- Docker installed (for container image building)
- Appropriate AWS permissions for:
  - AWS Batch (full access)
  - Amazon ECR (full access)
  - IAM (role creation and management)
  - CloudWatch Logs (log group management)
  - VPC and EC2 (networking resources)

### Additional Prerequisites by Implementation

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### CDK TypeScript
- Node.js 16.x or later
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS provider credentials configured

### Cost Considerations

Estimated costs for this tutorial:
- **Fargate Tasks**: $0.04048 per vCPU per hour + $0.004445 per GB memory per hour
- **ECR Storage**: $0.10 per GB per month
- **CloudWatch Logs**: $0.50 per GB ingested
- **Total estimated cost**: $0.50-$2.00 for tutorial completion

> **Note**: Clean up resources promptly to minimize costs. Fargate pricing is based on actual resource consumption with per-second billing (1-minute minimum).

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name batch-fargate-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=demo

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name batch-fargate-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name batch-fargate-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy BatchFargateStack

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy BatchFargateStack

# View outputs
cdk ls --long
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

# The script will:
# 1. Create IAM roles and policies
# 2. Set up ECR repository
# 3. Build and push container image
# 4. Create Batch compute environment
# 5. Configure job queue and definition
# 6. Submit test jobs
```

## Post-Deployment Verification

After successful deployment, verify the infrastructure:

### Check Batch Environment Status

```bash
# List compute environments
aws batch describe-compute-environments \
    --query 'computeEnvironments[].{Name:computeEnvironmentName,State:state,Status:status}'

# Check job queue status
aws batch describe-job-queues \
    --query 'jobQueues[].{Name:jobQueueName,State:state,Priority:priority}'
```

### Submit Test Job

```bash
# Submit a test job (replace with your job queue and definition names)
aws batch submit-job \
    --job-name "test-job-$(date +%s)" \
    --job-queue "batch-fargate-queue-XXXXXX" \
    --job-definition "batch-fargate-job-XXXXXX"
```

### Monitor Job Execution

```bash
# List jobs in queue
aws batch list-jobs \
    --job-queue "batch-fargate-queue-XXXXXX"

# Get job details
aws batch describe-jobs \
    --jobs JOB_ID_HERE
```

## Container Image Management

### Building Custom Images

The infrastructure includes a sample Python container for batch processing. To customize:

1. **Modify the processing logic** in `batch-process.py`
2. **Update the Dockerfile** if dependencies change
3. **Rebuild and push** the image to ECR

```bash
# Build custom image
docker build -t my-batch-processor .

# Tag for ECR
docker tag my-batch-processor:latest \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/batch-processing-demo:latest

# Push to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/batch-processing-demo:latest
```

## Customization Options

### Environment Variables

All implementations support these customization parameters:

- **Environment Name**: Prefix for resource names
- **VPC Configuration**: Custom VPC and subnet IDs
- **Resource Limits**: vCPU and memory allocations
- **Log Retention**: CloudWatch log retention period
- **Container Image**: Custom ECR image URI

### Resource Configuration Examples

#### Adjusting Compute Resources

```bash
# For larger workloads, modify job definition resources
# In CloudFormation parameters:
JobVcpu: "1.0"
JobMemory: "2048"

# In Terraform variables:
job_vcpu = "1.0"
job_memory = "2048"
```

#### Scaling Configuration

```bash
# Modify compute environment max capacity
# In CloudFormation:
MaxvCpus: 512

# In Terraform:
max_vcpus = 512
```

## Monitoring and Logging

### CloudWatch Integration

All job execution logs are automatically sent to CloudWatch:

```bash
# View log groups
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/batch"

# View specific job logs
aws logs get-log-events \
    --log-group-name "/aws/batch/job" \
    --log-stream-name "batch-fargate/default/JOB_ID"
```

### Metrics and Alarms

The infrastructure includes basic CloudWatch metrics. To add custom alarms:

```bash
# Create alarm for failed jobs
aws cloudwatch put-metric-alarm \
    --alarm-name "BatchJobFailures" \
    --alarm-description "Alert on batch job failures" \
    --metric-name "FailedJobs" \
    --namespace "AWS/Batch" \
    --statistic "Sum" \
    --period 300 \
    --threshold 1 \
    --comparison-operator "GreaterThanOrEqualToThreshold"
```

## Security Considerations

### IAM Roles and Policies

The infrastructure implements least privilege access:

- **Execution Role**: Minimal permissions for Fargate task execution
- **Service Roles**: AWS-managed service roles for Batch operations
- **No Public Access**: All resources deployed in private subnets where possible

### Network Security

- Security groups restrict access to necessary ports only
- ECR repositories are private by default
- VPC configuration follows AWS security best practices

### Secrets Management

For production workloads, integrate with AWS Secrets Manager:

```bash
# Store sensitive configuration
aws secretsmanager create-secret \
    --name "batch-config" \
    --description "Batch job configuration" \
    --secret-string '{"database_url":"your-secret-value"}'
```

## Troubleshooting

### Common Issues

#### Jobs Stuck in RUNNABLE State
- **Cause**: Insufficient compute capacity or networking issues
- **Solution**: Check compute environment status and VPC configuration

#### Container Image Pull Failures
- **Cause**: ECR permissions or image not found
- **Solution**: Verify execution role permissions and image URI

#### Job Failures
- **Cause**: Application errors or resource constraints
- **Solution**: Check CloudWatch logs and resource allocation

### Debugging Commands

```bash
# Check compute environment status
aws batch describe-compute-environments \
    --compute-environments COMPUTE_ENV_NAME

# View job queue details
aws batch describe-job-queues \
    --job-queues JOB_QUEUE_NAME

# Get detailed job information
aws batch describe-jobs \
    --jobs JOB_ID
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name batch-fargate-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name batch-fargate-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy BatchFargateStack

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
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Cancel running jobs
# 2. Disable and delete job queue
# 3. Disable and delete compute environment
# 4. Remove ECR repository
# 5. Delete IAM roles
# 6. Clean up CloudWatch resources
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
aws batch describe-compute-environments
aws batch describe-job-queues
aws ecr describe-repositories
aws iam list-roles --query 'Roles[?contains(RoleName, `BatchFargate`)]'
```

## Performance Optimization

### Resource Right-Sizing

- **CPU Allocation**: Start with 0.25 vCPU for light workloads
- **Memory Allocation**: Use 512 MB for basic processing, scale as needed
- **Job Arrays**: Use for parallel processing of large datasets

### Cost Optimization

- **Spot Integration**: Consider hybrid compute environments with Spot instances for fault-tolerant workloads
- **Resource Scheduling**: Use job queues to optimize resource utilization
- **Log Retention**: Adjust CloudWatch log retention to balance cost and compliance needs

## Advanced Configuration

### Multi-Queue Setup

For complex workloads, implement multiple job queues:

```bash
# High-priority queue for real-time processing
# Standard queue for batch processing
# Low-priority queue for background tasks
```

### Integration Patterns

- **Step Functions**: Orchestrate complex workflows
- **EventBridge**: Trigger jobs based on events
- **S3 Integration**: Process files automatically on upload

## Support and Resources

### AWS Documentation
- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/)
- [Fargate User Guide](https://docs.aws.amazon.com/AmazonECS/latest/userguide/what-is-fargate.html)
- [ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/)

### Best Practices
- [AWS Batch Best Practices](https://docs.aws.amazon.com/batch/latest/userguide/best-practices.html)
- [Container Security Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security.html)

### Community Resources
- [AWS Samples Repository](https://github.com/aws-samples/)
- [AWS Batch Workshop](https://batch.workshop.aws/)

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS documentation links provided above.