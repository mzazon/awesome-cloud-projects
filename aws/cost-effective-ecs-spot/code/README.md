# Infrastructure as Code for Cost-Effective ECS Clusters with Spot Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Effective ECS Clusters with Spot Instances".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate IAM permissions for ECS, EC2, Auto Scaling, and CloudWatch services
- Existing VPC with subnets in multiple Availability Zones
- Understanding of containerized applications and ECS concepts
- Application designed to handle instance failures gracefully

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 configured with appropriate permissions
- IAM permissions for CloudFormation stack operations

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript compiler installed

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI installed (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0+ installed
- AWS provider configured

#### Bash Scripts
- Bash shell environment
- jq utility for JSON processing
- curl for health checks

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cost-effective-ecs-spot-cluster \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
                 ParameterKey=SubnetIds,ParameterValue="subnet-xxxxxxxx,subnet-yyyyyyyy,subnet-zzzzzzzz" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name cost-effective-ecs-spot-cluster \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name cost-effective-ecs-spot-cluster \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
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
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AWS_REGION=us-east-1
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_IDS="subnet-xxxxxxxx,subnet-yyyyyyyy,subnet-zzzzzzzz"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables

All implementations support these environment variables for customization:

```bash
# Required
export AWS_REGION=us-east-1
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_IDS="subnet-xxxxxxxx,subnet-yyyyyyyy,subnet-zzzzzzzz"

# Optional (with defaults)
export CLUSTER_NAME="cost-optimized-cluster"
export SERVICE_NAME="spot-resilient-service"
export DESIRED_CAPACITY=3
export MIN_SIZE=1
export MAX_SIZE=10
export ON_DEMAND_PERCENTAGE=20
export SPOT_MAX_PRICE=0.10
export CONTAINER_IMAGE="public.ecr.aws/docker/library/nginx:latest"
export CONTAINER_PORT=80
export HEALTH_CHECK_GRACE_PERIOD=300
export TARGET_CPU_UTILIZATION=60
```

### Instance Types

The implementations use a diversified instance type strategy:

- **Primary Types**: m5.large, c5.large, m4.large
- **Secondary Types**: c4.large, r5.large
- **Spot Strategy**: Diversified across multiple instance types and AZs
- **On-Demand Strategy**: Prioritized with 20% base capacity

### Scaling Configuration

- **Minimum Capacity**: 1 instance (configurable)
- **Maximum Capacity**: 10 instances (configurable)
- **Target Capacity**: 80% utilization
- **Auto Scaling**: CPU-based target tracking at 60%
- **Health Check**: ECS health checks with 5-minute grace period

## Cost Optimization Features

### Spot Instance Configuration

- **Allocation Strategy**: Diversified across multiple instance pools
- **Spot Pools**: 4 different instance pools for maximum availability
- **Maximum Price**: $0.10/hour (configurable)
- **Interruption Handling**: Managed instance draining enabled

### Mixed Instance Policy

- **On-Demand Base**: 1 instance minimum
- **On-Demand Percentage**: 20% above base capacity
- **Spot Percentage**: 80% of additional capacity
- **Instance Distribution**: Across 3 Availability Zones

### Cost Monitoring

All implementations include:

- CloudWatch Container Insights for detailed metrics
- Cost allocation tags for tracking expenses
- Spot interruption monitoring
- Resource utilization dashboards

## Validation and Testing

### Post-Deployment Validation

```bash
# Check cluster status
aws ecs describe-clusters --clusters $CLUSTER_NAME

# Verify service health
aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME

# Check instance mix (Spot vs On-Demand)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME

# Monitor cost savings
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

### Load Testing

```bash
# Generate load to test auto scaling
for i in {1..100}; do
    curl -s http://YOUR_LOAD_BALANCER_URL/ > /dev/null &
done

# Monitor scaling activity
aws logs tail /aws/ecs/spot-resilient-app --follow
```

## Security Considerations

### IAM Permissions

The implementations create the following IAM roles:

- **ECS Task Execution Role**: Allows ECS to pull images and write logs
- **ECS Instance Role**: Allows EC2 instances to join ECS cluster
- **Auto Scaling Service Role**: Manages scaling operations

### Network Security

- Security groups restrict traffic to necessary ports only
- VPC endpoints for ECS and ECR (optional, recommended for production)
- CloudWatch Logs for audit trails

### Best Practices Applied

- Least privilege IAM policies
- Encrypted CloudWatch logs
- Resource tagging for cost allocation
- Health checks and monitoring
- Graceful shutdown handling

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name cost-effective-ecs-spot-cluster

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cost-effective-ecs-spot-cluster \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Cleanup bootstrap (if no longer needed)
# cdk bootstrap --destroy
```

### Using Terraform
```bash
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Spot Instance Interruptions**
   - Check CloudWatch metrics for interruption rates
   - Increase On-Demand percentage if needed
   - Verify managed instance draining is enabled

2. **Service Scaling Issues**
   - Verify capacity provider is associated with cluster
   - Check Auto Scaling Group health checks
   - Review CloudWatch scaling metrics

3. **Task Placement Failures**
   - Ensure sufficient instance capacity
   - Check resource requirements vs. available capacity
   - Verify security group and subnet configurations

### Debugging Commands

```bash
# Check ECS cluster events
aws ecs describe-clusters --clusters $CLUSTER_NAME --include clusterTags

# View Auto Scaling activities
aws autoscaling describe-scaling-activities \
    --auto-scaling-group-name $ASG_NAME

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ClusterName,Value=$CLUSTER_NAME \
    --start-time 2025-01-01T00:00:00Z \
    --end-time 2025-01-02T00:00:00Z \
    --period 300 \
    --statistics Average
```

## Monitoring and Alerts

### CloudWatch Metrics

- ECS Service CPU and Memory utilization
- Auto Scaling Group capacity and health
- Spot interruption rates
- Task placement failures

### Recommended Alarms

```bash
# High CPU utilization
aws cloudwatch put-metric-alarm \
    --alarm-name "ECS-HighCPU" \
    --alarm-description "ECS service CPU utilization" \
    --metric-name CPUUtilization \
    --namespace AWS/ECS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold

# Spot interruption rate
aws cloudwatch put-metric-alarm \
    --alarm-name "High-Spot-Interruptions" \
    --alarm-description "High spot interruption rate" \
    --metric-name SpotFleetRequestTerminatingInstances \
    --namespace AWS/EC2Spot \
    --statistic Sum \
    --period 900 \
    --threshold 2 \
    --comparison-operator GreaterThanThreshold
```

## Performance Optimization

### Instance Type Selection

- Use compute-optimized instances (C5, C4) for CPU-intensive workloads
- Use memory-optimized instances (R5, R4) for memory-intensive workloads
- Use general-purpose instances (M5, M4) for balanced workloads

### Auto Scaling Configuration

- Adjust target CPU utilization based on application requirements
- Fine-tune scale-out and scale-in cooldown periods
- Consider predictive scaling for known traffic patterns

### Cost Optimization Tips

1. **Monitor Spot Prices**: Regularly review spot pricing trends
2. **Adjust Instance Mix**: Increase On-Demand percentage for critical workloads
3. **Right-Size Instances**: Use CloudWatch metrics to optimize instance types
4. **Reserved Instances**: Consider RIs for base On-Demand capacity
5. **Scheduled Scaling**: Implement predictive scaling for known patterns

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../cost-effective-ecs-clusters-with-spot-instances.md)
2. Review AWS ECS documentation for [Spot Instance best practices](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/capacity-providers.html)
3. Consult AWS support for service-specific issues
4. Review CloudWatch logs for detailed error messages

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect changes
3. Follow AWS best practices for security and cost optimization
4. Validate changes against the original recipe requirements

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and AWS terms of service.