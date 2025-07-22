# Infrastructure as Code for Infrastructure Automation with AWS Proton and CDK

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Automation with AWS Proton and CDK".

## Solution Overview

This infrastructure automation solution enables organizations to provide standardized, self-service infrastructure provisioning while maintaining central governance and security controls. The solution uses AWS Proton as the orchestration layer with AWS CDK as the infrastructure-as-code foundation, allowing platform teams to create reusable templates that development teams can deploy consistently across environments.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure includes:
- AWS Proton service roles and permissions
- S3 bucket for template storage
- Environment templates (VPC, ECS cluster, networking)
- Service templates (Fargate services, load balancers, auto-scaling)
- CI/CD integration points
- CloudWatch logging and monitoring

## Prerequisites

- AWS account with administrator access
- AWS CLI v2 installed and configured
- Node.js 16.x or later (for CDK implementations)
- Python 3.8+ (for CDK Python implementation)
- Terraform 1.5+ (for Terraform implementation)
- Git installed and configured
- Basic understanding of Infrastructure as Code concepts
- Understanding of containerization and CI/CD concepts
- Estimated cost: $15-25 for testing environments

## Quick Start

### Using CloudFormation
```bash
# Deploy the core infrastructure
aws cloudformation create-stack \
    --stack-name proton-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name proton-automation-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name proton-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# Verify deployment
cdk ls
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

# Deploy the infrastructure
cdk deploy

# Verify deployment
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Verify resources
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws proton list-environment-templates
aws proton list-service-templates
```

## Configuration Options

### Environment Template Customization

Most implementations support these configuration parameters:

- **VPC CIDR**: Network range for the environment (default: 10.0.0.0/16)
- **Environment Name**: Identifier for the environment
- **Region**: AWS region for deployment
- **Availability Zones**: Number of AZs to use (default: 2)

### Service Template Customization

Service templates can be configured with:

- **Container Image**: Docker image to deploy
- **Container Port**: Application port (default: 80)
- **Memory Allocation**: Task memory in MiB (default: 512)
- **CPU Allocation**: Task CPU units (default: 256)
- **Desired Count**: Number of running tasks (default: 2)
- **Auto-scaling**: Min/max capacity settings
- **Health Check Path**: Application health endpoint (default: /)

### Example Parameter Files

Create a `parameters.json` file for CloudFormation:
```json
[
  {
    "ParameterKey": "EnvironmentName",
    "ParameterValue": "development"
  },
  {
    "ParameterKey": "VpcCidr",
    "ParameterValue": "10.0.0.0/16"
  }
]
```

Create a `terraform.tfvars` file for Terraform:
```hcl
environment_name = "development"
vpc_cidr = "10.0.0.0/16"
container_image = "nginx:latest"
container_port = 80
```

## Post-Deployment Steps

After deploying the infrastructure, complete these steps to start using the automation platform:

### 1. Create Development Environment
```bash
# Create environment specification
cat > dev-environment-spec.json << 'EOF'
{
  "vpc_cidr": "10.0.0.0/16",
  "environment_name": "development"
}
EOF

# Create the environment
aws proton create-environment \
    --name "dev-environment" \
    --template-name "vpc-ecs-environment" \
    --template-major-version "1" \
    --spec file://dev-environment-spec.json \
    --proton-service-role-arn $(terraform output -raw proton_service_role_arn)
```

### 2. Deploy Test Service
```bash
# Create service specification
cat > test-service-spec.json << 'EOF'
{
  "image": "nginx:latest",
  "port": 80,
  "environment": "development",
  "memory": 512,
  "cpu": 256,
  "desired_count": 1,
  "min_capacity": 1,
  "max_capacity": 3,
  "health_check_path": "/"
}
EOF

# Create the service
aws proton create-service \
    --name "test-web-service" \
    --template-name "fargate-web-service" \
    --template-major-version "1" \
    --spec file://test-service-spec.json
```

### 3. Verify Deployment
```bash
# Check environment status
aws proton get-environment --name "dev-environment"

# Check service status
aws proton get-service --name "test-web-service"

# Get load balancer endpoint
aws proton get-service-instance \
    --service-name "test-web-service" \
    --name "dev-instance" \
    --query 'serviceInstance.outputs'
```

## Monitoring and Observability

The deployed infrastructure includes:

