# Infrastructure as Code for Cross-Region Service Failover with VPC Lattice and Route53

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Region Service Failover with VPC Lattice and Route53".

## Overview

This infrastructure deploys a resilient multi-region microservices architecture using VPC Lattice service networks for secure service-to-service communication and Route53 health checks for DNS-based failover. The solution establishes service networks in both primary and secondary regions, deploys health check endpoints using Lambda functions, and configures intelligent DNS routing to automatically detect service failures and redirect traffic to healthy regions.

## Architecture Components

- **VPC Lattice Service Networks**: Secure cross-VPC service communication in primary (us-east-1) and secondary (us-west-2) regions
- **Lambda Functions**: Health check endpoints with application-level validation
- **Route53 Health Checks**: Continuous monitoring from multiple AWS edge locations
- **Route53 DNS Failover**: Automatic traffic routing based on health check status
- **CloudWatch Monitoring**: Observability and alerting for health check events
- **IAM Roles**: Least-privilege access for Lambda execution

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS account with appropriate permissions for VPC Lattice, Route53, Lambda, CloudWatch, and IAM
- AWS CLI v2 installed and configured (or AWS CloudShell access)
- Access to create resources in multiple AWS regions (us-east-1 and us-west-2)
- Domain name or subdomain for health check endpoints (or Route53 hosted zone management permissions)

### Permissions Required
- `vpc-lattice:*` - Full VPC Lattice permissions
- `route53:*` - Route53 hosted zone and health check management
- `lambda:*` - Lambda function creation and management
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole` - IAM role management
- `cloudwatch:PutMetricAlarm` - CloudWatch alarm creation
- `ec2:CreateVpc`, `ec2:DeleteVpc` - VPC management (if creating new VPCs)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- Understanding of CloudFormation stack management

#### CDK (TypeScript)
- Node.js 18+ and npm
- AWS CDK CLI v2 (`npm install -g aws-cdk`)
- TypeScript knowledge

#### CDK (Python)
- Python 3.8+
- AWS CDK CLI v2 (`pip install aws-cdk-lib`)
- Python packaging tools (pip, setuptools)

#### Terraform
- Terraform 1.0+ installed
- AWS provider for Terraform
- Understanding of Terraform state management

### Cost Estimates
- **VPC Lattice**: ~$0.025/hour per service network + $0.02 per million requests
- **Lambda**: AWS Free Tier eligible (first 1M requests free, then $0.20 per 1M requests)
- **Route53**: $0.50/month per hosted zone + $0.50/month per health check
- **CloudWatch**: $0.30/month per alarm
- **Total estimated cost**: $20-35 for the duration of testing

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cross-region-failover-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=api-example.your-domain.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name cross-region-failover-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'

# Get outputs after deployment
aws cloudformation describe-stacks \
    --stack-name cross-region-failover-stack \
    --region us-east-1 \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View stack outputs
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

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the infrastructure
cdk deploy --all

# View stack outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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
export DOMAIN_NAME="api-example.your-domain.com"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables
All implementations support these environment variables for customization:

- `DOMAIN_NAME`: Domain name for the health check endpoints (required)
- `PRIMARY_REGION`: Primary AWS region (default: us-east-1)
- `SECONDARY_REGION`: Secondary AWS region (default: us-west-2)
- `SERVICE_NETWORK_NAME`: Name for VPC Lattice service networks
- `HEALTH_CHECK_INTERVAL`: Health check interval in seconds (default: 30)
- `FAILURE_THRESHOLD`: Number of failed checks before failover (default: 3)

### CloudFormation Parameters
- `DomainName`: The domain name for health check endpoints
- `PrimaryRegion`: Primary AWS region for deployment
- `SecondaryRegion`: Secondary AWS region for deployment
- `Environment`: Environment tag (default: production)

### CDK Context Variables
Set in `cdk.json` or via command line:
```bash
cdk deploy -c domainName=api-example.your-domain.com
```

### Terraform Variables
Configure in `terraform.tfvars`:
```hcl
domain_name = "api-example.your-domain.com"
primary_region = "us-east-1"
secondary_region = "us-west-2"
environment = "production"
```

## Validation and Testing

### Health Check Validation
```bash
# Check health check status
aws route53 get-health-check-status --health-check-id HEALTH_CHECK_ID

# Test DNS resolution
dig your-domain.com CNAME

