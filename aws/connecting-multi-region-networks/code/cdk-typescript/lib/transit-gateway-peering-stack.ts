import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';

/**
 * Properties for the TransitGatewayPeeringStack
 */
export interface TransitGatewayPeeringStackProps extends cdk.StackProps {
  /** Project name for resource naming */
  projectName: string;
  /** Primary region Transit Gateway ID */
  primaryTransitGatewayId: string;
  /** Secondary region Transit Gateway ID */
  secondaryTransitGatewayId: string;
  /** Primary region route table ID */
  primaryRouteTableId: string;
  /** Secondary region route table ID */
  secondaryRouteTableId: string;
  /** Primary region name */
  primaryRegion: string;
  /** Secondary region name */
  secondaryRegion: string;
  /** Remote CIDR blocks for routing */
  remoteCidrs: {
    primary: string[];
    secondary: string[];
  };
}

/**
 * Transit Gateway Peering Stack
 * 
 * This stack creates and manages cross-region Transit Gateway peering connections
 * and routing configuration. It handles:
 * - Cross-region peering attachment creation
 * - Peering attachment acceptance in remote region
 * - Cross-region route creation in both directions
 * - Route table associations for peering attachments
 * 
 * The stack uses AWS SDK custom resources to manage cross-region operations
 * since CloudFormation has limitations with cross-region resource management.
 */
export class TransitGatewayPeeringStack extends cdk.Stack {
  /** Peering attachment ID for monitoring and management */
  public readonly peeringAttachmentId: string;

  constructor(scope: Construct, id: string, props: TransitGatewayPeeringStackProps) {
    super(scope, id, props);

    // Create custom resource provider for cross-region operations
    const customResourceProvider = new cr.Provider(this, 'CustomResourceProvider', {
      onEventHandler: this.createPeeringHandler(props),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create Transit Gateway peering attachment
    const peeringAttachment = new ec2.CfnTransitGatewayPeeringAttachment(this, 'PeeringAttachment', {
      transitGatewayId: props.primaryTransitGatewayId,
      peerTransitGatewayId: props.secondaryTransitGatewayId,
      peerAccountId: cdk.Stack.of(this).account,
      peerRegion: props.secondaryRegion,
      tags: [
        {
          key: 'Name',
          value: `${props.projectName}-cross-region-peering`
        }
      ]
    });

    this.peeringAttachmentId = peeringAttachment.attrId;

    // Use custom resource to accept peering in secondary region
    const peeringAcceptance = new cdk.CustomResource(this, 'PeeringAcceptance', {
      serviceToken: customResourceProvider.serviceToken,
      properties: {
        PeeringAttachmentId: peeringAttachment.attrId,
        SecondaryRegion: props.secondaryRegion,
        Action: 'AcceptPeering'
      }
    });

    peeringAcceptance.node.addDependency(peeringAttachment);

    // Associate peering attachment with route tables in both regions
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'PrimaryPeeringRouteTableAssociation', {
      transitGatewayAttachmentId: peeringAttachment.attrId,
      transitGatewayRouteTableId: props.primaryRouteTableId
    });

    // Use custom resource to associate peering attachment with secondary route table
    const secondaryAssociation = new cdk.CustomResource(this, 'SecondaryPeeringAssociation', {
      serviceToken: customResourceProvider.serviceToken,
      properties: {
        PeeringAttachmentId: peeringAttachment.attrId,
        RouteTableId: props.secondaryRouteTableId,
        SecondaryRegion: props.secondaryRegion,
        Action: 'AssociatePeering'
      }
    });

    secondaryAssociation.node.addDependency(peeringAcceptance);

    // Create routes from primary to secondary region
    props.remoteCidrs.secondary.forEach((cidr, index) => {
      new ec2.CfnTransitGatewayRoute(this, `PrimaryToSecondaryRoute${index}`, {
        destinationCidrBlock: cidr,
        transitGatewayRouteTableId: props.primaryRouteTableId,
        transitGatewayAttachmentId: peeringAttachment.attrId
      });
    });

    // Use custom resource to create routes from secondary to primary region
    props.remoteCidrs.primary.forEach((cidr, index) => {
      const secondaryRoute = new cdk.CustomResource(this, `SecondaryToPrimaryRoute${index}`, {
        serviceToken: customResourceProvider.serviceToken,
        properties: {
          DestinationCidr: cidr,
          RouteTableId: props.secondaryRouteTableId,
          PeeringAttachmentId: peeringAttachment.attrId,
          SecondaryRegion: props.secondaryRegion,
          Action: 'CreateRoute'
        }
      });

      secondaryRoute.node.addDependency(secondaryAssociation);
    });

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'PeeringAttachmentId', {
      value: this.peeringAttachmentId,
      description: 'Cross-region Transit Gateway peering attachment ID',
      exportName: `${props.projectName}-peering-attachment-id`
    });

    new cdk.CfnOutput(this, 'PeeringStatus', {
      value: 'Created',
      description: 'Status of cross-region peering configuration'
    });

    // Add tags for resource management
    cdk.Tags.of(this).add('Component', 'cross-region-peering');
  }

  /**
   * Creates the Lambda function handler for cross-region operations
   */
  private createPeeringHandler(props: TransitGatewayPeeringStackProps): lambda.Function {
    return new lambda.Function(this, 'PeeringHandler', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(10),
      environment: {
        PRIMARY_REGION: props.primaryRegion,
        SECONDARY_REGION: props.secondaryRegion
      },
      initialPolicy: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:AcceptTransitGatewayPeeringAttachment',
            'ec2:AssociateTransitGatewayRouteTable',
            'ec2:CreateTransitGatewayRoute',
            'ec2:DescribeTransitGatewayPeeringAttachments',
            'ec2:DescribeTransitGatewayRouteTables',
            'ec2:DisassociateTransitGatewayRouteTable',
            'ec2:DeleteTransitGatewayRoute'
          ],
          resources: ['*']
        })
      ],
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib3

def handler(event, context):
    """
    Custom resource handler for cross-region Transit Gateway operations
    """
    print(f"Event: {json.dumps(event)}")
    
    request_type = event['RequestType']
    properties = event['ResourceProperties']
    action = properties.get('Action')
    
    try:
        if request_type == 'Create':
            return handle_create(properties)
        elif request_type == 'Update':
            return handle_update(properties)
        elif request_type == 'Delete':
            return handle_delete(properties)
    except Exception as e:
        print(f"Error: {str(e)}")
        send_response(event, context, 'FAILED', str(e))
        return
    
    send_response(event, context, 'SUCCESS', 'Operation completed')

def handle_create(properties):
    """Handle resource creation"""
    action = properties['Action']
    
    if action == 'AcceptPeering':
        accept_peering(properties)
    elif action == 'AssociatePeering':
        associate_peering(properties)
    elif action == 'CreateRoute':
        create_route(properties)
    
    return 'SUCCESS'

def handle_update(properties):
    """Handle resource update"""
    return handle_create(properties)

def handle_delete(properties):
    """Handle resource deletion"""
    action = properties['Action']
    
    if action == 'CreateRoute':
        delete_route(properties)
    # Note: Peering acceptance and association cleanup is handled by CloudFormation
    
    return 'SUCCESS'

def accept_peering(properties):
    """Accept Transit Gateway peering attachment in secondary region"""
    ec2 = boto3.client('ec2', region_name=properties['SecondaryRegion'])
    
    peering_id = properties['PeeringAttachmentId']
    
    response = ec2.accept_transit_gateway_peering_attachment(
        TransitGatewayAttachmentId=peering_id
    )
    
    print(f"Accepted peering attachment: {peering_id}")
    return response

def associate_peering(properties):
    """Associate peering attachment with route table in secondary region"""
    ec2 = boto3.client('ec2', region_name=properties['SecondaryRegion'])
    
    response = ec2.associate_transit_gateway_route_table(
        TransitGatewayAttachmentId=properties['PeeringAttachmentId'],
        TransitGatewayRouteTableId=properties['RouteTableId']
    )
    
    print(f"Associated peering with route table: {properties['RouteTableId']}")
    return response

def create_route(properties):
    """Create route in secondary region route table"""
    ec2 = boto3.client('ec2', region_name=properties['SecondaryRegion'])
    
    response = ec2.create_transit_gateway_route(
        DestinationCidrBlock=properties['DestinationCidr'],
        TransitGatewayRouteTableId=properties['RouteTableId'],
        TransitGatewayAttachmentId=properties['PeeringAttachmentId']
    )
    
    print(f"Created route: {properties['DestinationCidr']} -> {properties['PeeringAttachmentId']}")
    return response

def delete_route(properties):
    """Delete route from secondary region route table"""
    ec2 = boto3.client('ec2', region_name=properties['SecondaryRegion'])
    
    try:
        response = ec2.delete_transit_gateway_route(
            DestinationCidrBlock=properties['DestinationCidr'],
            TransitGatewayRouteTableId=properties['RouteTableId']
        )
        print(f"Deleted route: {properties['DestinationCidr']}")
        return response
    except Exception as e:
        print(f"Error deleting route (may not exist): {str(e)}")
        # Don't fail if route doesn't exist

def send_response(event, context, status, reason):
    """Send response to CloudFormation"""
    response_url = event['ResponseURL']
    
    response_body = {
        'Status': status,
        'Reason': reason,
        'PhysicalResourceId': context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId']
    }
    
    json_response = json.dumps(response_body)
    headers = {
        'content-type': '',
        'content-length': str(len(json_response))
    }
    
    http = urllib3.PoolManager()
    http.request('PUT', response_url, body=json_response, headers=headers)
`)
    });
  }
}