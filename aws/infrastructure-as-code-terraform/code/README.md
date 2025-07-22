# Infrastructure as Code for Infrastructure as Code with Terraform

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure as Code with Terraform".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a complete enterprise-grade infrastructure including:

- **VPC Module**: Isolated network environment with multi-AZ public subnets
- **Compute Module**: Auto Scaling Group with Application Load Balancer
- **State Management**: Remote state backend using S3 and DynamoDB
- **CI/CD Integration**: CodeBuild pipeline configuration
- **Environment Management**: Separate configurations for dev/staging/prod

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Terraform CLI v1.0 or later installed
- Git installed for version control
- AWS account with permissions for:
  - EC2 (instances, load balancers, auto scaling)
  - VPC (networks, subnets, security groups)
  - S3 (buckets for state storage)
  - DynamoDB (tables for state locking)
  - IAM (roles and policies)
- Estimated cost: $15-25 per day for resources created

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name terraform-iac-demo \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
                ParameterKey=InstanceType,ParameterValue=t3.micro \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name terraform-iac-demo \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name terraform-iac-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .env
source .env/bin/activate  # On Windows: .env\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Set required environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique suffix for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region    = "${AWS_REGION}"
project_name  = "terraform-iac-demo"
environment   = "dev"
vpc_cidr      = "10.0.0.0/16"
instance_type = "t3.micro"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Check deployment status
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=terraform-iac-demo"
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `AWS_REGION` | AWS region for deployment | `us-east-1` | No |
| `PROJECT_NAME` | Project identifier | `terraform-iac-demo` | No |
| `ENVIRONMENT` | Environment name | `dev` | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `aws_region` | AWS region for resources | string | `us-east-1` |
| `project_name` | Name of the project | string | `terraform-iac-demo` |
| `environment` | Environment name | string | `dev` |
| `vpc_cidr` | CIDR block for VPC | string | `10.0.0.0/16` |
| `instance_type` | EC2 instance type | string | `t3.micro` |

### CloudFormation Parameters

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `Environment` | Environment name | String | `dev` |
| `VpcCidr` | CIDR block for VPC | String | `10.0.0.0/16` |
| `InstanceType` | EC2 instance type | String | `t3.micro` |
| `ProjectName` | Project identifier | String | `terraform-iac-demo` |

## Validation and Testing

### Infrastructure Verification

```bash
# Verify VPC creation
aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=terraform-iac-demo" \
    --query 'Vpcs[0].{VpcId:VpcId,State:State,CidrBlock:CidrBlock}'

# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names terraform-iac-demo-web-asg \
    --query 'AutoScalingGroups[0].{Name:AutoScalingGroupName,DesiredCapacity:DesiredCapacity}'

# Test Application Load Balancer
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names terraform-iac-demo-web-alb \
    --query 'LoadBalancers[0].DNSName' --output text)

curl -s http://${ALB_DNS} | grep "Hello from Terraform"
```

### State Management Verification

```bash
# For Terraform implementation - check remote state
terraform state list

# Verify S3 state bucket
aws s3 ls s3://terraform-iac-demo-state-*/

# Check DynamoDB lock table
aws dynamodb describe-table --table-name terraform-iac-demo-locks
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name terraform-iac-demo

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name terraform-iac-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the infrastructure
cdk destroy

# Confirm destruction when prompted
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
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm destruction when prompted
```

### Complete Cleanup (All Methods)

```bash
# Remove any remaining state resources (if created manually)
BUCKET_NAME="terraform-iac-demo-state-$(date +%s)"
aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
aws s3api delete-bucket --bucket ${BUCKET_NAME} 2>/dev/null || true

# Delete DynamoDB lock table
aws dynamodb delete-table \
    --table-name terraform-iac-demo-locks 2>/dev/null || true

echo "✅ Complete cleanup finished"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for required service access

2. **Resource Conflicts**
   - Verify unique resource names across deployments
   - Check for existing resources with same names

3. **State Lock Issues** (Terraform)
   - Check DynamoDB table for stuck locks
   - Use `terraform force-unlock` if necessary

4. **Deployment Failures**
   - Review CloudFormation events or Terraform logs
   - Ensure prerequisites are met
   - Verify network connectivity and AWS service availability

### Debug Commands

```bash
# CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name terraform-iac-demo

# Terraform detailed logging
export TF_LOG=DEBUG
terraform plan

# CDK synthesis output
cdk synth

# AWS CLI debug mode
aws --debug ec2 describe-vpcs
```

## Customization

### Environment-Specific Deployments

Create separate parameter files for different environments:

```bash
# Development environment
cat > terraform.tfvars.dev << EOF
environment   = "dev"
instance_type = "t3.micro"
vpc_cidr      = "10.0.0.0/16"
EOF

# Production environment
cat > terraform.tfvars.prod << EOF
environment   = "prod"
instance_type = "t3.small"
vpc_cidr      = "10.1.0.0/16"
EOF
```

### Security Enhancements

- Enable VPC Flow Logs for network monitoring
- Implement AWS Systems Manager Session Manager for secure instance access
- Add AWS Config for compliance monitoring
- Enable AWS CloudTrail for audit logging

### Scaling Configurations

- Modify Auto Scaling Group parameters for capacity planning
- Implement CloudWatch alarms for automated scaling
- Configure Application Load Balancer health checks
- Add multiple availability zones for high availability

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Provider Documentation**: 
   - [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
   - [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
   - [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. **Community Support**:
   - AWS Support Forums
   - Terraform Community Forum
   - Stack Overflow with relevant tags

## Best Practices

- **Version Control**: Store all IaC code in version control systems
- **Environment Separation**: Use separate accounts or regions for different environments
- **State Management**: Always use remote state backends for team collaboration
- **Security**: Implement least privilege access and enable security monitoring
- **Cost Management**: Tag all resources and implement cost monitoring
- **Documentation**: Maintain up-to-date documentation and comments in code

## Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [AWS CDK Best Practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html)
- [Infrastructure as Code Security Best Practices](https://aws.amazon.com/blogs/devops/implementing-infrastructure-as-code-security-best-practices/)