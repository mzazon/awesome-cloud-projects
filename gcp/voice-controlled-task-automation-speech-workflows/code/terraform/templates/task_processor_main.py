import json
import base64
import time
from google.cloud import logging
from google.cloud import storage
import functions_framework

# Initialize logging
logging_client = logging.Client()
logger = logging_client.logger("task-processor")

@functions_framework.http
def process_task(request):
    """Process tasks created by voice commands"""
    try:
        # Parse request data
        if request.content_type == 'application/json':
            data = request.get_json()
        else:
            # Handle Cloud Tasks payload (base64 encoded)
            try:
                data = json.loads(base64.b64decode(request.data).decode())
            except:
                # Fallback for direct JSON payloads
                data = request.get_json()
        
        if not data:
            return {'error': 'No data provided'}, 400
        
        action = data.get('action')
        parameters = data.get('parameters', {})
        
        # Validate action
        if not action:
            return {'error': 'Missing action parameter'}, 400
        
        # Log task processing start
        logger.log_struct({
            'message': 'Processing voice-triggered task',
            'action': action,
            'parameters': parameters,
            'timestamp': time.time()
        })
        
        # Execute based on action type
        if action == 'create_task':
            result = handle_task_creation(parameters)
        elif action == 'scheduled_task':
            result = handle_scheduled_task(parameters)
        elif action == 'generate_report':
            result = handle_report_generation(parameters)
        else:
            logger.warning(f'Unknown action received: {action}')
            return {'error': f'Unknown action: {action}'}, 400
        
        # Log successful completion
        logger.log_struct({
            'message': 'Task processing completed successfully',
            'action': action,
            'result': result,
            'timestamp': time.time()
        })
        
        return {
            'status': 'completed',
            'action': action,
            'result': result,
            'timestamp': time.time()
        }
        
    except Exception as e:
        error_msg = f'Task processing failed: {str(e)}'
        logger.error(error_msg)
        return {
            'error': error_msg,
            'timestamp': time.time()
        }, 500

def handle_task_creation(parameters):
    """Handle task creation logic"""
    priority = parameters.get('priority', 'normal')
    category = parameters.get('category', 'general')
    description = parameters.get('description', 'Voice-created task')
    
    # Generate unique task ID
    task_id = f'task-{int(time.time())}-{hash(description) % 10000}'
    
    # Simulate task creation (replace with actual business logic)
    task_data = {
        'id': task_id,
        'priority': priority,
        'category': category,
        'description': description,
        'status': 'created',
        'created_by': 'voice-command',
        'created_at': time.time(),
        'due_date': calculate_due_date(priority),
        'estimated_duration': estimate_duration(category, description)
    }
    
    # Log task creation details
    logger.log_struct({
        'message': 'Task created successfully',
        'task_data': task_data
    })
    
    # Here you would integrate with your actual task management system
    # Examples: JIRA, Asana, Trello, or custom database
    
    return task_data

def handle_scheduled_task(parameters):
    """Handle scheduled task logic"""
    schedule_time = parameters.get('schedule_time', 'default')
    description = parameters.get('description', 'Scheduled voice task')
    
    # Calculate actual schedule time
    actual_schedule_time = calculate_schedule_time(schedule_time)
    
    # Simulate scheduled task processing
    scheduled_data = {
        'type': 'scheduled',
        'description': description,
        'scheduled_for': actual_schedule_time,
        'parameters': parameters,
        'executed_at': time.time(),
        'status': 'scheduled'
    }
    
    # Log scheduled task execution
    logger.log_struct({
        'message': 'Scheduled task processed',
        'scheduled_data': scheduled_data
    })
    
    # Here you would integrate with your scheduling system
    # Examples: Google Calendar, Outlook, or custom scheduler
    
    return scheduled_data

def handle_report_generation(parameters):
    """Handle report generation logic"""
    report_type = parameters.get('report_type', 'general')
    description = parameters.get('description', 'Voice-requested report')
    
    # Generate unique report ID
    report_id = f'report-{int(time.time())}-{hash(description) % 10000}'
    
    # Simulate report generation
    report_data = {
        'report_id': report_id,
        'type': report_type,
        'description': description,
        'generated_at': time.time(),
        'generated_by': 'voice-command',
        'parameters': parameters,
        'status': 'generated',
        'data_points': generate_sample_data(report_type)
    }
    
    # Log report generation
    logger.log_struct({
        'message': 'Report generated successfully',
        'report_data': report_data
    })
    
    # Here you would integrate with your reporting system
    # Examples: Google Sheets, Power BI, Tableau, or custom analytics
    
    return report_data

def calculate_due_date(priority):
    """Calculate due date based on priority"""
    current_time = time.time()
    
    if priority == 'high':
        # Due in 4 hours for high priority
        return current_time + (4 * 3600)
    elif priority == 'low':
        # Due in 3 days for low priority
        return current_time + (3 * 24 * 3600)
    else:
        # Due in 1 day for normal priority
        return current_time + (24 * 3600)

def estimate_duration(category, description):
    """Estimate task duration based on category and description"""
    base_durations = {
        'meeting': 3600,      # 1 hour
        'email': 1800,        # 30 minutes
        'call': 2700,         # 45 minutes
        'document': 7200,     # 2 hours
        'general': 3600       # 1 hour default
    }
    
    base_duration = base_durations.get(category, 3600)
    
    # Adjust based on description keywords
    if any(word in description.lower() for word in ['quick', 'brief', 'short']):
        return base_duration * 0.5
    elif any(word in description.lower() for word in ['detailed', 'comprehensive', 'thorough']):
        return base_duration * 2
    
    return base_duration

def calculate_schedule_time(schedule_time):
    """Calculate actual schedule time from natural language"""
    current_time = time.time()
    
    schedule_map = {
        'tomorrow': current_time + (24 * 3600),
        'next_week': current_time + (7 * 24 * 3600),
        'one_hour': current_time + 3600,
        'default': current_time + 3600  # Default to 1 hour
    }
    
    return schedule_map.get(schedule_time, current_time + 3600)

def generate_sample_data(report_type):
    """Generate sample data for reports"""
    sample_data = {
        'daily': {
            'tasks_completed': 8,
            'tasks_pending': 3,
            'average_completion_time': 2.5,
            'priority_breakdown': {'high': 2, 'normal': 6, 'low': 3}
        },
        'weekly': {
            'total_tasks': 45,
            'completion_rate': 0.87,
            'categories': {'meeting': 15, 'email': 20, 'document': 10},
            'productivity_score': 85
        },
        'task_status': {
            'created': 12,
            'in_progress': 8,
            'completed': 25,
            'overdue': 2
        },
        'general': {
            'timestamp': time.time(),
            'voice_commands_processed': 147,
            'success_rate': 0.92
        }
    }
    
    return sample_data.get(report_type, sample_data['general'])