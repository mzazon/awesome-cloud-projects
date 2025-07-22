# Infrastructure as Code for Building Global Active-Active Architecture with AWS Global Accelerator

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Global Active-Active Architecture with AWS Global Accelerator".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a globally distributed, active-active application architecture featuring:

- **AWS Global Accelerator** for intelligent traffic routing with static anycast IP addresses
- **DynamoDB Global Tables** for automatic multi-region data replication
- **Lambda functions** in multiple regions (us-east-1, eu-west-1, ap-southeast-1)
- **Application Load Balancers** for regional HTTP/HTTPS endpoints
- **Multi-region health checking** and automatic failover

## Prerequisites

### AWS Account and Permissions

- AWS account with permissions to create:
  - Global Accelerator accelerators and endpoint groups
  - DynamoDB Global Tables across multiple regions
  - Lambda functions and IAM roles
  - Application Load Balancers and Target Groups
  - VPC resources (if using custom VPCs)

### Required Tools

- **AWS CLI v2** installed and configured with appropriate global permissions
- **Node.js 18+** (for CDK TypeScript)
- **Python 3.9+** (for CDK Python)
- **Terraform 1.5+** (for Terraform deployment)
- **Bash shell** (for script-based deployment)

### Knowledge Prerequisites

- Understanding of multi-region architectures and data consistency models
- Familiarity with Lambda functions, ALB configuration, and DynamoDB operations
- Basic knowledge of DNS and network traffic routing concepts

### Cost Considerations

- **Estimated monthly cost**: $50-100 for basic usage
  - Global Accelerator: $18/month base + data transfer costs
  - Application Load Balancers: $16.20/month per region (3 regions)
  - DynamoDB Global Tables: Pay-per-request + cross-region replication charges
  - Lambda: Minimal costs for low-volume usage

