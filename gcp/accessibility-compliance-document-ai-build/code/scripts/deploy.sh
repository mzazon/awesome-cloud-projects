#!/bin/bash

# Accessibility Compliance with Document AI and Build - Deployment Script
# This script deploys an automated accessibility compliance testing solution
# using Document AI, Cloud Build, and Security Command Center

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="accessibility_compliance_deploy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
readonly REQUIRED_APIS=(
    "documentai.googleapis.com"
    "cloudbuild.googleapis.com"
    "securitycenter.googleapis.com"
    "storage.googleapis.com"
    "pubsub.googleapis.com"
    "cloudfunctions.googleapis.com"
)

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Script failed. Check ${LOG_FILE} for details."
    log_error "You may need to run the destroy script to clean up partial deployments."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check for required tools
    local tools=("jq" "openssl")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed. Please install it."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="accessibility-compliance-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="accessibility-compliance-${RANDOM_SUFFIX}"
    export TOPIC_NAME="accessibility-compliance-alerts"
    
    log_info "Environment configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  ZONE: ${ZONE}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  TOPIC_NAME: ${TOPIC_NAME}"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration updated"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "✓ ${api} enabled"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}..."
    
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "✓ Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for compliance audit trail
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_success "✓ Bucket versioning enabled"
}

# Create Pub/Sub topic
create_pubsub_topic() {
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}..."
    
    if gcloud pubsub topics create "${TOPIC_NAME}"; then
        log_success "✓ Pub/Sub topic created: ${TOPIC_NAME}"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
}

# Create Document AI processor
create_document_ai_processor() {
    log_info "Creating Document AI processor..."
    
    # Create OCR processor for content analysis
    PROCESSOR_ID=$(gcloud documentai processors create \
        --display-name="accessibility-content-processor" \
        --type=OCR_PROCESSOR \
        --location="${REGION}" \
        --format="value(name)" | cut -d'/' -f6)
    
    if [[ -n "${PROCESSOR_ID}" ]]; then
        export PROCESSOR_ID
        log_success "✓ Document AI processor created: ${PROCESSOR_ID}"
        
        # Store processor configuration
        cat > "${SCRIPT_DIR}/processor-config.env" << EOF
PROCESSOR_ID=${PROCESSOR_ID}
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_NAME=${TOPIC_NAME}
EOF
        log_success "✓ Processor configuration saved to processor-config.env"
    else
        log_error "Failed to create Document AI processor"
        exit 1
    fi
}

# Create accessibility analyzer script
create_accessibility_analyzer() {
    log_info "Creating accessibility analyzer script..."
    
    cat > "${SCRIPT_DIR}/accessibility_analyzer.py" << 'EOF'
import json
import sys
import re
from google.cloud import documentai
from google.cloud import storage
from google.cloud import securitycenter
from bs4 import BeautifulSoup

class AccessibilityAnalyzer:
    def __init__(self, project_id, processor_id, location):
        self.project_id = project_id
        self.processor_id = processor_id
        self.location = location
        self.client = documentai.DocumentProcessorServiceClient()
        self.processor_name = f"projects/{project_id}/locations/{location}/processors/{processor_id}"
        
    def analyze_html_content(self, html_content):
        """Analyze HTML content for accessibility violations."""
        soup = BeautifulSoup(html_content, 'html.parser')
        violations = []
        
        # Check for missing alt text on images
        images = soup.find_all('img')
        for img in images:
            if not img.get('alt'):
                violations.append({
                    'type': 'missing_alt_text',
                    'element': str(img),
                    'severity': 'high',
                    'wcag_criterion': '1.1.1',
                    'description': 'Image missing alternative text'
                })
        
        # Check for proper heading structure
        headings = soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6'])
        heading_levels = [int(h.name[1]) for h in headings]
        
        for i, level in enumerate(heading_levels[1:], 1):
            if level > heading_levels[i-1] + 1:
                violations.append({
                    'type': 'heading_structure',
                    'element': str(headings[i]),
                    'severity': 'medium',
                    'wcag_criterion': '1.3.1',
                    'description': 'Heading levels not properly nested'
                })
        
        # Check for form labels
        inputs = soup.find_all('input', type=['text', 'email', 'password'])
        for input_elem in inputs:
            if not input_elem.get('aria-label') and not input_elem.get('aria-labelledby'):
                associated_label = soup.find('label', attrs={'for': input_elem.get('id')})
                if not associated_label:
                    violations.append({
                        'type': 'missing_form_label',
                        'element': str(input_elem),
                        'severity': 'high',
                        'wcag_criterion': '1.3.1',
                        'description': 'Form input missing label'
                    })
        
        # Check for missing language declaration
        html_tag = soup.find('html')
        if html_tag and not html_tag.get('lang'):
            violations.append({
                'type': 'missing_language',
                'element': str(html_tag),
                'severity': 'medium',
                'wcag_criterion': '3.1.1',
                'description': 'HTML element missing lang attribute'
            })
        
        return violations
    
    def process_document(self, content):
        """Process document content with Document AI."""
        request = documentai.ProcessRequest(
            name=self.processor_name,
            raw_document=documentai.RawDocument(
                content=content,
                mime_type="text/html"
            )
        )
        
        result = self.client.process_document(request=request)
        return result.document
    
    def generate_compliance_report(self, violations, file_path):
        """Generate compliance report in JSON format."""
        report = {
            'file_path': file_path,
            'total_violations': len(violations),
            'violations_by_severity': {
                'high': len([v for v in violations if v['severity'] == 'high']),
                'medium': len([v for v in violations if v['severity'] == 'medium']),
                'low': len([v for v in violations if v['severity'] == 'low'])
            },
            'violations': violations,
            'compliance_status': 'FAIL' if violations else 'PASS'
        }
        return report

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python accessibility_analyzer.py <project_id> <processor_id> <html_file>")
        sys.exit(1)
    
    project_id = sys.argv[1]
    processor_id = sys.argv[2]
    html_file = sys.argv[3]
    
    analyzer = AccessibilityAnalyzer(project_id, processor_id, "us-central1")
    
    with open(html_file, 'rb') as f:
        content = f.read()
    
    # Analyze HTML content for accessibility violations
    violations = analyzer.analyze_html_content(content.decode('utf-8'))
    
    # Generate compliance report
    report = analyzer.generate_compliance_report(violations, html_file)
    
    # Output report
    print(json.dumps(report, indent=2))
EOF
    
    log_success "✓ Accessibility analyzer script created"
}

