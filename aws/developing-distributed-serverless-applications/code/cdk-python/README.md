# Multi-Region Aurora DSQL CDK Python Application

This CDK Python application deploys a globally distributed serverless application using Aurora DSQL's active-active multi-region architecture with Lambda functions and API Gateway across multiple regions.

## Architecture Overview

The application creates a complete multi-region setup with:

- **Aurora DSQL Clusters**: Active-active clusters in primary and secondary regions with a witness region for enhanced durability
- **Lambda Functions**: Serverless compute functions in each region for database operations
- **API Gateway**: RESTful APIs in each region with regional optimization
- **IAM Roles**: Least-privilege access controls for secure Aurora DSQL connectivity
- **CloudWatch Logs**: Comprehensive logging and monitoring

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk@latest`)
- Appropriate AWS permissions for Aurora DSQL, Lambda, API Gateway, and IAM
- Docker (for Lambda function bundling, if needed)

## Project Structure

```
cdk-python/
├── app.py                 # Main CDK application entry point
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration and context
├── README.md             # This file
├── tests/                # Unit tests (future)
└── cdk.out/             # CDK synthesized templates (generated)
```

## Quick Start

### 1. Environment Setup

```bash
# Clone the repository (if applicable)
git clone <repository-url>
cd multi-region-applications-aurora-dsql/code/cdk-python

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\\Scripts\\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure AWS Environment

```bash
# Set required environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION="us-east-1"

# Optional: Set custom configuration
export UNIQUE_SUFFIX="your-suffix"
```

### 3. Deploy Primary Region

```bash
# Bootstrap CDK (if not already done)
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-east-1

# Deploy primary region stack
cdk deploy MultiRegionAuroraDsql-Primary-dev
```

### 4. Deploy Secondary Region (Optional)

```bash
# Bootstrap secondary region
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-east-2

# Update context to enable secondary deployment
# Edit cdk.json and set "deploy_secondary": true

# Deploy secondary region stack
cdk deploy MultiRegionAuroraDsql-Secondary-dev
```

## Configuration

### CDK Context Variables

The application uses the following context variables (configurable in `cdk.json`):

| Variable | Default | Description |
|----------|---------|-------------|
| `unique_suffix` | `"dev"` | Unique identifier for resource names |
| `primary_region` | `"us-east-1"` | Primary AWS region |
| `secondary_region` | `"us-east-2"` | Secondary AWS region |
| `witness_region` | `"us-west-2"` | Witness region for Aurora DSQL |
| `deploy_secondary` | `false` | Whether to deploy secondary region |

### Customization Options

You can customize the deployment by modifying the context in `cdk.json`:

```json
{
  "context": {
    "unique_suffix": "prod",
    "primary_region": "us-west-2",
    "secondary_region": "eu-west-1",
    "witness_region": "us-east-1",
    "deploy_secondary": true,
    "lambda": {
      "memory_size": 1024,
      "timeout": 60
    }
  }
}
```

## Deployment Commands

### Standard Deployment

```bash
# List all stacks
cdk list

# Synthesize templates (optional)
cdk synth

# Deploy primary region only
cdk deploy MultiRegionAuroraDsql-Primary-dev

# Deploy all stacks (if secondary is enabled)
cdk deploy --all

# Deploy with approval
cdk deploy --require-approval=broadening
```

### Development Workflow

```bash
# Watch for changes and auto-deploy (primary only)
cdk watch MultiRegionAuroraDsql-Primary-dev

# Diff changes before deployment
cdk diff MultiRegionAuroraDsql-Primary-dev

# Show deployed stack outputs
aws cloudformation describe-stacks \
  --stack-name MultiRegionAuroraDsql-Primary-dev \
  --query 'Stacks[0].Outputs'
```

## Testing the Deployment

### Health Check

```bash
# Get API Gateway URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
  --stack-name MultiRegionAuroraDsql-Primary-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text)

# Test health endpoint
curl "${API_URL}health"
```

### User Management

```bash
# Create a user
curl -X POST "${API_URL}users" \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'

# Get all users
curl "${API_URL}users"
```

## Multi-Region Configuration

### Cluster Peering

After deploying both regions, configure cluster peering:

