# Infrastructure as Code for Patient Sentiment Analysis with Cloud Healthcare API and Natural Language AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Patient Sentiment Analysis with Cloud Healthcare API and Natural Language AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent healthcare analytics pipeline that:

- Processes FHIR patient records from Cloud Healthcare API
- Leverages Natural Language AI to extract sentiment insights from clinical notes
- Stores results in BigQuery for comprehensive analytics dashboards
- Uses event-driven processing with Pub/Sub and Cloud Functions

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Healthcare API
  - Cloud Natural Language API
  - Cloud Functions API
  - BigQuery API
  - Pub/Sub API
  - Cloud Build API
- Appropriate IAM permissions for resource creation:
  - Healthcare Dataset Admin
  - BigQuery Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Service Account Admin

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/patient-sentiment \
    --service-account=$SERVICE_ACCOUNT \
    --local-source="."

# Check deployment status
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/patient-sentiment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud healthcare datasets list --location=$REGION
```

## Configuration Parameters

### Infrastructure Manager Variables

Configure the following parameters in your deployment:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `healthcare_dataset_id`: Healthcare dataset identifier
- `fhir_store_id`: FHIR store identifier
- `bigquery_dataset_id`: BigQuery dataset for analytics
- `function_name`: Cloud Function name for sentiment processing

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "healthcare_dataset_id" {
  description = "Healthcare dataset identifier"
  type        = string
  default     = "patient-records"
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}
```

Customize values in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
healthcare_dataset_id = "patient-records-prod"
```

## Deployed Resources

The infrastructure creates the following Google Cloud resources:

### Healthcare Resources
- **Healthcare Dataset**: HIPAA-compliant data storage
- **FHIR Store**: R4-compliant patient record storage with Pub/Sub notifications
- **IAM Bindings**: Service account permissions for Healthcare API access

### Processing Resources
- **Pub/Sub Topic**: Event-driven processing triggers
- **Pub/Sub Subscription**: Message delivery to Cloud Functions
- **Cloud Function**: Sentiment analysis processing with Python runtime
- **Service Account**: Function execution identity with least-privilege permissions

### Analytics Resources
- **BigQuery Dataset**: Data warehouse for sentiment analysis results
- **BigQuery Table**: Structured storage for patient sentiment data
- **IAM Bindings**: BigQuery access permissions for data processing

### Networking & Security
- **IAM Service Accounts**: Dedicated service accounts with minimal required permissions
- **IAM Policy Bindings**: Role assignments following principle of least privilege
- **API Enablement**: Required Google Cloud service APIs

## Testing the Deployment

After deployment, test the sentiment analysis pipeline:

1. **Upload Sample FHIR Records**:
   ```bash
   # Create sample patient observation
   curl -X POST \
       -H "Authorization: Bearer $(gcloud auth print-access-token)" \
       -H "Content-Type: application/fhir+json" \
       -d '{
         "resourceType": "Observation",
         "id": "test-obs-001",
         "status": "final",
         "subject": {"reference": "Patient/test-patient"},
         "valueString": "The staff was incredibly helpful and caring during my stay."
       }' \
       "https://healthcare.googleapis.com/v1/projects/$PROJECT_ID/locations/$REGION/datasets/$HEALTHCARE_DATASET/fhirStores/$FHIR_STORE/fhir/Observation"
   ```

2. **Verify Processing**:
   ```bash
   # Check Cloud Function logs
   gcloud functions logs read $FUNCTION_NAME --region=$REGION --limit=10
   
   # Query BigQuery results
   bq query --use_legacy_sql=false \
       "SELECT * FROM \`$PROJECT_ID.$BQ_DATASET.sentiment_analysis\` LIMIT 10"
   ```

3. **Monitor Resources**:
   ```bash
   # Check Pub/Sub message processing
   gcloud pubsub topics list-subscriptions $PUBSUB_TOPIC
   
   # Verify Healthcare API access
   gcloud healthcare fhir-stores describe $FHIR_STORE \
       --dataset=$HEALTHCARE_DATASET --location=$REGION
   ```

## Monitoring and Observability

The deployment includes monitoring capabilities:

- **Cloud Functions Monitoring**: Automatic metrics collection for function execution
- **Pub/Sub Metrics**: Message processing rates and error tracking
- **BigQuery Monitoring**: Query performance and storage metrics
- **Healthcare API Audit Logs**: FHIR resource access logging

Access monitoring dashboards:
```bash
# View function metrics
gcloud functions describe $FUNCTION_NAME --region=$REGION