# Test service endpoints directly
curl -k https://SERVICE_DNS_NAME
```

### Failover Testing
```bash
# Simulate primary region failure (example with Lambda)
aws lambda put-function-configuration \
    --function-name FUNCTION_NAME \
    --environment 'Variables={SIMULATE_FAILURE=true}' \
    --region us-east-1

# Monitor failover in DNS resolution
watch -n 10 'dig +short your-domain.com CNAME'

# Restore primary region
aws lambda put-function-configuration \
    --function-name FUNCTION_NAME \
    --environment 'Variables={SIMULATE_FAILURE=false}' \
    --region us-east-1
```

### Monitoring
```bash
# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53 \
    --metric-name HealthCheckStatus \
    --dimensions Name=HealthCheckId,Value=HEALTH_CHECK_ID \
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
    --stack-name cross-region-failover-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cross-region-failover-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy all stacks
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm destruction when prompted
```

## Troubleshooting

### Common Issues

#### VPC Lattice Service Creation Fails
- **Issue**: Service network creation timeout
- **Solution**: Ensure proper IAM permissions and region availability
- **Command**: Check service status with `aws vpc-lattice describe-service-network`

#### Route53 Health Checks Failing
- **Issue**: Health checks showing failed status
- **Solution**: Verify Lambda function deployment and VPC Lattice service endpoints
- **Command**: Test endpoints directly with `curl -k https://SERVICE_DNS_NAME`

#### DNS Resolution Not Working
- **Issue**: Domain not resolving to correct endpoint
- **Solution**: Verify hosted zone delegation and health check configuration
- **Command**: Use `dig` command to trace DNS resolution

#### Cross-Region Connectivity Issues
- **Issue**: Services not accessible across regions
- **Solution**: Check VPC Lattice service network associations and security groups
- **Command**: Review service associations with `aws vpc-lattice list-service-network-service-associations`

### Debug Commands
```bash
# List all VPC Lattice resources
aws vpc-lattice list-service-networks --region us-east-1
aws vpc-lattice list-services --region us-east-1

# Check Route53 health check status
aws route53 list-health-checks
aws route53 get-health-check-status --health-check-id HEALTH_CHECK_ID

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/
aws logs get-log-events --log-group-name LOG_GROUP_NAME --log-stream-name LOG_STREAM_NAME

# Check CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM
```

## Security Considerations

### IAM Best Practices
- All Lambda functions use least-privilege IAM roles
- Cross-service access is explicitly defined
- No hardcoded credentials in any configuration

### Network Security
- VPC Lattice provides secure service-to-service communication
- Health check endpoints use HTTPS encryption
- Service networks enforce traffic policies

### DNS Security
- Route53 health checks validate SSL certificates
- DNS records use short TTL values for rapid failover
- Health check endpoints implement input validation

## Performance Optimization

### Health Check Tuning
- Default 30-second health check interval balances responsiveness with costs
- Failure threshold of 3 attempts reduces false positives
- Consider adjusting based on application requirements

### DNS Optimization
- TTL values of 60 seconds enable rapid failover
- Multiple health check locations provide global validation
- Consider using Route53 Application Recovery Controller for advanced scenarios

### Cost Optimization
- Lambda functions use minimal memory allocation (256MB)
- Health checks run every 30 seconds (minimum billable interval)
- VPC Lattice charges are usage-based with no minimum fees

## Advanced Configuration

### Custom Health Check Logic
Modify the Lambda function to implement application-specific health checks:

```python
def check_service_health():
    """
    Implement custom health validation
    """
    # Database connectivity check
    # External API availability
    # Cache service status
    # Application metrics validation
    return True
```

### Multi-Region Extensions
- Add additional regions by replicating the service network pattern
- Implement weighted routing for active-active configurations
- Consider Route53 Application Recovery Controller for complex scenarios

### Integration with CI/CD
- Use the Terraform implementation for GitOps workflows
- Implement automated testing of failover scenarios
- Consider blue-green deployment patterns within each region

## Support and Documentation

### Official AWS Documentation
- [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [Route53 DNS Failover Configuration](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-configuring.html)
- [Route53 Health Check Types](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-types.html)

### Additional Resources
- [AWS Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [AWS Disaster Recovery Strategies](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS service documentation
4. Use AWS Support for service-specific issues

## License

This infrastructure code is provided as-is for educational and implementation purposes. Users are responsible for understanding and managing the costs and security implications of deployed resources.