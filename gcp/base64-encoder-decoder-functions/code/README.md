# Infrastructure as Code for Base64 Encoder Decoder with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Base64 Encoder Decoder with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, delete)
  - Cloud Storage (bucket creation and management)
  - Cloud Build API (for function deployment)
  - Service Account management
- For Terraform: Terraform CLI installed (>= 1.0)
- For Infrastructure Manager: Access to Google Cloud Infrastructure Manager service

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/base64-functions \
    --service-account PROJECT_ID@PROJECT_ID.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --input-values project_id=PROJECT_ID,region=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Bucket**: Stores files for Base64 processing with appropriate IAM permissions
- **Base64 Encoder Function**: HTTP-triggered Cloud Function that encodes text and files to Base64
- **Base64 Decoder Function**: HTTP-triggered Cloud Function that decodes Base64 back to original format
- **Service Accounts**: Properly configured IAM for secure function execution
- **API Enablement**: Required Google Cloud APIs (Cloud Functions, Cloud Build, Cloud Storage)

## Configuration Options

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_name` | Cloud Storage bucket name | Auto-generated | No |
| `encoder_function_name` | Name for encoder function | `base64-encoder` | No |
| `decoder_function_name` | Name for decoder function | `base64-decoder` | No |
| `function_memory` | Memory allocation for functions | `256MB` | No |
| `function_timeout` | Function timeout in seconds | `60s` | No |
| `max_instances` | Maximum function instances | `10` | No |

### Terraform-Specific Variables

```bash
# Example terraform.tfvars file
project_id = "my-gcp-project"
region = "us-central1"
bucket_name = "my-base64-files-bucket"
encoder_function_name = "base64-encoder"
decoder_function_name = "base64-decoder"
function_memory = "256MB"
function_timeout = 60
max_instances = 10
```

### Infrastructure Manager Input Values

```yaml
# Example input values for Infrastructure Manager
project_id: "my-gcp-project"
region: "us-central1"
bucket_name: "my-base64-files-bucket"
encoder_function_name: "base64-encoder"
decoder_function_name: "base64-decoder"
function_memory: "256MB"
function_timeout: "60s"
max_instances: 10
```

## Deployed Resources

### Cloud Functions
- **base64-encoder**: HTTP-triggered function for Base64 encoding
  - Runtime: Python 3.12
  - Memory: 256MB (configurable)
  - Timeout: 60 seconds (configurable)
  - Trigger: HTTP with unauthenticated access
  - Features: Text encoding, file upload support, CORS headers

- **base64-decoder**: HTTP-triggered function for Base64 decoding
  - Runtime: Python 3.12
  - Memory: 256MB (configurable)
  - Timeout: 60 seconds (configurable)
  - Trigger: HTTP with unauthenticated access
  - Features: Base64 validation, UTF-8 text detection, error handling

### Cloud Storage
- **Storage Bucket**: Secure file storage for function operations
  - Location: Same as deployment region
  - Storage Class: Standard
  - Access: Service account permissions configured
  - Lifecycle: No automatic deletion policies

### IAM & Security
- **Service Accounts**: Dedicated service accounts for function execution
- **IAM Bindings**: Least-privilege access to required resources
- **API Access**: Functions configured for HTTP access with CORS support

## Testing the Deployment

### Verify Function Deployment

```bash
# List deployed functions
gcloud functions list --filter="name:(base64-encoder OR base64-decoder)"

# Get function URLs
ENCODER_URL=$(gcloud functions describe base64-encoder --format="value(httpsTrigger.url)")
DECODER_URL=$(gcloud functions describe base64-decoder --format="value(httpsTrigger.url)")

echo "Encoder URL: $ENCODER_URL"
echo "Decoder URL: $DECODER_URL"
```

### Test Base64 Encoding

```bash
# Test text encoding via GET
curl -X GET "${ENCODER_URL}?text=Hello%20World" | python3 -m json.tool

# Test text encoding via POST
curl -X POST "${ENCODER_URL}" \
    -H "Content-Type: application/json" \
    -d '{"text":"Hello from Cloud Functions!"}' \
    | python3 -m json.tool

# Test file upload
echo "Test file content" > test.txt
curl -X POST "${ENCODER_URL}" -F "file=@test.txt" | python3 -m json.tool
```

### Test Base64 Decoding

```bash
# Test decoding (Hello World in Base64)
ENCODED_TEXT="SGVsbG8gV29ybGQ="
curl -X GET "${DECODER_URL}?encoded=${ENCODED_TEXT}" | python3 -m json.tool

