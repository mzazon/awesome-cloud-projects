import json
import boto3
import os
from datetime import datetime

personalize = boto3.client('personalize')

def lambda_handler(event, context):
    """
    Personalize Manager Lambda Function
    
    Manages Amazon Personalize resources including dataset groups,
    solutions, campaigns, and training workflows.
    """
    try:
        # Parse request body if it's a string (API Gateway format)
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
        
        action = body.get('action')
        
        if action == 'create_dataset_group':
            return create_dataset_group(body)
        elif action == 'create_dataset':
            return create_dataset(body)
        elif action == 'import_data':
            return import_data(body)
        elif action == 'create_solution':
            return create_solution(body)
        elif action == 'create_solution_version':
            return create_solution_version(body)
        elif action == 'create_campaign':
            return create_campaign(body)
        elif action == 'update_campaign':
            return update_campaign(body)
        elif action == 'check_status':
            return check_status(body)
        elif action == 'list_resources':
            return list_resources(body)
        elif action == 'create_event_tracker':
            return create_event_tracker(body)
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        print(f"Error in Personalize manager: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def create_dataset_group(event_data):
    """Create a new Personalize dataset group"""
    try:
        dataset_group_name = event_data['dataset_group_name']
        domain = event_data.get('domain', 'ECOMMERCE')
        
        response = personalize.create_dataset_group(
            name=dataset_group_name,
            domain=domain
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'dataset_group_arn': response['datasetGroupArn'],
                'message': 'Dataset group creation initiated'
            })
        }
        
    except Exception as e:
        print(f"Error creating dataset group: {str(e)}")
        raise e

def create_dataset(event_data):
    """Create a dataset within a dataset group"""
    try:
        dataset_name = event_data['dataset_name']
        dataset_group_arn = event_data['dataset_group_arn']
        dataset_type = event_data['dataset_type']  # INTERACTIONS, ITEMS, USERS
        schema_arn = event_data['schema_arn']
        
        response = personalize.create_dataset(
            name=dataset_name,
            datasetGroupArn=dataset_group_arn,
            datasetType=dataset_type,
            schemaArn=schema_arn
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'dataset_arn': response['datasetArn'],
                'message': 'Dataset creation initiated'
            })
        }
        
    except Exception as e:
        print(f"Error creating dataset: {str(e)}")
        raise e

def import_data(event_data):
    """Import data into a Personalize dataset"""
    try:
        job_name = event_data['job_name']
        dataset_arn = event_data['dataset_arn']
        s3_data_source = event_data['s3_data_source']
        role_arn = event_data['role_arn']
        import_mode = event_data.get('import_mode', 'FULL')
        
        response = personalize.create_dataset_import_job(
            jobName=job_name,
            datasetArn=dataset_arn,
            dataSource={
                's3DataSource': {
                    'path': s3_data_source
                }
            },
            roleArn=role_arn,
            importMode=import_mode
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'dataset_import_job_arn': response['datasetImportJobArn'],
                'message': 'Data import job initiated'
            })
        }
        
    except Exception as e:
        print(f"Error importing data: {str(e)}")
        raise e

def create_solution(event_data):
    """Create a Personalize solution"""
    try:
        solution_name = event_data['solution_name']
        dataset_group_arn = event_data['dataset_group_arn']
        recipe_arn = event_data['recipe_arn']
        solution_config = event_data.get('solution_config', {})
        
        params = {
            'name': solution_name,
            'datasetGroupArn': dataset_group_arn,
            'recipeArn': recipe_arn
        }
        
        if solution_config:
            params['solutionConfig'] = solution_config
        
        response = personalize.create_solution(**params)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'solution_arn': response['solutionArn'],
                'message': 'Solution creation initiated'
            })
        }
        
    except Exception as e:
        print(f"Error creating solution: {str(e)}")
        raise e

def create_solution_version(event_data):
    """Create a new version of a Personalize solution (train model)"""
    try:
        solution_arn = event_data['solution_arn']
        training_mode = event_data.get('training_mode', 'FULL')
        
        response = personalize.create_solution_version(
            solutionArn=solution_arn,
            trainingMode=training_mode
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'solution_version_arn': response['solutionVersionArn'],
                'message': 'Solution training initiated'
            })
        }
        
    except Exception as e:
        print(f"Error creating solution version: {str(e)}")
        raise e

