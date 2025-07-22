# Infrastructure as Code for Elastic Load Balancing with ALB and NLB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Elastic Load Balancing with ALB and NLB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - EC2 (instances, security groups, VPC)
  - Elastic Load Balancing (ALB, NLB, target groups)
  - IAM (for CDK deployments)
- Existing VPC with public subnets in multiple availability zones
- Tool-specific prerequisites:
  - **CloudFormation**: AWS CLI access
  - **CDK**: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
  - **Terraform**: Terraform 1.0+
  - **Bash**: Standard Unix tools (curl, grep, etc.)

## Architecture Overview

This infrastructure creates:
- Application Load Balancer (ALB) for HTTP/HTTPS traffic
- Network Load Balancer (NLB) for high-performance TCP traffic
- Target groups with health checks
- EC2 instances running web servers
- Security groups with proper network segmentation
- Cross-AZ deployment for high availability

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name elb-demo-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=elb-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name elb-demo-stack \
    --query 'Stacks[0].StackStatus'

# Get load balancer DNS names
aws cloudformation describe-stacks \
    --stack-name elb-demo-stack \
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
cdk deploy

# View deployed resources
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

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

# View deployment status
echo "ALB DNS: $ALB_DNS"
echo "NLB DNS: $NLB_DNS"
```

## Testing the Deployment

### Verify Load Balancer Functionality
```bash
# Test Application Load Balancer
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names elb-demo-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Test traffic distribution
for i in {1..5}; do
    echo "Request $i:"
    curl -s http://$ALB_DNS | grep "Instance ID"
    sleep 1
done

# Test Network Load Balancer
NLB_DNS=$(aws elbv2 describe-load-balancers \
    --names elb-demo-nlb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

curl -s http://$NLB_DNS
```

### Verify Health Checks
```bash
# Check ALB target health
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups \
        --names elb-demo-alb-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)

# Check NLB target health
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups \
        --names elb-demo-nlb-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
```

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Unique identifier for all resources (default: elb-demo)
- `InstanceType`: EC2 instance type (default: t3.micro)
- `VpcId`: VPC ID for deployment (uses default VPC if not specified)
- `SubnetIds`: Comma-separated list of subnet IDs

### CDK Configuration
Modify the following in the CDK code:
- `PROJECT_NAME`: Change the project identifier
- `INSTANCE_TYPE`: Adjust EC2 instance sizing
- `VPC_CONFIG`: Specify custom VPC settings
- `HEALTH_CHECK_CONFIG`: Customize health check parameters

### Terraform Variables
Edit `terraform/variables.tf` or create `terraform.tfvars`:
```hcl
project_name = "my-elb-demo"
instance_type = "t3.small"
vpc_id = "vpc-12345678"
subnet_ids = ["subnet-12345678", "subnet-87654321"]
```

### Bash Script Environment Variables
Set these variables before running scripts:
```bash
export PROJECT_NAME="my-elb-demo"
export INSTANCE_TYPE="t3.small"
export AWS_REGION="us-west-2"
```

## Security Considerations

### Network Security
- ALB security group allows HTTP/HTTPS from internet (0.0.0.0/0)
- NLB security group allows TCP traffic on port 80 from internet
- EC2 security group only allows traffic from load balancer security groups
- SSH access is restricted and should be further limited in production

### Best Practices Implemented
- Principle of least privilege for security groups
- Cross-AZ deployment for high availability
- Health checks to ensure traffic only reaches healthy instances
- Session stickiness configured for ALB
- Client IP preservation enabled for NLB

### Production Hardening
For production deployments, consider:
- Implementing SSL/TLS termination with ACM certificates
- Adding WAF integration for application-layer protection
- Restricting SSH access to specific IP ranges or bastion hosts
- Enabling VPC Flow Logs for network monitoring
- Implementing CloudTrail for API auditing

## Monitoring and Observability

### CloudWatch Metrics
Key metrics to monitor:
- `TargetResponseTime`: Response time from targets
- `HealthyHostCount`: Number of healthy targets
- `UnHealthyHostCount`: Number of unhealthy targets
- `RequestCount`: Total requests processed
- `HTTPCode_Target_2XX_Count`: Successful responses

### Logging
- Enable access logs for both ALB and NLB
- Configure CloudWatch Logs for application logs
- Set up CloudTrail for API call logging

### Alarms
Create CloudWatch alarms for:
- High target response times
- Low healthy host count
- High error rates
- Unusual traffic patterns

## Troubleshooting

### Common Issues

1. **Targets not becoming healthy**
   - Check security group rules
   - Verify health check path is accessible
   - Ensure instances are running web servers

2. **Load balancer not accessible**
   - Verify load balancer is in public subnets
   - Check security group allows inbound traffic
   - Confirm DNS resolution is working

3. **Uneven traffic distribution**
   - Check target group health
   - Verify load balancing algorithm settings
   - Review session stickiness configuration

### Debugging Commands
```bash
# Check load balancer status
aws elbv2 describe-load-balancers \
    --names elb-demo-alb elb-demo-nlb

# View target group health
aws elbv2 describe-target-health \
    --target-group-arn <target-group-arn>

# Check security group rules
aws ec2 describe-security-groups \
    --group-names elb-demo-alb-sg elb-demo-nlb-sg elb-demo-ec2-sg
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name elb-demo-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name elb-demo-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the infrastructure
cdk destroy

# Clean up CDK context
rm -rf cdk.out/
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
echo "Cleanup completed"
```

## Cost Optimization

### Resource Costs
- **Application Load Balancer**: ~$16-25/month (base) + data processing fees
- **Network Load Balancer**: ~$16-25/month (base) + data processing fees
- **EC2 Instances**: ~$8-15/month per t3.micro instance
- **Data Transfer**: Variable based on usage

### Cost Reduction Tips
- Use spot instances for non-production workloads
- Implement Auto Scaling to optimize instance count
- Monitor and optimize data transfer costs
- Consider reserved instances for predictable workloads
- Use CloudWatch to track and optimize resource utilization

## Advanced Features

### SSL/TLS Termination
Add HTTPS listeners with ACM certificates:
```bash
# Request ACM certificate
aws acm request-certificate \
    --domain-name example.com \
    --validation-method DNS

# Add HTTPS listener to ALB
aws elbv2 create-listener \
    --load-balancer-arn <alb-arn> \
    --protocol HTTPS \
    --port 443 \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --certificates CertificateArn=<certificate-arn>
```

### Path-Based Routing
Configure advanced routing rules:
```bash
# Create additional target group
aws elbv2 create-target-group \
    --name api-servers \
    --protocol HTTP \
    --port 8080 \
    --vpc-id <vpc-id>

# Add path-based routing rule
aws elbv2 create-rule \
    --listener-arn <listener-arn> \
    --priority 100 \
    --conditions Field=path-pattern,Values="/api/*" \
    --actions Type=forward,TargetGroupArn=<api-target-group-arn>
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS documentation for specific services
3. Verify your AWS permissions and quotas
4. Consult AWS support for service-specific issues

## Additional Resources

- [AWS Elastic Load Balancing Documentation](https://docs.aws.amazon.com/elasticloadbalancing/)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Network Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [Target Group Health Checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)