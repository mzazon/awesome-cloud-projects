#!/usr/bin/env python3
"""
Fleet Management Dashboard Cloud Function

This function serves a comprehensive web-based dashboard for monitoring
real-time fleet operations, displaying vehicle locations, traffic conditions,
optimization metrics, and system health for fleet managers.

Project: ${project_id}
Bigtable Instance: ${bigtable_instance}
Traffic Table: ${traffic_table}
Location Table: ${location_table}
Route Table: ${route_table}
"""

import json
import os
import logging
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional
import base64

from google.cloud import bigtable
from google.cloud import error_reporting
from flask import Flask, render_template_string, request, jsonify
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Error Reporting
error_client = error_reporting.Client()

# Global clients
bigtable_client = None

# Flask app for dashboard
app = Flask(__name__)

def initialize_clients():
    """Initialize Google Cloud clients."""
    global bigtable_client
    
    try:
        if bigtable_client is None:
            bigtable_client = bigtable.Client(project=os.environ['PROJECT_ID'])
            
        logger.info("Successfully initialized Bigtable client")
        
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")
        error_client.report_exception()
        raise

@functions_framework.http
def fleet_dashboard(request):
    """
    Main entry point for fleet management dashboard.
    
    Args:
        request: Flask request object
        
    Returns:
        HTML dashboard or JSON API response
    """
    try:
        initialize_clients()
        
        # Handle API requests
        if request.path.startswith('/api/'):
            return handle_api_request(request)
        
        # Serve main dashboard
        dashboard_data = get_dashboard_data()
        dashboard_html = render_dashboard_html(dashboard_data)
        
        return dashboard_html
        
    except Exception as e:
        logger.error(f"Dashboard error: {e}")
        error_client.report_exception()
        return f"<h1>Dashboard Error</h1><p>{str(e)}</p>", 500

def handle_api_request(request):
    """Handle API requests for dashboard data."""
    try:
        path = request.path
        
        if path == '/api/vehicles':
            return jsonify(get_vehicle_locations())
        elif path == '/api/traffic':
            return jsonify(get_traffic_conditions())
        elif path == '/api/routes':
            return jsonify(get_recent_optimizations())
        elif path == '/api/metrics':
            return jsonify(get_system_metrics())
        elif path == '/api/health':
            return jsonify(get_system_health())
        else:
            return jsonify({"error": "Unknown API endpoint"}), 404
            
    except Exception as e:
        logger.error(f"API request error: {e}")
        return jsonify({"error": str(e)}), 500

def get_dashboard_data() -> Dict[str, Any]:
    """
    Gather all data needed for the dashboard.
    
    Returns:
        dict: Complete dashboard data
    """
    try:
        dashboard_data = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'vehicles': get_vehicle_locations(),
            'traffic': get_traffic_conditions(),
            'recent_optimizations': get_recent_optimizations(),
            'system_metrics': get_system_metrics(),
            'system_health': get_system_health()
        }
        
        # Calculate summary statistics
        dashboard_data['summary'] = calculate_summary_statistics(dashboard_data)
        
        return dashboard_data
        
    except Exception as e:
        logger.error(f"Error gathering dashboard data: {e}")
        return {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'error': str(e),
            'vehicles': [],
            'traffic': [],
            'recent_optimizations': [],
            'system_metrics': {},
            'system_health': {'status': 'error'}
        }

