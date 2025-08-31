# Infrastructure as Code for Automated Service Lifecycle with VPC Lattice and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Service Lifecycle with VPC Lattice and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements automated service lifecycle management using:
- **VPC Lattice**: Application-layer networking for microservices
- **EventBridge**: Event-driven automation and routing
- **Lambda**: Serverless lifecycle management functions
- **CloudWatch**: Monitoring, metrics, and scheduled health checks
- **IAM**: Secure access controls and permissions

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for:
  - VPC Lattice (CreateServiceNetwork, CreateService, etc.)
  - EventBridge (CreateEventBus, PutRule, PutTargets)
  - Lambda (CreateFunction, InvokeFunction)
  - CloudWatch (PutDashboard, CreateLogGroup)
  - IAM (CreateRole, AttachRolePolicy)
- Estimated cost: $25-50 per month for testing environment
- Basic understanding of microservices and event-driven architectures

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.x or higher
- CloudFormation deployment permissions

#### CDK TypeScript
- Node.js 18.x or higher
- npm or yarn package manager
- AWS CDK v2.x installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or higher
- pip package manager
- AWS CDK v2.x installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform v1.0 or higher
- AWS provider v5.x or higher

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name service-lifecycle-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name service-lifecycle-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name service-lifecycle-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first-time setup)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first-time setup)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
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

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Deployment environment (dev/staging/prod) | dev | No |
| ServiceNetworkName | VPC Lattice service network name | microservices-network | No |
| EventBusName | Custom EventBridge bus name | service-lifecycle-bus | No |
| HealthCheckFrequency | Health check frequency in minutes | 5 | No |
| LogRetentionDays | CloudWatch log retention period | 7 | No |

### CDK Configuration

Modify `cdk.json` or pass context variables:

```bash
# CDK TypeScript/Python
cdk deploy -c environment=staging -c healthCheckFrequency=3
```

### Terraform Variables

Create `terraform.tfvars` file:

```hcl
environment = "dev"
service_network_name = "my-microservices-network"
event_bus_name = "my-service-lifecycle-bus"
health_check_frequency = 5
log_retention_days = 14
aws_region = "us-west-2"
```

## Validation & Testing

### Verify Deployment

```bash
# Check VPC Lattice service network
aws vpc-lattice list-service-networks

# Verify EventBridge custom bus
aws events list-event-buses

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `service-lifecycle`)]'

# View CloudWatch dashboard
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `ServiceLifecycle`)]'
```

### Test Health Monitoring

```bash
# Trigger health monitoring function manually
aws lambda invoke \
    --function-name $(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `health-monitor`)].FunctionName' \
        --output text) \
    --payload '{}' \
    response.json

# Check response
cat response.json
```

### Monitor EventBridge Events

```bash
# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the automatically created dashboard:

```bash
# Get dashboard URL
aws cloudwatch list-dashboards \
    --dashboard-name-prefix ServiceLifecycle \
    --query 'DashboardEntries[0].DashboardName' \
    --output text
```

### Log Analysis

```bash
# View health monitor logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/service-health-monitor \
    --start-time $(date -d '1 hour ago' +%s)000

# View auto-scaler logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/service-auto-scaler \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Metrics and Alarms

Key metrics to monitor:
- VPC Lattice request count and response times
- Lambda function duration and error rates
- EventBridge rule success/failure rates
- Auto-scaling actions triggered

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure the deployment role has all required permissions
2. **Resource Limits**: Check AWS service quotas for VPC Lattice and Lambda
3. **EventBridge Rules**: Verify event patterns match expected event structure
4. **Lambda Timeouts**: Monitor function duration and adjust timeout settings

### Debug Commands

```bash
# Check CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name service-lifecycle-stack

# Verify IAM role policies
aws iam list-attached-role-policies \
    --role-name ServiceLifecycleRole

# Test EventBridge rule
aws events test-event-pattern \
    --event-pattern file://event-pattern.json \
    --event file://sample-event.json
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name service-lifecycle-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name service-lifecycle-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
aws vpc-lattice list-service-networks
aws events list-event-buses --name-prefix service-lifecycle
aws lambda list-functions --query 'Functions[?contains(FunctionName, `service-lifecycle`)]'
aws logs describe-log-groups --log-group-name-prefix /aws/vpclattice/service-lifecycle
```

## Customization

### Adding Custom Health Checks

Modify the health monitoring Lambda function to include additional metrics:

```python
# Add custom health check logic
def check_database_connectivity():
    # Custom database health check
    pass

def check_external_dependencies():
    # Check external service dependencies
    pass
```

### Custom Scaling Policies

Enhance the auto-scaling function with custom scaling logic:

```python
# Implement custom scaling policies
def calculate_desired_capacity(current_metrics):
    # Custom scaling algorithm
    pass
```

### Multi-Region Deployment

For multi-region deployments:

1. Deploy the stack in multiple regions
2. Configure cross-region EventBridge replication
3. Set up Route 53 health checks for failover

### Integration with CI/CD

Add to your CI/CD pipeline:

```yaml
# Example GitHub Actions workflow
- name: Deploy Service Lifecycle
  run: |
    cd terraform/
    terraform init
    terraform plan
    terraform apply -auto-approve
```

## Performance Optimization

### Lambda Function Optimization

- Adjust memory allocation based on function performance
- Enable provisioned concurrency for consistent performance
- Implement connection pooling for database connections

### EventBridge Optimization

- Use specific event patterns to reduce rule evaluations
- Implement dead letter queues for failed events
- Monitor rule execution metrics

### VPC Lattice Optimization

- Configure appropriate target group settings
- Enable access logs for detailed traffic analysis
- Implement proper health check configurations

## Security Considerations

### IAM Best Practices

- Use least privilege principle for all roles
- Regularly audit IAM permissions
- Enable CloudTrail for API logging

### Network Security

- Configure VPC Lattice auth policies
- Use security groups for additional protection
- Enable encryption in transit and at rest

### Secrets Management

- Store sensitive configuration in AWS Secrets Manager
- Use IAM roles instead of access keys
- Regularly rotate credentials

## Cost Optimization

### Monitoring Costs

```bash
# Check AWS Cost Explorer for service costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

### Cost Reduction Strategies

- Use appropriate Lambda memory allocation
- Implement log retention policies
- Monitor VPC Lattice data transfer costs
- Use spot instances for development environments

## Support and Documentation

### AWS Documentation Links

- [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/latest/monitoring/)

### Community Resources

- AWS re:Invent sessions on VPC Lattice and EventBridge
- AWS Architecture Center patterns
- AWS Samples GitHub repository

### Getting Help

- AWS Support Center for technical issues
- AWS Developer Forums for community support
- AWS Professional Services for enterprise guidance

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.