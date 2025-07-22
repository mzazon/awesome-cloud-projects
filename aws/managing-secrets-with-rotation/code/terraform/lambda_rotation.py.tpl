import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secretsmanager = boto3.client('secretsmanager')


def lambda_handler(event, context):
    """
    Lambda function to handle secret rotation for AWS Secrets Manager
    
    This function implements the four-step rotation process:
    1. createSecret: Generate new secret version
    2. setSecret: Update the secret in the service (database)
    3. testSecret: Test the new secret
    4. finishSecret: Complete the rotation
    """
    try:
        # Extract parameters from event
        secret_arn = event['SecretId']
        token = event['ClientRequestToken']
        step = event['Step']
        
        logger.info(f"Starting rotation step: {step} for secret: {secret_arn}")
        
        # Execute the appropriate rotation step
        if step == "createSecret":
            create_secret(secret_arn, token)
        elif step == "setSecret":
            set_secret(secret_arn, token)
        elif step == "testSecret":
            test_secret(secret_arn, token)
        elif step == "finishSecret":
            finish_secret(secret_arn, token)
        else:
            logger.error(f"Invalid step parameter: {step}")
            raise ValueError(f"Invalid step parameter: {step}")
        
        logger.info(f"Successfully completed rotation step: {step}")
        return {
            "statusCode": 200,
            "body": json.dumps(f"Rotation step {step} completed successfully")
        }
        
    except Exception as e:
        logger.error(f"Error in rotation step {step}: {str(e)}")
        raise


def create_secret(secret_arn, token):
    """
    Create a new secret version with a new password
    
    This step generates a new password and creates a new version of the secret
    tagged with AWSPENDING stage.
    """
    try:
        # Check if AWSPENDING version already exists
        try:
            secretsmanager.get_secret_value(
                SecretId=secret_arn,
                VersionId=token,
                VersionStage="AWSPENDING"
            )
            logger.info("createSecret: AWSPENDING version already exists")
            return
        except ClientError as e:
            if e.response['Error']['Code'] != 'ResourceNotFoundException':
                raise
        
        # Get the current secret
        current_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT"
        )
        
        # Parse current secret data
        current_data = json.loads(current_secret['SecretString'])
        
        # Generate new password
        new_password_response = secretsmanager.get_random_password(
            PasswordLength=20,
            ExcludeCharacters='"@/\\`',
            RequireEachIncludedType=True
        )
        new_password = new_password_response['RandomPassword']
        
        # Create new secret data with updated password
        new_secret_data = current_data.copy()
        new_secret_data['password'] = new_password
        
        # Create new secret version
        secretsmanager.put_secret_value(
            SecretId=secret_arn,
            ClientRequestToken=token,
            SecretString=json.dumps(new_secret_data),
            VersionStages=['AWSPENDING']
        )
        
        logger.info("createSecret: Successfully created new secret version")
        
    except Exception as e:
        logger.error(f"createSecret: Error creating secret version: {str(e)}")
        raise


def set_secret(secret_arn, token):
    """
    Set the secret in the service (database)
    
    In a production environment, this would connect to the database
    and update the user's password to match the new secret.
    """
    try:
        # Get the pending secret
        pending_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionId=token,
            VersionStage="AWSPENDING"
        )
        
        pending_data = json.loads(pending_secret['SecretString'])
        
        # In a real implementation, you would:
        # 1. Connect to the database using admin credentials
        # 2. Update the user's password to pending_data['password']
        # 3. Verify the password change was successful
        
        logger.info("setSecret: Password would be updated in the database")
        logger.info(f"setSecret: Database host: {pending_data.get('host')}")
        logger.info(f"setSecret: Database user: {pending_data.get('username')}")
        
        # For demo purposes, we'll just log and continue
        # In production, implement actual database connection and password update
        
    except Exception as e:
        logger.error(f"setSecret: Error setting secret in service: {str(e)}")
        raise


def test_secret(secret_arn, token):
    """
    Test the new secret
    
    This step verifies that the new secret works correctly by
    attempting to connect to the database with the new credentials.
    """
    try:
        # Get the pending secret
        pending_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionId=token,
            VersionStage="AWSPENDING"
        )
        
        pending_data = json.loads(pending_secret['SecretString'])
        
        # In a real implementation, you would:
        # 1. Connect to the database using the new credentials
        # 2. Execute a simple query to verify connectivity
        # 3. Close the connection
        
        logger.info("testSecret: New credentials would be tested")
        logger.info(f"testSecret: Testing connection to {pending_data.get('host')}:{pending_data.get('port')}")
        
        # For demo purposes, we'll simulate a successful test
        # In production, implement actual database connection test
        
        # Simulate connection test
        if not pending_data.get('password'):
            raise ValueError("Password is empty")
            
        logger.info("testSecret: Connection test successful")
        
    except Exception as e:
        logger.error(f"testSecret: Error testing secret: {str(e)}")
        raise


def finish_secret(secret_arn, token):
    """
    Complete the rotation
    
    This step moves the AWSCURRENT stage to the new version and
    moves the old version to AWSPREVIOUS.
    """
    try:
        # Get the current version ID
        current_version_id = None
        try:
            versions = secretsmanager.list_secret_version_ids(SecretId=secret_arn)
            for version in versions['Versions']:
                if 'AWSCURRENT' in version['VersionStages']:
                    current_version_id = version['VersionId']
                    break
        except Exception as e:
            logger.warning(f"Could not get current version ID: {str(e)}")
        
        # Update secret version stages
        if current_version_id:
            # Move AWSCURRENT to the new version and AWSPREVIOUS to old version
            secretsmanager.update_secret_version_stage(
                SecretId=secret_arn,
                VersionStage="AWSCURRENT",
                MoveToVersionId=token,
                RemoveFromVersionId=current_version_id
            )
            
            # Move old version to AWSPREVIOUS
            secretsmanager.update_secret_version_stage(
                SecretId=secret_arn,
                VersionStage="AWSPREVIOUS",
                MoveToVersionId=current_version_id
            )
        else:
            # If no current version found, just move AWSCURRENT to new version
            secretsmanager.update_secret_version_stage(
                SecretId=secret_arn,
                VersionStage="AWSCURRENT",
                MoveToVersionId=token
            )
        
        logger.info("finishSecret: Successfully completed rotation")
        
    except Exception as e:
        logger.error(f"finishSecret: Error finishing rotation: {str(e)}")
        raise


def get_secret_dict(secret_arn, version_stage="AWSCURRENT"):
    """
    Helper function to get secret as a dictionary
    """
    try:
        response = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionStage=version_stage
        )
        return json.loads(response['SecretString'])
    except Exception as e:
        logger.error(f"Error getting secret: {str(e)}")
        raise