def get_vehicle_locations() -> List[Dict[str, Any]]:
    """
    Get current vehicle locations from Bigtable.
    
    Returns:
        list: Vehicle location data
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['LOCATION_TABLE'])
        
        # Get recent vehicle locations (last 2 hours)
        current_time = int(datetime.now(timezone.utc).timestamp())
        cutoff_time = current_time - (2 * 3600)  # 2 hours ago
        
        vehicles = {}
        
        # Scan table for recent locations
        rows = table.read_rows(limit=1000)
        
        for row in rows:
            try:
                # Parse row key: vehicle_id#reverse_timestamp
                row_key = row.row_key.decode('utf-8')
                vehicle_id, reverse_timestamp_str = row_key.split('#', 1)
                
                # Convert reverse timestamp back to actual timestamp
                reverse_timestamp = int(reverse_timestamp_str)
                actual_timestamp = 9999999999 - reverse_timestamp
                
                # Skip old locations
                if actual_timestamp < cutoff_time:
                    continue
                
                # Only keep the most recent location per vehicle
                if vehicle_id not in vehicles or actual_timestamp > vehicles[vehicle_id]['timestamp']:
                    location_data = {
                        'vehicle_id': vehicle_id,
                        'timestamp': actual_timestamp,
                        'datetime': datetime.fromtimestamp(actual_timestamp, timezone.utc).isoformat()
                    }
                    
                    # Extract location data
                    if 'location' in row.cells:
                        if 'latitude' in row.cells['location']:
                            location_data['latitude'] = float(row.cells['location']['latitude'][0].value.decode('utf-8'))
                        if 'longitude' in row.cells['location']:
                            location_data['longitude'] = float(row.cells['location']['longitude'][0].value.decode('utf-8'))
                    
                    # Extract status data
                    if 'status' in row.cells:
                        if 'speed' in row.cells['status']:
                            location_data['speed'] = float(row.cells['status']['speed'][0].value.decode('utf-8'))
                        if 'heading' in row.cells['status']:
                            location_data['heading'] = float(row.cells['status']['heading'][0].value.decode('utf-8'))
                    
                    # Extract route info
                    if 'route_info' in row.cells:
                        if 'road_segment' in row.cells['route_info']:
                            location_data['road_segment'] = row.cells['route_info']['road_segment'][0].value.decode('utf-8')
                    
                    # Determine vehicle status
                    location_data['status'] = determine_vehicle_status(location_data)
                    
                    vehicles[vehicle_id] = location_data
                    
            except Exception as e:
                logger.warning(f"Error processing vehicle location row: {e}")
                continue
        
        vehicle_list = list(vehicles.values())
        logger.info(f"Retrieved locations for {len(vehicle_list)} vehicles")
        
        return vehicle_list
        
    except Exception as e:
        logger.error(f"Error retrieving vehicle locations: {e}")
        return []

def determine_vehicle_status(location_data: Dict[str, Any]) -> str:
    """Determine vehicle status based on location data."""
    try:
        # Check how recent the location is
        current_time = datetime.now(timezone.utc).timestamp()
        location_age = current_time - location_data['timestamp']
        
        if location_age > 1800:  # 30 minutes
            return 'offline'
        
        # Check speed to determine if moving
        speed = location_data.get('speed', 0)
        if speed < 2:
            return 'idle'
        elif speed > 2 and speed < 60:
            return 'active'
        else:
            return 'speeding'
            
    except Exception:
        return 'unknown'

def get_traffic_conditions() -> List[Dict[str, Any]]:
    """
    Get current traffic conditions from Bigtable.
    
    Returns:
        list: Traffic condition data
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['TRAFFIC_TABLE'])
        
        # Get recent traffic data (last hour)
        current_time = int(datetime.now(timezone.utc).timestamp())
        cutoff_time = current_time - 3600  # 1 hour ago
        
        traffic_segments = {}
        
        # Scan table for recent traffic data
        rows = table.read_rows(limit=500)
        
        for row in rows:
            try:
                row_key = row.row_key.decode('utf-8')
                segment_id, reverse_timestamp_str = row_key.split('#', 1)
                
                reverse_timestamp = int(reverse_timestamp_str)
                actual_timestamp = 9999999999 - reverse_timestamp
                
                # Skip old data
                if actual_timestamp < cutoff_time:
                    continue
                
                # Only keep the most recent data per segment
                if segment_id not in traffic_segments or actual_timestamp > traffic_segments[segment_id]['timestamp']:
                    traffic_data = {
                        'segment_id': segment_id,
                        'timestamp': actual_timestamp,
                        'datetime': datetime.fromtimestamp(actual_timestamp, timezone.utc).isoformat()
                    }
                    
                    # Extract traffic metrics
                    if 'traffic_speed' in row.cells:
                        if 'current' in row.cells['traffic_speed']:
                            traffic_data['speed'] = float(row.cells['traffic_speed']['current'][0].value.decode('utf-8'))
                    
                    if 'traffic_volume' in row.cells:
                        if 'vehicles_per_hour' in row.cells['traffic_volume']:
                            traffic_data['volume'] = float(row.cells['traffic_volume']['vehicles_per_hour'][0].value.decode('utf-8'))
                    
                    if 'road_conditions' in row.cells:
                        if 'weather' in row.cells['road_conditions']:
                            traffic_data['conditions'] = row.cells['road_conditions']['weather'][0].value.decode('utf-8')
                    
                    # Determine congestion level
                    traffic_data['congestion_level'] = determine_congestion_level(traffic_data.get('speed', 50))
                    
                    traffic_segments[segment_id] = traffic_data
                    
            except Exception as e:
                logger.warning(f"Error processing traffic row: {e}")
                continue
        
        traffic_list = list(traffic_segments.values())
        logger.info(f"Retrieved traffic data for {len(traffic_list)} segments")
        
        return traffic_list
        
    except Exception as e:
        logger.error(f"Error retrieving traffic conditions: {e}")
        return []

