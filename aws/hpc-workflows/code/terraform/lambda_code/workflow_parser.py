"""
Workflow Parser Lambda Function

This function parses HPC workflow definitions and transforms them into
executable plans for Step Functions orchestration.

Features:
- Parse workflow definitions with task dependencies
- Perform topological sorting for dependency resolution
- Calculate resource requirements and cost estimates
- Generate execution plans with parallelization strategies
- Validate workflow syntax and constraints
- Support for different workflow formats and patterns
"""

import json
import boto3
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional, Set, Tuple
from collections import defaultdict, deque

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
pricing = boto3.client('pricing', region_name='us-east-1')  # Pricing API is only available in us-east-1

# Configuration constants
PROJECT_NAME = "${project_name}"
REGION = "${region}"

# Instance type pricing estimates (per hour)
INSTANCE_PRICING = {
    'c5.large': 0.085,
    'c5.xlarge': 0.17,
    'c5.2xlarge': 0.34,
    'c5.4xlarge': 0.68,
    'c5.9xlarge': 1.53,
    'c5.18xlarge': 3.06,
    'm5.large': 0.096,
    'm5.xlarge': 0.192,
    'm5.2xlarge': 0.384,
    'm5.4xlarge': 0.768,
    'r5.large': 0.126,
    'r5.xlarge': 0.252,
    'r5.2xlarge': 0.504,
    'r5.4xlarge': 1.008
}

# Spot instance discount (typically 60-90% off On-Demand)
SPOT_DISCOUNT = 0.70


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for workflow parsing operations.
    
    Args:
        event: Lambda event containing workflow definition
        context: Lambda context object
        
    Returns:
        Dict containing parsed workflow and execution plan
    """
    try:
        logger.info(f"Received workflow parsing request: {json.dumps(event, default=str)}")
        
        workflow_definition = event.get('workflow_definition')
        workflow_id = event.get('workflow_id', f"workflow-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}")
        dry_run = event.get('dry_run', False)
        
        if not workflow_definition:
            raise ValueError("workflow_definition is required")
        
        # Parse workflow definition
        parsed_workflow = parse_workflow(workflow_definition)
        
        # Validate workflow
        validation_result = validate_workflow(parsed_workflow)
        if not validation_result['valid']:
            raise ValueError(f"Invalid workflow: {validation_result['errors']}")
        
        # Generate execution plan
        execution_plan = generate_execution_plan(parsed_workflow, workflow_id)
        
        # Calculate cost and duration estimates
        cost_estimate = calculate_estimated_cost(execution_plan, parsed_workflow)
        duration_estimate = calculate_estimated_duration(execution_plan, parsed_workflow)
        
        # Send metrics
        send_cloudwatch_metric('WorkflowParsed', 1, workflow_id)
        send_cloudwatch_metric('WorkflowTasks', len(parsed_workflow['tasks']), workflow_id)
        
        result = {
            'statusCode': 200,
            'workflow_id': workflow_id,
            'parsed_workflow': parsed_workflow,
            'execution_plan': execution_plan,
            'cost_estimate': cost_estimate,
            'duration_estimate': duration_estimate,
            'validation': validation_result,
            'dry_run': dry_run
        }
        
        logger.info(f"Workflow parsing completed for {workflow_id}")
        
        return result
        
    except Exception as e:
        logger.error(f"Error parsing workflow: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'workflow_id': event.get('workflow_id', 'unknown')
        }


def parse_workflow(workflow_def: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse workflow definition into structured format.
    
    Args:
        workflow_def: Raw workflow definition
        
    Returns:
        Dict containing parsed workflow structure
    """
    try:
        parsed = {
            'name': workflow_def.get('name', 'Unnamed Workflow'),
            'description': workflow_def.get('description', ''),
            'version': workflow_def.get('version', '1.0'),
            'tasks': [],
            'dependencies': {},
            'global_config': workflow_def.get('global_config', {}),
            'metadata': workflow_def.get('metadata', {})
        }
        
        # Parse tasks
        for task in workflow_def.get('tasks', []):
            parsed_task = parse_task(task)
            parsed['tasks'].append(parsed_task)
            
            # Parse dependencies
            if 'depends_on' in task:
                dependencies = task['depends_on']
                if isinstance(dependencies, str):
                    dependencies = [dependencies]
                parsed['dependencies'][task['id']] = dependencies
        
        # Validate task IDs are unique
        task_ids = [task['id'] for task in parsed['tasks']]
        if len(task_ids) != len(set(task_ids)):
            raise ValueError("Task IDs must be unique")
        
        # Validate dependencies reference existing tasks
        all_task_ids = set(task_ids)
        for task_id, deps in parsed['dependencies'].items():
            for dep in deps:
                if dep not in all_task_ids:
                    raise ValueError(f"Task {task_id} depends on non-existent task {dep}")
        
        return parsed
        
    except Exception as e:
        logger.error(f"Error parsing workflow: {str(e)}")
        raise


