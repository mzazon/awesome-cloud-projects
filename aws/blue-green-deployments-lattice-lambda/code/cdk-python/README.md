# Blue-Green Deployments with VPC Lattice and Lambda - CDK Python

This directory contains a complete AWS CDK Python application for implementing blue-green deployments using VPC Lattice and Lambda functions. The solution provides zero-downtime deployment capabilities with automated traffic shifting and monitoring.

## Architecture Overview

The CDK application creates:

- **VPC Lattice Service Network**: Application networking foundation
- **Lambda Functions**: Blue and green environment compute
- **Target Groups**: Health checking and request routing
- **Weighted Routing**: Traffic distribution control
- **CloudWatch Monitoring**: Performance and error tracking
- **IAM Roles**: Least privilege security

## Prerequisites

- Python 3.9 or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for VPC Lattice, Lambda, CloudWatch, and IAM

## Installation

1. **Clone and Navigate**:
   ```bash
   cd aws/blue-green-deployments-lattice-lambda/code/cdk-python/
   ```

2. **Create Virtual Environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Deployment

### Quick Start

Deploy with default settings (90% blue, 10% green):

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy
```

### Custom Configuration

Deploy with custom traffic weights and versions:

```bash
# Deploy with custom weights
cdk deploy -c blue_weight=70 -c green_weight=30

# Deploy with custom versions
cdk deploy -c blue_version=1.5.0 -c green_version=2.1.0

# Deploy to different environment
cdk deploy -c environment=staging
```

### Configuration Options

The application supports the following context parameters:

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `environment` | Deployment environment | `production` | `staging` |
| `blue_version` | Blue environment version | `1.0.0` | `1.5.0` |
| `green_version` | Green environment version | `2.0.0` | `2.1.0` |
| `blue_weight` | Blue traffic percentage | `90` | `70` |
| `green_weight` | Green traffic percentage | `10` | `30` |

## Traffic Management

### Viewing Current Configuration

```bash
# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name BlueGreenLatticeStack \
    --query 'Stacks[0].Outputs'

# Check service endpoint
aws vpc-lattice get-service \
    --service-identifier <SERVICE_ID>
```

### Testing Traffic Distribution

```bash
# Get service domain name from outputs
SERVICE_DOMAIN=$(aws cloudformation describe-stacks \
    --stack-name BlueGreenLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceDomainName`].OutputValue' \
    --output text)

# Test multiple requests
for i in {1..10}; do
    curl -s "https://${SERVICE_DOMAIN}" | jq -r '.environment'
done
```

### Updating Traffic Weights

To update traffic distribution, use the AWS CLI to modify the listener:

```bash
# Get resources
SERVICE_ID=$(aws cloudformation describe-stacks \
    --stack-name BlueGreenLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LatticeServiceId`].OutputValue' \
    --output text)

BLUE_TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name BlueGreenLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`BlueTargetGroupArn`].OutputValue' \
    --output text)

GREEN_TG_ARN=$(aws cloudformation describe-stacks \
    --stack-name BlueGreenLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`GreenTargetGroupArn`].OutputValue' \
    --output text)

# Get listener ARN
LISTENER_ARN=$(aws vpc-lattice list-listeners \
    --service-identifier ${SERVICE_ID} \
    --query 'items[0].arn' --output text)

# Update weights (example: 50/50 split)
aws vpc-lattice update-listener \
    --service-identifier ${SERVICE_ID} \
    --listener-identifier ${LISTENER_ARN} \
    --default-action '{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "'${BLUE_TG_ARN}'",
                    "weight": 50
                },
                {
                    "targetGroupIdentifier": "'${GREEN_TG_ARN}'", 
                    "weight": 50
                }
            ]
        }
    }'
```

## Monitoring

### CloudWatch Dashboards

The application creates CloudWatch alarms for:

- **Green Environment Error Rate**: Monitors Lambda errors
- **Green Environment Duration**: Monitors response times
- **Blue Environment Error Rate**: Baseline monitoring

### Viewing Metrics

```bash
# View Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=ecommerce-blue-production \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check alarm status
aws cloudwatch describe-alarms \
    --alarm-names "ecommerce-green-production-ErrorRate"
```

## Development

### Code Structure

```
.
├── app.py                  # Main CDK application
├── requirements.txt        # Python dependencies  
├── setup.py               # Package configuration
├── cdk.json               # CDK configuration
├── README.md              # This file
└── tests/                 # Unit tests (future)
```

### Adding Features

To extend the application:

1. **Add New Constructs**: Modify the `BlueGreenLatticeStack` class
2. **Update Configuration**: Add new context parameters in `cdk.json`
3. **Test Changes**: Use `cdk diff` to preview changes
4. **Apply Updates**: Deploy with `cdk deploy`

### Best Practices

- Always run `cdk synth` before deployment
- Use context parameters for environment-specific configuration
- Monitor CloudWatch alarms after deployment changes
- Test traffic distribution after weight updates
- Implement gradual rollouts (10% → 25% → 50% → 100%)

## Cleanup

Remove all resources:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure proper AWS credentials
   aws sts get-caller-identity
   ```

2. **VPC Lattice Not Available**:
   ```bash
   # Check region support
   aws vpc-lattice describe-service-networks --region us-east-1
   ```

3. **Lambda Function Errors**:
   ```bash
   # View function logs
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/ecommerce
   ```

### Useful Commands

- `cdk ls` - List all stacks
- `cdk synth` - Synthesize CloudFormation template
- `cdk deploy` - Deploy the stack
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove the stack

## Security Considerations

- IAM roles follow least privilege principle
- Lambda functions have appropriate execution permissions
- VPC Lattice uses AWS IAM authentication
- CloudWatch logs are encrypted by default
- All resources are tagged for governance

## Cost Optimization

- Lambda functions use ARM64 architecture when possible
- Memory allocation optimized for workload requirements
- CloudWatch log retention set to 1 week by default
- VPC Lattice charges based on data processing units

## Support

For issues with this CDK application:

1. Check CloudFormation events in AWS Console
2. Review CloudWatch logs for Lambda functions
3. Validate IAM permissions
4. Consult AWS CDK documentation

## License

MIT License - see the original recipe documentation for details.