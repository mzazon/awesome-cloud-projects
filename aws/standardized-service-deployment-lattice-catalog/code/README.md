# Infrastructure as Code for Standardized Service Deployment with VPC Lattice and Service Catalog

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Standardized Service Deployment with VPC Lattice and Service Catalog".

## Recipe Overview

This solution demonstrates how to implement AWS Service Catalog to provide governed self-service deployment of standardized VPC Lattice service templates. The architecture combines Service Catalog's portfolio management with CloudFormation templates to deliver consistent, compliant service mesh deployments while enabling development teams to provision VPC Lattice services independently through a centralized catalog of pre-approved configurations.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The IaC implementations deploy the following key components:

- **AWS Service Catalog Portfolio**: Organizational structure for grouping VPC Lattice service products
- **Service Catalog Products**: Standardized templates for VPC Lattice service networks and services
- **VPC Lattice Service Network**: Logical boundary for service mesh with IAM authentication policies
- **VPC Lattice Service**: Individual services with standardized target groups and listeners
- **IAM Roles and Policies**: Launch constraints for Service Catalog with appropriate VPC Lattice permissions
- **S3 Bucket**: Storage for CloudFormation templates used by Service Catalog products

## Prerequisites

- AWS account with appropriate permissions for:
  - VPC Lattice (create service networks, services, target groups, listeners)
  - Service Catalog (create portfolios, products, launch constraints)
  - CloudFormation (create/delete stacks, describe stack resources)
  - IAM (create roles, attach policies, manage trust relationships)
  - S3 (create buckets, upload/download objects)
  - EC2 (describe VPCs for service deployment)
- AWS CLI v2 installed and configured (or use AWS CloudShell)
- Existing VPC with subnets for service deployment
- For CDK: Node.js 18+ or Python 3.8+
- For Terraform: Terraform CLI 1.0+
- Basic understanding of service mesh concepts and CloudFormation
- Estimated cost: $5-15 for testing resources (VPC Lattice services, CloudFormation stacks)

