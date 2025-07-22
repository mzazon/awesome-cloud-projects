#!/usr/bin/env python3
"""
AWS CDK Application for Automated Development Environment Provisioning with WorkSpaces Personal

This CDK application creates an automated system that provisions standardized WorkSpaces Personal 
environments with pre-configured development tools, security policies, and team-specific software stacks.

The solution includes:
- Lambda function for orchestrating WorkSpaces provisioning
- Systems Manager document for development environment setup
- EventBridge rule for automated scheduling
- IAM roles and policies for secure operation
- Secrets Manager for storing AD credentials
"""

import os
import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_ssm as ssm,
    aws_secretsmanager as secretsmanager,
    aws_logs as logs
)


class WorkSpacesAutomationStack(Stack):
    """
    CDK Stack for WorkSpaces Personal automation infrastructure.
    
    This stack creates all the necessary AWS resources to automatically provision
    and configure development environments using WorkSpaces Personal.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters - these can be customized via CDK context or environment variables
        self.project_name = self.node.try_get_context("project_name") or "devenv-automation"
        self.directory_id = self.node.try_get_context("directory_id") or "d-906734e6b2"
        self.bundle_id = self.node.try_get_context("bundle_id") or "wsb-b0s22j3d7"
        
        # Create Secrets Manager secret for AD credentials
        self.ad_credentials_secret = self._create_ad_credentials_secret()
        
        # Create Systems Manager document for development environment setup
        self.dev_setup_document = self._create_ssm_document()
        
        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function for WorkSpaces automation
        self.automation_lambda = self._create_lambda_function()
        
        # Create EventBridge rule for scheduled automation
        self.automation_rule = self._create_eventbridge_rule()
        
        # Create CloudWatch Log Group for Lambda function
        self.log_group = self._create_log_group()

    def _create_ad_credentials_secret(self) -> secretsmanager.Secret:
        """
        Creates a Secrets Manager secret to store Active Directory service account credentials.
        
        Returns:
            secretsmanager.Secret: The created secret for AD credentials
        """
        secret = secretsmanager.Secret(
            self, "ADCredentialsSecret",
            secret_name=f"{self.project_name}-ad-credentials",
            description="Active Directory service account credentials for WorkSpaces automation",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "workspaces-service"}',
                generate_string_key="password",
                exclude_characters=' "%@/\\',
                password_length=32,
                require_each_included_type=True
            ),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Add tags for resource management
        cdk.Tags.of(secret).add("Project", self.project_name)
        cdk.Tags.of(secret).add("Purpose", "DevEnvironmentAutomation")
        
        return secret

    def _create_ssm_document(self) -> ssm.CfnDocument:
        """
        Creates a Systems Manager document for configuring development environments.
        
        Returns:
            ssm.CfnDocument: The SSM document for development environment setup
        """
        document_content = {
            "schemaVersion": "2.2",
            "description": "Configure development environment on WorkSpaces Personal",
            "parameters": {
                "developmentTools": {
                    "type": "String",
                    "description": "Comma-separated list of development tools to install",
                    "default": "git,vscode,nodejs,python,docker"
                },
                "teamConfiguration": {
                    "type": "String",
                    "description": "Team-specific configuration settings",
                    "default": "standard"
                }
            },
            "mainSteps": [
                {
                    "action": "aws:runPowerShellScript",
                    "name": "InstallChocolatey",
                    "inputs": {
                        "runCommand": [
                            "Write-Output 'Installing Chocolatey package manager...'",
                            "Set-ExecutionPolicy Bypass -Scope Process -Force",
                            "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072",
                            "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))",
                            "Write-Output 'Chocolatey installation completed'"
                        ]
                    }
                },
                {
                    "action": "aws:runPowerShellScript",
                    "name": "InstallDevelopmentTools",
                    "inputs": {
                        "runCommand": [
                            "Write-Output 'Installing development tools...'",
                            "$tools = '{{ developmentTools }}'.Split(',')",
                            "foreach ($tool in $tools) {",
                            "  $trimmedTool = $tool.Trim()",
                            "  Write-Output \"Installing $trimmedTool...\"",
                            "  switch ($trimmedTool) {",
                            "    'git' { choco install git -y --no-progress }",
                            "    'vscode' { choco install vscode -y --no-progress }",
                            "    'nodejs' { choco install nodejs -y --no-progress }",
                            "    'python' { choco install python -y --no-progress }",
                            "    'docker' { choco install docker-desktop -y --no-progress }",
                            "    default { Write-Output \"Unknown tool: $trimmedTool\" }",
                            "  }",
                            "}",
                            "Write-Output 'Development environment setup completed successfully'"
                        ]
                    }
                },
                {
                    "action": "aws:runPowerShellScript",
                    "name": "ConfigureEnvironment",
                    "inputs": {
                        "runCommand": [
                            "Write-Output 'Configuring development environment...'",
                            "# Set Git global configuration",
                            "git config --global init.defaultBranch main",
                            "git config --global pull.rebase false",
                            "# Create development directories",
                            "New-Item -ItemType Directory -Force -Path C:\\Dev\\Projects",
                            "New-Item -ItemType Directory -Force -Path C:\\Dev\\Tools",
                            "Write-Output 'Environment configuration completed'"
                        ]
                    }
                }
            ]
        }

        document = ssm.CfnDocument(
            self, "DevEnvironmentSetupDocument",
            document_type="Command",
            document_format="JSON",
            name=f"{self.project_name}-dev-setup",
            content=document_content,
            tags=[
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="Purpose", value="DevEnvironmentAutomation")
            ]
        )

        return document

    def _create_lambda_role(self) -> iam.Role:
        """
        Creates IAM role with necessary permissions for the Lambda function.
        
        Returns:
            iam.Role: The IAM role for Lambda function execution
        """
        # Create the Lambda execution role
        lambda_role = iam.Role(
            self, "WorkSpacesAutomationLambdaRole",
            role_name=f"{self.project_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Service role for WorkSpaces automation Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add WorkSpaces permissions
        workspaces_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "workspaces:CreateWorkspaces",
                "workspaces:TerminateWorkspaces", 
                "workspaces:DescribeWorkspaces",
                "workspaces:DescribeWorkspaceDirectories",
                "workspaces:DescribeWorkspaceBundles",
                "workspaces:ModifyWorkspaceProperties"
            ],
            resources=["*"]
        )

        # Add Systems Manager permissions
        ssm_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "ssm:DescribeInstanceInformation",
                "ssm:GetDocument",
                "ssm:ListDocuments",
                "ssm:DescribeDocumentParameters"
            ],
            resources=["*"]
        )

        # Add Secrets Manager permissions
        secrets_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["secretsmanager:GetSecretValue"],
            resources=[self.ad_credentials_secret.secret_arn]
        )

        # Add EC2 permissions for VPC Lambda (if needed)
        ec2_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces", 
                "ec2:DeleteNetworkInterface",
                "ec2:AttachNetworkInterface",
                "ec2:DetachNetworkInterface"
            ],
            resources=["*"]
        )

        # Attach policies to role
        lambda_role.add_to_policy(workspaces_policy)
        lambda_role.add_to_policy(ssm_policy)
        lambda_role.add_to_policy(secrets_policy)
        lambda_role.add_to_policy(ec2_policy)

        # Add tags
        cdk.Tags.of(lambda_role).add("Project", self.project_name)
        cdk.Tags.of(lambda_role).add("Purpose", "DevEnvironmentAutomation")

        return lambda_role

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Creates the Lambda function for WorkSpaces automation.
        
        Returns:
            _lambda.Function: The Lambda function for automation
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
import time
from botocore.exceptions import ClientError
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for WorkSpaces automation
    
    Args:
        event: Event data containing configuration parameters
        context: Lambda runtime information
        
    Returns:
        Response with status and results
    """
    try:
        # Initialize AWS clients
        workspaces_client = boto3.client('workspaces')
        ssm_client = boto3.client('ssm')
        secrets_client = boto3.client('secretsmanager')
        
        logger.info("Starting WorkSpaces automation process")
        
        # Validate required event parameters
        required_params = ['secret_name', 'directory_id', 'bundle_id']
        for param in required_params:
            if param not in event:
                raise ValueError(f"Missing required parameter: {param}")
        
        # Get AD credentials from Secrets Manager
        credentials = get_ad_credentials(secrets_client, event['secret_name'])
        
        # Get current WorkSpaces
        current_workspaces = get_current_workspaces(workspaces_client, event['directory_id'])
        logger.info(f"Found {len(current_workspaces)} existing WorkSpaces")
        
        # Get users who should have WorkSpaces (simplified for demo)
        target_users = get_target_users(event)
        logger.info(f"Target users: {target_users}")
        
        # Provision WorkSpaces for new users
        provision_results = provision_workspaces(
            workspaces_client, ssm_client, 
            target_users, current_workspaces, event
        )
        
        # Configure new WorkSpaces
        configuration_results = configure_workspaces(
            ssm_client, provision_results, event
        )
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'WorkSpaces provisioning completed successfully',
                'provisioned': provision_results,
                'configured': configuration_results,
                'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
            })
        }
        
        logger.info("WorkSpaces automation completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Error in WorkSpaces automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'WorkSpaces automation failed'
            })
        }

