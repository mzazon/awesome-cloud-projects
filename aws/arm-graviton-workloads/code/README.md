# Infrastructure as Code for ARM-based Workloads with Graviton Processors

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ARM-based Workloads with Graviton Processors".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EC2, CloudWatch, Auto Scaling, and Application Load Balancer
- Basic understanding of ARM architecture and performance testing concepts
- Estimated cost: $15-25 for running instances during the 2-3 hour exercise

### Required AWS Permissions

- `ec2:*` (EC2 instances, security groups, key pairs)
- `autoscaling:*` (Auto Scaling Groups and Launch Templates)
- `elasticloadbalancing:*` (Application Load Balancer)
- `cloudwatch:*` (CloudWatch dashboards and alarms)
- `iam:PassRole` (for EC2 instance roles)

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name graviton-workload-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=my-key-pair \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name graviton-workload-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name graviton-workload-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Deploy the stack
cdk deploy --parameters keyPairName=my-key-pair

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the stack
cdk deploy --parameters key_pair_name=my-key-pair

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="key_pair_name=my-key-pair"

# Apply the configuration
terraform apply -var="key_pair_name=my-key-pair"

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
```

## Architecture Overview

The infrastructure deploys:

1. **Security Group**: Allows HTTP (port 80) and SSH (port 22) access
2. **EC2 Instances**: 
   - One x86 baseline instance (c6i.large)
   - One ARM Graviton instance (c7g.large)
3. **Application Load Balancer**: Distributes traffic between instances
4. **Auto Scaling Group**: Manages ARM instances with launch template
5. **CloudWatch Dashboard**: Monitors performance metrics
6. **Cost Monitoring**: Tracks and alerts on costs

## Performance Testing

After deployment, the infrastructure includes:

- **Benchmark Scripts**: Automated CPU stress testing on both architectures
- **Web Servers**: Simple HTTP servers showing instance architecture
- **CloudWatch Metrics**: Real-time performance monitoring
- **Cost Comparison**: Tracks pricing differences between architectures

### Manual Testing Commands

```bash
# Test x86 instance directly
curl http://[X86_PUBLIC_IP]

# Test ARM instance directly
curl http://[ARM_PUBLIC_IP]

# Test load balancer (distributes between both)
curl http://[ALB_DNS_NAME]

# SSH to instances for manual benchmarking
ssh -i [KEY_PAIR].pem ec2-user@[INSTANCE_IP]
sudo /home/ec2-user/benchmark.sh
```

## Cost Optimization

The solution demonstrates significant cost savings:

- **c6i.large (x86)**: ~$0.0864/hour
- **c7g.large (ARM)**: ~$0.0691/hour
- **Estimated Savings**: 20% with ARM Graviton processors

### Cost Monitoring Features

- CloudWatch billing alarms
- Detailed instance monitoring
- Cost comparison dashboards
- Automated cost alerts

## Customization

### Key Variables/Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `key_pair_name` | EC2 Key Pair name | Required |
| `instance_types` | Instance types for comparison | c6i.large, c7g.large |
| `vpc_id` | VPC ID to deploy resources | Default VPC |
| `subnet_ids` | Subnet IDs for deployment | Default subnets |
| `allowed_cidr` | CIDR blocks for security group | 0.0.0.0/0 |
| `environment` | Environment tag | graviton-demo |

### Terraform Variables

```hcl
# terraform/terraform.tfvars
key_pair_name = "my-existing-key-pair"
environment = "production"
allowed_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
```

### CloudFormation Parameters

```yaml
# parameters.json
[
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "my-existing-key-pair"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "production"
  }
]
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates dashboards for:

- CPU utilization comparison (ARM vs x86)
- Network performance metrics
- Cost analysis and trending
- Instance health and status

### Performance Metrics

- **CPU Utilization**: Average, maximum, and minimum usage
- **Network I/O**: Bytes in/out for performance comparison
- **Instance Status**: Health checks and availability
- **Cost Tracking**: Hourly and daily cost breakdown

## Security Considerations

### Network Security

- Security groups with minimal required access
- SSH access restricted to necessary CIDR blocks
- HTTP access for testing purposes only

### IAM Roles

- EC2 instances use least-privilege IAM roles
- CloudWatch agent permissions for metrics collection
- Auto Scaling service-linked roles

### Best Practices

- Regular security group audits
- Key pair rotation
- CloudWatch log monitoring
- Cost anomaly detection

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name graviton-workload-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name graviton-workload-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Troubleshooting

### Common Issues

1. **Key Pair Not Found**
   - Ensure the key pair exists in the target region
   - Verify the key pair name is correct

2. **AMI Not Available**
   - Check if the AMI ID is available in your region
   - Use the latest Amazon Linux 2 AMI

3. **Instance Launch Failures**
   - Verify subnet has available IP addresses
   - Check security group rules
   - Ensure proper IAM permissions

4. **Cost Alarms Not Working**
   - Enable billing alerts in AWS Account Settings
   - Verify CloudWatch permissions
   - Check alarm configuration

### Debugging Steps

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name graviton-workload-stack

# Verify EC2 instance status
aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=graviton-demo"

# Check Auto Scaling Group health
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names [ASG_NAME]
```

## Performance Benchmarking

### Benchmark Results Analysis

The infrastructure includes automated benchmarking that typically shows:

- **Integer Operations**: ARM often shows 10-25% better performance
- **Floating Point**: Graviton3 excels in FP operations
- **Memory Bandwidth**: Consistent performance characteristics
- **Energy Efficiency**: Up to 60% less energy consumption

### Custom Benchmarking

```bash
# SSH to instance and run custom tests
ssh -i [KEY_PAIR].pem ec2-user@[INSTANCE_IP]

# Install additional benchmarking tools
sudo yum install -y sysbench

# Run CPU benchmark
sysbench cpu --threads=4 --time=60 run

# Run memory benchmark
sysbench memory --threads=4 --time=60 run
```

## Extension Ideas

1. **Container Workloads**: Deploy ARM-based containers using Amazon ECS
2. **Database Performance**: Compare ARM vs x86 for database workloads
3. **CI/CD Integration**: Automate ARM/x86 testing in build pipelines
4. **Cost Optimization**: Implement automated instance type switching
5. **Multi-Region Testing**: Compare ARM performance across regions

## Support and Documentation

- [AWS Graviton Processor Documentation](https://aws.amazon.com/ec2/graviton/)
- [ARM Architecture Migration Guide](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-guide/)
- [Performance Testing Best Practices](https://docs.aws.amazon.com/whitepapers/latest/aws-graviton-performance-testing/)
- [Cost Optimization Guide](https://aws.amazon.com/ec2/cost-optimization/)

## Contributing

For improvements to this infrastructure code:

1. Test changes against the original recipe requirements
2. Validate cost implications
3. Ensure security best practices
4. Update documentation accordingly

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.