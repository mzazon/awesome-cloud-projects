# Infrastructure as Code for Network Troubleshooting VPC Lattice with Network Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Network Troubleshooting VPC Lattice with Network Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice (service networks, services, target groups)
  - VPC Reachability Analyzer (network insights)
  - CloudWatch (dashboards, alarms, logs)
  - Systems Manager (automation documents, execution)
  - Lambda (functions, permissions)
  - IAM (roles, policies)
  - EC2 (instances, security groups, network interfaces)
  - SNS (topics, subscriptions)
- For CDK implementations: Node.js 18+ or Python 3.9+
- For Terraform: Terraform 1.0+
- Default VPC available in the target region
- Estimated cost: $20-30 for running this infrastructure

## Architecture Overview

This solution deploys:

- **VPC Lattice Service Network** for service mesh connectivity
- **EC2 Test Instances** with security groups for connectivity testing
- **CloudWatch Dashboard** with VPC Lattice performance metrics
- **CloudWatch Alarms** for error rate and latency monitoring
- **SNS Topic** for alert notifications
- **Lambda Function** for automated troubleshooting responses
- **Systems Manager Automation** for VPC Reachability Analyzer workflows
- **IAM Roles** with least privilege permissions

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name network-troubleshooting-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EmailAddress,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name network-troubleshooting-stack \
    --query "Stacks[0].StackStatus"

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name network-troubleshooting-stack
```

### Using CDK TypeScript

```bash
# Navigate to the CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters EmailAddress=your-email@example.com

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to the CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters EmailAddress=your-email@example.com

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="email_address=your-email@example.com"

# Apply the configuration
terraform apply -var="email_address=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export EMAIL_ADDRESS="your-email@example.com"
export AWS_REGION=$(aws configure get region)

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment results
aws cloudformation describe-stacks \
    --stack-name network-troubleshooting-stack \
    --query "Stacks[0].Outputs"
```

## Configuration Parameters

All implementations support the following customizable parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| EmailAddress | Email address for SNS notifications | - | Yes |
| InstanceType | EC2 instance type for test instances | t3.micro | No |
| Environment | Environment tag for resources | test | No |
| VpcId | VPC ID to use (uses default if not specified) | default VPC | No |

### Parameter Examples

**CloudFormation:**
```bash
--parameters \
    ParameterKey=EmailAddress,ParameterValue=admin@company.com \
    ParameterKey=InstanceType,ParameterValue=t3.small \
    ParameterKey=Environment,ParameterValue=production
```

**CDK:**
```bash
cdk deploy \
    --parameters EmailAddress=admin@company.com \
    --parameters InstanceType=t3.small \
    --parameters Environment=production
```

**Terraform:**
```bash
terraform apply \
    -var="email_address=admin@company.com" \
    -var="instance_type=t3.small" \
    -var="environment=production"
```

## Post-Deployment Verification

1. **Verify VPC Lattice Service Network:**
   ```bash
   aws vpc-lattice list-service-networks \
       --query "items[?contains(name, 'troubleshooting')]"
   ```

2. **Check CloudWatch Dashboard:**
   ```bash
   aws cloudwatch list-dashboards \
       --dashboard-name-prefix "VPCLatticeNetworkTroubleshooting"
   ```

3. **Validate SNS Topic Subscription:**
   ```bash
   aws sns list-topics \
       --query "Topics[?contains(TopicArn, 'network-alerts')]"
   ```

4. **Test Lambda Function:**
   ```bash
   aws lambda list-functions \
       --query "Functions[?contains(FunctionName, 'network-troubleshooting')]"
   ```

5. **Verify Automation Document:**
   ```bash
   aws ssm list-documents \
       --document-filter-list "key=Name,value=NetworkReachabilityAnalysis"
   ```

## Testing the Solution

### Manual Troubleshooting Test

```bash
# Get the automation document name
DOCUMENT_NAME=$(aws ssm list-documents \
    --document-filter-list "key=Name,value=NetworkReachabilityAnalysis" \
    --query "DocumentIdentifiers[0].Name" --output text)

# Get test instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*lattice-test*" \
              "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" --output text)

# Get automation role ARN
ROLE_ARN=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'NetworkTroubleshooting')].Arn" \
    --output text)

# Execute network analysis
aws ssm start-automation-execution \
    --document-name ${DOCUMENT_NAME} \
    --parameters \
        "SourceId=${INSTANCE_ID},DestinationId=${INSTANCE_ID},AutomationAssumeRole=${ROLE_ARN}"
