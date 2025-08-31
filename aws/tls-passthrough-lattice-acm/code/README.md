# Infrastructure as Code for End-to-End Encryption with VPC Lattice TLS Passthrough

This directory contains Infrastructure as Code (IaC) implementations for the recipe "End-to-End Encryption with VPC Lattice TLS Passthrough".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete end-to-end TLS encryption solution using:
- VPC Lattice Service Network for service mesh capabilities
- Certificate Manager for SSL/TLS certificate management
- Route 53 for DNS resolution and service discovery
- EC2 instances as target applications with HTTPS endpoints
- TLS passthrough configuration maintaining encryption integrity

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - VPC Lattice (service networks, services, listeners, target groups)
  - Certificate Manager (certificate management)
  - Route 53 (hosted zones, DNS records)
  - EC2 (instances, VPC, security groups)
  - IAM (roles and policies for services)
- A registered domain name for SSL certificate validation
- Basic understanding of TLS/SSL and DNS configuration

### Cost Considerations

Estimated cost for testing: $25-50 (includes EC2 instances, VPC Lattice service, certificates)
- VPC Lattice: ~$0.025 per hour per service + data processing charges
- EC2 t3.micro instances: ~$0.0104 per hour per instance
- Certificate Manager: Free for AWS-issued certificates
- Route 53: $0.50 per hosted zone per month + query charges

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name tls-passthrough-lattice \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=CustomDomain,ParameterValue=api-service.example.com \
                 ParameterKey=CertificateDomain,ParameterValue=*.example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name tls-passthrough-lattice \
    --query 'Stacks[0].StackStatus'

# Get output values
aws cloudformation describe-stacks \
    --stack-name tls-passthrough-lattice \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export CDK_DEFAULT_REGION=us-east-1
export CUSTOM_DOMAIN=api-service.example.com
export CERTIFICATE_DOMAIN=*.example.com

# Deploy the infrastructure
cdk bootstrap  # First time only
cdk deploy --parameters CustomDomain=${CUSTOM_DOMAIN} \
           --parameters CertificateDomain=${CERTIFICATE_DOMAIN}

# View stack outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Set up virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment parameters
export CDK_DEFAULT_REGION=us-east-1
export CUSTOM_DOMAIN=api-service.example.com
export CERTIFICATE_DOMAIN=*.example.com

# Deploy the infrastructure
cdk bootstrap  # First time only
cdk deploy --parameters CustomDomain=${CUSTOM_DOMAIN} \
           --parameters CertificateDomain=${CERTIFICATE_DOMAIN}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="custom_domain=api-service.example.com" \
              -var="certificate_domain=*.example.com" \
              -var="aws_region=us-east-1"

# Deploy infrastructure
terraform apply -var="custom_domain=api-service.example.com" \
               -var="certificate_domain=*.example.com" \
               -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CUSTOM_DOMAIN=api-service.example.com
export CERTIFICATE_DOMAIN=*.example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

### 1. Certificate Validation

After deployment, you must validate the SSL certificate:

1. Navigate to AWS Certificate Manager console
2. Find your certificate and note the DNS validation records
3. Add the CNAME records to your domain's DNS provider
4. Wait for validation to complete (typically 5-10 minutes)

### 2. DNS Configuration

If using your own domain, configure DNS to point to the generated infrastructure:

```bash
# Get the VPC Lattice service DNS name from outputs
SERVICE_DNS_NAME=$(aws cloudformation describe-stacks \
    --stack-name tls-passthrough-lattice \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceDnsName`].OutputValue' \
    --output text)

# Create CNAME record in your DNS provider
# api-service.example.com CNAME ${SERVICE_DNS_NAME}
```

## Validation & Testing

### Test TLS Passthrough Functionality

```bash
# Wait for certificate validation and DNS propagation
sleep 300

# Test HTTPS connectivity (may need -k flag for self-signed target certificates)
curl -k -v https://api-service.example.com

# Verify TLS handshake details
openssl s_client -connect api-service.example.com:443 \
    -servername api-service.example.com </dev/null 2>/dev/null | \
    grep -E "(subject|issuer)"

# Test load balancing with multiple requests
for i in {1..5}; do
    echo "Request $i:"
    curl -k -s https://api-service.example.com | grep "Instance ID"
    sleep 2
