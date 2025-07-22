# Infrastructure as Code for Real-Time Collaborative Applications with Firebase Realtime Database and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Collaborative Applications with Firebase Realtime Database and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with Firebase CLI integration

## Prerequisites

- Google Cloud Project with billing enabled
- Firebase CLI installed and configured (`npm install -g firebase-tools`)
- Google Cloud CLI (gcloud) installed and authenticated
- Node.js 18+ and npm for Cloud Functions development
- Appropriate permissions for:
  - Firebase project creation and management
  - Cloud Functions deployment
  - Firebase Authentication configuration
  - Firebase Realtime Database management
  - Firebase Hosting deployment

## Architecture Overview

This solution deploys a complete real-time collaborative application including:

- **Firebase Authentication**: Secure user management with email/password and Google sign-in
- **Firebase Realtime Database**: Real-time data synchronization across all connected clients
- **Cloud Functions**: Serverless business logic for document management and validation
- **Firebase Hosting**: Global CDN hosting for the web application
- **Security Rules**: Comprehensive access control for collaborative documents

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments create collab-app-deployment \
    --location=${REGION} \
    --source-blueprint=. \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe collab-app-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
app_name   = "collaborative-editor"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts (Complete Setup)

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy complete solution
./scripts/deploy.sh

# Follow the interactive prompts for:
# - Firebase project initialization
# - Authentication provider setup
# - Database security rules deployment
# - Cloud Functions deployment
# - Hosting configuration
```

## Configuration Options

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/variables.yaml
project_id:
  description: "Google Cloud Project ID"
  type: string
  required: true

region:
  description: "Deployment region"
  type: string
  default: "us-central1"

app_name:
  description: "Application name prefix"
  type: string
  default: "collaborative-app"

enable_analytics:
  description: "Enable Firebase Analytics"
  type: boolean
  default: false
```

### Terraform Variables

```hcl
# terraform/terraform.tfvars
project_id              = "your-project-id"
region                  = "us-central1"
app_name               = "collaborative-editor"
database_region        = "us-central1"
functions_memory       = "256MB"
functions_timeout      = "60s"
enable_cors           = true
enable_analytics      = false
```

### Environment Variables for Scripts

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization
export APP_NAME="collaborative-editor"
export FUNCTIONS_MEMORY="256MB"
export ENABLE_ANALYTICS="false"
```

## Deployment Details

### Firebase Services Configuration

1. **Authentication Setup**:
   - Email/password authentication enabled
   - Google Sign-In provider configured
   - User management and security rules

2. **Realtime Database**:
   - Real-time data synchronization
   - Security rules for document access control
   - Automatic scaling and offline support

3. **Cloud Functions**:
   - Document management (create, share, collaborate)
   - User management and permissions
   - Real-time change tracking and analytics
   - Server-side validation and security

4. **Hosting Configuration**:
   - Global CDN distribution
   - Automatic SSL certificates
   - Single-page application routing
   - Optimized caching headers

### Security Features

- **Database Security Rules**: Protect collaborative documents with user-based access control
- **Function Authentication**: All Cloud Functions require authenticated users
- **CORS Configuration**: Properly configured cross-origin requests
- **Input Validation**: Server-side validation for all user inputs
- **Role-based Access**: Owner and collaborator roles with appropriate permissions

## Testing and Validation

### Functional Testing

```bash
# Test Firebase project setup
firebase projects:list

# Validate authentication configuration
firebase auth:export users.json --project ${PROJECT_ID}

# Check database security rules
firebase database:test --project ${PROJECT_ID}

# Test Cloud Functions deployment
firebase functions:list --project ${PROJECT_ID}

