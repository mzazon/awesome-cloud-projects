# Terraform Infrastructure for Real-Time Collaborative Applications

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete real-time collaborative document editing application using Firebase Realtime Database and Cloud Functions.

## Architecture Overview

The infrastructure provisions:

- **Firebase Project**: Complete Firebase project setup with required APIs
- **Firebase Realtime Database**: Real-time data synchronization for collaborative editing
- **Cloud Functions**: Serverless backend logic for document management and user collaboration
- **Firebase Authentication**: Secure user authentication with multiple providers
- **Firebase Hosting**: Static web hosting for the collaborative application
- **Cloud Storage**: Storage bucket for Cloud Functions source code
- **Monitoring & Alerting**: Comprehensive monitoring for collaborative features
- **IAM & Security**: Proper service accounts and security configurations

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Terraform**: Version 1.0 or later installed locally
3. **Google Cloud CLI**: `gcloud` CLI installed and authenticated
4. **Firebase CLI**: Firebase CLI for additional configuration (optional)
5. **Permissions**: The following IAM roles on your GCP project:
   - `roles/owner` OR
   - `roles/editor` AND `roles/iam.serviceAccountAdmin` AND `roles/resourcemanager.projectIamAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/real-time-collaborative-applications-firebase-database-functions/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"

# Optional customizations
region                        = "us-central1"
resource_prefix              = "collab-app"
environment                  = "dev"
firebase_project_display_name = "My Collaborative Editor"

# Authentication providers
auth_providers = ["email", "google.com"]

# Function configuration
function_memory  = 256
function_timeout = 60

# Storage configuration
storage_class = "STANDARD"

# Labels for resource organization
labels = {
  application = "collaborative-editor"
  managed-by  = "terraform"
  team        = "development"
}
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 5. Get Configuration

After successful deployment, retrieve the Firebase configuration:

```bash
# Get Firebase config for client applications
terraform output -json client_config_template

# Get all important URLs and endpoints
terraform output testing_endpoints
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `resource_prefix` | Prefix for resource names | `collab-app` | No |

### Firebase Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `firebase_project_display_name` | Display name for Firebase project | `Collaborative Document Editor` |
| `database_region` | Firebase Realtime Database region | `us-central1` |
| `auth_providers` | Authentication providers to enable | `["email", "google.com"]` |
| `hosting_site_id` | Firebase Hosting site ID | `project_id` |

### Cloud Functions Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `nodejs_runtime` | Node.js runtime version | `nodejs18` | `nodejs16`, `nodejs18`, `nodejs20` |
| `function_memory` | Memory allocation (MB) | `256` | 128-8192 |
| `function_timeout` | Function timeout (seconds) | `60` | 1-540 |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cors_allowed_origins` | CORS allowed origins | `["*"]` |
| `enable_audit_logs` | Enable audit logging | `true` |

## Deployed Resources

### Firebase Services

- **Firebase Project**: Complete project setup with required APIs
- **Realtime Database**: NoSQL database with real-time synchronization
- **Firebase Authentication**: User authentication and management
- **Firebase Hosting**: Static web application hosting
- **Firebase Web App**: Client application configuration

### Cloud Functions

1. **create-document**: Creates new collaborative documents
2. **add-collaborator**: Adds users as document collaborators
3. **get-user-documents**: Retrieves user's document list

### Supporting Infrastructure

- **Cloud Storage Bucket**: Stores Cloud Functions source code
- **Service Account**: IAM service account for Cloud Functions
- **Monitoring**: Log-based metrics and alerting policies
- **IAM Bindings**: Proper permissions for all services

## Security Features

### Authentication & Authorization

- Firebase Authentication with email/password and Google OAuth
- Service account with least-privilege permissions
- Function-level IAM controls for secure access

### Data Protection

- Uniform bucket-level access for Cloud Storage
- Secure CORS configuration for web applications
- Audit logging for compliance and monitoring

### Network Security

- Private service accounts for Cloud Functions
- Controlled ingress settings for function access
- Secure database rules (deployed separately)

## Monitoring & Observability

### Logging

- Structured logging for all Cloud Functions
- Document modification tracking
- User activity monitoring

### Metrics

- Custom log-based metrics for collaborative features
- Function execution metrics
- Database operation monitoring

### Alerting

- Function error rate alerts
- Performance threshold monitoring
- Custom alerting policies for business metrics

## Client Application Integration

### Firebase Configuration

Use the `client_config_template` output to configure your client application:

```javascript
// Get configuration from Terraform output
const firebaseConfig = {
  apiKey: "your-api-key",
  authDomain: "your-project.firebaseapp.com",
  databaseURL: "https://your-project-default-rtdb.firebaseio.com/",
  projectId: "your-project-id",
  storageBucket: "your-project.appspot.com",
  messagingSenderId: "123456789",
  appId: "your-app-id"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
```

### Cloud Functions Endpoints

The Cloud Functions are deployed as HTTP functions. Use the `cloud_functions` output to get endpoint URLs:

```javascript
// Example function calls
const createDocument = firebase.functions().httpsCallable('createDocument');
const addCollaborator = firebase.functions().httpsCallable('addCollaborator');
const getUserDocuments = firebase.functions().httpsCallable('getUserDocuments');
```

## Database Security Rules

Deploy database security rules separately using Firebase CLI:

```bash
# Create database.rules.json
cat > database.rules.json << 'EOF'
{
  "rules": {
    "documents": {
      "$documentId": {
        ".read": "auth != null && (auth.uid in data.collaborators || data.owner == auth.uid)",
        ".write": "auth != null && (auth.uid in data.collaborators || data.owner == auth.uid)",
        "content": {
          ".validate": "newData.isString() && newData.val().length <= 10000"
        },
        "lastModified": {
          ".write": "auth != null"
        }
      }
    },
    "users": {
      "$uid": {
        ".read": "auth != null && auth.uid == $uid",
        ".write": "auth != null && auth.uid == $uid"
      }
    }
  }
}
EOF

# Deploy rules
firebase deploy --only database
```

## Testing the Deployment

### 1. Verify Infrastructure

```bash
# Check all resources were created
terraform show

# Test function deployments
gcloud functions list --filter="name:collab-app"

# Verify Firebase project
firebase projects:list
```

### 2. Test Authentication

```bash
# Test user creation
curl -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "testpassword123",
    "returnSecureToken": true
  }'
