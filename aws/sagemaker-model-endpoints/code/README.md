# Infrastructure as Code for SageMaker Model Endpoints for ML Inference

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SageMaker Model Endpoints for ML Inference".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a complete machine learning inference pipeline including:

- **Amazon ECR Repository**: Stores custom inference container images
- **Amazon S3 Bucket**: Hosts trained model artifacts
- **IAM Execution Role**: Provides necessary permissions for SageMaker
- **SageMaker Model**: Combines container image and model artifacts
- **SageMaker Endpoint Configuration**: Defines hosting specifications
- **SageMaker Endpoint**: Provides real-time inference API
- **Auto Scaling Configuration**: Automatically scales based on traffic
- **CloudWatch Monitoring**: Tracks endpoint performance and metrics

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Docker installed (for container building and pushing)
- Python 3.8+ with boto3 and sagemaker SDK
- Trained machine learning model (the deployment includes a sample iris classifier)
- Appropriate AWS permissions for:
  - Amazon SageMaker (full access)
  - Amazon ECR (full access)
  - Amazon S3 (full access)
  - IAM (role creation and policy attachment)
  - Application Auto Scaling
  - CloudWatch

### Required IAM Permissions

Your AWS user/role needs the following minimum permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sagemaker:*",
                "ecr:*",
                "s3:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:GetRole",
                "iam:PassRole",
                "application-autoscaling:*",
                "cloudwatch:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name sagemaker-ml-endpoints \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ModelName,ParameterValue=sklearn-iris-classifier \
        ParameterKey=EndpointName,ParameterValue=iris-prediction-endpoint

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name sagemaker-ml-endpoints \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name sagemaker-ml-endpoints
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
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

# The script will:
# 1. Create ECR repository and build/push container
# 2. Train and package sample model
# 3. Create SageMaker resources
# 4. Configure auto-scaling
# 5. Test the endpoint
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
export AWS_REGION="us-east-1"                    # AWS region
export MODEL_NAME="sklearn-iris-classifier"      # SageMaker model name
export ENDPOINT_NAME="iris-prediction-endpoint"  # Endpoint name
export INSTANCE_TYPE="ml.t2.medium"             # Instance type
export MIN_CAPACITY="1"                         # Minimum instances
export MAX_CAPACITY="5"                         # Maximum instances
export TARGET_INVOCATIONS="70"                  # Target invocations per instance
```

### Customizable Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| ModelName | SageMaker model name | sklearn-iris-classifier | Any valid name |
| EndpointName | Endpoint name | iris-prediction-endpoint | Any valid name |
| InstanceType | EC2 instance type | ml.t2.medium | ml.t2.medium, ml.c5.large, ml.m5.large |
| MinCapacity | Minimum instances | 1 | 1-10 |
| MaxCapacity | Maximum instances | 5 | 2-20 |
| TargetInvocations | Target invocations per instance | 70 | 10-1000 |

## Testing the Deployment

After deployment, test your endpoint:

```bash
# Create test payload
cat > test_payload.json << 'EOF'
{
  "instances": [
    [5.1, 3.5, 1.4, 0.2],
    [6.7, 3.1, 4.4, 1.4],
    [6.3, 3.3, 6.0, 2.5]
  ]
}
EOF

# Test the endpoint
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name iris-prediction-endpoint \
    --content-type application/json \
    --body fileb://test_payload.json \
    prediction_output.json

# View results
cat prediction_output.json | python -m json.tool
```

Expected response:
```json
{
  "predictions": [
    {
      "predicted_class": "setosa",
      "predicted_class_index": 0,
      "probabilities": {
        "setosa": 1.0,
        "versicolor": 0.0,
        "virginica": 0.0
      }
    }
  ]
}
```

## Monitoring and Metrics

### CloudWatch Metrics

Monitor your endpoint performance:

```bash
# View invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/SageMaker \
    --metric-name Invocations \
    --dimensions Name=EndpointName,Value=iris-prediction-endpoint \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# View latency metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/SageMaker \
    --metric-name ModelLatency \
    --dimensions Name=EndpointName,Value=iris-prediction-endpoint \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### Auto Scaling Status

```bash
# Check auto scaling configuration
aws application-autoscaling describe-scalable-targets \
    --service-namespace sagemaker \
    --resource-ids endpoint/iris-prediction-endpoint/variant/primary

# View scaling activities
aws application-autoscaling describe-scaling-activities \
    --service-namespace sagemaker \
    --resource-id endpoint/iris-prediction-endpoint/variant/primary
```

## Cost Optimization

### Instance Selection Guidelines

