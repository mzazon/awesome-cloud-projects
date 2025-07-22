# Cost-Optimized Batch Processing with AWS Batch and Spot Instances - CDK Python

This CDK Python application creates a complete infrastructure for cost-optimized batch processing using AWS Batch with EC2 Spot Instances. It provides up to 90% cost savings compared to On-Demand instances while maintaining reliability through intelligent retry strategies and fault tolerance mechanisms.

## Architecture

The solution deploys the following components:

- **VPC**: Custom VPC with public and private subnets across multiple AZs
- **ECR Repository**: Container registry for batch application images
- **IAM Roles**: Least privilege roles for Batch service, EC2 instances, and job execution
- **Security Groups**: Network security for batch instances
- **AWS Batch**: Compute environment, job queue, and job definition
- **CloudWatch**: Log group for job monitoring
- **S3 Bucket**: Storage for job artifacts with lifecycle policies

## Features

### Cost Optimization
- **Spot Instance Allocation**: Uses `SPOT_CAPACITY_OPTIMIZED` strategy
- **Mixed Instance Types**: Supports multiple instance families (c5, m5, r5)
- **Intelligent Scaling**: Scales from 0 to 256 vCPUs based on demand
- **Bid Percentage**: Maximum 80% of On-Demand pricing
- **Lifecycle Policies**: Automatic cleanup of old resources

### Fault Tolerance
- **Retry Strategy**: Automatic retry for Spot interruptions
- **Multiple AZs**: Deployment across multiple availability zones
- **Health Checks**: Container health monitoring
- **Error Handling**: Graceful handling of instance terminations

### Security
- **IAM Roles**: Least privilege access patterns
- **VPC Isolation**: Private subnets for compute resources
- **Security Groups**: Network-level access control
- **Encryption**: S3 bucket encryption at rest

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **Python 3.8+**: Required for CDK Python applications
3. **AWS CDK**: Installed globally (`npm install -g aws-cdk`)
4. **Docker**: For building and pushing container images
5. **Permissions**: AWS account with permissions to create all required resources

## Installation

1. **Clone the repository** (if not already done):
   ```bash
   git clone <repository-url>
   cd cost-optimized-batch-processing-aws-batch-spot-instances/code/cdk-python
   ```

2. **Create a virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Deployment

### 1. Bootstrap CDK (first time only)

```bash
cdk bootstrap
```

### 2. Customize Configuration

Edit the `cdk.json` file to customize:
- AWS account ID and region
- Stack tags
- Context variables

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Deploy with automatic approval
cdk deploy --require-approval never
```

### 4. Verify Deployment

After deployment, you'll see outputs including:
- ECR Repository URI
- Job Queue Name
- Job Definition Name
- Compute Environment Name
- S3 Bucket Name
- CloudWatch Log Group

## Usage

### 1. Build and Push Container Image

```bash
# Get ECR repository URI from CDK outputs
ECR_URI=$(aws cloudformation describe-stacks \
  --stack-name CostOptimizedBatchProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
  --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URI

# Build and push your batch application
docker build -t batch-app .
docker tag batch-app:latest $ECR_URI:latest
docker push $ECR_URI:latest
```

### 2. Submit Batch Jobs

```bash
# Submit a test job
aws batch submit-job \
  --job-name test-job-$(date +%s) \
  --job-queue CostOptimizedBatchProcessingStack-job-queue \
  --job-definition CostOptimizedBatchProcessingStack-job-definition
```

### 3. Monitor Jobs

```bash
# List jobs
aws batch list-jobs --job-queue CostOptimizedBatchProcessingStack-job-queue

# Describe job
aws batch describe-jobs --jobs <job-id>

# View logs
aws logs tail /aws/batch/CostOptimizedBatchProcessingStack --follow
```

## Customization

### Instance Types

Modify the `instance_types` list in `app.py` to use different instance families:

```python
instance_types=[
    "c5.large", "c5.xlarge", "c5.2xlarge",
    "m5.large", "m5.xlarge", "m5.2xlarge",
    "r5.large", "r5.xlarge", "r5.2xlarge",
    # Add more instance types as needed
]
```

### Scaling Configuration

Adjust the compute environment scaling parameters:

```python
min_v_cpus=0,        # Minimum vCPUs (0 for cost optimization)
max_v_cpus=256,      # Maximum vCPUs
desired_v_cpus=0,    # Desired vCPUs (0 for auto-scaling)
```

### Bid Percentage

Change the maximum Spot price bid:

```python
bid_percentage=80,  # Maximum 80% of On-Demand price
```

### Retry Strategy

Customize the retry behavior:

```python
retry_strategy=batch.CfnJobDefinition.RetryStrategyProperty(
    attempts=3,  # Number of retry attempts
    # Add more retry conditions as needed
)
```

## Cost Optimization Tips

1. **Use Mixed Instance Types**: Diversify across multiple instance families
2. **Monitor Spot Prices**: Choose regions with lower Spot prices
3. **Implement Checkpointing**: Save progress to resume interrupted jobs
4. **Optimize Container Images**: Use lightweight base images
5. **Use S3 Lifecycle Policies**: Automatically archive old job artifacts
6. **Monitor Usage**: Set up CloudWatch alarms for cost monitoring

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics:
- `AWS/Batch/SubmittedJobs`
- `AWS/Batch/RunnableJobs`
- `AWS/Batch/RunningJobs`
- `AWS/EC2/SpotFleetRequestConfig`

### Common Issues

1. **Jobs Stuck in RUNNABLE**: Check compute environment capacity
2. **Spot Interruptions**: Implement checkpointing and retry logic
3. **Container Pull Errors**: Verify ECR permissions and image existence
4. **Network Issues**: Check VPC configuration and security groups

### Logs

Access logs through:
- CloudWatch Logs: `/aws/batch/CostOptimizedBatchProcessingStack`
- ECS Console: Container instance logs
- AWS Batch Console: Job execution logs

## Security Best Practices

1. **IAM Roles**: Use least privilege principles
2. **VPC Configuration**: Deploy in private subnets
3. **Security Groups**: Restrict network access
4. **Encryption**: Enable S3 bucket encryption
5. **Access Logging**: Enable CloudTrail for API calls
6. **Secrets Management**: Use AWS Secrets Manager for sensitive data

## Cleanup

To avoid ongoing charges, clean up resources:

```bash
# Delete all jobs (if running)
aws batch cancel-job --job-id <job-id> --reason "Cleanup"

# Destroy the stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

## Development

### Running Tests

```bash
# Install test dependencies
pip install pytest pytest-cov

# Run tests
pytest tests/

# Run with coverage
pytest --cov=app tests/
```

### Code Quality

```bash
# Format code
black app.py

# Sort imports
isort app.py

# Lint code
flake8 app.py

# Type checking
mypy app.py
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

This code is provided under the Apache 2.0 License. See the LICENSE file for details.

## Support

For issues and questions:
- AWS CDK Documentation: https://docs.aws.amazon.com/cdk/
- AWS Batch Documentation: https://docs.aws.amazon.com/batch/
- AWS Forums: https://forums.aws.amazon.com/