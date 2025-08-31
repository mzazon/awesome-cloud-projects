# Digital Twin Simulation Engine for Manufacturing Resilience
# Cloud Function implementation for simulating equipment failure scenarios

import functions_framework
import json
import random
import os
from datetime import datetime, timedelta
from google.cloud import pubsub_v1, bigquery
from typing import Dict, Any, Optional


@functions_framework.http
def simulate_failure_scenario(request):
    """
    HTTP Cloud Function for simulating equipment failure scenarios for resilience testing.
    
    This function serves as the core digital twin simulation engine, modeling various
    equipment failure scenarios and calculating their business impact. It integrates
    with Pub/Sub for event publishing and BigQuery for storing simulation results.
    
    Args:
        request: HTTP request object containing simulation parameters
        
    Returns:
        JSON response with simulation ID, status, and scenario details
    """
    
    # Initialize Google Cloud clients
    publisher = pubsub_v1.PublisherClient()
    bigquery_client = bigquery.Client()
    
    # Get configuration from environment variables
    project_id = os.environ.get('PROJECT_ID', '${project_id}')
    dataset_name = os.environ.get('DATASET_NAME', 'manufacturing_data')
    
    # Configure Pub/Sub topic paths
    simulation_topic_path = publisher.topic_path(project_id, 'failure-simulation-events')
    
    try:
        # Parse and validate simulation request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {
                'error': 'Invalid JSON request body',
                'status': 'failed'
            }, 400
        
        # Extract simulation parameters with defaults
        equipment_id = request_json.get('equipment_id', 'pump_001')
        failure_type = request_json.get('failure_type', 'temperature_spike')
        duration_hours = request_json.get('duration_hours', 2)
        severity = request_json.get('severity', None)
        
        # Validate input parameters
        if not equipment_id or not isinstance(equipment_id, str):
            return {
                'error': 'Invalid equipment_id parameter',
                'status': 'failed'
            }, 400
        
        if duration_hours <= 0 or duration_hours > 168:  # Max 1 week
            return {
                'error': 'Duration must be between 1 and 168 hours',
                'status': 'failed'
            }, 400
        
        # Generate unique simulation identifier
        simulation_id = f"sim_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{random.randint(1000, 9999)}"
        
        # Calculate business impact based on failure scenario
        business_impact = calculate_business_impact(failure_type, duration_hours)
        
        # Generate realistic failure progression data
        failure_progression = generate_failure_progression(failure_type, duration_hours)
        
        # Create comprehensive simulation event data
        simulation_event = {
            'simulation_id': simulation_id,
            'equipment_id': equipment_id,
            'failure_type': failure_type,
            'start_time': datetime.utcnow().isoformat(),
            'duration_hours': duration_hours,
            'severity': severity or determine_severity(failure_type, duration_hours),
            'predicted_recovery_time': calculate_recovery_time(failure_type, duration_hours),
            'business_impact': business_impact,
            'failure_progression': failure_progression,
            'environmental_factors': generate_environmental_factors(),
            'recommended_actions': generate_recovery_recommendations(failure_type, duration_hours)
        }
        
        # Publish simulation event to Pub/Sub
        future = publisher.publish(
            simulation_topic_path, 
            json.dumps(simulation_event).encode('utf-8'),
            simulation_id=simulation_id,
            equipment_id=equipment_id,
            failure_type=failure_type
        )
        
        # Wait for publish confirmation
        message_id = future.result(timeout=30)
        
        # Store simulation results in BigQuery
        store_simulation_results(bigquery_client, project_id, dataset_name, simulation_event)
        
        # Return success response
        return {
            'simulation_id': simulation_id,
            'status': 'simulation_started',
            'message_id': message_id,
            'details': simulation_event,
            'metadata': {
                'timestamp': datetime.utcnow().isoformat(),
                'function_version': '1.0.0',
                'estimated_completion': (datetime.utcnow() + timedelta(hours=duration_hours)).isoformat()
            }
        }
        
    except Exception as e:
        # Log error and return failure response
        print(f"Error in simulation function: {str(e)}")
        return {
            'error': f'Simulation failed: {str(e)}',
            'status': 'failed',
            'simulation_id': simulation_id if 'simulation_id' in locals() else None
        }, 500


def calculate_business_impact(failure_type: str, duration_hours: int) -> Dict[str, Any]:
    """
    Calculate estimated business impact of failure scenario based on type and duration.
    
    This function models the financial and operational impact of equipment failures,
    considering factors like downtime costs, affected production lines, and recovery complexity.
    
    Args:
        failure_type: Type of equipment failure
        duration_hours: Expected duration of the failure
        
    Returns:
        Dictionary containing business impact metrics
    """
    
    # Base downtime cost per hour (configurable based on industry)
    base_cost_per_hour = 50000  # $50k per hour as specified in recipe
    
    # Failure type multipliers based on severity and complexity
    failure_multipliers = {
        'temperature_spike': 1.2,
        'vibration_anomaly': 1.5,
        'pressure_drop': 2.0,
        'complete_failure': 3.0,
        'electrical_fault': 2.5,
        'mechanical_wear': 1.8,
        'sensor_malfunction': 1.1,
        'cooling_system_failure': 2.2,
        'hydraulic_failure': 2.4,
        'software_error': 1.3
    }
    
    # Calculate impact multiplier
    multiplier = failure_multipliers.get(failure_type, 1.5)  # Default multiplier
    
    # Calculate total financial impact
    total_impact = base_cost_per_hour * duration_hours * multiplier
    
    # Determine number of affected production lines (based on equipment criticality)
    affected_lines = min(random.randint(1, 5), max(1, int(total_impact / 100000)))
    
    # Calculate recovery complexity
    recovery_complexity = 'high' if total_impact > 200000 else 'medium' if total_impact > 50000 else 'low'
    
    # Calculate additional impact factors
    supply_chain_delay = calculate_supply_chain_impact(failure_type, duration_hours)
    quality_impact = calculate_quality_impact(failure_type, duration_hours)
    
    return {
        'estimated_cost': total_impact,
        'affected_production_lines': affected_lines,
        'recovery_complexity': recovery_complexity,
        'downtime_hours': duration_hours,
        'cost_per_hour': base_cost_per_hour * multiplier,
        'supply_chain_delay_hours': supply_chain_delay,
        'quality_impact_score': quality_impact,
        'regulatory_reporting_required': total_impact > 500000,
        'insurance_claim_eligible': total_impact > 100000
    }


def calculate_supply_chain_impact(failure_type: str, duration_hours: int) -> int:
    """Calculate supply chain delay impact in hours."""
    base_delay = duration_hours * 0.3  # 30% of failure duration as base delay
    
    if failure_type in ['complete_failure', 'mechanical_wear']:
        return int(base_delay * 1.5)  # Higher supply chain impact
    elif failure_type in ['sensor_malfunction', 'software_error']:
        return int(base_delay * 0.5)  # Lower supply chain impact
    
    return int(base_delay)


def calculate_quality_impact(failure_type: str, duration_hours: int) -> float:
    """Calculate quality impact score (0-10 scale)."""
    base_score = min(duration_hours * 0.1, 10.0)  # Base score from duration
    
    quality_multipliers = {
        'temperature_spike': 1.5,
        'pressure_drop': 1.8,
        'complete_failure': 2.0,
        'cooling_system_failure': 1.7,
        'sensor_malfunction': 0.5,
        'software_error': 0.3
    }
    
    multiplier = quality_multipliers.get(failure_type, 1.0)
    return min(base_score * multiplier, 10.0)


def generate_failure_progression(failure_type: str, duration_hours: int) -> Dict[str, Any]:
    """
    Generate realistic failure progression timeline with multiple phases.
    
    Args:
        failure_type: Type of equipment failure
        duration_hours: Total duration of the failure
        
    Returns:
        Dictionary describing failure progression phases
    """
    
    phases = []
    
    # Phase 1: Initial detection (first 5-15% of duration)
    detection_phase_duration = max(0.1, duration_hours * random.uniform(0.05, 0.15))
    phases.append({
        'phase': 'detection',
        'duration_hours': detection_phase_duration,
        'description': 'Initial anomaly detection and alert generation',
        'automated_actions': ['alert_generation', 'data_collection', 'initial_diagnostics'],
        'severity_level': 'low'
    })
    
    # Phase 2: Investigation and analysis (next 20-30% of duration)
    investigation_duration = duration_hours * random.uniform(0.20, 0.30)
    phases.append({
        'phase': 'investigation',
        'duration_hours': investigation_duration,
        'description': 'Root cause analysis and impact assessment',
        'automated_actions': ['diagnostic_tests', 'historical_analysis', 'expert_notification'],
        'severity_level': 'medium'
    })
    
    # Phase 3: Active failure (remaining duration)
    active_failure_duration = duration_hours - detection_phase_duration - investigation_duration
    phases.append({
        'phase': 'active_failure',
        'duration_hours': active_failure_duration,
        'description': 'Equipment failure requiring intervention',
        'automated_actions': ['production_halt', 'safety_protocols', 'recovery_initiation'],
        'severity_level': 'high'
    })
    
    return {
        'total_phases': len(phases),
        'phases': phases,
        'critical_decision_points': generate_decision_points(failure_type),
        'escalation_triggers': generate_escalation_triggers(failure_type)
    }


def generate_decision_points(failure_type: str) -> list:
    """Generate critical decision points during failure progression."""
    base_decisions = [
        'Continue production with reduced capacity',
        'Halt production immediately',
        'Switch to backup equipment',
        'Initiate emergency maintenance'
    ]
    
    failure_specific_decisions = {
        'temperature_spike': ['Increase cooling capacity', 'Reduce operating speed'],
        'pressure_drop': ['Check seal integrity', 'Adjust pressure settings'],
        'complete_failure': ['Activate backup systems', 'Implement manual override'],
        'vibration_anomaly': ['Reduce equipment speed', 'Check mounting systems']
    }
    
    return base_decisions + failure_specific_decisions.get(failure_type, [])