def parse_task(task: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse individual task definition.
    
    Args:
        task: Raw task definition
        
    Returns:
        Dict containing parsed task structure
    """
    # Required fields
    if 'id' not in task:
        raise ValueError("Task must have an 'id' field")
    
    parsed_task = {
        'id': task['id'],
        'name': task.get('name', task['id']),
        'type': task.get('type', 'batch'),
        'description': task.get('description', ''),
        
        # Container configuration
        'container_image': task.get('container_image', 'amazonlinux:2'),
        'command': task.get('command', []),
        'environment': task.get('environment', {}),
        
        # Resource requirements
        'resources': {
            'vcpus': task.get('vcpus', 1),
            'memory': task.get('memory', 1024),
            'nodes': task.get('nodes', 1),
            'instance_type': task.get('instance_type', 'c5.large'),
            'storage': task.get('storage', 10)  # GB
        },
        
        # Retry and fault tolerance
        'retry_strategy': {
            'attempts': task.get('retry_attempts', 3),
            'backoff_multiplier': task.get('backoff_multiplier', 2.0),
            'max_delay_seconds': task.get('max_delay_seconds', 300)
        },
        
        # Checkpointing
        'checkpoint_enabled': task.get('checkpoint_enabled', True),
        'checkpoint_interval': task.get('checkpoint_interval', 300),  # seconds
        
        # Cost optimization
        'spot_enabled': task.get('spot_enabled', True),
        'spot_max_price': task.get('spot_max_price', '0.50'),
        'preemptible': task.get('preemptible', True),
        
        # Execution preferences
        'priority': task.get('priority', 50),
        'timeout_seconds': task.get('timeout_seconds', 3600),
        'parallel_execution': task.get('parallel_execution', True),
        
        # Metadata
        'tags': task.get('tags', {}),
        'metadata': task.get('metadata', {})
    }
    
    # Validate resource requirements
    if parsed_task['resources']['vcpus'] < 1:
        raise ValueError(f"Task {task['id']}: vcpus must be at least 1")
    if parsed_task['resources']['memory'] < 128:
        raise ValueError(f"Task {task['id']}: memory must be at least 128 MB")
    if parsed_task['resources']['nodes'] < 1:
        raise ValueError(f"Task {task['id']}: nodes must be at least 1")
    
    return parsed_task


def validate_workflow(parsed_workflow: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate parsed workflow for consistency and correctness.
    
    Args:
        parsed_workflow: Parsed workflow structure
        
    Returns:
        Dict containing validation results
    """
    errors = []
    warnings = []
    
    try:
        # Check for circular dependencies
        circular_deps = detect_circular_dependencies(parsed_workflow['dependencies'])
        if circular_deps:
            errors.append(f"Circular dependencies detected: {circular_deps}")
        
        # Check resource requirements
        total_vcpus = sum(task['resources']['vcpus'] * task['resources']['nodes'] 
                         for task in parsed_workflow['tasks'])
        if total_vcpus > 1000:  # Arbitrary limit
            warnings.append(f"High total vCPU requirement: {total_vcpus}")
        
        # Check for orphaned tasks (no dependencies and no dependents)
        task_ids = {task['id'] for task in parsed_workflow['tasks']}
        dependencies = parsed_workflow['dependencies']
        
        has_dependencies = set(dependencies.keys())
        is_dependency = set()
        for deps in dependencies.values():
            is_dependency.update(deps)
        
        orphaned_tasks = task_ids - has_dependencies - is_dependency
        if len(orphaned_tasks) > 1:
            warnings.append(f"Multiple orphaned tasks detected: {orphaned_tasks}")
        
        # Check for long-running tasks without checkpointing
        for task in parsed_workflow['tasks']:
            if (task['timeout_seconds'] > 3600 and 
                not task['checkpoint_enabled']):
                warnings.append(f"Long-running task {task['id']} without checkpointing")
        
        # Check for inconsistent instance types
        instance_types = {task['resources']['instance_type'] for task in parsed_workflow['tasks']}
        if len(instance_types) > 10:
            warnings.append(f"Many different instance types: {len(instance_types)}")
        
        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings,
            'total_tasks': len(parsed_workflow['tasks']),
            'total_dependencies': len(parsed_workflow['dependencies'])
        }
        
    except Exception as e:
        logger.error(f"Error validating workflow: {str(e)}")
        return {
            'valid': False,
            'errors': [str(e)],
            'warnings': warnings
        }