> **Note**: VPC Lattice pricing is based on data processing units and active service networks. This tutorial uses minimal resources for demonstration purposes. See [VPC Lattice pricing](https://aws.amazon.com/vpc-lattice/pricing/) for current rates.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the complete standardized service deployment infrastructure
aws cloudformation create-stack \
    --stack-name standardized-lattice-deployment \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
                 ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name standardized-lattice-deployment \
    --query 'Stacks[0].StackStatus'

# Get outputs including Service Catalog portfolio ID
aws cloudformation describe-stacks \
    --stack-name standardized-lattice-deployment \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure AWS CDK (if first time using CDK in this region)
npm run cdk bootstrap

# Deploy the standardized service deployment stack
npm run cdk deploy StandardizedServiceDeploymentStack

# Deploy all stacks (VPC Lattice templates and Service Catalog)
npm run cdk deploy --all

# View deployed resources
npm run cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configure AWS CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the standardized service deployment stack
cdk deploy StandardizedServiceDeploymentStack

# Deploy all stacks
cdk deploy --all

# View deployed resources
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the deployment plan
terraform plan \
    -var="vpc_id=vpc-xxxxxxxxx" \
    -var="environment=dev"

# Deploy the infrastructure
terraform apply \
    -var="vpc_id=vpc-xxxxxxxxx" \
    -var="environment=dev"

# View deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export VPC_ID=vpc-xxxxxxxxx
export ENVIRONMENT=dev
export AWS_REGION=us-east-1

# Deploy the complete infrastructure
./scripts/deploy.sh

# Check deployment status
aws servicecatalog list-portfolios \
    --query 'PortfolioDetails[?contains(DisplayName, `vpc-lattice-services`)]'
```

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

```bash
# Required
export VPC_ID=vpc-xxxxxxxxx          # VPC ID for VPC Lattice target groups
export AWS_REGION=us-east-1          # AWS region for deployment

# Optional with defaults
export ENVIRONMENT=dev               # Environment name (dev/staging/prod)
export PROJECT_NAME=lattice-catalog  # Project name for resource naming
export PORTFOLIO_NAME_PREFIX=vpc-lattice-services  # Service Catalog portfolio prefix
```

### Terraform Variables

Key variables that can be customized in `terraform/variables.tf`:

- `vpc_id`: VPC ID for VPC Lattice target groups (required)
- `environment`: Environment name for resource tagging
- `project_name`: Project name for consistent resource naming
- `service_network_auth_type`: Authentication type for service network (AWS_IAM or NONE)
- `health_check_path`: Health check path for VPC Lattice services
- `default_port`: Default port for VPC Lattice services
- `enable_access_logs`: Enable access logging for VPC Lattice services

### CDK Context

For CDK deployments, you can customize the deployment using `cdk.json` context:

```json
{
  "context": {
    "vpc-id": "vpc-xxxxxxxxx",
    "environment": "dev",
    "project-name": "lattice-catalog",
    "service-network-auth-type": "AWS_IAM"
  }
}
```

## Validation & Testing

After deployment, verify the infrastructure:

### 1. Service Catalog Resources

```bash
# List Service Catalog portfolios
aws servicecatalog list-portfolios \
    --query 'PortfolioDetails[?contains(DisplayName, `vpc-lattice-services`)]'

# List products in the portfolio
PORTFOLIO_ID=$(aws servicecatalog list-portfolios \
    --query 'PortfolioDetails[?contains(DisplayName, `vpc-lattice-services`)].Id' \
    --output text)

aws servicecatalog search-products-as-admin \
    --portfolio-id "${PORTFOLIO_ID}" \
    --query 'ProductViewDetails[*].ProductViewSummary.[Name,ProductId]'
```

### 2. S3 Bucket and Templates

```bash
# List CloudFormation templates in S3 bucket
BUCKET_NAME=$(aws s3api list-buckets \
    --query 'Buckets[?contains(Name, `service-catalog-templates`)].Name' \
    --output text)

aws s3 ls s3://${BUCKET_NAME}/
```

### 3. IAM Resources

```bash
# Verify Service Catalog launch role
aws iam list-roles \
    --query 'Roles[?contains(RoleName, `ServiceCatalogVpcLatticeRole`)].RoleName'

# Check role policies
ROLE_NAME=$(aws iam list-roles \
    --query 'Roles[?contains(RoleName, `ServiceCatalogVpcLatticeRole`)].RoleName' \
    --output text)

aws iam list-role-policies --role-name "${ROLE_NAME}"
```

### 4. Test Service Catalog End-User Experience

```bash
# Search products as end user
aws servicecatalog search-products \
    --query 'ProductViewSummaries[*].[Name,ProductId]'

# Test deploying a service network
SERVICE_NETWORK_PRODUCT_ID=$(aws servicecatalog search-products \
    --query 'ProductViewSummaries[?contains(Name, `standardized-service-network`)].ProductId' \
    --output text)

aws servicecatalog provision-product \
    --product-id "${SERVICE_NETWORK_PRODUCT_ID}" \
    --provisioned-product-name "test-network-$(date +%s)" \
    --provisioning-artifact-name "v1.0" \
    --provisioning-parameters \
    Key="NetworkName",Value="test-network" \
    Key="AuthType",Value="AWS_IAM"
```

## Self-Service Deployment Guide

Once the infrastructure is deployed, development teams can use Service Catalog to deploy standardized VPC Lattice services:

### 1. Deploy Service Network

```bash
# Find the service network product
aws servicecatalog search-products \
    --query 'ProductViewSummaries[?contains(Name, `standardized-service-network`)]'

# Deploy service network
aws servicecatalog provision-product \
    --product-name "standardized-service-network" \
    --provisioned-product-name "my-service-network" \
    --provisioning-artifact-name "v1.0" \
    --provisioning-parameters \
    Key="NetworkName",Value="my-service-network" \
    Key="AuthType",Value="AWS_IAM"
```

### 2. Deploy VPC Lattice Service

```bash
# Deploy standardized lattice service
aws servicecatalog provision-product \
    --product-name "standardized-lattice-service" \
    --provisioned-product-name "my-api-service" \
    --provisioning-artifact-name "v1.0" \
    --provisioning-parameters \
    Key="ServiceName",Value="my-api-service" \
    Key="ServiceNetworkId",Value="sn-xxxxxxxxx" \
    Key="TargetType",Value="IP" \
    Key="VpcId",Value="vpc-xxxxxxxxx" \
    Key="Port",Value="8080" \
    Key="Protocol",Value="HTTP"
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete CloudFormation stack
aws cloudformation delete-stack \
    --stack-name standardized-lattice-deployment

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name standardized-lattice-deployment \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# CDK TypeScript
cd cdk-typescript/
npm run cdk destroy --all

# CDK Python
cd cdk-python/
cdk destroy --all
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="vpc_id=vpc-xxxxxxxxx" \
    -var="environment=dev"

# Clean up Terraform state
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws servicecatalog list-portfolios \
    --query 'PortfolioDetails[?contains(DisplayName, `vpc-lattice-services`)]'
```

## Cost Optimization

To minimize costs during testing:

1. **Use Spot Instances**: For any EC2 instances used as targets in VPC Lattice target groups
2. **Enable Auto-Scaling**: Configure target groups to scale based on demand
3. **Clean Up Regularly**: Remove test services and service networks when not needed
4. **Monitor Usage**: Use AWS Cost Explorer to track VPC Lattice data processing costs
5. **Use Development Environment**: Configure lower-capacity resources for non-production testing

## Security Best Practices

The IaC implementations follow AWS security best practices:

1. **Principle of Least Privilege**: IAM roles have minimal permissions for VPC Lattice operations
2. **Resource-Based Policies**: VPC Lattice services use IAM-based authentication
3. **Account-Level Access**: Service network policies restrict access to same AWS account
4. **Encryption**: All data in transit is encrypted using TLS
5. **Audit Trail**: CloudTrail logs all Service Catalog and VPC Lattice API calls
6. **Resource Tagging**: All resources are tagged for governance and cost tracking

## Troubleshooting

### Common Issues

1. **Service Catalog Permission Errors**:
   ```bash
   # Verify launch role permissions
   aws iam get-role-policy \
       --role-name ServiceCatalogVpcLatticeRole-* \
       --policy-name VpcLatticePermissions
   ```

2. **VPC Lattice Service Network Creation Fails**:
   ```bash
   # Check VPC Lattice service limits
   aws service-quotas get-service-quota \
       --service-code vpc-lattice \
       --quota-code L-4D4B79E3
   ```

3. **CloudFormation Stack Deployment Fails**:
   ```bash
   # Check stack events for error details
   aws cloudformation describe-stack-events \
       --stack-name standardized-lattice-deployment
   ```

4. **Target Group Health Check Failures**:
   ```bash
   # Verify target group configuration
   aws vpc-lattice list-target-groups \
       --query 'items[?contains(name, `targets`)]'
   ```

### Support Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [AWS Service Catalog User Guide](https://docs.aws.amazon.com/servicecatalog/latest/dg/what-is-service-catalog.html)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/latest/userguide/Welcome.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Advanced Configurations

### Multi-Environment Setup

For production deployments across multiple environments:

1. **Environment-Specific Parameters**: Create separate parameter files for dev/staging/prod
2. **Cross-Account Access**: Configure Service Catalog for cross-account deployments
3. **Advanced Constraints**: Implement Service Catalog template constraints for compliance
4. **Automated Testing**: Integrate with CI/CD pipelines for infrastructure validation

### Integration Patterns

1. **ServiceNow Integration**: Use AWS Service Management Connector for enterprise workflows
2. **Cross-Account Service Mesh**: Implement RAM sharing for multi-account service discovery
3. **Advanced Routing**: Configure weighted routing and path-based routing in VPC Lattice
4. **Compliance Monitoring**: Integrate with AWS Config for ongoing compliance validation

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment:

- **CloudFormation**: Modify parameters in the template
- **CDK**: Update configuration in `cdk.json` or use CDK context
- **Terraform**: Set variables in `terraform.tfvars` or use environment variables
- **Scripts**: Set environment variables before running deployment scripts

## Support

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation. For AWS-specific issues, consider using AWS Support or the AWS Developer Forums.