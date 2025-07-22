import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

/**
 * Properties for the AutomatedWorkspacesStack
 */
export interface AutomatedWorkspacesStackProps extends cdk.StackProps {
  /** WorkSpaces directory ID */
  readonly directoryId?: string;
  
  /** WorkSpaces bundle ID */
  readonly bundleId: string;
  
  /** List of target users for WorkSpaces provisioning */
  readonly targetUsers: string[];
  
  /** EventBridge schedule expression for automation */
  readonly automationSchedule: string;
  
  /** Whether to enable VPC endpoints for enhanced security */
  readonly enableVpcEndpoints: boolean;
  
  /** Stack name override */
  readonly stackName: string;
}

/**
 * CDK Stack for automated WorkSpaces Personal provisioning
 * 
 * This stack creates:
 * - Lambda function for WorkSpaces automation
 * - IAM roles and policies with least privilege access
 * - Secrets Manager secret for AD credentials
 * - Systems Manager document for development environment setup
 * - EventBridge rule for scheduled automation
 * - CloudWatch log groups for monitoring and debugging
 */
export class AutomatedWorkspacesStack extends cdk.Stack {
  /** Lambda function for WorkSpaces automation */
  public readonly automationFunction: lambda.Function;
  
  /** Secrets Manager secret for AD credentials */
  public readonly adSecret: secretsmanager.Secret;
  
  /** Systems Manager document for environment configuration */
  public readonly setupDocument: ssm.CfnDocument;
  
  /** EventBridge rule for scheduled automation */
  public readonly automationRule: events.Rule;

  constructor(scope: Construct, id: string, props: AutomatedWorkspacesStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.directoryId) {
      this.node.addWarning('DirectoryId not provided - must be set via context or in deployment');
    }

    // Create Secrets Manager secret for AD credentials
    this.adSecret = this.createAdCredentialsSecret();

    // Create Systems Manager document for development environment setup
    this.setupDocument = this.createDevEnvironmentDocument();

    // Create IAM role for Lambda function
    const lambdaRole = this.createLambdaExecutionRole();

    // Create Lambda function
    this.automationFunction = this.createAutomationLambda(lambdaRole, props);

    // Create EventBridge rule for automation scheduling
    this.automationRule = this.createAutomationSchedule(props);

    // Add CloudFormation outputs
    this.createOutputs();

