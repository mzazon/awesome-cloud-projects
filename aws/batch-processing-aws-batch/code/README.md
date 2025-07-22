# Infrastructure as Code for Batch Processing Workloads with AWS Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Batch Processing Workloads with AWS Batch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete AWS Batch environment including:

- **AWS Batch Compute Environment**: Managed EC2 instances with auto-scaling (0-100 vCPUs)
- **Job Queue**: Priority-based job scheduling
- **Job Definition**: Container-based batch job blueprint
- **ECR Repository**: Container image storage with vulnerability scanning
- **IAM Roles**: Service roles for AWS Batch and EC2 instance profile
- **CloudWatch Logs**: Centralized logging for job execution
- **Security Group**: Network access control for compute resources
- **CloudWatch Alarms**: Monitoring and alerting for job failures and queue utilization

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed (for container image building)
- Appropriate AWS permissions for:
  - AWS Batch (full access)
  - EC2 (launch instances, manage security groups)
  - ECR (create repositories, push images)
  - IAM (create roles and policies)
  - CloudWatch (create log groups and alarms)
  - VPC (describe default VPC and subnets)
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-15 for compute resources during deployment

> **Note**: This solution uses EC2 instances and may incur charges. Clean up resources when finished to avoid ongoing costs.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name batch-processing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=batch-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name batch-processing-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name batch-processing-stack \
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
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply configuration
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

# The script will prompt for configuration values
# and display deployment progress
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Build and Push Container Image**:
   ```bash
   # Get ECR repository URI from outputs
   ECR_REPO_URI=$(aws cloudformation describe-stacks \
       --stack-name batch-processing-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
       --output text)
   
   # Login to ECR
   aws ecr get-login-password --region us-east-1 | \
       docker login --username AWS --password-stdin $ECR_REPO_URI
   
   # Build and push your application image
   docker build -t batch-app .
   docker tag batch-app:latest $ECR_REPO_URI:latest
   docker push $ECR_REPO_URI:latest
   ```

2. **Submit Test Job**:
   ```bash
   # Get job queue and definition names from outputs
   JOB_QUEUE=$(aws cloudformation describe-stacks \
       --stack-name batch-processing-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
       --output text)
   
   JOB_DEFINITION=$(aws cloudformation describe-stacks \
       --stack-name batch-processing-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionArn`].OutputValue' \
       --output text)
   
   # Submit a test job
   aws batch submit-job \
       --job-name test-job \
       --job-queue $JOB_QUEUE \
       --job-definition $JOB_DEFINITION
   ```

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Name prefix for all resources (default: batch-processing)
- `MaxvCpus`: Maximum vCPUs for compute environment (default: 100)
- `InstanceTypes`: EC2 instance types for compute environment (default: optimal)
- `SpotBidPercentage`: Spot instance bid percentage (default: 50)

### CDK Configuration
Edit the configuration variables at the top of `app.ts` or `app.py`:
- `project_name`: Resource naming prefix
- `max_vcpus`: Maximum compute capacity
- `instance_types`: Allowed instance types
- `spot_bid_percentage`: Spot pricing configuration

### Terraform Variables
Customize deployment by setting variables in `terraform.tfvars`:
```hcl
project_name = "my-batch-env"
max_vcpus = 200
instance_types = ["m5.large", "m5.xlarge"]
spot_bid_percentage = 60
```

## Monitoring and Troubleshooting

### View Job Status
```bash
# List jobs in queue
aws batch list-jobs --job-queue <job-queue-name>

# Get detailed job information
aws batch describe-jobs --jobs <job-id>

# View job logs
aws logs get-log-events \
    --log-group-name /aws/batch/job \
    --log-stream-name <log-stream-name>
```

### Check Compute Environment
```bash
# Monitor compute environment status
aws batch describe-compute-environments \
    --compute-environments <compute-env-name>

# Check EC2 instances in compute environment
aws ec2 describe-instances \
    --filters "Name=tag:aws:batch:compute-environment,Values=<compute-env-name>"
