#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as config from 'aws-cdk-lib/aws-config';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as logs from 'aws-cdk-lib/aws-logs';
import { NagSuppressions } from 'cdk-nag';
import { AwsSolutionsChecks } from 'cdk-nag';
import { Construct } from 'constructs';

/**
 * Stack for Policy Enforcement Automation with VPC Lattice and Config
 * 
 * This stack implements an automated policy enforcement system using AWS Config 
 * custom rules to monitor VPC Lattice service networks for compliance violations,
 * Lambda functions for intelligent evaluation and remediation logic, and SNS for
 * immediate notification workflows.
 */
export class PolicyEnforcementLatticeConfigStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC for VPC Lattice testing
    const vpc = new ec2.Vpc(this, 'ComplianceVpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for this use case
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Create S3 bucket for AWS Config
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `aws-config-bucket-${this.account}-${this.region}-${randomSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(365),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create SNS topic for compliance notifications
    const complianceTopic = new sns.Topic(this, 'ComplianceTopic', {
      topicName: `lattice-compliance-alerts-${randomSuffix}`,
      displayName: 'VPC Lattice Compliance Alerts',
    });

    // Add email subscription (can be customized during deployment)
    complianceTopic.addSubscription(
      new snsSubscriptions.EmailSubscription('admin@company.com')
    );

    // Create IAM role for AWS Config service
    const configServiceRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `ConfigServiceRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
      inlinePolicies: {
        ConfigS3DeliveryRolePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketAcl',
                's3:ListBucket',
              ],
              resources: [configBucket.bucketArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [`${configBucket.bucketArn}/AWSLogs/${this.account}/Config/*`],
              conditions: {
                StringEquals: {
                  's3:x-amz-acl': 'bucket-owner-full-control',
                },
              },
            }),
          ],
        }),
      },
    });

    // Grant Config service access to the S3 bucket
    configBucket.grantRead(configServiceRole);
    configBucket.grantPut(configServiceRole, 'AWSLogs/*');

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaComplianceRole', {
      roleName: `LatticeComplianceRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LatticeCompliancePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:*',
                'config:PutEvaluations',
                'config:StartConfigRulesEvaluation',
                'sns:Publish',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Groups for Lambda functions
    const evaluatorLogGroup = new logs.LogGroup(this, 'EvaluatorLogGroup', {
      logGroupName: `/aws/lambda/lattice-compliance-evaluator-${randomSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const remediationLogGroup = new logs.LogGroup(this, 'RemediationLogGroup', {
      logGroupName: `/aws/lambda/lattice-auto-remediation-${randomSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for compliance evaluation
    const complianceEvaluator = new lambda.Function(this, 'ComplianceEvaluator', {
      functionName: `lattice-compliance-evaluator-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      logGroup: evaluatorLogGroup,
      environment: {
        SNS_TOPIC_ARN: complianceTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Evaluate VPC Lattice resources for compliance."""
    
    config_client = boto3.client('config')
    lattice_client = boto3.client('vpc-lattice')
    sns_client = boto3.client('sns')
    
    # Parse Config rule invocation
    configuration_item = event['configurationItem']
    rule_parameters = json.loads(event.get('ruleParameters', '{}'))
    
    compliance_type = 'COMPLIANT'
    annotation = 'Resource is compliant with security policies'
    
    try:
        resource_type = configuration_item['resourceType']
        resource_id = configuration_item['resourceId']
        
        if resource_type == 'AWS::VpcLattice::ServiceNetwork':
            compliance_type, annotation = evaluate_service_network(
                lattice_client, resource_id, rule_parameters
            )
        elif resource_type == 'AWS::VpcLattice::Service':
            compliance_type, annotation = evaluate_service(
                lattice_client, resource_id, rule_parameters
            )
        
        # Send notification if non-compliant
        if compliance_type == 'NON_COMPLIANT':
            send_compliance_notification(sns_client, resource_id, annotation)
            
    except Exception as e:
        logger.error(f"Error evaluating compliance: {str(e)}")
        compliance_type = 'NOT_APPLICABLE'
        annotation = f"Error during evaluation: {str(e)}"
    
    # Return evaluation result to Config
    config_client.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_type,
                'Annotation': annotation,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Evaluation complete: {compliance_type}')
    }

def evaluate_service_network(client, network_id, parameters):
    """Evaluate service network compliance."""
    try:
        # Get service network details
        response = client.get_service_network(serviceNetworkIdentifier=network_id)
        network = response['serviceNetwork']
        
        # Check for auth policy requirement
        if parameters.get('requireAuthPolicy', 'true') == 'true':
            try:
                client.get_auth_policy(resourceIdentifier=network_id)
            except client.exceptions.ResourceNotFoundException:
                return 'NON_COMPLIANT', 'Service network missing required auth policy'
        
        # Check network name compliance
        if not network['name'].startswith(parameters.get('namePrefix', 'secure-')):
            return 'NON_COMPLIANT', f"Service network name must start with {parameters.get('namePrefix', 'secure-')}"
        
        return 'COMPLIANT', 'Service network meets all security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service network: {str(e)}"

def evaluate_service(client, service_id, parameters):
    """Evaluate service compliance."""
    try:
        response = client.get_service(serviceIdentifier=service_id)
        service = response['service']
        
        # Check auth type requirement
        if parameters.get('requireAuth', 'true') == 'true':
            if service.get('authType') == 'NONE':
                return 'NON_COMPLIANT', 'Service must have authentication enabled'
        
        return 'COMPLIANT', 'Service meets security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service: {str(e)}"

def send_compliance_notification(sns_client, resource_id, message):
    """Send SNS notification for compliance violations."""
    try:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='VPC Lattice Compliance Violation Detected',
            Message=f"""
Compliance violation detected:

Resource ID: {resource_id}
Issue: {message}
Timestamp: {datetime.utcnow().isoformat()}

Please review and remediate this resource immediately.
            """
        )
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
      `),
    });

    // Grant SNS publish permissions to compliance evaluator
    complianceTopic.grantPublish(complianceEvaluator);

    // Create Lambda function for automated remediation
    const autoRemediation = new lambda.Function(this, 'AutoRemediation', {
      functionName: `lattice-auto-remediation-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(120),
      memorySize: 256,
      logGroup: remediationLogGroup,
      environment: {
        CONFIG_RULE_NAME: `vpc-lattice-policy-compliance-${randomSuffix}`,
        AWS_ACCOUNT_ID: this.account,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Automatically remediate VPC Lattice compliance violations."""
    
    lattice_client = boto3.client('vpc-lattice')
    config_client = boto3.client('config')
    
    try:
        # Parse SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])
        resource_id = extract_resource_id(message)
        
        if not resource_id:
            logger.error("Unable to extract resource ID from message")
            return
        
        # Attempt remediation based on resource type
        if 'service-network' in resource_id:
            remediate_service_network(lattice_client, resource_id)
        elif 'service' in resource_id:
            remediate_service(lattice_client, resource_id)
        
        # Trigger Config re-evaluation
        config_client.start_config_rules_evaluation(
            ConfigRuleNames=[os.environ['CONFIG_RULE_NAME']]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Remediation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }

def extract_resource_id(message):
    """Extract resource ID from compliance message."""
    # Simple extraction logic - in production, use more robust parsing
    lines = message.split('\\n')
    for line in lines:
        if 'Resource ID:' in line:
            return line.split('Resource ID:')[1].strip()
    return None

def remediate_service_network(client, network_id):
    """Apply remediation to service network."""
    try:
        # Create basic auth policy if missing
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:*",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalAccount": os.environ['AWS_ACCOUNT_ID']
                        }
                    }
                }
            ]
        }
        
        client.put_auth_policy(
            resourceIdentifier=network_id,
            policy=json.dumps(auth_policy)
        )
        
        logger.info(f"Applied auth policy to service network: {network_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service network {network_id}: {str(e)}")

