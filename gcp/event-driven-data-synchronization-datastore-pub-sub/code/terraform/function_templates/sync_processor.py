import base64
import json
import logging
import os
from datetime import datetime
from google.cloud import datastore
from google.cloud import pubsub_v1
import functions_framework

# Initialize clients
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
datastore_client = datastore.Client(project=PROJECT_ID)
publisher = pubsub_v1.PublisherClient()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def sync_processor(cloud_event):
    """
    Process data synchronization events with conflict resolution.
    
    This function handles create, update, and delete operations for Datastore entities
    with intelligent conflict resolution based on timestamps and business rules.
    """
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        event_data = json.loads(message_data.decode('utf-8'))
        
        logger.info(f"Processing sync event: {event_data}")
        
        # Extract event information
        entity_id = event_data.get('entity_id')
        operation = event_data.get('operation')  # create, update, delete
        data = event_data.get('data', {})
        timestamp = event_data.get('timestamp')
        correlation_id = event_data.get('correlation_id')
        
        # Validate required fields
        if not entity_id or not operation:
            logger.error(f"Invalid event data: missing entity_id or operation")
            return
        
        # Process based on operation type
        if operation in ['create', 'update']:
            result = handle_data_operation(entity_id, operation, data, timestamp, correlation_id)
        elif operation == 'delete':
            result = handle_delete_operation(entity_id, timestamp, correlation_id)
        else:
            logger.error(f"Unknown operation: {operation}")
            return
        
        # Publish success event for external systems if configured
        if result.get('success') and result.get('publish_external'):
            publish_external_sync_event(entity_id, operation, result.get('data'))
            
        logger.info(f"Sync operation completed: {result}")
        
    except Exception as e:
        logger.error(f"Sync processing failed: {str(e)}")
        # Re-raise exception to trigger dead letter queue
        raise

def handle_data_operation(entity_id, operation, data, timestamp, correlation_id):
    """
    Handle create/update operations with conflict resolution.
    
    Args:
        entity_id: Unique identifier for the entity
        operation: Either 'create' or 'update'
        data: Dictionary containing entity data
        timestamp: ISO timestamp of the operation
        correlation_id: Unique identifier for tracking the operation
        
    Returns:
        Dictionary with operation results
    """
    
    key = datastore_client.key('SyncEntity', entity_id)
    
    try:
        with datastore_client.transaction():
            # Get existing entity for conflict detection
            existing_entity = datastore_client.get(key)
            
            if existing_entity and operation == 'update':
                # Check for conflicts using timestamp
                existing_timestamp = existing_entity.get('last_modified')
                if existing_timestamp and timestamp:
                    try:
                        existing_dt = datetime.fromisoformat(existing_timestamp.replace('Z', '+00:00'))
                        new_dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                        
                        if existing_dt > new_dt:
                            # Conflict detected - apply resolution strategy
                            logger.warning(f"Conflict detected for entity {entity_id}")
                            return resolve_conflict(existing_entity, data, timestamp, correlation_id)
                    except ValueError as e:
                        logger.warning(f"Timestamp parsing error: {e}")
            
            # Create or update entity
            entity = existing_entity or datastore.Entity(key=key)
            
            # Update entity with new data
            entity.update(data)
            entity['last_modified'] = timestamp or datetime.utcnow().isoformat()
            entity['sync_status'] = 'synced'
            entity['version'] = entity.get('version', 0) + 1
            entity['correlation_id'] = correlation_id
            entity['operation'] = operation
            
            # Store entity
            datastore_client.put(entity)
            
            logger.info(f"Successfully {operation}d entity {entity_id} (version {entity['version']})")
            
            return {
                'success': True,
                'entity_id': entity_id,
                'operation': operation,
                'data': dict(entity),
                'conflict_resolved': False,
                'publish_external': True
            }
            
    except Exception as e:
        logger.error(f"Failed to {operation} entity {entity_id}: {str(e)}")
        return {
            'success': False,
            'entity_id': entity_id,
            'operation': operation,
            'error': str(e),
            'publish_external': False
        }

