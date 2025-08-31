"""
Cloud Function to trigger Cloud Asset Inventory exports to BigQuery.
This function is called by Cloud Scheduler to automate asset inventory exports.
"""

import json
import logging
import os
from typing import Dict, Any

import functions_framework
from google.cloud import asset_v1
from google.cloud.exceptions import GoogleCloudError
from flask import Request

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
DATASET_NAME = os.environ.get('DATASET_NAME', '${dataset_name}')
ORGANIZATION_ID = os.environ.get('ORGANIZATION_ID', '${organization_id}')
ASSET_TYPES = json.loads(os.environ.get('ASSET_TYPES', '${asset_types}'))

@functions_framework.http
def trigger_asset_export(request: Request) -> Dict[str, Any]:
    """
    HTTP Cloud Function to trigger Cloud Asset Inventory export to BigQuery.
    
    Args:
        request: Flask request object containing JSON payload with:
            - organization_id: GCP organization ID
            - project_id: GCP project ID for BigQuery destination
            - dataset_name: BigQuery dataset name
            - asset_types: List of asset types to export (optional)
    
    Returns:
        JSON response with operation status and details
    """
    # Set CORS headers for potential web access
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'Content-Type',
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            logger.error("No JSON payload received")
            return ({
                'success': False,
                'error': 'No JSON payload provided',
                'message': 'Request must contain JSON payload with required parameters'
            }, 400, headers)
        
        # Extract parameters with fallbacks to environment variables
        organization_id = request_json.get('organization_id', ORGANIZATION_ID)
        project_id = request_json.get('project_id', PROJECT_ID)
        dataset_name = request_json.get('dataset_name', DATASET_NAME)
        asset_types = request_json.get('asset_types', ASSET_TYPES)
        
        # Validate required parameters
        if not organization_id:
            logger.error("Missing organization_id")
            return ({
                'success': False,
                'error': 'Missing organization_id',
                'message': 'organization_id is required for asset export'
            }, 400, headers)
        
        if not project_id:
            logger.error("Missing project_id")
            return ({
                'success': False,
                'error': 'Missing project_id',
                'message': 'project_id is required for BigQuery destination'
            }, 400, headers)
        
        if not dataset_name:
            logger.error("Missing dataset_name")
            return ({
                'success': False,
                'error': 'Missing dataset_name',
                'message': 'dataset_name is required for BigQuery destination'
            }, 400, headers)
        
        logger.info(f"Starting asset export for organization {organization_id}")
        logger.info(f"Export destination: {project_id}.{dataset_name}.asset_inventory")
        logger.info(f"Asset types: {asset_types}")
        
        # Initialize Asset Service client
        client = asset_v1.AssetServiceClient()
        
        # Configure the parent resource (organization)
        parent = f"organizations/{organization_id}"
        
        # Configure BigQuery destination
        output_config = asset_v1.OutputConfig()
        output_config.bigquery_destination.dataset = f"projects/{project_id}/datasets/{dataset_name}"
        output_config.bigquery_destination.table = "asset_inventory"
        output_config.bigquery_destination.force = True
        output_config.bigquery_destination.separate_tables_per_asset_type = False
        
        # Create export request
        export_request = {
            "parent": parent,
            "output_config": output_config,
            "content_type": asset_v1.ContentType.RESOURCE,
            "asset_types": asset_types if asset_types else None
        }
        
        # Start the export operation
        operation = client.export_assets(request=export_request)
        
        logger.info(f"Asset export operation started: {operation.name}")
        
        # Return success response
        response_data = {
            'success': True,
            'operation_name': operation.name,
            'message': f"Asset export operation started successfully",
            'details': {
                'organization_id': organization_id,
                'project_id': project_id,
                'dataset_name': dataset_name,
                'destination_table': f"{project_id}.{dataset_name}.asset_inventory",
                'asset_types_count': len(asset_types) if asset_types else 0,
                'asset_types': asset_types
            }
        }
        
        logger.info("Asset export triggered successfully")
        return (response_data, 200, headers)
        
    except GoogleCloudError as e:
        logger.error(f"Google Cloud error during asset export: {str(e)}")
        return ({
            'success': False,
            'error': 'Google Cloud API error',
            'message': str(e),
            'error_type': type(e).__name__
        }, 500, headers)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return ({
            'success': False,
            'error': 'Invalid JSON payload',
            'message': f"Failed to parse JSON: {str(e)}"
        }, 400, headers)
        
    except Exception as e:
        logger.error(f"Unexpected error during asset export: {str(e)}")
        return ({
            'success': False,
            'error': 'Internal server error',
            'message': f"An unexpected error occurred: {str(e)}",
            'error_type': type(e).__name__
        }, 500, headers)


def validate_asset_types(asset_types: list) -> bool:
    """
    Validate that asset types are in the correct format.
    
    Args:
        asset_types: List of asset type strings
        
    Returns:
        True if valid, False otherwise
    """
    if not isinstance(asset_types, list):
        return False
    
    valid_prefixes = [
        'compute.googleapis.com/',
        'storage.googleapis.com/',
        'container.googleapis.com/',
        'sqladmin.googleapis.com/',
        'bigquery.googleapis.com/',
        'cloudresourcemanager.googleapis.com/'
    ]
    
    for asset_type in asset_types:
        if not isinstance(asset_type, str):
            return False
        if not any(asset_type.startswith(prefix) for prefix in valid_prefixes):
            logger.warning(f"Asset type {asset_type} may not be valid")
    
    return True


# Additional helper function for monitoring
@functions_framework.http
def health_check(request: Request) -> Dict[str, Any]:
    """
    Simple health check endpoint for monitoring.
    
    Returns:
        Health status information
    """
    return {
        'status': 'healthy',
        'service': 'asset-export-trigger',
        'version': '1.0.0',
        'configuration': {
            'project_id': PROJECT_ID,
            'dataset_name': DATASET_NAME,
            'asset_types_configured': len(ASSET_TYPES)
        }
    }