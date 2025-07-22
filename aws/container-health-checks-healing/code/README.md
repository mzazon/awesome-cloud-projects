# Infrastructure as Code for Container Health Checks and Self-Healing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Health Checks and Self-Healing".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Docker installed locally for building container images
- kubectl installed for EKS cluster management
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Appropriate AWS permissions for ECS, EKS, EC2, CloudWatch, Application Load Balancer, Lambda, and IAM

### Required AWS Permissions

Your AWS credentials must have permissions for:
- ECS cluster and service management
- EKS cluster creation and management
- EC2 VPC, subnet, and security group operations
- Application Load Balancer and target group operations
- Lambda function creation and execution
- CloudWatch alarms and metrics
- IAM role creation and policy attachment
- Auto Scaling configuration

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name container-health-checks-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-health-cluster \
                 ParameterKey=ServiceName,ParameterValue=my-health-service

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name container-health-checks-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name container-health-checks-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
# Navigate to Terraform directory
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

# The script will:
# 1. Create VPC and networking components
# 2. Deploy ECS cluster with health checks
# 3. Create Application Load Balancer
# 4. Configure CloudWatch alarms
# 5. Set up auto-scaling policies
# 6. Deploy EKS cluster with health probes
# 7. Create self-healing Lambda function
```

## Architecture Overview

This infrastructure deploys a comprehensive container health checking and self-healing solution including:

### Core Components
- **VPC**: Custom VPC with public subnets across multiple AZs
- **Application Load Balancer**: Layer 7 load balancing with health checks
- **ECS Cluster**: Fargate-based container orchestration with health monitoring
- **EKS Cluster**: Kubernetes orchestration with liveness, readiness, and startup probes
- **Target Groups**: Health check configuration for traffic management

### Monitoring & Self-Healing
- **CloudWatch Alarms**: Multi-metric monitoring for proactive alerting
- **Auto Scaling**: Automatic capacity adjustment based on health metrics
- **Lambda Function**: Advanced self-healing logic for complex recovery scenarios
- **Health Check Endpoints**: Custom health validation endpoints

### Security Features
- **Security Groups**: Network-level access control
- **IAM Roles**: Least privilege access for services
- **VPC Isolation**: Network segmentation for security

## Configuration Options

### CloudFormation Parameters
- `ClusterName`: Name for the ECS cluster
- `ServiceName`: Name for the ECS service
- `VpcCidr`: CIDR block for the VPC (default: 10.0.0.0/16)
- `DesiredCapacity`: Initial number of containers (default: 2)
- `MaxCapacity`: Maximum number of containers for auto-scaling (default: 10)

### CDK Configuration
Modify the stack parameters in `app.ts` (TypeScript) or `app.py` (Python):
```typescript
// CDK TypeScript example
const stack = new ContainerHealthChecksStack(app, 'ContainerHealthChecksStack', {
  clusterName: 'my-health-cluster',
  serviceName: 'my-health-service',
  desiredCapacity: 2,
  maxCapacity: 10,
});
```

### Terraform Variables
Set variables in `terraform.tfvars` or via environment variables:
```hcl
cluster_name = "my-health-cluster"
service_name = "my-health-service"
vpc_cidr = "10.0.0.0/16"
desired_capacity = 2
max_capacity = 10
```

## Health Check Configuration

### ECS Health Checks
- **Command**: `curl -f http://localhost/health || exit 1`
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Retries**: 3
- **Start Period**: 60 seconds

### Application Load Balancer Health Checks
- **Protocol**: HTTP
- **Port**: 80
- **Path**: `/health`
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 3

### Kubernetes Health Probes
- **Liveness Probe**: Detects when containers need restart
- **Readiness Probe**: Controls traffic routing to containers
- **Startup Probe**: Protects slow-starting containers

## Monitoring and Alerts

### CloudWatch Alarms
1. **UnhealthyTargets**: Monitors load balancer target health
2. **HighResponseTime**: Tracks application response times
3. **ECSServiceRunningTasks**: Ensures adequate container capacity

