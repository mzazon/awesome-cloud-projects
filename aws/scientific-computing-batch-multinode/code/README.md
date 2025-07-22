# Infrastructure as Code for Implementing Scientific Computing with Batch Multi-Node

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Scientific Computing with Batch Multi-Node".

## Overview

This recipe demonstrates how to build a scalable, distributed scientific computing platform using AWS Batch multi-node parallel jobs. The solution enables tightly-coupled parallel processing across multiple EC2 instances with MPI (Message Passing Interface) communication, shared storage via Amazon EFS, and containerized scientific applications deployed through Amazon ECR.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Required Tools

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Docker installed for building container images
- Node.js 16+ and npm (for CDK TypeScript)
- Python 3.7+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

### AWS Permissions

Your AWS credentials must have permissions for the following services:
- AWS Batch (full access)
- Amazon EC2 (VPC, security groups, instances)
- Amazon ECR (repository management)
- Amazon EFS (file system creation and management)
- AWS IAM (role and policy management)
- Amazon CloudWatch (monitoring and logging)

### Knowledge Prerequisites

- Understanding of MPI programming concepts and parallel computing
- Familiarity with scientific computing workflows and job scheduling
- Basic knowledge of containerization with Docker

### Estimated Costs

**Hourly operational costs**: $2-10/hour depending on instance types and node count

> **Warning**: Multi-node parallel jobs use dedicated instances and can be expensive. Always monitor costs and follow cleanup procedures to avoid unexpected charges.

## Architecture

The solution creates the following components:

- **VPC and Networking**: Dedicated VPC with public subnet, internet gateway, and enhanced networking support
- **Security Groups**: Configured for MPI communication between nodes and EFS access
- **EFS Filesystem**: Shared storage for input/output data and intermediate results
- **ECR Repository**: Container registry for MPI-enabled scientific computing images
- **IAM Roles**: Service roles for AWS Batch and EC2 instance profiles
- **Batch Infrastructure**: Managed compute environment, job queue, and multi-node job definitions
- **Monitoring**: CloudWatch dashboards and alarms for job monitoring

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name scientific-computing-batch \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-sci-cluster

# Monitor deployment status
aws cloudformation wait stack-create-complete \
    --stack-name scientific-computing-batch

# Get outputs
aws cloudformation describe-stacks \
    --stack-name scientific-computing-batch \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
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
# 1. Create VPC and networking components
# 2. Set up security groups for MPI communication
# 3. Create EFS filesystem for shared storage
# 4. Build and push MPI container image to ECR
# 5. Create IAM roles and Batch infrastructure
# 6. Configure monitoring and job submission tools
```

## Configuration Options

### Environment Variables

All implementations support the following environment variables for customization:

```bash
# Set your preferred AWS region
export AWS_REGION=us-west-2

# Customize cluster naming
export CLUSTER_NAME=my-scientific-cluster

# Configure instance types for compute environment
export INSTANCE_TYPES="c5.large,c5.xlarge,c5.2xlarge"

# Set EFS throughput mode
export EFS_THROUGHPUT_MODE=provisioned
export EFS_PROVISIONED_THROUGHPUT=100

# Configure maximum vCPUs for scaling
export MAX_VCPUS=512
```

### Terraform Variables

For Terraform deployment, customize variables in `terraform.tfvars`:

```hcl
cluster_name = "my-scientific-cluster"
vpc_cidr = "10.0.0.0/16"
instance_types = ["c5.large", "c5.xlarge", "c5.2xlarge"]
max_vcpus = 256
efs_throughput_mode = "provisioned"
efs_provisioned_throughput = 100
```

### CloudFormation Parameters

For CloudFormation deployment, specify parameters:

```bash
aws cloudformation create-stack \
    --stack-name scientific-computing-batch \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ClusterName,ParameterValue=my-sci-cluster \
        ParameterKey=InstanceTypes,ParameterValue="c5.large,c5.xlarge" \
        ParameterKey=MaxvCpus,ParameterValue=256 \
        ParameterKey=EFSThroughputMode,ParameterValue=provisioned
```

## Usage Examples

### Submitting a Multi-Node Job

After deployment, use the generated job submission script:

```bash
# Basic job submission
./submit-scientific-job.sh \
    --job-name "molecular-dynamics-sim" \
    --nodes 4 \
    --vcpus 4 \
    --memory 8192

# Advanced job with custom paths
./submit-scientific-job.sh \
    --job-name "weather-modeling" \
    --nodes 8 \
    --vcpus 2 \
    --memory 4096 \
    --input-path "/mnt/efs/weather-data" \
    --output-path "/mnt/efs/results"