```

### CloudWatch Alarms
The deployment includes alarms for:
- **Failed Jobs**: Alerts when jobs fail
- **High Queue Utilization**: Alerts when queue utilization exceeds 80%

View alarms in the AWS Console or via CLI:
```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix "BatchJobFailures"
```

## Security Considerations

This deployment implements security best practices:

- **IAM Roles**: Least privilege access for Batch service and EC2 instances
- **VPC Security**: Uses default VPC with security group restricting access
- **Container Security**: ECR vulnerability scanning enabled
- **Encryption**: CloudWatch Logs encrypted at rest
- **Network Isolation**: Compute resources deployed in private subnets (if available)

## Cost Optimization

The solution includes several cost optimization features:

- **Spot Instances**: 50% spot instance utilization to reduce costs
- **Auto-scaling**: Scales from 0 to maximum vCPUs based on demand
- **Optimal Instance Selection**: AWS Batch automatically selects cost-effective instance types
- **Log Retention**: 30-day log retention to manage storage costs

Monitor costs using:
```bash
# Get cost and usage for AWS Batch
aws ce get-cost-and-usage \
    --time-period Start=2023-01-01,End=2023-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Customization

### Environment Variables

Common customization options:

- **Compute Environment**:
  - `minvCpus`: Minimum vCPUs (default: 0)
  - `maxvCpus`: Maximum vCPUs (default: 100)
  - `desiredvCpus`: Desired vCPUs (default: 0)
  - `spotBidPercentage`: Spot instance bid percentage (default: 50)

- **Job Definition**:
  - `jobTimeout`: Job timeout in seconds (default: 3600)
  - `vcpus`: vCPUs per job (default: 1)
  - `memory`: Memory per job in MiB (default: 512)

- **Networking**:
  - VPC ID and subnet IDs for compute resources
  - Security group configurations

### Instance Types

Modify instance types in the compute environment:

- **Optimal**: Let AWS choose (recommended)
- **Specific**: c5.large, m5.xlarge, etc.
- **Families**: c5, m5, r5 for different workload patterns

## Cost Optimization

### Spot Instances

- Default configuration uses 50% Spot instances
- Adjust `spotBidPercentage` based on workload tolerance
- Monitor Spot instance interruptions in CloudWatch

### Auto Scaling

- Compute environment scales from 0 to max vCPUs automatically
- Resources are terminated when idle
- Set appropriate `desiredvCpus` for baseline capacity

### Instance Right-Sizing

- Monitor CloudWatch metrics for CPU and memory utilization
- Adjust job definition resource requirements accordingly
- Use different job definitions for different workload types

## Security Best Practices

### IAM Permissions

- Service roles follow least privilege principle
- Instance profiles include only necessary ECS permissions
- Container execution roles can be customized per job definition

### Network Security

- Compute instances run in private subnets (recommended)
- Security groups restrict access to necessary ports only
- VPC endpoints can be used for AWS service access

### Container Security

- ECR vulnerability scanning enabled by default
- Use minimal base images for containers
- Regularly update container images and dependencies

## Troubleshooting

### Common Issues

1. **Compute Environment Creation Fails**:
   - Verify IAM service role has correct permissions
   - Check VPC and subnet configurations
   - Ensure instance profile exists and is properly configured

2. **Jobs Stuck in RUNNABLE State**:
   - Check compute environment capacity
   - Verify instance types are available in selected AZs
   - Review Spot instance availability

3. **Container Image Pull Failures**:
   - Verify ECR repository permissions
   - Check image URI in job definition
   - Ensure compute instances have ECR access

### Debugging Commands

```bash
# Check compute environment details
aws batch describe-compute-environments \
    --compute-environments <compute-env-name>

# List job queue status
aws batch describe-job-queues \
    --job-queues <job-queue-name>

# Get job failure reasons
aws batch describe-jobs --jobs <job-id> \
    --query 'jobs[0].statusReason'
```

## Customization

