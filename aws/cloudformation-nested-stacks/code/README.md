# Infrastructure as Code for CloudFormation Nested Stacks Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CloudFormation Nested Stacks Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code with nested stack templates (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit implementation with nested constructs (TypeScript)
- **CDK Python**: AWS Cloud Development Kit implementation with nested constructs (Python)
- **Terraform**: Multi-cloud infrastructure as code with modular configuration
- **Scripts**: Bash deployment and cleanup scripts with template management

## Architecture Overview

This implementation creates a hierarchical infrastructure using nested stacks:

- **Network Layer**: VPC, subnets, NAT gateways, and routing tables
- **Security Layer**: IAM roles, security groups, and access policies
- **Application Layer**: Load balancer, auto scaling group, and RDS database
- **Root Stack**: Orchestrates all nested stacks with proper dependencies

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudFormation (full access for nested stacks)
  - S3 (for template storage)
  - IAM (for role and policy creation)
  - EC2, VPC, RDS, and ELB services
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $20-40 for testing resources (varies by environment configuration)

## Quick Start

### Using CloudFormation (Native)

```bash
# Set required environment variables
export AWS_REGION=$(aws configure get region)
export TEMPLATE_BUCKET="cf-templates-$(aws sts get-caller-identity --query Account --output text)-$(date +%s)"
export STACK_NAME="nested-infrastructure-$(date +%s)"

# Create S3 bucket for templates
aws s3 mb s3://${TEMPLATE_BUCKET} --region ${AWS_REGION}

# Deploy nested stack templates
aws s3 cp cloudformation/ s3://${TEMPLATE_BUCKET}/ --recursive --exclude "*.md"

# Deploy root stack
aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-url https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/root-stack.yaml \
    --parameters ParameterKey=TemplateBucketName,ParameterValue=${TEMPLATE_BUCKET} \
                ParameterKey=Environment,ParameterValue=development \
                ParameterKey=ProjectName,ParameterValue=webapp \
    --capabilities CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME}
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy all nested stacks
npx cdk deploy --all

# View outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy all nested stacks
cdk deploy --all

# View outputs
cdk list
```

### Using Terraform

```bash
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

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables for customization:

```bash
# Required
export AWS_REGION="us-east-1"              # AWS region for deployment
export PROJECT_NAME="webapp"               # Project name for resource tagging
export ENVIRONMENT="development"           # Environment (development/staging/production)

# Optional
export VPC_CIDR="10.0.0.0/16"             # VPC CIDR block
export ENABLE_NAT_GATEWAY="true"           # Enable NAT gateways for private subnets
export DB_INSTANCE_CLASS="db.t3.micro"     # RDS instance class
export EC2_INSTANCE_TYPE="t3.micro"        # EC2 instance type
export MIN_CAPACITY="1"                    # Auto scaling minimum capacity
export MAX_CAPACITY="3"                    # Auto scaling maximum capacity
```

### CloudFormation Parameters

The CloudFormation implementation supports these parameters:

- `Environment`: Deployment environment (development/staging/production)
- `ProjectName`: Project name for resource tagging
- `TemplateBucketName`: S3 bucket containing nested stack templates
- `VpcCidr`: CIDR block for VPC (default: 10.0.0.0/16)
- `InstanceType`: EC2 instance type (mapped by environment)
- `DatabaseClass`: RDS instance class (mapped by environment)

### CDK Context Variables

CDK implementations use `cdk.json` context for configuration:

```json
{
  "context": {
    "environment": "development",
    "projectName": "webapp",
    "vpcCidr": "10.0.0.0/16",
    "enableNatGateway": true,
    "multiAz": false
  }
}
```

### Terraform Variables

Terraform implementation uses `terraform.tfvars` for configuration:

```hcl
environment          = "development"
project_name         = "webapp"
vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b"]
instance_type       = "t3.micro"
db_instance_class   = "db.t3.micro"
enable_nat_gateway  = true
```

## Outputs

All implementations provide these key outputs:

- **VPC ID**: The created VPC identifier
- **Subnet IDs**: Public and private subnet identifiers
- **Security Group IDs**: Application, database, and load balancer security groups
- **Load Balancer DNS**: Application Load Balancer endpoint
- **Database Endpoint**: RDS database connection endpoint
- **Application URL**: Complete application access URL

## Cross-Stack References

The nested stack architecture demonstrates these cross-stack reference patterns:

### Export/Import Pattern (CloudFormation)
```yaml
# In Network Stack
Outputs:
  VpcId:
    Value: !Ref VPC
    Export:
      Name: !Sub '${AWS::StackName}-VpcId'

# In Security Stack
Parameters:
  VpcId:
    Type: String
    Default: !ImportValue NetworkStack-VpcId