### Auto Scaling Policies
- **ECS Service**: Target tracking based on CPU utilization (70%)
- **Kubernetes HPA**: CPU (70%) and memory (80%) utilization
- **Cooldown Periods**: 300 seconds for scale-out and scale-in

## Testing Health Checks

After deployment, you can test the health check functionality:

```bash
# Get the load balancer DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $(terraform output -raw alb_arn) \
    --query 'LoadBalancers[0].DNSName' --output text)

# Test health endpoints
curl http://$ALB_DNS/health
curl http://$ALB_DNS/

# Simulate container failure
aws ecs list-tasks --cluster $(terraform output -raw cluster_name) \
    --service-name $(terraform output -raw service_name)
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name container-health-checks-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name container-health-checks-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete EKS resources
# 2. Delete ECS resources
# 3. Delete load balancer and networking
# 4. Delete Lambda function and CloudWatch alarms
# 5. Delete IAM roles and VPC resources
```

## Troubleshooting

### Common Issues

1. **ECS Tasks Not Starting**
   - Check CloudWatch logs for container startup issues
   - Verify task definition health check configuration
   - Ensure security groups allow necessary traffic

2. **Load Balancer Health Check Failures**
   - Verify target group health check path is accessible
   - Check security group rules for ALB to container communication
   - Review health check timeout and threshold settings

3. **Auto Scaling Not Triggering**
   - Verify CloudWatch alarms are configured correctly
   - Check IAM permissions for auto scaling service
   - Review scaling policy thresholds and cooldown periods

4. **EKS Cluster Access Issues**
   - Ensure kubectl is configured with correct cluster context
   - Verify IAM permissions for EKS cluster operations
   - Check VPC and subnet configurations

### Debugging Commands

```bash
# Check ECS service health
aws ecs describe-services --cluster CLUSTER_NAME --services SERVICE_NAME

# Check target group health
aws elbv2 describe-target-health --target-group-arn TARGET_GROUP_ARN

# Check CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names ALARM_NAME

# Check Kubernetes pod status
kubectl get pods -l app=health-check-app
kubectl describe pod POD_NAME
```

## Cost Considerations

### Estimated Monthly Costs (US East-1)
- **ECS Fargate**: ~$30-50 for 2 vCPU, 4GB RAM tasks
- **EKS Cluster**: ~$73 for control plane + worker node costs
- **Application Load Balancer**: ~$23 for ALB + data processing
- **CloudWatch**: ~$5-10 for alarms and log ingestion
- **Lambda**: ~$1-2 for self-healing function execution

**Total Estimated Cost**: ~$130-160 per month

### Cost Optimization Tips
- Use Spot instances for EKS worker nodes in non-production
- Implement aggressive auto-scaling policies to minimize idle resources
- Use CloudWatch log retention policies to control log storage costs
- Consider using ECS on EC2 for predictable workloads

## Advanced Configuration

### Custom Health Check Endpoints
Modify the container health check commands to use custom endpoints:

```json
{
  "healthCheck": {
    "command": [
      "CMD-SHELL",
      "curl -f http://localhost/custom-health || exit 1"
    ]
  }
}
```

### Multi-Region Deployment
For high availability, consider deploying across multiple regions:
- Use Route 53 health checks for DNS failover
- Implement cross-region VPC peering for data replication
- Configure CloudWatch cross-region alarms

### Custom Metrics
Implement custom application metrics for more sophisticated health monitoring:
- Use CloudWatch custom metrics for business-specific health indicators
- Implement custom scaling policies based on application-specific metrics
- Create custom alarms for domain-specific failure scenarios

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../container-health-checks-self-healing-applications.md)
- [AWS ECS documentation](https://docs.aws.amazon.com/ecs/)
- [AWS EKS documentation](https://docs.aws.amazon.com/eks/)
- [CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
- [CDK documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your specific requirements.