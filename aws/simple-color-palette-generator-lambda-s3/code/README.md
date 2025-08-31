# Infrastructure as Code for Simple Color Palette Generator with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Color Palette Generator with Lambda and S3". This serverless solution creates random, aesthetically pleasing color combinations on demand using AWS Lambda and S3 storage.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys:
- AWS Lambda function with color generation logic
- S3 bucket for palette storage with encryption and versioning
- IAM role with least privilege permissions
- Lambda function URL for HTTP access
- Resource-based policies for secure access

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for creating:
  - Lambda functions and function URLs
  - S3 buckets with encryption and versioning
  - IAM roles and policies
- One of the following tool sets:
  - **CloudFormation**: No additional tools required
  - **CDK TypeScript**: Node.js (18.x or later), npm, AWS CDK CLI
  - **CDK Python**: Python (3.8 or later), pip, AWS CDK CLI
  - **Terraform**: Terraform (1.0 or later)
  - **Bash Scripts**: Standard Unix tools (curl, jq for testing)

## Cost Estimates

- **AWS Lambda**: $0.20 per 1M requests + $0.0000166667 per GB-second
- **S3 Storage**: $0.023 per GB per month (Standard class)
- **Lambda Function URL**: No additional cost
- **Estimated monthly cost for typical usage**: $0.01-$0.05

> **Note**: This solution uses AWS Free Tier eligible services. Lambda provides 1 million free requests per month, and S3 offers 5GB of free storage.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name color-palette-generator \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-color-palettes-$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name color-palette-generator

# Get the function URL
aws cloudformation describe-stacks \
    --stack-name color-palette-generator \
    --query 'Stacks[0].Outputs[?OutputKey==`FunctionUrl`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy

# The function URL will be displayed in the output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy

# The function URL will be displayed in the output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Get the function URL
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the solution
./scripts/deploy.sh

# The script will display the function URL upon completion
```

## Testing Your Deployment

Once deployed, test the color palette generator:

```bash
# Replace FUNCTION_URL with your actual function URL
FUNCTION_URL="https://your-function-url.lambda-url.region.on.aws/"

# Test different palette types
curl "${FUNCTION_URL}?type=complementary" | jq '.'
curl "${FUNCTION_URL}?type=analogous" | jq '.'
curl "${FUNCTION_URL}?type=triadic" | jq '.'
curl "${FUNCTION_URL}?type=random" | jq '.'
```

Expected response format:
```json
{
  "id": "a1b2c3d4",
  "type": "complementary",
  "colors": [[255, 100, 50], [50, 155, 205], ...],
  "created_at": "2025-01-15T10:30:00.000Z",
  "hex_colors": ["#ff6432", "#329bcd", ...]
}
```

## Customization

### CloudFormation Parameters

- `BucketName`: Name for the S3 bucket (must be globally unique)
- `FunctionName`: Name for the Lambda function
- `Environment`: Environment tag for resources (default: "dev")

### CDK Configuration

Modify the following in the CDK applications:

- **TypeScript**: Edit variables in `app.ts`
- **Python**: Edit variables in `app.py`

Available customizations:
- Bucket name prefix
- Function memory size and timeout
- CORS configuration
- Environment variables

### Terraform Variables

Customize deployment by modifying `variables.tf` or creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
bucket_name_prefix = "my-palettes"
function_name     = "my-palette-generator"
memory_size       = 512
timeout          = 60
environment      = "production"
```

### Bash Script Configuration

Edit the configuration section at the top of `scripts/deploy.sh`:

```bash
# Configuration
BUCKET_PREFIX="color-palettes"
FUNCTION_PREFIX="palette-generator"
MEMORY_SIZE=256
TIMEOUT=30
```

## API Usage Examples

### Web Application Integration

```javascript
// JavaScript example for web applications
async function generatePalette(type = 'complementary') {
    const response = await fetch(`${FUNCTION_URL}?type=${type}`);
    const palette = await response.json();
    
    // Display colors in your UI
    palette.hex_colors.forEach(color => {
        console.log(`Color: ${color}`);
    });
    
    return palette;
}
```

### Python Integration

```python
import requests
import json

def get_color_palette(function_url, palette_type='complementary'):
    response = requests.get(f"{function_url}?type={palette_type}")
    return response.json()

# Usage
palette = get_color_palette(FUNCTION_URL, 'analogous')
print(json.dumps(palette, indent=2))
```

## Monitoring and Troubleshooting

### CloudWatch Logs

View Lambda function logs:

```bash
# Get log group name
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/palette-generator"

# View recent logs
aws logs tail /aws/lambda/your-function-name --follow
```

### Common Issues

1. **403 Forbidden Error**: Check IAM permissions and resource-based policies
2. **500 Internal Server Error**: Check CloudWatch logs for function errors
3. **Bucket Access Denied**: Verify S3 bucket permissions and encryption settings
4. **CORS Issues**: Ensure Function URL CORS configuration matches your application

### Performance Optimization

- Monitor Lambda duration and memory usage in CloudWatch
- Consider provisioned concurrency for consistent response times
- Use S3 storage classes for cost optimization of stored palettes

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name color-palette-generator

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name color-palette-generator
```

### Using CDK

```bash
# From the CDK directory (TypeScript or Python)
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- All S3 data is encrypted at rest using AES-256
- IAM roles follow least privilege principles
- Lambda function has minimal required permissions
- Function URL supports CORS for web application integration
- No hardcoded credentials or secrets in the code

## Advanced Configuration

### Adding Authentication

To add authentication to the function URL, modify the deployment to use `AWS_IAM` auth type:

**CloudFormation**: Set `AuthType: AWS_IAM` in the function URL configuration
**CDK**: Use `authType: lambda.FunctionUrlAuthType.AWS_IAM`
**Terraform**: Set `authorization_type = "AWS_IAM"`

### Custom Domain

Consider using API Gateway with a custom domain for production deployments:

1. Create an API Gateway REST API
2. Set up custom domain with SSL certificate
3. Configure Lambda proxy integration
4. Update CORS settings as needed

### Batch Processing

For bulk palette generation, consider:

1. SQS queue for batch requests
2. Lambda function with higher memory allocation
3. S3 batch operations for processing stored palettes
4. Step Functions for complex workflows

## Support and Documentation

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation in the parent directory.

## Contributing

To contribute improvements to this IaC:

1. Test changes in a development environment
2. Validate all deployment methods still work
3. Update documentation as needed
4. Follow AWS security best practices
5. Ensure cleanup procedures work correctly

## License

This infrastructure code is provided as-is for educational and development purposes. Please review and modify according to your organization's requirements before production use.