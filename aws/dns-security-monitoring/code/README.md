# Infrastructure as Code for Automated DNS Security Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated DNS Security Monitoring".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive DNS security monitoring system that:

- Creates DNS Firewall domain lists and rule groups for threat filtering
- Associates firewall rules with VPC to protect DNS traffic
- Enables CloudWatch logging for DNS query analysis
- Deploys Lambda functions for automated threat response
- Configures CloudWatch alarms for threat detection
- Sets up SNS notifications for security alerts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Route 53 Resolver (DNS Firewall, Query Logging)
  - CloudWatch (Logs, Metrics, Alarms)
  - Lambda (Function management, IAM roles)
  - SNS (Topic management, subscriptions)
  - IAM (Role and policy management)
- Existing VPC for DNS firewall association
- Email address for security alert notifications
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Cost Estimation

Expected monthly costs for moderate DNS traffic volumes:
- Route 53 Resolver DNS Firewall: $10-15 (based on VPC associations and query volume)
- CloudWatch Logs: $2-5 (30-day retention)
- CloudWatch Alarms: $0.20 per alarm
- Lambda: $1-3 (based on alert frequency)
- SNS: $0.50-2 (based on notification volume)

**Total estimated cost: $15-25/month**

## Quick Start

### Using CloudFormation

```bash
# Deploy the DNS security monitoring infrastructure
aws cloudformation create-stack \
    --stack-name dns-security-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
        ParameterKey=AlertEmail,ParameterValue=security@company.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name dns-security-monitoring \
    --query 'Stacks[0].StackStatus'

# Get outputs after deployment
aws cloudformation describe-stacks \
    --stack-name dns-security-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export VPC_ID=vpc-xxxxxxxxx
export ALERT_EMAIL=security@company.com

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Configure deployment parameters
export VPC_ID=vpc-xxxxxxxxx
export ALERT_EMAIL=security@company.com

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
vpc_id = "vpc-xxxxxxxxx"
alert_email = "security@company.com"
aws_region = "us-east-1"
environment = "production"
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
export VPC_ID=vpc-xxxxxxxxx
export ALERT_EMAIL=security@company.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Configuration Parameters

### Required Parameters

- **VPC ID**: The VPC where DNS firewall will be associated
- **Alert Email**: Email address for security notifications

### Optional Parameters

- **AWS Region**: Target AWS region (default: us-east-1)
- **Environment**: Environment tag (default: production)
- **Retention Days**: CloudWatch log retention (default: 30 days)
- **Alarm Threshold**: DNS block rate threshold (default: 50 queries)
- **Domain List**: Custom malicious domains (default: sample domains)

## Post-Deployment Configuration

### 1. Confirm Email Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

### 2. Update Domain Lists

Add your organization's specific threat intelligence:

```bash
# Get domain list ID from outputs
DOMAIN_LIST_ID=$(aws route53resolver list-firewall-domain-lists \
    --query "FirewallDomainLists[?contains(Name, 'malicious-domains')].Id" \
    --output text)

# Add additional malicious domains
aws route53resolver update-firewall-domains \
    --firewall-domain-list-id $DOMAIN_LIST_ID \
    --operation ADD \
    --domains badactor.com suspicious.tk malware.example
```

### 3. Test DNS Blocking

From an EC2 instance in the protected VPC:

```bash
# This should be blocked and return NXDOMAIN
dig malware.example

# Check CloudWatch metrics for blocked queries
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Route53Resolver" \
    --metric-name "QueryCount" \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Alerts

### CloudWatch Dashboards

View DNS security metrics in CloudWatch:

1. Navigate to CloudWatch Console
2. Select "Dashboards" from the left menu
3. Look for the DNS Security Dashboard (if created)

### Key Metrics to Monitor

- `AWS/Route53Resolver` - `QueryCount`: Total DNS queries
- `AWS/Route53Resolver` - `ResponseCode`: DNS response codes
- `AWS/Lambda` - `Duration`: Lambda function execution time
- `AWS/Lambda` - `Errors`: Lambda function errors

### Log Analysis

Query DNS logs using CloudWatch Logs Insights:

```sql
fields @timestamp, sourceIpAddress, queryName, responseCode
| filter responseCode = "BLOCKED"
| stats count() by queryName
| sort count desc
| limit 20
```

## Security Considerations

### IAM Permissions

The deployed solution follows the principle of least privilege:

- Lambda execution role has minimal permissions
- DNS Firewall rules are scoped to specific VPCs
- CloudWatch permissions are limited to necessary log groups

### Network Security

- DNS Firewall operates at the VPC level
- All DNS queries are logged for audit purposes
- Automated response functions have built-in safety checks

### Data Protection

- CloudWatch logs have configurable retention periods
- SNS messages are encrypted in transit
- Lambda functions do not store sensitive data

## Troubleshooting

### Common Issues

1. **Email notifications not received**:
   - Check spam folder
   - Verify email subscription confirmation
   - Test SNS topic manually

2. **DNS blocking not working**:
   - Verify VPC association status
   - Check rule group priority
   - Confirm domain list contents

3. **CloudWatch alarms not triggering**:
   - Verify alarm thresholds
   - Check metric namespaces
   - Test with manual metric data

### Debug Commands

```bash
# Check DNS Firewall status
aws route53resolver list-firewall-rule-group-associations

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/route53resolver/dns-security" \
    --start-time $(date -d '1 hour ago' +%s)000

# Test Lambda function
aws lambda invoke \
    --function-name dns-security-response \
    --payload '{"test": true}' \
    response.json
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name dns-security-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name dns-security-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the CDK stack
cdk destroy

# Clean up local files
npm run clean  # TypeScript
# or
rm -rf .venv   # Python
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/destroy.sh --verify
```

## Customization

### Adding Custom Domain Lists

Modify the domain lists in your IaC templates to include organization-specific threats:

```yaml
# CloudFormation example
MaliciousDomains:
  Type: AWS::Route53Resolver::FirewallDomainList
  Properties:
    Domains:
      - malware.example
      - suspicious.tk
      - your-custom-threat.com
```

### Adjusting Alert Thresholds

Modify CloudWatch alarm thresholds based on your environment:

```hcl
# Terraform example
resource "aws_cloudwatch_metric_alarm" "dns_high_block_rate" {
  alarm_name          = "DNS-High-Block-Rate"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "100"  # Adjust as needed
  evaluation_periods  = "2"
}
```

### Extending Lambda Response Actions

Enhance the Lambda function to include additional response actions:

- Update security groups
- Create incident tickets
- Trigger additional security workflows
- Integrate with external SIEM systems

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../implementing-automated-dns-security-monitoring-with-route-53-resolver-dns-firewall-and-cloudwatch.md)
2. Refer to [AWS Route 53 Resolver documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html)
3. Review [CloudWatch documentation](https://docs.aws.amazon.com/cloudwatch/)
4. Consult [Lambda documentation](https://docs.aws.amazon.com/lambda/)

## Contributing

To improve this infrastructure code:

1. Follow AWS Well-Architected Framework principles
2. Maintain backward compatibility
3. Update documentation for any changes
4. Test thoroughly before submission