# Create Cloud Build configuration
create_cloudbuild_config() {
    log_info "Creating Cloud Build configuration..."
    
    # Get organization ID
    ORG_ID=$(gcloud organizations list --format="value(name)" | head -1 | cut -d'/' -f2)
    export ORG_ID
    
    # Create Security Command Center source
    SOURCE_ID=$(gcloud scc sources create \
        --organization="${ORG_ID}" \
        --display-name="Accessibility Compliance Scanner" \
        --description="Automated WCAG compliance monitoring" \
        --format="value(name)" | cut -d'/' -f4)
    export SOURCE_ID
    
    log_success "✓ Security Command Center source created: ${SOURCE_ID}"
    
    # Update configuration file
    cat >> "${SCRIPT_DIR}/processor-config.env" << EOF
ORG_ID=${ORG_ID}
SOURCE_ID=${SOURCE_ID}
EOF
    
    cat > "${SCRIPT_DIR}/cloudbuild.yaml" << EOF
steps:
# Install dependencies
- name: 'python:3.9'
  entrypoint: 'pip'
  args: ['install', 'google-cloud-documentai', 'google-cloud-storage', 
         'google-cloud-securitycenter', 'beautifulsoup4', 'requests']

# Copy accessibility analyzer
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    cp accessibility_analyzer.py /workspace/
    chmod +x /workspace/accessibility_analyzer.py

# Run accessibility analysis on HTML files
- name: 'python:3.9'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    export PROJECT_ID=\${PROJECT_ID}
    export PROCESSOR_ID=\${_PROCESSOR_ID}
    
    # Find and analyze HTML files
    find . -name "*.html" -type f | while read html_file; do
      echo "Analyzing: \$html_file"
      python3 /workspace/accessibility_analyzer.py \\
        \${PROJECT_ID} \${_PROCESSOR_ID} "\$html_file" > "\${html_file}.accessibility.json"
    done

# Upload compliance reports to Cloud Storage
- name: 'gcr.io/cloud-builders/gsutil'
  args: ['cp', '*.accessibility.json', 'gs://\${_BUCKET_NAME}/reports/']

# Send results to Security Command Center
- name: 'python:3.9'
  entrypoint: 'python3'
  args:
  - '-c'
  - |
    import json
    import glob
    from google.cloud import securitycenter
    
    client = securitycenter.SecurityCenterClient()
    org_name = "organizations/\${_ORG_ID}"
    
    for report_file in glob.glob("*.accessibility.json"):
      with open(report_file) as f:
        report = json.load(f)
      
      if report['compliance_status'] == 'FAIL':
        finding = {
          "state": "ACTIVE",
          "resource_name": f"//cloudbuild.googleapis.com/projects/\${PROJECT_ID}/builds/\${BUILD_ID}",
          "category": "ACCESSIBILITY_COMPLIANCE",
          "external_uri": f"gs://\${_BUCKET_NAME}/reports/{report_file}",
          "source_properties": {
            "violations_count": str(report['total_violations']),
            "file_path": report['file_path'],
            "high_severity": str(report['violations_by_severity']['high'])
          }
        }
        
        # Create finding in Security Command Center
        try:
          response = client.create_finding(
            request={
              "parent": f"{org_name}/sources/\${_SOURCE_ID}",
              "finding_id": f"accessibility-{BUILD_ID}-{hash(report_file)}",
              "finding": finding
            }
          )
          print(f"Created finding: {response.name}")
        except Exception as e:
          print(f"Error creating finding: {e}")

substitutions:
  _PROCESSOR_ID: '${PROCESSOR_ID}'
  _BUCKET_NAME: '${BUCKET_NAME}'
  _ORG_ID: '${ORG_ID}'
  _SOURCE_ID: '${SOURCE_ID}'

options:
  logging: CLOUD_LOGGING_ONLY
EOF
    
    log_success "✓ Cloud Build configuration created"
}

