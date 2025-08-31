#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Private API Integration with VPC Lattice and EventBridge
 * 
 * This stack demonstrates secure event-driven architecture using VPC Lattice
 * Resource Configurations to enable direct private API access from EventBridge
 * and Step Functions without Lambda proxies.
 */
export class PrivateApiIntegrationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);

    // Create VPC for demonstration purposes
    const targetVpc = new ec2.Vpc(this, 'TargetVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.1.0.0/16'),
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for private endpoints
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create VPC Endpoint for API Gateway
    const apiGatewayVpcEndpoint = new ec2.InterfaceVpcEndpoint(this, 'ApiGatewayVpcEndpoint', {
      vpc: targetVpc,
      service: ec2.InterfaceVpcEndpointAwsService.APIGATEWAY,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      policyDocument: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:*'],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create Private API Gateway
    const privateApi = new apigateway.RestApi(this, 'PrivateApi', {
      restApiName: `private-demo-api-${uniqueSuffix}`,
      description: 'Private API Gateway for VPC Lattice integration',
      endpointConfiguration: {
        types: [apigateway.EndpointType.PRIVATE],
        vpcEndpoints: [apiGatewayVpcEndpoint],
      },
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: ['execute-api:Invoke'],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'aws:sourceVpce': apiGatewayVpcEndpoint.vpcEndpointId,
              },
            },
          }),
        ],
      }),
      cloudWatchRole: true, // Enable CloudWatch integration
    });

    // Create /orders resource and POST method
    const ordersResource = privateApi.root.addResource('orders');
    const orderIntegration = new apigateway.MockIntegration({
      requestTemplates: {
        'application/json': '{"statusCode": 200}',
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseTemplates: {
            'application/json': JSON.stringify({
              orderId: '12345',
              status: 'created',
              timestamp: '$context.requestTime',
            }),
          },
        },
      ],
    });

    ordersResource.addMethod('POST', orderIntegration, {
      authorizationType: apigateway.AuthorizationType.IAM,
      methodResponses: [
        {
          statusCode: '200',
        },
      ],
    });

    // Deploy API to prod stage
    const deployment = new apigateway.Deployment(this, 'ApiDeployment', {
      api: privateApi,
    });

    const prodStage = new apigateway.Stage(this, 'ProdStage', {
      deployment,
      stageName: 'prod',
      // Enable access logging
      accessLogDestination: new apigateway.LogGroupLogDestination(
        new logs.LogGroup(this, 'ApiAccessLogs', {
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        })
      ),
      accessLogFormat: apigateway.AccessLogFormat.jsonWithStandardFields(),
    });

    // Create VPC Lattice Service Network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `private-api-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: 'demo' },
        { key: 'Purpose', value: 'private-api-integration' },
      ],
    });

    // Create VPC Lattice Resource Gateway
    const resourceGateway = new vpclattice.CfnResourceGateway(this, 'ResourceGateway', {
      name: `api-gateway-resource-gateway-${uniqueSuffix}`,
      vpcIdentifier: targetVpc.vpcId,
      subnetIds: targetVpc.isolatedSubnets.map(subnet => subnet.subnetId),
      tags: [
        { key: 'Purpose', value: 'private-api-access' },
        { key: 'Environment', value: 'demo' },
      ],
    });

    // Create VPC Lattice Resource Configuration
    const resourceConfiguration = new vpclattice.CfnResourceConfiguration(this, 'ResourceConfiguration', {
      name: `private-api-config-${uniqueSuffix}`,
      type: 'SINGLE',
      resourceGatewayIdentifier: resourceGateway.attrId,
      resourceConfigurationDefinition: {
        type: 'RESOURCE',
        resourceIdentifier: apiGatewayVpcEndpoint.vpcEndpointId,
        portRanges: [
          {
            fromPort: 443,
            toPort: 443,
            protocol: 'TCP',
          },
        ],
      },
      allowAssociationToShareableServiceNetwork: true,
      tags: [
        { key: 'Purpose', value: 'private-api-integration' },
        { key: 'Environment', value: 'demo' },
      ],
    });

    // Associate Resource Configuration with Service Network
    const resourceAssociation = new vpclattice.CfnServiceNetworkResourceAssociation(
      this,
      'ResourceAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        resourceConfigurationIdentifier: resourceConfiguration.attrArn,
      }
    );

    // Create IAM Role for EventBridge and Step Functions
    const eventBridgeStepFunctionsRole = new iam.Role(this, 'EventBridgeStepFunctionsRole', {
      roleName: `EventBridgeStepFunctionsVPCLatticeRole-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('events.amazonaws.com'),
        new iam.ServicePrincipal('states.amazonaws.com')
      ),
      inlinePolicies: {
        VPCLatticeConnectionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:CreateConnection',
                'events:UpdateConnection',
                'events:InvokeApiDestination',
                'execute-api:Invoke',
                'vpc-lattice:GetResourceConfiguration',
                'states:StartExecution',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Custom EventBridge Bus
    const customEventBus = new events.EventBus(this, 'CustomEventBus', {
      eventBusName: `private-api-bus-${uniqueSuffix}`,
    });

    // Create EventBridge Connection for Private API
    const apiConnection = new events.Connection(this, 'PrivateApiConnection', {
      connectionName: `private-api-connection-${uniqueSuffix}`,
      description: 'Connection to private API Gateway via VPC Lattice',
      authorization: events.Authorization.invocationHttpParameters({
        headerParameters: {
          'Content-Type': 'application/json',
        },
      }),
    });

    // Create Step Functions State Machine Definition
    const processOrderTask = new sfnTasks.HttpInvoke(this, 'ProcessOrderTask', {
      apiRoot: `https://${privateApi.restApiId}-${apiGatewayVpcEndpoint.vpcEndpointId}.execute-api.${this.region}.amazonaws.com/prod`,
      apiEndpoint: sfnTasks.TaskInput.fromText('/orders'),
      method: sfnTasks.HttpMethod.POST,
      headers: sfnTasks.TaskInput.fromObject({
        'Content-Type': 'application/json',
      }),
      body: sfnTasks.TaskInput.fromObject({
        'customerId': '12345',
        'orderItems': ['item1', 'item2'],
        'timestamp.$': '$$.State.EnteredTime',
      }),
      connection: apiConnection,
      retryOnServiceExceptions: true,
    });

    const processSuccess = new stepfunctions.Pass(this, 'ProcessSuccess', {
      result: stepfunctions.Result.fromString('Order processed successfully'),
    });

    const handleError = new stepfunctions.Pass(this, 'HandleError', {
      result: stepfunctions.Result.fromString('Order processing failed'),
    });

    // Define state machine with error handling
    const definition = processOrderTask
      .addRetry({
        errors: ['States.Http.StatusCodeFailure'],
        intervalSeconds: 2,
        maxAttempts: 3,
        backoffRate: 2.0,
      })
      .addCatch(handleError, {
        errors: ['States.TaskFailed'],
      })
      .next(processSuccess);

    // Create Step Functions State Machine
    const stateMachine = new stepfunctions.StateMachine(this, 'PrivateApiWorkflow', {
      stateMachineName: `private-api-workflow-${uniqueSuffix}`,
      definition,
      role: eventBridgeStepFunctionsRole,
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/private-api-workflow-${uniqueSuffix}`,
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
      tracingEnabled: true, // Enable X-Ray tracing
    });

    // Create EventBridge Rule to trigger Step Functions
    const eventRule = new events.Rule(this, 'TriggerPrivateApiWorkflow', {
      eventBus: customEventBus,
      ruleName: 'trigger-private-api-workflow',
      description: 'Triggers Step Functions workflow for order processing',
      eventPattern: {
        source: ['demo.application'],
        detailType: ['Order Received'],
      },
      enabled: true,
    });

    // Add Step Functions as target
    eventRule.addTarget(
      new targets.SfnStateMachine(stateMachine, {
        role: eventBridgeStepFunctionsRole,
      })
    );

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: targetVpc.vpcId,
      description: 'Target VPC ID',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'PrivateApiId', {
      value: privateApi.restApiId,
      description: 'Private API Gateway ID',
      exportName: `${this.stackName}-PrivateApiId`,
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: `https://${privateApi.restApiId}-${apiGatewayVpcEndpoint.vpcEndpointId}.execute-api.${this.region}.amazonaws.com/prod`,
      description: 'Private API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'ResourceConfigurationArn', {
      value: resourceConfiguration.attrArn,
      description: 'VPC Lattice Resource Configuration ARN',
      exportName: `${this.stackName}-ResourceConfigurationArn`,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions State Machine ARN',
      exportName: `${this.stackName}-StateMachineArn`,
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'Custom EventBridge Bus Name',
      exportName: `${this.stackName}-EventBusName`,
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws events put-events --entries '[{"Source": "demo.application", "DetailType": "Order Received", "Detail": "{\\"orderId\\": \\"test-123\\", \\"customerId\\": \\"cust-456\\"}", "EventBusName": "${customEventBus.eventBusName}"}]'`,
      description: 'Command to test the integration',
      exportName: `${this.stackName}-TestCommand`,
    });
  }
}

// CDK App
const app = new cdk.App();

new PrivateApiIntegrationStack(app, 'PrivateApiIntegrationStack', {
  description: 'Private API Integration with VPC Lattice and EventBridge (uksb-1tupboc58)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production
  terminationProtection: false, // Set to true for production deployments
  
  // Stack-level tags
  tags: {
    Project: 'PrivateApiIntegration',
    Environment: 'Demo',
    ManagedBy: 'CDK',
    Repository: 'aws-recipes',
  },
});