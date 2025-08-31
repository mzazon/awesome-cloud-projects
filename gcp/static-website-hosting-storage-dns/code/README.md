# Infrastructure as Code for Static Website Hosting with Cloud Storage and DNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Static Website Hosting with Cloud Storage and DNS".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - Storage Admin
  - DNS Administrator
  - Service Usage Admin
- A registered domain name (configured with your domain registrar)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native Infrastructure as Code service that uses standard Terraform configuration with enhanced Google Cloud integration.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export DOMAIN_NAME="your-domain.com"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply \
    infrastructure-manager/main.yaml \
    --location=${REGION} \
    --deployment-id=static-website-hosting \
    --input-values="project_id=${PROJECT_ID},domain_name=${DOMAIN_NAME}"
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive ecosystem support for infrastructure management.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables (create terraform.tfvars or use -var flags)
echo "project_id = \"your-project-id\"" > terraform.tfvars
echo "domain_name = \"your-domain.com\"" >> terraform.tfvars
echo "region = \"us-central1\"" >> terraform.tfvars

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

Bash scripts provide direct CLI commands for manual deployment and learning purposes.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export DOMAIN_NAME="your-domain.com"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Upload sample website content (optional)
./scripts/upload-content.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `domain_name` | Domain name for the website | - | Yes |
| `region` | Google Cloud region | `us-central1` | No |
| `storage_class` | Cloud Storage class | `STANDARD` | No |
| `dns_ttl` | DNS record TTL in seconds | `300` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | `string` | - | Yes |
| `domain_name` | Domain name for the website | `string` | - | Yes |
| `region` | Google Cloud region | `string` | `us-central1` | No |
| `storage_class` | Cloud Storage class | `string` | `STANDARD` | No |
| `dns_ttl` | DNS record TTL in seconds | `number` | `300` | No |
| `enable_versioning` | Enable bucket versioning | `bool` | `false` | No |

### Environment Variables for Bash Scripts

| Variable | Description | Example |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud project ID | `my-website-project` |
| `DOMAIN_NAME` | Your domain name | `example.com` |
| `REGION` | Google Cloud region | `us-central1` |
| `BUCKET_NAME` | Storage bucket name (auto-set to domain) | `example.com` |

## Post-Deployment Configuration

### DNS Name Server Configuration

After deploying the infrastructure, you must configure your domain registrar to use Google Cloud DNS name servers:

1. **Get the name servers**:
   ```bash
   # For Infrastructure Manager deployment
   gcloud infra-manager deployments describe static-website-hosting \
       --location=${REGION} \
       --format="value(outputs.name_servers.value[])"
   
   # For Terraform deployment
   terraform output name_servers
   
   # For Bash deployment
   gcloud dns managed-zones describe ${DNS_ZONE_NAME} \
       --format="value(nameServers[])"
   ```

2. **Configure with your domain registrar**:
   - Log into your domain registrar's control panel
   - Navigate to DNS or Name Server settings
   - Replace existing name servers with the Google Cloud DNS name servers
   - Save the configuration

3. **Verify DNS propagation** (may take 24-48 hours):
   ```bash
   # Check DNS resolution
   nslookup ${DOMAIN_NAME}
   
   # Test website access
   curl -I http://${DOMAIN_NAME}
   ```

### Content Upload

Upload your website content to the created storage bucket:

```bash
# Upload files with cache control headers
gsutil -h "Cache-Control:public, max-age=3600" \
    cp index.html gs://${DOMAIN_NAME}/

gsutil -h "Cache-Control:public, max-age=3600" \
    cp 404.html gs://${DOMAIN_NAME}/

# Upload additional assets
gsutil -h "Cache-Control:public, max-age=86400" \
    cp -r assets/* gs://${DOMAIN_NAME}/assets/
```

## Validation and Testing

### Infrastructure Validation

1. **Verify bucket configuration**:
   ```bash
   # Check bucket website settings
   gsutil web get gs://${DOMAIN_NAME}
   
   # Verify public access
   gsutil iam get gs://${DOMAIN_NAME}
   ```

2. **Test DNS configuration**:
   ```bash
   # List DNS records
   gcloud dns record-sets list --zone=${DNS_ZONE_NAME}
   
   # Test DNS resolution
   dig ${DOMAIN_NAME} CNAME
   ```

3. **Test website access**:
   ```bash
   # Test direct storage access
   curl -I "https://storage.googleapis.com/${DOMAIN_NAME}/index.html"
   
   # Test domain access (after DNS propagation)
   curl -I "http://${DOMAIN_NAME}"
   ```

### Performance Testing

```bash
# Test page load performance
curl -w "@curl-format.txt" -o /dev/null -s "http://${DOMAIN_NAME}"

# Create curl format file for timing
cat > curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete static-website-hosting \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud storage buckets list --filter="name:${DOMAIN_NAME}"
gcloud dns managed-zones list --filter="dnsName:${DOMAIN_NAME}."
```