```bash
# Get cluster ARNs
PRIMARY_ARN=$(aws dsql get-cluster \
  --region us-east-1 \
  --cluster-identifier multi-region-app-dev-primary \
  --query 'Cluster.Arn' --output text)

SECONDARY_ARN=$(aws dsql get-cluster \
  --region us-east-2 \
  --cluster-identifier multi-region-app-dev-secondary \
  --query 'Cluster.Arn' --output text)

# Configure peering (primary to secondary)
aws dsql update-cluster \
  --region us-east-1 \
  --cluster-identifier multi-region-app-dev-primary \
  --multi-region-properties "witnessRegion=us-west-2,linkedClusterArns=[${SECONDARY_ARN}]"

# Configure peering (secondary to primary)
aws dsql update-cluster \
  --region us-east-2 \
  --cluster-identifier multi-region-app-dev-secondary \
  --multi-region-properties "witnessRegion=us-west-2,linkedClusterArns=[${PRIMARY_ARN}]"
```

## Monitoring and Observability

### CloudWatch Logs

View Lambda function logs:

```bash
# Primary region logs
aws logs tail /aws/lambda/multi-region-app-dev-us-east-1 --follow

# Secondary region logs
aws logs tail /aws/lambda/multi-region-app-dev-us-east-2 --follow
```

### Metrics and Alarms

The deployment includes CloudWatch metrics for:
- Lambda function duration and errors
- API Gateway request count and latency
- Aurora DSQL connection and query metrics

## Security Considerations

### IAM Permissions

The Lambda functions use minimal IAM permissions:
- `dsql:DbConnect` - Connect to Aurora DSQL clusters
- `dsql:DbConnectAdmin` - Administrative database operations
- Basic Lambda execution permissions

### Network Security

- API Gateway uses regional endpoints
- Aurora DSQL clusters use encryption at rest and in transit
- Lambda functions run in the default VPC with AWS-managed security

### Data Protection

- All database operations use IAM authentication
- Sensitive data is encrypted using AWS KMS
- CloudWatch logs have retention policies

## Troubleshooting

### Common Issues

1. **Aurora DSQL cluster creation fails**
   - Check region availability for Aurora DSQL
   - Verify IAM permissions for `dsql:CreateCluster`

2. **Lambda function timeouts**
   - Increase timeout in `cdk.json` context
   - Check Aurora DSQL cluster status

3. **API Gateway 5xx errors**
   - Check Lambda function logs
   - Verify IAM role permissions

### Debug Commands

```bash
# Check stack status
cdk list

# View detailed error information
cdk deploy --debug

# Check AWS CLI configuration
aws sts get-caller-identity
aws configure list
```

## Cleanup

### Destroy Resources

```bash
# Destroy secondary region (if deployed)
cdk destroy MultiRegionAuroraDsql-Secondary-dev

# Destroy primary region
cdk destroy MultiRegionAuroraDsql-Primary-dev

# Clean up CDK bootstrap (optional)
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Delete Aurora DSQL clusters (if deletion protection is enabled)
aws dsql update-cluster \
  --region us-east-1 \
  --cluster-identifier multi-region-app-dev-primary \
  --no-deletion-protection

aws dsql delete-cluster \
  --region us-east-1 \
  --cluster-identifier multi-region-app-dev-primary
```

## Cost Optimization

### Resource Costs

Estimated monthly costs (moderate usage):
- Aurora DSQL: $50-100 (pay-per-use)
- Lambda: $10-20 (1M requests)
- API Gateway: $10-15 (1M requests)
- CloudWatch Logs: $5-10

### Cost Reduction Tips

1. Use smaller Lambda memory sizes for simple operations
2. Implement API Gateway caching
3. Set appropriate log retention periods
4. Monitor and optimize Aurora DSQL usage patterns

## Development

### Code Quality

```bash
# Run linting
flake8 . --exclude=cdk.out

# Run type checking
mypy . --ignore-missing-imports

# Format code
black .

# Sort imports
isort .
```

### Testing

```bash
# Run unit tests (when implemented)
pytest tests/ -v

# Run security scans
bandit -r . -x cdk.out
```

## Support

For issues and questions:

1. Check AWS Aurora DSQL documentation
2. Review CloudWatch logs for error details
3. Consult AWS CDK documentation
4. Check the original recipe documentation

## License

This project is licensed under the Apache License 2.0. See the original recipe for more details.