def create_campaign(event_data):
    """Create a Personalize campaign for real-time recommendations"""
    try:
        campaign_name = event_data['campaign_name']
        solution_version_arn = event_data['solution_version_arn']
        min_provisioned_tps = event_data.get('min_provisioned_tps', 1)
        campaign_config = event_data.get('campaign_config', {})
        
        params = {
            'name': campaign_name,
            'solutionVersionArn': solution_version_arn,
            'minProvisionedTPS': min_provisioned_tps
        }
        
        if campaign_config:
            params['campaignConfig'] = campaign_config
        
        response = personalize.create_campaign(**params)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'campaign_arn': response['campaignArn'],
                'message': 'Campaign creation initiated'
            })
        }
        
    except Exception as e:
        print(f"Error creating campaign: {str(e)}")
        raise e

def update_campaign(event_data):
    """Update an existing Personalize campaign"""
    try:
        campaign_arn = event_data['campaign_arn']
        solution_version_arn = event_data.get('solution_version_arn')
        min_provisioned_tps = event_data.get('min_provisioned_tps')
        campaign_config = event_data.get('campaign_config')
        
        params = {'campaignArn': campaign_arn}
        
        if solution_version_arn:
            params['solutionVersionArn'] = solution_version_arn
        if min_provisioned_tps:
            params['minProvisionedTPS'] = min_provisioned_tps
        if campaign_config:
            params['campaignConfig'] = campaign_config
        
        response = personalize.update_campaign(**params)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'campaign_arn': response['campaignArn'],
                'message': 'Campaign update initiated'
            })
        }
        
    except Exception as e:
        print(f"Error updating campaign: {str(e)}")
        raise e

def create_event_tracker(event_data):
    """Create an event tracker for real-time data ingestion"""
    try:
        name = event_data['name']
        dataset_group_arn = event_data['dataset_group_arn']
        
        response = personalize.create_event_tracker(
            name=name,
            datasetGroupArn=dataset_group_arn
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'event_tracker_arn': response['eventTrackerArn'],
                'tracking_id': response['trackingId'],
                'message': 'Event tracker created'
            })
        }
        
    except Exception as e:
        print(f"Error creating event tracker: {str(e)}")
        raise e

def check_status(event_data):
    """Check the status of various Personalize resources"""
    try:
        resource_arn = event_data['resource_arn']
        resource_type = event_data['resource_type']
        
        if resource_type == 'solution':
            response = personalize.describe_solution(solutionArn=resource_arn)
            status = response['solution']['status']
        elif resource_type == 'solution_version':
            response = personalize.describe_solution_version(solutionVersionArn=resource_arn)
            status = response['solutionVersion']['status']
        elif resource_type == 'campaign':
            response = personalize.describe_campaign(campaignArn=resource_arn)
            status = response['campaign']['status']
        elif resource_type == 'dataset_import_job':
            response = personalize.describe_dataset_import_job(datasetImportJobArn=resource_arn)
            status = response['datasetImportJob']['status']
        elif resource_type == 'dataset_group':
            response = personalize.describe_dataset_group(datasetGroupArn=resource_arn)
            status = response['datasetGroup']['status']
        else:
            raise ValueError(f"Unknown resource type: {resource_type}")
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'resource_arn': resource_arn,
                'resource_type': resource_type,
                'status': status,
                'is_complete': status in ['ACTIVE', 'CREATE FAILED'],
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error checking status: {str(e)}")
        raise e

def list_resources(event_data):
    """List Personalize resources"""
    try:
        resource_type = event_data.get('resource_type', 'dataset_groups')
        max_results = event_data.get('max_results', 10)
        
        if resource_type == 'dataset_groups':
            response = personalize.list_dataset_groups(maxResults=max_results)
            resources = response['datasetGroups']
        elif resource_type == 'solutions':
            dataset_group_arn = event_data['dataset_group_arn']
            response = personalize.list_solutions(
                datasetGroupArn=dataset_group_arn,
                maxResults=max_results
            )
            resources = response['solutions']
        elif resource_type == 'campaigns':
            solution_arn = event_data.get('solution_arn')
            if solution_arn:
                response = personalize.list_campaigns(
                    solutionArn=solution_arn,
                    maxResults=max_results
                )
            else:
                response = personalize.list_campaigns(maxResults=max_results)
            resources = response['campaigns']
        else:
            raise ValueError(f"Unknown resource type: {resource_type}")
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'resource_type': resource_type,
                'resources': resources,
                'count': len(resources)
            })
        }
        
    except Exception as e:
        print(f"Error listing resources: {str(e)}")
        raise e

def get_recommendations_for_user(user_id, campaign_arn, num_results=10):
    """Helper function to get recommendations for testing"""
    personalize_runtime = boto3.client('personalize-runtime')
    
    try:
        response = personalize_runtime.get_recommendations(
            campaignArn=campaign_arn,
            userId=user_id,
            numResults=num_results
        )
        
        return response['itemList']
        
    except Exception as e:
        print(f"Error getting recommendations: {str(e)}")
        return []