## Troubleshooting

### Common Issues

1. **Domain not resolving**:
   - Verify DNS name servers are configured with domain registrar
   - Check DNS propagation status (can take 24-48 hours)
   - Ensure CNAME record points to `c.storage.googleapis.com.`

2. **403 Forbidden errors**:
   - Verify bucket has public read permissions
   - Check that `allUsers` has `objectViewer` role on bucket
   - Ensure bucket name exactly matches domain name

3. **404 errors for website**:
   - Verify bucket is configured for website hosting
   - Check that `index.html` and `404.html` are uploaded
   - Ensure website configuration is set correctly

4. **Terraform state issues**:
   ```bash
   # Refresh Terraform state
   terraform refresh
   
   # Import existing resources if needed
   terraform import google_storage_bucket.website_bucket ${DOMAIN_NAME}
   ```

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:(storage OR dns)"

# Verify permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check bucket configuration
gsutil ls -L -b gs://${DOMAIN_NAME}

# Test DNS from different locations
for server in 8.8.8.8 1.1.1.1 208.67.222.222; do
    echo "Testing DNS server: $server"
    nslookup ${DOMAIN_NAME} $server
done
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege Access**: Bucket configured with minimum required permissions
- **Public Read Only**: Website content is publicly readable but not writable
- **Audit Logging**: All resource access is logged through Google Cloud Audit Logs
- **Resource-Level IAM**: Granular permissions applied to individual resources

### Additional Security Enhancements

1. **Enable Cloud Armor** for DDoS protection:
   ```bash
   # Create security policy
   gcloud compute security-policies create website-security-policy
   ```

2. **Implement Content Security Policy** headers:
   ```bash
   # Add CSP headers to uploaded content
   gsutil -h "Content-Security-Policy:default-src 'self'" \
       cp index.html gs://${DOMAIN_NAME}/
   ```

3. **Monitor access patterns**:
   ```bash
   # Set up log monitoring
   gcloud logging sinks create website-access-sink \
       storage.googleapis.com/logs-bucket \
       --log-filter='resource.type="gcs_bucket"'
   ```

## Cost Optimization

### Estimated Costs

- **Cloud Storage**: $0.020 per GB/month (Standard class)
- **Cloud DNS**: $0.20 per hosted zone/month + $0.40 per million queries
- **Network Egress**: $0.12 per GB (first TB free monthly)

### Cost Reduction Strategies

1. **Use appropriate storage class**:
   ```bash
   # For infrequently accessed content
   gsutil lifecycle set lifecycle.json gs://${DOMAIN_NAME}
   ```

2. **Implement cache headers** to reduce egress:
   ```bash
   # Set long cache times for static assets
   gsutil -h "Cache-Control:public, max-age=31536000" \
       cp assets/* gs://${DOMAIN_NAME}/assets/
   ```

3. **Monitor usage** with Cloud Monitoring:
   ```bash
   # Create billing alerts
   gcloud alpha billing budgets create \
       --billing-account=${BILLING_ACCOUNT_ID} \
       --display-name="Static Website Budget" \
       --budget-amount=10.00
   ```

## Customization

### Adding HTTPS Support

To add HTTPS support, consider upgrading to use Cloud Load Balancer:

```bash
# Reserve static IP
gcloud compute addresses create website-ip --global

# Create load balancer configuration
gcloud compute backend-buckets create website-backend \
    --gcs-bucket-name=${DOMAIN_NAME}

# Create URL map
gcloud compute url-maps create website-map \
    --default-backend-bucket=website-backend
```

### Content Versioning

Enable bucket versioning for content history:

```bash
# Enable versioning
gsutil versioning set on gs://${DOMAIN_NAME}

# List object versions
gsutil ls -a gs://${DOMAIN_NAME}/
```

### Multiple Environment Support

Customize for different environments (dev, staging, prod):

```bash
# Use environment-specific variables
export ENVIRONMENT="staging"
export DOMAIN_NAME="${ENVIRONMENT}.example.com"
export PROJECT_ID="${PROJECT_ID}-${ENVIRONMENT}"
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Google Cloud documentation:
   - [Cloud Storage Static Website Hosting](https://cloud.google.com/storage/docs/hosting-static-website)
   - [Cloud DNS Documentation](https://cloud.google.com/dns/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. Review Terraform Google Cloud Provider documentation
4. Check Google Cloud Status page for service issues

## Contributing

When modifying this infrastructure code:

1. Test changes in a separate project first
2. Update variable descriptions and documentation
3. Validate with `terraform plan` or Infrastructure Manager dry-run
4. Update this README with any new configuration options
5. Test cleanup procedures to ensure complete resource removal