# VPC Lattice TLS Passthrough - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying the complete VPC Lattice TLS Passthrough solution from the recipe "End-to-End Encryption with VPC Lattice TLS Passthrough".

## Architecture Overview

This Terraform configuration deploys:

- **VPC Infrastructure**: VPC, subnet, internet gateway, route table, and security group
- **Certificate Management**: ACM certificate with DNS validation and self-signed certificates for targets
- **Target Infrastructure**: EC2 instances configured with Apache HTTPS servers
- **VPC Lattice Components**: Service network, service, target group, and TLS passthrough listener
- **DNS Configuration**: Route 53 hosted zone and CNAME records (optional)

## Prerequisites

### Required Tools
- Terraform >= 1.5
- AWS CLI v2 configured with appropriate credentials
- A registered domain name for SSL certificate validation

### Required AWS Permissions
Your AWS credentials must have permissions for:
- VPC, EC2, and networking resources
- VPC Lattice service management
- AWS Certificate Manager (ACM)
- Route 53 (if managing DNS)
- IAM roles and policies

### Cost Considerations
Estimated costs for this demo:
- EC2 instances (2x t3.micro): ~$15/month
- VPC Lattice service: ~$10/month
- ACM certificate: Free
- Route 53 hosted zone: $0.50/month
- **Total estimated cost**: ~$25-30/month

## Quick Start

### 1. Clone and Initialize

```bash
# Navigate to the Terraform directory
cd aws/tls-passthrough-lattice-acm/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required: Your domain configuration
custom_domain_name = "api-service.yourdomain.com"
certificate_domain = "*.yourdomain.com"

# Optional: Environment and naming
environment = "demo"

# Optional: Infrastructure sizing
instance_type         = "t3.micro"
target_instance_count = 2

# Optional: DNS management
create_route53_zone = false  # Set to true if you want Terraform to manage DNS
route53_zone_id     = "Z1EXAMPLE"  # Required if create_route53_zone = false

# Optional: Certificate management
create_certificate = true   # Set to false if using existing certificate
# certificate_arn = "arn:aws:acm:region:account:certificate/12345"  # Required if create_certificate = false
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Complete Certificate Validation

After applying, you'll need to validate the ACM certificate:

1. **Get validation records**:
   ```bash
   terraform output certificate_validation_records
   ```

2. **Create DNS records**: Add the displayed DNS validation records to your domain's DNS configuration

3. **Wait for validation**: The certificate status will change to "ISSUED" within 5-10 minutes

4. **Verify deployment**:
   ```bash
   # Check certificate status
   terraform output certificate_status
   
   # Test the endpoint (after certificate validation)
   terraform output test_commands
   ```

## Configuration Options

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `custom_domain_name` | Domain name for the VPC Lattice service | `"api-service.example.com"` | Yes |
| `certificate_domain` | Domain for SSL certificate (can use wildcard) | `"*.example.com"` | Yes |

### Infrastructure Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name for tagging | `"demo"` |
| `vpc_cidr` | CIDR block for VPC | `"10.0.0.0/16"` |
| `subnet_cidr` | CIDR block for subnet | `"10.0.1.0/24"` |
| `instance_type` | EC2 instance type | `"t3.micro"` |
| `target_instance_count` | Number of target instances | `2` |

### Certificate Management

| Variable | Description | Default |
|----------|-------------|---------|
| `create_certificate` | Create new ACM certificate | `true` |
| `certificate_arn` | Existing certificate ARN | `""` |

### DNS Management

| Variable | Description | Default |
|----------|-------------|---------|
| `create_route53_zone` | Create Route 53 hosted zone | `false` |
| `route53_zone_id` | Existing hosted zone ID | `""` |

### Security and Monitoring

| Variable | Description | Default |
|----------|-------------|---------|
| `allowed_cidr_blocks` | CIDRs allowed to access targets | `["10.0.0.0/8"]` |
| `enable_detailed_monitoring` | Enable detailed CloudWatch monitoring | `false` |
| `health_check_grace_period` | Health check grace period (seconds) | `300` |

## Outputs

The configuration provides comprehensive outputs including:

- **Infrastructure IDs**: VPC, subnet, security group, instance IDs
- **VPC Lattice Resources**: Service network, service, target group, listener ARNs
- **Certificate Information**: ARN, status, validation records
- **DNS Configuration**: Hosted zone ID, name servers
- **Testing Commands**: Ready-to-use curl and openssl commands
- **Deployment Notes**: Step-by-step completion instructions

View all outputs:
```bash
terraform output
```

View specific output:
```bash
terraform output deployment_notes
terraform output test_commands
```

## Testing the Deployment

### 1. Verify Target Health

```bash
# Check target group health
aws vpc-lattice list-targets --target-group-identifier $(terraform output -raw target_group_id)
```

### 2. Test HTTPS Connectivity

```bash
# Test with curl (ignore certificate warnings for self-signed target certs)
curl -k -v https://$(terraform output -raw custom_domain_name)

# Verify TLS handshake details
openssl s_client -connect $(terraform output -raw custom_domain_name):443 \
    -servername $(terraform output -raw custom_domain_name) </dev/null
```

### 3. Load Balancing Test

```bash
# Test multiple requests to verify load balancing
for i in {1..5}; do
    echo "Request $i:"
    curl -k -s https://$(terraform output -raw custom_domain_name) | grep -E "(Instance ID|Timestamp)"
    sleep 2
done
```

## Troubleshooting

### Common Issues

1. **Certificate Validation Pending**
   - Verify DNS validation records are created correctly
   - Check domain ownership and DNS propagation
   - Wait up to 30 minutes for validation

2. **Target Instances Unhealthy**
   - Check security group rules allow traffic on port 443
   - Verify Apache is running: `systemctl status httpd`
   - Check instance logs: `/var/log/user-data.log`

3. **DNS Resolution Issues**
   - Verify CNAME record points to VPC Lattice service DNS name
   - Check DNS propagation with `nslookup` or `dig`
   - Confirm hosted zone is properly configured

4. **Connection Timeouts**
   - Verify VPC routes and internet gateway configuration
   - Check NACL rules (default should allow)
   - Confirm VPC Lattice service network associations

### Debug Commands

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn $(terraform output -raw certificate_arn)

# Verify VPC Lattice service
aws vpc-lattice get-service --service-identifier $(terraform output -raw service_id)

# Check target health
aws vpc-lattice list-targets --target-group-identifier $(terraform output -raw target_group_id)

# View instance logs (via SSM if configured)
aws ssm start-session --target $(terraform output -raw target_instance_ids | jq -r '.[0]')
```

## Security Considerations

### Production Recommendations

1. **Certificate Management**
   - Use proper certificates from trusted CAs in production
   - Implement certificate rotation automation
   - Monitor certificate expiration

2. **Network Security**
   - Restrict security group rules to minimum required access
   - Use private subnets for target instances in production
   - Implement VPC endpoints for AWS services

3. **Access Control**
   - Enable VPC Lattice authentication policies
   - Use IAM roles for EC2 instances
   - Implement least privilege principles

4. **Monitoring**
   - Enable VPC Flow Logs
   - Configure CloudWatch alarms for target health
   - Set up certificate expiration monitoring

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy
```

### Manual Cleanup (if needed)

If some resources fail to destroy:

```bash
# Check for remaining VPC Lattice resources
aws vpc-lattice list-services
aws vpc-lattice list-service-networks

# Remove certificate (if created externally)
aws acm delete-certificate --certificate-arn CERTIFICATE_ARN

# Remove Route 53 hosted zone (if created externally)
aws route53 delete-hosted-zone --id HOSTED_ZONE_ID
```

## Advanced Configuration

### Using Existing Certificate

```hcl
# terraform.tfvars
create_certificate = false
certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
```

### Using Existing DNS Zone

```hcl
# terraform.tfvars
create_route53_zone = false
route53_zone_id     = "Z1D633PJN98FT9"
```

### Custom Instance Configuration

```hcl
# terraform.tfvars
instance_type                = "t3.small"
target_instance_count        = 3
enable_detailed_monitoring   = true
health_check_grace_period    = 600
```

### Multiple AZ Deployment

To deploy across multiple AZs, modify the main.tf file to create subnets in different availability zones and distribute instances accordingly.

## Support and References

- **Original Recipe**: [End-to-End Encryption with VPC Lattice TLS Passthrough](../tls-passthrough-lattice-acm.md)
- **AWS VPC Lattice Documentation**: [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- **AWS Certificate Manager**: [ACM User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- **Terraform AWS Provider**: [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this Terraform configuration, please refer to the original recipe documentation or AWS service documentation.