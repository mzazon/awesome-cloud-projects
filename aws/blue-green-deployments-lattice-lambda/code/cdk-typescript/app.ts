#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the BlueGreenLatticeStack
 */
interface BlueGreenLatticeStackProps extends cdk.StackProps {
  /**
   * Initial traffic percentage for the green environment (0-100)
   * @default 10
   */
  initialGreenTrafficPercentage?: number;
  
  /**
   * The runtime for Lambda functions
   * @default Runtime.PYTHON_3_12
   */
  lambdaRuntime?: lambda.Runtime;
  
  /**
   * Memory size for Lambda functions in MB
   * @default 256
   */
  lambdaMemorySize?: number;
  
  /**
   * Timeout for Lambda functions in seconds
   * @default 30
   */
  lambdaTimeout?: number;
  
  /**
   * Environment prefix for resource naming
   * @default 'ecommerce-api'
   */
  environmentPrefix?: string;
}

/**
 * CDK Stack implementing blue-green deployments with VPC Lattice and Lambda
 * 
 * This stack creates:
 * - Two Lambda functions (blue and green environments)
 * - VPC Lattice service network and service
 * - Target groups for traffic routing
 * - CloudWatch monitoring and alarms
 * - IAM roles and policies with least privilege
 */
export class BlueGreenLatticeStack extends cdk.Stack {
  
  public readonly blueFunction: lambda.Function;
  public readonly greenFunction: lambda.Function;
  public readonly latticeService: vpclattice.CfnService;
  public readonly serviceEndpoint: string;
  
  constructor(scope: Construct, id: string, props: BlueGreenLatticeStackProps = {}) {
    super(scope, id, props);
    
    // Extract properties with defaults
    const {
      initialGreenTrafficPercentage = 10,
      lambdaRuntime = lambda.Runtime.PYTHON_3_12,
      lambdaMemorySize = 256,
      lambdaTimeout = 30,
      environmentPrefix = 'ecommerce-api'
    } = props;
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = this.generateUniqueSuffix();
    
    // Create IAM role for Lambda functions with least privilege
    const lambdaRole = this.createLambdaRole(uniqueSuffix);
    
    // Create Lambda functions for blue and green environments
    const { blueFunction, greenFunction } = this.createLambdaFunctions(
      lambdaRole,
      lambdaRuntime,
      lambdaMemorySize,
      lambdaTimeout,
      environmentPrefix,
      uniqueSuffix
    );
    
    this.blueFunction = blueFunction;
    this.greenFunction = greenFunction;
    
    // Create VPC Lattice service network
    const serviceNetwork = this.createServiceNetwork(environmentPrefix, uniqueSuffix);
    
    // Create target groups for blue and green environments
    const { blueTargetGroup, greenTargetGroup } = this.createTargetGroups(
      blueFunction,
      greenFunction,
      uniqueSuffix
    );
    
    // Create VPC Lattice service with weighted routing
    const latticeService = this.createLatticeService(
      serviceNetwork,
      blueTargetGroup,
      greenTargetGroup,
      initialGreenTrafficPercentage,
      environmentPrefix,
      uniqueSuffix
    );
    
    this.latticeService = latticeService;
    this.serviceEndpoint = latticeService.attrDnsEntryDomainName;
    
    // Create CloudWatch monitoring and alarms
    this.createMonitoring(greenFunction, uniqueSuffix);
    
    // Output important values
    this.createOutputs(blueFunction, greenFunction, latticeService);
    
    // Apply tags to all resources
    this.applyTags();
  }
  
  /**
   * Generate a unique suffix for resource naming
   */
  private generateUniqueSuffix(): string {
    // Use the stack's unique ID suffix for deterministic naming
    return this.node.addr.substring(0, 6).toLowerCase();
  }
  