```

### Construct References (CDK)
```typescript
// In TypeScript CDK
const networkStack = new NetworkStack(app, 'NetworkStack');
const securityStack = new SecurityStack(app, 'SecurityStack', {
  vpc: networkStack.vpc
});
```

### Data Sources (Terraform)
```hcl
# Reference outputs from other modules
data "terraform_remote_state" "network" {
  backend = "local"
  config = {
    path = "../network/terraform.tfstate"
  }
}

resource "aws_security_group" "app" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}
```

## Validation and Testing

### Infrastructure Validation

```bash
# Validate all resources are created
aws cloudformation describe-stacks --stack-name ${STACK_NAME}

# Test cross-stack references
aws cloudformation list-exports

# Verify application accessibility
APPLICATION_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
    --output text)
curl -I ${APPLICATION_URL}
```

### CDK Testing

```bash
# Run CDK unit tests
npm test  # TypeScript
pytest    # Python

# Validate CDK synthesis
cdk synth --all
```

### Terraform Testing

```bash
# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Run tests (if configured)
terraform test
```

## Monitoring and Troubleshooting

### CloudFormation Events

```bash
# Monitor stack events
aws cloudformation describe-stack-events --stack-name ${STACK_NAME}

# Check nested stack status
aws cloudformation list-stack-resources --stack-name ${STACK_NAME}
```

### Common Issues

1. **Template Upload Failures**: Ensure S3 bucket exists and templates are uploaded
2. **IAM Permission Errors**: Verify CAPABILITY_NAMED_IAM is specified
3. **Resource Limit Exceeded**: Check AWS service limits in your region
4. **Cross-Stack Reference Failures**: Verify export names match import values
5. **Update Conflicts**: Use change sets to preview updates before execution

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# CloudFormation
export AWS_CLI_FILE_ENCODING=UTF-8
aws cloudformation describe-stack-events --stack-name ${STACK_NAME} --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# CDK
cdk deploy --debug

# Terraform
TF_LOG=DEBUG terraform apply
```

## Cleanup

### Using CloudFormation
```bash
# Delete root stack (automatically deletes nested stacks)
aws cloudformation delete-stack --stack-name ${STACK_NAME}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}

# Clean up template bucket
aws s3 rb s3://${TEMPLATE_BUCKET} --force
```

### Using CDK
```bash
# Destroy all stacks
cdk destroy --all

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Type 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm destructive actions when prompted
```

## Advanced Features

### Change Sets for Safe Updates

```bash
# Create change set to preview changes
aws cloudformation create-change-set \
    --stack-name ${STACK_NAME} \
    --change-set-name update-$(date +%s) \
    --template-url https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/root-stack.yaml \
    --parameters ParameterKey=Environment,ParameterValue=staging \
    --capabilities CAPABILITY_NAMED_IAM

# Review changes before execution
aws cloudformation describe-change-set \
    --stack-name ${STACK_NAME} \
    --change-set-name update-$(date +%s)
```

### Blue-Green Deployments

The nested stack architecture supports blue-green deployment patterns:

1. Deploy new stack with different environment parameter
2. Test new environment thoroughly
3. Update DNS or load balancer to point to new stack
4. Cleanup old stack after validation

### Stack Policies

Protect critical resources with stack policies:

```bash
# Apply stack policy to prevent accidental updates
aws cloudformation set-stack-policy \
    --stack-name ${STACK_NAME} \
    --stack-policy-body file://stack-policy.json
```

## Cost Optimization

### Environment-Based Sizing

The implementation automatically adjusts resource sizes based on environment:

- **Development**: t3.micro instances, single AZ RDS
- **Staging**: t3.small instances, multi-AZ RDS
- **Production**: t3.medium instances, multi-AZ RDS with enhanced monitoring

### Resource Tagging

All resources are tagged for cost tracking:

```yaml
Tags:
  - Key: Environment
    Value: !Ref Environment
  - Key: Project
    Value: !Ref ProjectName
  - Key: CostCenter
    Value: Infrastructure
```

## Security Considerations

### IAM Least Privilege

- EC2 instances use instance profiles with minimal required permissions
- Security groups follow principle of least privilege
- Database credentials stored in AWS Secrets Manager

### Network Security

- Application instances deployed in private subnets
- NAT gateways provide outbound internet access for private subnets
- Security groups restrict traffic to necessary ports and sources

### Encryption

- RDS storage encryption enabled by default
- EBS volumes encrypted
- S3 template bucket uses server-side encryption

## Support and Resources

### Documentation Links

- [AWS CloudFormation Nested Stacks](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-nested-stacks.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### Community Resources

- [AWS CloudFormation Samples](https://github.com/aws-samples/aws-cloudformation-templates)
- [CDK Patterns](https://cdkpatterns.com/)
- [Terraform AWS Modules](https://registry.terraform.io/namespaces/terraform-aws-modules)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS CloudFormation events and logs
3. Consult the original recipe documentation
4. Reference AWS service documentation for specific resources

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow the respective tool's best practices
3. Update documentation for any parameter changes
4. Validate all implementations work consistently
5. Consider security and cost implications of changes