def resolve_conflict(existing_entity, new_data, timestamp, correlation_id):
    """
    Implement conflict resolution strategy.
    
    Strategy: 
    1. Merge non-conflicting fields
    2. Keep latest timestamp for metadata
    3. Apply business rules for specific fields
    4. Mark as conflict resolved
    
    Args:
        existing_entity: Current entity in Datastore
        new_data: New data to merge
        timestamp: Timestamp of the new data
        correlation_id: Operation correlation ID
        
    Returns:
        Dictionary with conflict resolution results
    """
    
    try:
        # Start with existing entity data
        resolved_data = dict(existing_entity)
        
        # Apply conflict resolution rules
        for key, value in new_data.items():
            if key == 'description':
                # For description, append if different
                existing_desc = resolved_data.get('description', '')
                if existing_desc and existing_desc != value:
                    resolved_data['description'] = f"{existing_desc} | {value}"
                else:
                    resolved_data['description'] = value
            elif key == 'metadata':
                # For metadata, merge dictionaries
                existing_meta = resolved_data.get('metadata', {})
                if isinstance(existing_meta, dict) and isinstance(value, dict):
                    existing_meta.update(value)
                    resolved_data['metadata'] = existing_meta
                else:
                    resolved_data['metadata'] = value
            elif key in ['name', 'status', 'category']:
                # For core fields, use newer value
                resolved_data[key] = value
            else:
                # For other fields, use newer value
                resolved_data[key] = value
        
        # Update conflict resolution metadata
        resolved_data['last_modified'] = max(
            existing_entity.get('last_modified', ''),
            timestamp or ''
        )
        resolved_data['conflict_resolved'] = True
        resolved_data['conflict_resolution_timestamp'] = datetime.utcnow().isoformat()
        resolved_data['version'] = existing_entity.get('version', 0) + 1
        resolved_data['correlation_id'] = correlation_id
        
        # Update entity in Datastore
        updated_entity = datastore.Entity(existing_entity.key)
        updated_entity.update(resolved_data)
        datastore_client.put(updated_entity)
        
        logger.info(f"Conflict resolved for entity {existing_entity.key.name}")
        
        return {
            'success': True,
            'entity_id': existing_entity.key.name,
            'operation': 'conflict_resolved',
            'data': resolved_data,
            'conflict_resolved': True,
            'publish_external': True
        }
        
    except Exception as e:
        logger.error(f"Conflict resolution failed for entity {existing_entity.key.name}: {str(e)}")
        return {
            'success': False,
            'entity_id': existing_entity.key.name,
            'operation': 'conflict_resolution_failed',
            'error': str(e),
            'publish_external': False
        }

def handle_delete_operation(entity_id, timestamp, correlation_id):
    """
    Handle delete operations with proper cleanup.
    
    Args:
        entity_id: Unique identifier for the entity
        timestamp: ISO timestamp of the operation
        correlation_id: Unique identifier for tracking the operation
        
    Returns:
        Dictionary with operation results
    """
    
    key = datastore_client.key('SyncEntity', entity_id)
    
    try:
        with datastore_client.transaction():
            entity = datastore_client.get(key)
            
            if entity:
                # Store deletion metadata before deleting
                deletion_record = {
                    'entity_id': entity_id,
                    'deleted_at': timestamp or datetime.utcnow().isoformat(),
                    'deleted_data': dict(entity),
                    'correlation_id': correlation_id
                }
                
                # Create deletion audit record
                audit_key = datastore_client.key('DeletedEntity', f"{entity_id}-{datetime.utcnow().isoformat()}")
                audit_entity = datastore.Entity(key=audit_key)
                audit_entity.update(deletion_record)
                datastore_client.put(audit_entity)
                
                # Delete the main entity
                datastore_client.delete(key)
                
                logger.info(f"Successfully deleted entity {entity_id}")
                
                return {
                    'success': True,
                    'entity_id': entity_id,
                    'operation': 'delete',
                    'data': deletion_record,
                    'publish_external': True
                }
            else:
                logger.warning(f"Entity {entity_id} not found for deletion")
                return {
                    'success': True,
                    'entity_id': entity_id,
                    'operation': 'delete',
                    'message': 'Entity not found (already deleted)',
                    'publish_external': False
                }
                
    except Exception as e:
        logger.error(f"Failed to delete entity {entity_id}: {str(e)}")
        return {
            'success': False,
            'entity_id': entity_id,
            'operation': 'delete',
            'error': str(e),
            'publish_external': False
        }

def publish_external_sync_event(entity_id, operation, data):
    """
    Publish events for external system synchronization.
    
    Args:
        entity_id: Unique identifier for the entity
        operation: Type of operation (create, update, delete)
        data: Entity data to synchronize
    """
    
    try:
        # Check if external sync topics exist
        topic_name = f"external-sync-{operation}"
        topic_path = publisher.topic_path(PROJECT_ID, topic_name)
        
        message_data = json.dumps({
            'entity_id': entity_id,
            'operation': operation,
            'data': data,
            'source': 'datastore-sync',
            'timestamp': datetime.utcnow().isoformat(),
            'sync_version': '1.0'
        }).encode('utf-8')
        
        future = publisher.publish(topic_path, message_data)
        message_id = future.result()
        
        logger.info(f"Published external sync event for {entity_id}: {message_id}")
        
    except Exception as e:
        logger.warning(f"Failed to publish external sync event for {entity_id}: {str(e)}")
        # Don't raise exception as this is optional functionality