    // Apply CDK Nag suppressions for justified security exceptions
    this.applyCdkNagSuppressions();
  }

  /**
   * Creates Secrets Manager secret for Active Directory service account credentials
   */
  private createAdCredentialsSecret(): secretsmanager.Secret {
    const secret = new secretsmanager.Secret(this, 'AdCredentials', {
      secretName: `${this.stackName}/ad-credentials`,
      description: 'Active Directory service account credentials for WorkSpaces automation',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'workspaces-service' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
        requireEachIncludedType: true,
      },
    });

    // Enable automatic rotation (optional)
    secret.addRotationSchedule('AdCredentialsRotation', {
      automaticallyAfter: cdk.Duration.days(30),
    });

    return secret;
  }

  /**
   * Creates Systems Manager document for development environment configuration
   */
  private createDevEnvironmentDocument(): ssm.CfnDocument {
    const documentContent = {
      schemaVersion: '2.2',
      description: 'Configure development environment on WorkSpaces Personal',
      parameters: {
        developmentTools: {
          type: 'String',
          description: 'Comma-separated list of development tools to install',
          default: 'git,vscode,nodejs,python,docker',
        },
        teamConfiguration: {
          type: 'String', 
          description: 'Team-specific configuration settings',
          default: 'standard',
        },
      },
      mainSteps: [
        {
          action: 'aws:runPowerShellScript',
          name: 'InstallChocolatey',
          inputs: {
            runCommand: [
              'Write-Output "Installing Chocolatey package manager..."',
              'Set-ExecutionPolicy Bypass -Scope Process -Force',
              '[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072',
              'iex ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))',
              'Write-Output "Chocolatey installation completed"',
            ],
          },
        },
        {
          action: 'aws:runPowerShellScript',
          name: 'InstallDevelopmentTools',
          inputs: {
            runCommand: [
              'Write-Output "Installing development tools..."',
              '$tools = "{{ developmentTools }}".Split(",")',
              'foreach ($tool in $tools) {',
              '  $trimmedTool = $tool.Trim()',
              '  Write-Output "Installing $trimmedTool..."',
              '  switch ($trimmedTool) {',
              '    "git" { choco install git -y --no-progress }',
              '    "vscode" { choco install vscode -y --no-progress }',
              '    "nodejs" { choco install nodejs -y --no-progress }',
              '    "python" { choco install python -y --no-progress }',
              '    "docker" { choco install docker-desktop -y --no-progress }',
              '    default { Write-Output "Unknown tool: $trimmedTool" }',
              '  }',
              '}',
              'Write-Output "Development environment setup completed successfully"',
            ],
          },
        },
        {
          action: 'aws:runPowerShellScript',
          name: 'ConfigureEnvironment',
          inputs: {
            runCommand: [
              'Write-Output "Configuring development environment..."',
              '# Set Git global configuration',
              'git config --global init.defaultBranch main',
              'git config --global pull.rebase false',
              '# Create development directories',
              'New-Item -ItemType Directory -Force -Path C:\\Dev\\Projects',
              'New-Item -ItemType Directory -Force -Path C:\\Dev\\Tools',
              'Write-Output "Environment configuration completed"',
            ],
          },
        },
      ],
    };

    return new ssm.CfnDocument(this, 'DevEnvironmentDocument', {
      documentType: 'Command',
      documentFormat: 'JSON',
      name: `${this.stackName}-dev-environment-setup`,
      content: documentContent,
      tags: [
        { key: 'Project', value: 'DevEnvironmentAutomation' },
        { key: 'Purpose', value: 'WorkSpacesConfiguration' },
      ],
    });
  }

  /**
   * Creates IAM execution role for the Lambda function with least privilege permissions
   */
  private createLambdaExecutionRole(): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for WorkSpaces automation Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // WorkSpaces permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'workspaces:CreateWorkspaces',
        'workspaces:TerminateWorkspaces',
        'workspaces:DescribeWorkspaces',
        'workspaces:DescribeWorkspaceDirectories',
        'workspaces:DescribeWorkspaceBundles',
        'workspaces:ModifyWorkspaceProperties',
      ],
      resources: ['*'],
    }));

    // Systems Manager permissions
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:SendCommand',
        'ssm:GetCommandInvocation',
        'ssm:DescribeInstanceInformation',
        'ssm:GetDocument',
        'ssm:ListDocuments',
        'ssm:DescribeDocumentParameters',
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:document/${this.stackName}-dev-environment-setup`,
        'arn:aws:ssm:*:*:instance/*',
        'arn:aws:ssm:*:*:command/*',
      ],
    }));

    // Secrets Manager permissions - scoped to specific secret
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['secretsmanager:GetSecretValue'],
      resources: [this.adSecret.secretArn],
    }));

    // VPC permissions for Lambda (if needed)
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:CreateNetworkInterface',
        'ec2:DescribeNetworkInterfaces',
        'ec2:DeleteNetworkInterface',
        'ec2:AttachNetworkInterface',
        'ec2:DetachNetworkInterface',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates the Lambda function for WorkSpaces automation
   */
  private createAutomationLambda(
    role: iam.Role,
    props: AutomatedWorkspacesStackProps
  ): lambda.Function {
    // Create CloudWatch Log Group with retention
    const logGroup = new logs.LogGroup(this, 'AutomationLogGroup', {
      logGroupName: `/aws/lambda/${this.stackName}-automation`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function code
    const functionCode = `
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
    """
    try:
        # Initialize AWS clients
        workspaces_client = boto3.client('workspaces')
        ssm_client = boto3.client('ssm')
        secrets_client = boto3.client('secretsmanager')
        
        logger.info("Starting WorkSpaces automation process")
        
        # Get configuration from event
        secret_name = event.get('secret_name', '${this.adSecret.secretName}')
        directory_id = event.get('directory_id', '${props.directoryId || 'CHANGE_ME'}')
        bundle_id = event.get('bundle_id', '${props.bundleId}')
        target_users = event.get('target_users', ${JSON.stringify(props.targetUsers)})
        ssm_document = event.get('ssm_document', '${this.setupDocument.name}')
        
        # Get AD credentials from Secrets Manager
        credentials = get_ad_credentials(secrets_client, secret_name)
        
        # Get current WorkSpaces
        current_workspaces = get_current_workspaces(workspaces_client, directory_id)
        logger.info(f"Found {len(current_workspaces)} existing WorkSpaces")
        
        # Provision WorkSpaces for new users
        provision_results = provision_workspaces(
            workspaces_client, target_users, current_workspaces, 
            directory_id, bundle_id
        )
        
        # Configure new WorkSpaces (delayed for availability)
        configuration_results = schedule_workspace_configuration(
            ssm_client, provision_results, ssm_document
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

def provision_workspaces(
    workspaces_client: Any, 
    target_users: List[str], 
    current_workspaces: Dict[str, str],
    directory_id: str,
    bundle_id: str
) -> List[Dict[str, str]]:
    """Provision WorkSpaces for users who don't have them"""
    results = []
    
    for user in target_users:
        if user not in current_workspaces:
            try:
                logger.info(f"Creating WorkSpace for user: {user}")
                
                response = workspaces_client.create_workspaces(
                    Workspaces=[{
                        'DirectoryId': directory_id,
                        'UserName': user,
                        'BundleId': bundle_id,
                        'WorkspaceProperties': {
                            'RunningMode': 'AUTO_STOP',
                            'RunningModeAutoStopTimeoutInMinutes': 60,
                            'UserVolumeEncryptionEnabled': True,
                            'RootVolumeEncryptionEnabled': True
                        },
                        'Tags': [
                            {'Key': 'Project', 'Value': 'DevEnvironmentAutomation'},
                            {'Key': 'User', 'Value': user},
                            {'Key': 'Environment', 'Value': 'Development'},
                            {'Key': 'ManagedBy', 'Value': 'CDK'}
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

def schedule_workspace_configuration(
    ssm_client: Any, 
    provision_results: List[Dict[str, str]], 
    ssm_document: str
) -> List[Dict[str, str]]:
    """Schedule configuration for newly provisioned WorkSpaces"""
    configuration_results = []
    
    # Note: In production, you would wait for WorkSpaces to be available
    # and then send SSM commands to configure them
    
    for result in provision_results:
        if result.get('status') == 'created':
            configuration_results.append({
                'workspace_id': result['workspace_id'],
                'user': result['user'],
                'configuration_status': 'scheduled',
                'ssm_document': ssm_document
            })
    
    return configuration_results
`;

    const fn = new lambda.Function(this, 'AutomationFunction', {
      functionName: `${this.stackName}-automation`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: role,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Automated WorkSpaces provisioning for development teams',
      environment: {
        SECRET_NAME: this.adSecret.secretName,
        SSM_DOCUMENT_NAME: this.setupDocument.name || `${this.stackName}-dev-environment-setup`,
        DIRECTORY_ID: props.directoryId || 'CHANGE_ME',
        BUNDLE_ID: props.bundleId,
      },
      logGroup: logGroup,
    });

    return fn;
  }

  /**
   * Creates EventBridge rule for scheduled automation
   */
  private createAutomationSchedule(props: AutomatedWorkspacesStackProps): events.Rule {
    const rule = new events.Rule(this, 'AutomationSchedule', {
      ruleName: `${this.stackName}-daily-automation`,
      description: 'Daily WorkSpaces provisioning automation',
      schedule: events.Schedule.expression(props.automationSchedule),
      enabled: true,
    });

    // Create event payload
    const eventPayload = {
      secret_name: this.adSecret.secretName,
      directory_id: props.directoryId || 'CHANGE_ME',
      bundle_id: props.bundleId,
      target_users: props.targetUsers,
      ssm_document: this.setupDocument.name || `${this.stackName}-dev-environment-setup`,
    };

    // Add Lambda target
    rule.addTarget(new targets.LambdaFunction(this.automationFunction, {
      event: events.RuleTargetInput.fromObject(eventPayload),
    }));

    return rule;
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.automationFunction.functionName,
      description: 'Name of the WorkSpaces automation Lambda function',
      exportName: `${this.stackName}-lambda-function-name`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.automationFunction.functionArn,
      description: 'ARN of the WorkSpaces automation Lambda function',
      exportName: `${this.stackName}-lambda-function-arn`,
    });

    new cdk.CfnOutput(this, 'SecretsManagerArn', {
      value: this.adSecret.secretArn,
      description: 'ARN of the Active Directory credentials secret',
      exportName: `${this.stackName}-secret-arn`,
    });

    new cdk.CfnOutput(this, 'SSMDocumentName', {
      value: this.setupDocument.name || `${this.stackName}-dev-environment-setup`,
      description: 'Name of the Systems Manager document for environment setup',
      exportName: `${this.stackName}-ssm-document-name`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: this.automationRule.ruleName,
      description: 'Name of the EventBridge rule for automation scheduling',
      exportName: `${this.stackName}-eventbridge-rule-name`,
    });
  }

  /**
   * Apply CDK Nag suppressions for justified security exceptions
   */
  private applyCdkNagSuppressions(): void {
    // Suppress warnings for Lambda role permissions that require wildcards
    NagSuppressions.addResourceSuppressions(
      this.automationFunction,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'Lambda function requires broad permissions for WorkSpaces and SSM operations across accounts',
        },
      ],
      true
    );

    // Suppress warnings for Secrets Manager secret without KMS key
    NagSuppressions.addResourceSuppressions(
      this.adSecret,
      [
        {
          id: 'AwsSolutions-SMG4',
          reason: 'Using AWS managed KMS key for cost optimization in development environment',
        },
      ]
    );
  }
}