def detect_circular_dependencies(dependencies: Dict[str, List[str]]) -> List[List[str]]:
    """
    Detect circular dependencies in workflow.
    
    Args:
        dependencies: Dict mapping task IDs to their dependencies
        
    Returns:
        List of circular dependency chains
    """
    visited = set()
    rec_stack = set()
    circular_deps = []
    
    def dfs(node: str, path: List[str]) -> None:
        if node in rec_stack:
            # Found a cycle
            cycle_start = path.index(node)
            circular_deps.append(path[cycle_start:] + [node])
            return
        
        if node in visited:
            return
        
        visited.add(node)
        rec_stack.add(node)
        
        for dep in dependencies.get(node, []):
            dfs(dep, path + [node])
        
        rec_stack.remove(node)
    
    for task_id in dependencies:
        if task_id not in visited:
            dfs(task_id, [])
    
    return circular_deps


def generate_execution_plan(parsed_workflow: Dict[str, Any], workflow_id: str) -> Dict[str, Any]:
    """
    Generate step-by-step execution plan with parallelization.
    
    Args:
        parsed_workflow: Parsed workflow structure
        workflow_id: Unique workflow identifier
        
    Returns:
        Dict containing execution plan
    """
    try:
        execution_plan = {
            'workflow_id': workflow_id,
            'stages': [],
            'parallel_groups': [],
            'total_tasks': len(parsed_workflow['tasks']),
            'parallelization_factor': 1,
            'critical_path': []
        }
        
        # Create task lookup
        task_lookup = {task['id']: task for task in parsed_workflow['tasks']}
        dependencies = parsed_workflow['dependencies']
        
        # Perform topological sort to determine execution order
        remaining_tasks = set(task_lookup.keys())
        completed_tasks = set()
        stage_number = 0
        
        while remaining_tasks:
            stage_number += 1
            
            # Find tasks with no remaining dependencies
            ready_tasks = []
            for task_id in remaining_tasks:
                deps = dependencies.get(task_id, [])
                if all(dep in completed_tasks for dep in deps):
                    ready_tasks.append(task_lookup[task_id])
            
            if not ready_tasks:
                # This shouldn't happen if we validated for circular dependencies
                raise ValueError("Unable to resolve task dependencies - possible circular dependency")
            
            # Create stage
            current_stage = {
                'stage': stage_number,
                'tasks': ready_tasks,
                'parallel_execution': len(ready_tasks) > 1,
                'max_concurrency': min(len(ready_tasks), 10),  # Limit parallelism
                'estimated_duration': max(
                    estimate_task_duration(task) for task in ready_tasks
                )
            }
            
            execution_plan['stages'].append(current_stage)
            
            # Update completed tasks
            for task in ready_tasks:
                completed_tasks.add(task['id'])
                remaining_tasks.remove(task['id'])
        
        # Calculate critical path
        execution_plan['critical_path'] = calculate_critical_path(
            parsed_workflow['tasks'], dependencies
        )
        
        # Calculate parallelization factor
        total_sequential_time = sum(stage['estimated_duration'] for stage in execution_plan['stages'])
        total_parallel_time = sum(
            estimate_task_duration(task) for task in parsed_workflow['tasks']
        )
        
        if total_parallel_time > 0:
            execution_plan['parallelization_factor'] = total_parallel_time / total_sequential_time
        
        return execution_plan
        
    except Exception as e:
        logger.error(f"Error generating execution plan: {str(e)}")
        raise


