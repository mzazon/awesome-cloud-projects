# Infrastructure as Code for Creating DNS-Based Load Balancing with Route 53

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Creating DNS-Based Load Balancing with Route 53".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive DNS-based load balancing solution using Amazon Route 53 with multiple routing policies:

- **Route 53 Hosted Zone** for DNS management
- **Multi-region ALB infrastructure** across US East, EU West, and APAC regions
- **Health checks** for automatic failover
- **Multiple routing policies**: Weighted, Latency-based, Geolocation, Failover, and Multivalue
- **SNS notifications** for health check alerts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Route 53 (hosted zones, health checks, record management)
  - EC2 (VPC, subnets, security groups, instances)
  - Elastic Load Balancing (ALB creation and management)
  - SNS (topic creation and management)
  - IAM (role creation for health checks)
- Basic understanding of DNS concepts and Route 53 routing policies
- Domain name for testing (can be a subdomain)
- Estimated cost: $50-100/month for multi-region deployment

> **Note**: This recipe creates resources across multiple AWS regions (us-east-1, eu-west-1, ap-southeast-1). Ensure you have appropriate permissions and consider cross-region costs.

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name dns-load-balancing-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=example.com \
                 ParameterKey=Environment,ParameterValue=production \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name dns-load-balancing-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name dns-load-balancing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment
export CDK_DOMAIN_NAME=example.com
export CDK_ENVIRONMENT=production

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DOMAIN_NAME=example.com
export CDK_ENVIRONMENT=production

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
domain_name = "example.com"
environment = "production"
primary_region = "us-east-1"
secondary_region = "eu-west-1"
tertiary_region = "ap-southeast-1"
enable_health_check_notifications = true
EOF

# Plan the deployment
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
export DOMAIN_NAME=example.com
export ENVIRONMENT=production
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=eu-west-1
export TERTIARY_REGION=ap-southeast-1

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| DomainName | Domain name for DNS records | - | Yes |
| Environment | Environment tag for resources | production | No |
| PrimaryRegion | Primary AWS region | us-east-1 | No |
| SecondaryRegion | Secondary AWS region | eu-west-1 | No |
| TertiaryRegion | Tertiary AWS region | ap-southeast-1 | No |
| HealthCheckInterval | Health check interval in seconds | 30 | No |
| HealthCheckFailureThreshold | Number of failures before marking unhealthy | 3 | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| domain_name | Domain name for DNS records | string | - |
| environment | Environment tag | string | "production" |
| primary_region | Primary AWS region | string | "us-east-1" |
| secondary_region | Secondary AWS region | string | "eu-west-1" |
| tertiary_region | Tertiary AWS region | string | "ap-southeast-1" |
| vpc_cidr | CIDR block for VPCs | string | "10.0.0.0/16" |
| enable_health_check_notifications | Enable SNS notifications | bool | true |
| health_check_interval | Health check interval | number | 30 |
| health_check_failure_threshold | Failure threshold | number | 3 |

### CDK Configuration

CDK implementations use environment variables for configuration:

```bash
export CDK_DOMAIN_NAME=your-domain.com
export CDK_ENVIRONMENT=production
export CDK_PRIMARY_REGION=us-east-1
export CDK_SECONDARY_REGION=eu-west-1
export CDK_TERTIARY_REGION=ap-southeast-1
export CDK_ENABLE_NOTIFICATIONS=true
```

## Testing and Validation

After deployment, test the various routing policies:

### Test DNS Resolution
```bash
# Test weighted routing
for i in {1..10}; do
    echo "Query $i: $(dig +short api.your-domain.com @8.8.8.8)"
done

# Test geolocation routing
dig +short geo.api.your-domain.com @8.8.8.8

# Test latency-based routing
dig +short latency.api.your-domain.com @8.8.8.8

# Test failover routing
dig +short failover.api.your-domain.com @8.8.8.8

# Test multivalue routing
dig +short multivalue.api.your-domain.com @8.8.8.8
```

### Verify Health Checks
```bash
# Check health check status (CloudFormation/CDK)
aws route53 list-health-checks \
    --query 'HealthChecks[*].[Id,HealthCheckConfig.FullyQualifiedDomainName]' \
    --output table

# Check specific health check status
aws route53 get-health-check-status \
    --health-check-id <health-check-id> \
    --query 'StatusList[0]'
```

