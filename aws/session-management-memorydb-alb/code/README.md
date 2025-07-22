# Infrastructure as Code for Building Distributed Session Management with MemoryDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Distributed Session Management with MemoryDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a distributed session management system using:
- Amazon MemoryDB for Redis as a centralized session store
- Application Load Balancer for traffic distribution
- ECS with Fargate for containerized applications
- Systems Manager Parameter Store for configuration management
- Auto Scaling for dynamic capacity management

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - MemoryDB cluster creation and management
  - ECS cluster and service management
  - Application Load Balancer creation
  - VPC and networking resources
  - IAM role creation and policy attachment
  - Systems Manager Parameter Store access
  - CloudWatch Logs access
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name distributed-session-mgmt-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-session-cluster \
                 ParameterKey=MemoryDBNodeType,ParameterValue=db.r6g.large

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name distributed-session-mgmt-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name distributed-session-mgmt-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired values

# Plan deployment
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

# Follow prompts for configuration values
# Script will output important endpoints and connection details
```

## Configuration Options

### Common Parameters

All implementations support these customizable parameters:

- **Cluster Name**: Name for the ECS cluster and related resources
- **MemoryDB Node Type**: Instance type for MemoryDB cluster (default: db.r6g.large)
- **MemoryDB Shards**: Number of shards for the MemoryDB cluster (default: 2)
- **ECS Task CPU/Memory**: Resource allocation for ECS tasks
- **Auto Scaling Limits**: Min/max capacity for ECS service auto scaling
- **Environment**: Environment tag (dev, staging, prod)

### CloudFormation Parameters

Edit parameters in the CloudFormation template or provide via CLI:

```yaml
Parameters:
  ClusterName:
    Type: String
    Default: session-cluster
  MemoryDBNodeType:
    Type: String
    Default: db.r6g.large
    AllowedValues: [db.r6g.large, db.r6g.xlarge, db.r6g.2xlarge]
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
```

### CDK Configuration

Edit the configuration variables in the CDK app files:

**TypeScript**: `app.ts`
**Python**: `app.py`

### Terraform Variables

Create and edit `terraform.tfvars`:

```hcl
cluster_name        = "my-session-cluster"
memorydb_node_type = "db.r6g.large"
memorydb_num_shards = 2
environment        = "dev"
ecs_task_cpu      = 256
ecs_task_memory   = 512
min_capacity      = 2
max_capacity      = 10
```

## Validation & Testing

After deployment, validate the solution:

### 1. Check MemoryDB Cluster Status

```bash
# Get cluster endpoint from outputs
MEMORYDB_ENDPOINT=$(aws memorydb describe-clusters \
    --cluster-name <your-cluster-name> \
    --query 'Clusters[0].ClusterEndpoint.Address' \
    --output text)

# Test Redis connectivity (requires redis-cli)
redis-cli -h ${MEMORYDB_ENDPOINT} -p 6379 ping
```

### 2. Test Application Load Balancer

```bash
# Get ALB DNS name from outputs
ALB_DNS_NAME="<output-from-deployment>"

# Test HTTP connectivity
curl -I http://${ALB_DNS_NAME}/
```

### 3. Verify ECS Service Health

```bash
# Check service status
aws ecs describe-services \
    --cluster <your-cluster-name> \
    --services session-app-service \
    --query 'services[0].runningCount'
```

### 4. Test Session Storage

```bash
# Connect to MemoryDB and test session operations
redis-cli -h ${MEMORYDB_ENDPOINT} -p 6379 \
    SET "test:session:123" "sample_session_data" EX 1800

# Verify retrieval
redis-cli -h ${MEMORYDB_ENDPOINT} -p 6379 \
    GET "test:session:123"
```

## Security Considerations

This implementation includes several security best practices:

- **Network Isolation**: Resources deployed in private subnets with security groups
- **Least Privilege IAM**: Minimal permissions for ECS tasks and service roles
- **Encryption**: MemoryDB encryption at rest and in transit enabled
- **Parameter Store**: Sensitive configuration stored securely in AWS Systems Manager
- **VPC Security Groups**: Restrictive ingress/egress rules

## Monitoring & Logging

The solution includes comprehensive monitoring:

- **CloudWatch Metrics**: MemoryDB, ECS, and ALB metrics
- **CloudWatch Logs**: Application and ECS task logs
- **Auto Scaling Metrics**: CPU-based scaling with configurable thresholds
- **Health Checks**: ALB target group health monitoring

## Cost Optimization

To optimize costs:

- Use appropriate MemoryDB instance types for your workload
- Configure ECS auto scaling to scale down during low usage
- Review CloudWatch log retention periods
- Consider using Spot instances for non-production environments (modify ECS capacity providers)

## Troubleshooting

### Common Issues

1. **ECS Tasks Not Starting**:
   - Check IAM permissions for task execution role
   - Verify security group configurations
   - Review CloudWatch logs for error messages

2. **MemoryDB Connection Issues**:
   - Verify security group allows port 6379 from ECS tasks
   - Check MemoryDB cluster status and endpoint
   - Ensure Parameter Store values are correct

3. **Load Balancer Health Check Failures**:
   - Verify application is listening on correct port
   - Check health check path configuration
   - Review target group settings

### Debugging Commands

```bash
# Check ECS task logs
aws logs tail /ecs/session-app --follow

# Describe ECS service events
aws ecs describe-services \
    --cluster <cluster-name> \
    --services session-app-service \
    --query 'services[0].events[0:5]'

# Check Parameter Store values
aws ssm get-parameters-by-path \
    --path "/session-app/" \
    --recursive
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name distributed-session-mgmt-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name distributed-session-mgmt-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Support & Documentation

- [Original Recipe](../distributed-session-management-memorydb-application-load-balancer.md) - Complete implementation guide
- [Amazon MemoryDB Documentation](https://docs.aws.amazon.com/memorydb/)
- [Application Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/)
- [Amazon ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation to reflect any changes
3. Ensure security best practices are maintained
4. Validate that all resource dependencies are properly configured

## Estimated Costs

Monthly cost estimates (us-east-1 region):

- **MemoryDB Cluster** (db.r6g.large, 2 shards, 1 replica per shard): ~$400-500
- **Application Load Balancer**: ~$20-25
- **ECS Fargate Tasks** (2-10 tasks, 0.25 vCPU, 0.5 GB memory): ~$15-75
- **Data Transfer**: Variable based on usage
- **CloudWatch Logs**: ~$5-15

**Total estimated monthly cost**: $440-615

> **Note**: Actual costs may vary based on usage patterns, data transfer, and regional pricing differences.