### Adding Custom Job Definitions
Create additional job definitions for different workload types:

```bash
aws batch register-job-definition \
    --job-definition-name my-custom-job \
    --type container \
    --container-properties '{
        "image": "my-account.dkr.ecr.region.amazonaws.com/my-repo:latest",
        "vcpus": 2,
        "memory": 2048,
        "environment": [
            {"name": "CUSTOM_ENV_VAR", "value": "custom_value"}
        ]
    }'
```

### Multi-Queue Architecture
Extend the solution with multiple queues for different priorities:

```bash
# Create high-priority queue
aws batch create-job-queue \
    --job-queue-name high-priority-queue \
    --state ENABLED \
    --priority 100 \
    --compute-environment-order order=1,computeEnvironment=<compute-env-name>

# Create low-priority queue
aws batch create-job-queue \
    --job-queue-name low-priority-queue \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order order=1,computeEnvironment=<compute-env-name>
```

### Array Jobs for Parallel Processing
Submit array jobs for embarrassingly parallel workloads:

```bash
aws batch submit-job \
    --job-name parallel-processing \
    --job-queue <job-queue-name> \
    --job-definition <job-definition-name> \
    --array-properties size=10
```

## Troubleshooting

### Common Issues

1. **Jobs Stuck in RUNNABLE State**:
   - Check compute environment status
   - Verify EC2 service limits
   - Review IAM permissions

2. **Container Image Pull Errors**:
   - Verify ECR repository URI
   - Check IAM permissions for ECR access
   - Ensure image exists and is tagged correctly

3. **Job Failures**:
   - Review CloudWatch Logs for error messages
   - Check resource requirements (CPU, memory)
   - Verify environment variables and job parameters

### Debug Commands
```bash
# Check compute environment events
aws batch describe-compute-environments \
    --compute-environments <name> \
    --query 'computeEnvironments[0].events'

# List failed jobs
aws batch list-jobs \
    --job-queue <queue-name> \
    --job-status FAILED

# Get job failure reason
aws batch describe-jobs --jobs <job-id> \
    --query 'jobs[0].statusReason'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name batch-processing-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name batch-processing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
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

> **Warning**: Ensure all batch jobs are completed or cancelled before cleanup to avoid leaving orphaned EC2 instances.

## Performance Optimization

### Job Parallelization

- Use array jobs for embarrassingly parallel workloads
- Configure appropriate array sizes based on data partitioning
- Monitor queue utilization to optimize throughput

### Resource Allocation

- Profile jobs to determine optimal CPU and memory requirements
- Use different job definitions for different workload types
- Consider GPU instances for compute-intensive tasks

### Data Access Patterns

- Use Amazon EFS for shared file systems
- Implement S3 data staging for large datasets
- Consider data locality when scheduling jobs

## Advanced Configuration

### Multi-Queue Setup

Create separate queues for different priorities:

```bash
# High priority queue
aws batch create-job-queue \
    --job-queue-name high-priority-queue \
    --priority 100 \
    --compute-environment-order order=1,computeEnvironment=<compute-env>

# Low priority queue  
aws batch create-job-queue \
    --job-queue-name low-priority-queue \
    --priority 10 \
    --compute-environment-order order=1,computeEnvironment=<compute-env>
```

### Job Dependencies

Create dependent job workflows:

```bash
# Submit parent job
PARENT_JOB_ID=$(aws batch submit-job \
    --job-name parent-job \
    --job-queue <queue-name> \
    --job-definition <job-def> \
    --query 'jobId' --output text)

# Submit dependent job
aws batch submit-job \
    --job-name child-job \
    --job-queue <queue-name> \
    --job-definition <job-def> \
    --depends-on jobId=${PARENT_JOB_ID}
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS Batch documentation: https://docs.aws.amazon.com/batch/
3. Verify AWS service limits and quotas
4. Review CloudWatch Logs and metrics

For AWS Batch best practices, see: https://docs.aws.amazon.com/batch/latest/userguide/best-practices.html