def determine_congestion_level(speed: float) -> str:
    """Determine congestion level based on speed."""
    if speed >= 50:
        return 'free_flow'
    elif speed >= 30:
        return 'moderate'
    elif speed >= 15:
        return 'heavy'
    else:
        return 'severe'

def get_recent_optimizations() -> List[Dict[str, Any]]:
    """
    Get recent route optimizations from Bigtable.
    
    Returns:
        list: Recent optimization data
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['ROUTE_TABLE'])
        
        # Get recent optimizations (last 24 hours)
        optimizations = []
        
        rows = table.read_rows(limit=50)
        
        for row in rows:
            try:
                optimization_data = {}
                
                # Extract optimization metadata
                if 'route_data' in row.cells:
                    for column, cells in row.cells['route_data'].items():
                        if cells:
                            value = cells[0].value.decode('utf-8')
                            if column == 'full_result':
                                try:
                                    optimization_data['full_result'] = json.loads(value)
                                except:
                                    pass
                            else:
                                optimization_data[column] = value
                
                # Extract performance metrics
                if 'performance_metrics' in row.cells:
                    optimization_data['metrics'] = {}
                    for column, cells in row.cells['performance_metrics'].items():
                        if cells:
                            try:
                                optimization_data['metrics'][column] = float(cells[0].value.decode('utf-8'))
                            except:
                                optimization_data['metrics'][column] = cells[0].value.decode('utf-8')
                
                if optimization_data:
                    optimizations.append(optimization_data)
                    
            except Exception as e:
                logger.warning(f"Error processing optimization row: {e}")
                continue
        
        logger.info(f"Retrieved {len(optimizations)} recent optimizations")
        return optimizations
        
    except Exception as e:
        logger.error(f"Error retrieving optimizations: {e}")
        return []

def get_system_metrics() -> Dict[str, Any]:
    """
    Calculate system performance metrics.
    
    Returns:
        dict: System metrics
    """
    try:
        metrics = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'uptime_hours': 24,  # Simplified - would calculate actual uptime
            'total_vehicles_tracked': 0,
            'active_vehicles': 0,
            'total_optimizations_today': 0,
            'avg_optimization_time_seconds': 0,
            'data_freshness_minutes': 0
        }
        
        # Get actual metrics from data
        vehicles = get_vehicle_locations()
        metrics['total_vehicles_tracked'] = len(vehicles)
        metrics['active_vehicles'] = len([v for v in vehicles if v.get('status') == 'active'])
        
        optimizations = get_recent_optimizations()
        metrics['total_optimizations_today'] = len(optimizations)
        
        if optimizations:
            # Calculate average optimization metrics
            total_cost_savings = sum(opt.get('metrics', {}).get('cost_savings_percent', 0) for opt in optimizations)
            metrics['avg_cost_savings_percent'] = total_cost_savings / len(optimizations)
        
        return metrics
        
    except Exception as e:
        logger.error(f"Error calculating system metrics: {e}")
        return {'error': str(e)}

def get_system_health() -> Dict[str, Any]:
    """
    Check system health status.
    
    Returns:
        dict: System health information
    """
    try:
        health = {
            'status': 'healthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'components': {
                'bigtable': 'healthy',
                'location_tracking': 'healthy',
                'traffic_monitoring': 'healthy',
                'route_optimization': 'healthy'
            },
            'alerts': []
        }
        
        # Check if we have recent vehicle data
        vehicles = get_vehicle_locations()
        if len(vehicles) == 0:
            health['components']['location_tracking'] = 'warning'
            health['alerts'].append('No recent vehicle location data')
        
        # Check if we have recent traffic data
        traffic = get_traffic_conditions()
        if len(traffic) == 0:
            health['components']['traffic_monitoring'] = 'warning'
            health['alerts'].append('No recent traffic condition data')
        
        # Check if we have recent optimizations
        optimizations = get_recent_optimizations()
        if len(optimizations) == 0:
            health['components']['route_optimization'] = 'warning'
            health['alerts'].append('No recent route optimizations')
        
        # Overall status
        if any(status == 'error' for status in health['components'].values()):
            health['status'] = 'error'
        elif any(status == 'warning' for status in health['components'].values()):
            health['status'] = 'warning'
        
        return health
        
    except Exception as e:
        logger.error(f"Error checking system health: {e}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

def calculate_summary_statistics(dashboard_data: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate summary statistics for dashboard."""
    try:
        vehicles = dashboard_data['vehicles']
        traffic = dashboard_data['traffic']
        optimizations = dashboard_data['recent_optimizations']
        
        summary = {
            'active_vehicles': len([v for v in vehicles if v.get('status') == 'active']),
            'total_vehicles': len(vehicles),
            'avg_vehicle_speed': 0,
            'traffic_segments_monitored': len(traffic),
            'severe_congestion_segments': len([t for t in traffic if t.get('congestion_level') == 'severe']),
            'optimizations_today': len(optimizations),
            'total_distance_optimized_km': 0,
            'avg_cost_savings_percent': 0
        }
        
        # Calculate average vehicle speed
        speeds = [v.get('speed', 0) for v in vehicles if v.get('speed')]
        if speeds:
            summary['avg_vehicle_speed'] = sum(speeds) / len(speeds)
        
        # Calculate optimization metrics
        if optimizations:
            total_distance = sum(float(opt.get('total_distance_km', 0)) for opt in optimizations if opt.get('total_distance_km'))
            summary['total_distance_optimized_km'] = total_distance
            
            cost_savings = [opt.get('metrics', {}).get('cost_savings_percent', 0) for opt in optimizations]
            if cost_savings:
                summary['avg_cost_savings_percent'] = sum(cost_savings) / len(cost_savings)
        
        return summary
        
    except Exception as e:
        logger.error(f"Error calculating summary statistics: {e}")
        return {}

