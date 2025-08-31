# Infrastructure as Code for gRPC Microservices with VPC Lattice and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "gRPC Microservices with VPC Lattice and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete gRPC microservices architecture featuring:
- VPC Lattice Service Network with HTTP/2 support
- Three gRPC microservices (User, Order, and Inventory Services)
- EC2 instances hosting gRPC services with health check endpoints
- Target groups configured for HTTP/2 protocol and health monitoring
- CloudWatch comprehensive monitoring with metrics, logs, and alarms
- Advanced listener rules for intelligent traffic routing

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions including:
  - `vpc-lattice:*` for VPC Lattice service management
  - `cloudwatch:*` for monitoring and logging
  - `ec2:*` for compute resources
  - `iam:CreateRole` and `iam:PassRole` for service roles
  - `logs:*` for CloudWatch logs
- Understanding of gRPC protocols and HTTP/2
- Estimated cost: $25-50 for EC2 instances and CloudWatch during testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name grpc-microservices-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production \
                 ParameterKey=ProjectName,ParameterValue=grpc-demo

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name grpc-microservices-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name grpc-microservices-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy --all

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
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

# Verify deployment
./scripts/verify.sh
```

## Configuration Options

### CloudFormation Parameters

- `Environment`: Deployment environment (development/staging/production)
- `ProjectName`: Project identifier for resource naming
- `VpcCidr`: CIDR block for the VPC (default: 10.0.0.0/16)
- `InstanceType`: EC2 instance type for gRPC services (default: t3.micro)
- `KeyPairName`: EC2 Key Pair for SSH access (optional)

### CDK Configuration

Both TypeScript and Python CDK implementations support these environment variables:
- `CDK_DEFAULT_REGION`: Target AWS region
- `CDK_DEFAULT_ACCOUNT`: Target AWS account
- `ENVIRONMENT`: Deployment environment tag
- `PROJECT_NAME`: Project identifier

### Terraform Variables

- `region`: AWS region for deployment
- `environment`: Environment tag for resources
- `project_name`: Project identifier for naming
- `vpc_cidr`: VPC CIDR block
- `instance_type`: EC2 instance type
- `key_pair_name`: Optional EC2 key pair

### Bash Script Configuration

Environment variables can be set in `scripts/config.env`:
- `AWS_REGION`: Target AWS region
- `ENVIRONMENT`: Environment identifier
- `PROJECT_NAME`: Project name for resource tagging

## Deployment Verification

After deployment, verify the infrastructure:

### Check VPC Lattice Service Network

```bash
# List service networks
aws vpc-lattice list-service-networks \
    --query 'items[?contains(name, `grpc-microservices`)].{Name:name,Status:status}'

# Check service network details
SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
    --query 'items[?contains(name, `grpc-microservices`)].id' \
    --output text)

aws vpc-lattice get-service-network \
    --service-network-identifier ${SERVICE_NETWORK_ID}
```

### Verify gRPC Services

```bash
# List VPC Lattice services
aws vpc-lattice list-services \
    --query 'items[?contains(name, `service`)].{Name:name,Status:status,DNS:dnsEntry.domainName}'

# Check target group health
aws vpc-lattice list-target-groups \
    --query 'items[].{Name:name,Status:status}' \
    --output table
```

### Test Health Endpoints

```bash
# Get EC2 instance IPs and test health endpoints
aws ec2 describe-instances \
    --filters 'Name=tag:Service,Values=UserService,OrderService,InventoryService' \
    --query 'Reservations[].Instances[].{Service:Tags[?Key==`Service`].Value|[0],IP:PrivateIpAddress,State:State.Name}' \
    --output table

# Test health endpoints (replace IP with actual instance IP)
curl -s http://INSTANCE_IP:8080/health | jq .
```

### Monitor CloudWatch Metrics

```bash
# Check CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "gRPC-Microservices-*" \
    --query 'DashboardName'

# View recent metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VpcLattice \
    --metric-name TotalRequestCount \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name grpc-microservices-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name grpc-microservices-stack
```

### Using CDK

```bash
# Destroy all CDK stacks
cdk destroy --all

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Adding Additional gRPC Services

To add more gRPC microservices:

