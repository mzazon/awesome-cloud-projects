import json
import base64
from google.cloud import bigquery
from google.cloud import asset_v1
import functions_framework
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize BigQuery client
client = bigquery.Client()

# Configuration from environment variables
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
MANDATORY_LABELS = ${mandatory_labels}

@functions_framework.cloud_event
def process_asset_change(cloud_event):
    """Process asset change notifications for tag compliance."""
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        asset_data = json.loads(message_data)
        
        logger.info(f"Processing asset change: {asset_data.get('name', 'unknown')}")
        
        # Extract resource information
        resource_name = asset_data.get("name", "")
        resource_type = asset_data.get("assetType", "")
        
        # Handle nested resource data structure
        resource_info = asset_data.get("resource", {})
        resource_data = resource_info.get("data", {})
        labels = resource_data.get("labels", {})
        
        # Check tag compliance
        compliant = all(label in labels for label in MANDATORY_LABELS)
        
        logger.info(f"Resource {resource_name} compliance status: {compliant}")
        
        # Prepare compliance record
        compliance_record = {
            "resource_name": resource_name,
            "resource_type": resource_type,
            "labels": json.dumps(labels),
            "compliant": compliant,
            "timestamp": datetime.utcnow().isoformat(),
            "cost_center": labels.get("cost_center", ""),
            "department": labels.get("department", ""),
            "environment": labels.get("environment", ""),
            "project_code": labels.get("project_code", "")
        }
        
        # Insert compliance record into BigQuery
        table_id = f"{PROJECT_ID}.{DATASET_NAME}.tag_compliance"
        table = client.get_table(table_id)
        
        errors = client.insert_rows_json(table, [compliance_record])
        
        if errors:
            logger.error(f"Failed to insert compliance record: {errors}")
            raise Exception(f"BigQuery insert failed: {errors}")
        
        logger.info(f"Successfully processed asset: {resource_name}, Compliant: {compliant}")
        
        # Log non-compliant resources for alerting
        if not compliant:
            missing_labels = [label for label in MANDATORY_LABELS if label not in labels]
            logger.warning(f"Non-compliant resource {resource_name} missing labels: {missing_labels}")
        
        return {"status": "success", "resource": resource_name, "compliant": compliant}
        
    except Exception as e:
        logger.error(f"Error processing asset change: {str(e)}")
        raise e