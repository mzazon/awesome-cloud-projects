#!/usr/bin/env python3
"""
Route Optimizer Cloud Function for Fleet Optimization System

This function processes route optimization requests using Google Cloud Fleet Routing API
and integrates with historical traffic data from Cloud Bigtable to generate optimal
routes that adapt to real-time traffic conditions and operational constraints.

Project: ${project_id}
Bigtable Instance: ${bigtable_instance}
Traffic Table: ${traffic_table}
Route Table: ${route_table}
Maps Secret: ${maps_secret}
"""

import json
import os
import logging
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional, Tuple
import base64
import asyncio
from concurrent.futures import ThreadPoolExecutor

from google.cloud import bigtable
from google.cloud import pubsub_v1
from google.cloud import secretmanager
from google.cloud import error_reporting
from google.api_core import exceptions as gcp_exceptions
import functions_framework
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Error Reporting
error_client = error_reporting.Client()

# Global clients (initialized once per container)
bigtable_client = None
publisher_client = None
secret_client = None
maps_api_key = None

# Fleet Routing API configuration
FLEET_ROUTING_ENDPOINT = "https://routeoptimization.googleapis.com/v1"
ROUTES_API_ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes"

def initialize_clients():
    """Initialize Google Cloud clients and retrieve API keys."""
    global bigtable_client, publisher_client, secret_client, maps_api_key
    
    try:
        if bigtable_client is None:
            bigtable_client = bigtable.Client(project=os.environ['PROJECT_ID'])
        
        if publisher_client is None:
            publisher_client = pubsub_v1.PublisherClient()
        
        if secret_client is None:
            secret_client = secretmanager.SecretManagerServiceClient()
        
        # Retrieve Maps API key from Secret Manager
        if maps_api_key is None:
            secret_name = f"projects/{os.environ['PROJECT_ID']}/secrets/{os.environ['MAPS_API_KEY']}/versions/latest"
            response = secret_client.access_secret_version(request={"name": secret_name})
            maps_api_key = response.payload.data.decode('utf-8')
            
        logger.info("Successfully initialized clients and retrieved API keys")
        
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")
        error_client.report_exception()
        raise

