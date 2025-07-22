#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as globalaccelerator from 'aws-cdk-lib/aws-globalaccelerator';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Configuration interface for the multi-region application
 */
interface MultiRegionConfig {
  readonly tableName: string;
  readonly appName: string;
  readonly primaryRegion: string;
  readonly secondaryRegions: string[];
  readonly enableGlobalAccelerator: boolean;
}

/**
 * Regional stack for Lambda function, ALB, and DynamoDB table
 */
class RegionalApplicationStack extends cdk.Stack {
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly lambdaFunction: lambda.Function;
  public readonly dynamoTable: dynamodb.Table;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    config: MultiRegionConfig;
    isPrimary: boolean;
    lambdaRole: iam.Role;
  }) {
    super(scope, id, props);

    const { config, isPrimary, lambdaRole } = props;

    // Create DynamoDB table with streams enabled for Global Tables
    this.dynamoTable = new dynamodb.Table(this, 'GlobalUserDataTable', {
      tableName: config.tableName,
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'timestamp', type: dynamodb.AttributeType.NUMBER },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      timeToLiveAttribute: 'ttl', // Optional TTL for data lifecycle management
    });

    // Add Global Secondary Index for querying by region
    this.dynamoTable.addGlobalSecondaryIndex({
      indexName: 'RegionIndex',
      partitionKey: { name: 'created_region', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'last_updated', type: dynamodb.AttributeType.NUMBER },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // Create CloudWatch Log Group for Lambda
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${config.appName}-${this.region}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function code
    const lambdaCode = `
import json
import boto3
import time
import os
from decimal import Decimal

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Multi-region active-active application handler
    Supports CRUD operations with automatic regional optimization
    """
    
    try:
        # Get HTTP method and path
        method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        # Parse request body for POST/PUT requests
        body = {}
        if event.get('body'):
            body = json.loads(event['body'])
        
        # Get AWS region from context
        region = context.invoked_function_arn.split(':')[3]
        
        # Route based on HTTP method and path
        if method == 'GET' and path == '/health':
            return health_check(region)
        elif method == 'GET' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return get_user_data(user_id, region)
        elif method == 'POST' and path == '/user':
            return create_user_data(body, region)
        elif method == 'PUT' and path.startswith('/user/'):
            user_id = path.split('/')[-1]
            return update_user_data(user_id, body, region)
        elif method == 'GET' and path == '/users':
            return list_users(region)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e), 'region': region})
        }

def health_check(region):
    """Health check endpoint for load balancer"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'region': region,
            'timestamp': int(time.time())
        })
    }

def get_user_data(user_id, region):
    """Get user data with regional context"""
    try:
        # Get latest record for user
        response = table.query(
            KeyConditionExpression='userId = :userId',
            ExpressionAttributeValues={':userId': user_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        if response['Items']:
            item = response['Items'][0]
            # Convert Decimal to float for JSON serialization
            item = json.loads(json.dumps(item, default=decimal_default))
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user': item,
                    'served_from_region': region
                })
            }
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'User not found'})
            }
            
    except Exception as e:
        raise Exception(f"Error getting user data: {str(e)}")

def create_user_data(body, region):
    """Create new user data with regional tracking"""
    try:
        user_id = body.get('userId')
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'userId is required'})
            }
        
        timestamp = int(time.time() * 1000)  # milliseconds for better precision
        
        item = {
            'userId': user_id,
            'timestamp': timestamp,
            'data': body.get('data', {}),
            'created_region': region,
            'last_updated': timestamp,
            'version': 1,
            'ttl': int(time.time()) + (365 * 24 * 60 * 60)  # 1 year TTL
        }
        
        table.put_item(Item=item)
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User created successfully',
                'userId': user_id,
                'created_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error creating user data: {str(e)}")

def update_user_data(user_id, body, region):
    """Update user data with conflict resolution"""
    try:
        timestamp = int(time.time() * 1000)
        
        # Use atomic update with version control
        response = table.update_item(
            Key={'userId': user_id, 'timestamp': timestamp},
            UpdateExpression='SET #data = :data, last_updated = :timestamp, updated_region = :region ADD version :inc',
            ExpressionAttributeNames={'#data': 'data'},
            ExpressionAttributeValues={
                ':data': body.get('data', {}),
                ':timestamp': timestamp,
                ':region': region,
                ':inc': 1
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'User updated successfully',
                'userId': user_id,
                'updated_in_region': region,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        raise Exception(f"Error updating user data: {str(e)}")

def list_users(region):
    """List users with pagination support"""
    try:
        # Simple scan with limit (in production, use GSI for better performance)
        response = table.scan(Limit=20)
        
        users = []
        processed_users = set()
        
        for item in response['Items']:
            user_id = item['userId']
            if user_id not in processed_users:
                users.append({
                    'userId': user_id,
                    'last_updated': int(item['last_updated']),
                    'version': int(item.get('version', 1))
                })
                processed_users.add(user_id)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'users': users,
                'count': len(users),
                'served_from_region': region
            })
        }
        
    except Exception as e:
        raise Exception(f"Error listing users: {str(e)}")

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
`;

    // Create Lambda function
    this.lambdaFunction = new lambda.Function(this, 'GlobalAppFunction', {
      functionName: `${config.appName}-${this.region}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        TABLE_NAME: this.dynamoTable.tableName,
        REGION: this.region,
      },
      logGroup: logGroup,
      description: `Multi-region active-active application function for ${this.region}`,
      retryAttempts: 0, // Disable automatic retries for ALB integration
    });

    // Create Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      loadBalancerName: `${config.appName}-${this.region}-alb`,
      vpc,
      internetFacing: true,
      securityGroup: this.createALBSecurityGroup(vpc),
    });

    // Create Target Group for Lambda
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'LambdaTargetGroup', {
      targetGroupName: `${config.appName}-${this.region}-tg`,
      targetType: elbv2.TargetType.LAMBDA,
      targets: [new targets.LambdaTarget(this.lambdaFunction)],
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 3,
        unhealthyThresholdCount: 3,
      },
    });

    // Create ALB Listener
    this.loadBalancer.addListener('HTTPListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [this.targetGroup],
    });

    // Grant Lambda permission to be invoked by ALB
    this.lambdaFunction.addPermission('ALBInvokePermission', {
      principal: new iam.ServicePrincipal('elasticloadbalancing.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: this.targetGroup.targetGroupArn,
    });

    // Outputs
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `${this.stackName}-LoadBalancerDNS`,
    });

    new cdk.CfnOutput(this, 'DynamoTableName', {
      value: this.dynamoTable.tableName,
      description: 'DynamoDB table name',
      exportName: `${this.stackName}-DynamoTableName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerArn', {
      value: this.loadBalancer.loadBalancerArn,
      description: 'Application Load Balancer ARN for Global Accelerator',
      exportName: `${this.stackName}-LoadBalancerArn`,
    });
  }

  /**
   * Create security group for Application Load Balancer
   */
  private createALBSecurityGroup(vpc: ec2.IVpc): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from anywhere'
    );

    // Allow HTTPS traffic from anywhere (for future SSL termination)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from anywhere'
    );

    return securityGroup;
  }
}

