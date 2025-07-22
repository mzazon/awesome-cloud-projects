# Infrastructure as Code for Cost-Optimized Batch Processing with AWS Batch and Spot Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Optimized Batch Processing with Spot".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Docker installed (for containerizing batch applications)
- Basic understanding of containerization and batch processing concepts
- The following AWS permissions are required:
  - IAM: Create and manage roles, policies, and instance profiles
  - EC2: Create security groups, describe VPCs and subnets
  - ECR: Create repositories, push/pull images
  - AWS Batch: Create compute environments, job queues, and job definitions
  - ECS: Manage container services (used by AWS Batch)
  - CloudWatch: Access for logging and monitoring

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later
- CloudFormation permissions

#### CDK TypeScript
- Node.js v18 or later
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform v1.0 or later
- AWS provider v4.0 or later

## Quick Start

### Using CloudFormation

```bash
# Create stack with default parameters
aws cloudformation create-stack \
    --stack-name cost-optimized-batch-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxx \
                 ParameterKey=SubnetIds,ParameterValue=subnet-xxxxx,subnet-yyyyy

# Monitor stack creation
aws cloudformation describe-stacks \
    --stack-name cost-optimized-batch-stack \
    --query 'Stacks[0].StackStatus'
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
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
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

# Review the execution plan
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

# Monitor deployment progress
# (Script will provide status updates)
```

## Infrastructure Components

This IaC deploys the following AWS resources:

### Core AWS Batch Resources
- **Compute Environment**: Managed EC2 compute environment configured for Spot instances
- **Job Queue**: Priority-based job scheduling queue
- **Job Definition**: Container-based job template with retry strategies

### IAM Resources
- **Service Role**: Enables AWS Batch to manage compute resources
- **Instance Role**: Allows EC2 instances to register with ECS
- **Job Execution Role**: Permits tasks to pull images and write logs
- **Instance Profile**: Associates instance role with EC2 instances

### Container Resources
- **ECR Repository**: Stores containerized batch applications
- **Sample Application**: Python-based batch processing container

### Networking Resources
- **Security Group**: Controls network access for batch instances
- **VPC Integration**: Leverages existing VPC and subnets

## Configuration Options

### CloudFormation Parameters
- `VpcId`: VPC ID for batch compute resources
- `SubnetIds`: Comma-separated list of subnet IDs
- `MaxvCpus`: Maximum vCPUs for compute environment (default: 100)
- `BidPercentage`: Spot instance bid percentage (default: 80)
- `InstanceTypes`: EC2 instance types for compute environment

### CDK Context Variables
- `vpcId`: VPC ID for deployment
- `subnetIds`: Array of subnet IDs
- `maxvCpus`: Maximum vCPUs for scaling
- `spotBidPercentage`: Spot instance bid percentage

### Terraform Variables
- `vpc_id`: VPC ID for resources
- `subnet_ids`: List of subnet IDs
- `max_vcpus`: Maximum vCPUs for compute environment
- `spot_bid_percentage`: Spot instance bid percentage
- `instance_types`: List of EC2 instance types

## Cost Optimization Features

### Spot Instance Configuration
- **Allocation Strategy**: SPOT_CAPACITY_OPTIMIZED for maximum availability
- **Mixed Instance Types**: Multiple instance families for flexibility
- **Bid Percentage**: Configurable bid up to specified percentage of On-Demand price

### Auto Scaling
- **Dynamic Scaling**: Scales from 0 to maximum based on job demand
- **Cost-Aware Scaling**: Prioritizes most cost-effective instances
- **Automatic Termination**: Scales down when jobs complete

### Retry Strategy
- **Intelligent Retries**: Automatically retries jobs interrupted by Spot termination
- **Application-Level Failures**: Avoids retries for application errors
- **Configurable Attempts**: Customizable retry count

## Monitoring and Logging

### CloudWatch Integration
- **Job Logs**: Automatic log collection from batch jobs
- **Compute Metrics**: Instance utilization and performance metrics
- **Cost Tracking**: Spot instance savings and usage patterns

### Recommended Monitoring
- Job success rates and failure patterns
- Spot instance interruption frequency
- Cost savings compared to On-Demand instances
- Resource utilization efficiency