def get_ad_credentials(secrets_client: Any, secret_name: str) -> Dict[str, str]:
    """Retrieve AD credentials from Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except ClientError as e:
        logger.error(f"Failed to retrieve credentials: {e}")
        raise

def get_current_workspaces(workspaces_client: Any, directory_id: str) -> Dict[str, str]:
    """Get list of current WorkSpaces for the directory"""
    try:
        response = workspaces_client.describe_workspaces(
            DirectoryId=directory_id
        )
        return {
            ws['UserName']: ws['WorkspaceId'] 
            for ws in response['Workspaces']
            if ws['State'] in ['AVAILABLE', 'PENDING', 'STARTING', 'REBUILDING']
        }
    except ClientError as e:
        logger.error(f"Failed to describe WorkSpaces: {e}")
        return {}

def get_target_users(event: Dict[str, Any]) -> List[str]:
    """Get list of users who should have WorkSpaces"""
    # In production, this would query Active Directory
    # For demo purposes, using a static list from event or default
    return event.get('target_users', ['developer1', 'developer2', 'developer3'])

def provision_workspaces(
    workspaces_client: Any, 
    ssm_client: Any,
    target_users: List[str], 
    current_workspaces: Dict[str, str], 
    event: Dict[str, Any]
) -> List[Dict[str, str]]:
    """Provision WorkSpaces for users who don't have them"""
    results = []
    
    for user in target_users:
        if user not in current_workspaces:
            try:
                logger.info(f"Creating WorkSpace for user: {user}")
                
                response = workspaces_client.create_workspaces(
                    Workspaces=[{
                        'DirectoryId': event['directory_id'],
                        'UserName': user,
                        'BundleId': event['bundle_id'],
                        'WorkspaceProperties': {
                            'RunningMode': 'AUTO_STOP',
                            'RunningModeAutoStopTimeoutInMinutes': 60,
                            'UserVolumeEncryptionEnabled': True,
                            'RootVolumeEncryptionEnabled': True
                        },
                        'Tags': [
                            {'Key': 'Project', 'Value': 'DevEnvironmentAutomation'},
                            {'Key': 'User', 'Value': user},
                            {'Key': 'Environment', 'Value': 'Development'}
                        ]
                    }]
                )
                
                if response['PendingRequests']:
                    workspace_id = response['PendingRequests'][0]['WorkspaceId']
                    results.append({
                        'user': user,
                        'workspace_id': workspace_id,
                        'status': 'created'
                    })
                    logger.info(f"Successfully created WorkSpace {workspace_id} for {user}")
                
            except ClientError as e:
                logger.error(f"Failed to create WorkSpace for {user}: {e}")
                results.append({
                    'user': user,
                    'status': 'failed',
                    'error': str(e)
                })
        else:
            logger.info(f"User {user} already has WorkSpace: {current_workspaces[user]}")
    
    return results