# Verify hosting deployment
firebase hosting:sites:list --project ${PROJECT_ID}
```

### Application Testing

1. **Authentication Flow**:
   - User registration and login
   - Google Sign-In integration
   - Session management

2. **Real-time Collaboration**:
   - Document creation and sharing
   - Live text synchronization
   - Collaborator management
   - Conflict resolution

3. **Performance Testing**:
   - Multiple concurrent users
   - Real-time sync latency
   - Offline/online transitions

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete collab-app-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm deletion of:
# - Cloud Functions
# - Database data
# - Hosting sites
# - Authentication users
# - Firebase project (optional)
```

### Manual Cleanup (if needed)

```bash
# Delete Firebase project completely
firebase projects:delete ${PROJECT_ID}

# Clean up local development files
rm -rf functions/node_modules
rm -rf .firebase
rm -f firebase-debug.log
```

## Monitoring and Maintenance

### Firebase Console Monitoring

- **Authentication**: Monitor user registrations and sign-ins
- **Database**: Track real-time connections and data usage
- **Functions**: Monitor function invocations and performance
- **Hosting**: Review traffic patterns and performance metrics

### Google Cloud Monitoring

```bash
# View Cloud Functions logs
gcloud functions logs read --limit=50

# Monitor database performance
gcloud logging read "resource.type=firebase_database"

# Check hosting metrics
gcloud logging read "resource.type=firebase_hosting"
```

### Performance Optimization

1. **Database Optimization**:
   - Index frequently queried fields
   - Implement data pagination for large datasets
   - Use database triggers efficiently

2. **Function Optimization**:
   - Optimize cold start times
   - Implement connection pooling
   - Use appropriate memory allocation

3. **Frontend Optimization**:
   - Implement proper caching strategies
   - Minimize bundle size
   - Use service workers for offline support

## Troubleshooting

### Common Issues

1. **Authentication Errors**:
   ```bash
   # Verify project authentication
   firebase login --reauth
   gcloud auth application-default login
   ```

2. **Database Permission Errors**:
   ```bash
   # Check security rules
   firebase database:get /.settings/rules --project ${PROJECT_ID}
   
   # Test rules with specific user
   firebase database:test --project ${PROJECT_ID}
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check function logs
   firebase functions:log --project ${PROJECT_ID}
   
   # Redeploy specific function
   firebase deploy --only functions:createDocument
   ```

4. **Hosting Issues**:
   ```bash
   # Check hosting status
   firebase hosting:sites:list --project ${PROJECT_ID}
   
   # Redeploy hosting
   firebase deploy --only hosting
   ```

### Debug Mode

```bash
# Enable debug logging for deployment
export FIREBASE_DEBUG=true
export GOOGLE_CLOUD_DEBUG=true

# Run deployment with verbose output
./scripts/deploy.sh --debug
```

## Cost Optimization

### Firebase Pricing Considerations

- **Spark Plan (Free)**:
  - 1GB Realtime Database storage
  - 100 simultaneous connections
  - 10GB hosting storage
  - 125K function invocations/month

- **Blaze Plan (Pay-as-you-go)**:
  - Unlimited usage with incremental pricing
  - Required for production applications
  - Predictable scaling costs

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Firebase Collaborative App Budget" \
    --budget-amount=50USD

# Monitor usage
firebase projects:addsdk --project ${PROJECT_ID}
```

## Support and Resources

### Documentation Links

- [Firebase Realtime Database Documentation](https://firebase.google.com/docs/database)
- [Cloud Functions for Firebase Guide](https://firebase.google.com/docs/functions)
- [Firebase Authentication Documentation](https://firebase.google.com/docs/auth)
- [Firebase Hosting Guide](https://firebase.google.com/docs/hosting)
- [Firebase Security Rules Documentation](https://firebase.google.com/docs/database/security)

### Community Resources

- [Firebase Community Slack](https://firebase.community/)
- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow Firebase Tag](https://stackoverflow.com/questions/tagged/firebase)

### Getting Help

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Firebase and Google Cloud documentation
3. Search community forums and Stack Overflow
4. Contact Google Cloud Support (for Blaze plan users)

## License

This infrastructure code is provided as-is under the MIT License. See the original recipe documentation for usage guidelines and best practices.