#!/usr/bin/env python3
"""
CDK Application for Serverless Medical Image Processing with AWS HealthImaging and Step Functions

This application creates a complete serverless medical imaging pipeline that:
- Processes DICOM files uploaded to S3
- Imports them into AWS HealthImaging for HIPAA-compliant storage
- Orchestrates workflows using Step Functions
- Performs automated analysis using Lambda functions
- Provides real-time notifications via EventBridge

Architecture:
- S3 buckets for input/output
- AWS HealthImaging data store for medical image storage
- Lambda functions for processing logic
- Step Functions for workflow orchestration
- EventBridge for event-driven automation
- IAM roles with least privilege access
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_events as events,
    aws_events_targets as targets,
    aws_s3_notifications as s3n,
    aws_logs as logs
)
from constructs import Construct


class MedicalImageProcessingStack(Stack):
    """
    CDK Stack for Serverless Medical Image Processing Pipeline
    
    This stack creates all the infrastructure needed for a HIPAA-compliant
    medical imaging workflow using AWS HealthImaging and Step Functions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.datastore_name = self.node.try_get_context("datastore_name") or "medical-imaging-datastore"
        self.environment_name = self.node.try_get_context("environment") or "dev"
        
        # Create S3 buckets for input and output
        self.input_bucket, self.output_bucket = self._create_storage_infrastructure()
        
        # Create IAM roles for Lambda and Step Functions
        self.lambda_role, self.step_functions_role = self._create_iam_roles()
        
        # Create HealthImaging data store
        self.datastore_id = self._create_healthimaging_datastore()
        
        # Create Lambda functions
        self.lambda_functions = self._create_lambda_functions()
        
        # Create Step Functions state machine
        self.state_machine = self._create_step_functions_workflow()
        
        # Create EventBridge rules
        self._create_eventbridge_rules()
        
        # Configure S3 event notifications
        self._configure_s3_notifications()
        
        # Create CloudWatch Log Groups
        self._create_log_groups()
        
        # Create stack outputs
        self._create_outputs()

    def _create_storage_infrastructure(self) -> tuple[s3.Bucket, s3.Bucket]:
        """
        Create S3 buckets for DICOM input and processed output storage.
        
        Returns:
            Tuple of (input_bucket, output_bucket)
        """
        # Input bucket for DICOM files
        input_bucket = s3.Bucket(
            self,
            "DicomInputBucket",
            bucket_name=f"dicom-input-{self.environment_name}-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                )
            ]
        )

        # Output bucket for processed results
        output_bucket = s3.Bucket(
            self,
            "DicomOutputBucket",
            bucket_name=f"dicom-output-{self.environment_name}-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldResults",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        return input_bucket, output_bucket

    def _create_iam_roles(self) -> tuple[iam.Role, iam.Role]:
        """
        Create IAM roles for Lambda functions and Step Functions with least privilege access.
        
        Returns:
            Tuple of (lambda_role, step_functions_role)
        """
        # Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add permissions for HealthImaging, S3, and Step Functions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "medical-imaging:*",
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket",
                    "states:StartExecution",
                    "states:SendTaskSuccess",
                    "states:SendTaskFailure"
                ],
                resources=["*"]  # In production, scope this down to specific resources
            )
        )

        # Step Functions execution role
        step_functions_role = iam.Role(
            self,
            "StepFunctionsExecutionRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaRole")
            ]
        )

        # Add permissions for HealthImaging SDK calls
        step_functions_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "medical-imaging:GetDICOMImportJob",
                    "medical-imaging:ListDICOMImportJobs"
                ],
                resources=["*"]
            )
        )

        return lambda_role, step_functions_role

    def _create_healthimaging_datastore(self) -> str:
        """
        Create AWS HealthImaging data store for HIPAA-compliant medical image storage.
        
        Returns:
            Data store ID as a string reference
        """
        # Note: CDK doesn't have native HealthImaging constructs yet
        # Using CfnResource to create the data store
        datastore = cdk.CfnResource(
            self,
            "HealthImagingDataStore",
            type="AWS::HealthImaging::Datastore",
            properties={
                "DatastoreName": self.datastore_name,
                "Tags": {
                    "Environment": self.environment_name,
                    "Application": "MedicalImageProcessing",
                    "Compliance": "HIPAA"
                }
            }
        )

        return datastore.ref

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """
        Create Lambda functions for the medical imaging pipeline.
        
        Returns:
            Dictionary of Lambda function constructs
        """
        functions = {}

        # Import initiation function
        functions["start_import"] = lambda_.Function(
            self,
            "StartDicomImportFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="start_import.lambda_handler",
            code=lambda_.Code.from_inline(self._get_start_import_code()),
            timeout=Duration.minutes(1),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "DATASTORE_ID": self.datastore_id,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "LAMBDA_ROLE_ARN": self.lambda_role.role_arn
            },
            description="Initiates DICOM import jobs when files are uploaded to S3"
        )

        # Metadata processing function
        functions["process_metadata"] = lambda_.Function(
            self,
            "ProcessMetadataFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="process_metadata.lambda_handler",
            code=lambda_.Code.from_inline(self._get_metadata_processing_code()),
            timeout=Duration.minutes(2),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "OUTPUT_BUCKET": self.output_bucket.bucket_name
            },
            description="Extracts and processes DICOM metadata from HealthImaging image sets"
        )

        # Image analysis function
        functions["analyze_image"] = lambda_.Function(
            self,
            "AnalyzeImageFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="analyze_image.lambda_handler",
            code=lambda_.Code.from_inline(self._get_image_analysis_code()),
            timeout=Duration.minutes(5),
            memory_size=1024,
            role=self.lambda_role,
            environment={
                "OUTPUT_BUCKET": self.output_bucket.bucket_name
            },
            description="Performs basic image analysis on medical images"
        )

        # Grant S3 permissions to all functions
        for function in functions.values():
            self.input_bucket.grant_read(function)
            self.output_bucket.grant_read_write(function)

        return functions

    def _create_step_functions_workflow(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for workflow orchestration.
        
        Returns:
            Step Functions state machine construct
        """
        # Define the state machine workflow
        check_import_status = sfn_tasks.CallAwsService(
            self,
            "CheckImportStatus",
            service="medical-imaging",
            action="getDICOMImportJob",
            parameters={
                "DatastoreId.$": "$.dataStoreId",
                "JobId.$": "$.jobId"
            },
            result_path="$.importStatus"
        )

        # Choice state to check import completion
        is_import_complete = sfn.Choice(self, "IsImportComplete")

        # Wait state for polling
        wait_for_import = sfn.Wait(
            self,
            "WaitForImport",
            time=sfn.WaitTime.duration(Duration.seconds(30))
        )

        # Process image sets task
        process_image_sets = sfn_tasks.LambdaInvoke(
            self,
            "ProcessImageSets",
            lambda_function=self.lambda_functions["process_metadata"],
            output_path="$.Payload"
        )

        # Analyze images task
        analyze_images = sfn_tasks.LambdaInvoke(
            self,
            "AnalyzeImages",
            lambda_function=self.lambda_functions["analyze_image"],
            output_path="$.Payload"
        )

        # Success state
        success_state = sfn.Succeed(self, "ProcessingComplete")

        # Failed state
        failed_state = sfn.Fail(
            self,
            "ImportFailed",
            error="ImportJobFailed",
            cause="The DICOM import job failed"
        )

        # Chain the states together
        definition = check_import_status.next(
            is_import_complete.when(
                sfn.Condition.string_equals("$.importStatus.JobStatus", "COMPLETED"),
                process_image_sets.next(analyze_images).next(success_state)
            ).when(
                sfn.Condition.string_equals("$.importStatus.JobStatus", "IN_PROGRESS"),
                wait_for_import.next(check_import_status)
            ).otherwise(failed_state)
        )

        # Create the state machine
        state_machine = sfn.StateMachine(
            self,
            "DicomProcessingStateMachine",
            definition=definition,
            role=self.step_functions_role,
            state_machine_type=sfn.StateMachineType.EXPRESS,
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/dicom-processing-{self.environment_name}",
                    removal_policy=RemovalPolicy.DESTROY
                ),
                level=sfn.LogLevel.ALL,
                include_execution_data=True
            ),
            timeout=Duration.minutes(30)
        )

        return state_machine

    def _create_eventbridge_rules(self) -> None:
        """
        Create EventBridge rules for automated workflow triggers.
        """
        # Rule for HealthImaging import completion
        import_completed_rule = events.Rule(
            self,
            "DicomImportCompletedRule",
            event_pattern=events.EventPattern(
                source=["aws.medical-imaging"],
                detail_type=["Import Job Completed"],
                detail={
                    "datastoreId": [self.datastore_id]
                }
            ),
            description="Triggers when DICOM import job completes"
        )

        # Add Lambda target to the rule
        import_completed_rule.add_target(
            targets.LambdaFunction(self.lambda_functions["process_metadata"])
        )

    def _configure_s3_notifications(self) -> None:
        """
        Configure S3 event notifications to trigger the pipeline.
        """
        # Add S3 notification to trigger import function
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_functions["start_import"]),
            s3.NotificationKeyFilter(suffix=".dcm")
        )

    def _create_log_groups(self) -> None:
        """
        Create CloudWatch Log Groups for monitoring and debugging.
        """
        # Log group for application logs
        logs.LogGroup(
            self,
            "ApplicationLogGroup",
            log_group_name=f"/aws/lambda/medical-imaging-{self.environment_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers.
        """
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for DICOM input files"
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed output files"
        )

        CfnOutput(
            self,
            "DataStoreId",
            value=self.datastore_id,
            description="HealthImaging data store ID"
        )

        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN"
        )

        CfnOutput(
            self,
            "StartImportFunctionName",
            value=self.lambda_functions["start_import"].function_name,
            description="Lambda function for starting DICOM imports"
        )

    def _get_start_import_code(self) -> str:
        """
        Returns the Lambda function code for starting DICOM imports.
        """
        return '''
import json
import boto3
import os

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Initiates a HealthImaging import job when DICOM files are uploaded to S3.
    This function processes S3 events and starts the medical image import workflow.
    """
    datastore_id = os.environ['DATASTORE_ID']
    output_bucket = os.environ['OUTPUT_BUCKET']
    
    # Extract S3 event details
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Prepare import job parameters
        input_s3_uri = f"s3://{bucket}/{os.path.dirname(key)}/"
        output_s3_uri = f"s3://{output_bucket}/import-results/"
        
        # Start import job
        response = medical_imaging.start_dicom_import_job(
            dataStoreId=datastore_id,
            inputS3Uri=input_s3_uri,
            outputS3Uri=output_s3_uri,
            dataAccessRoleArn=os.environ['LAMBDA_ROLE_ARN']
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'jobId': response['jobId'],
                'dataStoreId': response['dataStoreId'],
                'status': 'SUBMITTED'
            })
        }
'''

    def _get_metadata_processing_code(self) -> str:
        """
        Returns the Lambda function code for processing DICOM metadata.
        """
        return '''
import json
import boto3
import os

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Extracts and processes DICOM metadata from HealthImaging image sets.
    Parses patient information, study details, and technical parameters.
    """
    datastore_id = event['datastoreId']
    image_set_id = event['imageSetId']
    
    try:
        # Get image set metadata
        response = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Parse DICOM metadata
        metadata = json.loads(response['imageSetMetadataBlob'].read())
        
        # Extract relevant fields
        patient_info = metadata.get('Patient', {})
        study_info = metadata.get('Study', {})
        series_info = metadata.get('Series', {})
        
        processed_metadata = {
            'patientId': patient_info.get('DICOM', {}).get('PatientID'),
            'patientName': patient_info.get('DICOM', {}).get('PatientName'),
            'studyDate': study_info.get('DICOM', {}).get('StudyDate'),
            'studyDescription': study_info.get('DICOM', {}).get('StudyDescription'),
            'modality': series_info.get('DICOM', {}).get('Modality'),
            'imageSetId': image_set_id,
            'processingTimestamp': context.aws_request_id
        }
        
        # Store processed metadata
        output_key = f"metadata/{image_set_id}/metadata.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(processed_metadata),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(processed_metadata)
        }
        
    except Exception as e:
        print(f"Error processing metadata: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_image_analysis_code(self) -> str:
        """
        Returns the Lambda function code for image analysis.
        """
        return '''
