# Infrastructure as Code for Quantum Computing Pipelines with Braket

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quantum Computing Pipelines with Braket".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Amazon Braket service enabled in your AWS account
- Appropriate IAM permissions for:
  - Amazon Braket full access
  - Lambda function management
  - S3 bucket operations
  - CloudWatch logs and metrics
  - IAM role creation and policy attachment
- For quantum processor (QPU) access: Additional approval through AWS Support
- Estimated cost: $50-200 for quantum simulations and compute resources

> **Note**: Amazon Braket QPU access requires separate approval and incurs significantly higher costs than quantum simulators.

## Architecture Overview

This implementation creates a complete hybrid quantum-classical computing pipeline including:

- **Storage Layer**: S3 buckets for input data, output results, and quantum algorithm code
- **Quantum Processing**: Amazon Braket integration for quantum algorithm execution
- **Classical Processing**: Lambda functions for data preparation, job orchestration, monitoring, and post-processing
- **Monitoring**: CloudWatch dashboard, metrics, and alarms for pipeline observability
- **Security**: IAM roles and policies following least privilege principles

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the quantum computing pipeline
aws cloudformation create-stack \
    --stack-name quantum-pipeline-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-quantum-project

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name quantum-pipeline-stack \
    --query 'Stacks[0].StackStatus'

# Get output values
aws cloudformation describe-stacks \
    --stack-name quantum-pipeline-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the quantum pipeline
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python (AWS)

```bash
# Set up Python environment
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the quantum pipeline
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
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

# Deploy quantum pipeline
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Testing the Pipeline

After deployment, test the quantum computing pipeline:

```bash
# Set environment variables from outputs
export PROJECT_NAME=$(terraform output -raw project_name)  # or from CloudFormation/CDK outputs
export INPUT_BUCKET=$(terraform output -raw s3_input_bucket)
export OUTPUT_BUCKET=$(terraform output -raw s3_output_bucket)
export CODE_BUCKET=$(terraform output -raw s3_code_bucket)

# Test data preparation
aws lambda invoke \
    --function-name ${PROJECT_NAME}-data-preparation \
    --payload '{
        "input_bucket": "'${INPUT_BUCKET}'",
        "output_bucket": "'${OUTPUT_BUCKET}'",
        "problem_type": "optimization",
        "problem_size": 4
    }' \
    --cli-binary-format raw-in-base64-out \
    test-response.json

# View test results
cat test-response.json

# Extract data key for next step
DATA_KEY=$(cat test-response.json | jq -r '.body' | jq -r '.data_key')
echo "Data key: ${DATA_KEY}"

# Test quantum job submission
aws lambda invoke \
    --function-name ${PROJECT_NAME}-job-submission \
    --payload '{
        "input_bucket": "'${INPUT_BUCKET}'",
        "output_bucket": "'${OUTPUT_BUCKET}'",
        "code_bucket": "'${CODE_BUCKET}'",
        "data_key": "'${DATA_KEY}'"
    }' \
    --cli-binary-format raw-in-base64-out \
    job-submission-response.json

# Check submission response
cat job-submission-response.json
```

## Monitoring and Observability

Access the CloudWatch dashboard to monitor quantum pipeline performance:

```bash
# Get dashboard URL
aws cloudwatch describe-dashboards \
    --query 'DashboardEntries[?contains(DashboardName, `quantum-pipeline`)].DashboardName' \
    --output text

# View recent quantum job metrics
aws cloudwatch get-metric-statistics \
    --namespace QuantumPipeline \
    --metric-name JobsSubmitted \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Customization

### Common Configuration Options

Each implementation supports customization through variables/parameters:

- **Project Name**: Prefix for all resources (default: auto-generated)
- **AWS Region**: Deployment region (default: us-east-1 for Braket compatibility)
- **Lambda Configuration**: Memory size, timeout, and runtime versions
- **S3 Configuration**: Bucket names, encryption settings, and lifecycle policies
- **Quantum Settings**: Default problem sizes, optimization parameters, and device preferences
- **Monitoring**: CloudWatch retention periods and alarm thresholds

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: quantum-pipeline
    Description: Name prefix for all resources
  
  DefaultProblemSize:
    Type: Number
    Default: 4
    MinValue: 2
    MaxValue: 20
    Description: Default quantum problem size
  
  LambdaMemorySize:
    Type: Number
    Default: 512
    Description: Memory allocation for Lambda functions
  
  EnableBraketQPU:
    Type: String
    Default: 'false'
    AllowedValues: ['true', 'false']
    Description: Enable Amazon Braket QPU access
  
  CloudWatchRetentionDays:
    Type: Number
    Default: 14
    Description: CloudWatch log retention period in days
```

### CDK Context Variables

```json
{
  "project-name": "my-quantum-project",
  "enable-qpu-access": false,
  "monitoring-retention-days": 30,
  "lambda-timeout-seconds": 300,
  "default-problem-size": 4,
  "lambda-memory-size": 512,
  "enable-s3-versioning": true
}
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "quantum-pipeline"
}

variable "default_problem_size" {
  description = "Default quantum problem size"
  type        = number
  default     = 4
  
  validation {
    condition     = var.default_problem_size >= 2 && var.default_problem_size <= 20
    error_message = "Problem size must be between 2 and 20 qubits."
  }
}

variable "enable_braket_qpu" {
  description = "Enable Amazon Braket QPU access"
  type        = bool
  default     = false
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}
```

### Example terraform.tfvars

```hcl
# Core configuration
aws_region   = "us-east-1"
project_name = "my-quantum-project"
environment  = "prod"

# Quantum computing configuration
enable_braket_qpu       = false
braket_device_type      = "simulator"
optimization_iterations = 200
learning_rate          = 0.05

