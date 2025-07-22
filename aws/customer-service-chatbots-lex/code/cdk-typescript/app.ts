#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lexv2 from 'aws-cdk-lib/aws-lex';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for Customer Service Chatbots with Amazon Lex V2
 * 
 * This stack creates:
 * - DynamoDB table for customer data
 * - Lambda function for intent fulfillment
 * - Amazon Lex V2 bot with intents and slots
 * - IAM roles and policies with least privilege access
 */
export class CustomerServiceChatbotStack extends cdk.Stack {
  public readonly bot: lexv2.CfnBot;
  public readonly fulfillmentFunction: lambda.Function;
  public readonly customerDataTable: dynamodb.Table;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resources
    const uniqueSuffix = this.generateUniqueSuffix();

    // Create DynamoDB table for customer data
    this.customerDataTable = this.createCustomerDataTable(uniqueSuffix);

    // Create Lambda function for intent fulfillment
    this.fulfillmentFunction = this.createFulfillmentFunction(uniqueSuffix);

    // Grant Lambda function read/write access to DynamoDB table
    this.customerDataTable.grantReadWriteData(this.fulfillmentFunction);

    // Create Amazon Lex V2 bot
    this.bot = this.createLexBot(uniqueSuffix);

    // Grant Lex permission to invoke Lambda function
    this.fulfillmentFunction.addPermission('LexInvokePermission', {
      principal: new iam.ServicePrincipal('lexv2.amazonaws.com'),
      sourceArn: `arn:aws:lex:${this.region}:${this.account}:bot/${this.bot.attrBotId}`,
      action: 'lambda:InvokeFunction'
    });

    // Add sample customer data to DynamoDB table
    this.addSampleCustomerData();

