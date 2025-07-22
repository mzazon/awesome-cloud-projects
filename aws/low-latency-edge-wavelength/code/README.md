# Infrastructure as Code for Low-Latency Edge Applications with Wavelength

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Low-Latency Edge Applications with Wavelength".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for EC2, VPC, Route 53, CloudFront, and Wavelength services
- Access to a Wavelength Zone (requires carrier partnership and opt-in)
- Domain name registered for DNS configuration
- Appropriate IAM permissions for resource creation
- Estimated cost: $150-200 for running this infrastructure

> **Note**: Wavelength Zones are available in select metropolitan areas through carrier partnerships. Check [AWS Wavelength locations](https://aws.amazon.com/wavelength/locations/) for availability in your region.

## Architecture Overview

This infrastructure deploys a multi-tier edge computing architecture that combines:

- **AWS Wavelength Zone**: Ultra-low latency edge computing for 5G mobile applications
- **Amazon CloudFront**: Global content delivery network for static assets
- **Application Load Balancer**: High availability traffic distribution in Wavelength Zone
- **Amazon S3**: Scalable storage for static web assets
- **Amazon Route 53**: DNS management and intelligent traffic routing
- **VPC with Carrier Gateway**: Optimized networking for mobile traffic

## Quick Start

### Using CloudFormation

```bash
# Set required parameters
export DOMAIN_NAME="your-domain.com"  # Replace with your domain
export WAVELENGTH_ZONE="us-west-2-wl1-las-wlz-1"  # Replace with available zone

# Deploy the stack
aws cloudformation create-stack \
    --stack-name wavelength-edge-app \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=${DOMAIN_NAME} \
                 ParameterKey=WavelengthZone,ParameterValue=${WAVELENGTH_ZONE} \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name wavelength-edge-app
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export DOMAIN_NAME="your-domain.com"
export WAVELENGTH_ZONE="us-west-2-wl1-las-wlz-1"

# Deploy the stack
cdk deploy --parameters domainName=${DOMAIN_NAME} \
           --parameters wavelengthZone=${WAVELENGTH_ZONE}
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Set environment variables
export DOMAIN_NAME="your-domain.com"
export WAVELENGTH_ZONE="us-west-2-wl1-las-wlz-1"

# Deploy the stack
cdk deploy --parameters domainName=${DOMAIN_NAME} \
           --parameters wavelengthZone=${WAVELENGTH_ZONE}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Set variables (create terraform.tfvars file)
cat > terraform.tfvars << EOF
domain_name = "your-domain.com"
wavelength_zone = "us-west-2-wl1-las-wlz-1"
project_name = "edge-app"
EOF

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export DOMAIN_NAME="your-domain.com"
export WAVELENGTH_ZONE="us-west-2-wl1-las-wlz-1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

- **Domain Name**: Your registered domain name for DNS configuration
- **Wavelength Zone**: The Wavelength Zone to deploy edge resources (must be opted-in)

### Optional Parameters

- **Project Name**: Prefix for resource names (default: auto-generated)
- **Instance Type**: EC2 instance type for edge application (default: t3.medium)
- **S3 Bucket Name**: Custom name for static assets bucket (default: auto-generated)

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Test edge application latency
curl -w "Total time: %{time_total}s\n" http://[ALB_DNS]/health

# Test CloudFront static content delivery
curl -I https://[CLOUDFRONT_DOMAIN]/index.html

# Test API routing to Wavelength
curl https://[CLOUDFRONT_DOMAIN]/api/health

# Check Wavelength instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*wavelength*"
```

## Monitoring and Observability

The infrastructure includes monitoring capabilities:

- **CloudWatch Metrics**: Instance and load balancer health monitoring
- **ALB Health Checks**: Automatic health monitoring for edge applications
- **CloudFront Metrics**: Global content delivery performance tracking
- **VPC Flow Logs**: Network traffic analysis (optional)

## Security Features

- **Security Groups**: Restrictive ingress rules for edge and regional resources
- **Origin Access Control**: Secure S3 access through CloudFront only
- **HTTPS Enforcement**: CloudFront redirects HTTP to HTTPS
- **VPC Isolation**: Private networking between edge and regional components

## Performance Optimization

- **Edge Placement**: Applications deployed in Wavelength Zones for ultra-low latency
- **Intelligent Routing**: CloudFront routes static content globally, API calls to edge
- **Carrier Gateway**: Optimized mobile network connectivity
- **Auto Scaling**: Application Load Balancer supports multiple edge instances

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name wavelength-edge-app

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name wavelength-edge-app
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Wavelength Zone Not Available**
   - Verify the zone is opted-in: `aws ec2 describe-availability-zones --filters "Name=zone-type,Values=wavelength-zone"`
   - Check [AWS Wavelength locations](https://aws.amazon.com/wavelength/locations/) for availability

2. **CloudFront Distribution Deployment Time**
   - CloudFront distributions can take 15-20 minutes to deploy globally
   - Monitor status: `aws cloudfront get-distribution --id [DISTRIBUTION_ID]`

3. **DNS Propagation Delays**
   - DNS changes may take up to 48 hours to propagate globally
   - Test with `nslookup` or `dig` commands

4. **Instance Launch Failures**
   - Verify Wavelength Zone has capacity for selected instance type
   - Check security group and subnet configurations

### Resource Limits

- **Wavelength Zones**: Limited instance types available
- **CloudFront**: 200 distributions per account (default)
- **Route 53**: 500 hosted zones per account (default)
- **EC2**: Instance limits vary by region and zone

## Cost Optimization

- **Instance Right-Sizing**: Use appropriate instance types for workload requirements
- **CloudFront Pricing Class**: Consider regional pricing classes for cost optimization
- **Data Transfer**: Monitor data transfer costs between Wavelength and regional services
- **Resource Cleanup**: Always clean up resources after testing to avoid ongoing charges

## Advanced Configurations

### Multi-Zone Deployment

Deploy across multiple Wavelength Zones for regional coverage:

```bash
# Add additional zones to Terraform variables
wavelength_zones = [
  "us-west-2-wl1-las-wlz-1",
  "us-east-1-wl1-nyc-wlz-1"
]
```

### Custom Application Deployment

Replace the sample application with your own:

1. Update the user data script in the templates
2. Modify security group rules for your application ports
3. Configure health check paths for your application

### SSL/TLS Configuration

Add custom SSL certificates:

1. Upload certificates to AWS Certificate Manager
2. Configure CloudFront distribution to use custom certificates
3. Update Route 53 records for HTTPS endpoints

## Support and Documentation

- [AWS Wavelength Documentation](https://docs.aws.amazon.com/wavelength/)
- [Amazon CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)
- [Edge Computing Best Practices](https://docs.aws.amazon.com/whitepapers/latest/edge-computing/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Terraform Provider**: AWS ~> 5.0
- **CDK Version**: 2.x
- **CloudFormation**: 2010-09-09