# Lambda configuration
lambda_memory_size         = 1024
lambda_timeout             = 600
quantum_algorithm_timeout  = 1800

# Monitoring configuration
enable_monitoring                = true
cloudwatch_retention_days       = 30
alarm_threshold_job_failures    = 5
alarm_threshold_low_efficiency  = 0.2

# Additional tags
tags = {
  Owner       = "quantum-team"
  CostCenter  = "research"
  Application = "quantum-optimization"
}
```

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles with minimal required permissions:

- **Braket Execution Role**: Access to quantum simulators and QPUs
- **Lambda Execution Role**: S3 access, CloudWatch logging, and Braket job management
- **S3 Bucket Policies**: Restricted access to quantum pipeline resources only

### Data Protection

- All S3 buckets use server-side encryption
- CloudWatch logs are encrypted at rest
- Quantum algorithm code is stored securely in S3
- IAM policies follow least privilege principles

### Network Security

- Lambda functions operate in AWS-managed VPCs
- S3 bucket access is restricted to pipeline resources
- No public internet access required for quantum processing

## Cost Optimization

### Simulator vs QPU Usage

- **Quantum Simulators**: Cost-effective for development and testing
- **Quantum Processors (QPUs)**: Higher cost but provide actual quantum hardware access
- **Automatic Device Selection**: Algorithm chooses optimal device based on problem size

### Resource Management

- Lambda functions scale automatically based on demand
- S3 storage costs are minimal for typical quantum algorithms
- CloudWatch monitoring provides cost visibility

### Cost Monitoring

```bash
# View estimated costs for quantum jobs
aws braket search-jobs \
    --filter "jobName:quantum-pipeline*" \
    --query 'jobs[*].[jobName,billableDuration]' \
    --output table
```

## Troubleshooting

### Common Issues

1. **Braket Service Not Available**: Ensure Amazon Braket is enabled in your region
2. **QPU Access Denied**: QPU access requires separate approval from AWS Support
3. **Lambda Timeouts**: Increase timeout values for complex quantum algorithms
4. **S3 Permissions**: Verify IAM roles have correct S3 bucket permissions

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/quantum-pipeline"

# View recent Lambda execution logs
aws logs tail /aws/lambda/quantum-pipeline-data-preparation \
    --since 1h --follow

# Check Braket job status
aws braket search-jobs \
    --filter "jobName:quantum-pipeline*" \
    --query 'jobs[*].[jobName,status,createdAt]' \
    --output table

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace QuantumPipeline \
    --metric-name OptimizationEfficiency \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name quantum-pipeline-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name quantum-pipeline-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the quantum pipeline
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction
cdk destroy --force
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm destruction
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Force cleanup (skip confirmations)
./scripts/destroy.sh --force
```

### Manual Cleanup Verification

```bash
# Verify S3 buckets are deleted
aws s3 ls | grep quantum-pipeline

# Check Lambda functions are removed
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `quantum-pipeline`)].FunctionName'

# Verify IAM roles are deleted
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `quantum-pipeline`)].RoleName'

# Cancel any running Braket jobs
aws braket search-jobs \
    --filter "jobName:quantum-pipeline*" \
    --query "jobs[?status=='RUNNING'].jobArn" \
    --output text | while read job_arn; do
    if [ ! -z "$job_arn" ]; then
        aws braket cancel-job --job-arn $job_arn
        echo "Cancelled job: $job_arn"
    fi
done
```

## Advanced Usage

### Multi-Algorithm Support

The infrastructure supports multiple quantum algorithms:

- **Variational Quantum Eigensolver (VQE)**: For chemistry and optimization
- **Quantum Approximate Optimization Algorithm (QAOA)**: For combinatorial optimization
- **Quantum Machine Learning**: For hybrid classical-quantum ML models

### Custom Algorithm Integration

```bash
# Upload custom quantum algorithm
aws s3 cp my-quantum-algorithm.py \
    s3://${CODE_BUCKET}/quantum-code/custom_algorithm.py

# Update Lambda function to use custom algorithm
aws lambda update-function-code \
    --function-name ${PROJECT_NAME}-job-submission \
    --s3-bucket ${CODE_BUCKET} \
    --s3-key quantum-code/custom_algorithm.py
```

### Batch Processing

```bash
# Submit multiple quantum jobs
for problem_size in 4 6 8; do
    aws lambda invoke \
        --function-name ${PROJECT_NAME}-data-preparation \
        --payload '{"problem_size": '${problem_size}'}' \
        --cli-binary-format raw-in-base64-out \
        batch-job-${problem_size}.json
done
```

## Performance Optimization

### Lambda Configuration

- **Memory**: Increase for complex quantum algorithms (1024MB+)
- **Timeout**: Extend for long-running quantum jobs (15 minutes max)
- **Concurrency**: Set reserved concurrency for predictable performance

### Quantum Algorithm Optimization

- **Circuit Depth**: Minimize for better fidelity on NISQ devices
- **Parameter Count**: Optimize for faster classical optimization
- **Device Selection**: Choose appropriate quantum backend for problem size

## Support and Resources

### Documentation

- [Amazon Braket Developer Guide](https://docs.aws.amazon.com/braket/latest/developerguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [PennyLane Quantum Computing Framework](https://pennylane.ai/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Community

- [AWS Quantum Computing Blog](https://aws.amazon.com/blogs/quantum-computing/)
- [Amazon Braket Examples Repository](https://github.com/aws/amazon-braket-examples)
- [Quantum Computing Stack Exchange](https://quantumcomputing.stackexchange.com/)

### Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs for detailed error messages
3. Consult the original recipe documentation
4. Contact AWS Support for Braket-specific issues

## License

This infrastructure code is provided under the same license as the original recipe documentation.