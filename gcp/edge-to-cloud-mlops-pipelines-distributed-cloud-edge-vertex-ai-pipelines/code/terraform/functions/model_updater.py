"""
Edge Model Updater Cloud Function

This Cloud Function provides automated model update capabilities for edge 
deployments in the MLOps pipeline. It integrates with Vertex AI Model Registry
and manages model deployments across distributed edge locations.

Functions:
- update_edge_models: HTTP-triggered function to update models at edge locations
- get_latest_model: Retrieve latest model from Vertex AI Model Registry
- update_deployment_manifest: Create deployment manifests for edge locations
- validate_model_version: Validate model version compatibility
"""

import functions_framework
import json
import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

# Google Cloud client libraries
from google.cloud import storage
from google.cloud import aiplatform
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Cloud Logging client
logging_client = cloud_logging.Client()
logging_client.setup_logging()

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', 'your-project-id')
EDGE_MODELS_BUCKET = os.environ.get('EDGE_MODELS_BUCKET', 'your-edge-models-bucket')
MLOPS_BUCKET = os.environ.get('MLOPS_BUCKET', 'mlops-artifacts-default')
DEFAULT_MODEL_NAME = 'edge-inference-model'

# Initialize clients
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

class ModelUpdateError(Exception):
    """Custom exception for model update operations."""
    pass

