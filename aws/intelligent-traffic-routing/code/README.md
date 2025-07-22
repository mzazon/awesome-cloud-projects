# Infrastructure as Code for Intelligent Global Traffic Routing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Global Traffic Routing".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - VPCs, subnets, and networking resources
  - Application Load Balancers and target groups
  - Auto Scaling Groups and Launch Templates
  - Route53 hosted zones and health checks
  - CloudFront distributions
  - S3 buckets and policies
  - CloudWatch alarms and dashboards
  - SNS topics and subscriptions
- Domain name for testing (optional, will create example domain)
- Estimated cost: $100-200/month for testing environment

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Basic understanding of AWS CloudFormation templates

#### CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript knowledge recommended

#### CDK Python
- Python 3.8+ installed
- pip package manager
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Python development knowledge recommended

#### Terraform
- Terraform 1.0+ installed
- Basic understanding of HashiCorp Configuration Language (HCL)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name global-load-balancer \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-global-lb \
                 ParameterKey=DomainName,ParameterValue=example-domain.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name global-load-balancer

# Get outputs
aws cloudformation describe-stacks \
    --stack-name global-load-balancer \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export PROJECT_NAME="my-global-lb"
export DOMAIN_NAME="example-domain.com"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# View stack outputs
cdk ls
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment parameters
export PROJECT_NAME="my-global-lb"
export DOMAIN_NAME="example-domain.com"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# View stack outputs
cdk ls
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "my-global-lb"
domain_name = "example-domain.com"
primary_region = "us-east-1"
secondary_region = "eu-west-1"
tertiary_region = "ap-southeast-1"
EOF

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="my-global-lb"
export DOMAIN_NAME="example-domain.com"
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="eu-west-1"
export TERTIARY_REGION="ap-southeast-1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
curl -I https://$(aws cloudfront list-distributions \
    --query 'DistributionList.Items[0].DomainName' \
    --output text)/
```

## Architecture Overview

This implementation creates a comprehensive global load balancing solution with the following components:

### Core Infrastructure
- **Multi-Region VPCs**: Isolated network environments in 3 AWS regions
- **Application Load Balancers**: Regional traffic distribution with health checks
- **Auto Scaling Groups**: Self-healing application instances across regions
- **Sample Web Application**: Simple HTTP service for testing and demonstration

### Global Load Balancing
- **Route53 Health Checks**: Continuous monitoring of regional endpoints
- **DNS Routing Policies**: Weighted and geolocation-based traffic steering
- **CloudFront Distribution**: Global edge network with origin failover
- **Origin Groups**: Automatic failover cascade through all regions

### Monitoring & Alerting
- **CloudWatch Alarms**: Automated notifications for health check failures
- **Monitoring Dashboard**: Unified view of global system health
- **SNS Notifications**: Email/SMS alerts for operational teams

### Fallback Mechanisms
- **S3 Static Content**: Maintenance page for complete service outages
- **Origin Access Control**: Secure access to fallback content
- **Custom Error Pages**: User-friendly error responses

## Testing Your Deployment

### Basic Connectivity Test
```bash
# Get CloudFront domain name
CLOUDFRONT_DOMAIN=$(aws cloudfront list-distributions \
    --query 'DistributionList.Items[0].DomainName' \
    --output text)

# Test main application
curl -s https://${CLOUDFRONT_DOMAIN}/ | grep "Hello from"

# Test health endpoint
curl -s https://${CLOUDFRONT_DOMAIN}/health | jq '.'
```

### Failover Testing
```bash
# Simulate regional failure (if using scripts deployment)
source scripts/test-failover.sh

# Monitor health check status
aws route53 get-health-check --health-check-id <health-check-id>

# Test automatic failover behavior
for i in {1..10}; do
    echo "Test $i:"
    curl -s https://${CLOUDFRONT_DOMAIN}/ | grep "Hello from" || echo "Failed"
    sleep 30
done
```

### DNS Resolution Testing
```bash
# Test weighted routing
nslookup app.${DOMAIN_NAME}

# Test geolocation routing
nslookup geo.${DOMAIN_NAME}