```

### Monitoring Jobs

```bash
# Check job status
aws batch describe-jobs --jobs $JOB_ID

# View job logs
aws logs tail /aws/batch/job --follow

# Monitor compute environment scaling
aws batch describe-compute-environments \
    --compute-environments $COMPUTE_ENV_NAME
```

### Scaling the Cluster

```bash
# Update maximum vCPUs for larger workloads
aws batch update-compute-environment \
    --compute-environment $COMPUTE_ENV_NAME \
    --compute-resources maxvCpus=512

# Submit multiple concurrent jobs for scale testing
for i in {1..5}; do
    aws batch submit-job \
        --job-name "scale-test-$i" \
        --job-queue $JOB_QUEUE_NAME \
        --job-definition $JOB_DEFINITION_NAME
done
```

## Validation & Testing

### Infrastructure Validation

```bash
# Verify VPC and networking
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*scientific*"

# Check EFS filesystem status
aws efs describe-file-systems

# Validate ECR repository
aws ecr describe-repositories

# Confirm Batch resources
aws batch describe-compute-environments
aws batch describe-job-queues
aws batch describe-job-definitions
```

### Application Testing

```bash
# Submit test job
JOB_ID=$(aws batch submit-job \
    --job-name "test-mpi-communication" \
    --job-queue $JOB_QUEUE_NAME \
    --job-definition $JOB_DEFINITION_NAME \
    --query 'jobId' --output text)

# Monitor job progress
aws batch wait job-status-succeeded --job-id $JOB_ID

# Verify job completed successfully
aws batch describe-jobs --jobs $JOB_ID \
    --query 'jobs[0].status'
```

### Performance Testing

```bash
# Test with different node counts
for nodes in 2 4 8; do
    aws batch submit-job \
        --job-name "perf-test-${nodes}nodes" \
        --job-queue $JOB_QUEUE_NAME \
        --job-definition $JOB_DEFINITION_NAME \
        --node-overrides numNodes=$nodes
done

# Monitor resource utilization
aws cloudwatch get-metric-statistics \
    --namespace AWS/Batch \
    --metric-name RunningJobs \
    --dimensions Name=JobQueue,Value=$JOB_QUEUE_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Customization

### Adding Custom Scientific Applications

1. **Modify the Dockerfile** in your container build process:

```dockerfile
# Add your scientific application
COPY my-app/ /app/my-app/
RUN cd /app/my-app && make install

# Update the run script
COPY my-run-script.sh /app/
```

2. **Update the job definition** to use your custom application:

```json
{
    "container": {
        "image": "your-ecr-repo:your-tag",
        "command": ["/app/my-run-script.sh"],
        "environment": [
            {"name": "APP_CONFIG", "value": "/mnt/efs/config.ini"}
        ]
    }
}
```

### Integrating with External Data Sources

```bash
# Mount additional EFS access points
aws efs create-access-point \
    --file-system-id $EFS_ID \
    --posix-user Uid=1000,Gid=1000 \
    --root-directory Path="/datasets",CreationInfo='{OwnerUid=1000,OwnerGid=1000,Permissions=755}'

# Configure S3 data synchronization
aws s3 sync s3://my-scientific-data/ /mnt/efs/input/
```

### Performance Optimization

```bash
# Use compute-optimized instances for CPU-intensive workloads
aws batch update-compute-environment \
    --compute-environment $COMPUTE_ENV_NAME \
    --compute-resources instanceTypes=["c5n.large","c5n.xlarge","c5n.2xlarge"]

# Enable placement groups for low-latency communication
aws ec2 create-placement-group \
    --group-name scientific-computing-pg \
    --strategy cluster
```

## Troubleshooting

### Common Issues

1. **Jobs stuck in RUNNABLE state**:
   ```bash
   # Check compute environment capacity
   aws batch describe-compute-environments \
       --compute-environments $COMPUTE_ENV_NAME \
       --query 'computeEnvironments[0].computeResources.{Current:desiredvCpus,Max:maxvCpus}'
   
   # Verify instance limits
   aws service-quotas get-service-quota \
       --service-code ec2 \
       --quota-code L-1216C47A
   ```

2. **MPI communication failures**:
   ```bash
   # Verify security group rules
   aws ec2 describe-security-groups \
       --group-ids $SECURITY_GROUP_ID \
       --query 'SecurityGroups[0].IpPermissions'
   
   # Check network configuration
   aws ec2 describe-subnets --subnet-ids $SUBNET_ID
   ```

3. **EFS mount issues**:
   ```bash
   # Verify mount targets
   aws efs describe-mount-targets --file-system-id $EFS_ID
   
   # Check security group for NFS traffic
   aws ec2 describe-security-groups \
       --filters "Name=group-name,Values=*batch*" \
       --query 'SecurityGroups[0].IpPermissions[?FromPort==`2049`]'
   ```