class EdgeModelUpdater:
    """Handles model updates for edge deployments."""
    
    def __init__(self):
        """Initialize the model updater with required clients."""
        try:
            # Initialize Vertex AI with project configuration
            aiplatform.init(project=PROJECT_ID)
            self.storage_client = storage.Client()
            logger.info(f"Initialized EdgeModelUpdater for project: {PROJECT_ID}")
        except Exception as e:
            logger.error(f"Failed to initialize EdgeModelUpdater: {e}")
            raise ModelUpdateError(f"Initialization failed: {e}")
    
    def get_latest_model(self, model_name: str = DEFAULT_MODEL_NAME) -> Optional[Dict[str, Any]]:
        """
        Retrieve the latest model from Vertex AI Model Registry.
        
        Args:
            model_name: Name of the model to retrieve
            
        Returns:
            Dict containing model information or None if not found
        """
        try:
            # List models with the specified display name
            models = aiplatform.Model.list(
                filter=f'display_name="{model_name}"',
                order_by="create_time desc"
            )
            
            if not models:
                logger.warning(f"No models found with name: {model_name}")
                return None
            
            latest_model = models[0]
            
            model_info = {
                'name': latest_model.name,
                'display_name': latest_model.display_name,
                'resource_name': latest_model.resource_name,
                'uri': getattr(latest_model, 'uri', ''),
                'version_id': getattr(latest_model, 'version_id', 'latest'),
                'create_time': latest_model.create_time.isoformat() if latest_model.create_time else None,
                'update_time': latest_model.update_time.isoformat() if latest_model.update_time else None,
                'description': getattr(latest_model, 'description', ''),
                'labels': getattr(latest_model, 'labels', {})
            }
            
            logger.info(f"Retrieved latest model: {model_info['display_name']}")
            return model_info
            
        except Exception as e:
            logger.error(f"Failed to retrieve model {model_name}: {e}")
            raise ModelUpdateError(f"Model retrieval failed: {e}")
    
    def validate_model_version(self, model_info: Dict[str, Any], 
                             requested_version: str) -> bool:
        """
        Validate that the model version is compatible for edge deployment.
        
        Args:
            model_info: Model information dictionary
            requested_version: Requested model version
            
        Returns:
            True if valid, False otherwise
        """
        try:
            # Basic validation checks
            if not model_info:
                logger.error("Model information is empty")
                return False
            
            # Check if model has required fields
            required_fields = ['name', 'display_name', 'resource_name']
            for field in required_fields:
                if field not in model_info or not model_info[field]:
                    logger.error(f"Model missing required field: {field}")
                    return False
            
            # Version format validation
            if not requested_version.startswith('v') or not requested_version[1:].isdigit():
                logger.error(f"Invalid version format: {requested_version}")
                return False
            
            logger.info(f"Model validation passed for version: {requested_version}")
            return True
            
        except Exception as e:
            logger.error(f"Model validation failed: {e}")
            return False
    
    def create_deployment_manifest(self, model_info: Dict[str, Any],
                                 model_version: str, edge_location: str) -> Dict[str, Any]:
        """
        Create a deployment manifest for edge model deployment.
        
        Args:
            model_info: Model information from Vertex AI
            model_version: Version tag for the deployment
            edge_location: Target edge location identifier
            
        Returns:
            Deployment manifest dictionary
        """
        try:
            timestamp = datetime.now(timezone.utc).isoformat()
            
            manifest = {
                'metadata': {
                    'version': '1.0',
                    'generated_at': timestamp,
                    'generator': 'edge-model-updater',
                    'edge_location': edge_location
                },
                'model': {
                    'name': model_info['display_name'],
                    'version': model_version,
                    'resource_name': model_info['resource_name'],
                    'uri': model_info.get('uri', ''),
                    'source_model_id': model_info['name'],
                    'description': model_info.get('description', ''),
                    'labels': model_info.get('labels', {})
                },
                'deployment': {
                    'target_location': edge_location,
                    'deployment_status': 'pending',
                    'created_at': timestamp,
                    'updated_at': timestamp,
                    'configuration': {
                        'max_batch_size': 32,
                        'timeout_seconds': 30,
                        'health_check_interval': 10,
                        'auto_scaling': {
                            'enabled': True,
                            'min_replicas': 1,
                            'max_replicas': 5
                        }
                    }
                },
                'compatibility': {
                    'framework': 'scikit-learn',
                    'python_version': '3.9',
                    'dependencies': [
                        'scikit-learn>=1.0.0',
                        'numpy>=1.20.0',
                        'pandas>=1.3.0'
                    ]
                },
                'monitoring': {
                    'enable_logging': True,
                    'enable_metrics': True,
                    'health_check_path': '/health',
                    'metrics_path': '/metrics'
                }
            }
            
            logger.info(f"Created deployment manifest for {edge_location}")
            return manifest
            
        except Exception as e:
            logger.error(f"Failed to create deployment manifest: {e}")
            raise ModelUpdateError(f"Manifest creation failed: {e}")
    
    def upload_to_edge_bucket(self, edge_location: str, model_version: str,
                            manifest: Dict[str, Any]) -> str:
        """
        Upload deployment manifest to the edge models bucket.
        
        Args:
            edge_location: Target edge location
            model_version: Model version
            manifest: Deployment manifest
            
        Returns:
            GCS path to uploaded manifest
        """
        try:
            bucket = self.storage_client.bucket(EDGE_MODELS_BUCKET)
            
            # Create blob path for the manifest
            blob_path = f"deployments/{edge_location}/{model_version}/manifest.json"
            blob = bucket.blob(blob_path)
            
            # Upload manifest as JSON
            blob.upload_from_string(
                json.dumps(manifest, indent=2),
                content_type='application/json'
            )
            
            # Set metadata
            blob.metadata = {
                'edge_location': edge_location,
                'model_version': model_version,
                'deployment_status': 'pending',
                'created_by': 'edge-model-updater'
            }
            blob.patch()
            
            gcs_path = f"gs://{EDGE_MODELS_BUCKET}/{blob_path}"
            logger.info(f"Uploaded manifest to: {gcs_path}")
            
            return gcs_path
            
        except Exception as e:
            logger.error(f"Failed to upload manifest to edge bucket: {e}")
            raise ModelUpdateError(f"Upload failed: {e}")
    
    def send_custom_metric(self, metric_name: str, value: float,
                          labels: Dict[str, str] = None):
        """
        Send custom metrics to Cloud Monitoring.
        
        Args:
            metric_name: Name of the metric
            value: Metric value
            labels: Additional labels for the metric
        """
        try:
            if labels is None:
                labels = {}
                
            # Add default labels
            labels.update({
                'function_name': 'edge-model-updater',
                'project_id': PROJECT_ID
            })
            
            # Create metric data point
            series = monitoring_v3.TimeSeries()
            series.metric.type = f"custom.googleapis.com/mlops/{metric_name}"
            series.resource.type = "cloud_function"
            series.resource.labels["function_name"] = "edge-model-updater"
            series.resource.labels["region"] = "us-central1"
            
            # Add custom labels
            for key, val in labels.items():
                series.metric.labels[key] = str(val)
            
            # Create data point
            point = monitoring_v3.Point()
            point.value.double_value = value
            point.interval.end_time.seconds = int(datetime.now().timestamp())
            series.points = [point]
            
            # Send to monitoring
            project_name = f"projects/{PROJECT_ID}"
            monitoring_client.create_time_series(
                name=project_name,
                time_series=[series]
            )
            
            logger.info(f"Sent metric {metric_name}: {value}")
            
        except Exception as e:
            logger.error(f"Failed to send metric {metric_name}: {e}")