```

### Lambda Function Test

```bash
# Get Lambda function name
FUNCTION_NAME=$(aws lambda list-functions \
    --query "Functions[?contains(FunctionName, 'network-troubleshooting')].FunctionName" \
    --output text)

# Create test event
cat > test-event.json << 'EOF'
{
  "Records": [
    {
      "EventSource": "aws:sns",
      "Sns": {
        "Message": "{\"AlarmName\":\"VPCLattice-HighErrorRate\",\"NewStateValue\":\"ALARM\"}"
      }
    }
  ]
}
EOF

# Invoke Lambda function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload file://test-event.json \
    response.json

# View response
cat response.json
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the deployed dashboard to monitor:
- VPC Lattice request count and response times
- HTTP response code distribution (2XX, 4XX, 5XX)
- Active connection counts
- Target response times

### CloudWatch Alarms

The solution includes pre-configured alarms for:
- **High Error Rate**: Triggers when 5XX errors exceed threshold
- **High Latency**: Triggers when response time exceeds 5 seconds

### Log Analysis

```bash
# View VPC Lattice access logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/vpclattice"

# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/network-troubleshooting"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name network-troubleshooting-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name network-troubleshooting-stack
```

### Using CDK

```bash
# Navigate to the appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -var="email_address=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the destruction script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions for all services
2. **VPC Requirements**: A default VPC must exist in the target region
3. **Resource Limits**: Check AWS service quotas for VPC Lattice and Lambda
4. **Email Verification**: SNS requires email verification before sending notifications

### Debug Commands

```bash
# Check stack events for CloudFormation
aws cloudformation describe-stack-events \
    --stack-name network-troubleshooting-stack

# View Lambda function logs
aws logs tail /aws/lambda/network-troubleshooting --follow

# Check automation execution status
aws ssm describe-automation-executions \
    --filters "Key=DocumentName,Values=NetworkReachabilityAnalysis"
```

### Resource Cleanup Issues

If automatic cleanup fails:

```bash
# Manual VPC Lattice cleanup
aws vpc-lattice list-service-networks \
    --query "items[?contains(name, 'troubleshooting')].id" \
    --output text | xargs -I {} aws vpc-lattice delete-service-network --service-network-identifier {}

# Manual Lambda cleanup
aws lambda list-functions \
    --query "Functions[?contains(FunctionName, 'network-troubleshooting')].FunctionName" \
    --output text | xargs -I {} aws lambda delete-function --function-name {}
```

## Customization

### Adding Custom Metrics

Extend the CloudWatch dashboard by modifying the dashboard JSON in your chosen IaC implementation:

```json
{
  "type": "metric",
  "properties": {
    "metrics": [
      ["AWS/VpcLattice", "CustomMetric", "ServiceNetwork", "${ServiceNetworkId}"]
    ],
    "title": "Custom Network Metric"
  }
}
```

### Additional Automation Workflows

Create custom Systems Manager documents for specific troubleshooting scenarios:

```yaml
# Example: DNS resolution troubleshooting
DocumentFormat: YAML
DocumentType: Automation
SchemaVersion: '0.3'
Description: 'Automated DNS resolution analysis'
```

### Security Enhancements

- Enable VPC Flow Logs for comprehensive network monitoring
- Add AWS Config rules for configuration compliance
- Implement AWS CloudTrail for API auditing
- Use AWS Secrets Manager for sensitive configuration data

## Cost Optimization

### Resource Costs

- **VPC Lattice**: Charged per service network and data processing
- **Lambda**: Charged per invocation and execution time
- **CloudWatch**: Charged for custom metrics, alarms, and log storage
- **EC2**: Charged for test instance hours
- **SNS**: Charged per notification sent

### Cost Reduction Tips

1. Use t3.nano instances for testing (instead of t3.micro)
2. Configure CloudWatch log retention policies
3. Set up CloudWatch billing alarms
4. Use AWS Cost Explorer to monitor spend

## Support

### Documentation References

- [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [VPC Reachability Analyzer Guide](https://docs.aws.amazon.com/vpc/latest/reachability/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Systems Manager Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

### Community Resources

- AWS Architecture Center: Network troubleshooting patterns
- AWS Well-Architected Framework: Operational Excellence pillar
- AWS Security Best Practices for VPC Lattice

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies before deploying in production environments.