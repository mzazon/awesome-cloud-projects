# Infrastructure as Code for Blue-Green Deployments with VPC Lattice and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blue-Green Deployments with VPC Lattice and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice (create services, target groups, listeners)
  - Lambda (create functions, manage permissions)
  - IAM (create roles, attach policies)
  - CloudWatch (create alarms, view metrics)
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+
- For bash scripts: jq tool for JSON processing

## Architecture Overview

This implementation creates:
- Two Lambda functions (blue and green environments)
- VPC Lattice service network and service
- Target groups for traffic routing
- CloudWatch alarms for monitoring
- IAM roles with appropriate permissions
- Weighted routing configuration for blue-green deployments

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name blue-green-lattice-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name blue-green-lattice-stack \
    --query 'Stacks[0].StackStatus'

# Get service endpoint
aws cloudformation describe-stacks \
    --stack-name blue-green-lattice-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform

```bash
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

# The script will output the service endpoint and deployment status
```

## Testing the Deployment

After deployment, test the blue-green setup:

```bash
# Get the service endpoint (replace with actual endpoint from outputs)
SERVICE_ENDPOINT="your-service-endpoint.vpc-lattice-svcs.us-east-1.on.aws"

# Test traffic distribution
echo "Testing traffic distribution:"
for i in {1..10}; do
    response=$(curl -s "https://${SERVICE_ENDPOINT}" | jq -r '.environment // "unknown"')
    echo "Request $i: $response"
    sleep 1
done
```

## Traffic Management

### Update Traffic Weights

Use AWS CLI to modify traffic distribution:

```bash
# Get listener ARN (replace SERVICE_ID with actual value)
LISTENER_ARN=$(aws vpc-lattice list-listeners \
    --service-identifier YOUR_SERVICE_ID \
    --query "items[0].arn" --output text)

# Shift more traffic to green (e.g., 70% blue, 30% green)
aws vpc-lattice update-listener \
    --service-identifier YOUR_SERVICE_ID \
    --listener-identifier $LISTENER_ARN \
    --default-action '{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "YOUR_BLUE_TG_ARN",
                    "weight": 70
                },
                {
                    "targetGroupIdentifier": "YOUR_GREEN_TG_ARN", 
                    "weight": 30
                }
            ]
        }
    }'
```

### Complete Deployment

Switch all traffic to green environment:

```bash
# Route 100% traffic to green
aws vpc-lattice update-listener \
    --service-identifier YOUR_SERVICE_ID \
    --listener-identifier $LISTENER_ARN \
    --default-action '{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "YOUR_BLUE_TG_ARN",
                    "weight": 0
                },
                {
                    "targetGroupIdentifier": "YOUR_GREEN_TG_ARN",
                    "weight": 100
                }
            ]
        }
    }'
```

### Rollback

Instantly rollback to blue environment if issues are detected:

```bash
# Emergency rollback to blue
aws vpc-lattice update-listener \
    --service-identifier YOUR_SERVICE_ID \
    --listener-identifier $LISTENER_ARN \
    --default-action '{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "YOUR_BLUE_TG_ARN",
                    "weight": 100
                },
                {
                    "targetGroupIdentifier": "YOUR_GREEN_TG_ARN",
                    "weight": 0
                }
            ]
        }
    }'
```

## Monitoring

### CloudWatch Dashboards

View metrics in the AWS Console:
1. Go to CloudWatch → Dashboards
2. Look for the blue-green deployment dashboard
3. Monitor Lambda invocations, errors, and duration

### CloudWatch Alarms

Check alarm status:

```bash
# List all alarms for the deployment
aws cloudwatch describe-alarms \
    --alarm-name-prefix "blue-green-lattice"

# Get alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "your-alarm-name"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name blue-green-lattice-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name blue-green-lattice-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Environment Variables

Common customization options:

- `ENVIRONMENT`: Deployment environment (default: production)
- `AWS_REGION`: Target AWS region (default: us-east-1)
- `LAMBDA_MEMORY_SIZE`: Lambda memory allocation (default: 256MB)
- `LAMBDA_TIMEOUT`: Lambda timeout in seconds (default: 30)
- `INITIAL_BLUE_WEIGHT`: Initial traffic weight for blue environment (default: 90)
- `INITIAL_GREEN_WEIGHT`: Initial traffic weight for green environment (default: 10)

### Lambda Function Updates

To deploy new Lambda code:

1. Update the function code in your deployment
2. Create a new deployment package
3. Update the Lambda function
4. Gradually shift traffic using the traffic management commands above

### Security Considerations

- Lambda functions use least-privilege IAM roles
- VPC Lattice service uses AWS_IAM authentication
- CloudWatch alarms monitor for security events
- All resources are tagged for governance

## Troubleshooting

### Common Issues

1. **Service not accessible**: Check VPC Lattice service network associations
2. **Lambda errors**: Review CloudWatch logs for function errors
3. **Traffic not distributing**: Verify target group health status
4. **Permission errors**: Ensure IAM roles have necessary permissions

### Debug Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name YOUR_FUNCTION_NAME

# Check target group health
aws vpc-lattice list-targets --target-group-identifier YOUR_TG_ARN

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# Check service associations
aws vpc-lattice list-service-network-service-associations \
    --service-network-identifier YOUR_SERVICE_NETWORK_ID
```

## Cost Optimization

- Lambda functions use ARM64 architecture for better price-performance
- VPC Lattice charges based on service hours and data processed
- CloudWatch alarms are configured with appropriate evaluation periods
- Consider using Reserved Capacity for predictable workloads

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS VPC Lattice documentation
3. Consult AWS Lambda best practices guide
4. Review CloudWatch monitoring documentation

## Next Steps

After successful deployment, consider:
1. Implementing automated rollback triggers
2. Adding custom metrics for business KPIs
3. Integrating with CI/CD pipelines
4. Expanding to multi-region deployments
5. Adding database migration strategies