def update_edge_models(request) -> Dict[str, Any]:
    """
    Main Cloud Function entry point for updating edge models.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with update results
    """
    start_time = datetime.now()
    
    try:
        # Parse request
        request_json = request.get_json(silent=True) or {}
        
        # Extract parameters
        model_name = request_json.get('model_name', DEFAULT_MODEL_NAME)
        model_version = request_json.get('model_version', 'v1')
        edge_locations = request_json.get('edge_locations', ['default'])
        force_update = request_json.get('force_update', False)
        
        logger.info(f"Starting model update for {model_name} version {model_version}")
        logger.info(f"Target edge locations: {edge_locations}")
        
        # Initialize updater
        updater = EdgeModelUpdater()
        
        # Get latest model from Vertex AI
        model_info = updater.get_latest_model(model_name)
        if not model_info:
            error_msg = f"No model found with name: {model_name}"
            logger.error(error_msg)
            return {'error': error_msg, 'status': 'failed'}, 404
        
        # Validate model version
        if not updater.validate_model_version(model_info, model_version):
            error_msg = f"Model validation failed for version: {model_version}"
            logger.error(error_msg)
            return {'error': error_msg, 'status': 'failed'}, 400
        
        # Process each edge location
        results = []
        successful_updates = 0
        failed_updates = 0
        
        for location in edge_locations:
            try:
                logger.info(f"Processing edge location: {location}")
                
                # Create deployment manifest
                manifest = updater.create_deployment_manifest(
                    model_info, model_version, location
                )
                
                # Upload to edge bucket
                gcs_path = updater.upload_to_edge_bucket(
                    location, model_version, manifest
                )
                
                # Record success
                result = {
                    'edge_location': location,
                    'status': 'success',
                    'model_version': model_version,
                    'manifest_path': gcs_path,
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }
                results.append(result)
                successful_updates += 1
                
                logger.info(f"Successfully updated edge location: {location}")
                
            except Exception as e:
                logger.error(f"Failed to update edge location {location}: {e}")
                
                result = {
                    'edge_location': location,
                    'status': 'error',
                    'error': str(e),
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }
                results.append(result)
                failed_updates += 1
        
        # Calculate processing time
        processing_time = (datetime.now() - start_time).total_seconds()
        
        # Send metrics
        updater.send_custom_metric('model_updates_successful', successful_updates)
        updater.send_custom_metric('model_updates_failed', failed_updates)
        updater.send_custom_metric('update_processing_time', processing_time)
        
        # Prepare response
        response = {
            'status': 'completed',
            'message': f'Model update initiated for {len(edge_locations)} edge locations',
            'model_info': {
                'name': model_info['display_name'],
                'version': model_version,
                'resource_name': model_info['resource_name']
            },
            'summary': {
                'total_locations': len(edge_locations),
                'successful_updates': successful_updates,
                'failed_updates': failed_updates,
                'processing_time_seconds': processing_time
            },
            'results': results,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        logger.info(f"Model update completed: {successful_updates} successful, {failed_updates} failed")
        
        return response, 200
        
    except ModelUpdateError as e:
        logger.error(f"Model update error: {e}")
        return {
            'error': str(e),
            'status': 'failed',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, 500
        
    except Exception as e:
        logger.error(f"Unexpected error in model update: {e}")
        return {
            'error': f'Internal server error: {str(e)}',
            'status': 'failed',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, 500

@functions_framework.http
def main(request):
    """
    Cloud Function HTTP entry point.
    
    This function serves as the main entry point for HTTP requests to the 
    edge model updater. It routes requests to the appropriate handler based
    on the request method and path.
    """
    try:
        # Handle CORS preflight requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Handle POST requests for model updates
        if request.method == 'POST':
            response_data, status_code = update_edge_models(request)
            
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            }
            
            return (json.dumps(response_data), status_code, headers)
        
        # Handle GET requests for health check
        elif request.method == 'GET':
            health_response = {
                'status': 'healthy',
                'function_name': 'edge-model-updater',
                'version': '1.0',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'project_id': PROJECT_ID,
                'edge_models_bucket': EDGE_MODELS_BUCKET
            }
            
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            }
            
            return (json.dumps(health_response), 200, headers)
        
        else:
            error_response = {
                'error': f'Method {request.method} not allowed',
                'allowed_methods': ['GET', 'POST', 'OPTIONS']
            }
            
            return (json.dumps(error_response), 405)
            
    except Exception as e:
        logger.error(f"Unexpected error in main handler: {e}")
        error_response = {
            'error': 'Internal server error',
            'details': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        return (json.dumps(error_response), 500)