def configure_workspaces(
    ssm_client: Any, 
    provision_results: List[Dict[str, str]], 
    event: Dict[str, Any]
) -> List[Dict[str, str]]:
    """Configure newly provisioned WorkSpaces"""
    configuration_results = []
    
    # Note: In production, you would wait for WorkSpaces to be available
    # and then send SSM commands to configure them
    
    for result in provision_results:
        if result.get('status') == 'created':
            configuration_results.append({
                'workspace_id': result['workspace_id'],
                'user': result['user'],
                'configuration_status': 'scheduled'
            })
    
    return configuration_results
        '''

        lambda_function = _lambda.Function(
            self, "WorkSpacesAutomationFunction",
            function_name=f"{self.project_name}-provisioner",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated WorkSpaces provisioning for development teams",
            environment={
                "SECRET_NAME": self.ad_credentials_secret.secret_name,
                "SSM_DOCUMENT_NAME": self.dev_setup_document.name,
                "DIRECTORY_ID": self.directory_id,
                "BUNDLE_ID": self.bundle_id
            }
        )

        # Add tags
        cdk.Tags.of(lambda_function).add("Project", self.project_name)
        cdk.Tags.of(lambda_function).add("Purpose", "DevEnvironmentAutomation")

        return lambda_function

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Creates an EventBridge rule for scheduled WorkSpaces automation.
        
        Returns:
            events.Rule: The EventBridge rule for automation scheduling
        """
        # Create EventBridge rule for daily automation
        automation_rule = events.Rule(
            self, "WorkSpacesAutomationRule",
            rule_name=f"{self.project_name}-daily-provisioning",
            description="Daily WorkSpaces provisioning automation",
            schedule=events.Schedule.rate(Duration.hours(24)),
            enabled=True
        )

        # Add Lambda target with event configuration
        target_input = {
            "secret_name": self.ad_credentials_secret.secret_name,
            "directory_id": self.directory_id,
            "bundle_id": self.bundle_id,
            "target_users": ["developer1", "developer2", "developer3"],
            "ssm_document": self.dev_setup_document.name
        }

        automation_rule.add_target(
            targets.LambdaFunction(
                self.automation_lambda,
                event=events.RuleTargetInput.from_object(target_input)
            )
        )

        # Add tags
        cdk.Tags.of(automation_rule).add("Project", self.project_name)
        cdk.Tags.of(automation_rule).add("Purpose", "DevEnvironmentAutomation")

        return automation_rule

    def _create_log_group(self) -> logs.LogGroup:
        """
        Creates a CloudWatch Log Group for the Lambda function.
        
        Returns:
            logs.LogGroup: The CloudWatch Log Group for Lambda logs
        """
        log_group = logs.LogGroup(
            self, "WorkSpacesAutomationLogGroup",
            log_group_name=f"/aws/lambda/{self.automation_lambda.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Add tags
        cdk.Tags.of(log_group).add("Project", self.project_name)
        cdk.Tags.of(log_group).add("Purpose", "DevEnvironmentAutomation")

        return log_group


app = cdk.App()

# Create the WorkSpaces automation stack
WorkSpacesAutomationStack(
    app, 
    "WorkSpacesAutomationStack",
    description="Automated Development Environment Provisioning with WorkSpaces Personal",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    )
)

app.synth()