#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

/**
 * Properties for the MicroserviceAuthorizationStack
 */
interface MicroserviceAuthorizationStackProps extends cdk.StackProps {
  /** Unique suffix for resource names to avoid conflicts */
  readonly resourceSuffix?: string;
  /** Environment prefix for resource tagging */
  readonly environment?: string;
}

/**
 * CDK Stack implementing microservice authorization with VPC Lattice and IAM
 * 
 * This stack creates a zero-trust networking architecture using VPC Lattice
 * for service-to-service communication with fine-grained IAM-based authorization.
 * 
 * Components:
 * - IAM roles for microservice identity
 * - VPC Lattice service network with IAM authentication
 * - Lambda functions representing microservices
 * - VPC Lattice service and target group
 * - Fine-grained authorization policies
 * - CloudWatch monitoring and access logging
 */
class MicroserviceAuthorizationStack extends cdk.Stack {
  public readonly serviceNetworkId: string;
  public readonly serviceId: string;
  public readonly productServiceRole: iam.Role;
  public readonly orderServiceRole: iam.Role;

  constructor(scope: Construct, id: string, props: MicroserviceAuthorizationStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const suffix = props.resourceSuffix || Math.random().toString(36).substring(2, 8);
    const environment = props.environment || 'demo';

    // Common tags for all resources
    const commonTags = {
      Environment: environment,
      Purpose: 'MicroserviceAuth',
      Stack: this.stackName,
      CreatedBy: 'CDK'
    };

    // Apply tags to stack
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Create IAM roles for microservice identity management
    const { productServiceRole, orderServiceRole } = this.createServiceRoles(suffix);
    this.productServiceRole = productServiceRole;
    this.orderServiceRole = orderServiceRole;

    // Create VPC Lattice service network with IAM authentication
    const serviceNetwork = this.createServiceNetwork(suffix);
    this.serviceNetworkId = serviceNetwork.ref;

    // Create Lambda functions representing microservices
    const { productServiceFunction, orderServiceFunction } = this.createLambdaFunctions(
      suffix,
      productServiceRole,
      orderServiceRole
    );

    // Create VPC Lattice service and target group
    const { service, targetGroup } = this.createVpcLatticeService(suffix, orderServiceFunction);
    this.serviceId = service.ref;

    // Associate service with service network
    this.createServiceNetworkAssociation(serviceNetwork, service);

    // Create fine-grained authorization policy
    this.createAuthorizationPolicy(service, productServiceRole);

    // Enable CloudWatch monitoring and access logging
    this.createMonitoring(serviceNetwork, suffix);

    // Grant Lambda permission for VPC Lattice invocation
    this.configureVpcLatticePermissions(orderServiceFunction, productServiceRole, service);

    // Create stack outputs
    this.createOutputs(serviceNetwork, service, productServiceFunction, orderServiceFunction);
  }

  /**
   * Creates IAM roles for microservice identity management
   */
  private createServiceRoles(suffix: string): {
    productServiceRole: iam.Role;
    orderServiceRole: iam.Role;
  } {
    // Create IAM role for product service (client)
    const productServiceRole = new iam.Role(this, 'ProductServiceRole', {
      roleName: `ProductServiceRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for product service Lambda function with VPC Lattice access',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    // Create IAM role for order service (provider)
    const orderServiceRole = new iam.Role(this, 'OrderServiceRole', {
      roleName: `OrderServiceRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for order service Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    return { productServiceRole, orderServiceRole };
  }

  /**
   * Creates VPC Lattice service network with IAM authentication
   */
  private createServiceNetwork(suffix: string): cdk.aws_vpclattice.CfnServiceNetwork {
    const serviceNetwork = new cdk.aws_vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `microservices-network-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Name', value: `microservices-network-${suffix}` },
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });

    return serviceNetwork;
  }

  /**
   * Creates Lambda functions representing microservices
   */
  private createLambdaFunctions(
    suffix: string,
    productServiceRole: iam.Role,
    orderServiceRole: iam.Role
  ): {
    productServiceFunction: lambda.Function;
    orderServiceFunction: lambda.Function;
  } {
    // Product service (client) Lambda function
    const productServiceFunction = new lambda.Function(this, 'ProductServiceFunction', {
      functionName: `product-service-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: productServiceRole,
      timeout: cdk.Duration.seconds(30),
      description: 'Product service Lambda function acting as VPC Lattice client',
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib3

def lambda_handler(event, context):
    """
    Product service Lambda handler - simulates a client microservice
    that would make requests to other services via VPC Lattice
    """
    try:
        # In a real scenario, this would make HTTP requests to VPC Lattice service
        # using the AWS SigV4 signing process for authentication
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Product service authenticated and ready',
                'service': 'product-service',
                'role': context.invoked_function_arn.split(':')[4],
                'requestId': context.aws_request_id
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Order service (provider) Lambda function
    const orderServiceFunction = new lambda.Function(this, 'OrderServiceFunction', {
      functionName: `order-service-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      role: orderServiceRole,
      timeout: cdk.Duration.seconds(30),
      description: 'Order service Lambda function exposed via VPC Lattice',
      code: lambda.Code.fromInline(`
import json

def lambda_handler(event, context):
    """
    Order service Lambda handler - simulates a provider microservice
    that processes requests from other services via VPC Lattice
    """
    try:
        # Process the request and return order data
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Order service processing request',
                'service': 'order-service',
                'requestId': context.aws_request_id,
                'orders': [
                    {'id': 1, 'product': 'Widget A', 'quantity': 5, 'status': 'processing'},
                    {'id': 2, 'product': 'Widget B', 'quantity': 3, 'status': 'shipped'},
                    {'id': 3, 'product': 'Widget C', 'quantity': 2, 'status': 'delivered'}
                ],
                'totalOrders': 3,
                'timestamp': context.aws_request_id
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': str(e),
                'service': 'order-service'
            })
        }
      `)
    });

    return { productServiceFunction, orderServiceFunction };
  }

  /**
   * Creates VPC Lattice service and target group
   */
  private createVpcLatticeService(
    suffix: string,
    orderServiceFunction: lambda.Function
  ): {
    service: cdk.aws_vpclattice.CfnService;
    targetGroup: cdk.aws_vpclattice.CfnTargetGroup;
  } {
    // Create VPC Lattice service for order service
    const service = new cdk.aws_vpclattice.CfnService(this, 'OrderService', {
      name: `order-service-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Name', value: `order-service-${suffix}` },
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });

    // Create target group for Lambda function
    const targetGroup = new cdk.aws_vpclattice.CfnTargetGroup(this, 'OrderTargetGroup', {
      name: `order-targets-${suffix}`,
      type: 'LAMBDA',
      targets: [
        {
          id: orderServiceFunction.functionArn
        }
      ],
      tags: [
        { key: 'Name', value: `order-targets-${suffix}` },
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });

    // Create listener for the service
    new cdk.aws_vpclattice.CfnListener(this, 'OrderListener', {
      name: 'order-listener',
      serviceIdentifier: service.ref,
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: targetGroup.ref,
              weight: 100
            }
          ]
        }
      },
      tags: [
        { key: 'Name', value: 'order-listener' },
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });

    return { service, targetGroup };
  }

  /**
   * Associates service with service network
   */
  private createServiceNetworkAssociation(
    serviceNetwork: cdk.aws_vpclattice.CfnServiceNetwork,
    service: cdk.aws_vpclattice.CfnService
  ): void {
    new cdk.aws_vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceNetworkAssociation', {
      serviceNetworkIdentifier: serviceNetwork.ref,
      serviceIdentifier: service.ref,
      tags: [
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });
  }

  /**
   * Creates fine-grained authorization policy for zero-trust access control
   */
  private createAuthorizationPolicy(
    service: cdk.aws_vpclattice.CfnService,
    productServiceRole: iam.Role
  ): void {
    const authPolicy = {
      Version: '2012-10-17',
      Statement: [
        {
          Sid: 'AllowProductServiceAccess',
          Effect: 'Allow',
          Principal: {
            AWS: productServiceRole.roleArn
          },
          Action: 'vpc-lattice-svcs:Invoke',
          Resource: `arn:aws:vpc-lattice:${this.region}:${this.account}:service/${service.ref}/*`,
          Condition: {
            StringEquals: {
              'vpc-lattice-svcs:RequestMethod': ['GET', 'POST']
            },
            StringLike: {
              'vpc-lattice-svcs:RequestPath': '/orders*'
            }
          }
        },
        {
          Sid: 'DenyUnauthorizedAccess',
          Effect: 'Deny',
          Principal: '*',
          Action: 'vpc-lattice-svcs:Invoke',
          Resource: `arn:aws:vpc-lattice:${this.region}:${this.account}:service/${service.ref}/*`,
          Condition: {
            StringNotLike: {
              'aws:PrincipalArn': productServiceRole.roleArn
            }
          }
        }
      ]
    };

    new cdk.aws_vpclattice.CfnAuthPolicy(this, 'ServiceAuthPolicy', {
      resourceIdentifier: service.ref,
      policy: authPolicy
    });
  }

  /**
   * Creates CloudWatch monitoring and access logging
   */
  private createMonitoring(
    serviceNetwork: cdk.aws_vpclattice.CfnServiceNetwork,
    suffix: string
  ): void {
    // Create CloudWatch log group for VPC Lattice access logs
    const logGroup = new logs.LogGroup(this, 'VpcLatticeAccessLogs', {
      logGroupName: `/aws/vpclattice/microservices-network-${suffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Enable access logging for the service network
    new cdk.aws_vpclattice.CfnAccessLogSubscription(this, 'AccessLogSubscription', {
      resourceIdentifier: serviceNetwork.ref,
      destinationArn: logGroup.logGroupArn,
      tags: [
        { key: 'Purpose', value: 'MicroserviceAuth' }
      ]
    });

    // Create CloudWatch alarm for authorization failures
    new cloudwatch.Alarm(this, 'AuthFailuresAlarm', {
      alarmName: `VPC-Lattice-Auth-Failures-${suffix}`,
      alarmDescription: 'Monitor VPC Lattice authorization failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: '4XXError',
        dimensionsMap: {
          ServiceNetwork: serviceNetwork.ref
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create CloudWatch alarm for high latency
    new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `VPC-Lattice-High-Latency-${suffix}`,
      alarmDescription: 'Monitor VPC Lattice high latency',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'TargetResponseTime',
        dimensionsMap: {
          ServiceNetwork: serviceNetwork.ref
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5000, // 5 seconds
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
  }

  /**
   * Configures VPC Lattice permissions and IAM policies
   */
  private configureVpcLatticePermissions(
    orderServiceFunction: lambda.Function,
    productServiceRole: iam.Role,
    service: cdk.aws_vpclattice.CfnService
  ): void {
    // Grant VPC Lattice permission to invoke Lambda function
    orderServiceFunction.addPermission('VpcLatticeInvokePermission', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: `arn:aws:vpc-lattice:${this.region}:${this.account}:service/${service.ref}`
    });

    // Add policy to product service role for invoking VPC Lattice services
    const vpcLatticeInvokePolicy = new iam.Policy(this, 'VpcLatticeInvokePolicy', {
      policyName: 'VPCLatticeInvokePolicy',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['vpc-lattice-svcs:Invoke'],
          resources: [`arn:aws:vpc-lattice:${this.region}:${this.account}:service/${service.ref}/*`]
        })
      ]
    });

    productServiceRole.attachInlinePolicy(vpcLatticeInvokePolicy);
  }

  /**
   * Creates CloudFormation outputs for key resources
   */
  private createOutputs(
    serviceNetwork: cdk.aws_vpclattice.CfnServiceNetwork,
    service: cdk.aws_vpclattice.CfnService,
    productServiceFunction: lambda.Function,
    orderServiceFunction: lambda.Function
  ): void {
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.ref,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`
    });

    new cdk.CfnOutput(this, 'ServiceId', {
      value: service.ref,
      description: 'VPC Lattice Service ID',
      exportName: `${this.stackName}-ServiceId`
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: `arn:aws:vpc-lattice:${this.region}:${this.account}:service/${service.ref}`,
      description: 'VPC Lattice Service ARN',
      exportName: `${this.stackName}-ServiceArn`
    });

    new cdk.CfnOutput(this, 'ProductServiceFunctionName', {
      value: productServiceFunction.functionName,
      description: 'Product Service Lambda Function Name',
      exportName: `${this.stackName}-ProductServiceFunctionName`
    });

    new cdk.CfnOutput(this, 'OrderServiceFunctionName', {
      value: orderServiceFunction.functionName,
      description: 'Order Service Lambda Function Name',
      exportName: `${this.stackName}-OrderServiceFunctionName`
    });

    new cdk.CfnOutput(this, 'ProductServiceRoleArn', {
      value: this.productServiceRole.roleArn,
      description: 'Product Service IAM Role ARN',
      exportName: `${this.stackName}-ProductServiceRoleArn`
    });

    new cdk.CfnOutput(this, 'OrderServiceRoleArn', {
      value: this.orderServiceRole.roleArn,
      description: 'Order Service IAM Role ARN',
      exportName: `${this.stackName}-OrderServiceRoleArn`
    });
  }
}

// CDK App
const app = new cdk.App();

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Create the main stack
const stack = new MicroserviceAuthorizationStack(app, 'MicroserviceAuthorizationStack', {
  description: 'Microservice Authorization with VPC Lattice and IAM - Zero-trust networking for microservices',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  resourceSuffix: process.env.RESOURCE_SUFFIX,
  environment: process.env.ENVIRONMENT || 'demo'
});

// Add CDK Nag suppressions for specific use cases
NagSuppressions.addStackSuppressions(stack, [
  {
    id: 'AwsSolutions-IAM4',
    reason: 'Using AWS managed policy AWSLambdaBasicExecutionRole for Lambda execution roles is a best practice'
  },
  {
    id: 'AwsSolutions-IAM5',
    reason: 'VPC Lattice invoke policy requires wildcard permissions for service paths as per AWS documentation'
  },
  {
    id: 'AwsSolutions-L1',
    reason: 'Using Python 3.12 which is the latest stable runtime for Lambda'
  }
]);

app.synth();