| Instance Type | vCPUs | Memory | Use Case | Hourly Cost (approx.) |
|---------------|-------|--------|----------|----------------------|
| ml.t2.medium | 2 | 4 GB | Light workloads, testing | $0.065 |
| ml.c5.large | 2 | 4 GB | CPU-intensive models | $0.119 |
| ml.m5.large | 2 | 8 GB | Balanced workloads | $0.134 |
| ml.c5.xlarge | 4 | 8 GB | High-performance CPU | $0.238 |
| ml.p3.2xlarge | 8 | 61 GB | GPU-accelerated models | $4.284 |

### Cost Monitoring

```bash
# Estimate monthly costs (assuming 24/7 operation)
echo "Monthly cost estimate for ml.t2.medium: \$$(echo '0.065 * 24 * 30' | bc) USD"

# Check current endpoint status and instance count
aws sagemaker describe-endpoint \
    --endpoint-name iris-prediction-endpoint \
    --query 'ProductionVariants[0].CurrentInstanceCount'
```

## Troubleshooting

### Common Issues

1. **Endpoint Creation Fails**
   ```bash
   # Check endpoint status
   aws sagemaker describe-endpoint \
       --endpoint-name iris-prediction-endpoint \
       --query 'FailureReason'
   ```

2. **Container Build Issues**
   ```bash
   # Test container locally
   docker run -p 8080:8080 sklearn-iris-classifier:latest
   
   # Test health check
   curl http://localhost:8080/ping
   ```

3. **Model Loading Errors**
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups \
       --log-group-name-prefix /aws/sagemaker/Endpoints/iris-prediction-endpoint
   ```

4. **Auto Scaling Not Working**
   ```bash
   # Verify scaling policies
   aws application-autoscaling describe-scaling-policies \
       --service-namespace sagemaker
   ```

### Debug Mode

Enable debug logging in your inference container by setting environment variables:

```bash
# In your container environment
export SAGEMAKER_PROGRAM=predictor.py
export SAGEMAKER_ENABLE_CLOUDWATCH_METRICS=true
export PYTHONUNBUFFERED=TRUE
```

## Security Considerations

### IAM Best Practices

- Use least privilege principles for the SageMaker execution role
- Enable CloudTrail logging for API calls
- Use VPC endpoints for private communication
- Enable encryption at rest for S3 and ECR

### Network Security

```bash
# Deploy in VPC (add to Terraform/CloudFormation)
# Configure security groups to restrict access
# Use VPC endpoints for SageMaker, S3, and ECR
```

### Data Protection

- Enable S3 bucket encryption
- Use ECR image scanning
- Implement model artifact signing
- Enable CloudWatch Logs encryption

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name sagemaker-ml-endpoints

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name sagemaker-ml-endpoints
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
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

# Confirm deletion when prompted
```

### Manual Cleanup Verification

```bash
# Verify endpoint deletion
aws sagemaker list-endpoints \
    --name-contains iris-prediction

# Verify S3 bucket deletion
aws s3 ls | grep sagemaker-models

# Verify ECR repository deletion
aws ecr describe-repositories \
    --repository-names sagemaker-sklearn-inference
```

## Advanced Usage

### Multi-Model Endpoints

Extend the deployment to support multiple models:

```python
# Example: Add additional models to the same endpoint
endpoint_config = {
    "production_variants": [
        {
            "variant_name": "model-v1",
            "model_name": "iris-classifier-v1",
            "initial_instance_count": 1,
            "instance_type": "ml.t2.medium",
            "initial_variant_weight": 0.8
        },
        {
            "variant_name": "model-v2", 
            "model_name": "iris-classifier-v2",
            "initial_instance_count": 1,
            "instance_type": "ml.t2.medium",
            "initial_variant_weight": 0.2
        }
    ]
}
```

### A/B Testing

Configure traffic splitting between model variants:

```bash
# Update endpoint with traffic distribution
aws sagemaker update-endpoint-weights-and-capacities \
    --endpoint-name iris-prediction-endpoint \
    --desired-weights-and-capacities \
    VariantName=model-v1,DesiredWeight=0.7 \
    VariantName=model-v2,DesiredWeight=0.3
```

### Custom Metrics

Add custom CloudWatch metrics to your inference code:

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def publish_custom_metric(metric_name, value, unit='Count'):
    cloudwatch.put_metric_data(
        Namespace='SageMaker/CustomMetrics',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit,
                'Dimensions': [
                    {
                        'Name': 'EndpointName',
                        'Value': 'iris-prediction-endpoint'
                    }
                ]
            }
        ]
    )
```

## Support and Documentation

- [Amazon SageMaker Developer Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/)
- [SageMaker Inference Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/realtime-endpoints.html)
- [SageMaker Auto Scaling](https://docs.aws.amazon.com/sagemaker/latest/dg/endpoint-auto-scaling.html)
- [Container Image Specifications](https://docs.aws.amazon.com/sagemaker/latest/dg/your-algorithms-inference-code.html)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.