### Debugging Commands

```bash
# Get detailed job information
aws batch describe-jobs --jobs $JOB_ID \
    --query 'jobs[0].{Status:status,Reason:statusReason,Log:attempts[0].logStreamName}'

# Access container logs
aws logs get-log-events \
    --log-group-name /aws/batch/job \
    --log-stream-name $LOG_STREAM_NAME

# Check instance health
aws ec2 describe-instances \
    --filters "Name=tag:aws:batch:compute-environment,Values=$COMPUTE_ENV_NAME" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,LaunchTime]'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name scientific-computing-batch

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name scientific-computing-batch
```

### Using CDK

```bash
# For TypeScript
cd cdk-typescript/
cdk destroy

# For Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Cancel any running jobs
# 2. Delete Batch resources (job queues, compute environments)
# 3. Remove storage resources (EFS, ECR)
# 4. Clean up IAM roles and networking
# 5. Delete monitoring resources
```

### Manual Cleanup (if needed)

```bash
# Cancel all running jobs
aws batch list-jobs --job-queue $JOB_QUEUE_NAME --job-status RUNNING \
    | jq -r '.jobSummaryList[].jobId' \
    | xargs -I {} aws batch terminate-job --job-id {} --reason "Manual cleanup"

# Delete ECR images
aws ecr batch-delete-image \
    --repository-name $ECR_REPO_NAME \
    --image-ids imageTag=latest

# Remove CloudWatch logs
aws logs delete-log-group --log-group-name /aws/batch/job
```

## Security Considerations

### Best Practices

1. **Network Security**:
   - Security groups restrict MPI communication to cluster nodes only
   - EFS access limited to compute instances via security group rules
   - No public internet access to compute nodes except for package downloads

2. **IAM Security**:
   - Minimal permissions following principle of least privilege
   - Service-specific roles for Batch and EC2 instances
   - No hardcoded credentials in container images

3. **Data Protection**:
   - EFS encryption at rest enabled by default
   - ECR image scanning enabled for vulnerability detection
   - Container images run with non-root privileges where possible

### Monitoring & Compliance

```bash
# Enable CloudTrail for audit logging
aws cloudtrail create-trail \
    --name scientific-computing-trail \
    --s3-bucket-name your-logging-bucket

# Configure Config rules for compliance
aws configservice put-config-rule \
    --config-rule ConfigRuleName=batch-compute-environment-encrypted \
    Source='{Owner=AWS,SourceIdentifier=BATCH_COMPUTE_ENVIRONMENT_ENCRYPTED}'
```

## Cost Optimization

### Recommendations

1. **Use Spot Instances** for fault-tolerant workloads:
   ```bash
   # Update compute environment to use Spot instances
   aws batch update-compute-environment \
       --compute-environment $COMPUTE_ENV_NAME \
       --compute-resources type=EC2,allocationStrategy=SPOT_CAPACITY_OPTIMIZED
   ```

2. **Implement Auto Scaling**:
   ```bash
   # Set minimum capacity to 0 for cost savings
   aws batch update-compute-environment \
       --compute-environment $COMPUTE_ENV_NAME \
       --compute-resources minvCpus=0,desiredvCpus=0
   ```

3. **Use EFS Intelligent Tiering**:
   ```bash
   # Enable automatic cost optimization
   aws efs modify-file-system \
       --file-system-id $EFS_ID \
       --throughput-mode provisioned \
       --provisioned-throughput-in-mibps 100
   ```

## Support

### Additional Resources

- [Original Recipe Documentation](../distributed-scientific-computing-aws-batch-multi-node-jobs.md)
- [AWS Batch Multi-Node Parallel Jobs Documentation](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html)
- [MPI Programming Guide](https://www.mpi-forum.org/)
- [Scientific Computing on AWS](https://aws.amazon.com/hpc/)

### Getting Help

For issues with this infrastructure code:

1. **Infrastructure Issues**: Check AWS CloudFormation/CDK logs and events
2. **Application Issues**: Review container logs in CloudWatch
3. **Performance Issues**: Use AWS Batch and CloudWatch metrics
4. **Cost Issues**: Review AWS Cost Explorer and set up billing alerts

### Contributing

To improve this infrastructure code:

1. Follow AWS best practices for security and performance
2. Test changes in a development environment first
3. Update documentation for any configuration changes
4. Ensure cleanup procedures work correctly

---

**Note**: This infrastructure code implements the complete solution described in the original recipe. Refer to the recipe documentation for detailed explanations of the architecture and scientific computing concepts.