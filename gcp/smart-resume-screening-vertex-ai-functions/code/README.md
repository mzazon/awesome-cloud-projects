# Infrastructure as Code for Smart Resume Screening with Vertex AI and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Resume Screening with Vertex AI and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active GCP project with billing enabled
- Appropriate IAM permissions for the following services:
  - Cloud Functions
  - Cloud Storage
  - Firestore
  - Vertex AI
  - Cloud Build
  - Natural Language API
- Python 3.11+ (for function development)
- Terraform 1.0+ (if using Terraform deployment)

## Architecture Overview

This infrastructure deploys:
- Cloud Storage bucket for resume uploads
- Cloud Function (2nd generation) for resume processing
- Firestore database for candidate data storage
- IAM roles and bindings for service communication
- Cloud Function trigger for Storage events

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/resume-screening \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

Configure `inputs.yaml` with your specific values:

```yaml
project_id: "your-project-id"
region: "us-central1"
bucket_location: "US"
function_memory: "512Mi"
function_timeout: "300s"
firestore_location: "us-central1"
```

### Terraform Variables

Available variables in `terraform/variables.tf`:

- `project_id`: GCP project ID (required)
- `region`: Deployment region (default: "us-central1")
- `bucket_location`: Storage bucket location (default: "US")
- `function_memory`: Cloud Function memory allocation (default: "512Mi")
- `function_timeout`: Cloud Function timeout (default: "300s")
- `firestore_location`: Firestore database location (default: "us-central1")

### Bash Script Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BUCKET_LOCATION="US"
export FUNCTION_MEMORY="512Mi"
export FUNCTION_TIMEOUT="300s"
```

## Post-Deployment Setup

After infrastructure deployment, you'll need to:

1. **Upload the Cloud Function source code**:
   ```bash
   # The function source code is included in the deployment
   # Verify function deployment status
   gcloud functions describe process-resume --region=${REGION}
   ```

2. **Test the system with sample resumes**:
   ```bash
   # Create test resume file
   echo "John Doe - 5 years Python experience, Masters in CS" > test-resume.txt
   
   # Upload to trigger processing
   gsutil cp test-resume.txt gs://$(terraform output -raw bucket_name)/
   ```

3. **Verify Firestore data**:
   ```bash
   # Check if candidates collection was created
   gcloud firestore collections list
   ```

## Testing the Deployment

### Verify Infrastructure

```bash
# Check Cloud Function status
gcloud functions describe process-resume --region=${REGION}

# Check Storage bucket
gsutil ls gs://$(terraform output -raw bucket_name)

# Check Firestore database
gcloud firestore databases list
```

### Upload Test Resume

```bash
# Create a sample resume file
cat << EOF > sample-resume.txt
Jane Smith
Software Engineer

EXPERIENCE:
3 years of experience in Python development
Proficient in Machine Learning and Cloud Computing
Experience with Docker and Kubernetes

EDUCATION:
Bachelor of Science in Computer Science

SKILLS:
- Python programming
- Machine Learning
- Cloud platforms (GCP, AWS)
- Docker containerization
EOF

# Upload resume to trigger processing
gsutil cp sample-resume.txt gs://$(terraform output -raw bucket_name)/

# Wait for processing and check results
sleep 30
gcloud functions logs read process-resume --region=${REGION} --limit=10
```

### Query Processed Data

```bash
# Create a simple query script
cat << 'EOF' > query_candidates.py
from google.cloud import firestore
import json

db = firestore.Client()
candidates = db.collection('candidates').stream()

print("Processed Candidates:")
for candidate in candidates:
    data = candidate.to_dict()
    print(f"File: {data.get('file_name', 'Unknown')}")
    print(f"Score: {data.get('screening_score', 0)}")
    print(f"Skills: {data.get('skills_extracted', [])}")
    print("---")
EOF

# Run query (requires google-cloud-firestore package)
python3 query_candidates.py
```

## Monitoring and Observability

### View Function Logs

```bash
# Real-time logs
gcloud functions logs tail process-resume --region=${REGION}

# Recent logs
gcloud functions logs read process-resume --region=${REGION} --limit=50
```

### Monitor Function Metrics

```bash
# Function invocations
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=process-resume" --limit=10

# Error monitoring
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=process-resume AND severity>=ERROR" --limit=10
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Verify required APIs are enabled
   gcloud services list --enabled
   ```

2. **Storage trigger not working**:
   ```bash
   # Verify function trigger configuration
   gcloud functions describe process-resume --region=${REGION} --format="value(eventTrigger)"
   ```

3. **Firestore permission errors**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

### Debug Function Execution

```bash
# Test function locally (requires Functions Framework)
cd function-source/
pip install functions-framework google-cloud-storage google-cloud-firestore google-cloud-language

# Run locally
functions-framework --target=process_resume --debug
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/resume-screening
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete process-resume --region=${REGION} --quiet

# Delete Storage bucket
gsutil -m rm -r gs://resume-uploads-*

# Delete Firestore data (optional - keeps database structure)
# Note: Firestore database deletion requires Console or specific API calls
```

## Cost Optimization

### Resource Sizing Recommendations

- **Cloud Function Memory**: Start with 512MB, monitor usage and adjust
- **Function Timeout**: 300s is sufficient for most resume processing
- **Storage Class**: Use STANDARD for active resume processing, NEARLINE for archival

### Cost Monitoring

```bash
# Monitor function execution costs
gcloud logging read "resource.type=cloud_function" --format="table(timestamp,resource.labels.function_name,labels.execution_id)"

# Storage costs
gsutil du -sh gs://$(terraform output -raw bucket_name)
```

## Security Considerations

### IAM Best Practices

The infrastructure implements least-privilege access:
- Cloud Function service account has minimal required permissions
- Storage bucket access is restricted to the function
- Firestore access follows principle of least privilege

### Data Protection

- All data is encrypted at rest by default
- Function execution environment is isolated
- No sensitive data is logged in function outputs

## Customization

### Extending the Function

To modify the resume processing logic:

1. Update the function source code in `function-source/main.py`
2. Redeploy using your chosen IaC method
3. Test with sample resumes

### Adding Additional Services

To integrate additional AI services:

1. Add service enabling to the IaC configuration
2. Update IAM permissions for the function service account
3. Modify function code to use new services

### Scaling Considerations

For high-volume processing:
- Consider using Cloud Run for more control over scaling
- Implement batch processing for multiple resumes
- Add Cloud Monitoring alerts for function performance

## Integration with Existing Systems

### API Integration

```bash
# Create API endpoint for resume submission (example)
gcloud run deploy resume-api \
    --image=gcr.io/${PROJECT_ID}/resume-api \
    --region=${REGION} \
    --allow-unauthenticated
```

### Webhook Integration

The infrastructure can be extended to support webhooks for ATS integration by adding:
- Cloud Run service for API endpoints
- Pub/Sub for reliable message processing
- Cloud Scheduler for batch processing

## Support

For issues with this infrastructure code:
- Review the original recipe documentation for context
- Check Google Cloud documentation for service-specific issues
- Monitor function logs for runtime errors
- Verify all required APIs are enabled

## Version History

- v1.0: Initial infrastructure implementation
- v1.1: Added enhanced monitoring and security configurations

---

**Note**: This infrastructure creates billable resources. Monitor usage and clean up resources when no longer needed to avoid unexpected charges.