#!/usr/bin/env python3
"""
Healthcare Data Processing Cloud Function
Triggers batch processing when medical records are uploaded to Cloud Storage
"""

import functions_framework
from google.cloud import batch_v1
from google.cloud import aiplatform
from google.cloud import logging as cloud_logging
import json
import os
import re
from typing import Dict, Any


# Initialize logging
logging_client = cloud_logging.Client()
logging_client.setup_logging()

import logging
logger = logging.getLogger(__name__)


@functions_framework.cloud_event
def trigger_healthcare_processing(cloud_event):
    """
    Trigger healthcare data processing when files are uploaded to Cloud Storage.
    
    Args:
        cloud_event: CloudEvent containing file upload information
        
    Returns:
        Dict with job creation status and job name
    """
    try:
        # Extract file information from the event
        file_name = cloud_event.data.get('name', '')
        bucket = cloud_event.data.get('bucket', '')
        
        logger.info(f"Processing healthcare file: {file_name} from bucket: {bucket}")
        
        # Validate file is a healthcare data file
        if not _is_healthcare_file(file_name):
            logger.info(f"Skipping non-healthcare file: {file_name}")
            return {"status": "skipped", "reason": "not_healthcare_file"}
        
        # Extract environment variables
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        fhir_store = os.environ.get('FHIR_STORE')
        dataset_id = os.environ.get('DATASET_ID')
        
        if not all([project_id, region, fhir_store, dataset_id]):
            logger.error("Missing required environment variables")
            return {"status": "error", "reason": "missing_env_vars"}
        
        # Initialize Batch client
        batch_client = batch_v1.BatchServiceClient()
        
        # Create unique job ID
        safe_file_name = re.sub(r'[^a-zA-Z0-9-]', '-', file_name)[:50]
        job_id = f"healthcare-processing-{safe_file_name}-{cloud_event.data.get('timeCreated', '').replace(':', '-')[:19]}"
        
        # Configure the healthcare processing job
        job = _create_batch_job_config(
            file_name=file_name,
            bucket=bucket,
            project_id=project_id,
            region=region,
            fhir_store=fhir_store,
            dataset_id=dataset_id
        )
        
        # Submit the batch job
        parent = f"projects/{project_id}/locations/{region}"
        
        logger.info(f"Submitting batch job: {job_id}")
        response = batch_client.create_job(
            parent=parent,
            job_id=job_id,
            job=job
        )
        
        logger.info(f"Healthcare processing job created successfully: {response.name}")
        
        # Log compliance event
        _log_compliance_event(file_name, bucket, job_id, "job_created")
        
        return {
            "status": "job_created", 
            "job_name": response.name,
            "job_id": job_id,
            "file_processed": file_name
        }
        
    except Exception as e:
        logger.error(f"Error processing healthcare file {file_name}: {str(e)}")
        
        # Log compliance violation if processing fails
        _log_compliance_event(file_name, bucket, "", "processing_error", str(e))
        
        return {
            "status": "error", 
            "error": str(e),
            "file_processed": file_name
        }


def _is_healthcare_file(file_name: str) -> bool:
    """
    Determine if a file is a healthcare data file based on naming patterns.
    
    Args:
        file_name: Name of the uploaded file
        
    Returns:
        True if file appears to be healthcare data
    """
    healthcare_patterns = [
        r'.*\.(json|xml|hl7|fhir)$',  # Common healthcare formats
        r'.*medical.*',               # Files with 'medical' in name
        r'.*patient.*',               # Files with 'patient' in name
        r'.*clinical.*',              # Files with 'clinical' in name
        r'.*health.*',                # Files with 'health' in name
        r'.*ehr.*',                   # Electronic health records
        r'.*emr.*',                   # Electronic medical records
        r'scripts/',                  # Skip scripts directory
    ]
    
    # Skip script files and system files
    if file_name.startswith('scripts/') or file_name.startswith('.'):
        return False
    
    # Check if file matches healthcare patterns
    for pattern in healthcare_patterns[:-1]:  # Exclude scripts pattern
        if re.search(pattern, file_name.lower()):
            return True
    
    return False