- **CloudWatch Logs**: Centralized logging for all services
- **ECS Service Metrics**: Container performance monitoring
- **Application Load Balancer Metrics**: Request and response monitoring
- **Auto-scaling Metrics**: Scaling events and capacity changes

Access monitoring dashboards:
```bash
# View recent logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/ecs/"

# View ECS cluster metrics
aws ecs describe-clusters \
    --clusters $(aws ecs list-clusters --query 'clusterArns[0]' --output text)
```

## Troubleshooting

### Common Issues

1. **Template Registration Failures**
   - Verify S3 bucket permissions
   - Check template bundle format
   - Validate schema syntax

2. **Environment Creation Failures**
   - Check IAM service role permissions
   - Verify VPC CIDR doesn't conflict
   - Ensure sufficient IP addresses

3. **Service Deployment Failures**
   - Verify container image accessibility
   - Check ECS task execution role
   - Validate health check endpoint

### Debug Commands
```bash
# Check Proton service logs
aws logs get-log-events \
    --log-group-name "/aws/proton/provisioning"

# Verify IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn $(terraform output -raw proton_service_role_arn) \
    --action-names "ecs:CreateService" \
    --resource-arns "*"

# Check CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name $(aws proton get-environment \
        --name "dev-environment" \
        --query 'environment.provisioning.stackArn' \
        --output text | cut -d/ -f2)
```

## Cleanup

### Using CloudFormation
```bash
# Delete any created environments and services first
aws proton delete-service --name "test-web-service"
aws proton delete-environment --name "dev-environment"

# Wait for resources to be deleted
aws proton wait environment-deleted --name "dev-environment"

# Delete the main stack
aws cloudformation delete-stack --stack-name proton-automation-stack
aws cloudformation wait stack-delete-complete --stack-name proton-automation-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Clean up Proton resources first
aws proton delete-service --name "test-web-service"
aws proton delete-environment --name "dev-environment"
aws proton wait environment-deleted --name "dev-environment"

# Destroy CDK stack
cdk destroy
```

### Using Terraform
```bash
cd terraform/

# Clean up Proton resources first
aws proton delete-service --name "test-web-service" || true
aws proton delete-environment --name "dev-environment" || true
aws proton wait environment-deleted --name "dev-environment" || true

# Destroy Terraform infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# List and delete any remaining Proton resources
aws proton list-services
aws proton list-environments
aws proton list-service-templates
aws proton list-environment-templates

# Clean up S3 bucket
aws s3 rm s3://$(aws s3 ls | grep proton-templates | awk '{print $3}') --recursive
aws s3api delete-bucket --bucket $(aws s3 ls | grep proton-templates | awk '{print $3}')
```

## Customization

### Adding New Service Templates

1. Create CDK infrastructure code for your service type
2. Define the service schema with required parameters
3. Package and upload to the templates S3 bucket
4. Register with AWS Proton

### Environment Template Modifications

Common customizations include:
- Additional VPC features (NAT Gateways, VPC Endpoints)
- Different compute platforms (EC2, Lambda)
- Enhanced security configurations
- Multi-region deployments

### Integration with CI/CD

The infrastructure supports integration with:
- AWS CodePipeline and CodeBuild
- GitHub Actions
- GitLab CI/CD
- Jenkins

Example GitHub Actions workflow:
```yaml
name: Deploy with Proton
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Update Proton service
        run: |
          aws proton update-service-instance \
            --service-name "my-service" \
            --name "prod-instance" \
            --spec file://service-spec.json
```

## Security Considerations

- All IAM roles follow least privilege principles
- Container images should be scanned for vulnerabilities
- VPC security groups restrict access to necessary ports only
- ECS tasks run with non-root users when possible
- Secrets are managed through AWS Secrets Manager or Parameter Store
- All resources are encrypted in transit and at rest

## Cost Optimization

- Environment templates include auto-scaling to minimize idle resources
- Use Spot instances where appropriate for development environments
- Implement lifecycle policies for CloudWatch logs
- Monitor costs with AWS Cost Explorer and set up billing alerts

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS Proton documentation: https://docs.aws.amazon.com/proton/
3. Consult AWS CDK documentation: https://docs.aws.amazon.com/cdk/
4. Refer to the original recipe documentation
5. Contact your platform team for template-specific issues

## Contributing

To contribute improvements to these templates:
1. Test changes in a development environment
2. Update relevant documentation
3. Ensure all IaC implementations remain synchronized
4. Follow the organization's infrastructure standards