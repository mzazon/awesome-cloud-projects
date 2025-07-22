# Edge-to-Cloud Video Analytics Infrastructure

This Terraform configuration deploys a comprehensive video analytics platform on Google Cloud Platform, combining Media CDN for global content delivery with Vertex AI for intelligent video analysis.

## Architecture Overview

The infrastructure creates an end-to-end video analytics pipeline:

- **Cloud Storage**: Video content storage and CDN origin
- **Media CDN**: Global edge caching and content delivery
- **Cloud Functions**: Event-driven video processing pipeline
- **Vertex AI**: Advanced video intelligence and analytics
- **Cloud Monitoring**: Comprehensive monitoring and alerting

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk) >= 400.0.0
- [Git](https://git-scm.com/) for version control

### Google Cloud Setup

1. **Create or select a GCP project**:
   ```bash
   gcloud projects create your-project-id
   gcloud config set project your-project-id
   ```

2. **Enable billing** for the project in the [GCP Console](https://console.cloud.google.com/billing)

3. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

4. **Set default region and zone**:
   ```bash
   gcloud config set compute/region us-central1
   gcloud config set compute/zone us-central1-a
   ```

### Required Permissions

Your account needs the following IAM roles:
- Project Editor or Owner
- Storage Admin
- Cloud Functions Admin
- Vertex AI Admin
- Compute Network Admin
- Service Account Admin

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd gcp/edge-to-cloud-video-analytics-media-cdn-vertex-ai/code/terraform

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit Configuration

Edit `terraform.tfvars` with your project-specific values:

```hcl
# Required: Replace with your project ID
project_id = "your-gcp-project-id"

# Required: Replace with your domain for CDN
cdn_domain_name = "video-cdn.yourdomain.com"

# Optional: Customize for your environment
bucket_prefix = "your-org-video-analytics"
notification_email = "alerts@yourdomain.com"
environment = "production"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var-file="terraform.tfvars"

# Deploy the infrastructure
terraform apply -var-file="terraform.tfvars"
```

### 4. Post-Deployment Setup

1. **Configure DNS** (if using custom domain):
   ```bash
   # Get the CDN IP address from Terraform output
   terraform output media_cdn
   
   # Create DNS A record pointing your domain to the CDN IP
   ```

2. **Test video upload**:
   ```bash
   # Upload a test video
   gsutil cp test-video.mp4 gs://$(terraform output -raw video_content_bucket.name)/videos/
   
   # Monitor processing in Cloud Console
   ```

## Configuration Options

### Storage Configuration

```hcl
# Storage settings
bucket_prefix = "video-analytics"        # Globally unique prefix
storage_class = "STANDARD"               # STANDARD, NEARLINE, COLDLINE, ARCHIVE
enable_versioning = true                 # Object versioning
lifecycle_management = true              # Automatic lifecycle policies
```

### Cloud Functions Configuration

```hcl
# Function settings
function_runtime = "python39"            # python39, python310, python311
function_memory = "1Gi"                  # 128Mi to 32Gi
function_timeout = 540                   # 1-540 seconds
max_instances = 10                       # Maximum concurrent instances
```

### Vertex AI Configuration

```hcl
# Video analysis features
video_analysis_features = [
  "OBJECT_TRACKING",                     # Track objects across frames
  "LABEL_DETECTION",                     # Identify content labels
  "SHOT_CHANGE_DETECTION",               # Detect scene changes
  "TEXT_DETECTION"                       # Extract text from video
]
```

### Media CDN Configuration

```hcl
# CDN settings
enable_cdn = true                        # Enable Media CDN
cdn_domain_name = "video-cdn.example.com" # Your custom domain
cdn_cache_ttl = 3600                     # Default cache TTL (seconds)
cdn_max_ttl = 86400                      # Maximum cache TTL (seconds)
```

### Monitoring Configuration

```hcl
# Monitoring settings
enable_monitoring = true                 # Enable alerts
notification_email = "alerts@example.com" # Alert destination
storage_alert_threshold_gb = 100         # Storage usage alert
function_error_threshold = 5             # Function error alert
```

## Usage Guide

### Uploading Videos

Videos uploaded to the content bucket automatically trigger processing:

```bash
# Upload single video
gsutil cp video.mp4 gs://your-content-bucket/videos/

# Upload multiple videos
gsutil -m cp *.mp4 gs://your-content-bucket/videos/

# Upload with metadata
gsutil -h "Cache-Control:public,max-age=3600" cp video.mp4 gs://your-content-bucket/videos/
```

### Accessing Results

Analytics results are stored in the results bucket:

```bash
# List all results
gsutil ls gs://your-results-bucket/

# View insights for a specific video
gsutil cat gs://your-results-bucket/insights/video_insights.json

# Download comprehensive report
gsutil cp gs://your-results-bucket/reports/video_report.txt ./
```

### Content Delivery

Videos are automatically available through the CDN:

```bash
# Access via CDN IP
https://CDN_IP_ADDRESS/videos/your-video.mp4

# Access via custom domain (after DNS configuration)
https://video-cdn.yourdomain.com/videos/your-video.mp4
```

## Monitoring and Troubleshooting

### Cloud Functions Logs

```bash
# View function logs
gcloud functions logs read video-processor-SUFFIX --limit=50

# Follow logs in real-time
gcloud functions logs tail video-processor-SUFFIX
```

### Storage Operations

```bash
# Check bucket contents
gsutil ls -la gs://your-content-bucket/

# Monitor bucket usage
gsutil du -sh gs://your-content-bucket/

# Check bucket permissions
gsutil iam get gs://your-content-bucket/
```

### Vertex AI Operations

```bash
# List video analysis operations
gcloud ai operations list --region=us-central1

# Check operation status
gcloud ai operations describe OPERATION_ID --region=us-central1
```

### CDN Performance

```bash
# Test CDN response
curl -I https://your-cdn-domain.com/videos/test.mp4

# Check cache status
curl -H "Cache-Control: no-cache" https://your-cdn-domain.com/videos/test.mp4
```

## Cost Optimization

### Storage Lifecycle

The configuration includes automatic lifecycle policies:
- **30 days**: Move to Nearline storage
- **90 days**: Move to Coldline storage
- **365 days**: Move to Archive storage

### Function Optimization

- **Min instances**: Set to 0 for cost savings
- **Memory allocation**: Right-size based on actual usage
- **Timeout**: Optimize for typical processing times

### CDN Efficiency

- **Cache TTL**: Longer TTL reduces origin requests
- **Compression**: Enabled automatically for bandwidth savings
- **Regional optimization**: Deploy in regions closest to users

## Security Features

### Access Control

- **Uniform bucket-level access**: Consistent IAM policies
- **Public access prevention**: Blocks public exposure
- **Service account isolation**: Dedicated SAs for each service
- **Least privilege**: Minimal required permissions

### Encryption

- **Google-managed encryption**: Default for all data
- **Customer-managed keys**: Optional CMEK support
- **In-transit encryption**: HTTPS/TLS everywhere

### Network Security

- **Private Google Access**: Secure API communications
- **VPC isolation**: Optional private networking
- **SSL certificates**: Automatic Google-managed SSL

## Scaling Considerations

### Function Scaling

- **Max instances**: Prevent runaway costs
- **Concurrency**: Balance throughput vs. cost
- **Memory/CPU**: Scale based on video complexity

### Storage Scaling

- **Multi-regional**: For global access patterns
- **Lifecycle policies**: Automatic cost optimization
- **Transfer acceleration**: For large uploads

### CDN Scaling

- **Global distribution**: Automatic edge caching
- **Auto-scaling**: Handles traffic spikes
- **Regional optimization**: Content closer to users

## Maintenance

### Regular Tasks

1. **Monitor costs**: Review billing and usage patterns
2. **Update dependencies**: Keep Terraform and providers current
3. **Review logs**: Check for errors and performance issues
4. **Security review**: Audit IAM policies and access patterns

### Backup and Recovery

```bash
# Export Terraform state
terraform state pull > terraform.tfstate.backup

# Backup bucket contents
gsutil -m rsync -r gs://source-bucket gs://backup-bucket

# Export configuration
gcloud config export > gcloud-config-backup.yaml
```

### Disaster Recovery

The infrastructure includes:
- **Multi-zone deployment**: Automatic failover
- **Data replication**: Cross-region backup options
- **Infrastructure as Code**: Rapid redeployment capability

## Support and Resources

### Documentation

- [Google Cloud Video Intelligence](https://cloud.google.com/video-intelligence/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Media CDN Documentation](https://cloud.google.com/media-cdn/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)

### Community

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [GitHub Issues](link-to-your-repository/issues)

### Professional Support

- [Google Cloud Support](https://cloud.google.com/support)
- [Partner Network](https://cloud.google.com/partners)

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy -var-file="terraform.tfvars"

# Confirm deletion
# Type 'yes' when prompted
```

**Warning**: This will permanently delete all data and cannot be undone.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

For major changes, please open an issue first to discuss the proposed changes.