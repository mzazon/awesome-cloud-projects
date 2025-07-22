# Infrastructure as Code for EKS Node Groups with Spot Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Node Groups with Spot Instances".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl CLI tool installed and configured
- Appropriate AWS permissions for:
  - EKS cluster management
  - EC2 instance management
  - IAM role creation and management
  - Auto Scaling Group management
  - CloudWatch logging and monitoring
- Existing EKS cluster (version 1.24 or higher recommended)
- Estimated cost: $50-200/month depending on node group sizes and usage patterns

> **Note**: Spot instances can be interrupted with 2-minute notice, making them suitable for fault-tolerant workloads but not for critical production systems requiring guaranteed availability.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name eks-spot-nodegroups \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=your-cluster-name \
                 ParameterKey=NodeGroupSubnets,ParameterValue="subnet-12345,subnet-67890" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name eks-spot-nodegroups

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name eks-spot-nodegroups \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters clusterName=your-cluster-name \
           --parameters nodeGroupSubnets=subnet-12345,subnet-67890

# View deployed resources
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CLUSTER_NAME=your-cluster-name
export NODE_GROUP_SUBNETS=subnet-12345,subnet-67890

# Deploy the infrastructure
cdk deploy

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
cluster_name = "your-cluster-name"
node_group_subnets = ["subnet-12345", "subnet-67890"]
aws_region = "us-west-2"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CLUSTER_NAME=your-cluster-name
export NODE_GROUP_SUBNETS="subnet-12345 subnet-67890"
export AWS_REGION=us-west-2

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
kubectl get nodes -o wide
```

## Architecture Overview

This solution deploys:

1. **Spot Instance Node Group**: Cost-optimized nodes using multiple instance types (m5.large, m5a.large, c5.large, c5a.large, m5.xlarge, c5.xlarge)
2. **On-Demand Node Group**: Reliable capacity for critical workloads (m5.large, c5.large)
3. **AWS Node Termination Handler**: Graceful handling of Spot interruptions
4. **Cluster Autoscaler**: Automatic scaling based on workload demands
5. **IAM Roles and Policies**: Secure access permissions for all components
6. **CloudWatch Monitoring**: Cost and performance tracking

## Configuration Options

### Common Parameters

- `cluster_name`: Name of your existing EKS cluster
- `node_group_subnets`: List of subnet IDs for node placement
- `aws_region`: AWS region for deployment
- `spot_min_size`: Minimum number of Spot instances (default: 2)
- `spot_max_size`: Maximum number of Spot instances (default: 10)
- `spot_desired_size`: Desired number of Spot instances (default: 4)
- `ondemand_min_size`: Minimum number of On-Demand instances (default: 1)
- `ondemand_max_size`: Maximum number of On-Demand instances (default: 3)
- `ondemand_desired_size`: Desired number of On-Demand instances (default: 2)

### Advanced Configuration

- `spot_instance_types`: List of instance types for Spot node group
- `ondemand_instance_types`: List of instance types for On-Demand node group
- `node_disk_size`: EBS volume size for worker nodes (default: 30GB)
- `kubernetes_version`: EKS cluster version compatibility
- `enable_monitoring`: Enable detailed CloudWatch monitoring

## Validation

After deployment, verify the infrastructure:

```bash
# Check node group status
aws eks describe-nodegroup \
    --cluster-name your-cluster-name \
    --nodegroup-name spot-mixed-nodegroup

# Verify nodes are running
kubectl get nodes -l node-type=spot

# Check Spot instance distribution
kubectl get nodes -o wide --show-labels | grep -E "(m5|c5)"

# Verify Node Termination Handler
kubectl get daemonset aws-node-termination-handler -n kube-system

# Check Cluster Autoscaler
kubectl get deployment cluster-autoscaler -n kube-system
```

## Testing Spot Tolerance

Deploy a test application to verify Spot instance functionality:

```bash
# Create a test deployment
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-test-app
spec:
  replicas: 6
  selector:
    matchLabels:
      app: spot-test-app
  template:
    metadata:
      labels:
        app: spot-test-app
        workload-type: spot-tolerant
    spec:
      tolerations:
      - key: node-type
        operator: Equal
        value: spot
        effect: NoSchedule
      nodeSelector:
        node-type: spot
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF

# Verify pods are scheduled on Spot instances
kubectl get pods -o wide -l app=spot-test-app
```

## Cost Optimization Tips

1. **Instance Type Selection**: The default configuration uses a mix of compute-optimized (c5) and general-purpose (m5) instances for optimal cost-performance balance
2. **Spot Allocation Strategy**: Uses `diversified` strategy to spread instances across multiple types and availability zones
3. **Monitoring**: Enable cost monitoring to track savings compared to On-Demand pricing
4. **Workload Placement**: Use node taints and tolerations to ensure appropriate workload placement

## Troubleshooting

### Common Issues

1. **Node Group Creation Fails**:
   - Verify IAM permissions
   - Check subnet configuration
   - Ensure cluster exists and is accessible

2. **Spot Interruptions**:
   - Monitor interruption rates in CloudWatch
   - Adjust instance type diversity
   - Implement proper Pod Disruption Budgets

3. **Cluster Autoscaler Not Scaling**:
   - Check IAM permissions
   - Verify Auto Scaling Group tags
   - Review autoscaler logs

### Debugging Commands

```bash
# Check node group events
aws eks describe-nodegroup --cluster-name your-cluster-name --nodegroup-name spot-mixed-nodegroup

# View Cluster Autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=100

# Check Node Termination Handler logs
kubectl logs -n kube-system daemonset/aws-node-termination-handler --tail=100

# Monitor Spot interruption events
aws ec2 describe-spot-instance-requests --filters "Name=state,Values=active"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name eks-spot-nodegroups

# Wait for stack deletion
aws cloudformation wait stack-delete-complete --stack-name eks-spot-nodegroups
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Security Considerations

- **IAM Roles**: All components use least-privilege IAM roles
- **Network Security**: Nodes are deployed in private subnets
- **Encryption**: EBS volumes use encryption at rest
- **Access Control**: Kubernetes RBAC controls access to cluster resources
- **Monitoring**: CloudWatch provides audit logging and monitoring

## Performance Optimization

- **Instance Diversity**: Multiple instance types reduce interruption impact
- **Auto Scaling**: Automatic scaling based on resource demands
- **Resource Requests**: Proper resource requests enable efficient scheduling
- **Pod Disruption Budgets**: Maintain application availability during interruptions

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS EKS documentation for managed node groups
3. Consult the AWS Spot Instance best practices guide
4. Verify IAM permissions and cluster configuration

## Additional Resources

- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EC2 Spot Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [Kubernetes Cluster Autoscaler](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
- [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)