/**
 * Global Accelerator stack for managing cross-region traffic
 */
class GlobalAcceleratorStack extends cdk.Stack {
  public readonly accelerator: globalaccelerator.Accelerator;
  public readonly listener: globalaccelerator.Listener;

  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    config: MultiRegionConfig;
    regionalStacks: RegionalApplicationStack[];
  }) {
    super(scope, id, props);

    const { config, regionalStacks } = props;

    if (!config.enableGlobalAccelerator) {
      return;
    }

    // Create Global Accelerator
    this.accelerator = new globalaccelerator.Accelerator(this, 'GlobalAccelerator', {
      acceleratorName: `${config.appName}-accelerator`,
      enabled: true,
      ipAddressType: globalaccelerator.IpAddressType.IPV4,
    });

    // Create Listener
    this.listener = this.accelerator.addListener('HTTPListener', {
      listenerName: 'HTTPListener',
      protocol: globalaccelerator.Protocol.TCP,
      portRanges: [{ fromPort: 80, toPort: 80 }],
    });

    // Add regional endpoints
    regionalStacks.forEach((regionalStack, index) => {
      const isPrimary = index === 0;
      
      this.listener.addEndpointGroup(`EndpointGroup${regionalStack.region}`, {
        endpointGroupName: `${config.appName}-${regionalStack.region}-eg`,
        region: regionalStack.region,
        endpoints: [
          {
            endpointId: regionalStack.loadBalancer.loadBalancerArn,
            weight: 100,
            clientIpPreservationEnabled: false,
          },
        ],
        trafficDialPercentage: 100,
        healthCheckIntervalSeconds: 30,
        healthyThresholdCount: 3,
        unhealthyThresholdCount: 3,
      });
    });

    // Outputs
    new cdk.CfnOutput(this, 'GlobalAcceleratorDNS', {
      value: this.accelerator.dnsName,
      description: 'Global Accelerator DNS name',
    });

    new cdk.CfnOutput(this, 'GlobalAcceleratorStaticIPs', {
      value: cdk.Fn.join(', ', this.accelerator.ipAddresses),
      description: 'Global Accelerator static IP addresses',
    });
  }
}