# Test round-trip encoding/decoding
ORIGINAL="Hello Cloud Functions"
ENCODED=$(curl -s -X POST "${ENCODER_URL}" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"${ORIGINAL}\"}" \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['encoded'])")

DECODED=$(curl -s -X POST "${DECODER_URL}" \
    -H "Content-Type: application/json" \
    -d "{\"encoded\":\"${ENCODED}\"}" \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['decoded'])")

echo "Original: $ORIGINAL"
echo "Decoded:  $DECODED"
```

## Monitoring and Logging

### View Function Logs

```bash
# View encoder function logs
gcloud functions logs read base64-encoder --limit=50

# View decoder function logs
gcloud functions logs read base64-decoder --limit=50

# Follow logs in real-time
gcloud functions logs tail base64-encoder
```

### Monitor Function Performance

```bash
# Get function metrics (requires Cloud Monitoring API)
gcloud functions describe base64-encoder --format="yaml(name,status,updateTime)"
gcloud functions describe base64-decoder --format="yaml(name,status,updateTime)"
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   - Verify Cloud Build API is enabled
   - Check IAM permissions for deployment service account
   - Ensure function source code is valid

2. **HTTP 403 Errors**
   - Verify functions are deployed with `--allow-unauthenticated`
   - Check IAM policies and function-level permissions

3. **Storage Access Issues**
   - Verify Cloud Storage bucket exists and is accessible
   - Check service account permissions for bucket access

4. **Function Timeout**
   - Increase function timeout if processing large files
   - Monitor function execution time in logs

### Debug Commands

```bash
# Check function deployment status
gcloud functions describe FUNCTION_NAME --format="yaml"

# View recent function executions
gcloud functions logs read FUNCTION_NAME --limit=10 --format="table(timestamp,severity,textPayload)"

# Test function connectivity
curl -X OPTIONS FUNCTION_URL -v  # Check CORS headers
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/base64-functions
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup

```bash
# Delete functions
gcloud functions delete base64-encoder --region=us-central1 --quiet
gcloud functions delete base64-decoder --region=us-central1 --quiet

# Delete storage bucket (replace with actual bucket name)
gsutil -m rm -r gs://BUCKET_NAME

# Clean up local files
rm -f test.txt
```

## Cost Considerations

- **Cloud Functions**: Pay-per-invocation model with generous free tier
  - 2 million invocations per month free
  - Additional invocations: $0.40 per million
- **Cloud Storage**: Pay for storage used and operations
  - First 5 GB free per month
  - Standard storage: $0.020 per GB per month
- **Network Egress**: Charges apply for data transfer out of Google Cloud
  - First 1 GB free per month
  - Regional egress varies by destination

### Cost Optimization Tips

1. Use appropriate memory allocation for functions (256MB is often sufficient)
2. Implement caching for frequently processed content
3. Monitor function execution time and optimize code
4. Consider Cloud Storage lifecycle policies for temporary files
5. Use Cloud Monitoring to track usage and costs

## Security Best Practices

1. **Authentication**: Consider implementing authentication for production use
   - Use Firebase Authentication
   - Implement API key validation
   - Use Google Cloud IAM for service-to-service calls

2. **Input Validation**: Functions include comprehensive input validation
   - Base64 format validation
   - File size limits
   - Content type checking

3. **Network Security**: Functions support CORS but consider restricting origins
   - Configure specific allowed origins
   - Implement rate limiting
   - Use Cloud Armor for DDoS protection

4. **Data Protection**: Implement encryption and access controls
   - Enable Cloud Storage encryption at rest
   - Use HTTPS for all communications
   - Implement audit logging

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../base64-encoder-decoder-functions.md)
2. Refer to [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Review [Cloud Storage documentation](https://cloud.google.com/storage/docs)
4. Check [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Consult [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Next Steps

After successful deployment, consider these enhancements:

1. **Add Authentication**: Implement proper authentication for production use
2. **File Format Detection**: Add support for detecting and reporting file types
3. **Batch Processing**: Create Cloud Storage triggers for automated processing
4. **Web Interface**: Build a frontend using Firebase Hosting or App Engine
5. **Caching**: Implement Cloud Memorystore for improved performance
6. **Monitoring**: Set up Cloud Monitoring alerts and dashboards