### Monitor with CloudWatch
```bash
# View health check metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53 \
    --metric-name HealthCheckStatus \
    --dimensions Name=HealthCheckId,Value=<health-check-id> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name dns-load-balancing-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name dns-load-balancing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy all stacks
cdk destroy --all

# Confirm destruction
cdk list
```

### Using Terraform
```bash
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm with force flag if needed
./scripts/destroy.sh --force
```

## Troubleshooting

### Common Issues

1. **Domain not owned**: Ensure you own the domain or use a test domain
2. **Health checks failing**: Verify ALB endpoints are accessible on port 80
3. **DNS propagation**: Allow 24-48 hours for full DNS propagation
4. **Cross-region resources**: Ensure proper region configuration
5. **IAM permissions**: Verify all required permissions are granted

### Debug Commands

```bash
# Check Route 53 records
aws route53 list-resource-record-sets \
    --hosted-zone-id <zone-id> \
    --output table

# Verify ALB status
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[*].[LoadBalancerName,State.Code,DNSName]' \
    --output table

# Check health check configuration
aws route53 get-health-check \
    --health-check-id <health-check-id>

# Monitor SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn <topic-arn>
```

### Performance Optimization

1. **TTL Values**: Adjust TTL values based on your failover requirements
2. **Health Check Frequency**: Balance cost with detection speed
3. **Region Selection**: Choose regions closest to your user base
4. **Weight Distribution**: Optimize based on regional capacity and cost

## Cost Optimization

### Estimated Monthly Costs

- **Route 53 Hosted Zone**: $0.50 per hosted zone
- **Health Checks**: $0.50 per health check (3 total)
- **DNS Queries**: $0.40 per million queries
- **ALBs**: ~$16-25 per ALB per month (3 total)
- **EC2 Instances**: Varies based on instance type and usage
- **Data Transfer**: Varies based on traffic volume

### Cost Reduction Tips

1. **Reduce health check frequency** for non-critical applications
2. **Use fewer regions** if global coverage isn't required
3. **Optimize ALB target group health checks** to reduce false positives
4. **Monitor DNS query volume** and optimize caching

## Security Considerations

### Network Security
- Security groups restrict access to necessary ports only
- ALBs are deployed in public subnets with controlled access
- Private subnets can be used for application instances

### DNS Security
- Health checks use HTTP (consider HTTPS for production)
- TTL values balance security and performance
- Consider DNS logging for audit trails

### Access Control
- IAM roles follow least privilege principle
- Resource-based policies restrict cross-account access
- CloudTrail logging for all Route 53 API calls

## Advanced Configuration

### Custom Health Check Endpoints
Modify health check paths to use custom endpoints:

```bash
# Update health check resource path
aws route53 update-health-check \
    --health-check-id <health-check-id> \
    --resource-path /api/health/detailed
```

### SSL/TLS Configuration
For production deployments, configure HTTPS:

1. Request SSL certificates via ACM
2. Update ALB listeners for HTTPS
3. Modify health checks to use HTTPS
4. Update security group rules for port 443

### Private DNS Zones
For internal applications, consider Route 53 private hosted zones:

```bash
# Create private hosted zone
aws route53 create-hosted-zone \
    --name internal.example.com \
    --vpc VPCRegion=us-east-1,VPCId=<vpc-id> \
    --caller-reference private-$(date +%s)
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for conceptual guidance
2. **AWS Documentation**: Check Route 53, ELB, and VPC documentation
3. **Provider Documentation**: 
   - [AWS Route 53 Developer Guide](https://docs.aws.amazon.com/route53/)
   - [CloudFormation Route 53 Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_Route53.html)
   - [CDK Route 53 Construct Library](https://docs.aws.amazon.com/cdk/api/latest/docs/aws-route53-readme.html)
   - [Terraform AWS Provider Route 53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone)

## Contributing

When modifying this infrastructure code:

1. Test all deployment methods before committing
2. Update documentation for any new parameters or outputs
3. Ensure backward compatibility when possible
4. Follow the established patterns for each IaC tool
5. Validate syntax and best practices compliance