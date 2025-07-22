# Infrastructure as Code for Optimizing HPC Workloads with AWS Batch and Spot Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing HPC Workloads with AWS Batch and Spot Instances".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS IAM permissions for:
  - AWS Batch (full access)
  - EC2 (launch instances, manage security groups, VPC access)
  - IAM (create roles and policies)
  - S3 (create and manage buckets)
  - EFS (create and manage file systems)
  - CloudWatch (create log groups and alarms)
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform >= 1.0
- Estimated cost: $5-20 for testing (depending on compute time and Spot pricing)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name hpc-batch-spot-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=hpc-test \
                 ParameterKey=MaxvCpus,ParameterValue=1000

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name hpc-batch-spot-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name hpc-batch-spot-stack \
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
cdk deploy --require-approval never

# Get stack outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
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

# Monitor deployment (optional)
watch aws batch describe-compute-environments \
    --compute-environments hpc-spot-compute-*
```

## Configuration Options

### CloudFormation Parameters
- `EnvironmentName`: Prefix for resource names (default: hpc-batch)
- `MaxvCpus`: Maximum vCPUs for compute environment (default: 1000)
- `SpotBidPercentage`: Bid percentage for Spot instances (default: 80)
- `RetentionDays`: CloudWatch log retention (default: 7)

### CDK Context Variables
```json
{
  "environment-name": "hpc-batch",
  "max-vcpus": 1000,
  "spot-bid-percentage": 80,
  "retention-days": 7
}
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
environment_name = "hpc-batch"
max_vcpus = 1000
spot_bid_percentage = 80
retention_days = 7
instance_types = ["c5.large", "c5.xlarge", "c5.2xlarge", "m5.large", "m5.xlarge"]
EOF
```

## Testing the Deployment

### Submit a Test Job
```bash
# Get job queue name from outputs
JOB_QUEUE_NAME=$(aws cloudformation describe-stacks \
    --stack-name hpc-batch-spot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
    --output text)

JOB_DEFINITION_NAME=$(aws cloudformation describe-stacks \
    --stack-name hpc-batch-spot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`JobDefinitionName`].OutputValue' \
    --output text)

# Submit test job
aws batch submit-job \
    --job-name "test-hpc-job-$(date +%s)" \
    --job-queue ${JOB_QUEUE_NAME} \
    --job-definition ${JOB_DEFINITION_NAME}
```

### Monitor Job Execution
```bash
# List running jobs
aws batch list-jobs \
    --job-queue ${JOB_QUEUE_NAME} \
    --job-status RUNNING

# View compute environment scaling
aws batch describe-compute-environments \
    --query 'computeEnvironments[0].computeResources.[desiredvCpus,runningEc2InstanceCount]' \
    --output table
```

### Check Cost Savings
```bash
# View Spot instance savings in CloudWatch
aws cloudwatch get-metric-statistics \
    --namespace AWS/Batch \
    --metric-name SubmittedJobs \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Architecture Overview

The infrastructure deploys:

1. **AWS Batch Compute Environment**: Spot-optimized managed environment with auto-scaling
2. **Job Queue**: Priority-based job scheduling with automatic retry capabilities
3. **Job Definition**: Container specification with fault tolerance and shared storage
4. **IAM Roles**: Least privilege roles for Batch service and EC2 instances
5. **Amazon EFS**: Shared storage for distributed HPC workloads
6. **Security Groups**: Network security for Batch instances and EFS access
7. **CloudWatch**: Monitoring and alerting for job failures and cost tracking
8. **S3 Bucket**: Object storage for input/output data

## Security Features

- **Least Privilege IAM**: Minimal permissions for each component
- **Network Isolation**: Security groups restrict access to necessary ports only
- **Encryption**: EFS encryption at rest and in transit
- **Spot Instance Optimization**: SPOT_CAPACITY_OPTIMIZED strategy for reduced interruptions
- **CloudWatch Monitoring**: Comprehensive logging and alerting

## Cost Optimization

- **Spot Instances**: Up to 90% cost savings compared to on-demand
- **Auto Scaling**: Zero to thousands of cores based on demand
- **Intelligent Allocation**: Capacity-optimized Spot selection reduces interruptions
- **Shared Storage**: Pay-per-use EFS pricing model
- **Resource Tagging**: Cost allocation and tracking

## Troubleshooting

### Common Issues

1. **Compute Environment Stuck in INVALID State**:
   ```bash
   # Check compute environment status reason
   aws batch describe-compute-environments \
       --query 'computeEnvironments[0].statusReason'
   ```

2. **Jobs Stuck in RUNNABLE State**:
   ```bash
   # Verify compute environment has capacity
   aws batch describe-compute-environments \
       --query 'computeEnvironments[0].computeResources.desiredvCpus'
   ```

3. **EFS Mount Failures**:
   ```bash
   # Check EFS file system status
   aws efs describe-file-systems \
       --query 'FileSystems[0].LifeCycleState'
   ```

### Debug Commands

```bash
# View Batch service events
aws batch describe-compute-environments \
    --query 'computeEnvironments[0].events[0:5]'

# Check CloudWatch logs
aws logs describe-log-streams \
    --log-group-name /aws/batch/job \
    --order-by LastEventTime \
    --descending

# Monitor Spot interruptions
aws ec2 describe-spot-price-history \
    --instance-types c5.large \
    --max-items 5
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name hpc-batch-spot-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name hpc-batch-spot-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy --force

# Clean up CDK bootstrap (optional)
cdk destroy --force CDKToolkit
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws batch describe-compute-environments \
    --query 'computeEnvironments[?starts_with(computeEnvironmentName, `hpc-spot-compute`)]'
```

## Customization

### Adding Custom Instance Types
```bash
# Modify instance types in variables
export CUSTOM_INSTANCE_TYPES='["c5.4xlarge", "c5.9xlarge", "r5.large", "r5.xlarge"]'
```

### Enabling GPU Support
```bash
# Add GPU instance types for ML/AI workloads
export GPU_INSTANCE_TYPES='["p3.2xlarge", "p3.8xlarge", "g4dn.xlarge"]'
```

### Custom Container Images
```bash
# Update job definition with custom ECR image
export CUSTOM_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/my-hpc-app:latest"
```

## Performance Tuning

### Optimizing for Throughput
- Increase `maxvCpus` for larger workloads
- Use compute-optimized instance families (C5, C5n)
- Enable placement groups for network-intensive applications

### Optimizing for Cost
- Adjust `bidPercentage` based on workload urgency
- Use burstable instances (T3) for variable workloads
- Implement checkpoint/restart for long-running jobs

### Optimizing for Reliability
- Use mixed instance types to improve Spot availability
- Implement application-level fault tolerance
- Use EFS for checkpoint storage

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS Batch documentation: https://docs.aws.amazon.com/batch/
4. Review AWS Spot Instance best practices: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html

## Additional Resources

- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/latest/userguide/)
- [EC2 Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [AWS Well-Architected HPC Lens](https://docs.aws.amazon.com/wellarchitected/latest/high-performance-computing-lens/)
- [AWS HPC Workshop](https://www.hpcworkshops.com/)