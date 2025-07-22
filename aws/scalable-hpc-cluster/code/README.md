# Infrastructure as Code for Scalable HPC Cluster with Auto-Scaling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable HPC Cluster with Auto-Scaling".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EC2, VPC, IAM, FSx, S3, and CloudFormation
- Python 3.8+ installed (for ParallelCluster CLI)
- SSH key pair for cluster access
- Basic understanding of HPC concepts and Slurm job scheduler

### Required IAM Permissions

Your AWS credentials must have permissions for:
- EC2 instance management and VPC operations
- S3 bucket creation and management
- FSx Lustre filesystem operations
- CloudFormation stack operations
- IAM role and policy management
- CloudWatch monitoring and logging

### Cost Considerations

- **Head Node**: ~$0.10/hour (m5.large)
- **Compute Nodes**: ~$0.27/hour per c5n.large (auto-scaling)
- **FSx Lustre**: ~$0.14/GiB/month (1.2 TiB minimum)
- **EBS Storage**: ~$0.08/GiB/month (gp3)
- **Data Transfer**: Standard AWS data transfer rates apply

> **Warning**: HPC instances can incur significant costs. Monitor usage and implement appropriate cost controls.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name hpc-parallelcluster-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
                 ParameterKey=ClusterName,ParameterValue=my-hpc-cluster

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name hpc-parallelcluster-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name hpc-parallelcluster-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure parameters (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters KeyPairName=your-key-pair

# View outputs
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Configure parameters (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters KeyPairName=your-key-pair

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will prompt for required parameters
# Follow the interactive prompts to configure your cluster
```

## Post-Deployment Steps

After successful deployment, you'll need to:

1. **Install ParallelCluster CLI** (if not already installed):
   ```bash
   pip3 install aws-parallelcluster
   ```

2. **Connect to Head Node**:
   ```bash
   # Use the HeadNodeIP from outputs
   ssh -i ~/.ssh/your-key-pair.pem ec2-user@HEAD_NODE_IP
   ```

3. **Test Job Submission**:
   ```bash
   # On the head node
   cat > test-job.sh << 'EOF'
   #!/bin/bash
   #SBATCH --job-name=test
   #SBATCH --nodes=1
   #SBATCH --ntasks=1
   #SBATCH --time=00:05:00
   
   echo "Hello from HPC cluster!"
   hostname
   EOF
   
   sbatch test-job.sh
   squeue
   ```

4. **Monitor with CloudWatch**:
   - Access the CloudWatch dashboard created during deployment
   - Monitor CPU utilization, network metrics, and job queue status

## Configuration Options

### Key Parameters

- **ClusterName**: Name for your HPC cluster
- **KeyPairName**: EC2 key pair for SSH access
- **MaxComputeNodes**: Maximum number of compute nodes (default: 10)
- **ComputeInstanceType**: EC2 instance type for compute nodes (default: c5n.large)
- **FSxStorageCapacity**: FSx Lustre storage capacity in GiB (default: 1200)
- **S3BucketName**: S3 bucket for data storage (auto-generated if not specified)

### Customization Examples

#### Modify Instance Types
```bash
# For compute-intensive workloads
terraform apply -var="compute_instance_type=c5n.xlarge"

# For memory-intensive workloads
terraform apply -var="compute_instance_type=r5n.large"
```

#### Adjust Storage Configuration
```bash
# Increase FSx storage for larger datasets
terraform apply -var="fsx_storage_capacity=2400"

# Enable FSx export to S3
terraform apply -var="enable_fsx_export=true"
```

#### Configure Auto-Scaling
```bash
# Set minimum compute nodes
terraform apply -var="min_compute_nodes=2"

# Adjust scale-down idle time
terraform apply -var="scaledown_idletime=10"
```

## Validation & Testing

### Verify Deployment

1. **Check Cluster Status**:
   ```bash
   pcluster describe-cluster --cluster-name YOUR_CLUSTER_NAME
   ```

2. **Test Slurm Scheduler**:
   ```bash
   ssh -i ~/.ssh/your-key-pair.pem ec2-user@HEAD_NODE_IP
   sinfo
   squeue
   ```

3. **Test Storage Performance**:
   ```bash
   # On head node
   dd if=/dev/zero of=/fsx/test-file bs=1M count=1000
   time dd if=/fsx/test-file of=/dev/null bs=1M
   rm /fsx/test-file
   ```

4. **Test Auto-Scaling**:
   ```bash
   # Submit multiple jobs to trigger scaling
   for i in {1..5}; do
       sbatch --nodes=2 --ntasks=8 --time=00:10:00 \
              --wrap="sleep 600; echo 'Job $i completed'"
   done
   ```

### Monitoring

- **CloudWatch Dashboard**: Access cluster metrics and performance data
- **ParallelCluster UI**: Web interface for cluster management (if enabled)
- **Slurm Commands**: `sinfo`, `squeue`, `sacct` for job and node status
- **FSx Performance**: Monitor I/O metrics in CloudWatch

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name hpc-parallelcluster-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name hpc-parallelcluster-stack
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

# Follow interactive prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove:

1. **ParallelCluster**: `pcluster delete-cluster --cluster-name YOUR_CLUSTER_NAME`
2. **S3 Bucket**: Empty and delete the data bucket
3. **VPC Resources**: Delete VPC, subnets, and security groups
4. **CloudWatch Resources**: Delete custom dashboards and alarms

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**:
   - Check CloudFormation events for detailed error messages
   - Verify IAM permissions and service limits
   - Ensure key pair exists in the target region

2. **Compute Nodes Not Scaling**:
   - Check Slurm configuration and job queue status
   - Verify subnet and security group configurations
   - Review ParallelCluster logs in CloudWatch

3. **Storage Performance Issues**:
   - Verify FSx Lustre configuration and capacity
   - Check network performance of compute instances
   - Monitor CloudWatch FSx metrics

4. **Job Submission Failures**:
   - Verify Slurm service status on head node
   - Check job script syntax and resource requirements
   - Review Slurm logs for error messages

### Debug Commands

```bash
# Check cluster status
pcluster describe-cluster --cluster-name YOUR_CLUSTER_NAME

# View ParallelCluster logs
pcluster get-cluster-log-events --cluster-name YOUR_CLUSTER_NAME

# Check Slurm configuration
scontrol show config

# Monitor job queue
watch squeue

# Check node status
sinfo -N -l
```

## Best Practices

### Security

- Use IAM roles with least privilege principles
- Enable VPC Flow Logs for network monitoring
- Implement security groups with minimal required access
- Use encrypted storage for sensitive data
- Regular security updates on cluster nodes

### Cost Optimization

- Use Spot instances for fault-tolerant workloads
- Implement appropriate auto-scaling policies
- Monitor and optimize FSx storage capacity
- Set up cost alerts and budgets
- Regular review of unused resources

### Performance

- Choose appropriate instance types for your workloads
- Optimize MPI applications for network topology
- Use placement groups for tightly-coupled applications
- Monitor and tune I/O patterns
- Regular performance benchmarking

### Operational Excellence

- Implement comprehensive monitoring and alerting
- Regular backup of important data to S3
- Version control for cluster configurations
- Documentation of custom configurations
- Regular testing of disaster recovery procedures

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS ParallelCluster documentation
3. Consult AWS support for service-specific issues
4. Review CloudFormation/CDK/Terraform provider documentation

## Additional Resources

- [AWS ParallelCluster Documentation](https://docs.aws.amazon.com/parallelcluster/)
- [Slurm Workload Manager Documentation](https://slurm.schedmd.com/documentation.html)
- [AWS HPC Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/high-performance-computing-lens/)
- [FSx Lustre Performance Guide](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html)
- [EC2 Instance Types for HPC](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing)