# Terraform Infrastructure for Visual Infrastructure Composer Demo

This directory contains Terraform Infrastructure as Code (IaC) that creates the same infrastructure demonstrated in the "Visual Infrastructure Design with Application Composer and CloudFormation" recipe.

## Overview

This Terraform configuration creates an S3 bucket configured for static website hosting, which represents the same infrastructure that would be designed visually using AWS Infrastructure Composer. The key difference is that this implementation provides version control, automation, and repeatability through Infrastructure as Code.

## Architecture

The Terraform configuration creates:

- **S3 Bucket**: Configured for static website hosting with unique naming
- **Bucket Policy**: Allows public read access to website content
- **Website Configuration**: Sets index.html and error.html as default documents
- **Security Settings**: Enables server-side encryption and proper access controls
- **Sample Content**: Optional HTML files demonstrating website functionality
- **Monitoring**: Optional CloudWatch alarms for bucket monitoring

## Prerequisites

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** 1.5.0 or later installed
3. **AWS Account** with permissions for:
   - S3 bucket creation and management
   - IAM policy creation
   - CloudWatch alarm creation (if monitoring enabled)
4. **Permissions**: Ensure your AWS credentials have the necessary IAM permissions

## Quick Start

### 1. Initialize Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform (download providers and modules)
terraform init
```

### 2. Review and Customize Variables

```bash
# Copy the example variables file (if available)
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your requirements
nano terraform.tfvars
```

Example `terraform.tfvars` file:

```hcl
# Basic configuration
bucket_prefix = "my-visual-website"
environment   = "demo"

# Website settings
index_document = "index.html"
error_document = "error.html"
upload_sample_content = true

# Optional: Enable monitoring
enable_monitoring = true
sns_topic_arn    = "arn:aws:sns:us-east-1:123456789012:alerts"

# Additional tags
additional_tags = {
  Owner   = "your-name"
  Project = "infrastructure-demo"
}
```

### 3. Plan the Deployment

```bash
# Review what Terraform will create
terraform plan
```

### 4. Deploy the Infrastructure

```bash
# Apply the Terraform configuration
terraform apply

# Type 'yes' when prompted to confirm
```

### 5. Access Your Website

After deployment, Terraform will output the website URL:

```bash
# Get the website URL from Terraform outputs
terraform output website_url

# Test the website
curl -I $(terraform output -raw website_url)
```

## Configuration Options

### Basic Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `bucket_prefix` | Prefix for S3 bucket name | `"my-visual-website"` | No |
| `environment` | Environment name for tagging | `"demo"` | No |
| `index_document` | Default webpage filename | `"index.html"` | No |
| `error_document` | 404 error page filename | `"error.html"` | No |

### Advanced Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `upload_sample_content` | Upload demo HTML files | `true` | No |
| `enable_versioning` | Enable S3 bucket versioning | `false` | No |
| `enable_monitoring` | Enable CloudWatch monitoring | `false` | No |
| `sns_topic_arn` | SNS topic for alarm notifications | `""` | No |

### Security Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `force_destroy` | Allow bucket deletion with objects | `false` | No |
| `content_security_policy` | CSP header for enhanced security | `"default-src 'self'"` | No |

## Outputs

After deployment, the following outputs are available:

```bash
# Get all outputs
terraform output

# Get specific outputs
terraform output website_url
terraform output bucket_name
terraform output region
```

Key outputs include:

- **website_url**: The URL to access your static website
- **bucket_name**: The name of the created S3 bucket
- **test_commands**: Useful CLI commands for testing
- **quick_start_guide**: Step-by-step usage instructions

## Testing and Validation

### Automated Testing

```bash
# Test website accessibility
curl -I $(terraform output -raw website_url)

# Test 404 error page
curl -I $(terraform output -raw website_url)/nonexistent

# List bucket contents
aws s3 ls s3://$(terraform output -raw bucket_name)/

# Check bucket website configuration
aws s3api get-bucket-website --bucket $(terraform output -raw bucket_name)
```

### Manual Testing

1. **Visit Website**: Open the website URL in your browser
2. **Test 404 Page**: Try accessing a non-existent page
3. **Upload Content**: Add your own HTML files to the bucket
4. **Monitor Alarms**: Check CloudWatch alarms (if enabled)

## Customization

### Adding Your Own Content

Replace the sample content with your own:

```bash
# Upload your index.html
aws s3 cp my-index.html s3://$(terraform output -raw bucket_name)/index.html

# Upload additional files
aws s3 sync ./my-website/ s3://$(terraform output -raw bucket_name)/
```

### Enabling Advanced Features

1. **CloudFront Distribution**: Add CloudFront for global CDN
2. **Custom Domain**: Configure Route 53 and SSL certificates
3. **CI/CD Pipeline**: Integrate with CodePipeline for automated deployments
4. **Monitoring**: Enable detailed CloudWatch monitoring and alerting

### Environment-Specific Deployments

```bash
# Deploy to different environments
terraform workspace new staging
terraform workspace new production

# Deploy with environment-specific variables
terraform apply -var-file="staging.tfvars"
terraform apply -var-file="production.tfvars"
```

## Cleanup

### Remove All Resources

```bash
# Destroy all created resources
terraform destroy

# Type 'yes' when prompted to confirm
```

### Selective Cleanup

```bash
# Remove only specific resources
terraform destroy -target=aws_s3_object.index
terraform destroy -target=aws_s3_object.error
```

### Force Cleanup (if bucket has content)

If the bucket contains additional files:

```bash
# Empty the bucket first
aws s3 rm s3://$(terraform output -raw bucket_name) --recursive

# Then destroy
terraform destroy
```

## Troubleshooting

### Common Issues

1. **Bucket Name Conflicts**
   ```bash
   # Solution: Change bucket_prefix variable
   terraform apply -var="bucket_prefix=my-unique-website"
   ```

2. **Permission Errors**
   ```bash
   # Solution: Check AWS credentials and permissions
   aws sts get-caller-identity
   aws iam get-user
   ```

3. **Website Not Accessible**
   ```bash
   # Check bucket policy and public access settings
   aws s3api get-bucket-policy --bucket $(terraform output -raw bucket_name)
   aws s3api get-public-access-block --bucket $(terraform output -raw bucket_name)
   ```

### Debug Mode

```bash
# Enable debug logging
export TF_LOG=DEBUG
terraform apply

# View detailed logs
export TF_LOG_PATH=terraform.log
terraform apply
```

## Security Considerations

### Best Practices

1. **State File Security**: Store Terraform state in encrypted S3 backend
2. **Credential Management**: Use IAM roles instead of access keys
3. **Least Privilege**: Apply minimal required permissions
4. **Resource Tagging**: Tag all resources for governance
5. **Monitoring**: Enable CloudTrail and CloudWatch logging

### Production Deployment

For production environments:

```hcl
# terraform.tfvars for production
environment = "prod"
enable_versioning = true
enable_monitoring = true
force_destroy = false
```

## Contributing

To contribute improvements to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed descriptions

## Support

For issues with this Terraform implementation:

1. Check the [troubleshooting section](#troubleshooting)
2. Review AWS S3 and CloudFormation documentation
3. Consult the original recipe documentation
4. Open an issue in the repository

## Related Resources

- [AWS Infrastructure Composer Documentation](https://docs.aws.amazon.com/infrastructure-composer/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)
- [AWS S3 Static Website Hosting Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [Original Recipe: Visual Infrastructure Design with Application Composer](../visual-infrastructure-composer-cloudformation.md)