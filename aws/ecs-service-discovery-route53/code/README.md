# Infrastructure as Code for ECS Service Discovery with Route 53

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ECS Service Discovery with Route 53".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for ECS, Route 53, Elastic Load Balancing, and Cloud Map
- Existing VPC with public and private subnets across multiple AZs
- Basic understanding of containerization and DNS concepts
- Estimated cost: $50-100/month for ALB, ECS tasks, and Route 53 resources

## Architecture Overview

This infrastructure deploys a complete microservices architecture with:

- **ECS Fargate Cluster** running containerized services
- **AWS Cloud Map** for private DNS-based service discovery
- **Application Load Balancer** with path-based routing
- **Route 53 Private Hosted Zone** for internal service resolution
- **Security Groups** configured for proper service communication
- **CloudWatch Logging** for observability

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ecs-service-discovery-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-12345678 \
                 ParameterKey=PrivateSubnetIds,ParameterValue="subnet-12345678,subnet-87654321" \
                 ParameterKey=PublicSubnetIds,ParameterValue="subnet-abcdef12,subnet-21fedcba" \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name ecs-service-discovery-stack \
    --query "Stacks[0].StackStatus"

# Get load balancer URL
aws cloudformation describe-stacks \
    --stack-name ecs-service-discovery-stack \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerURL'].OutputValue" \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters vpcId=vpc-12345678 \
           --parameters privateSubnetIds=subnet-12345678,subnet-87654321 \
           --parameters publicSubnetIds=subnet-abcdef12,subnet-21fedcba

# Get outputs
cdk output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters vpcId=vpc-12345678 \
           --parameters privateSubnetIds=subnet-12345678,subnet-87654321 \
           --parameters publicSubnetIds=subnet-abcdef12,subnet-21fedcba

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="vpc_id=vpc-12345678" \
    -var="private_subnet_ids=[\"subnet-12345678\",\"subnet-87654321\"]" \
    -var="public_subnet_ids=[\"subnet-abcdef12\",\"subnet-21fedcba\"]"

# Apply the configuration
terraform apply \
    -var="vpc_id=vpc-12345678" \
    -var="private_subnet_ids=[\"subnet-12345678\",\"subnet-87654321\"]" \
    -var="public_subnet_ids=[\"subnet-abcdef12\",\"subnet-21fedcba\"]"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export VPC_ID=vpc-12345678
export PRIVATE_SUBNET_IDS="subnet-12345678,subnet-87654321"
export PUBLIC_SUBNET_IDS="subnet-abcdef12,subnet-21fedcba"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the load balancer URL when complete
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `VpcId` | VPC ID for deployment | - | Yes |
| `PrivateSubnetIds` | Comma-separated private subnet IDs | - | Yes |
| `PublicSubnetIds` | Comma-separated public subnet IDs | - | Yes |
| `NamespacePrefix` | Prefix for service discovery namespace | `microservices` | No |
| `ClusterName` | ECS cluster name | `microservices-cluster` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `vpc_id` | VPC ID for deployment | `string` | - | Yes |
| `private_subnet_ids` | List of private subnet IDs | `list(string)` | - | Yes |
| `public_subnet_ids` | List of public subnet IDs | `list(string)` | - | Yes |
| `namespace_name` | Service discovery namespace | `string` | `internal.local` | No |
| `cluster_name` | ECS cluster name | `string` | `microservices-cluster` | No |
| `desired_count` | Desired number of tasks per service | `number` | `2` | No |

### CDK Context

Configure the following in `cdk.json` or pass as parameters:

```json
{
  "vpcId": "vpc-12345678",
  "privateSubnetIds": ["subnet-12345678", "subnet-87654321"],
  "publicSubnetIds": ["subnet-abcdef12", "subnet-21fedcba"],
  "namespaceName": "internal.local",
  "clusterName": "microservices-cluster"
}
```

## Testing the Deployment

### Verify Service Discovery

1. **Check namespace creation**:
   ```bash
   aws servicediscovery list-namespaces \
       --query "Namespaces[?Name=='internal.local']"
   ```

2. **List registered services**:
   ```bash
   aws servicediscovery list-services \
       --query "Services[*].[Name,Id]" --output table
   ```