1. **CloudFormation**: Add new target group and service resources in the template
2. **CDK**: Extend the service array in the stack configuration
3. **Terraform**: Add new service modules to `main.tf`
4. **Bash**: Update deployment script with additional service creation commands

### Modifying Health Check Configuration

Health check parameters can be customized in each implementation:
- `healthCheckIntervalSeconds`: Frequency of health checks
- `healthyThresholdCount`: Required consecutive healthy checks
- `unhealthyThresholdCount`: Required consecutive unhealthy checks
- `healthCheckTimeoutSeconds`: Timeout for each health check

### Scaling Configuration

To modify instance counts or types:
- Update `InstanceType` parameter in CloudFormation
- Modify instance configuration in CDK constructs
- Change `instance_type` variable in Terraform
- Update script variables for Bash deployment

### Advanced Routing Rules

Each implementation includes examples of:
- Header-based routing for API versioning
- Path-based routing for gRPC method routing
- Weighted routing for canary deployments

Modify the listener rule configurations to implement custom routing logic.

## Monitoring and Observability

### CloudWatch Integration

The deployed infrastructure includes:
- **Metrics**: VPC Lattice service metrics for all gRPC services
- **Logs**: Access logs for request tracking and debugging
- **Alarms**: Proactive monitoring for error rates and latency
- **Dashboard**: Centralized visualization of service health

### Custom Metrics

To add custom application metrics:
1. Install CloudWatch agent on EC2 instances
2. Configure custom metric collection
3. Update dashboard with additional visualizations
4. Create alarms for business-specific thresholds

### Distributed Tracing

For enhanced observability, consider integrating:
- AWS X-Ray for distributed tracing
- OpenTelemetry for standardized instrumentation
- Custom gRPC interceptors for request correlation

## Security Considerations

### Network Security

- VPC with private subnets for gRPC services
- Security groups restricting access to required ports (50051-50053, 8080)
- VPC Lattice IAM authentication for service-to-service communication

### Data Protection

- TLS encryption for all gRPC communication
- IAM roles with least privilege access
- CloudWatch logs encryption at rest

### Access Control

- Service-level IAM policies for VPC Lattice
- EC2 instance profiles with minimal required permissions
- Optional SSH key pair for debugging access

## Troubleshooting

### Common Issues

1. **Target Group Health Checks Failing**
   - Verify EC2 instances are running health check servers on port 8080
   - Check security group rules allow health check traffic
   - Review CloudWatch logs for health check errors

2. **gRPC Communication Issues**
   - Confirm HTTP/2 protocol is configured in target groups
   - Verify listener rules are correctly routing traffic
   - Check VPC Lattice service DNS resolution

3. **CloudWatch Metrics Missing**
   - Ensure VPC Lattice services are associated with service network
   - Verify IAM permissions for CloudWatch metrics
   - Check metric filter configurations

### Debugging Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service --service-identifier SERVICE_ID

# View target group targets and health
aws vpc-lattice list-targets --target-group-identifier TARGET_GROUP_ID

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/vpc-lattice

# Test connectivity from EC2 instance
aws ssm start-session --target INSTANCE_ID
```

## Performance Optimization

### gRPC Optimization

- Enable gRPC keepalive settings for persistent connections
- Configure connection pooling for client applications
- Use gRPC compression for large payloads
- Implement client-side load balancing where appropriate

### VPC Lattice Optimization

- Monitor target group utilization and scale instances accordingly
- Use weighted routing for gradual traffic shifting
- Implement circuit breaker patterns with listener rules
- Consider cross-zone load balancing for high availability

### CloudWatch Optimization

- Adjust log retention periods based on compliance requirements
- Use metric filters to reduce log processing costs
- Implement log aggregation for centralized analysis
- Set appropriate alarm thresholds to minimize false positives

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../grpc-microservices-lattice-cloudwatch.md)
- [AWS VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [AWS CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [gRPC Documentation](https://grpc.io/docs/)

## Contributing

When modifying this infrastructure code:
1. Test changes in a development environment
2. Update documentation for any configuration changes
3. Validate security configurations
4. Ensure cleanup procedures work correctly
5. Update version comments in implementation files

---

**Note**: This infrastructure deploys production-ready gRPC microservices with comprehensive monitoring. Ensure you understand the cost implications and security requirements before deploying to production environments.