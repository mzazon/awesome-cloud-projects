# AWS CDK Python - Batch Processing Workloads

This directory contains a production-ready AWS CDK Python application that creates a complete AWS Batch infrastructure for processing large-scale batch workloads with automatic scaling and cost optimization.

## Architecture Overview

The CDK application creates:

- **ECR Repository**: Container registry for storing batch processing images with vulnerability scanning
- **VPC & Networking**: Isolated network environment with public/private subnets and VPC endpoints
- **AWS Batch Components**:
  - Managed compute environment with EC2 and Spot instances (50% Spot for cost optimization)
  - Job queue for managing job submissions with priority-based scheduling
  - Job definition template for containerized workloads
- **IAM Roles**: Service and instance roles with least-privilege permissions
- **Monitoring**: CloudWatch log groups and alarms for operational visibility
- **Security**: CDK Nag integration for security best practices validation

## Prerequisites

- Python 3.9+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Docker (for building and pushing container images)

## Getting Started

### 1. Environment Setup

```bash
# Create and activate Python virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (one-time per account/region)
cdk bootstrap
```

### 2. Deploy the Infrastructure

```bash
# Synthesize CloudFormation template (recommended first step)
cdk synth

# Deploy the stack
cdk deploy

# Or deploy with auto-approval (for automation)
cdk deploy --require-approval never
```

### 3. Verify Deployment

After deployment, the CDK will output important resource identifiers:

- ECR Repository URI
- Compute Environment Name
- Job Queue Name
- Job Definition ARN
- CloudWatch Log Group Name

## Configuration

The stack can be customized through context values in `cdk.json` or command line:

```bash
# Deploy with custom settings
cdk deploy -c max_vcpus=200 -c environment_name=production-batch
```

Available configuration options:

- `max_vcpus`: Maximum vCPUs for compute environment (default: 100)
- `spot_bid_percentage`: Percentage for Spot instances (default: 50)
- `environment_name`: Prefix for resource names (default: "batch-processing")
- `vpc_id`: Use existing VPC (optional)
- `subnet_ids`: Use existing subnets (optional)

## Using the Infrastructure

### Building and Pushing Container Images

```bash
# Get ECR login token
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ECR_REPOSITORY_URI>

# Build and tag your container
docker build -t my-batch-app .
docker tag my-batch-app:latest <ECR_REPOSITORY_URI>:latest

# Push to ECR
docker push <ECR_REPOSITORY_URI>:latest
```

### Submitting Jobs

```bash
# Submit a batch job
aws batch submit-job \
    --job-name my-processing-job \
    --job-queue <JOB_QUEUE_NAME> \
    --job-definition <JOB_DEFINITION_NAME> \
    --parameters DATA_SIZE=1000,PROCESSING_TIME=60
```

### Monitoring Jobs

```bash
# List jobs in queue
aws batch list-jobs --job-queue <JOB_QUEUE_NAME>

# Get job details
aws batch describe-jobs --jobs <JOB_ID>

# View job logs
aws logs get-log-events \
    --log-group-name /aws/batch/job \
    --log-stream-name <LOG_STREAM_NAME>
```

## Development

### Code Quality

The project includes comprehensive tooling for code quality:

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run type checking
mypy app.py

# Format code
black app.py

# Lint code
pylint app.py

# Security scanning
bandit -r .

# Install pre-commit hooks
pre-commit install
```

### Testing

```bash
# Install test dependencies
pip install -e ".[test]"

# Run tests
pytest tests/ -v --cov=.

# Run specific test
pytest tests/test_batch_stack.py::TestBatchStack::test_creates_ecr_repository
```

### CDK Nag Security Validation

This application includes CDK Nag for security best practices validation:

```bash
# CDK Nag runs automatically during synth/deploy
# To see detailed security findings:
cdk synth --verbose
```

## Cost Optimization

The infrastructure is optimized for cost:

- **Spot Instances**: 50% Spot instances in compute environment for up to 90% savings
- **Auto Scaling**: Compute environment scales from 0 to max capacity based on demand
- **VPC Endpoints**: Reduces NAT gateway costs for ECR access
- **Log Retention**: CloudWatch logs retained for 30 days to manage storage costs
- **ECR Lifecycle**: Keeps only 10 most recent container images

## Security Features

- **Least Privilege IAM**: Roles follow principle of least privilege
- **Network Isolation**: Resources deployed in private subnets
- **Container Scanning**: ECR vulnerability scanning enabled
- **CDK Nag Integration**: Automated security best practices validation
- **Encryption**: Data encrypted at rest and in transit where applicable

## Troubleshooting

### Common Issues

1. **Compute Environment Stuck in INVALID State**:
   ```bash
   # Check IAM roles have proper permissions
   aws iam get-role --role-name <BATCH_SERVICE_ROLE_NAME>
   ```

2. **Jobs Stuck in RUNNABLE State**:
   ```bash
   # Check compute environment capacity
   aws batch describe-compute-environments --compute-environments <COMPUTE_ENV_NAME>
   ```

3. **Container Pull Errors**:
   ```bash
   # Verify ECR permissions and image exists
   aws ecr describe-images --repository-name <REPO_NAME>
   ```

### Debugging

Enable verbose logging:

```bash
# Deploy with debug logging
export CDK_DEBUG=true
cdk deploy --verbose
```

Check CloudWatch logs:
- Batch job logs: `/aws/batch/job`
- CloudFormation events: AWS Console > CloudFormation > Events

## Cleanup

```bash
# Destroy all resources
cdk destroy

# Force destroy (skip confirmation)
cdk destroy --force
```

**Warning**: This will delete all batch jobs, compute environments, and associated data.

## Advanced Usage

### Multi-Queue Setup

For different workload priorities, deploy multiple stacks:

```bash
# High priority queue
cdk deploy -c environment_name=high-priority -c max_vcpus=200

# Low priority queue  
cdk deploy -c environment_name=low-priority -c max_vcpus=50 -c spot_bid_percentage=90
```

### Cross-Region Deployment

```bash
# Deploy to different region
cdk deploy --profile production --region eu-west-1
```

### Integration with CI/CD

```yaml
# Example GitHub Actions workflow
- name: Deploy CDK
  run: |
    pip install -r requirements.txt
    cdk deploy --require-approval never
  env:
    AWS_DEFAULT_REGION: us-east-1
```

## Support

For issues and questions:

1. Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. AWS Batch documentation: https://docs.aws.amazon.com/batch/
3. CDK GitHub issues: https://github.com/aws/aws-cdk/issues

## License

This project is licensed under the MIT License - see the LICENSE file for details.