/**
 * IAM stack for cross-region Lambda execution role
 */
class IAMStack extends cdk.Stack {
  public readonly lambdaRole: iam.Role;

  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    config: MultiRegionConfig;
  }) {
    super(scope, id, props);

    const { config } = props;

    // Create Lambda execution role with DynamoDB permissions
    this.lambdaRole = new iam.Role(this, 'GlobalAppLambdaRole', {
      roleName: `${config.appName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for multi-region Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add DynamoDB permissions for all regions
    this.lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem',
        'dynamodb:Query',
        'dynamodb:Scan',
        'dynamodb:BatchGetItem',
        'dynamodb:BatchWriteItem',
      ],
      resources: [
        `arn:aws:dynamodb:*:${this.account}:table/${config.tableName}`,
        `arn:aws:dynamodb:*:${this.account}:table/${config.tableName}/*`,
      ],
    }));

    // Add CloudWatch Logs permissions
    this.lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: [
        `arn:aws:logs:*:${this.account}:log-group:/aws/lambda/${config.appName}-*`,
        `arn:aws:logs:*:${this.account}:log-group:/aws/lambda/${config.appName}-*:*`,
      ],
    }));

    // Output
    new cdk.CfnOutput(this, 'LambdaRoleArn', {
      value: this.lambdaRole.roleArn,
      description: 'Lambda execution role ARN',
      exportName: `${this.stackName}-LambdaRoleArn`,
    });
  }
}

/**
 * Main CDK Application
 */
class MultiRegionActiveActiveApp extends cdk.App {
  constructor() {
    super();

    // Configuration
    const config: MultiRegionConfig = {
      tableName: this.node.tryGetContext('tableName') || 'GlobalUserData',
      appName: this.node.tryGetContext('appName') || 'global-app',
      primaryRegion: this.node.tryGetContext('primaryRegion') || 'us-east-1',
      secondaryRegions: this.node.tryGetContext('secondaryRegions') || ['eu-west-1', 'ap-southeast-1'],
      enableGlobalAccelerator: this.node.tryGetContext('enableGlobalAccelerator') ?? true,
    };

    const account = this.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
    const allRegions = [config.primaryRegion, ...config.secondaryRegions];

    // Create IAM stack in primary region
    const iamStack = new IAMStack(this, 'MultiRegionActiveActiveIAM', {
      env: { account, region: config.primaryRegion },
      config,
      description: 'IAM resources for multi-region active-active application',
    });

    // Create regional application stacks
    const regionalStacks: RegionalApplicationStack[] = [];

    allRegions.forEach((region, index) => {
      const isPrimary = index === 0;
      const stackName = isPrimary ? 'MultiRegionActiveActivePrimary' : `MultiRegionActiveActiveSecondary${index}`;
      
      const regionalStack = new RegionalApplicationStack(this, stackName, {
        env: { account, region },
        config,
        isPrimary,
        lambdaRole: iamStack.lambdaRole,
        description: `Regional application stack for ${region}`,
        stackName: `${config.appName}-${region}`,
      });

      // Add dependency on IAM stack
      regionalStack.addDependency(iamStack);

      regionalStacks.push(regionalStack);
    });

    // Create Global Accelerator stack (must be in us-west-2)
    if (config.enableGlobalAccelerator) {
      const globalAcceleratorStack = new GlobalAcceleratorStack(this, 'MultiRegionActiveActiveGlobalAccelerator', {
        env: { account, region: 'us-west-2' },
        config,
        regionalStacks,
        description: 'Global Accelerator for multi-region active-active application',
      });

      // Add dependencies on all regional stacks
      regionalStacks.forEach(stack => globalAcceleratorStack.addDependency(stack));
    }

    // Add tags to all stacks
    cdk.Tags.of(this).add('Project', 'MultiRegionActiveActive');
    cdk.Tags.of(this).add('Environment', this.node.tryGetContext('environment') || 'dev');
    cdk.Tags.of(this).add('Owner', this.node.tryGetContext('owner') || 'aws-recipes');
  }
}

// Instantiate the app
new MultiRegionActiveActiveApp();