def remediate_service(client, service_id):
    """Apply remediation to service."""
    try:
        # Update service to require authentication
        client.update_service(
            serviceIdentifier=service_id,
            authType='AWS_IAM'
        )
        
        logger.info(f"Updated service authentication: {service_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service {service_id}: {str(e)}")
      `),
    });

    // Subscribe auto-remediation function to SNS topic
    complianceTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(autoRemediation)
    );

    // Create AWS Config delivery channel
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      s3BucketName: configBucket.bucketName,
      name: 'default',
    });

    // Create AWS Config configuration recorder
    const configurationRecorder = new config.CfnConfigurationRecorder(this, 'ConfigurationRecorder', {
      name: 'default',
      roleArn: configServiceRole.roleArn,
      recordingGroup: {
        allSupported: false,
        includeGlobalResourceTypes: false,
        resourceTypes: [
          'AWS::VpcLattice::ServiceNetwork',
          'AWS::VpcLattice::Service',
        ],
      },
    });

    // Ensure delivery channel is created before configuration recorder
    configurationRecorder.addDependency(deliveryChannel);

    // Create AWS Config rule for VPC Lattice compliance
    const configRule = new config.CfnConfigRule(this, 'VpcLatticeComplianceRule', {
      configRuleName: `vpc-lattice-policy-compliance-${randomSuffix}`,
      description: 'Evaluates VPC Lattice resources for compliance with security policies',
      source: {
        owner: 'AWS_LAMBDA',
        sourceIdentifier: complianceEvaluator.functionArn,
        sourceDetails: [
          {
            eventSource: 'aws.config',
            messageType: 'ConfigurationItemChangeNotification',
          },
          {
            eventSource: 'aws.config',
            messageType: 'OversizedConfigurationItemChangeNotification',
          },
        ],
      },
      inputParameters: JSON.stringify({
        requireAuthPolicy: 'true',
        namePrefix: 'secure-',
        requireAuth: 'true',
      }),
    });

    // Grant Config permission to invoke compliance evaluator Lambda
    complianceEvaluator.addPermission('AllowConfigInvoke', {
      principal: new iam.ServicePrincipal('config.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceAccount: this.account,
    });

    // Ensure Config rule is created after configuration recorder
    configRule.addDependency(configurationRecorder);

    // Create test VPC Lattice service network (non-compliant for testing)
    const testServiceNetwork = new vpclattice.CfnServiceNetwork(this, 'TestServiceNetwork', {
      name: `test-network-${randomSuffix}`,
      authType: 'AWS_IAM',
    });

    // Associate VPC with service network
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'ServiceNetworkVpcAssociation', {
      serviceNetworkIdentifier: testServiceNetwork.attrId,
      vpcIdentifier: vpc.vpcId,
    });

    // Create a test service (initially non-compliant)
    const testService = new vpclattice.CfnService(this, 'TestService', {
      name: `test-service-${randomSuffix}`,
      authType: 'NONE', // Non-compliant for testing
    });

    // CDK Nag suppressions
    NagSuppressions.addResourceSuppressions(
      lambdaRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'Lambda function requires broad VPC Lattice and Config permissions for compliance evaluation and remediation across multiple resources.',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      configServiceRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'AWS Config service role requires broad permissions to access S3 bucket for configuration history delivery.',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      complianceEvaluator,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'Using Python 3.12 which is the latest supported runtime version for Lambda.',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      autoRemediation,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'Using Python 3.12 which is the latest supported runtime version for Lambda.',
        },
      ]
    );

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID for VPC Lattice service network testing',
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: testServiceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
    });

    new cdk.CfnOutput(this, 'TestServiceId', {
      value: testService.attrId,
      description: 'Test VPC Lattice Service ID (initially non-compliant)',
    });

    new cdk.CfnOutput(this, 'ComplianceTopicArn', {
      value: complianceTopic.topicArn,
      description: 'SNS Topic ARN for compliance notifications',
    });

    new cdk.CfnOutput(this, 'ConfigRuleName', {
      value: configRule.configRuleName!,
      description: 'AWS Config Rule name for VPC Lattice compliance monitoring',
    });

    new cdk.CfnOutput(this, 'ComplianceEvaluatorFunction', {
      value: complianceEvaluator.functionName,
      description: 'Lambda function name for compliance evaluation',
    });

    new cdk.CfnOutput(this, 'AutoRemediationFunction', {
      value: autoRemediation.functionName,
      description: 'Lambda function name for automated remediation',
    });
  }
}

// Create CDK application
const app = new cdk.App();

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Create the stack
new PolicyEnforcementLatticeConfigStack(app, 'PolicyEnforcementLatticeConfigStack', {
  description: 'Policy Enforcement Automation with VPC Lattice and Config - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'policy-enforcement-lattice-config',
    Environment: 'development',
    CostCenter: 'security',
    Owner: 'compliance-team',
  },
});