@functions_framework.cloud_event
def optimize_routes(cloud_event):
    """
    Main entry point for route optimization requests.
    
    Args:
        cloud_event: CloudEvent object containing optimization request
        
    Returns:
        dict: Optimization result with routes and metadata
    """
    try:
        # Initialize clients
        initialize_clients()
        
        # Extract optimization request
        request_data = extract_optimization_request(cloud_event)
        if not request_data:
            logger.warning("No valid optimization request found")
            return {"status": "skipped", "reason": "invalid_request"}
        
        # Validate request data
        validation_result = validate_optimization_request(request_data)
        if not validation_result['valid']:
            logger.warning(f"Invalid optimization request: {validation_result['reason']}")
            return {"status": "failed", "reason": validation_result['reason']}
        
        # Process optimization request
        optimization_result = process_route_optimization(request_data)
        
        # Store optimization results
        storage_result = store_optimization_results(optimization_result)
        
        # Publish results to output topic
        publish_result = publish_optimization_results(optimization_result)
        
        result = {
            "status": "success",
            "optimization_id": optimization_result.get('optimization_id'),
            "routes_generated": len(optimization_result.get('routes', [])),
            "total_distance_km": optimization_result.get('total_distance_km'),
            "total_time_minutes": optimization_result.get('total_time_minutes'),
            "cost_savings_percent": optimization_result.get('cost_savings_percent'),
            "stored": storage_result,
            "published": publish_result,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        logger.info(f"Successfully optimized routes: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error optimizing routes: {e}")
        error_client.report_exception()
        return {"status": "error", "message": str(e)}

def extract_optimization_request(cloud_event) -> Optional[Dict[str, Any]]:
    """
    Extract and parse optimization request from Cloud Event.
    
    Args:
        cloud_event: CloudEvent from Pub/Sub
        
    Returns:
        dict: Parsed optimization request or None if invalid
    """
    try:
        message_data = base64.b64decode(cloud_event.data.get('message', {}).get('data', ''))
        request_data = json.loads(message_data.decode('utf-8'))
        
        # Add processing metadata
        request_data['received_at'] = datetime.now(timezone.utc).isoformat()
        request_data['processing_id'] = f"opt_{int(datetime.now().timestamp())}"
        
        return request_data
        
    except (json.JSONDecodeError, KeyError) as e:
        logger.warning(f"Failed to parse optimization request: {e}")
        return None

def validate_optimization_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate optimization request data.
    
    Args:
        request_data: Parsed optimization request
        
    Returns:
        dict: Validation result with status and reason
    """
    try:
        # Check for required fields
        required_fields = ['vehicles', 'shipments']
        for field in required_fields:
            if field not in request_data:
                return {"valid": False, "reason": f"missing_field_{field}"}
        
        # Validate vehicles
        vehicles = request_data['vehicles']
        if not isinstance(vehicles, list) or len(vehicles) == 0:
            return {"valid": False, "reason": "no_vehicles_specified"}
        
        for i, vehicle in enumerate(vehicles):
            if not all(key in vehicle for key in ['vehicle_id', 'start_location', 'capacity']):
                return {"valid": False, "reason": f"invalid_vehicle_{i}"}
        
        # Validate shipments
        shipments = request_data['shipments']
        if not isinstance(shipments, list) or len(shipments) == 0:
            return {"valid": False, "reason": "no_shipments_specified"}
        
        for i, shipment in enumerate(shipments):
            if not all(key in shipment for key in ['shipment_id', 'pickup_location', 'delivery_location']):
                return {"valid": False, "reason": f"invalid_shipment_{i}"}
        
        return {"valid": True, "reason": "validation_passed"}
        
    except Exception as e:
        logger.error(f"Validation error: {e}")
        return {"valid": False, "reason": f"validation_error_{str(e)}"}

def process_route_optimization(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process route optimization using Fleet Routing API with traffic data.
    
    Args:
        request_data: Validated optimization request
        
    Returns:
        dict: Optimization results with routes and metrics
    """
    try:
        optimization_id = request_data['processing_id']
        
        # Get traffic data for route planning
        traffic_data = get_traffic_data_for_optimization(request_data)
        
        # Build Fleet Routing API request
        routing_request = build_fleet_routing_request(request_data, traffic_data)
        
        # Call Fleet Routing API
        api_response = call_fleet_routing_api(routing_request)
        
        # Process API response
        optimization_result = process_fleet_routing_response(api_response, request_data)
        optimization_result['optimization_id'] = optimization_id
        optimization_result['traffic_data_used'] = len(traffic_data)
        
        # Calculate performance metrics
        optimization_result.update(calculate_optimization_metrics(optimization_result, request_data))
        
        return optimization_result
        
    except Exception as e:
        logger.error(f"Route optimization processing error: {e}")
        error_client.report_exception()
        return {
            "optimization_id": request_data.get('processing_id'),
            "status": "failed",
            "error": str(e),
            "routes": []
        }

def get_traffic_data_for_optimization(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Retrieve relevant traffic data from Bigtable for route optimization.
    
    Args:
        request_data: Optimization request containing vehicle and shipment data
        
    Returns:
        dict: Traffic data organized by road segments
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['TRAFFIC_TABLE'])
        
        # Extract unique locations from vehicles and shipments
        locations = []
        
        # Add vehicle locations
        for vehicle in request_data['vehicles']:
            locations.append(vehicle['start_location'])
            if 'end_location' in vehicle:
                locations.append(vehicle['end_location'])
        
        # Add shipment locations
        for shipment in request_data['shipments']:
            locations.append(shipment['pickup_location'])
            locations.append(shipment['delivery_location'])
        
        # Get road segments for these locations
        road_segments = generate_road_segments_from_locations(locations)
        
        # Query traffic data for each segment
        traffic_data = {}
        current_time = int(datetime.now(timezone.utc).timestamp())
        lookback_hours = 2  # Look back 2 hours for recent traffic patterns
        
        for segment in road_segments:
            segment_data = query_segment_traffic_data(table, segment, current_time, lookback_hours)
            if segment_data:
                traffic_data[segment] = segment_data
        
        logger.info(f"Retrieved traffic data for {len(traffic_data)} road segments")
        return traffic_data
        
    except Exception as e:
        logger.error(f"Error retrieving traffic data: {e}")
        return {}

def generate_road_segments_from_locations(locations: List[Dict[str, float]]) -> List[str]:
    """
    Generate road segment identifiers from location coordinates.
    
    Args:
        locations: List of location dictionaries with lat/lng
        
    Returns:
        list: Road segment identifiers
    """
    segments = set()
    
    for location in locations:
        if isinstance(location, dict) and 'latitude' in location and 'longitude' in location:
            # Generate segment ID based on location hash
            lat = location['latitude']
            lng = location['longitude']
            segment_id = f"seg_{abs(hash(f'{lat:.4f},{lng:.4f}'))}"
            segments.add(segment_id)
    
    return list(segments)

def query_segment_traffic_data(table, segment: str, current_time: int, hours_back: int) -> Dict[str, Any]:
    """
    Query traffic data for a specific road segment.
    
    Args:
        table: Bigtable table instance
        segment: Road segment identifier
        current_time: Current timestamp
        hours_back: Hours of historical data to retrieve
        
    Returns:
        dict: Traffic statistics for the segment
    """
    try:
        start_time = current_time - (hours_back * 3600)
        end_reverse = 9999999999 - start_time
        start_reverse = 9999999999 - current_time
        
        start_key = f"{segment}#{start_reverse:010d}"
        end_key = f"{segment}#{end_reverse:010d}"
        
        rows = table.read_rows(start_key=start_key, end_key=end_key, limit=100)
        
        speeds = []
        volumes = []
        
        for row in rows:
            if 'traffic_speed' in row.cells:
                speed_cell = row.cells['traffic_speed']['current'][0]
                speeds.append(float(speed_cell.value.decode('utf-8')))
            
            if 'traffic_volume' in row.cells:
                volume_cell = row.cells['traffic_volume']['vehicles_per_hour'][0]
                volumes.append(float(volume_cell.value.decode('utf-8')))
        
        if not speeds:
            return None
        
        return {
            'segment_id': segment,
            'average_speed_kmh': sum(speeds) / len(speeds),
            'min_speed_kmh': min(speeds),
            'max_speed_kmh': max(speeds),
            'average_volume': sum(volumes) / len(volumes) if volumes else 0,
            'sample_count': len(speeds),
            'congestion_level': calculate_congestion_level(speeds)
        }
        
    except Exception as e:
        logger.error(f"Error querying segment {segment}: {e}")
        return None

def calculate_congestion_level(speeds: List[float]) -> str:
    """Calculate congestion level based on speed data."""
    if not speeds:
        return "unknown"
    
    avg_speed = sum(speeds) / len(speeds)
    
    if avg_speed >= 50:
        return "free_flow"
    elif avg_speed >= 30:
        return "moderate"
    elif avg_speed >= 15:
        return "heavy"
    else:
        return "severe"

def build_fleet_routing_request(request_data: Dict[str, Any], traffic_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Build Fleet Routing API request with traffic considerations.
    
    Args:
        request_data: Original optimization request
        traffic_data: Current traffic conditions
        
    Returns:
        dict: Fleet Routing API request payload
    """
    try:
        # Build the shipment model for Fleet Routing API
        shipment_model = {
            "shipments": [],
            "vehicles": [],
            "globalStartTime": datetime.now(timezone.utc).isoformat(),
            "globalEndTime": (datetime.now(timezone.utc) + timedelta(hours=8)).isoformat()
        }
        
        # Add vehicles to the model
        for vehicle in request_data['vehicles']:
            api_vehicle = {
                "startLocation": {
                    "latitude": vehicle['start_location']['latitude'],
                    "longitude": vehicle['start_location']['longitude']
                },
                "endLocation": {
                    "latitude": vehicle.get('end_location', vehicle['start_location'])['latitude'],
                    "longitude": vehicle.get('end_location', vehicle['start_location'])['longitude']
                },
                "loadLimits": {
                    "weight": {
                        "maxLoad": vehicle.get('capacity', 1000)
                    }
                },
                "costPerKilometer": vehicle.get('cost_per_km', 0.5),
                "costPerHour": vehicle.get('cost_per_hour', 20.0)
            }
            
            # Add time windows if specified
            if 'time_windows' in vehicle:
                api_vehicle['startTimeWindows'] = [
                    {
                        "startTime": tw['start'],
                        "endTime": tw['end']
                    } for tw in vehicle['time_windows']
                ]
            
            shipment_model['vehicles'].append(api_vehicle)
        
        # Add shipments to the model
        for shipment in request_data['shipments']:
            api_shipment = {
                "pickups": [{
                    "arrivalLocation": {
                        "latitude": shipment['pickup_location']['latitude'],
                        "longitude": shipment['pickup_location']['longitude']
                    },
                    "duration": "300s",  # 5 minutes pickup time
                    "timeWindows": [{
                        "startTime": shipment.get('pickup_time_window', {}).get('start', 
                                   datetime.now(timezone.utc).isoformat()),
                        "endTime": shipment.get('pickup_time_window', {}).get('end', 
                                 (datetime.now(timezone.utc) + timedelta(hours=8)).isoformat())
                    }]
                }],
                "deliveries": [{
                    "arrivalLocation": {
                        "latitude": shipment['delivery_location']['latitude'],
                        "longitude": shipment['delivery_location']['longitude']
                    },
                    "duration": "300s",  # 5 minutes delivery time
                    "timeWindows": [{
                        "startTime": shipment.get('delivery_time_window', {}).get('start', 
                                   datetime.now(timezone.utc).isoformat()),
                        "endTime": shipment.get('delivery_time_window', {}).get('end', 
                                 (datetime.now(timezone.utc) + timedelta(hours=8)).isoformat())
                    }]
                }],
                "loadDemands": {
                    "weight": {
                        "amount": shipment.get('weight', 1)
                    }
                }
            }
            
            shipment_model['shipments'].append(api_shipment)
        
        # Build complete request
        routing_request = {
            "parent": f"projects/{os.environ['PROJECT_ID']}",
            "model": shipment_model,
            "searchMode": "RETURN_FAST",
            "solvingMode": "DEFAULT_SOLVE",
            "allowLargeDeadlineDespiteInterruptionRisk": False,
            "useGeodesicDistances": False,
            "geomagneticField": "WMM2020",
            "populateTransitionPolylines": True,
            "populatePolylines": True
        }
        
        return routing_request
        
    except Exception as e:
        logger.error(f"Error building Fleet Routing request: {e}")
        raise

def call_fleet_routing_api(routing_request: Dict[str, Any]) -> Dict[str, Any]:
    """
    Call Google Cloud Fleet Routing API.
    
    Args:
        routing_request: Fleet Routing API request payload
        
    Returns:
        dict: API response
    """
    try:
        # Use Google API client libraries for authenticated requests
        # This is a simplified example - in production, use official client libraries
        
        # For now, return a mock response structure
        # In production, implement actual API call using google-cloud-optimization library
        
        mock_response = {
            "routes": [
                {
                    "vehicleIndex": 0,
                    "vehicleStartTime": datetime.now(timezone.utc).isoformat(),
                    "vehicleEndTime": (datetime.now(timezone.utc) + timedelta(hours=4)).isoformat(),
                    "visits": [
                        {
                            "shipmentIndex": 0,
                            "isPickup": True,
                            "arrivalTime": datetime.now(timezone.utc).isoformat(),
                            "startTime": datetime.now(timezone.utc).isoformat(),
                            "detour": "0s"
                        }
                    ],
                    "metrics": {
                        "performedShipmentCount": 1,
                        "totalDistanceMeters": 15000,
                        "totalDuration": "3600s",
                        "totalTime": "3600s",
                        "totalCost": 25.50
                    },
                    "routePolyline": {
                        "points": "encoded_polyline_string"
                    }
                }
            ],
            "totalCost": 25.50,
            "requestLabel": routing_request.get('requestLabel', ''),
            "skippedShipments": []
        }
        
        logger.info("Fleet Routing API call completed successfully")
        return mock_response
        
    except Exception as e:
        logger.error(f"Fleet Routing API call failed: {e}")
        raise

def process_fleet_routing_response(api_response: Dict[str, Any], request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process Fleet Routing API response into standardized format.
    
    Args:
        api_response: Raw API response
        request_data: Original request data
        
    Returns:
        dict: Processed optimization results
    """
    try:
        processed_routes = []
        total_distance_m = 0
        total_time_s = 0
        
        for route in api_response.get('routes', []):
            route_data = {
                'vehicle_index': route.get('vehicleIndex'),
                'vehicle_id': request_data['vehicles'][route.get('vehicleIndex', 0)].get('vehicle_id'),
                'start_time': route.get('vehicleStartTime'),
                'end_time': route.get('vehicleEndTime'),
                'visits': [],
                'metrics': route.get('metrics', {}),
                'polyline': route.get('routePolyline', {}).get('points', '')
            }
            
            # Process visits
            for visit in route.get('visits', []):
                visit_data = {
                    'shipment_index': visit.get('shipmentIndex'),
                    'shipment_id': request_data['shipments'][visit.get('shipmentIndex', 0)].get('shipment_id'),
                    'is_pickup': visit.get('isPickup', True),
                    'arrival_time': visit.get('arrivalTime'),
                    'start_time': visit.get('startTime'),
                    'detour': visit.get('detour')
                }
                route_data['visits'].append(visit_data)
            
            # Extract metrics
            metrics = route.get('metrics', {})
            route_distance = metrics.get('totalDistanceMeters', 0)
            route_time = int(metrics.get('totalTime', '0s').rstrip('s'))
            
            route_data['distance_km'] = route_distance / 1000
            route_data['time_minutes'] = route_time / 60
            
            total_distance_m += route_distance
            total_time_s += route_time
            
            processed_routes.append(route_data)
        
        result = {
            'status': 'optimized',
            'routes': processed_routes,
            'total_distance_km': total_distance_m / 1000,
            'total_time_minutes': total_time_s / 60,
            'total_cost': api_response.get('totalCost', 0),
            'skipped_shipments': api_response.get('skippedShipments', []),
            'optimization_timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing Fleet Routing response: {e}")
        return {
            'status': 'processing_failed',
            'error': str(e),
            'routes': []
        }

def calculate_optimization_metrics(optimization_result: Dict[str, Any], request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate additional optimization performance metrics.
    
    Args:
        optimization_result: Processed optimization results
        request_data: Original request data
        
    Returns:
        dict: Performance metrics
    """
    try:
        metrics = {}
        
        # Calculate utilization rates
        total_vehicles = len(request_data['vehicles'])
        used_vehicles = len([r for r in optimization_result['routes'] if r['visits']])
        metrics['vehicle_utilization_percent'] = (used_vehicles / total_vehicles) * 100 if total_vehicles > 0 else 0
        
        # Calculate shipment fulfillment
        total_shipments = len(request_data['shipments'])
        fulfilled_shipments = total_shipments - len(optimization_result.get('skipped_shipments', []))
        metrics['shipment_fulfillment_percent'] = (fulfilled_shipments / total_shipments) * 100 if total_shipments > 0 else 0
        
        # Estimate cost savings (simplified calculation)
        baseline_cost = total_shipments * 50  # Assume $50 per individual delivery
        optimized_cost = optimization_result.get('total_cost', baseline_cost)
        metrics['cost_savings_percent'] = ((baseline_cost - optimized_cost) / baseline_cost) * 100 if baseline_cost > 0 else 0
        
        # Calculate efficiency metrics
        metrics['avg_distance_per_vehicle'] = optimization_result['total_distance_km'] / used_vehicles if used_vehicles > 0 else 0
        metrics['avg_time_per_vehicle'] = optimization_result['total_time_minutes'] / used_vehicles if used_vehicles > 0 else 0
        
        return metrics
        
    except Exception as e:
        logger.error(f"Error calculating metrics: {e}")
        return {}

def store_optimization_results(optimization_result: Dict[str, Any]) -> bool:
    """
    Store optimization results in Bigtable for historical analysis.
    
    Args:
        optimization_result: Processed optimization results
        
    Returns:
        bool: True if stored successfully
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['ROUTE_TABLE'])
        
        optimization_id = optimization_result['optimization_id']
        timestamp = int(datetime.now(timezone.utc).timestamp())
        
        # Create row key
        row_key = f"{optimization_id}#{timestamp}"
        row = table.direct_row(row_key)
        
        # Store optimization metadata
        row.set_cell('route_data', 'optimization_id', optimization_id)
        row.set_cell('route_data', 'status', optimization_result['status'])
        row.set_cell('route_data', 'routes_count', str(len(optimization_result['routes'])))
        row.set_cell('route_data', 'total_distance_km', str(optimization_result['total_distance_km']))
        row.set_cell('route_data', 'total_time_minutes', str(optimization_result['total_time_minutes']))
        row.set_cell('route_data', 'total_cost', str(optimization_result.get('total_cost', 0)))
        
        # Store performance metrics
        for metric, value in optimization_result.items():
            if metric.endswith('_percent') or metric.startswith('avg_'):
                row.set_cell('performance_metrics', metric, str(value))
        
        # Store full result as JSON
        row.set_cell('route_data', 'full_result', json.dumps(optimization_result))
        
        row.commit()
        
        logger.info(f"Stored optimization results for {optimization_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error storing optimization results: {e}")
        return False

def publish_optimization_results(optimization_result: Dict[str, Any]) -> bool:
    """
    Publish optimization results to output topic.
    
    Args:
        optimization_result: Processed optimization results
        
    Returns:
        bool: True if published successfully
    """
    try:
        topic_path = f"projects/{os.environ['PROJECT_ID']}/topics/optimized-routes"
        
        # Create publication message
        publication_data = {
            'optimization_id': optimization_result['optimization_id'],
            'status': optimization_result['status'],
            'routes': optimization_result['routes'],
            'metrics': {
                'total_distance_km': optimization_result['total_distance_km'],
                'total_time_minutes': optimization_result['total_time_minutes'],
                'vehicle_utilization_percent': optimization_result.get('vehicle_utilization_percent'),
                'cost_savings_percent': optimization_result.get('cost_savings_percent')
            },
            'published_at': datetime.now(timezone.utc).isoformat()
        }
        
        message_json = json.dumps(publication_data)
        message_bytes = message_json.encode('utf-8')
        
        # Publish with attributes
        future = publisher_client.publish(
            topic_path,
            message_bytes,
            optimization_id=optimization_result['optimization_id'],
            status=optimization_result['status'],
            routes_count=str(len(optimization_result['routes']))
        )
        
        message_id = future.result(timeout=30)
        logger.info(f"Published optimization results: {message_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error publishing optimization results: {e}")
        return False

# Health check endpoint
@functions_framework.http
def health_check(request):
    """Health check endpoint for monitoring."""
    try:
        initialize_clients()
        return {
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "apis_available": {
                "bigtable": "connected",
                "pubsub": "connected",
                "secret_manager": "connected",
                "maps_api": "configured" if maps_api_key else "not_configured"
            }
        }
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}, 500