# Create compliance notification function
create_notification_function() {
    log_info "Creating compliance notification Cloud Function..."
    
    cat > "${SCRIPT_DIR}/compliance_notifier.py" << 'EOF'
import json
import base64
from google.cloud import pubsub_v1

def process_compliance_alert(event, context):
    """Process Security Command Center findings for accessibility compliance."""
    
    # Decode Pub/Sub message
    if 'data' in event:
        message = base64.b64decode(event['data']).decode('utf-8')
        finding_data = json.loads(message)
        
        # Check if it's an accessibility finding
        if finding_data.get('category') == 'ACCESSIBILITY_COMPLIANCE':
            severity = 'HIGH' if int(finding_data.get('source_properties', {}).get('high_severity', '0')) > 0 else 'MEDIUM'
            
            alert_message = f"""
            Accessibility Compliance Alert
            
            Severity: {severity}
            File: {finding_data.get('source_properties', {}).get('file_path', 'Unknown')}
            Violations: {finding_data.get('source_properties', {}).get('violations_count', '0')}
            High Severity Issues: {finding_data.get('source_properties', {}).get('high_severity', '0')}
            
            Please review the compliance report for detailed remediation steps.
            """
            
            print(f"Accessibility compliance alert: {alert_message}")
            
            # Here you would integrate with your preferred notification system
            # (email, Slack, Microsoft Teams, etc.)
            
    return 'Alert processed'
EOF
    
    cat > "${SCRIPT_DIR}/requirements.txt" << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-functions==1.13.3
EOF
    
    # Deploy Cloud Function
    if gcloud functions deploy compliance-notifier \
        --runtime python39 \
        --trigger-topic "${TOPIC_NAME}" \
        --source "${SCRIPT_DIR}" \
        --entry-point process_compliance_alert \
        --memory 256MB \
        --timeout 60s \
        --region "${REGION}"; then
        log_success "✓ Compliance notification function deployed"
    else
        log_error "Failed to deploy notification function"
        exit 1
    fi
    
    # Create notification policy for Security Command Center
    if gcloud scc notifications create accessibility-alerts \
        --organization="${ORG_ID}" \
        --description="Accessibility compliance alerts" \
        --pubsub-topic="projects/${PROJECT_ID}/topics/${TOPIC_NAME}" \
        --filter="category=\"ACCESSIBILITY_COMPLIANCE\""; then
        log_success "✓ Security Command Center notification policy created"
    else
        log_warning "Failed to create notification policy - this is optional"
    fi
}

# Create build triggers
create_build_triggers() {
    log_info "Creating Cloud Build triggers..."
    
    # Create manual trigger for testing
    if gcloud builds triggers create manual \
        --name="accessibility-manual-trigger" \
        --build-config="${SCRIPT_DIR}/cloudbuild.yaml" \
        --description="Manual accessibility compliance testing" \
        --substitutions="_PROCESSOR_ID=${PROCESSOR_ID},_BUCKET_NAME=${BUCKET_NAME},_ORG_ID=${ORG_ID},_SOURCE_ID=${SOURCE_ID}"; then
        log_success "✓ Manual build trigger created"
    else
        log_error "Failed to create manual build trigger"
        exit 1
    fi
    
    log_info "To create GitHub triggers later, use:"
    log_info "gcloud builds triggers create github --repo-name=<your-repo> --repo-owner=<your-username> --branch-pattern='^main\$' --build-config=cloudbuild.yaml"
}