```

### 3. Test Cloud Functions

```bash
# Test function endpoints (after obtaining auth token)
curl -X POST \
  "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/createDocument" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Document"}'
```

## Customization

### Adding More Functions

1. Update `function_code/index.js` with new function
2. Add new `google_cloudfunctions2_function` resource in `main.tf`
3. Configure appropriate IAM bindings

### Scaling Configuration

```hcl
# In terraform.tfvars
function_memory = 512  # Increase for heavy workloads
function_timeout = 120 # Increase for long-running operations

# Add auto-scaling configuration
service_config {
  max_instance_count = 1000
  min_instance_count = 5
}
```

### Multi-Environment Setup

```hcl
# Environment-specific configurations
environment = "prod"

labels = {
  application = "collaborative-editor"
  environment = "production"
  managed-by  = "terraform"
}

# Production-specific settings
enable_audit_logs = true
cors_allowed_origins = ["https://your-domain.com"]
```

## Cost Optimization

### Firebase Spark Plan (Free)

- Realtime Database: 1GB storage, 100 concurrent connections
- Cloud Functions: 125K invocations/month, 40K GB-seconds
- Firebase Hosting: 1GB storage, 10GB transfer/month
- Authentication: Unlimited users

### Estimated Costs (Beyond Free Tier)

- **Cloud Functions**: ~$0.40 per 1M invocations
- **Realtime Database**: ~$5 per GB/month
- **Cloud Storage**: ~$0.02 per GB/month
- **Hosting**: ~$0.026 per GB transfer

### Cost Controls

```hcl
# Set function limits
service_config {
  max_instance_count = 10  # Limit concurrent instances
  timeout_seconds    = 30  # Reduce timeout for simple functions
}

# Use lifecycle policies for storage
lifecycle_rule {
  condition {
    age = 7  # Delete old function versions after 7 days
  }
  action {
    type = "Delete"
  }
}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs manually
   gcloud services enable firebase.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   # Check IAM roles
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
     --member="user:your-email@domain.com" \
     --role="roles/firebase.admin"
   ```

3. **Function Deployment Failed**
   ```bash
   # Check function logs
   gcloud functions logs read ${FUNCTION_NAME}
   
   # Verify source code
   gsutil ls gs://${BUCKET_NAME}/
   ```

### Debug Commands

```bash
# View Terraform state
terraform state list
terraform state show google_firebase_project.default

# Check Google Cloud resources
gcloud projects describe ${PROJECT_ID}
gcloud functions list
gcloud storage buckets list

# Firebase-specific debugging
firebase projects:list
firebase functions:list
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all Terraform-managed resources
terraform destroy

# Verify cleanup
gcloud projects list --filter="projectId:${PROJECT_ID}"
```

### Manual Cleanup (if needed)

```bash
# Delete Firebase project (if Terraform fails)
firebase projects:delete ${PROJECT_ID}

# Clean up any remaining GCS buckets
gsutil rm -r gs://${BUCKET_NAME}

# Remove local Terraform state
rm -rf .terraform
rm terraform.tfstate*
```

## Support and Documentation

### Official Documentation

- [Firebase Documentation](https://firebase.google.com/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Recipe Documentation

Refer to the original recipe documentation for:
- Step-by-step implementation guide
- Client application code examples
- Security best practices
- Advanced configuration options

### Community Resources

- [Firebase Community](https://firebase.google.com/community)
- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Community](https://www.terraform.io/community)

## Contributing

When modifying this infrastructure:

1. Update variable descriptions and validation rules
2. Add appropriate outputs for new resources
3. Include monitoring and security configurations
4. Update this README with new features
5. Test thoroughly in development environment

## License

This infrastructure code is provided as part of the cloud recipe collection and follows the same licensing terms as the parent repository.