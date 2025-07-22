# Infrastructure as Code for Dynamic Content Delivery with Firebase Hosting and Cloud CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dynamic Content Delivery with Firebase Hosting and Cloud CDN".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (`gcloud`) v450+ installed and configured
- Firebase CLI v13+ installed (`npm install -g firebase-tools`)
- Node.js v18+ and npm for Cloud Functions development
- Appropriate Google Cloud permissions for resource creation
- Project with billing enabled

### Required APIs
- Firebase API (`firebase.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Compute Engine API (`compute.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

### Permissions Required
- Firebase Admin
- Cloud Functions Developer
- Storage Admin
- Compute Network Admin
- Project Editor (or equivalent granular permissions)

### Estimated Costs
- Firebase Hosting: Free tier includes 10GB storage + 360MB/day transfer
- Cloud Functions: $0.40/million invocations + $0.0000025/GB-second
- Cloud Storage: $0.020/GB/month for standard storage
- Cloud CDN: $0.08/GB for first 10TB/month
- Total estimated cost: $5-15 for testing this recipe

## Quick Start

### Using Infrastructure Manager

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/content-delivery-demo \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=demo,recipe=content-delivery"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/content-delivery-demo
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SITE_ID="cdn-demo-$(date +%s)"

# Run deployment script
./scripts/deploy.sh

# The script will output the hosting URL and other important information
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `site_id` | Firebase Hosting site ID | Generated | No |
| `environment` | Environment tag | `demo` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `location` | Multi-region location | `us-central` | No |
| `site_id` | Firebase Hosting site ID | Generated | No |
| `storage_bucket_name` | Cloud Storage bucket name | Generated | No |
| `enable_cdn` | Enable Cloud CDN | `true` | No |
| `cache_mode` | CDN cache mode | `CACHE_ALL_STATIC` | No |
| `default_ttl` | Default TTL in seconds | `3600` | No |
| `max_ttl` | Maximum TTL in seconds | `86400` | No |

Create a `terraform.tfvars` file with your specific values:

```hcl
project_id = "your-project-id"
region     = "us-central1"
site_id    = "my-cdn-demo"
```

## Deployment Architecture

The IaC implementations create the following resources:

### Core Infrastructure
- **Firebase Hosting Site**: Global CDN-enabled hosting platform
- **Cloud Functions**: Serverless backend for dynamic content
  - `getProducts`: Product catalog API with regional pricing
  - `getRecommendations`: User recommendation engine
- **Cloud Storage Bucket**: Media asset storage with CDN integration
- **Load Balancer**: Custom HTTP(S) load balancer with Cloud CDN

### Networking & Security
- **Backend Bucket**: Cloud Storage backend for load balancer
- **URL Map**: Traffic routing configuration
- **HTTP Proxy**: Target proxy for load balancer
- **Forwarding Rule**: Global IP address and traffic forwarding
- **IAM Roles**: Least-privilege service account permissions

### Monitoring & Analytics
- **Cloud Monitoring**: Infrastructure and application metrics
- **Firebase Analytics**: User engagement and performance tracking
- **Custom Dashboards**: CDN performance and cache hit ratio monitoring

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Test Firebase Hosting endpoint
curl -I "https://your-site-id.web.app"

# Test dynamic content APIs
curl "https://your-site-id.web.app/getProducts" | jq .

# Test CDN caching headers
curl -I "https://your-site-id.web.app/styles.css"

# Load test CDN performance
for i in {1..5}; do
  curl -w "Time: %{time_total}s\n" -o /dev/null -s "https://your-site-id.web.app"
done
```

## Monitoring & Observability

### Key Metrics to Monitor
- **Cache Hit Ratio**: Percentage of requests served from CDN cache
- **Response Times**: P50, P95, P99 response times globally
- **Error Rates**: 4xx and 5xx error percentages
- **Bandwidth Usage**: Data transfer costs and patterns
- **Function Invocations**: Backend processing load and costs

### Cloud Monitoring Queries

```sql
-- CDN Cache Hit Ratio
fetch https_lb_rule
| filter resource.backend_target_name =~ ".*backend"
| group_by 1m, [resource.backend_target_name]
| value val(cache_hit_rate)

-- Function Response Times
fetch cloud_function
| filter resource.function_name =~ "getProducts|getRecommendations"
| group_by 1m, [resource.function_name]
| value val(execution_time_nanos) / 1000000  # Convert to milliseconds
```

### Firebase Performance Monitoring

The web application includes Firebase Performance Monitoring to track:
- Page load times
- Network request latency
- First Contentful Paint (FCP)
- Largest Contentful Paint (LCP)
- Cumulative Layout Shift (CLS)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/content-delivery-demo \
    --delete-policy="DELETE"

# Verify resources are removed
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup (if needed)

```bash
# Delete Firebase Hosting site
firebase hosting:sites:delete your-site-id --force

# Delete Cloud Functions
gcloud functions delete getProducts --region=us-central1 --quiet
gcloud functions delete getRecommendations --region=us-central1 --quiet

# Delete Cloud Storage bucket
gsutil rm -r gs://your-storage-bucket

# Delete load balancer components
gcloud compute forwarding-rules delete cdn-forwarding-rule --global --quiet
gcloud compute target-http-proxies delete cdn-http-proxy --quiet
gcloud compute url-maps delete cdn-url-map --quiet
gcloud compute backend-buckets delete your-bucket-backend --quiet
```

## Customization

### Adding Custom Domains

To use custom domains with your Firebase Hosting site:

1. **Add domain in Firebase Console** or via CLI:
   ```bash
   firebase hosting:sites:get your-site-id
   # Follow prompts to add custom domain
   ```

2. **Update DNS records** as instructed by Firebase

3. **Configure SSL** (automatic with Firebase Hosting)

### Scaling Considerations

- **Cloud Functions**: Automatically scale based on demand
- **Firebase Hosting**: Globally distributed, handles millions of requests
- **Cloud Storage**: Unlimited storage capacity
- **Cloud CDN**: Global edge locations with automatic scaling

### Security Enhancements

For production deployments, consider:

1. **Cloud Armor WAF**: Add Web Application Firewall rules
2. **Identity-Aware Proxy**: Implement authenticated access
3. **VPC Service Controls**: Network-level security perimeters
4. **Cloud KMS**: Encryption key management for sensitive data
5. **Security Headers**: Additional HTTP security headers

### Performance Optimizations

1. **Image Optimization**: Implement WebP conversion and compression
2. **Brotli Compression**: Enable advanced compression algorithms
3. **HTTP/3**: Utilize latest protocol improvements
4. **Edge-Side Includes**: Dynamic content at edge locations
5. **Service Worker**: Client-side caching strategies

## Troubleshooting

### Common Issues

**Firebase Hosting deployment fails:**
```bash
# Check Firebase project configuration
firebase projects:list
firebase use your-project-id

# Verify authentication
firebase login --reauth
```

**Cloud Functions timeout:**
```bash
# Check function logs
gcloud functions logs read getProducts --limit 50

# Update timeout settings
gcloud functions deploy getProducts --timeout=60s
```

**CDN cache not working:**
```bash
# Verify backend bucket configuration
gcloud compute backend-buckets describe your-bucket-backend

# Check cache headers
curl -I -H "Cache-Control: no-cache" your-url
```

**Load balancer IP not accessible:**
```bash
# Check forwarding rule status
gcloud compute forwarding-rules describe cdn-forwarding-rule --global

# Verify DNS propagation
nslookup your-domain.com
```

### Debug Mode

Enable debug logging:

```bash
# For gcloud commands
export CLOUDSDK_CORE_LOG_LEVEL=debug

# For Firebase CLI
export DEBUG="firebase:*"

# For Terraform
export TF_LOG=DEBUG
```

## Support

### Documentation References
- [Firebase Hosting Documentation](https://firebase.google.com/docs/hosting)
- [Cloud CDN Documentation](https://cloud.google.com/cdn/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help
- [Google Cloud Support](https://cloud.google.com/support)
- [Firebase Support](https://firebase.google.com/support)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Community](https://www.googlecloudcommunity.com)

For issues specific to this infrastructure code, refer to the original recipe documentation or create an issue in the recipe repository.

## License

This infrastructure code is provided under the same license as the associated recipe documentation.