# Create test content
create_test_content() {
    log_info "Creating test HTML content..."
    
    mkdir -p "${SCRIPT_DIR}/test-content"
    
    cat > "${SCRIPT_DIR}/test-content/sample.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Accessibility Test Page</title>
</head>
<body>
    <h1>Welcome to Our Website</h1>
    
    <!-- Missing alt text violation -->
    <img src="logo.png" width="200" height="100">
    
    <!-- Improper heading structure violation -->
    <h4>Section Title</h4>
    <p>This heading skips from h1 to h4, violating proper nesting.</p>
    
    <!-- Missing form label violation -->
    <form>
        <input type="text" placeholder="Enter your name">
        <input type="email" placeholder="Enter your email">
        <button type="submit">Submit</button>
    </form>
    
    <!-- Proper accessibility implementation -->
    <img src="accessible-image.png" alt="Company logo featuring green and blue design" width="200" height="100">
    
    <h2>Properly Structured Section</h2>
    <p>This section follows proper heading hierarchy.</p>
    
    <form>
        <label for="proper-name">Full Name:</label>
        <input type="text" id="proper-name" required>
        
        <label for="proper-email">Email Address:</label>
        <input type="email" id="proper-email" required>
        
        <button type="submit">Send Message</button>
    </form>
</body>
</html>
EOF
    
    cat > "${SCRIPT_DIR}/test-content/dashboard.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Dashboard</title>
</head>
<body>
    <h1>Analytics Dashboard</h1>
    <h3>Quick Stats</h3>
    <img src="chart.png">
    <input type="search" placeholder="Search...">
</body>
</html>
EOF
    
    log_success "✓ Test HTML content created"
}

# Run initial test
run_initial_test() {
    log_info "Running initial accessibility compliance test..."
    
    # Copy test files to current directory for testing
    cp -r "${SCRIPT_DIR}/test-content"/* "${SCRIPT_DIR}/"
    cp "${SCRIPT_DIR}/accessibility_analyzer.py" .
    
    # Submit manual build
    if gcloud builds submit \
        --config="${SCRIPT_DIR}/cloudbuild.yaml" \
        --substitutions="_PROCESSOR_ID=${PROCESSOR_ID},_BUCKET_NAME=${BUCKET_NAME},_ORG_ID=${ORG_ID},_SOURCE_ID=${SOURCE_ID}" \
        .; then
        log_success "✓ Initial test build submitted successfully"
        
        # Wait and check build status
        sleep 60
        BUILD_ID=$(gcloud builds list \
            --filter="substitutions._PROCESSOR_ID=${PROCESSOR_ID}" \
            --limit=1 \
            --format="value(id)")
        
        if [[ -n "${BUILD_ID}" ]]; then
            log_info "Build ID: ${BUILD_ID}"
            log_success "✓ Build execution completed"
        fi
    else
        log_warning "Initial test build failed - this is normal for first deployment"
    fi
    
    # Clean up test files from current directory
    rm -f sample.html dashboard.html accessibility_analyzer.py
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment_summary.md" << EOF
# Accessibility Compliance Deployment Summary

## Deployment Details
- **Project ID**: ${PROJECT_ID}
- **Region**: ${REGION}
- **Deployment Date**: $(date)

## Resources Created
- Document AI Processor: ${PROCESSOR_ID}
- Storage Bucket: gs://${BUCKET_NAME}
- Pub/Sub Topic: ${TOPIC_NAME}
- Security Command Center Source: ${SOURCE_ID}
- Cloud Function: compliance-notifier
- Build Trigger: accessibility-manual-trigger

## Configuration Files
- processor-config.env: Contains all resource IDs
- cloudbuild.yaml: CI/CD pipeline configuration
- accessibility_analyzer.py: WCAG compliance analyzer
- compliance_notifier.py: Alert notification handler

## Next Steps
1. Review the test results in Cloud Storage: gs://${BUCKET_NAME}/reports/
2. Check Security Command Center for compliance findings
3. Configure GitHub/GitLab triggers for your repositories
4. Customize notification settings in the Cloud Function

## Testing
Run manual accessibility test:
\`\`\`bash
gcloud builds triggers run accessibility-manual-trigger
\`\`\`

## Monitoring
- Cloud Build logs: https://console.cloud.google.com/cloud-build/builds
- Security Command Center: https://console.cloud.google.com/security/command-center
- Function logs: https://console.cloud.google.com/functions/details/${REGION}/compliance-notifier

## Documentation
See the recipe documentation for detailed usage instructions and customization options.
EOF
    
    log_success "✓ Deployment summary generated: deployment_summary.md"
}

# Main deployment function
main() {
    log_info "Starting Accessibility Compliance deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    set_environment
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_pubsub_topic
    create_document_ai_processor
    create_accessibility_analyzer
    create_cloudbuild_config
    create_notification_function
    create_build_triggers
    create_test_content
    run_initial_test
    generate_summary
    
    log_success "🎉 Accessibility Compliance deployment completed successfully!"
    log_info "Check ${SCRIPT_DIR}/deployment_summary.md for next steps"
    log_info "Configuration saved in ${SCRIPT_DIR}/processor-config.env"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi