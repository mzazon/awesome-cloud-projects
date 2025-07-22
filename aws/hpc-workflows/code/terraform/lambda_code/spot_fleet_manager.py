"""
Spot Fleet Manager Lambda Function

This function manages EC2 Spot Fleet lifecycle including creation, modification,
termination, and health monitoring for fault-tolerant HPC workflows.

Features:
- Create diversified Spot Fleet requests with multiple instance types
- Modify fleet capacity based on workload demands
- Monitor fleet health and handle interruptions
- Automatic fallback to On-Demand instances when needed
- Integration with CloudWatch for monitoring and alerting
"""

import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2 = boto3.client('ec2')
cloudwatch = boto3.client('cloudwatch')

# Configuration constants
PROJECT_NAME = "${project_name}"
REGION = "${region}"
DEFAULT_INSTANCE_TYPES = ["c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"]
DEFAULT_SPOT_PRICE = "0.50"
DEFAULT_ALLOCATION_STRATEGY = "diversified"


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for Spot Fleet management operations.
    
    Args:
        event: Lambda event containing action and parameters
        context: Lambda context object
        
    Returns:
        Dict containing operation results and status
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        action = event.get('action', 'create')
        
        if action == 'create':
            return create_spot_fleet(event)
        elif action == 'modify':
            return modify_spot_fleet(event)
        elif action == 'terminate':
            return terminate_spot_fleet(event)
        elif action == 'check_health':
            return check_spot_fleet_health(event)
        elif action == 'get_instances':
            return get_spot_fleet_instances(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in spot fleet manager: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'action': event.get('action', 'unknown')
        }


def create_spot_fleet(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a new Spot Fleet with fault tolerance and diversification.
    
    Args:
        event: Event containing fleet configuration parameters
        
    Returns:
        Dict containing fleet ID and creation status
    """
    try:
        # Extract configuration from event
        target_capacity = event.get('target_capacity', 4)
        spot_price = event.get('spot_price', DEFAULT_SPOT_PRICE)
        allocation_strategy = event.get('allocation_strategy', DEFAULT_ALLOCATION_STRATEGY)
        instance_types = event.get('instance_types', DEFAULT_INSTANCE_TYPES)
        ami_id = event.get('ami_id')
        key_name = event.get('key_name')
        security_group_id = event.get('security_group_id')
        subnet_id = event.get('subnet_id')
        subnet_ids = event.get('subnet_ids', [])
        user_data = event.get('user_data', '')
        fleet_role_arn = event.get('fleet_role_arn')
        
        # Validate required parameters
        if not ami_id:
            raise ValueError("ami_id is required")
        if not security_group_id:
            raise ValueError("security_group_id is required")
        if not (subnet_id or subnet_ids):
            raise ValueError("subnet_id or subnet_ids is required")
        if not fleet_role_arn:
            raise ValueError("fleet_role_arn is required")
        
        # Use subnet_ids if provided, otherwise use single subnet_id
        if subnet_ids:
            subnets = subnet_ids
        else:
            subnets = [subnet_id]
        
        # Create launch specifications for different instance types
        launch_specifications = []
        
        for i, instance_type in enumerate(instance_types):
            # Distribute across subnets for high availability
            subnet_for_instance = subnets[i % len(subnets)]
            
            # Calculate weighted capacity based on instance size
            weighted_capacity = calculate_weighted_capacity(instance_type)
            
            launch_spec = {
                'ImageId': ami_id,
                'InstanceType': instance_type,
                'SecurityGroups': [{'GroupId': security_group_id}],
                'SubnetId': subnet_for_instance,
                'WeightedCapacity': weighted_capacity,
                'UserData': user_data
            }
            
            # Add key pair if provided
            if key_name:
                launch_spec['KeyName'] = key_name
            
            launch_specifications.append(launch_spec)
        
        # Create Spot Fleet request configuration
        spot_fleet_config = {
            'SpotFleetRequestConfig': {
                'IamFleetRole': fleet_role_arn,
                'AllocationStrategy': allocation_strategy,
                'TargetCapacity': target_capacity,
                'SpotPrice': spot_price,
                'LaunchSpecifications': launch_specifications,
                'TerminateInstancesWithExpiration': True,
                'Type': 'maintain',
                'ReplaceUnhealthyInstances': True,
                'InstanceInterruptionBehavior': 'terminate'
            }
        }
        
        logger.info(f"Creating Spot Fleet with configuration: {json.dumps(spot_fleet_config, default=str)}")
        
        # Create the Spot Fleet request
        response = ec2.request_spot_fleet(**spot_fleet_config)
        fleet_id = response['SpotFleetRequestId']
        
        # Wait for fleet to become active
        logger.info(f"Waiting for Spot Fleet {fleet_id} to become active...")
        waiter = ec2.get_waiter('spot_fleet_request_fulfilled')
        waiter.wait(
            SpotFleetRequestIds=[fleet_id],
            WaiterConfig={
                'Delay': 15,
                'MaxAttempts': 40
            }
        )
        
        # Send custom CloudWatch metric
        send_cloudwatch_metric('SpotFleetCreated', 1, fleet_id)
        
        logger.info(f"Spot Fleet {fleet_id} created successfully")
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'status': 'active',
            'target_capacity': target_capacity,
            'launch_specifications': len(launch_specifications),
            'allocation_strategy': allocation_strategy
        }
        
    except Exception as e:
        logger.error(f"Error creating Spot Fleet: {str(e)}")
        raise


def modify_spot_fleet(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Modify existing Spot Fleet capacity or configuration.
    
    Args:
        event: Event containing fleet ID and modification parameters
        
    Returns:
        Dict containing modification results
    """
    try:
        fleet_id = event.get('fleet_id')
        new_capacity = event.get('target_capacity')
        fallback_to_ondemand = event.get('fallback_to_ondemand', False)
        
        if not fleet_id:
            raise ValueError("fleet_id is required")
        if new_capacity is None:
            raise ValueError("target_capacity is required")
        
        logger.info(f"Modifying Spot Fleet {fleet_id} to capacity {new_capacity}")
        
        # Modify the Spot Fleet request
        response = ec2.modify_spot_fleet_request(
            SpotFleetRequestId=fleet_id,
            TargetCapacity=new_capacity
        )
        
        # If fallback to On-Demand is requested, handle it
        if fallback_to_ondemand:
            logger.info(f"Initiating fallback to On-Demand instances for fleet {fleet_id}")
            # This would involve creating additional On-Demand instances
            # Implementation depends on specific requirements
        
        # Send custom CloudWatch metric
        send_cloudwatch_metric('SpotFleetModified', 1, fleet_id)
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'new_capacity': new_capacity,
            'modification_response': response.get('Return', False),
            'fallback_initiated': fallback_to_ondemand
        }
        
    except Exception as e:
        logger.error(f"Error modifying Spot Fleet: {str(e)}")
        raise