def calculate_critical_path(tasks: List[Dict[str, Any]], dependencies: Dict[str, List[str]]) -> List[str]:
    """
    Calculate the critical path through the workflow.
    
    Args:
        tasks: List of task definitions
        dependencies: Task dependencies
        
    Returns:
        List of task IDs in critical path order
    """
    task_durations = {task['id']: estimate_task_duration(task) for task in tasks}
    
    # Build reverse dependency graph
    dependents = defaultdict(list)
    for task_id, deps in dependencies.items():
        for dep in deps:
            dependents[dep].append(task_id)
    
    # Calculate longest path using DFS
    memo = {}
    
    def longest_path(task_id: str) -> Tuple[float, List[str]]:
        if task_id in memo:
            return memo[task_id]
        
        task_duration = task_durations[task_id]
        
        if task_id not in dependents:
            # Leaf node
            memo[task_id] = (task_duration, [task_id])
            return memo[task_id]
        
        max_duration = 0
        max_path = []
        
        for dependent in dependents[task_id]:
            dep_duration, dep_path = longest_path(dependent)
            if dep_duration > max_duration:
                max_duration = dep_duration
                max_path = dep_path
        
        total_duration = task_duration + max_duration
        total_path = [task_id] + max_path
        
        memo[task_id] = (total_duration, total_path)
        return memo[task_id]
    
    # Find the critical path starting from tasks with no dependencies
    root_tasks = [task['id'] for task in tasks if task['id'] not in dependencies]
    
    critical_duration = 0
    critical_path = []
    
    for root_task in root_tasks:
        duration, path = longest_path(root_task)
        if duration > critical_duration:
            critical_duration = duration
            critical_path = path
    
    return critical_path


def estimate_task_duration(task: Dict[str, Any]) -> float:
    """
    Estimate task execution duration in minutes.
    
    Args:
        task: Task definition
        
    Returns:
        Estimated duration in minutes
    """
    # Base duration based on resource requirements
    base_duration = max(
        task['resources']['vcpus'] * 5,  # 5 minutes per vCPU
        task['resources']['memory'] / 1024 * 10,  # 10 minutes per GB
        task['resources']['nodes'] * 15  # 15 minutes per node
    )
    
    # Adjust for task type
    task_type = task.get('type', 'batch')
    if task_type == 'mpi':
        base_duration *= 2  # MPI tasks typically take longer
    elif task_type == 'gpu':
        base_duration *= 1.5  # GPU tasks have overhead
    
    # Add checkpoint overhead if enabled
    if task.get('checkpoint_enabled', True):
        base_duration *= 1.1  # 10% overhead for checkpointing
    
    # Consider timeout as maximum
    timeout_minutes = task.get('timeout_seconds', 3600) / 60
    
    return min(base_duration, timeout_minutes)


