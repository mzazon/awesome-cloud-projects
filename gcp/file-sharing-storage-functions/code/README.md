# Infrastructure as Code for Simple File Sharing with Cloud Storage and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Sharing with Cloud Storage and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Required Tools
- Google Cloud CLI (gcloud) installed and configured
- Terraform installed (version 1.5+ recommended) for Terraform deployment
- Appropriate IAM permissions for resource creation:
  - Cloud Storage Admin
  - Cloud Functions Admin
  - Service Account Admin
  - Project IAM Admin

### Required APIs
The following Google Cloud APIs must be enabled in your project:
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)

### Cost Considerations
- **Estimated monthly cost**: $0.10-$2.00 for typical usage
- **Free tier benefits**: Includes Cloud Functions (2M invocations/month) and Cloud Storage (5GB/month)
- **Cost components**: Storage, function invocations, network egress, and Cloud Build minutes

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native Infrastructure as Code service that uses YAML configuration files.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/file-sharing-portal \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/main.yaml"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project settings

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your project settings
```

## Configuration Options

### Infrastructure Manager Configuration

The `infrastructure-manager/main.yaml` file contains the following configurable parameters:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name_suffix`: Unique suffix for bucket naming
- `function_memory`: Memory allocation for Cloud Functions (default: 256MB)
- `function_timeout`: Timeout for Cloud Functions (default: 60s)

### Terraform Configuration

Key variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name_suffix = "random-suffix"
upload_function_name = "upload-file"
link_function_name = "generate-link"
function_memory = "256"
function_timeout = "60"
```

### Bash Script Configuration

The deployment script will prompt for:
- Project ID
- Preferred region
- Bucket naming preferences
- Function configuration options

## Resource Overview

This infrastructure creates the following Google Cloud resources:

### Core Resources
- **Cloud Storage Bucket**: Stores uploaded files with CORS configuration
- **Upload Cloud Function**: HTTP-triggered function for file uploads (Python 3.12)
- **Link Generation Cloud Function**: HTTP-triggered function for creating signed URLs (Python 3.12)

### Supporting Resources
- **IAM Service Accounts**: Dedicated service accounts for function execution
- **IAM Policies**: Least-privilege access policies for Cloud Storage operations
- **Cloud Build Triggers**: Automated deployment of function source code

### Security Features
- Uniform bucket-level access control
- CORS policies for web integration
- Time-limited signed URLs (1-hour expiration)
- Secure filename sanitization
- Comprehensive error handling and logging

## Testing Your Deployment

### 1. Verify Resources

```bash
# Check bucket creation
gcloud storage buckets list --filter="name:file-share"

# Check function deployment
gcloud functions list --filter="name:upload OR name:link"

# Test function endpoints
curl -X OPTIONS [UPLOAD_FUNCTION_URL]
curl -X OPTIONS [LINK_FUNCTION_URL]
```

### 2. Test File Upload

```bash
# Create test file
echo "Hello, file sharing!" > test-file.txt

# Upload via curl
curl -X POST \
    -F "file=@test-file.txt" \
    [UPLOAD_FUNCTION_URL]
```

### 3. Test Link Generation

```bash
# Generate shareable link
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"filename":"test-file.txt"}' \
    [LINK_FUNCTION_URL]
```

### 4. Web Interface Testing

After deployment, you can create a simple HTML file to test the web interface:

```html
<!DOCTYPE html>
<html>
<head>
    <title>File Sharing Test</title>
</head>
<body>
    <h2>Upload File</h2>
    <input type="file" id="fileInput">
    <button onclick="uploadFile()">Upload</button>
    
    <h2>Generate Link</h2>
    <input type="text" id="filename" placeholder="Enter filename">
    <button onclick="generateLink()">Generate Link</button>
    
    <script>
        const uploadUrl = 'YOUR_UPLOAD_FUNCTION_URL';
        const linkUrl = 'YOUR_LINK_FUNCTION_URL';
        
        async function uploadFile() {
            const file = document.getElementById('fileInput').files[0];
            const formData = new FormData();
            formData.append('file', file);
            
            const response = await fetch(uploadUrl, {
                method: 'POST',
                body: formData
            });
            
            const result = await response.json();
            console.log('Upload result:', result);
        }
        
        async function generateLink() {
            const filename = document.getElementById('filename').value;
            
            const response = await fetch(linkUrl, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({filename: filename})
            });
            
            const result = await response.json();
            console.log('Link result:', result);
        }
    </script>
</body>
</html>
```

## Monitoring and Troubleshooting

### View Logs

```bash
# Function logs
gcloud functions logs read upload-file --limit=50
gcloud functions logs read generate-link --limit=50

# Storage logs
gcloud logging read "resource.type=gcs_bucket" --limit=50 --format=table
```

### Common Issues

1. **CORS Errors**: Ensure bucket CORS policy is properly configured
2. **Function Timeouts**: Increase timeout values in configuration
3. **Permission Errors**: Verify IAM roles and service account permissions
4. **Bucket Access**: Check uniform bucket-level access settings

### Performance Optimization

- Monitor function execution time and memory usage
- Implement caching strategies for frequently accessed files
- Consider using Cloud CDN for better global performance
- Set up proper monitoring alerts for cost and performance metrics

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/file-sharing-portal
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running automated cleanup, verify all resources are removed:

```bash
# Check remaining buckets
gcloud storage buckets list --filter="name:file-share"

# Check remaining functions
gcloud functions list --filter="name:upload OR name:link"

# Check remaining service accounts
gcloud iam service-accounts list --filter="displayName:file-share"
```

## Customization

### Extending Functionality

1. **Add Authentication**: Integrate with Firebase Auth or Google Identity
2. **File Type Restrictions**: Modify upload function to validate file types
3. **Database Integration**: Add Firestore for file metadata tracking
4. **Email Notifications**: Integrate with SendGrid or Gmail API
5. **Virus Scanning**: Add Cloud Security Command Center integration

### Scaling Considerations

- **High Volume**: Consider Cloud Run for better scaling characteristics
- **Global Distribution**: Add Cloud CDN and multi-region buckets
- **Enterprise Features**: Implement audit logging and advanced IAM
- **Cost Optimization**: Set up lifecycle policies for old files

### Security Enhancements

- Implement request rate limiting
- Add virus scanning for uploaded files
- Enable audit logging for compliance
- Set up VPC Service Controls for data governance
- Configure private Google Access for enhanced security

## Support

### Documentation References

- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the original recipe documentation for implementation details
2. Review Google Cloud documentation for service-specific guidance
3. Consult Terraform documentation for configuration issues
4. Use `gcloud feedback` to report Google Cloud CLI issues

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud Platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core/27)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)