> **Note**: Review [Global Accelerator pricing](https://aws.amazon.com/global-accelerator/pricing/) and [DynamoDB pricing](https://aws.amazon.com/dynamodb/pricing/) for detailed cost information.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete multi-region stack
aws cloudformation create-stack \
    --stack-name global-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=my-global-app \
                ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                ParameterKey=SecondaryRegionEU,ParameterValue=eu-west-1 \
                ParameterKey=SecondaryRegionAsia,ParameterValue=ap-southeast-1 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name global-app-stack \
    --query 'Stacks[0].StackStatus'

# Get Global Accelerator endpoints
aws cloudformation describe-stacks \
    --stack-name global-app-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`GlobalAcceleratorIPs`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK in all target regions (if not already done)
npx cdk bootstrap aws://ACCOUNT-ID/us-east-1
npx cdk bootstrap aws://ACCOUNT-ID/eu-west-1
npx cdk bootstrap aws://ACCOUNT-ID/ap-southeast-1

# Deploy the application
npx cdk deploy --all

# View deployment outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK in all target regions (if not already done)
cdk bootstrap aws://ACCOUNT-ID/us-east-1
cdk bootstrap aws://ACCOUNT-ID/eu-west-1
cdk bootstrap aws://ACCOUNT-ID/ap-southeast-1

# Deploy the application
cdk deploy --all

# View deployment outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="app_name=my-global-app" \
    -var="primary_region=us-east-1" \
    -var="secondary_region_eu=eu-west-1" \
    -var="secondary_region_asia=ap-southeast-1"

# Apply the configuration
terraform apply \
    -var="app_name=my-global-app" \
    -var="primary_region=us-east-1" \
    -var="secondary_region_eu=eu-west-1" \
    -var="secondary_region_asia=ap-southeast-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set execute permissions
chmod +x scripts/deploy.sh scripts/destroy.sh

# Configure environment variables
export APP_NAME="my-global-app"
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION_EU="eu-west-1"
export SECONDARY_REGION_ASIA="ap-southeast-1"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment summary
./scripts/deploy.sh --status
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `app_name` | Application name prefix | `global-app` | No |
| `primary_region` | Primary AWS region | `us-east-1` | No |
| `secondary_region_eu` | EU secondary region | `eu-west-1` | No |
| `secondary_region_asia` | Asia secondary region | `ap-southeast-1` | No |
| `table_name` | DynamoDB table name | `GlobalUserData` | No |
| `accelerator_name` | Global Accelerator name | `GlobalAccelerator` | No |

### Advanced Configuration

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `lambda_timeout` | Lambda function timeout (seconds) | `30` | No |
| `lambda_memory` | Lambda function memory (MB) | `256` | No |
| `health_check_interval` | Health check interval (seconds) | `30` | No |
| `traffic_dial_percentage` | Traffic dial percentage | `100` | No |
| `enable_client_ip_preservation` | Preserve client IP addresses | `false` | No |

## Deployment Validation

### Test Global Accelerator Endpoints

```bash
# Get static IP addresses from deployment outputs
STATIC_IPS="<your-static-ips-from-outputs>"

# Test health endpoints
for IP in $STATIC_IPS; do
    echo "Testing health check via $IP:"
    curl -s "http://$IP/health" | jq .
    echo ""
done
```

### Test Multi-Region Data Consistency

```bash
# Create a test user
USER_ID="test-user-$(date +%s)"
curl -X POST "http://$STATIC_IP/user" \
    -H "Content-Type: application/json" \
    -d "{\"userId\":\"$USER_ID\",\"data\":{\"name\":\"Test User\",\"email\":\"test@example.com\"}}"

# Wait for replication
sleep 5

# Test read consistency across regions
for IP in $STATIC_IPS; do
    echo "Reading from $IP:"
    curl -s "http://$IP/user/$USER_ID" | jq .
done
```

### Monitor Endpoint Health

```bash
# Check Global Accelerator endpoint health
aws globalaccelerator describe-accelerator \
    --accelerator-arn <your-accelerator-arn> \
    --query 'Accelerator.{Name:Name,Status:Status,IpSets:IpSets[0].IpAddresses}'

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/GlobalAccelerator" \
    --metric-name "NewFlowCount" \
    --dimensions Name=Accelerator,Value=<your-accelerator-arn> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name global-app-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name global-app-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy all stacks
npx cdk destroy --all

# Or for Python CDK
cdk destroy --all
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="app_name=my-global-app" \
    -var="primary_region=us-east-1" \
    -var="secondary_region_eu=eu-west-1" \
    -var="secondary_region_asia=ap-southeast-1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

#### Global Accelerator Creation Failed
- Ensure you're creating the accelerator in the `us-west-2` region
- Verify you have the necessary permissions for Global Accelerator
- Check service quotas for accelerators in your account

#### DynamoDB Global Tables Setup Failed
- Verify that DynamoDB Streams are enabled on all tables
- Ensure tables exist in all target regions before creating Global Tables
- Check that table schemas match across all regions

#### Lambda Function Deployment Failed
- Verify IAM role has proper permissions for DynamoDB access
- Check that the deployment package size is within limits
- Ensure the Lambda function runtime is supported in all target regions

#### Application Load Balancer Health Checks Failing
- Verify Lambda functions are responding to health check requests
- Check security group configurations allow traffic
- Ensure target group health check settings are appropriate

### Performance Optimization

#### Reduce Cold Start Latency
```bash
# Enable provisioned concurrency (add to your IaC)
aws lambda put-provisioned-concurrency-config \
    --function-name your-function-name \
    --qualifier '$LATEST' \
    --provisioned-concurrency-config ProvisionedConcurrencyCount=5
```

#### Optimize DynamoDB Performance
```bash
# Enable DynamoDB Accelerator (DAX) for microsecond latency
# Add DAX cluster configuration to your IaC templates
```

### Monitoring and Alerts

#### Set Up CloudWatch Alarms
```bash
# Create alarm for Global Accelerator endpoint health
aws cloudwatch put-metric-alarm \
    --alarm-name "GlobalAccelerator-UnhealthyEndpoints" \
    --alarm-description "Alert when endpoints become unhealthy" \
    --metric-name "ProcessedBytesIn" \
    --namespace "AWS/GlobalAccelerator" \
    --statistic "Sum" \
    --period 300 \
    --threshold 0 \
    --comparison-operator "LessThanThreshold" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws:sns:us-east-1:123456789012:alerts"
```

## Security Considerations

### IAM Best Practices
- Lambda execution roles follow least privilege principle
- Cross-region replication uses service-linked roles
- API access can be secured with Lambda authorizers

### Network Security
- Application Load Balancers support SSL/TLS termination
- Lambda functions run in isolated execution environments
- DynamoDB encryption at rest and in transit enabled by default

### Data Protection
- DynamoDB Global Tables provide built-in encryption
- Lambda environment variables can be encrypted with KMS
- Global Accelerator traffic is encrypted in transit

## Advanced Usage

### Custom Domain Configuration
```bash
# Add custom domain to Application Load Balancers
# Configure Route 53 alias records pointing to Global Accelerator
# Set up ACM certificates for SSL/TLS termination
```

### Blue-Green Deployment
```bash
# Use Global Accelerator traffic dial to implement blue-green deployments
# Gradually shift traffic between endpoint groups
# Monitor metrics during deployment
```

### Disaster Recovery Testing
```bash
# Simulate regional failures by disabling endpoint groups
# Measure failover time and application recovery
# Test data consistency after failover scenarios
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../multi-region-active-active-applications-with-global-accelerator.md)
- [AWS Global Accelerator documentation](https://docs.aws.amazon.com/global-accelerator/)
- [DynamoDB Global Tables documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [Application Load Balancer documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

## Contributing

When contributing to this infrastructure code:
1. Test all changes in a development environment
2. Update documentation for any parameter changes
3. Validate security configurations
4. Ensure compatibility across all IaC implementations
5. Update cost estimates if resource configurations change