## Security Best Practices

### IAM Security
- **Least Privilege**: Minimal permissions for each role
- **Service-Specific Roles**: Separate roles for different functions
- **No Hardcoded Credentials**: Uses IAM roles and temporary credentials

### Network Security
- **Security Groups**: Restricts network access to necessary ports
- **VPC Integration**: Leverages existing network security controls
- **Egress Control**: Allows only necessary outbound traffic

### Container Security
- **Image Scanning**: ECR vulnerability scanning enabled
- **Runtime Security**: Container isolation and resource limits
- **Secrets Management**: Secure handling of sensitive data

## Troubleshooting

### Common Issues

#### Jobs Stuck in RUNNABLE State
- **Cause**: Insufficient compute capacity or networking issues
- **Solution**: Check VPC has internet access (NAT Gateway/Internet Gateway)
- **Verification**: Ensure security groups allow outbound HTTPS traffic

#### Spot Instance Interruptions
- **Cause**: High Spot demand or price fluctuations
- **Solution**: Increase bid percentage or add more instance types
- **Monitoring**: Review CloudWatch metrics for interruption patterns

#### Container Pull Failures
- **Cause**: ECR authentication or networking issues
- **Solution**: Verify IAM permissions and VPC connectivity
- **Debug**: Check CloudWatch logs for detailed error messages

### Validation Commands

```bash
# Check compute environment status
aws batch describe-compute-environments \
    --compute-environments <environment-name> \
    --query 'computeEnvironments[0].status'

# Monitor job progress
aws batch describe-jobs --jobs <job-id> \
    --query 'jobs[0].{Status:status,Queue:jobQueue}'

# Verify Spot instance usage
aws ec2 describe-instances \
    --filters "Name=instance-lifecycle,Values=spot" \
    --query 'Reservations[].Instances[].InstanceType'
```

## Performance Optimization

### Job Optimization
- **Resource Sizing**: Right-size CPU and memory requirements
- **Parallel Processing**: Utilize multiple vCPUs for parallel workloads
- **Batch Size**: Optimize job granularity for efficient resource utilization

### Compute Environment Tuning
- **Instance Diversity**: Use multiple instance types for better availability
- **Scaling Parameters**: Adjust min/max/desired capacity based on workload
- **Placement Strategy**: Leverage multiple AZs for resilience

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-optimized-batch-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cost-optimized-batch-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the cdk-typescript/ or cdk-python/ directory
cdk destroy

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

# Follow prompts for confirmation
```

## Customization

### Adding Custom Applications
1. Replace the sample Python application with your batch processing code
2. Update the Dockerfile to include your application dependencies
3. Modify job definition resource requirements based on your application needs
4. Adjust retry strategy based on your application's fault tolerance

### Scaling Configuration
- Modify `maxvCpus` to match your workload requirements
- Adjust `bidPercentage` based on your cost/availability tradeoff
- Add or remove instance types based on your application compatibility

### Security Hardening
- Implement custom VPC with private subnets
- Add additional security group rules for specific requirements
- Enable ECR image scanning and lifecycle policies
- Implement AWS Config rules for compliance monitoring

## Cost Estimation

### Expected Savings
- **Spot Instances**: Up to 90% savings compared to On-Demand instances
- **Auto Scaling**: Pay only for resources used during job execution
- **Efficient Scheduling**: Optimal resource allocation reduces waste

### Cost Factors
- **Instance Types**: Different instance families have varying Spot prices
- **Availability Zones**: Spot prices vary by AZ
- **Time of Day**: Spot prices fluctuate based on demand
- **Job Duration**: Longer jobs may be more susceptible to interruptions

### Monitoring Costs
- Use AWS Cost Explorer to track batch processing costs
- Set up billing alerts for budget monitoring
- Compare costs with On-Demand equivalent workloads

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS Batch documentation for service-specific issues
3. Review CloudWatch logs for detailed error information
4. Consult AWS support for service-related problems

## Additional Resources

- [AWS Batch User Guide](https://docs.aws.amazon.com/batch/latest/userguide/)
- [Amazon EC2 Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [AWS Batch Cost Optimization](https://docs.aws.amazon.com/batch/latest/userguide/cost-optimization.html)
- [Container Security Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security.html)