# Check Route53 health check status
aws route53 get-health-check-status --health-check-id <health-check-id>
```

## Customization

### Key Configuration Parameters

| Parameter | Description | Default | Customizable |
|-----------|-------------|---------|--------------|
| `project_name` | Prefix for all resource names | `global-lb-demo` | Yes |
| `domain_name` | Domain for DNS testing | `example.com` | Yes |
| `primary_region` | Primary deployment region | `us-east-1` | Yes |
| `secondary_region` | Secondary failover region | `eu-west-1` | Yes |
| `tertiary_region` | Tertiary failover region | `ap-southeast-1` | Yes |
| `instance_type` | EC2 instance type | `t3.micro` | Yes |
| `min_capacity` | Minimum instances per region | `1` | Yes |
| `max_capacity` | Maximum instances per region | `3` | Yes |
| `desired_capacity` | Desired instances per region | `2` | Yes |

### Customizing for Production

1. **SSL/TLS Certificates**:
   ```bash
   # Request ACM certificate for your domain
   aws acm request-certificate \
       --domain-name *.yourdomain.com \
       --validation-method DNS
   ```

2. **Custom Domain Configuration**:
   - Update CloudFront distribution with your SSL certificate
   - Configure Route53 with your actual domain
   - Update health check endpoints for your application

3. **Security Hardening**:
   - Implement Web Application Firewall (WAF) rules
   - Configure CloudFront security headers
   - Enable AWS Shield Advanced for DDoS protection
   - Implement least-privilege IAM policies

4. **Performance Optimization**:
   - Configure CloudFront caching behaviors
   - Implement gzip compression
   - Optimize health check intervals
   - Configure Auto Scaling policies based on metrics

## Monitoring and Operations

### CloudWatch Dashboards
The deployment creates a comprehensive dashboard showing:
- Route53 health check status across all regions
- CloudFront performance metrics and error rates
- Application Load Balancer response times
- Auto Scaling Group instance health

### Key Metrics to Monitor
- Route53 health check success rate
- CloudFront origin latency and error rates
- ALB target response times
- Auto Scaling Group capacity changes
- CloudWatch alarm states

### Operational Procedures
```bash
# Check overall system health
aws cloudwatch get-dashboard \
    --dashboard-name "Global-LoadBalancer-Dashboard"

# Review health check history
aws route53 get-health-check-status --health-check-id <health-check-id>

# Monitor CloudFront distributions
aws cloudfront list-distributions \
    --query 'DistributionList.Items[*].[Id,DomainName,Status]'

# Check Auto Scaling Group status
aws autoscaling describe-auto-scaling-groups \
    --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,Instances[*].HealthStatus]'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name global-load-balancer

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name global-load-balancer

# Verify deletion
aws cloudformation describe-stacks --stack-name global-load-balancer 2>/dev/null || echo "Stack deleted successfully"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --all
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --all
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`Global load balancer demo`]'
aws route53 list-hosted-zones --query 'HostedZones[?Name==`${DOMAIN_NAME}.`]'
```

## Troubleshooting

### Common Issues

1. **CloudFront Distribution Takes Time to Deploy**:
   - CloudFront deployments can take 15-45 minutes
   - Use `aws cloudfront wait distribution-deployed` to monitor progress

2. **Health Checks Failing**:
   - Verify security groups allow HTTP/HTTPS traffic
   - Check that application instances are responding on `/health` endpoint
   - Ensure Auto Scaling Groups have healthy instances

3. **DNS Resolution Issues**:
   - Route53 changes can take time to propagate
   - Verify health checks are passing before testing DNS
   - Check TTL values for DNS records

4. **Permission Errors**:
   - Ensure AWS credentials have all required permissions
   - CloudFormation and CDK require `CAPABILITY_IAM` for role creation
   - Verify cross-region permissions for multi-region deployments

### Debug Commands
```bash
# Check CloudFront distribution status
aws cloudfront get-distribution --id <distribution-id>

# Verify Route53 health check configuration
aws route53 get-health-check --health-check-id <health-check-id>

# Check Auto Scaling Group instances
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names <asg-name> \
    --query 'AutoScalingGroups[0].Instances'

# Review CloudWatch logs for Lambda functions (if applicable)
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/"
```

### Getting Help

- Review the original recipe documentation for detailed explanations
- Check AWS service documentation for specific service issues
- Use AWS Support for production environment issues
- Consult AWS Well-Architected Framework for optimization guidance

## Cost Optimization

### Estimated Monthly Costs (US East 1)
- **EC2 Instances**: ~$50-100 (6 t3.micro instances across regions)
- **Application Load Balancers**: ~$65 (3 ALBs across regions)
- **Route53 Health Checks**: ~$15 (3 health checks)
- **CloudFront**: ~$5-20 (depends on traffic)
- **Data Transfer**: ~$10-50 (depends on traffic and failover frequency)

### Cost Optimization Tips
1. Use spot instances for non-critical workloads
2. Implement lifecycle policies for CloudWatch logs
3. Optimize CloudFront caching to reduce origin requests
4. Schedule Auto Scaling to match usage patterns
5. Monitor and adjust health check frequencies

## Security Considerations

### Implemented Security Features
- **Network Isolation**: VPCs with private subnets and security groups
- **Encryption**: HTTPS/TLS encryption for all traffic
- **Access Control**: IAM roles with least privilege principles
- **Origin Access Control**: Secure S3 bucket access through CloudFront
- **Resource Tagging**: Comprehensive tagging for governance

### Additional Security Recommendations
1. Enable AWS Config for compliance monitoring
2. Implement AWS WAF for application protection
3. Configure AWS Shield Advanced for DDoS protection
4. Enable CloudTrail for audit logging
5. Use AWS Secrets Manager for sensitive configuration
6. Implement VPC Flow Logs for network monitoring

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Consult AWS Well-Architected Framework
4. Engage AWS Support for production issues
5. Use AWS forums and community resources

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and test thoroughly before using in production environments.