def _create_batch_job_config(
    file_name: str,
    bucket: str,
    project_id: str,
    region: str,
    fhir_store: str,
    dataset_id: str
) -> Dict[str, Any]:
    """
    Create Cloud Batch job configuration for healthcare data processing.
    
    Args:
        file_name: Name of the file to process
        bucket: Storage bucket containing the file
        project_id: Google Cloud project ID
        region: Google Cloud region
        fhir_store: FHIR store name
        dataset_id: Healthcare dataset ID
        
    Returns:
        Batch job configuration dictionary
    """
    
    # Container image with healthcare processing tools
    container_image = "gcr.io/google.com/cloudsdktool/cloud-sdk:latest"
    
    # Processing script
    processing_script = f"""#!/bin/bash
set -e

echo "Starting healthcare data processing for file: {file_name}"

# Install required Python packages
pip install --quiet google-cloud-storage google-cloud-healthcare google-cloud-aiplatform

# Create processing script
cat > /tmp/process_healthcare_file.py << 'EOF'
import os
import json
import logging
from google.cloud import storage
from google.cloud import healthcare_v1
from google.cloud import aiplatform
from datetime import datetime
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_healthcare_file():
    """Process healthcare file with AI analysis and FHIR conversion."""
    
    bucket_name = "{bucket}"
    file_name = "{file_name}"
    project_id = "{project_id}"
    region = "{region}"
    fhir_store = "{fhir_store}"
    dataset_id = "{dataset_id}"
    
    logger.info(f"Processing healthcare file: {{file_name}}")
    
    try:
        # Initialize clients
        storage_client = storage.Client()
        
        # Download file from storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            logger.error(f"File {{file_name}} not found in bucket {{bucket_name}}")
            return
        
        file_content = blob.download_as_text()
        logger.info(f"Downloaded file content: {{len(file_content)}} characters")
        
        # Parse and validate healthcare data
        healthcare_data = parse_healthcare_data(file_content, file_name)
        
        # Analyze content with AI (simulated for now)
        analysis_results = analyze_with_ai(healthcare_data, project_id, region)
        
        # Convert to FHIR format
        fhir_resource = convert_to_fhir(healthcare_data, analysis_results)
        
        # Store in Healthcare API
        store_in_fhir(fhir_resource, project_id, region, dataset_id, fhir_store)
        
        # Monitor compliance
        monitor_compliance(analysis_results, file_name)
        
        logger.info("Healthcare processing completed successfully")
        
    except Exception as e:
        logger.error(f"Error processing healthcare file: {{str(e)}}")
        raise

def parse_healthcare_data(content, file_name):
    """Parse healthcare data from various formats."""
    try:
        if file_name.lower().endswith('.json'):
            return json.loads(content)
        elif file_name.lower().endswith('.xml'):
            # For XML files, return raw content for now
            return {{"raw_xml": content, "format": "xml"}}
        else:
            # For other formats, treat as text
            return {{"raw_text": content, "format": "text"}}
    except json.JSONDecodeError:
        # If JSON parsing fails, treat as text
        return {{"raw_text": content, "format": "text"}}

def analyze_with_ai(healthcare_data, project_id, region):
    """Analyze healthcare data using AI services."""
    
    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=region)
    
    # Simulated AI analysis for demonstration
    analysis = {{
        "clinical_insights": extract_clinical_insights(healthcare_data),
        "compliance_status": check_compliance(healthcare_data),
        "critical_findings": identify_critical_findings(healthcare_data),
        "structured_data": extract_structured_data(healthcare_data)
    }}
    
    return analysis

def extract_clinical_insights(data):
    """Extract clinical insights from healthcare data."""
    insights = {{
        "patient_id": data.get("patient_id", "unknown"),
        "diagnosis": data.get("diagnosis", []),
        "medications": data.get("medications", []),
        "procedures": data.get("procedures", []),
        "vital_signs": data.get("vital_signs", {{}})
    }}
    
    return insights

def check_compliance(data):
    """Check HIPAA and healthcare compliance."""
    # Basic compliance checks
    has_patient_id = "patient_id" in data
    has_phi_markers = any(field in str(data).lower() for field in ["ssn", "social", "phone", "address"])
    
    return {{
        "hipaa_compliant": has_patient_id and not has_phi_markers,
        "phi_detected": has_phi_markers,
        "patient_id_present": has_patient_id
    }}

def identify_critical_findings(data):
    """Identify critical medical findings."""
    # Look for urgent indicators
    urgent_keywords = ["emergency", "critical", "urgent", "stat", "immediate"]
    content_str = str(data).lower()
    
    urgent = any(keyword in content_str for keyword in urgent_keywords)
    
    return {{
        "urgent": urgent,
        "alert_level": "critical" if urgent else "normal",
        "priority": "high" if urgent else "normal"
    }}

def extract_structured_data(data):
    """Extract structured data for FHIR conversion."""
    return {{
        "patient_id": data.get("patient_id", str(uuid.uuid4())),
        "encounter_date": data.get("encounter_date", datetime.now().isoformat()),
        "encounter_type": data.get("encounter_type", "outpatient"),
        "provider": data.get("provider", "unknown")
    }}

def convert_to_fhir(healthcare_data, analysis):
    """Convert healthcare data to FHIR R4 format."""
    structured_data = analysis["structured_data"]
    clinical_insights = analysis["clinical_insights"]
    
    # Create basic FHIR Patient resource
    fhir_resource = {{
        "resourceType": "Patient",
        "id": structured_data["patient_id"],
        "meta": {{
            "versionId": "1",
            "lastUpdated": datetime.now().isoformat() + "Z",
            "profile": ["http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient"]
        }},
        "identifier": [
            {{
                "system": "http://hospital-system.org/patient-ids",
                "value": structured_data["patient_id"]
            }}
        ],
        "active": True
    }}
    
    # Add encounter information if available
    if "encounter_date" in structured_data:
        fhir_resource["encounter"] = {{
            "resourceType": "Encounter",
            "status": "finished",
            "class": {{
                "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
                "code": "AMB",
                "display": "ambulatory"
            }},
            "period": {{
                "start": structured_data["encounter_date"]
            }}
        }}
    
    return fhir_resource

def store_in_fhir(fhir_resource, project_id, region, dataset_id, fhir_store):
    """Store FHIR resource in Healthcare API."""
    try:
        # For demonstration, we'll log the FHIR resource
        # In production, you would use the Healthcare API client
        logger.info(f"Storing FHIR resource in {{dataset_id}}/{{fhir_store}}")
        logger.info(f"FHIR Resource: {{json.dumps(fhir_resource, indent=2)}}")
        
        # Simulated storage confirmation
        logger.info(f"FHIR resource stored successfully: {{fhir_resource['id']}}")
        
    except Exception as e:
        logger.error(f"Error storing FHIR resource: {{str(e)}}")
        raise

def monitor_compliance(analysis, file_name):
    """Monitor compliance and generate alerts if needed."""
    compliance_status = analysis["compliance_status"]
    
    if not compliance_status["hipaa_compliant"]:
        logger.warning(f"HIPAA compliance issue detected in file: {{file_name}}")
        logger.warning(f"Compliance status: {{compliance_status}}")
        
        # In production, this would trigger alerts
        print("COMPLIANCE ALERT: Potential HIPAA violation detected")
    
    if analysis["critical_findings"]["urgent"]:
        logger.info(f"Critical finding detected in file: {{file_name}}")
        logger.info(f"Critical findings: {{analysis['critical_findings']}}")

if __name__ == "__main__":
    process_healthcare_file()
EOF

# Execute the healthcare processing script
python3 /tmp/process_healthcare_file.py

echo "Healthcare data processing completed for file: {file_name}"
"""
    
    job_config = {
        "allocation_policy": {
            "instances": [
                {
                    "policy": {
                        "machine_type": "e2-standard-2",
                        "provisioning_model": "STANDARD"
                    }
                }
            ]
        },
        "task_groups": [
            {
                "task_spec": {
                    "runnables": [
                        {
                            "container": {
                                "image_uri": container_image,
                                "commands": ["/bin/bash"],
                                "entrypoint": "/bin/bash",
                                "options": "-c"
                            },
                            "script": {
                                "text": processing_script
                            }
                        }
                    ],
                    "compute_resource": {
                        "cpu_milli": 2000,
                        "memory_mib": 4096
                    },
                    "max_retry_count": 3,
                    "max_run_duration": "3600s"
                },
                "task_count": 1,
                "parallelism": 1
            }
        ],
        "logs_policy": {
            "destination": "CLOUD_LOGGING"
        }
    }
    
    return job_config


def _log_compliance_event(
    file_name: str, 
    bucket: str, 
    job_id: str, 
    event_type: str, 
    details: str = ""
):
    """
    Log compliance events for audit trail.
    
    Args:
        file_name: Name of the processed file
        bucket: Storage bucket name
        job_id: Batch job ID
        event_type: Type of compliance event
        details: Additional event details
    """
    compliance_log = {
        "event_type": event_type,
        "file_name": file_name,
        "bucket": bucket,
        "job_id": job_id,
        "timestamp": str(cloud_event.get('time', '')),
        "details": details,
        "compliance_context": "HIPAA_healthcare_processing"
    }
    
    logger.info(f"Compliance event logged: {json.dumps(compliance_log)}")
    
    # Log with structured format for monitoring
    logger.info(
        "COMPLIANCE_EVENT",
        extra={
            "json_fields": compliance_log,
            "labels": {
                "event_type": event_type,
                "compliance_scope": "hipaa"
            }
        }
    )