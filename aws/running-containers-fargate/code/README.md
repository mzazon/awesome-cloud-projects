# Infrastructure as Code for Running Containers with AWS Fargate

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Running Containers with AWS Fargate".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Docker installed locally for building container images
- IAM permissions for ECS, ECR, Fargate, VPC, Application Auto Scaling, and CloudWatch
- A containerized application ready for deployment (or use the sample app included in scripts)
- Basic understanding of containerization and AWS services

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack with default parameters
aws cloudformation create-stack \
    --stack-name fargate-serverless-containers \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ContainerImage,ParameterValue=your-account.dkr.ecr.region.amazonaws.com/your-repo:latest

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name fargate-serverless-containers

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fargate-serverless-containers \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create ECR repository
# 2. Build and push sample container image
# 3. Create ECS cluster and task definition
# 4. Deploy Fargate service with auto-scaling
# 5. Output service endpoints and details
```

## Deployment Details

### Architecture Components

The infrastructure code deploys the following AWS resources:

- **Amazon ECR Repository**: Secure container image registry with vulnerability scanning
- **ECS Cluster**: Serverless container orchestration cluster using Fargate
- **Task Definition**: Container specification with resource allocation and health checks
- **ECS Service**: Service orchestration with desired task count and load balancing
- **Application Auto Scaling**: Automatic scaling based on CPU utilization (50% target)
- **Security Groups**: Network access controls for container traffic
- **IAM Roles**: Task execution role with minimal required permissions
- **CloudWatch Logs**: Centralized logging for container applications

### Networking Configuration

- Uses default VPC with public subnets for simplicity
- Each Fargate task gets its own elastic network interface
- Security group allows inbound traffic on application port (3000)
- Tasks assigned public IP addresses for external connectivity

### Auto Scaling Configuration

- **Min Capacity**: 1 task
- **Max Capacity**: 10 tasks
- **Target CPU Utilization**: 50%
- **Scale Out Cooldown**: 5 minutes
- **Scale In Cooldown**: 5 minutes

## Customization

### CloudFormation Parameters

- `ContainerImage`: ECR repository URI for your container image
- `ClusterName`: Name for the ECS cluster (default: fargate-cluster)
- `ServiceName`: Name for the ECS service (default: fargate-service)
- `TaskCpu`: CPU units for tasks (default: 256)
- `TaskMemory`: Memory for tasks in MB (default: 512)
- `DesiredCount`: Initial number of tasks (default: 2)

### CDK Configuration

Modify the CDK app configuration by editing:
- `app.ts` or `app.py` for main stack configuration
- Container image URI and resource specifications
- Auto-scaling parameters and thresholds
- VPC and networking configuration

### Terraform Variables

Edit `terraform/variables.tf` to customize:
- `container_image`: Container image URI
- `cluster_name`: ECS cluster name
- `desired_count`: Number of tasks to run
- `cpu`: Task CPU allocation
- `memory`: Task memory allocation
- `min_capacity`: Minimum auto-scaling capacity
- `max_capacity`: Maximum auto-scaling capacity

### Script Configuration

Environment variables in `scripts/deploy.sh`:
- `CONTAINER_PORT`: Application port (default: 3000)
- `TASK_CPU`: CPU units (default: 256)
- `TASK_MEMORY`: Memory in MB (default: 512)
- `DESIRED_COUNT`: Initial task count (default: 2)

## Production Considerations

### Security Enhancements

For production deployments, consider:

- **Private Subnets**: Deploy tasks in private subnets with NAT Gateway
- **Application Load Balancer**: Use ALB for SSL termination and path routing
- **WAF Integration**: Add AWS WAF for application protection
- **Secrets Management**: Use AWS Secrets Manager for sensitive configuration
- **VPC Endpoints**: Add VPC endpoints for ECR and CloudWatch Logs

### Monitoring and Observability

- **Container Insights**: Enable for detailed container metrics
- **X-Ray Tracing**: Add distributed tracing capabilities
- **Custom Metrics**: Implement application-specific CloudWatch metrics
- **Alarms**: Set up CloudWatch alarms for critical metrics

### Cost Optimization

- **Fargate Spot**: Use Fargate Spot for fault-tolerant workloads
- **Right-sizing**: Monitor CPU and memory utilization for optimal sizing
- **Scheduled Scaling**: Implement time-based scaling for predictable patterns

## Validation

### Health Checks

All implementations include:
- Container health checks on `/health` endpoint
- ECS service health monitoring
- Auto-recovery of failed tasks

### Testing Connectivity

After deployment, test the application:

```bash
# Get task public IPs (from deployment outputs)
TASK_IPS=$(aws ecs list-tasks --cluster <cluster-name> --service-name <service-name> --query 'taskArns' --output text | xargs -I {} aws ecs describe-tasks --cluster <cluster-name> --tasks {} --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

# Test application endpoint
for IP in $TASK_IPS; do
    curl -f "http://$IP:3000" && echo " ✅ Task responding"
done
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name fargate-serverless-containers
aws cloudformation wait stack-delete-complete --stack-name fargate-serverless-containers
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

**Note**: The destroy scripts will remove all resources including the ECR repository and container images.

## Troubleshooting

### Common Issues

1. **Task Startup Failures**:
   - Check CloudWatch logs for container errors
   - Verify container image exists in ECR
   - Ensure task execution role has proper permissions

2. **Service Not Stabilizing**:
   - Check health check configuration
   - Verify security group allows health check traffic
   - Review task resource allocation

3. **Auto-scaling Not Working**:
   - Verify CloudWatch metrics are being published
   - Check auto-scaling policy configuration
   - Ensure sufficient load to trigger scaling

### Useful Commands

```bash
# View service events
aws ecs describe-services --cluster <cluster-name> --services <service-name> --query 'services[0].events'

# Check task logs
aws logs tail /ecs/<task-family> --follow

# Monitor auto-scaling activity
aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id service/<cluster>/<service>
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation for context
2. Check AWS ECS and Fargate documentation
3. Validate IAM permissions and network configuration
4. Monitor CloudWatch logs and metrics for insights

## Additional Resources

- [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [Application Auto Scaling](https://docs.aws.amazon.com/autoscaling/application/userguide/what-is-application-auto-scaling.html)
- [Amazon ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)