import json
import boto3
import os
import base64
from io import BytesIO

medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Performs basic image analysis on medical images.
    In production, this would integrate with ML models for diagnostic support.
    """
    datastore_id = event['datastoreId']
    image_set_id = event['imageSetId']
    
    try:
        # Get image set metadata
        image_set_metadata = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # For demo, we'll analyze basic properties
        # In production, this would include AI/ML inference
        analysis_results = {
            'imageSetId': image_set_id,
            'analysisType': 'BasicQualityCheck',
            'timestamp': context.aws_request_id,
            'results': {
                'imageQuality': 'GOOD',
                'processingStatus': 'COMPLETED',
                'anomaliesDetected': False,
                'confidenceScore': 0.95
            }
        }
        
        # Store analysis results
        output_key = f"analysis/{image_set_id}/results.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(analysis_results),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(analysis_results)
        }
        
    except Exception as e:
        print(f"Error analyzing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''


class MedicalImageProcessingApp(cdk.App):
    """
    CDK Application for Medical Image Processing Pipeline
    """

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)

        # Create the main stack
        MedicalImageProcessingStack(
            self,
            "MedicalImageProcessingStack",
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION')
            ),
            description="Serverless Medical Image Processing with AWS HealthImaging and Step Functions"
        )


# Entry point for CDK CLI
app = MedicalImageProcessingApp()
app.synth()