3. **Test DNS resolution** (requires VPC access):
   ```bash
   # From within the VPC
   nslookup web.internal.local
   nslookup api.internal.local
   ```

### Verify Load Balancer

1. **Get ALB DNS name**:
   ```bash
   # CloudFormation
   aws cloudformation describe-stacks \
       --stack-name ecs-service-discovery-stack \
       --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerURL'].OutputValue" \
       --output text
   
   # Terraform
   terraform output load_balancer_url
   ```

2. **Test web service**:
   ```bash
   curl http://YOUR-ALB-DNS-NAME/
   ```

3. **Test API service**:
   ```bash
   curl http://YOUR-ALB-DNS-NAME/api/
   ```

### Verify ECS Services

1. **Check service status**:
   ```bash
   aws ecs describe-services \
       --cluster microservices-cluster \
       --services web-service api-service \
       --query "services[*].[serviceName,status,runningCount,desiredCount]" \
       --output table
   ```

2. **Check target group health**:
   ```bash
   aws elbv2 describe-target-health \
       --target-group-arn YOUR-TARGET-GROUP-ARN \
       --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
       --output table
   ```

## Troubleshooting

### Common Issues

1. **Tasks not starting**:
   - Check ECS service events: `aws ecs describe-services --cluster CLUSTER --services SERVICE`
   - Verify IAM execution role permissions
   - Check CloudWatch logs for container errors

2. **Service discovery not working**:
   - Verify namespace and services are created: `aws servicediscovery list-services`
   - Check Route 53 private hosted zone records
   - Ensure tasks are in the same VPC as the namespace

3. **Load balancer health checks failing**:
   - Verify security group rules allow ALB to reach tasks
   - Check container health check endpoints (`/health`)
   - Review target group health check configuration

4. **DNS resolution issues**:
   - Ensure tasks are using `awsvpc` network mode
   - Verify VPC DNS settings (enableDnsHostnames and enableDnsSupport)
   - Check security group rules for port 53

### Logs and Monitoring

1. **ECS Task Logs**:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix "/ecs/"
   ```

2. **CloudWatch Insights Queries**:
   ```sql
   fields @timestamp, @message
   | filter @message like /ERROR/
   | sort @timestamp desc
   | limit 100
   ```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ecs-service-discovery-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name ecs-service-discovery-stack \
    --query "Stacks[0].StackStatus"
```

### Using CDK (AWS)

```bash
# Destroy the infrastructure
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="vpc_id=vpc-12345678" \
    -var="private_subnet_ids=[\"subnet-12345678\",\"subnet-87654321\"]" \
    -var="public_subnet_ids=[\"subnet-abcdef12\",\"subnet-21fedcba\"]"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Adding New Services

1. **Update task definitions** with new container configurations
2. **Create additional Cloud Map services** for new service discovery entries
3. **Add target groups and listener rules** for ALB routing
4. **Configure security group rules** for service communication

### Scaling Configuration

1. **Modify desired count** in service definitions
2. **Adjust resource allocations** (CPU/memory) based on load
3. **Configure auto scaling policies** for dynamic scaling
4. **Update ALB target group settings** for larger fleets

### Security Enhancements

1. **Implement SSL/TLS termination** at ALB with ACM certificates
2. **Add WAF protection** for web application firewall rules
3. **Configure VPC endpoints** for private AWS service access
4. **Implement service mesh** with AWS App Mesh for advanced traffic management

## Cost Optimization

1. **Use Fargate Spot** for non-critical workloads (50-70% cost savings)
2. **Right-size tasks** based on actual resource utilization
3. **Implement lifecycle policies** for CloudWatch log retention
4. **Use ALB request routing** to minimize cross-AZ traffic charges

## Support

For issues with this infrastructure code, refer to:

1. [Original recipe documentation](../ecs-service-discovery-route53-application-load-balancer.md)
2. [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
3. [AWS Cloud Map Documentation](https://docs.aws.amazon.com/cloud-map/)
4. [AWS Application Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

## Contributing

When modifying this infrastructure code:

1. Follow AWS best practices for security and cost optimization
2. Update parameter descriptions and validation rules
3. Test changes in a development environment first
4. Update this README with any new configuration options
5. Ensure all IaC implementations remain functionally equivalent