  /**
   * Create IAM role for Lambda functions with minimal required permissions
   */
  private createLambdaRole(uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'LambdaVPCLatticeRole', {
      roleName: `LambdaVPCLatticeRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda functions in blue-green deployment with VPC Lattice',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });
    
    // Add custom policy for CloudWatch metrics (if needed for custom metrics)
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData'
      ],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'cloudwatch:namespace': 'AWS/Lambda'
        }
      }
    }));
    
    return role;
  }
  
  /**
   * Create Lambda functions for blue and green environments
   */
  private createLambdaFunctions(
    role: iam.Role,
    runtime: lambda.Runtime,
    memorySize: number,
    timeout: number,
    environmentPrefix: string,
    uniqueSuffix: string
  ): { blueFunction: lambda.Function; greenFunction: lambda.Function } {
    
    // Blue environment Lambda function (stable production version)
    const blueFunction = new lambda.Function(this, 'BlueFunction', {
      functionName: `${environmentPrefix}-blue-${uniqueSuffix}`,
      runtime: runtime,
      handler: 'index.lambda_handler',
      role: role,
      code: lambda.Code.fromInline(`
import json
import time

def lambda_handler(event, context):
    """
    Blue environment - stable production version
    Handles requests with consistent, reliable functionality
    """
    response_data = {
        'environment': 'blue',
        'version': '1.0.0',
        'message': 'Hello from Blue Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id,
        'function_name': context.function_name
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'blue',
            'X-Version': '1.0.0'
        },
        'body': json.dumps(response_data)
    }
      `),
      timeout: cdk.Duration.seconds(timeout),
      memorySize: memorySize,
      environment: {
        'ENVIRONMENT': 'blue',
        'VERSION': '1.0.0'
      },
      description: 'Blue environment Lambda function for stable production traffic',
      logRetention: logs.RetentionDays.ONE_WEEK,
      reservedConcurrentExecutions: 100 // Prevent runaway costs
    });
    
    // Green environment Lambda function (new version being deployed)
    const greenFunction = new lambda.Function(this, 'GreenFunction', {
      functionName: `${environmentPrefix}-green-${uniqueSuffix}`,
      runtime: runtime,
      handler: 'index.lambda_handler',
      role: role,
      code: lambda.Code.fromInline(`
import json
import time

def lambda_handler(event, context):
    """
    Green environment - new version being deployed
    Includes new features and enhancements for testing
    """
    response_data = {
        'environment': 'green',
        'version': '2.0.0',
        'message': 'Hello from Green Environment!',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id,
        'function_name': context.function_name,
        'new_feature': 'Enhanced response with additional metadata',
        'deployment_timestamp': int(time.time())
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Environment': 'green',
            'X-Version': '2.0.0'
        },
        'body': json.dumps(response_data)
    }
      `),
      timeout: cdk.Duration.seconds(timeout),
      memorySize: memorySize,
      environment: {
        'ENVIRONMENT': 'green',
        'VERSION': '2.0.0'
      },
      description: 'Green environment Lambda function for new version deployment',
      logRetention: logs.RetentionDays.ONE_WEEK,
      reservedConcurrentExecutions: 100 // Prevent runaway costs
    });
    
    return { blueFunction, greenFunction };
  }
  
  /**
   * Create VPC Lattice service network
   */
  private createServiceNetwork(environmentPrefix: string, uniqueSuffix: string): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `${environmentPrefix}-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: 'production' },
        { key: 'Purpose', value: 'blue-green-deployment' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    return serviceNetwork;
  }
  
  /**
   * Create target groups for blue and green Lambda functions
   */
  private createTargetGroups(
    blueFunction: lambda.Function,
    greenFunction: lambda.Function,
    uniqueSuffix: string
  ): { blueTargetGroup: vpclattice.CfnTargetGroup; greenTargetGroup: vpclattice.CfnTargetGroup } {
    
    // Blue target group
    const blueTargetGroup = new vpclattice.CfnTargetGroup(this, 'BlueTargetGroup', {
      name: `blue-tg-${uniqueSuffix}`,
      type: 'LAMBDA',
      targets: [
        {
          id: blueFunction.functionArn
        }
      ],
      tags: [
        { key: 'Environment', value: 'blue' },
        { key: 'Purpose', value: 'target-group' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    // Green target group
    const greenTargetGroup = new vpclattice.CfnTargetGroup(this, 'GreenTargetGroup', {
      name: `green-tg-${uniqueSuffix}`,
      type: 'LAMBDA',
      targets: [
        {
          id: greenFunction.functionArn
        }
      ],
      tags: [
        { key: 'Environment', value: 'green' },
        { key: 'Purpose', value: 'target-group' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    // Grant VPC Lattice permission to invoke Lambda functions
    blueFunction.addPermission('VPCLatticeBlueInvoke', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      sourceArn: blueTargetGroup.attrArn
    });
    
    greenFunction.addPermission('VPCLatticeGreenInvoke', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      sourceArn: greenTargetGroup.attrArn
    });
    
    return { blueTargetGroup, greenTargetGroup };
  }
  
  /**
   * Create VPC Lattice service with weighted routing
   */
  private createLatticeService(
    serviceNetwork: vpclattice.CfnServiceNetwork,
    blueTargetGroup: vpclattice.CfnTargetGroup,
    greenTargetGroup: vpclattice.CfnTargetGroup,
    greenTrafficPercentage: number,
    environmentPrefix: string,
    uniqueSuffix: string
  ): vpclattice.CfnService {
    
    const blueTrafficPercentage = 100 - greenTrafficPercentage;
    
    // Create VPC Lattice service
    const latticeService = new vpclattice.CfnService(this, 'LatticeService', {
      name: `lattice-service-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: 'production' },
        { key: 'Purpose', value: 'blue-green-service' },
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    // Associate service with service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceNetworkAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      serviceIdentifier: latticeService.attrId,
      tags: [
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    // Create HTTP listener with weighted routing
    new vpclattice.CfnListener(this, 'HttpListener', {
      serviceIdentifier: latticeService.attrId,
      name: 'http-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: blueTargetGroup.attrId,
              weight: blueTrafficPercentage
            },
            {
              targetGroupIdentifier: greenTargetGroup.attrId,
              weight: greenTrafficPercentage
            }
          ]
        }
      },
      tags: [
        { key: 'ManagedBy', value: 'CDK' }
      ]
    });
    
    return latticeService;
  }
  
  /**
   * Create CloudWatch monitoring and alarms for the green environment
   */
  private createMonitoring(greenFunction: lambda.Function, uniqueSuffix: string): void {
    
    // Error rate alarm for green environment
    const errorAlarm = new cloudwatch.Alarm(this, 'GreenErrorRateAlarm', {
      alarmName: `${greenFunction.functionName}-ErrorRate`,
      alarmDescription: 'Monitor error rate for green environment Lambda function',
      metric: greenFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    
    // Duration alarm for green environment
    const durationAlarm = new cloudwatch.Alarm(this, 'GreenDurationAlarm', {
      alarmName: `${greenFunction.functionName}-Duration`,
      alarmDescription: 'Monitor average duration for green environment Lambda function',
      metric: greenFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average'
      }),
      threshold: 10000, // 10 seconds in milliseconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    
    // Create a composite alarm for overall green environment health
    new cloudwatch.CompositeAlarm(this, 'GreenEnvironmentHealthAlarm', {
      alarmName: `${greenFunction.functionName}-OverallHealth`,
      alarmDescription: 'Composite alarm for overall green environment health',
      compositeAlarmRule: cloudwatch.AlarmRule.anyOf(
        cloudwatch.AlarmRule.fromAlarm(errorAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(durationAlarm, cloudwatch.AlarmState.ALARM)
      )
    });
  }
  
  /**
   * Create CloudFormation outputs for important resources
   */
  private createOutputs(
    blueFunction: lambda.Function,
    greenFunction: lambda.Function,
    latticeService: vpclattice.CfnService
  ): void {
    
    new cdk.CfnOutput(this, 'BlueFunctionName', {
      value: blueFunction.functionName,
      description: 'Name of the blue environment Lambda function',
      exportName: `${this.stackName}-BlueFunctionName`
    });
    
    new cdk.CfnOutput(this, 'GreenFunctionName', {
      value: greenFunction.functionName,
      description: 'Name of the green environment Lambda function',
      exportName: `${this.stackName}-GreenFunctionName`
    });
    
    new cdk.CfnOutput(this, 'BlueFunctionArn', {
      value: blueFunction.functionArn,
      description: 'ARN of the blue environment Lambda function'
    });
    
    new cdk.CfnOutput(this, 'GreenFunctionArn', {
      value: greenFunction.functionArn,
      description: 'ARN of the green environment Lambda function'
    });
    
    new cdk.CfnOutput(this, 'LatticeServiceId', {
      value: latticeService.attrId,
      description: 'ID of the VPC Lattice service',
      exportName: `${this.stackName}-LatticeServiceId`
    });
    
    new cdk.CfnOutput(this, 'LatticeServiceArn', {
      value: latticeService.attrArn,
      description: 'ARN of the VPC Lattice service'
    });
    
    new cdk.CfnOutput(this, 'ServiceEndpoint', {
      value: latticeService.attrDnsEntryDomainName,
      description: 'DNS endpoint for the VPC Lattice service',
      exportName: `${this.stackName}-ServiceEndpoint`
    });
    
    new cdk.CfnOutput(this, 'ServiceUrl', {
      value: `https://${latticeService.attrDnsEntryDomainName}`,
      description: 'HTTPS URL for testing the service'
    });
  }
  
  /**
   * Apply consistent tags to all resources in the stack
   */
  private applyTags(): void {
    cdk.Tags.of(this).add('Project', 'BlueGreenDeployment');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Owner', 'DevOps-Team');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

// Create the main stack
new BlueGreenLatticeStack(app, 'BlueGreenLatticeStack', {
  env: {
    account: account,
    region: region
  },
  description: 'Blue-green deployments with VPC Lattice and Lambda functions',
  
  // Configuration options
  initialGreenTrafficPercentage: app.node.tryGetContext('greenTrafficPercentage') || 10,
  lambdaMemorySize: app.node.tryGetContext('lambdaMemorySize') || 256,
  lambdaTimeout: app.node.tryGetContext('lambdaTimeout') || 30,
  environmentPrefix: app.node.tryGetContext('environmentPrefix') || 'ecommerce-api',
  
  // Stack-level tags
  tags: {
    'Project': 'BlueGreenDeployment',
    'Environment': 'Production',
    'CostCenter': 'Engineering',
    'ManagedBy': 'CDK'
  }
});

// Synthesize the app
app.synth();