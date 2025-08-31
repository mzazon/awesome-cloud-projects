# Infrastructure as Code for Canary Deployments with VPC Lattice and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Canary Deployments with VPC Lattice and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a progressive canary deployment system using:

- **VPC Lattice Service Network**: Provides service mesh connectivity
- **VPC Lattice Service**: Manages traffic routing with weighted distribution
- **Lambda Functions**: Two versions (production v1 and canary v2)
- **Target Groups**: Separate groups for production and canary traffic
- **CloudWatch Monitoring**: Alarms and metrics for deployment health
- **Automatic Rollback**: Lambda function for emergency traffic reversion

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice (full access)
  - Lambda (full access)
  - IAM (role creation and policy attachment)
  - CloudWatch (metrics and alarms)
  - SNS (topic creation)
- Basic understanding of canary deployment patterns
- Estimated cost: $5-15 for testing (Lambda invocations, VPC Lattice processing, CloudWatch monitoring)

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete canary deployment infrastructure
aws cloudformation create-stack \
    --stack-name canary-deployments-lattice-lambda \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ServiceName,ParameterValue=my-canary-service \
                ParameterKey=InitialCanaryWeight,ParameterValue=10

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name canary-deployments-lattice-lambda \
    --query 'Stacks[0].StackStatus'

# Get service endpoint for testing
aws cloudformation describe-stacks \
    --stack-name canary-deployments-lattice-lambda \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
# Set up Python environment and deploy
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
# Initialize and deploy with Terraform
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable and deploy
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the service endpoint and testing instructions
```

## Testing the Canary Deployment

After deployment, test the traffic distribution:

```bash
# Get the service endpoint (replace with your actual endpoint)
SERVICE_ENDPOINT="your-service-endpoint-here"

# Test traffic distribution
echo "Testing traffic distribution..."
v1_count=0
v2_count=0

for i in {1..50}; do
    response=$(curl -s "https://${SERVICE_ENDPOINT}")
    if echo "$response" | grep -q '"version": "v1.0.0"'; then
        ((v1_count++))
    elif echo "$response" | grep -q '"version": "v2.0.0"'; then
        ((v2_count++))
    fi
done

echo "V1 (Production) requests: $v1_count"
echo "V2 (Canary) requests: $v2_count"
echo "Distribution: $(($v1_count * 100 / 50))% / $(($v2_count * 100 / 50))%"
```

## Progressive Traffic Shifting

Update traffic weights to progress the canary deployment:

### CloudFormation
```bash
# Shift to 50/50 traffic split
aws cloudformation update-stack \
    --stack-name canary-deployments-lattice-lambda \
    --use-previous-template \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ServiceName,UsePreviousValue=true \
                ParameterKey=InitialCanaryWeight,ParameterValue=50
```

### CDK
```bash
# Update the canary weight in your CDK code and redeploy
cdk deploy
```

### Terraform
```bash
# Update the canary_weight variable
terraform apply -var="canary_weight=50"
```

## Monitoring and Rollback

### View CloudWatch Metrics

```bash
# Check Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=canary-demo-function-* \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check alarm states
aws cloudwatch describe-alarms \
    --alarm-name-prefix "canary-lambda"
```

### Manual Rollback

If issues are detected, immediately rollback to 100% production:

```bash
# CloudFormation rollback
aws cloudformation update-stack \
    --stack-name canary-deployments-lattice-lambda \
    --use-previous-template \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ServiceName,UsePreviousValue=true \
                ParameterKey=InitialCanaryWeight,ParameterValue=0

# Terraform rollback
terraform apply -var="canary_weight=0"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the complete stack and all resources
aws cloudformation delete-stack \
    --stack-name canary-deployments-lattice-lambda

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name canary-deployments-lattice-lambda \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Destroy all Terraform-managed resources
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### CloudFormation Parameters

- `ServiceName`: Name for the VPC Lattice service (default: canary-demo-service)
- `InitialCanaryWeight`: Initial traffic percentage for canary (0-100, default: 10)
- `FunctionMemorySize`: Lambda function memory in MB (default: 256)
- `AlarmErrorThreshold`: Error count threshold for alarms (default: 5)

### CDK Configuration

Modify the CDK app files to customize:

- Lambda function configuration (memory, timeout, runtime)
- VPC Lattice service settings
- CloudWatch alarm thresholds
- Traffic distribution weights

### Terraform Variables

Available variables in `terraform/variables.tf`:

- `service_name`: VPC Lattice service name
- `canary_weight`: Canary traffic percentage (0-100)
- `lambda_memory_size`: Lambda memory allocation
- `lambda_timeout`: Lambda timeout in seconds
- `alarm_error_threshold`: CloudWatch alarm error threshold

### Bash Script Environment Variables

Set these variables before running scripts:

```bash
export SERVICE_NAME="my-custom-service"
export CANARY_WEIGHT="20"
export LAMBDA_MEMORY="512"
export AWS_REGION="us-west-2"
```

## Advanced Configuration

### Custom Lambda Code

Replace the default Lambda function code by:

1. Updating the Lambda deployment packages in your IaC
2. Modifying the function configurations
3. Redeploying the infrastructure

### Additional Monitoring

Extend monitoring by adding:

- Custom CloudWatch metrics from Lambda functions
- Additional alarm conditions
- SNS notifications for deployment events
- Dashboard creation for visual monitoring

### Multi-Region Deployment

For multi-region canary deployments:

1. Deploy the infrastructure in multiple regions
2. Use Route 53 for DNS-based traffic distribution
3. Implement cross-region monitoring and rollback

## Troubleshooting

### Common Issues

1. **VPC Lattice Service Creation Fails**
   - Verify VPC Lattice is available in your region
   - Check IAM permissions for VPC Lattice operations

2. **Lambda Function Registration Fails**
   - Ensure Lambda functions are in ACTIVE state
   - Verify IAM role has VPC Lattice invoke permissions

3. **Traffic Distribution Not Working**
   - Check VPC Lattice listener rules configuration
   - Verify target group health status

4. **CloudWatch Alarms Not Triggering**
   - Verify alarm thresholds are appropriate
   - Check that Lambda functions are generating metrics

### Debug Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice describe-service --service-identifier <service-id>

# List target group targets and health
aws vpc-lattice list-targets --target-group-identifier <target-group-id>

# View Lambda function versions
aws lambda list-versions-by-function --function-name <function-name>

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda execution roles have minimal required permissions
- **Network Security**: VPC Lattice provides secure service-to-service communication
- **Encryption**: All data in transit is encrypted by default
- **Monitoring**: Comprehensive CloudWatch logging and monitoring
- **Access Control**: VPC Lattice auth policies can be customized for access control

## Cost Optimization

- **Lambda**: Pay only for invocations and execution time
- **VPC Lattice**: Charges based on requests processed and data transferred
- **CloudWatch**: Charges for metrics, alarms, and log storage
- **Estimated Monthly Cost**: $10-50 for moderate traffic (10,000 requests/month)

## Performance Considerations

- **Cold Starts**: Lambda functions may experience cold start latency
- **VPC Lattice Latency**: Adds minimal latency (typically <1ms)
- **Traffic Distribution**: Changes take effect within seconds
- **Scaling**: Automatic scaling based on traffic patterns

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS VPC Lattice documentation
3. Consult AWS Lambda best practices
4. Review CloudWatch monitoring guides

## Additional Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Canary Deployment Best Practices](https://docs.aws.amazon.com/whitepapers/latest/overview-deployment-options/canary-deployments.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)