# Check Pub/Sub subscription metrics
gcloud pubsub subscriptions describe $PUBSUB_TOPIC-sub
```

## Security Considerations

This implementation follows healthcare data security best practices:

### Data Protection
- **HIPAA Compliance**: Cloud Healthcare API provides HIPAA-compliant data storage
- **Encryption**: Data encrypted at rest and in transit
- **Access Logging**: Comprehensive audit trails for data access

### Identity and Access Management
- **Service Accounts**: Dedicated service accounts with minimal required permissions
- **Least Privilege**: Role assignments limited to specific resource access needs
- **API Security**: OAuth 2.0 authentication for all API access

### Network Security
- **Private Access**: Resources deployed in secure Google Cloud environment
- **API Restrictions**: Healthcare API access restricted to authorized service accounts

## Cost Estimation

Estimated monthly costs for typical usage:

- **Cloud Healthcare API**: $0.40 per GB stored + $0.01 per FHIR operation
- **Cloud Natural Language API**: $1.00 per 1,000 text records processed
- **Cloud Functions**: $0.0000025 per invocation + $0.0000166667 per GB-second
- **BigQuery**: $5.00 per TB stored + $5.00 per TB queried
- **Pub/Sub**: $0.40 per million messages

Total estimated cost: $20-50/month for moderate usage (1,000 patient records/month)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/patient-sentiment

# Verify deletion
gcloud infra-manager deployments list --location=$REGION
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm deletion
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud healthcare datasets list --location=$REGION
gcloud functions list --region=$REGION
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud healthcare datasets list --location=$REGION
gcloud pubsub topics list
gcloud functions list --region=$REGION
bq ls --project_id=$PROJECT_ID
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable healthcare.googleapis.com \
       language.googleapis.com \
       cloudfunctions.googleapis.com \
       bigquery.googleapis.com
   ```

2. **Permission Denied**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy $PROJECT_ID
   
   # Add required roles
   gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/healthcare.admin"
   ```

3. **Function Deployment Fails**:
   ```bash
   # Check Cloud Build API
   gcloud services enable cloudbuild.googleapis.com
   
   # Verify source code integrity
   cd function-source && ls -la
   ```

4. **FHIR Store Access Issues**:
   ```bash
   # Verify Healthcare dataset exists
   gcloud healthcare datasets describe $HEALTHCARE_DATASET --location=$REGION
   
   # Check FHIR store configuration
   gcloud healthcare fhir-stores describe $FHIR_STORE \
       --dataset=$HEALTHCARE_DATASET --location=$REGION
   ```

### Debug Commands

```bash
# Check resource status
gcloud healthcare datasets list --location=$REGION
gcloud functions list --region=$REGION
gcloud pubsub topics list
bq ls --project_id=$PROJECT_ID

# View detailed logs
gcloud functions logs read $FUNCTION_NAME --region=$REGION
gcloud logging read "resource.type=cloud_function"
```

## Customization

### Adding Custom Sentiment Categories

Modify the Cloud Function code to include custom sentiment categories:

```python
def classify_sentiment(score, magnitude):
    if score > 0.5:
        return "VERY_POSITIVE"
    elif score > 0.25:
        return "POSITIVE"
    elif score < -0.5:
        return "VERY_NEGATIVE"
    elif score < -0.25:
        return "NEGATIVE"
    else:
        return "NEUTRAL"
```

### Multi-Language Support

Add translation capabilities to process non-English patient feedback:

```python
from google.cloud import translate_v2 as translate

def translate_text(text, target_language='en'):
    translate_client = translate.Client()
    result = translate_client.translate(text, target_language=target_language)
    return result['translatedText']
```

### Advanced Analytics

Integrate BigQuery ML for predictive sentiment analysis:

```sql
CREATE MODEL `patient_sentiment.sentiment_predictor`
OPTIONS(model_type='logistic_reg') AS
SELECT
  sentiment_score,
  magnitude,
  overall_sentiment as label
FROM `patient_sentiment.sentiment_analysis`
WHERE processing_timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY);
```

## Support

For issues with this infrastructure code:

1. **Google Cloud Documentation**: [Cloud Healthcare API](https://cloud.google.com/healthcare-api/docs)
2. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. **Original Recipe**: Refer to the patient sentiment analysis recipe documentation
4. **Community Support**: Google Cloud Community forums and Stack Overflow

## Compliance and Governance

This infrastructure supports healthcare compliance requirements:

- **HIPAA**: Cloud Healthcare API provides HIPAA-compliant data processing
- **Data Residency**: Resources deployed in specified Google Cloud region
- **Audit Logging**: Comprehensive logging for compliance reporting
- **Access Controls**: Role-based access control with audit trails

Ensure your organization's compliance team reviews the deployment for specific regulatory requirements.