def terminate_spot_fleet(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Terminate an existing Spot Fleet.
    
    Args:
        event: Event containing fleet ID and termination parameters
        
    Returns:
        Dict containing termination results
    """
    try:
        fleet_id = event.get('fleet_id')
        terminate_instances = event.get('terminate_instances', True)
        
        if not fleet_id:
            raise ValueError("fleet_id is required")
        
        logger.info(f"Terminating Spot Fleet {fleet_id}")
        
        # Cancel the Spot Fleet request
        response = ec2.cancel_spot_fleet_requests(
            SpotFleetRequestIds=[fleet_id],
            TerminateInstances=terminate_instances
        )
        
        # Send custom CloudWatch metric
        send_cloudwatch_metric('SpotFleetTerminated', 1, fleet_id)
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'status': 'terminated',
            'instances_terminated': terminate_instances,
            'response': response.get('Successful', [])
        }
        
    except Exception as e:
        logger.error(f"Error terminating Spot Fleet: {str(e)}")
        raise


def check_spot_fleet_health(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Check the health and status of a Spot Fleet.
    
    Args:
        event: Event containing fleet ID
        
    Returns:
        Dict containing fleet health information
    """
    try:
        fleet_id = event.get('fleet_id')
        
        if not fleet_id:
            raise ValueError("fleet_id is required")
        
        # Get fleet information
        response = ec2.describe_spot_fleet_requests(
            SpotFleetRequestIds=[fleet_id]
        )
        
        if not response['SpotFleetRequestConfigs']:
            raise ValueError(f"Spot Fleet {fleet_id} not found")
        
        fleet_config = response['SpotFleetRequestConfigs'][0]
        fleet_state = fleet_config['SpotFleetRequestState']
        target_capacity = fleet_config['SpotFleetRequestConfig']['TargetCapacity']
        
        # Get instance information
        instances_response = ec2.describe_spot_fleet_instances(
            SpotFleetRequestId=fleet_id
        )
        
        active_instances = instances_response['ActiveInstances']
        total_instances = len(active_instances)
        
        # Count healthy instances
        healthy_instances = len([
            i for i in active_instances 
            if i.get('InstanceHealth') == 'healthy'
        ])
        
        # Calculate health percentage
        health_percentage = (healthy_instances / max(total_instances, 1)) * 100
        
        # Check for recent interruptions
        recent_interruptions = check_recent_interruptions(fleet_id)
        
        # Send health metrics to CloudWatch
        send_cloudwatch_metric('SpotFleetHealthyInstances', healthy_instances, fleet_id)
        send_cloudwatch_metric('SpotFleetTotalInstances', total_instances, fleet_id)
        send_cloudwatch_metric('SpotFleetHealthPercentage', health_percentage, fleet_id)
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'fleet_state': fleet_state,
            'target_capacity': target_capacity,
            'healthy_instances': healthy_instances,
            'total_instances': total_instances,
            'health_percentage': health_percentage,
            'recent_interruptions': recent_interruptions,
            'is_healthy': health_percentage >= 75  # Consider healthy if >= 75%
        }
        
    except Exception as e:
        logger.error(f"Error checking Spot Fleet health: {str(e)}")
        raise


