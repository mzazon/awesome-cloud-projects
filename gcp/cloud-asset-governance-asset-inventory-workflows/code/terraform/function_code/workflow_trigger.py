# Cloud Asset Governance Workflow Trigger Function
# This function receives Pub/Sub messages from Cloud Asset Inventory
# and triggers the governance workflow for policy evaluation and remediation.

import json
import base64
import logging
import os
from typing import Dict, Any, Optional
from google.cloud import workflows_v1
from google.oauth2 import service_account
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
GOVERNANCE_SUFFIX = os.environ.get('GOVERNANCE_SUFFIX', '${governance_suffix}')
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
WORKFLOW_NAME = os.environ.get('WORKFLOW_NAME', f'governance-orchestrator-{GOVERNANCE_SUFFIX}')

# Initialize Workflows client
workflows_client = workflows_v1.WorkflowsClient()

class WorkflowTrigger:
    """
    Handles triggering of governance workflows from asset change events.
    
    This class processes Pub/Sub messages containing asset change notifications
    and triggers appropriate governance workflows for policy evaluation.
    """
    
    def __init__(self):
        self.project_id = PROJECT_ID
        self.region = REGION
        self.workflow_name = WORKFLOW_NAME
        
    def parse_pubsub_message(self, event_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Parse Pub/Sub message containing asset change notification.
        
        Args:
            event_data: Event data from Pub/Sub trigger
            
        Returns:
            Parsed asset change data or None if invalid
        """
        try:
            # Decode base64 message data
            if 'data' not in event_data:
                logger.error("No data field found in Pub/Sub message")
                return None
            
            message_data = base64.b64decode(event_data['data']).decode('utf-8')
            parsed_data = json.loads(message_data)
            
            # Validate required fields
            if 'asset' not in parsed_data:
                logger.error("No asset field found in message data")
                return None
            
            asset = parsed_data['asset']
            
            # Extract key asset information
            asset_info = {
                'asset': asset,
                'change_type': parsed_data.get('changeType', 'UNKNOWN'),
                'resource_name': asset.get('name', 'unknown'),
                'asset_type': asset.get('assetType', 'unknown'),
                'timestamp': parsed_data.get('timestamp', ''),
                'ancestors': asset.get('ancestors', [])
            }
            
            return asset_info
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode JSON message: {str(e)}")
            return None
        except Exception as e:
            logger.error(f"Error parsing Pub/Sub message: {str(e)}")
            return None
    
    def should_process_asset(self, asset_info: Dict[str, Any]) -> bool:
        """
        Determine if the asset change should trigger governance processing.
        
        Args:
            asset_info: Parsed asset information
            
        Returns:
            True if asset should be processed, False otherwise
        """
        asset_type = asset_info.get('asset_type', '')
        change_type = asset_info.get('change_type', '')
        
        # Skip processing for deleted assets (they no longer exist to evaluate)
        if change_type == 'DELETE':
            logger.info(f"Skipping deleted asset: {asset_info.get('resource_name')}")
            return False
        
        # Define asset types that require governance evaluation
        governed_asset_types = {
            'storage.googleapis.com/Bucket',
            'compute.googleapis.com/Instance',
            'bigquery.googleapis.com/Dataset',
            'compute.googleapis.com/Disk',
            'iam.googleapis.com/ServiceAccount',
            'compute.googleapis.com/Network',
            'compute.googleapis.com/Subnetwork',
            'container.googleapis.com/Cluster',
            'sql.googleapis.com/DatabaseInstance'
        }
        
        if asset_type not in governed_asset_types:
            logger.debug(f"Asset type {asset_type} not in governance scope")
            return False
        
        # Skip system-managed resources
        resource_name = asset_info.get('resource_name', '')
        if any(pattern in resource_name for pattern in [
            'gke-',  # GKE managed resources
            'k8s-',  # Kubernetes managed resources
            'goog-',  # Google managed resources
        ]):
            logger.debug(f"Skipping system-managed resource: {resource_name}")
            return False
        
        return True
    
    def trigger_governance_workflow(self, asset_info: Dict[str, Any]) -> Dict[str, Any]:
        """
        Trigger the governance workflow with asset change data.
        
        Args:
            asset_info: Asset information to process
            
        Returns:
            Workflow execution result
        """
        try:
            # Construct workflow path
            workflow_path = (
                f"projects/{self.project_id}/locations/{self.region}/"
                f"workflows/{self.workflow_name}"
            )
            
            # Prepare workflow execution argument
            workflow_argument = {
                'asset_change': asset_info,
                'trigger_source': 'pubsub',
                'processing_timestamp': asset_info.get('timestamp', ''),
                'governance_suffix': GOVERNANCE_SUFFIX
            }
            
            # Create workflow execution request
            execution_request = workflows_v1.CreateExecutionRequest(
                parent=workflow_path,
                execution=workflows_v1.Execution(
                    argument=json.dumps(workflow_argument)
                )
            )
            
            # Execute workflow
            logger.info(f"Triggering workflow for asset: {asset_info.get('resource_name')}")
            operation = workflows_client.create_execution(request=execution_request)
            
            execution_name = operation.name
            logger.info(f"Workflow execution started: {execution_name}")
            
            return {
                'status': 'workflow_triggered',
                'execution_name': execution_name,
                'workflow_path': workflow_path,
                'asset_name': asset_info.get('resource_name'),
                'asset_type': asset_info.get('asset_type')
            }
            
        except Exception as e:
            logger.error(f"Failed to trigger workflow: {str(e)}")
            return {
                'status': 'error',
                'error_message': str(e),
                'asset_name': asset_info.get('resource_name', 'unknown')
            }
    
    def process_batch_messages(self, messages: list) -> Dict[str, Any]:
        """
        Process multiple asset change messages in batch.
        
        Args:
            messages: List of Pub/Sub messages
            
        Returns:
            Batch processing results
        """
        results = {
            'processed_count': 0,
            'skipped_count': 0,
            'error_count': 0,
            'workflow_executions': []
        }
        
        for message in messages:
            try:
                asset_info = self.parse_pubsub_message(message)
                
                if not asset_info:
                    results['error_count'] += 1
                    continue
                
                if not self.should_process_asset(asset_info):
                    results['skipped_count'] += 1
                    continue
                
                # Trigger workflow for this asset
                execution_result = self.trigger_governance_workflow(asset_info)
                results['workflow_executions'].append(execution_result)
                
                if execution_result['status'] == 'workflow_triggered':
                    results['processed_count'] += 1
                else:
                    results['error_count'] += 1
                    
            except Exception as e:
                logger.error(f"Error processing message: {str(e)}")
                results['error_count'] += 1
        
        return results

@functions_framework.cloud_event
def trigger_governance_workflow(cloud_event):
    """
    Cloud Function entry point for Pub/Sub triggered workflow execution.
    
    This function is triggered by Pub/Sub messages from Cloud Asset Inventory
    and initiates governance workflow processing for asset changes.
    """
    try:
        # Extract Pub/Sub message data
        if not cloud_event.data:
            logger.error("No data in cloud event")
            return {'status': 'error', 'message': 'No event data'}, 400
        
        # Parse the Pub/Sub message
        trigger = WorkflowTrigger()
        asset_info = trigger.parse_pubsub_message(cloud_event.data)
        
        if not asset_info:
            logger.error("Failed to parse asset information from Pub/Sub message")
            return {'status': 'error', 'message': 'Invalid message format'}, 400
        
        # Log asset change event
        logger.info(
            f"Received asset change: {asset_info.get('resource_name')} "
            f"(type: {asset_info.get('asset_type')}, "
            f"change: {asset_info.get('change_type')})"
        )
        
        # Check if asset should be processed
        if not trigger.should_process_asset(asset_info):
            logger.info(f"Asset skipped: {asset_info.get('resource_name')}")
            return {
                'status': 'skipped',
                'reason': 'Asset not in governance scope',
                'asset_name': asset_info.get('resource_name'),
                'asset_type': asset_info.get('asset_type')
            }, 200
        
        # Trigger governance workflow
        execution_result = trigger.trigger_governance_workflow(asset_info)
        
        if execution_result['status'] == 'workflow_triggered':
            logger.info(
                f"Successfully triggered workflow for {asset_info.get('resource_name')}: "
                f"{execution_result['execution_name']}"
            )
            return execution_result, 200
        else:
            logger.error(
                f"Failed to trigger workflow for {asset_info.get('resource_name')}: "
                f"{execution_result.get('error_message', 'Unknown error')}"
            )
            return execution_result, 500
            
    except Exception as e:
        logger.error(f"Unexpected error in workflow trigger: {str(e)}")
        return {
            'status': 'error',
            'message': f'Unexpected error: {str(e)}'
        }, 500

@functions_framework.http
def trigger_governance_workflow_http(request):
    """
    HTTP entry point for testing workflow triggers.
    
    This function provides an HTTP interface for testing governance
    workflow triggers with sample asset data.
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return {
                'status': 'error',
                'message': 'No JSON data provided'
            }, 400
        
        # Initialize trigger
        trigger = WorkflowTrigger()
        
        # Handle batch processing if multiple messages provided
        if 'messages' in request_json:
            results = trigger.process_batch_messages(request_json['messages'])
            return {
                'status': 'batch_processed',
                'results': results
            }, 200
        
        # Handle single message
        elif 'asset' in request_json:
            asset_info = {
                'asset': request_json['asset'],
                'change_type': request_json.get('change_type', 'CREATE'),
                'resource_name': request_json['asset'].get('name', 'test-resource'),
                'asset_type': request_json['asset'].get('assetType', 'unknown'),
                'timestamp': request_json.get('timestamp', ''),
                'ancestors': request_json['asset'].get('ancestors', [])
            }
            
            if trigger.should_process_asset(asset_info):
                execution_result = trigger.trigger_governance_workflow(asset_info)
                return execution_result, 200 if execution_result['status'] == 'workflow_triggered' else 500
            else:
                return {
                    'status': 'skipped',
                    'reason': 'Asset not in governance scope'
                }, 200
        
        else:
            return {
                'status': 'error',
                'message': 'Invalid request format. Expected asset data or messages array.'
            }, 400
            
    except Exception as e:
        logger.error(f"Error in HTTP trigger: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }, 500