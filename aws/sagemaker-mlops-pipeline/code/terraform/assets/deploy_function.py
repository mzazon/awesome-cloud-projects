import json
import boto3
import os
import time
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to deploy approved ML models to production endpoints
    """
    codepipeline = boto3.client('codepipeline')
    sagemaker = boto3.client('sagemaker')
    s3 = boto3.client('s3')
    
    # Get job details from CodePipeline
    job_id = event['CodePipeline.job']['id']
    
    try:
        logger.info(f"Starting model deployment for job: {job_id}")
        
        # Get input artifacts from CodePipeline
        input_artifacts = event['CodePipeline.job']['data']['inputArtifacts']
        
        if not input_artifacts:
            raise Exception("No input artifacts found")
        
        # Get artifact location
        artifact = input_artifacts[0]
        bucket = artifact['location']['s3Location']['bucketName']
        key = artifact['location']['s3Location']['objectKey']
        
        logger.info(f"Processing artifact from s3://{bucket}/{key}")
        
        # Download and extract artifact to find model package ARN
        # In a real implementation, you would download the artifact zip file
        # and extract the model_package_arn.txt file
        
        # For this example, we'll list the latest approved model package
        model_package_group_name = os.environ.get('MODEL_PACKAGE_GROUP_NAME', '${model_package_group_name}')
        
        # List approved model packages
        response = sagemaker.list_model_packages(
            ModelPackageGroupName=model_package_group_name,
            ModelApprovalStatus='Approved',
            SortBy='CreationTime',
            SortOrder='Descending',
            MaxResults=1
        )
        
        if not response['ModelPackageSummaryList']:
            raise Exception("No approved model packages found")
        
        model_package_arn = response['ModelPackageSummaryList'][0]['ModelPackageArn']
        logger.info(f"Found approved model package: {model_package_arn}")
        
        # Create unique names for deployment resources
        timestamp = int(time.time())
        project_name = os.environ.get('PROJECT_NAME', '${project_name}')
        environment = os.environ.get('ENVIRONMENT', '${environment}')
        
        model_name = f"{project_name}-{environment}-model-{timestamp}"
        endpoint_config_name = f"{project_name}-{environment}-config-{timestamp}"
        endpoint_name = f"{project_name}-{environment}-endpoint-{timestamp}"
        
        # Get SageMaker execution role
        sagemaker_role_arn = os.environ.get('SAGEMAKER_ROLE_ARN')
        instance_type = os.environ.get('INSTANCE_TYPE', 'ml.t2.medium')
        
        # Create SageMaker model
        logger.info(f"Creating SageMaker model: {model_name}")
        model_response = sagemaker.create_model_from_model_package(
            ModelName=model_name,
            ModelPackageName=model_package_arn,
            ExecutionRoleArn=sagemaker_role_arn,
            Tags=[
                {'Key': 'Project', 'Value': project_name},
                {'Key': 'Environment', 'Value': environment},
                {'Key': 'CreatedBy', 'Value': 'MLOps-Pipeline'},
                {'Key': 'ModelPackageArn', 'Value': model_package_arn}
            ]
        )
        
        # Create endpoint configuration
        logger.info(f"Creating endpoint configuration: {endpoint_config_name}")
        endpoint_config_response = sagemaker.create_endpoint_config(
            EndpointConfigName=endpoint_config_name,
            ProductionVariants=[
                {
                    'VariantName': 'primary',
                    'ModelName': model_name,
                    'InitialInstanceCount': 1,
                    'InstanceType': instance_type,
                    'InitialVariantWeight': 1.0
                }
            ],
            Tags=[
                {'Key': 'Project', 'Value': project_name},
                {'Key': 'Environment', 'Value': environment},
                {'Key': 'CreatedBy', 'Value': 'MLOps-Pipeline'}
            ]
        )
        
        # Create or update endpoint
        logger.info(f"Creating/updating endpoint: {endpoint_name}")
        try:
            # Try to update existing endpoint
            existing_endpoints = sagemaker.list_endpoints(
                NameContains=f"{project_name}-{environment}-endpoint",
                StatusEquals='InService'
            )
            
            if existing_endpoints['Endpoints']:
                # Update existing endpoint
                existing_endpoint_name = existing_endpoints['Endpoints'][0]['EndpointName']
                logger.info(f"Updating existing endpoint: {existing_endpoint_name}")
                
                endpoint_response = sagemaker.update_endpoint(
                    EndpointName=existing_endpoint_name,
                    EndpointConfigName=endpoint_config_name
                )
                endpoint_name = existing_endpoint_name
            else:
                # Create new endpoint
                endpoint_response = sagemaker.create_endpoint(
                    EndpointName=endpoint_name,
                    EndpointConfigName=endpoint_config_name,
                    Tags=[
                        {'Key': 'Project', 'Value': project_name},
                        {'Key': 'Environment', 'Value': environment},
                        {'Key': 'CreatedBy', 'Value': 'MLOps-Pipeline'}
                    ]
                )
        except Exception as e:
            logger.error(f"Error creating/updating endpoint: {str(e)}")
            # Create new endpoint if update fails
            endpoint_response = sagemaker.create_endpoint(
                EndpointName=endpoint_name,
                EndpointConfigName=endpoint_config_name,
                Tags=[
                    {'Key': 'Project', 'Value': project_name},
                    {'Key': 'Environment', 'Value': environment},
                    {'Key': 'CreatedBy', 'Value': 'MLOps-Pipeline'}
                ]
            )
        
        logger.info(f"Successfully initiated deployment to endpoint: {endpoint_name}")
        
        # Create deployment summary
        deployment_info = {
            'model_package_arn': model_package_arn,
            'model_name': model_name,
            'endpoint_config_name': endpoint_config_name,
            'endpoint_name': endpoint_name,
            'deployment_timestamp': timestamp,
            'status': 'DEPLOYED'
        }
        
        # Signal success to CodePipeline
        codepipeline.put_job_success_result(
            jobId=job_id,
            outputVariables={
                'MODEL_PACKAGE_ARN': model_package_arn,
                'ENDPOINT_NAME': endpoint_name,
                'DEPLOYMENT_STATUS': 'SUCCESS'
            }
        )
        
        logger.info("Deployment completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Deployment successful',
                'deployment_info': deployment_info
            })
        }
        
    except Exception as e:
        error_message = f"Deployment failed: {str(e)}"
        logger.error(error_message)
        
        # Signal failure to CodePipeline
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                'message': error_message,
                'type': 'JobFailed'
            }
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Deployment failed',
                'error': error_message
            })
        }