done
```

### Verify Infrastructure Health

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service \
    --service-identifier $(aws cloudformation describe-stacks \
        --stack-name tls-passthrough-lattice \
        --query 'Stacks[0].Outputs[?OutputKey==`ServiceArn`].OutputValue' \
        --output text) \
    --query 'status'

# Check target health
aws vpc-lattice list-targets \
    --target-group-identifier $(aws cloudformation describe-stacks \
        --stack-name tls-passthrough-lattice \
        --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
        --output text) \
    --query 'items[*].{Id:id,Status:status}' \
    --output table
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (removes all resources)
aws cloudformation delete-stack \
    --stack-name tls-passthrough-lattice

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name tls-passthrough-lattice \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="custom_domain=api-service.example.com" \
                 -var="certificate_domain=*.example.com" \
                 -var="aws_region=us-east-1"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Key Parameters

- **CustomDomain**: The custom domain name for your service (e.g., api-service.example.com)
- **CertificateDomain**: The domain pattern for SSL certificate (e.g., *.example.com)
- **InstanceType**: EC2 instance type for target applications (default: t3.micro)
- **VpcCidr**: CIDR block for the VPC (default: 10.0.0.0/16)
- **AvailabilityZone**: AZ for target instances (default: {region}a)

### Environment-Specific Configurations

#### Development Environment
```bash
# Use smaller instance types and basic monitoring
terraform apply -var="instance_type=t3.micro" \
               -var="enable_detailed_monitoring=false"
```

#### Production Environment
```bash
# Use larger instances with enhanced monitoring
terraform apply -var="instance_type=t3.small" \
               -var="enable_detailed_monitoring=true" \
               -var="enable_backup=true"
```

### Security Customizations

#### Enhanced Security Group Rules
Modify the security group to restrict access to specific IP ranges:

```bash
# Edit terraform/variables.tf to include allowed_cidr_blocks
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the service"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
```

#### Custom Certificate Authority
For enterprise environments, you can modify the configuration to use private certificates:

```bash
# Update target instance user data to use corporate CA certificates
# Modify the SSL configuration in user-data scripts
```

## Troubleshooting

### Common Issues

#### Certificate Validation Fails
```bash
# Check certificate status
aws acm describe-certificate \
    --certificate-arn <certificate-arn> \
    --query 'Certificate.Status'

# Verify DNS validation records are correctly configured
aws acm describe-certificate \
    --certificate-arn <certificate-arn> \
    --query 'Certificate.DomainValidationOptions'
```

#### Target Instances Unhealthy
```bash
# Check target health status
aws vpc-lattice list-targets \
    --target-group-identifier <target-group-arn>

# Verify security group allows port 443
aws ec2 describe-security-groups \
    --group-ids <security-group-id> \
    --query 'SecurityGroups[0].IpPermissions'

# Check instance system logs
aws ec2 get-console-output --instance-id <instance-id>
```

#### DNS Resolution Issues
```bash
# Test DNS resolution
nslookup api-service.example.com

# Check Route 53 records
aws route53 list-resource-record-sets \
    --hosted-zone-id <hosted-zone-id> \
    --query 'ResourceRecordSets[?Name==`api-service.example.com.`]'
```

### Debug Mode

Enable debug logging in bash scripts:
```bash
export DEBUG=true
./scripts/deploy.sh
```

## Architecture Notes

### TLS Passthrough Benefits
- **End-to-End Encryption**: Traffic remains encrypted from client to target
- **Compliance**: Meets strict regulatory requirements (PCI DSS, HIPAA)
- **Performance**: Reduced latency from eliminated TLS termination/re-encryption
- **Security**: No intermediate certificate exposure or decryption points

### Service Mesh Advantages
- **Service Discovery**: Automatic service registration and DNS-based discovery
- **Load Balancing**: Intelligent traffic distribution across healthy targets
- **Health Monitoring**: TCP-level health checks for encrypted traffic
- **Access Control**: Fine-grained IAM-based access policies

### Scalability Considerations
- **Target Group Scaling**: Supports dynamic target registration/deregistration
- **Cross-VPC Communication**: Service network enables multi-VPC architectures
- **Regional Distribution**: Can be extended to multi-region deployments
- **Performance Monitoring**: CloudWatch integration for observability

## Security Best Practices

1. **Certificate Management**: Use ACM for automated certificate renewal
2. **Access Control**: Implement least-privilege IAM policies
3. **Network Security**: Configure security groups with minimal required access
4. **Monitoring**: Enable CloudTrail and VPC Flow Logs for audit trails
5. **Encryption**: Ensure all data is encrypted in transit and at rest

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS VPC Lattice documentation: https://docs.aws.amazon.com/vpc-lattice/
3. Consult AWS Certificate Manager best practices: https://docs.aws.amazon.com/acm/latest/userguide/acm-bestpractices.html
4. Reference AWS Well-Architected Security Pillar: https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/

## Contributing

When modifying this infrastructure code:
- Follow AWS best practices and security guidelines
- Test deployments in development environments first
- Update documentation to reflect any changes
- Consider backward compatibility for existing deployments