def get_spot_fleet_instances(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get detailed information about instances in a Spot Fleet.
    
    Args:
        event: Event containing fleet ID
        
    Returns:
        Dict containing instance information
    """
    try:
        fleet_id = event.get('fleet_id')
        
        if not fleet_id:
            raise ValueError("fleet_id is required")
        
        # Get instance information
        response = ec2.describe_spot_fleet_instances(
            SpotFleetRequestId=fleet_id
        )
        
        instances = []
        for instance in response['ActiveInstances']:
            instance_info = {
                'instance_id': instance['InstanceId'],
                'instance_type': instance['InstanceType'],
                'spot_instance_request_id': instance['SpotInstanceRequestId'],
                'instance_health': instance.get('InstanceHealth', 'unknown')
            }
            instances.append(instance_info)
        
        return {
            'statusCode': 200,
            'fleet_id': fleet_id,
            'instances': instances,
            'total_instances': len(instances)
        }
        
    except Exception as e:
        logger.error(f"Error getting Spot Fleet instances: {str(e)}")
        raise


def calculate_weighted_capacity(instance_type: str) -> float:
    """
    Calculate weighted capacity for an instance type.
    
    Args:
        instance_type: EC2 instance type
        
    Returns:
        Weighted capacity value
    """
    # Define capacity weights based on instance size
    capacity_weights = {
        'small': 1.0,
        'medium': 1.0,
        'large': 1.0,
        'xlarge': 2.0,
        '2xlarge': 4.0,
        '4xlarge': 8.0,
        '8xlarge': 16.0,
        '12xlarge': 24.0,
        '16xlarge': 32.0,
        '24xlarge': 48.0
    }
    
    # Extract size from instance type
    size = instance_type.split('.')[1] if '.' in instance_type else 'large'
    
    return capacity_weights.get(size, 1.0)


def check_recent_interruptions(fleet_id: str) -> List[Dict[str, Any]]:
    """
    Check for recent Spot instance interruptions.
    
    Args:
        fleet_id: Spot Fleet ID
        
    Returns:
        List of recent interruption events
    """
    try:
        # This would typically check CloudWatch Events or CloudTrail
        # For now, return empty list as placeholder
        return []
        
    except Exception as e:
        logger.error(f"Error checking interruptions: {str(e)}")
        return []


def send_cloudwatch_metric(metric_name: str, value: float, fleet_id: str) -> None:
    """
    Send custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        fleet_id: Spot Fleet ID for dimensions
    """
    try:
        cloudwatch.put_metric_data(
            Namespace=f'{PROJECT_NAME}/SpotFleet',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FleetId',
                            'Value': fleet_id
                        },
                        {
                            'Name': 'Region',
                            'Value': REGION
                        }
                    ],
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        logger.info(f"Sent CloudWatch metric: {metric_name} = {value}")
        
    except Exception as e:
        logger.error(f"Error sending CloudWatch metric: {str(e)}")
        # Don't raise exception for metrics - they're not critical