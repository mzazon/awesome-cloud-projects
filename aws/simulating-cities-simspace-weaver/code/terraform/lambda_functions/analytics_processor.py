"""
Lambda function for processing smart city analytics and generating insights.
Analyzes sensor data patterns and generates actionable insights for urban planning.
"""
import json
import boto3
import logging
from datetime import datetime, timedelta
from decimal import Decimal
import os
from boto3.dynamodb.conditions import Key, Attr

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing smart city analytics.
    
    Args:
        event: Analytics request event data
        context: Lambda execution context
        
    Returns:
        dict: Response with analytics results
    """
    try:
        logger.info(f"Processing analytics request: {json.dumps(event, default=str)}")
        
        # Determine analytics type
        analytics_type = event.get('type', 'traffic_summary')
        time_range = event.get('time_range', '24h')
        
        # Route to appropriate analytics function
        if analytics_type == 'traffic_summary':
            result = generate_traffic_summary(time_range)
        elif analytics_type == 'sensor_health':
            result = generate_sensor_health_report()
        elif analytics_type == 'simulation_insights':
            result = generate_simulation_insights()
        elif analytics_type == 'city_performance':
            result = generate_city_performance_report(time_range)
        elif analytics_type == 'predictive_analysis':
            result = generate_predictive_analysis(time_range)
        elif analytics_type == 'custom_query':
            result = process_custom_query(event)
        else:
            raise ValueError(f"Unknown analytics type: {analytics_type}")
        
        logger.info(f"Analytics processing completed for type: {analytics_type}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=decimal_default)
        }
        
    except Exception as e:
        logger.error(f"Error processing analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process analytics request',
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def decimal_default(obj):
    """JSON serializer for Decimal objects."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def generate_traffic_summary(time_range):
    """
    Generate comprehensive traffic analytics summary.
    
    Args:
        time_range: Time range for analysis (e.g., '24h', '7d')
        
    Returns:
        dict: Traffic summary analytics
    """
    try:
        logger.info(f"Generating traffic summary for time range: {time_range}")
        
        # Calculate time bounds
        end_time = datetime.utcnow()
        start_time = calculate_start_time(end_time, time_range)
        
        # Query traffic sensor data
        traffic_data = query_sensor_data_by_type('traffic', start_time, end_time)
        
        if not traffic_data:
            return {
                'time_range': time_range,
                'message': 'No traffic data found for the specified time range',
                'generated_at': datetime.utcnow().isoformat()
            }
        
        # Calculate traffic metrics
        metrics = calculate_traffic_metrics(traffic_data)
        
        # Generate congestion analysis
        congestion_analysis = analyze_traffic_congestion(traffic_data)
        
        # Create peak hours analysis
        peak_hours = analyze_peak_traffic_hours(traffic_data)
        
        # Generate recommendations
        recommendations = generate_traffic_recommendations(metrics, congestion_analysis)
        
        summary = {
            'analytics_type': 'traffic_summary',
            'time_range': time_range,
            'period': {
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            },
            'metrics': metrics,
            'congestion_analysis': congestion_analysis,
            'peak_hours': peak_hours,
            'recommendations': recommendations,
            'data_quality': {
                'total_records': len(traffic_data),
                'unique_sensors': len(set(item['sensor_id'] for item in traffic_data)),
                'data_completeness': calculate_data_completeness(traffic_data, 'traffic')
            },
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return summary
        
    except Exception as e:
        logger.error(f"Error generating traffic summary: {str(e)}")
        raise

def generate_sensor_health_report():
    """
    Generate comprehensive sensor health and connectivity report.
    
    Returns:
        dict: Sensor health report
    """
    try:
        logger.info("Generating sensor health report")
        
        # Query recent sensor data (last hour)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Get all sensor data from the last hour
        response = table.scan(
            FilterExpression=Attr('timestamp').between(
                start_time.isoformat(),
                end_time.isoformat()
            )
        )
        
        sensor_data = response['Items']
        
        # Analyze sensor health by sensor ID
        sensor_health = analyze_sensor_health(sensor_data)
        
        # Calculate overall health metrics
        health_metrics = calculate_health_metrics(sensor_health)
        
        # Identify problematic sensors
        problematic_sensors = identify_problematic_sensors(sensor_health)
        
        # Generate health recommendations
        health_recommendations = generate_health_recommendations(sensor_health, health_metrics)
        
        report = {
            'analytics_type': 'sensor_health',
            'report_period': {
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            },
            'overall_metrics': health_metrics,
            'sensor_details': sensor_health,
            'problematic_sensors': problematic_sensors,
            'recommendations': health_recommendations,
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return report
        
    except Exception as e:
        logger.error(f"Error generating sensor health report: {str(e)}")
        raise

def generate_simulation_insights():
    """
    Generate insights from simulation results and digital twin analysis.
    
    Returns:
        dict: Simulation insights
    """
    try:
        logger.info("Generating simulation insights")
        
        # In a real implementation, this would analyze simulation results
        # For now, generate mock insights based on recent sensor data patterns
        
        # Get recent data for pattern analysis
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=24)
        
        traffic_data = query_sensor_data_by_type('traffic', start_time, end_time)
        weather_data = query_sensor_data_by_type('weather', start_time, end_time)
        
        # Generate insights based on data patterns
        insights = {
            'analytics_type': 'simulation_insights',
            'analysis_period': {
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            },
            'traffic_optimization': generate_traffic_optimization_insights(traffic_data),
            'infrastructure_utilization': generate_infrastructure_insights(traffic_data),
            'weather_impact': generate_weather_impact_insights(traffic_data, weather_data),
            'predictive_scenarios': generate_predictive_scenarios(traffic_data),
            'cost_benefit_analysis': generate_cost_benefit_analysis(),
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return insights
        
    except Exception as e:
        logger.error(f"Error generating simulation insights: {str(e)}")
        raise

def generate_city_performance_report(time_range):
    """
    Generate comprehensive city performance report across all sensors.
    
    Args:
        time_range: Time range for analysis
        
    Returns:
        dict: City performance report
    """
    try:
        logger.info(f"Generating city performance report for: {time_range}")
        
        # Calculate time bounds
        end_time = datetime.utcnow()
        start_time = calculate_start_time(end_time, time_range)
        
        # Get data for all sensor types
        all_sensor_data = query_all_sensor_data(start_time, end_time)
        
        # Group by sensor type
        data_by_type = group_data_by_sensor_type(all_sensor_data)
        
        # Calculate performance metrics for each type
        performance_metrics = {}
        for sensor_type, data in data_by_type.items():
            performance_metrics[sensor_type] = calculate_sensor_type_performance(sensor_type, data)
        
        # Calculate overall city performance score
        city_score = calculate_city_performance_score(performance_metrics)
        
        # Generate performance trends
        trends = analyze_performance_trends(data_by_type, time_range)
        
        # Create improvement recommendations
        improvements = generate_improvement_recommendations(performance_metrics, trends)
        
        report = {
            'analytics_type': 'city_performance',
            'time_range': time_range,
            'period': {
                'start_time': start_time.isoformat(),
                'end_time': end_time.isoformat()
            },
            'overall_score': city_score,
            'performance_by_category': performance_metrics,
            'trends': trends,
            'improvement_recommendations': improvements,
            'data_summary': {
                'total_sensors': len(set(item['sensor_id'] for item in all_sensor_data)),
                'total_records': len(all_sensor_data),
                'sensor_types': list(data_by_type.keys())
            },
            'generated_at': datetime.utcnow().isoformat()
        }
        
        return report
        
    except Exception as e:
        logger.error(f"Error generating city performance report: {str(e)}")
        raise

# Helper functions

def calculate_start_time(end_time, time_range):
    """Calculate start time based on time range."""
    if time_range == '1h':
        return end_time - timedelta(hours=1)
    elif time_range == '24h':
        return end_time - timedelta(hours=24)
    elif time_range == '7d':
        return end_time - timedelta(days=7)
    elif time_range == '30d':
        return end_time - timedelta(days=30)
    else:
        return end_time - timedelta(hours=24)  # Default to 24h

def query_sensor_data_by_type(sensor_type, start_time, end_time, limit=1000):
    """Query sensor data by type and time range."""
    try:
        response = table.query(
            IndexName='SensorTypeIndex',
            KeyConditionExpression=Key('sensor_type').eq(sensor_type) &
                                 Key('timestamp').between(start_time.isoformat(), end_time.isoformat()),
            Limit=limit
        )
        return response['Items']
    except Exception as e:
        logger.error(f"Error querying sensor data: {str(e)}")
        return []

def query_all_sensor_data(start_time, end_time, limit=5000):
    """Query all sensor data within time range."""
    try:
        response = table.scan(
            FilterExpression=Attr('timestamp').between(
                start_time.isoformat(),
                end_time.isoformat()
            ),
            Limit=limit
        )
        return response['Items']
    except Exception as e:
        logger.error(f"Error querying all sensor data: {str(e)}")
        return []

def calculate_traffic_metrics(traffic_data):
    """Calculate comprehensive traffic metrics."""
    if not traffic_data:
        return {}
    
    # Extract numeric values
    vehicle_counts = [float(item.get('data', {}).get('vehicle_count', 0)) for item in traffic_data]
    speeds = [float(item.get('data', {}).get('average_speed', 0)) for item in traffic_data if item.get('data', {}).get('average_speed', 0) > 0]
    
    return {
        'total_vehicle_detections': sum(vehicle_counts),
        'average_vehicles_per_sensor': sum(vehicle_counts) / len(vehicle_counts) if vehicle_counts else 0,
        'average_speed_kmh': sum(speeds) / len(speeds) if speeds else 0,
        'peak_vehicle_count': max(vehicle_counts) if vehicle_counts else 0,
        'minimum_speed_recorded': min(speeds) if speeds else 0,
        'maximum_speed_recorded': max(speeds) if speeds else 0,
        'unique_sensors': len(set(item['sensor_id'] for item in traffic_data)),
        'data_points': len(traffic_data)
    }

def analyze_traffic_congestion(traffic_data):
    """Analyze traffic congestion patterns."""
    if not traffic_data:
        return {}
    
    congestion_scores = []
    for item in traffic_data:
        speed = float(item.get('data', {}).get('average_speed', 50))
        volume = float(item.get('data', {}).get('vehicle_count', 0))
        
        # Calculate congestion score (higher volume + lower speed = higher congestion)
        if speed > 0:
            congestion_score = min(100, (volume / 10) * (60 - speed) / 60 * 100)
            congestion_scores.append(max(0, congestion_score))
    
    if not congestion_scores:
        return {'overall_congestion': 0}
    
    avg_congestion = sum(congestion_scores) / len(congestion_scores)
    
    return {
        'overall_congestion_score': round(avg_congestion, 2),
        'peak_congestion': round(max(congestion_scores), 2),
        'minimum_congestion': round(min(congestion_scores), 2),
        'congestion_level': get_congestion_level(avg_congestion)
    }

def get_congestion_level(score):
    """Convert congestion score to level."""
    if score < 20:
        return 'Low'
    elif score < 50:
        return 'Moderate'
    elif score < 80:
        return 'High'
    else:
        return 'Severe'

# Additional helper functions would continue here...

def generate_predictive_analysis(time_range):
    """Generate predictive analysis based on historical patterns."""
    # This would implement predictive analytics
    # For now, return a placeholder structure
    return {
        'analytics_type': 'predictive_analysis',
        'predictions': {
            'traffic_forecast': 'Traffic is expected to increase by 15% during peak hours',
            'infrastructure_needs': 'Additional sensors recommended for Highway 101 corridor',
            'maintenance_schedule': 'Sensor maintenance due in 30 days for downtown area'
        },
        'confidence_level': 0.85,
        'generated_at': datetime.utcnow().isoformat()
    }

def process_custom_query(event):
    """Process custom analytics query."""
    query_params = event.get('query_params', {})
    
    # This would implement custom query processing
    # For now, return a placeholder
    return {
        'analytics_type': 'custom_query',
        'query_params': query_params,
        'results': 'Custom query processing would be implemented here',
        'generated_at': datetime.utcnow().isoformat()
    }

# Additional helper functions for comprehensive analytics...
def analyze_sensor_health(sensor_data):
    """Analyze health status of individual sensors."""
    sensor_health = {}
    
    for item in sensor_data:
        sensor_id = item['sensor_id']
        if sensor_id not in sensor_health:
            sensor_health[sensor_id] = {
                'sensor_id': sensor_id,
                'sensor_type': item.get('sensor_type', 'unknown'),
                'message_count': 0,
                'last_seen': item['timestamp'],
                'battery_level': None,
                'status': 'active'
            }
        
        sensor_health[sensor_id]['message_count'] += 1
        
        # Update last seen if this message is newer
        if item['timestamp'] > sensor_health[sensor_id]['last_seen']:
            sensor_health[sensor_id]['last_seen'] = item['timestamp']
        
        # Update battery level if available
        if 'battery_level' in item:
            sensor_health[sensor_id]['battery_level'] = float(item['battery_level'])
    
    # Determine health status for each sensor
    for sensor in sensor_health.values():
        if sensor['message_count'] < 5:  # Less than 5 messages per hour
            sensor['status'] = 'warning'
        if sensor['message_count'] == 0:
            sensor['status'] = 'offline'
        if sensor['battery_level'] and sensor['battery_level'] < 20:
            sensor['status'] = 'low_battery'
    
    return list(sensor_health.values())

def calculate_data_completeness(data, sensor_type):
    """Calculate data completeness percentage."""
    if not data:
        return 0
    
    complete_records = 0
    for item in data:
        sensor_data = item.get('data', {})
        if sensor_type == 'traffic':
            if 'vehicle_count' in sensor_data and 'average_speed' in sensor_data:
                complete_records += 1
        elif sensor_type == 'weather':
            if 'temperature' in sensor_data and 'humidity' in sensor_data:
                complete_records += 1
        else:
            complete_records += 1  # Assume complete for unknown types
    
    return round((complete_records / len(data)) * 100, 2)