def calculate_estimated_cost(execution_plan: Dict[str, Any], parsed_workflow: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate estimated cost for workflow execution.
    
    Args:
        execution_plan: Generated execution plan
        parsed_workflow: Parsed workflow structure
        
    Returns:
        Dict containing cost estimates
    """
    try:
        total_cost = 0
        cost_breakdown = {}
        
        for stage in execution_plan['stages']:
            stage_cost = 0
            
            for task in stage['tasks']:
                # Get instance type and pricing
                instance_type = task['resources']['instance_type']
                base_price = INSTANCE_PRICING.get(instance_type, 0.10)  # Default fallback
                
                # Apply Spot discount if enabled
                if task.get('spot_enabled', True):
                    price_per_hour = base_price * SPOT_DISCOUNT
                else:
                    price_per_hour = base_price
                
                # Calculate cost based on duration and nodes
                duration_hours = estimate_task_duration(task) / 60
                nodes = task['resources']['nodes']
                task_cost = price_per_hour * duration_hours * nodes
                
                stage_cost += task_cost
                cost_breakdown[task['id']] = {
                    'instance_type': instance_type,
                    'price_per_hour': price_per_hour,
                    'duration_hours': duration_hours,
                    'nodes': nodes,
                    'cost': task_cost,
                    'spot_enabled': task.get('spot_enabled', True)
                }
            
            total_cost += stage_cost
        
        # Add infrastructure costs (Step Functions, Lambda, etc.)
        infrastructure_cost = calculate_infrastructure_cost(execution_plan)
        total_cost += infrastructure_cost
        
        return {
            'total_cost_usd': round(total_cost, 2),
            'infrastructure_cost_usd': round(infrastructure_cost, 2),
            'compute_cost_usd': round(total_cost - infrastructure_cost, 2),
            'cost_breakdown': cost_breakdown,
            'currency': 'USD',
            'estimation_date': datetime.utcnow().isoformat(),
            'disclaimer': 'Costs are estimates and may vary based on actual usage, pricing changes, and regional differences'
        }
        
    except Exception as e:
        logger.error(f"Error calculating cost: {str(e)}")
        return {
            'total_cost_usd': 0,
            'error': str(e)
        }


def calculate_infrastructure_cost(execution_plan: Dict[str, Any]) -> float:
    """
    Calculate infrastructure service costs.
    
    Args:
        execution_plan: Generated execution plan
        
    Returns:
        Infrastructure cost in USD
    """
    # Step Functions cost: $0.025 per 1000 state transitions
    total_tasks = execution_plan['total_tasks']
    state_transitions = total_tasks * 10  # Estimate 10 transitions per task
    stepfunctions_cost = (state_transitions / 1000) * 0.025
    
    # Lambda cost: $0.20 per 1M requests + $0.0000166667 per GB-second
    lambda_requests = total_tasks * 5  # Estimate 5 Lambda invocations per task
    lambda_gb_seconds = lambda_requests * 0.512 * 30  # 512MB for 30 seconds average
    lambda_cost = (lambda_requests / 1000000) * 0.20 + lambda_gb_seconds * 0.0000166667
    
    # S3 cost: $0.023 per GB (estimated 1GB per workflow)
    s3_cost = 0.023
    
    # DynamoDB cost: $0.25 per million write requests
    dynamodb_writes = total_tasks * 10  # Estimate 10 writes per task
    dynamodb_cost = (dynamodb_writes / 1000000) * 0.25
    
    # CloudWatch cost: $0.50 per million API requests
    cloudwatch_requests = total_tasks * 20  # Estimate 20 CloudWatch calls per task
    cloudwatch_cost = (cloudwatch_requests / 1000000) * 0.50
    
    return stepfunctions_cost + lambda_cost + s3_cost + dynamodb_cost + cloudwatch_cost


def calculate_estimated_duration(execution_plan: Dict[str, Any], parsed_workflow: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate estimated duration for workflow execution.
    
    Args:
        execution_plan: Generated execution plan
        parsed_workflow: Parsed workflow structure
        
    Returns:
        Dict containing duration estimates
    """
    try:
        # Calculate sequential duration (sum of all stages)
        sequential_duration = sum(stage['estimated_duration'] for stage in execution_plan['stages'])
        
        # Calculate parallel duration (critical path)
        critical_path_duration = sum(
            estimate_task_duration(task) 
            for task in parsed_workflow['tasks']
            if task['id'] in execution_plan['critical_path']
        )
        
        # Add overhead for orchestration
        orchestration_overhead = len(execution_plan['stages']) * 2  # 2 minutes per stage
        
        total_duration = sequential_duration + orchestration_overhead
        
        return {
            'estimated_duration_minutes': round(total_duration, 1),
            'sequential_duration_minutes': round(sequential_duration, 1),
            'critical_path_duration_minutes': round(critical_path_duration, 1),
            'orchestration_overhead_minutes': orchestration_overhead,
            'total_stages': len(execution_plan['stages']),
            'parallelization_factor': execution_plan.get('parallelization_factor', 1),
            'critical_path_tasks': execution_plan['critical_path']
        }
        
    except Exception as e:
        logger.error(f"Error calculating duration: {str(e)}")
        return {
            'estimated_duration_minutes': 0,
            'error': str(e)
        }


def send_cloudwatch_metric(metric_name: str, value: float, workflow_id: str) -> None:
    """
    Send custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        workflow_id: Workflow ID for dimensions
    """
    try:
        cloudwatch.put_metric_data(
            Namespace=f'{PROJECT_NAME}/WorkflowParser',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'WorkflowId',
                            'Value': workflow_id
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
        
    except Exception as e:
        logger.error(f"Error sending CloudWatch metric: {str(e)}")
        # Don't raise exception for metrics - they're not critical