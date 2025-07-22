# Infrastructure as Code for Infrastructure Automation with Proton and CDK

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Automation with Proton and CDK".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Node.js 16+ and npm installed for CDK development
- Python 3.8+ installed for CDK Python implementation
- Terraform 1.0+ installed for Terraform implementation
- AWS account with administrator access and permissions to create Proton resources
- Understanding of Infrastructure as Code and containerized applications
- Git repository for storing template code and application source

## Quick Start

### Using CloudFormation (AWS)

```bash
# Create the stack with required parameters
aws cloudformation create-stack \
    --stack-name proton-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-proton-project \
                 ParameterKey=EnvironmentTemplateName,ParameterValue=web-app-env \
                 ParameterKey=ServiceTemplateName,ParameterValue=web-app-svc \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name proton-automation-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name proton-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy ProtonAutomationStack

# View outputs
npx cdk outputs
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy ProtonAutomationStack

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
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

# The script will prompt for required parameters:
# - Project name
# - AWS region
# - Environment template name
# - Service template name
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: proton-demo)
- `EnvironmentTemplateName`: Name for the environment template (default: web-app-env)
- `ServiceTemplateName`: Name for the service template (default: web-app-svc)
- `VpcCidr`: CIDR block for the VPC (default: 10.0.0.0/16)

### CDK Context Variables

Set these in `cdk.context.json` or pass as context parameters:

```json
{
  "projectName": "my-proton-project",
  "environmentTemplateName": "web-app-env",
  "serviceTemplateName": "web-app-svc",
  "vpcCidr": "10.0.0.0/16"
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "my-proton-project"
environment_template_name = "web-app-env"
service_template_name = "web-app-svc"
vpc_cidr = "10.0.0.0/16"
aws_region = "us-east-1"
```

## Deployment Architecture

The infrastructure creates the following components:

1. **AWS Proton Service Role**: IAM role with necessary permissions for Proton operations
2. **S3 Bucket**: Storage for Proton template bundles
3. **Environment Template**: Proton template for shared infrastructure (VPC, ECS cluster)
4. **Service Template**: Proton template for application-specific resources
5. **VPC Infrastructure**: Multi-AZ VPC with public and private subnets
6. **ECS Cluster**: Container orchestration platform with Container Insights enabled

## Template Structure

### Environment Template Components

- **VPC**: Multi-AZ virtual private cloud with DNS support
- **Subnets**: Public and private subnets across multiple availability zones
- **Internet Gateway**: Outbound internet access for public subnets
- **NAT Gateway**: Secure outbound internet access for private subnets
- **ECS Cluster**: Container orchestration with monitoring enabled

### Service Template Components

- **ECS Service**: Container service definitions
- **Application Load Balancer**: Traffic distribution and health checks
- **Security Groups**: Network access controls
- **IAM Roles**: Task execution and service roles
- **CloudWatch Logs**: Centralized logging for containers

## Validation and Testing

After deployment, verify the infrastructure:

```bash
# List Proton environment templates
aws proton list-environment-templates

# Check template versions
aws proton list-environment-template-versions \
    --template-name <environment-template-name>

# Verify S3 bucket creation
aws s3 ls | grep proton-templates

# Test environment deployment
aws proton create-environment \
    --name test-environment \
    --template-name <environment-template-name> \
    --template-major-version "1" \
    --proton-service-role-arn <service-role-arn> \
    --spec file://test-environment-spec.yaml
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name proton-automation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name proton-automation-stack
```

### Using CDK (AWS)

```bash
# Destroy the stack
npx cdk destroy ProtonAutomationStack

# For Python CDK
cd cdk-python/
source .venv/bin/activate
cdk destroy ProtonAutomationStack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will prompt for confirmation before destroying resources
```

## Security Considerations

- **IAM Roles**: All resources use least privilege access principles
- **VPC Security**: Private subnets for application workloads, public subnets only for load balancers
- **Encryption**: S3 bucket encryption enabled for template storage
- **Network Security**: Security groups restrict access to necessary ports only
- **Monitoring**: CloudTrail and Container Insights enabled for audit and monitoring

## Cost Optimization

- **NAT Gateway**: Single NAT gateway for cost efficiency (consider multi-AZ for production)
- **ECS Fargate**: Pay-per-use model for container execution
- **S3 Storage**: Lifecycle policies for template version management
- **CloudWatch**: Log retention policies to manage storage costs

## Troubleshooting

### Common Issues

1. **Template Registration Failures**
   - Verify S3 bucket permissions
   - Check CloudFormation template syntax
   - Ensure Proton service role has necessary permissions

2. **Environment Deployment Failures**
   - Check CloudFormation stack events
   - Verify IAM permissions
   - Review template parameter values

3. **CDK Deployment Issues**
   - Ensure CDK is bootstrapped in target region
   - Check Node.js/Python version compatibility
   - Verify AWS credentials configuration

### Debug Commands

```bash
# Check Proton service role
aws iam get-role --role-name <proton-service-role-name>

# View CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name <stack-name>

# Check S3 bucket contents
aws s3 ls s3://<bucket-name>/ --recursive
```

## Customization

### Adding New Services

To extend the solution with additional services:

1. Create new service templates in the `service-templates/` directory
2. Update the infrastructure code to register additional templates
3. Modify the CDK constructs to support new service patterns
4. Update environment templates if shared infrastructure changes are needed

### Multi-Region Deployment

For multi-region deployments:

1. Modify Terraform/CDK code to accept region parameters
2. Update template storage to use region-specific S3 buckets
3. Consider cross-region dependencies and networking requirements
4. Update service templates to support region-specific configurations

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../infrastructure-automation-with-aws-proton-and-cdk.md)
- [AWS Proton User Guide](https://docs.aws.amazon.com/proton/latest/userguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [AWS Proton Templates GitHub Repository](https://github.com/aws-samples/aws-proton-sample-templates)
- [CDK Patterns](https://cdkpatterns.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)