def render_dashboard_html(dashboard_data: Dict[str, Any]) -> str:
    """
    Render the HTML dashboard using the gathered data.
    
    Args:
        dashboard_data: Complete dashboard data
        
    Returns:
        str: Rendered HTML dashboard
    """
    html_template = '''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Fleet Optimization Dashboard</title>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                color: #333;
            }
            
            .header {
                background: rgba(255, 255, 255, 0.95);
                backdrop-filter: blur(10px);
                padding: 20px;
                box-shadow: 0 2px 20px rgba(0,0,0,0.1);
            }
            
            .header h1 {
                color: #4285F4;
                font-size: 2.5em;
                margin-bottom: 10px;
                display: flex;
                align-items: center;
                gap: 15px;
            }
            
            .header .subtitle {
                color: #666;
                font-size: 1.1em;
                font-weight: 300;
            }
            
            .dashboard-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                gap: 20px;
                padding: 20px;
                max-width: 1400px;
                margin: 0 auto;
            }
            
            .metric-cards {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 15px;
                margin-bottom: 20px;
            }
            
            .metric-card {
                background: rgba(255, 255, 255, 0.95);
                border-radius: 15px;
                padding: 20px;
                text-align: center;
                box-shadow: 0 8px 32px rgba(0,0,0,0.1);
                backdrop-filter: blur(10px);
                border: 1px solid rgba(255,255,255,0.2);
                transition: transform 0.3s ease;
            }
            
            .metric-card:hover {
                transform: translateY(-5px);
            }
            
            .metric-value {
                font-size: 2.5em;
                font-weight: bold;
                margin-bottom: 5px;
            }
            
            .metric-label {
                color: #666;
                font-size: 0.9em;
                text-transform: uppercase;
                letter-spacing: 1px;
            }
            
            .card {
                background: rgba(255, 255, 255, 0.95);
                border-radius: 15px;
                padding: 25px;
                box-shadow: 0 8px 32px rgba(0,0,0,0.1);
                backdrop-filter: blur(10px);
                border: 1px solid rgba(255,255,255,0.2);
            }
            
            .card h2 {
                color: #4285F4;
                margin-bottom: 20px;
                font-size: 1.5em;
                display: flex;
                align-items: center;
                gap: 10px;
            }
            
            .vehicle-grid {
                display: grid;
                grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
                gap: 15px;
            }
            
            .vehicle-item {
                background: #f8f9fa;
                border-radius: 10px;
                padding: 15px;
                border-left: 4px solid #4285F4;
            }
            
            .vehicle-status {
                display: inline-block;
                padding: 4px 8px;
                border-radius: 20px;
                font-size: 0.8em;
                font-weight: bold;
                text-transform: uppercase;
            }
            
            .status-active { background: #34A853; color: white; }
            .status-idle { background: #FBBC04; color: #333; }
            .status-offline { background: #EA4335; color: white; }
            .status-speeding { background: #FF6D01; color: white; }
            .status-unknown { background: #9AA0A6; color: white; }
            
            .traffic-grid {
                display: grid;
                gap: 10px;
            }
            
            .traffic-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 12px;
                background: #f8f9fa;
                border-radius: 8px;
                border-left: 4px solid #34A853;
            }
            
            .congestion-free_flow { border-left-color: #34A853; }
            .congestion-moderate { border-left-color: #FBBC04; }
            .congestion-heavy { border-left-color: #FF6D01; }
            .congestion-severe { border-left-color: #EA4335; }
            
            .optimization-item {
                background: #f8f9fa;
                border-radius: 10px;
                padding: 15px;
                margin-bottom: 10px;
                border-left: 4px solid #4285F4;
            }
            
            .system-health {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 15px;
            }
            
            .health-status {
                padding: 8px 16px;
                border-radius: 20px;
                font-weight: bold;
                text-transform: uppercase;
            }
            
            .health-healthy { background: #34A853; color: white; }
            .health-warning { background: #FBBC04; color: #333; }
            .health-error { background: #EA4335; color: white; }
            
            .component-status {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
                gap: 10px;
            }
            
            .component {
                text-align: center;
                padding: 10px;
                border-radius: 8px;
                background: #f8f9fa;
            }
            
            .refresh-info {
                text-align: center;
                margin-top: 20px;
                color: #666;
                font-size: 0.9em;
            }
            
            .alert {
                background: #fff3cd;
                border: 1px solid #ffeaa7;
                color: #856404;
                padding: 10px;
                border-radius: 5px;
                margin: 5px 0;
            }
        </style>
        <script>
            // Auto-refresh dashboard every 30 seconds
            setTimeout(function() {
                window.location.reload();
            }, 30000);
            
            // Add real-time clock
            function updateClock() {
                const now = new Date();
                document.getElementById('current-time').textContent = now.toLocaleString();
            }
            
            setInterval(updateClock, 1000);
            updateClock();
        </script>
    </head>
    <body>
        <div class="header">
            <h1>🚛 Fleet Optimization Dashboard</h1>
            <p class="subtitle">Real-time fleet monitoring with Google Cloud Fleet Routing API and Cloud Bigtable</p>
            <p style="margin-top: 10px; color: #888;">
                Last Updated: {{ dashboard_data.timestamp[:19] }} UTC | 
                Current Time: <span id="current-time"></span>
            </p>
        </div>
        
        <div class="metric-cards">
            <div class="metric-card">
                <div class="metric-value" style="color: #4285F4;">{{ dashboard_data.summary.active_vehicles }}</div>
                <div class="metric-label">Active Vehicles</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #34A853;">{{ dashboard_data.summary.total_vehicles }}</div>
                <div class="metric-label">Total Fleet</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #FBBC04;">{{ "%.1f"|format(dashboard_data.summary.avg_vehicle_speed) }}</div>
                <div class="metric-label">Avg Speed (km/h)</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #EA4335;">{{ dashboard_data.summary.severe_congestion_segments }}</div>
                <div class="metric-label">Severe Congestion</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #9C27B0;">{{ dashboard_data.summary.optimizations_today }}</div>
                <div class="metric-label">Optimizations Today</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #FF6D01;">{{ "%.1f"|format(dashboard_data.summary.avg_cost_savings_percent) }}%</div>
                <div class="metric-label">Avg Cost Savings</div>
            </div>
        </div>
        
        <div class="dashboard-grid">
            <div class="card">
                <h2>🚗 Vehicle Status</h2>
                <div class="vehicle-grid">
                    {% for vehicle in dashboard_data.vehicles[:12] %}
                    <div class="vehicle-item">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                            <strong>{{ vehicle.vehicle_id }}</strong>
                            <span class="vehicle-status status-{{ vehicle.status }}">{{ vehicle.status }}</span>
                        </div>
                        <div style="font-size: 0.9em; color: #666;">
                            {% if vehicle.latitude and vehicle.longitude %}
                            📍 {{ "%.4f"|format(vehicle.latitude) }}, {{ "%.4f"|format(vehicle.longitude) }}<br>
                            {% endif %}
                            {% if vehicle.speed %}
                            🏃 {{ "%.1f"|format(vehicle.speed) }} km/h<br>
                            {% endif %}
                            🕒 {{ vehicle.datetime[:16] if vehicle.datetime else 'N/A' }}
                        </div>
                    </div>
                    {% endfor %}
                </div>
                {% if dashboard_data.vehicles|length > 12 %}
                <p style="text-align: center; margin-top: 15px; color: #666;">
                    Showing 12 of {{ dashboard_data.vehicles|length }} vehicles
                </p>
                {% endif %}
            </div>
            
            <div class="card">
                <h2>🚦 Traffic Conditions</h2>
                <div class="traffic-grid">
                    {% for traffic in dashboard_data.traffic[:15] %}
                    <div class="traffic-item congestion-{{ traffic.congestion_level }}">
                        <div>
                            <strong>{{ traffic.segment_id }}</strong><br>
                            <small>{{ traffic.datetime[:16] if traffic.datetime else 'N/A' }}</small>
                        </div>
                        <div style="text-align: right;">
                            {% if traffic.speed %}
                            <strong>{{ "%.1f"|format(traffic.speed) }} km/h</strong><br>
                            {% endif %}
                            <small style="text-transform: capitalize;">{{ traffic.congestion_level.replace('_', ' ') }}</small>
                        </div>
                    </div>
                    {% endfor %}
                </div>
                {% if dashboard_data.traffic|length > 15 %}
                <p style="text-align: center; margin-top: 15px; color: #666;">
                    Showing 15 of {{ dashboard_data.traffic|length }} traffic segments
                </p>
                {% endif %}
            </div>
            
            <div class="card">
                <h2>🔄 Recent Optimizations</h2>
                {% for opt in dashboard_data.recent_optimizations[:5] %}
                <div class="optimization-item">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                        <strong>{{ opt.optimization_id }}</strong>
                        <span style="color: #4285F4; font-weight: bold;">{{ opt.status }}</span>
                    </div>
                    <div style="font-size: 0.9em; color: #666;">
                        📊 {{ opt.routes_count }} routes generated<br>
                        📏 {{ opt.total_distance_km }} km total distance<br>
                        ⏱️ {{ opt.total_time_minutes }} minutes total time
                        {% if opt.metrics and opt.metrics.cost_savings_percent %}
                        <br>💰 {{ "%.1f"|format(opt.metrics.cost_savings_percent) }}% cost savings
                        {% endif %}
                    </div>
                </div>
                {% endfor %}
                {% if not dashboard_data.recent_optimizations %}
                <p style="text-align: center; color: #666; padding: 20px;">
                    No recent optimizations found
                </p>
                {% endif %}
            </div>
            
            <div class="card">
                <h2>💚 System Health</h2>
                <div class="system-health">
                    <span>Overall Status:</span>
                    <span class="health-status health-{{ dashboard_data.system_health.status }}">
                        {{ dashboard_data.system_health.status }}
                    </span>
                </div>
                
                <div class="component-status">
                    {% for component, status in dashboard_data.system_health.components.items() %}
                    <div class="component">
                        <div style="font-weight: bold; text-transform: capitalize;">{{ component.replace('_', ' ') }}</div>
                        <div class="health-status health-{{ status }}" style="font-size: 0.8em; margin-top: 5px;">
                            {{ status }}
                        </div>
                    </div>
                    {% endfor %}
                </div>
                
                {% if dashboard_data.system_health.alerts %}
                <div style="margin-top: 15px;">
                    <strong>Active Alerts:</strong>
                    {% for alert in dashboard_data.system_health.alerts %}
                    <div class="alert">⚠️ {{ alert }}</div>
                    {% endfor %}
                </div>
                {% endif %}
            </div>
        </div>
        
        <div class="refresh-info">
            <p>Dashboard auto-refreshes every 30 seconds | 
            Powered by Google Cloud Fleet Routing API, Cloud Bigtable, and Cloud Functions</p>
        </div>
    </body>
    </html>
    '''
    
    try:
        from jinja2 import Template
        template = Template(html_template)
        return template.render(dashboard_data=dashboard_data)
    except ImportError:
        # Fallback if Jinja2 not available
        return html_template.replace('{{ dashboard_data.timestamp[:19] }}', 
                                   dashboard_data['timestamp'][:19])

# Health check endpoint
@app.route('/health')
def health_check():
    """Health check endpoint."""
    try:
        initialize_clients()
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "components": {
                "bigtable": "connected",
                "dashboard": "active"
            }
        })
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500