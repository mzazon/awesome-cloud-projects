# Infrastructure as Code for SageMaker AutoML for Time Series Forecasting

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SageMaker AutoML for Time Series Forecasting".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon SageMaker (full access)
  - Amazon S3 (full access)
  - AWS IAM (role creation and management)
  - AWS Lambda (function creation and execution)
  - Amazon CloudWatch (dashboard and alarm management)
- Python 3.9+ for data preparation and model evaluation
- Estimated cost: $75-200 for full training cycle and 48-hour inference testing

> **Note**: Amazon Forecast was deprecated in July 2024. This recipe uses SageMaker AutoML for time series forecasting, which offers superior performance and cost efficiency.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name automl-forecasting-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name automl-forecasting-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name automl-forecasting-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
# Navigate to Terraform directory
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

# View deployment status
./scripts/status.sh
```

## Architecture Overview

The infrastructure deploys a comprehensive forecasting solution including:

### Core Components
- **S3 Bucket**: Secure data lake with versioning and encryption
- **SageMaker AutoML Job**: Automated model training and evaluation
- **SageMaker Endpoint**: Real-time inference endpoint
- **IAM Role**: Service execution role with least privilege permissions

### Monitoring & Operations
- **CloudWatch Dashboard**: Real-time monitoring of model performance
- **CloudWatch Alarms**: Automated alerting for error rates and latency
- **Lambda Function**: Serverless API for real-time forecasting

### Data Processing
- **Training Data Generation**: Synthetic e-commerce dataset with seasonality
- **Model Registry**: Version control and governance for ML models
- **Batch Processing**: Large-scale forecasting pipeline

## Configuration

### Environment Variables
Each implementation supports these key configuration parameters:

- `Environment`: Deployment environment (dev, test, prod)
- `ForecastBucketName`: S3 bucket for data and model artifacts
- `AutoMLJobName`: Unique identifier for the AutoML training job
- `EndpointInstanceType`: SageMaker endpoint instance type (default: ml.m5.large)
- `ForecastHorizon`: Number of days to forecast (default: 14)

### CloudFormation Parameters
```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, test, prod]
  
  ForecastHorizon:
    Type: Number
    Default: 14
    MinValue: 1
    MaxValue: 365
```

### Terraform Variables
```hcl
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "forecast_horizon" {
  description = "Number of days to forecast"
  type        = number
  default     = 14
  
  validation {
    condition     = var.forecast_horizon >= 1 && var.forecast_horizon <= 365
    error_message = "Forecast horizon must be between 1 and 365 days."
  }
}
```

## Deployment Process

### Step 1: Data Preparation
The infrastructure automatically generates a comprehensive training dataset including:
- 3 years of historical sales data
- Multiple product categories with different seasonality patterns
- Promotional effects and holiday impacts
- Regional variations and external factors

### Step 2: AutoML Training
The SageMaker AutoML job evaluates multiple algorithms:
- CNN-QR (Convolutional Neural Network Quantile Regression)
- DeepAR (Deep Autoregressive Forecasting)
- Prophet (Facebook's forecasting algorithm)
- NPTS (Neural Prediction Time Series)
- ARIMA (Autoregressive Integrated Moving Average)
- ETS (Exponential Smoothing)

### Step 3: Model Deployment
The best performing model is automatically deployed to a real-time endpoint with:
- Auto-scaling based on traffic
- CloudWatch monitoring and alerting
- Model version control and governance

### Step 4: API Integration
A Lambda function provides a REST API for real-time forecasting with:
- Input validation and error handling
- Standardized JSON response format
- Integration with business systems

## Monitoring and Alerts

### CloudWatch Metrics
- Endpoint invocations and error rates
- Model latency and throughput
- Training job progress and completion status

### Automated Alerts
- High error rate notifications
- Endpoint health monitoring
- Cost anomaly detection

### Performance Dashboards
- Real-time forecast accuracy metrics
- Business intelligence integration
- Model performance over time

## Security Features

### Data Protection
- S3 bucket encryption at rest (AES-256)
- VPC endpoints for secure service communication
- IAM roles with least privilege access

### Model Security
- SageMaker endpoint encryption in transit
- Model registry with access controls
- Audit logging for model deployments

### API Security
- Lambda function with execution role
- API Gateway integration (optional)
- Request validation and rate limiting

## Cost Optimization

### Resource Management
- Automatic endpoint scaling based on usage
- Spot instances for training jobs (where applicable)
- S3 intelligent tiering for data storage

### Budget Controls
- CloudWatch billing alarms
- Resource tagging for cost allocation
- Automated cleanup of temporary resources

## Troubleshooting

### Common Issues

**AutoML Job Fails**
```bash
# Check job status and failure reason
aws sagemaker describe-auto-ml-job-v2 \
    --auto-ml-job-name <job-name> \
    --query '{Status: AutoMLJobStatus, FailureReason: FailureReason}'
```

**Endpoint Creation Fails**
```bash
# Check endpoint status
aws sagemaker describe-endpoint \
    --endpoint-name <endpoint-name> \
    --query '{Status: EndpointStatus, FailureReason: FailureReason}'
```

**Lambda Function Errors**
```bash
# View function logs
aws logs tail /aws/lambda/<function-name> --follow
```

### Performance Optimization

**Improve Forecast Accuracy**
- Increase training data volume and quality
- Add more relevant features (weather, economic indicators)
- Experiment with different forecast horizons
- Implement ensemble methods with multiple models

**Reduce Latency**
- Use faster instance types for endpoints
- Implement caching for frequent requests
- Optimize data preprocessing pipelines
- Consider batch processing for large requests

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name automl-forecasting-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name automl-forecasting-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
./scripts/verify-cleanup.sh
```

## Advanced Features

### Model Governance
- Automated model versioning in SageMaker Model Registry
- Performance tracking across model versions
- Rollback capabilities for production deployments
- Compliance audit trails

### Business Intelligence Integration
- Automated forecast summary reports
- Integration with popular BI tools
- Custom dashboard creation
- Actionable business insights

### Batch Processing
- Large-scale forecasting for enterprise catalogs
- Parallel processing for improved performance
- Automated result distribution
- Integration with business workflows

## Support and Resources

### Documentation
- [Amazon SageMaker AutoML Developer Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-automate-model-development.html)
- [SageMaker Time Series Forecasting](https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-timeseries-forecasting.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Best Practices
- [AWS Well-Architected Machine Learning Lens](https://docs.aws.amazon.com/wellarchitected/latest/machine-learning-lens/welcome.html)
- [SageMaker Best Practices](https://docs.aws.amazon.com/sagemaker/latest/dg/best-practices.html)
- [Time Series Forecasting Best Practices](https://docs.aws.amazon.com/forecast/latest/dg/best-practices.html)

### Community Resources
- [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/)
- [SageMaker Examples Repository](https://github.com/aws/amazon-sagemaker-examples)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.