    // Output important resource identifiers
    this.createOutputs();
  }

  /**
   * Generates a unique suffix for resource naming
   */
  private generateUniqueSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }

  /**
   * Creates DynamoDB table for storing customer data
   */
  private createCustomerDataTable(uniqueSuffix: string): dynamodb.Table {
    return new dynamodb.Table(this, 'CustomerDataTable', {
      tableName: `customer-data-${uniqueSuffix}`,
      partitionKey: {
        name: 'CustomerId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      tags: [
        {
          key: 'Project',
          value: 'LexCustomerService'
        },
        {
          key: 'Purpose',
          value: 'CustomerServiceChatbot'
        }
      ]
    });
  }

  /**
   * Creates Lambda function for handling Lex intent fulfillment
   */
  private createFulfillmentFunction(uniqueSuffix: string): lambda.Function {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `LexLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    return new lambda.Function(this, 'FulfillmentFunction', {
      functionName: `lex-fulfillment-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    slots = event['sessionState']['intent']['slots']
    
    if intent_name == 'OrderStatus':
        return handle_order_status(event, slots)
    elif intent_name == 'BillingInquiry':
        return handle_billing_inquiry(event, slots)
    elif intent_name == 'ProductInfo':
        return handle_product_info(event, slots)
    else:
        return close_intent(event, 'Fulfilled', 
                           'I can help you with order status, billing questions, or product information.')

def handle_order_status(event, slots):
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your order status?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            message = f"Hi {item['Name']}! Your last order {item['LastOrderId']} is currently {item['LastOrderStatus']}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving order status: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your order status. Please try again later.')

def handle_billing_inquiry(event, slots):
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your account balance?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            balance = float(item['AccountBalance'])
            message = f"Hi {item['Name']}! Your current account balance is ${balance:.2f}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving billing info: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your account. Please try again later.')

def handle_product_info(event, slots):
    product_name = slots.get('ProductName', {}).get('value', {}).get('interpretedValue')
    
    if not product_name:
        return elicit_slot(event, 'ProductName', 
                          'What product would you like information about?')
    
    # Simple product info responses (in real implementation, query product database)
    product_info = {
        'laptop': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'smartphone': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'tablet': 'Our tablets are perfect for productivity and entertainment, starting at $399.'
    }
    
    product_lower = product_name.lower()
    if product_lower in product_info:
        message = product_info[product_lower]
    else:
        message = f"I don't have specific information about {product_name}. Please contact our sales team for detailed product information."
    
    return close_intent(event, 'Fulfilled', message)

def elicit_slot(event, slot_to_elicit, message):
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_to_elicit
            },
            'intent': event['sessionState']['intent']
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, fulfillment_state, message):
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': fulfillment_state
            }
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
      `),
      environment: {
        DYNAMODB_TABLE_NAME: this.customerDataTable.tableName
      },
      timeout: cdk.Duration.seconds(30),
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Lambda function for Amazon Lex intent fulfillment in customer service chatbot'
    });
  }

  /**
   * Creates Amazon Lex V2 bot with intents and slots
   */
  private createLexBot(uniqueSuffix: string): lexv2.CfnBot {
    // Create IAM role for Lex service
    const lexRole = new iam.Role(this, 'LexServiceRole', {
      roleName: `LexServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lexv2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonLexV2BotPolicy')
      ]
    });

    return new lexv2.CfnBot(this, 'CustomerServiceBot', {
      name: `CustomerServiceBot-${uniqueSuffix}`,
      description: 'Customer service chatbot for handling common inquiries',
      roleArn: lexRole.roleArn,
      dataPrivacy: {
        childDirected: false
      },
      idleSessionTtlInSeconds: 600,
      botLocales: [
        {
          localeId: 'en_US',
          description: 'English US locale for customer service bot',
          nluConfidenceThreshold: 0.40,
          voiceSettings: {
            voiceId: 'Joanna'
          },
          slotTypes: [
            {
              slotTypeName: 'CustomerId',
              description: 'Customer identification numbers',
              valueSelectionStrategy: 'ORIGINAL_VALUE',
              slotTypeValues: [
                {
                  sampleValue: { value: '12345' }
                },
                {
                  sampleValue: { value: '67890' }
                }
              ]
            },
            {
              slotTypeName: 'ProductName',
              description: 'Product names for inquiries',
              valueSelectionStrategy: 'TOP_RESOLUTION',
              slotTypeValues: [
                {
                  sampleValue: { value: 'laptop' },
                  synonyms: [
                    { value: 'computer' },
                    { value: 'notebook' }
                  ]
                },
                {
                  sampleValue: { value: 'smartphone' },
                  synonyms: [
                    { value: 'phone' },
                    { value: 'mobile' }
                  ]
                },
                {
                  sampleValue: { value: 'tablet' },
                  synonyms: [
                    { value: 'ipad' }
                  ]
                }
              ]
            }
          ],
          intents: [
            {
              intentName: 'OrderStatus',
              description: 'Handle order status inquiries',
              sampleUtterances: [
                { utterance: 'What is my order status' },
                { utterance: 'Check my order' },
                { utterance: 'Where is my order' },
                { utterance: 'Track my order {CustomerId}' },
                { utterance: 'Order status for {CustomerId}' },
                { utterance: 'My customer ID is {CustomerId}' }
              ],
              slots: [
                {
                  slotName: 'CustomerId',
                  description: 'Customer identification number',
                  slotTypeName: 'CustomerId',
                  valueElicitationSetting: {
                    slotConstraint: 'Required',
                    promptSpecification: {
                      messageGroupsList: [
                        {
                          message: {
                            plainTextMessage: {
                              value: 'Could you please provide your customer ID?'
                            }
                          }
                        }
                      ],
                      maxRetries: 2
                    }
                  }
                }
              ],
              fulfillmentCodeHook: {
                enabled: true
              }
            },
            {
              intentName: 'BillingInquiry',
              description: 'Handle billing and account balance inquiries',
              sampleUtterances: [
                { utterance: 'What is my account balance' },
                { utterance: 'Check my balance' },
                { utterance: 'How much do I owe' },
                { utterance: 'Billing information for {CustomerId}' },
                { utterance: 'Account balance for customer {CustomerId}' },
                { utterance: 'My balance please' }
              ],
              slots: [
                {
                  slotName: 'CustomerId',
                  description: 'Customer identification number for billing',
                  slotTypeName: 'CustomerId',
                  valueElicitationSetting: {
                    slotConstraint: 'Required',
                    promptSpecification: {
                      messageGroupsList: [
                        {
                          message: {
                            plainTextMessage: {
                              value: 'Please provide your customer ID to check your account balance.'
                            }
                          }
                        }
                      ],
                      maxRetries: 2
                    }
                  }
                }
              ],
              fulfillmentCodeHook: {
                enabled: true
              }
            },
            {
              intentName: 'ProductInfo',
              description: 'Handle product information requests',
              sampleUtterances: [
                { utterance: 'Tell me about {ProductName}' },
                { utterance: 'Product information for {ProductName}' },
                { utterance: 'What can you tell me about {ProductName}' },
                { utterance: 'I want to know about {ProductName}' },
                { utterance: 'Details about your {ProductName}' }
              ],
              slots: [
                {
                  slotName: 'ProductName',
                  description: 'Product name for information request',
                  slotTypeName: 'ProductName',
                  valueElicitationSetting: {
                    slotConstraint: 'Required',
                    promptSpecification: {
                      messageGroupsList: [
                        {
                          message: {
                            plainTextMessage: {
                              value: 'What product would you like information about?'
                            }
                          }
                        }
                      ],
                      maxRetries: 2
                    }
                  }
                }
              ],
              fulfillmentCodeHook: {
                enabled: true
              }
            },
            {
              intentName: 'FallbackIntent',
              description: 'Default fallback intent',
              parentIntentSignature: 'AMAZON.FallbackIntent',
              intentClosingSetting: {
                closingResponse: {
                  messageGroupsList: [
                    {
                      message: {
                        plainTextMessage: {
                          value: 'I can help you with order status, billing questions, or product information. How can I assist you today?'
                        }
                      }
                    }
                  ]
                }
              }
            }
          ]
        }
      ],
      botTags: [
        {
          key: 'Project',
          value: 'LexCustomerService'
        },
        {
          key: 'Purpose',
          value: 'CustomerServiceChatbot'
        }
      ]
    });
  }

  /**
   * Adds sample customer data to DynamoDB table using Custom Resource
   */
  private addSampleCustomerData(): void {
    // Create custom resource to populate sample data
    const customResourceRole = new iam.Role(this, 'CustomResourceRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ]
    });

    this.customerDataTable.grantWriteData(customResourceRole);

    const customResourceFunction = new lambda.Function(this, 'SampleDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      role: customResourceRole,
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        dynamodb = boto3.resource('dynamodb')
        table_name = event['ResourceProperties']['TableName']
        table = dynamodb.Table(table_name)
        
        if event['RequestType'] == 'Create':
            # Insert sample customer data
            table.put_item(Item={
                'CustomerId': '12345',
                'Name': 'John Smith',
                'Email': 'john.smith@example.com',
                'LastOrderId': 'ORD-789',
                'LastOrderStatus': 'Shipped',
                'AccountBalance': 156.78
            })
            
            table.put_item(Item={
                'CustomerId': '67890',
                'Name': 'Jane Doe',
                'Email': 'jane.doe@example.com',
                'LastOrderId': 'ORD-456',
                'LastOrderStatus': 'Processing',
                'AccountBalance': 89.23
            })
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
      `),
      timeout: cdk.Duration.minutes(5)
    });

    new cdk.CustomResource(this, 'SampleDataResource', {
      serviceToken: customResourceFunction.functionArn,
      properties: {
        TableName: this.customerDataTable.tableName
      }
    });
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'BotId', {
      value: this.bot.attrBotId,
      description: 'Amazon Lex Bot ID'
    });

    new cdk.CfnOutput(this, 'BotName', {
      value: this.bot.name!,
      description: 'Amazon Lex Bot Name'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.fulfillmentFunction.functionName,
      description: 'Lambda Function Name for intent fulfillment'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.fulfillmentFunction.functionArn,
      description: 'Lambda Function ARN for intent fulfillment'
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: this.customerDataTable.tableName,
      description: 'DynamoDB Table Name for customer data'
    });

    new cdk.CfnOutput(this, 'DynamoDBTableArn', {
      value: this.customerDataTable.tableArn,
      description: 'DynamoDB Table ARN for customer data'
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws lexv2-runtime recognize-text --bot-id ${this.bot.attrBotId} --bot-alias-id TSTALIASID --locale-id en_US --session-id test-session --text "What is my order status for customer 12345?"`,
      description: 'AWS CLI command to test the bot'
    });
  }
}

// CDK App
const app = new cdk.App();

new CustomerServiceChatbotStack(app, 'CustomerServiceChatbotStack', {
  description: 'Customer Service Chatbots with Amazon Lex V2, Lambda, and DynamoDB',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'LexCustomerService',
    Purpose: 'CustomerServiceChatbot',
    CreatedBy: 'CDK'
  }
});

app.synth();