def generate_escalation_triggers(failure_type: str) -> list:
    """Generate escalation triggers for different failure types."""
    return [
        'Temperature exceeds critical threshold',
        'Vibration levels exceed safety limits',
        'Production output drops below 50%',
        'Safety system activation',
        'Multiple equipment alerts',
        'Quality metrics degradation'
    ]


def determine_severity(failure_type: str, duration_hours: int) -> str:
    """Determine failure severity based on type and duration."""
    severity_matrix = {
        'complete_failure': 'high',
        'pressure_drop': 'high' if duration_hours > 4 else 'medium',
        'temperature_spike': 'medium' if duration_hours > 2 else 'low',
        'vibration_anomaly': 'medium',
        'sensor_malfunction': 'low',
        'software_error': 'low' if duration_hours < 1 else 'medium'
    }
    
    return severity_matrix.get(failure_type, 'medium')


def calculate_recovery_time(failure_type: str, duration_hours: int) -> int:
    """Calculate predicted recovery time in minutes."""
    base_recovery_minutes = {
        'temperature_spike': 30,
        'vibration_anomaly': 45,
        'pressure_drop': 60,
        'complete_failure': 180,
        'electrical_fault': 120,
        'mechanical_wear': 240,
        'sensor_malfunction': 15,
        'software_error': 20
    }
    
    base_time = base_recovery_minutes.get(failure_type, 90)
    
    # Adjust based on duration (longer failures may indicate more complex issues)
    duration_multiplier = 1 + (duration_hours / 24)  # Increase by failure duration
    
    return int(base_time * duration_multiplier * random.uniform(0.8, 1.2))


def generate_environmental_factors() -> Dict[str, Any]:
    """Generate environmental factors that may influence failure scenarios."""
    return {
        'ambient_temperature': round(random.uniform(15, 35), 1),  # Celsius
        'humidity_percent': round(random.uniform(30, 80), 1),
        'vibration_level': round(random.uniform(0.1, 2.0), 2),
        'electrical_stability': random.choice(['stable', 'minor_fluctuations', 'unstable']),
        'dust_level': random.choice(['low', 'medium', 'high']),
        'maintenance_schedule': random.choice(['current', 'overdue', 'recent'])
    }


def generate_recovery_recommendations(failure_type: str, duration_hours: int) -> list:
    """Generate specific recovery recommendations based on failure type."""
    base_recommendations = [
        'Implement immediate safety protocols',
        'Document all observations and actions',
        'Coordinate with maintenance team',
        'Prepare backup equipment if available'
    ]
    
    failure_specific_recommendations = {
        'temperature_spike': [
            'Check cooling system operation',
            'Verify thermal sensors accuracy',
            'Inspect heat exchangers for blockage',
            'Monitor coolant levels and flow rates'
        ],
        'vibration_anomaly': [
            'Inspect mounting bolts and foundations',
            'Check belt tension and alignment',
            'Verify bearing condition',
            'Analyze vibration frequency patterns'
        ],
        'pressure_drop': [
            'Inspect seals and gaskets',
            'Check for system leaks',
            'Verify pump operation',
            'Test pressure relief valves'
        ],
        'complete_failure': [
            'Activate emergency shutdown procedures',
            'Isolate affected equipment',
            'Implement backup systems',
            'Coordinate with emergency response team'
        ]
    }
    
    specific_recs = failure_specific_recommendations.get(failure_type, [])
    return base_recommendations + specific_recs


def store_simulation_results(client: bigquery.Client, project_id: str, dataset_name: str, simulation_event: Dict[str, Any]) -> None:
    """
    Store simulation results in BigQuery for analysis and reporting.
    
    Args:
        client: BigQuery client instance
        project_id: GCP project ID
        dataset_name: BigQuery dataset name
        simulation_event: Simulation event data to store
    """
    
    try:
        table_id = f"{project_id}.{dataset_name}.simulation_results"
        
        # Prepare row data for BigQuery insertion
        row_data = {
            'simulation_id': simulation_event['simulation_id'],
            'timestamp': datetime.utcnow(),
            'scenario': simulation_event['failure_type'],
            'equipment_id': simulation_event['equipment_id'],
            'predicted_outcome': simulation_event['business_impact']['recovery_complexity'],
            'confidence': round(random.uniform(0.7, 0.95), 2),  # Simulated confidence score
            'recovery_time': simulation_event['predicted_recovery_time']
        }
        
        # Insert row into BigQuery table
        errors = client.insert_rows_json(table_id, [row_data])
        
        if errors:
            print(f"Failed to insert simulation results into BigQuery: {errors}")
        else:
            print(f"Successfully stored simulation results for {simulation_event['simulation_id']}")
            
    except Exception as e:
        print(f"Error storing simulation results in BigQuery: {str(e)}")
        # Don't raise exception as this is not critical for simulation execution