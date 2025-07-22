import { Context, APIGatewayProxyEvent, EventBridgeEvent } from 'aws-lambda';
import { DSQLClient, ExecuteStatementCommand, ExecuteStatementCommandInput } from '@aws-sdk/client-dsql';
import { EventBridgeClient, PutEventsCommand, PutEventsCommandInput } from '@aws-sdk/client-eventbridge';

// Environment variables
const DSQL_CLUSTER_ID = process.env.DSQL_CLUSTER_ID!;
const AWS_REGION = process.env.AWS_REGION!;
const IS_PRIMARY_REGION = process.env.IS_PRIMARY_REGION === 'true';
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME!;

// Initialize AWS SDK clients
const dsqlClient = new DSQLClient({ region: AWS_REGION });
const eventBridgeClient = new EventBridgeClient({ region: AWS_REGION });

// Response interface
interface LambdaResponse {
  statusCode: number;
  body: string;
  headers?: Record<string, string>;
}

// Transaction interface
interface Transaction {
  id: string;
  amount: number;
  timestamp: string;
  region: string;
  status?: string;
}

// Event detail interface for EventBridge
interface TransactionEventDetail {
  transactionId: string;
  amount: number;
  region: string;
  operation: 'create' | 'read' | 'update' | 'delete';
  timestamp: string;
}

/**
 * Executes SQL statements against Aurora DSQL cluster
 */
async function executeDSQLStatement(sql: string, parameters: any[] = []): Promise<any> {
  try {
    const params: ExecuteStatementCommandInput = {
      ClusterIdentifier: DSQL_CLUSTER_ID,
      Sql: sql,
      Parameters: parameters.length > 0 ? parameters : undefined
    };

    const command = new ExecuteStatementCommand(params);
    const response = await dsqlClient.send(command);
    
    console.log('DSQL statement executed successfully', { sql, parameters, response });
    return response;
  } catch (error) {
    console.error('Error executing DSQL statement', { sql, parameters, error });
    throw error;
  }
}

/**
 * Publishes events to EventBridge for cross-region coordination
 */
async function publishEvent(eventType: string, detail: TransactionEventDetail): Promise<void> {
  try {
    const params: PutEventsCommandInput = {
      Entries: [
        {
          Source: 'dsql.application',
          DetailType: eventType,
          Detail: JSON.stringify(detail),
          EventBusName: EVENT_BUS_NAME,
          Time: new Date()
        }
      ]
    };

    const command = new PutEventsCommand(params);
    await eventBridgeClient.send(command);
    
    console.log('Event published successfully', { eventType, detail });
  } catch (error) {
    console.error('Error publishing event', { eventType, detail, error });
    throw error;
  }
}

/**
 * Creates a new transaction in Aurora DSQL
 */
async function createTransaction(transactionId: string, amount: number): Promise<Transaction> {
  const timestamp = new Date().toISOString();
  
  // Insert transaction using parameterized query
  await executeDSQLStatement(
    `INSERT INTO transactions (id, amount, timestamp, region, status) 
     VALUES (?, ?, ?, ?, ?)`,
    [
      { StringValue: transactionId },
      { DoubleValue: amount },
      { StringValue: timestamp },
      { StringValue: AWS_REGION },
      { StringValue: 'completed' }
    ]
  );

  const transaction: Transaction = {
    id: transactionId,
    amount,
    timestamp,
    region: AWS_REGION,
    status: 'completed'
  };

  // Publish event for cross-region coordination
  await publishEvent('Transaction Created', {
    transactionId,
    amount,
    region: AWS_REGION,
    operation: 'create',
    timestamp
  });

  return transaction;
}

/**
 * Reads transaction count from Aurora DSQL
 */
async function getTransactionCount(): Promise<number> {
  const response = await executeDSQLStatement(
    'SELECT COUNT(*) as transaction_count FROM transactions'
  );

  // Extract count from response
  const count = response.Records?.[0]?.Values?.[0]?.LongValue || 0;
  
  console.log('Retrieved transaction count', { count });
  return count;
}

/**
 * Reads recent transactions from Aurora DSQL
 */
async function getRecentTransactions(limit: number = 10): Promise<Transaction[]> {
  const response = await executeDSQLStatement(
    `SELECT id, amount, timestamp, region, status 
     FROM transactions 
     ORDER BY timestamp DESC 
     LIMIT ?`,
    [{ LongValue: limit }]
  );

  const transactions: Transaction[] = [];
  
  if (response.Records) {
    for (const record of response.Records) {
      if (record.Values && record.Values.length >= 5) {
        transactions.push({
          id: record.Values[0]?.StringValue || '',
          amount: record.Values[1]?.DoubleValue || 0,
          timestamp: record.Values[2]?.StringValue || '',
          region: record.Values[3]?.StringValue || '',
          status: record.Values[4]?.StringValue || 'unknown'
        });
      }
    }
  }

  console.log('Retrieved recent transactions', { count: transactions.length });
  return transactions;
}

/**
 * Handles direct Lambda invocation (for testing or API Gateway integration)
 */
async function handleDirectInvocation(event: any): Promise<LambdaResponse> {
  try {
    const operation = event.operation || 'read';
    
    switch (operation.toLowerCase()) {
      case 'create':
      case 'write': {
        const transactionId = event.transactionId || event.transaction_id || `txn-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const amount = parseFloat(event.amount) || 0;
        
        if (amount <= 0) {
          return {
            statusCode: 400,
            body: JSON.stringify({ 
              error: 'Invalid amount. Amount must be greater than 0.',
              region: AWS_REGION,
              isPrimary: IS_PRIMARY_REGION
            })
          };
        }

        const transaction = await createTransaction(transactionId, amount);
        
        return {
          statusCode: 200,
          body: JSON.stringify({
            message: 'Transaction created successfully',
            transaction,
            region: AWS_REGION,
            isPrimary: IS_PRIMARY_REGION
          })
        };
      }

      case 'read':
      case 'count': {
        const count = await getTransactionCount();
        
        return {
          statusCode: 200,
          body: JSON.stringify({
            transactionCount: count,
            region: AWS_REGION,
            isPrimary: IS_PRIMARY_REGION,
            timestamp: new Date().toISOString()
          })
        };
      }

      case 'list':
      case 'recent': {
        const limit = parseInt(event.limit) || 10;
        const transactions = await getRecentTransactions(limit);
        
        return {
          statusCode: 200,
          body: JSON.stringify({
            transactions,
            count: transactions.length,
            region: AWS_REGION,
            isPrimary: IS_PRIMARY_REGION,
            timestamp: new Date().toISOString()
          })
        };
      }

      default:
        return {
          statusCode: 400,
          body: JSON.stringify({
            error: `Unknown operation: ${operation}`,
            supportedOperations: ['create', 'write', 'read', 'count', 'list', 'recent'],
            region: AWS_REGION,
            isPrimary: IS_PRIMARY_REGION
          })
        };
    }
  } catch (error) {
    console.error('Error handling direct invocation', error);
    
    return {
      statusCode: 500,
      body: JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : 'Unknown error',
        region: AWS_REGION,
        isPrimary: IS_PRIMARY_REGION
      })
    };
  }
}

/**
 * Handles EventBridge events for cross-region coordination
 */
async function handleEventBridgeEvent(event: EventBridgeEvent<string, any>): Promise<void> {
  try {
    console.log('Processing EventBridge event', {
      source: event.source,
      detailType: event['detail-type'],
      region: event.region,
      detail: event.detail
    });

    // Process different event types
    switch (event['detail-type']) {
      case 'Transaction Created':
        console.log('Transaction created in another region', event.detail);
        // Could trigger additional processing, notifications, or analytics
        break;
        
      case 'Transaction Updated':
        console.log('Transaction updated in another region', event.detail);
        break;
        
      case 'Transaction Deleted':
        console.log('Transaction deleted in another region', event.detail);
        break;
        
      default:
        console.log('Unknown event type received', event['detail-type']);
    }
    
    // Publish acknowledgment event if needed
    if (event.detail?.requiresAcknowledgment) {
      await publishEvent('Event Processed', {
        transactionId: event.detail.transactionId || 'unknown',
        amount: event.detail.amount || 0,
        region: AWS_REGION,
        operation: 'read',
        timestamp: new Date().toISOString()
      });
    }
    
  } catch (error) {
    console.error('Error handling EventBridge event', error);
    throw error;
  }
}

/**
 * Main Lambda handler function
 */
export async function handler(event: any, context: Context): Promise<LambdaResponse | void> {
  console.log('Lambda function invoked', {
    requestId: context.requestId,
    functionName: context.functionName,
    region: AWS_REGION,
    isPrimary: IS_PRIMARY_REGION,
    event: JSON.stringify(event, null, 2)
  });

  try {
    // Check if this is an EventBridge event
    if (event.source === 'dsql.application' || event.source === 'eventbridge') {
      await handleEventBridgeEvent(event);
      return; // EventBridge events don't return HTTP responses
    }

    // Handle direct invocation (API Gateway, manual invocation, etc.)
    return await handleDirectInvocation(event);
    
  } catch (error) {
    console.error('Unhandled error in Lambda function', {
      error: error instanceof Error ? error.message : error,
      stack: error instanceof Error ? error.stack : undefined,
      event,
      context: {
        requestId: context.requestId,
        functionName: context.functionName,
        region: AWS_REGION
      }
    });

    // Return error response for direct invocations
    if (!event.source || (event.source !== 'dsql.application' && event.source !== 'eventbridge')) {
      return {
        statusCode: 500,
        body: JSON.stringify({
          error: 'Internal server error',
          message: error instanceof Error ? error.message : 'Unknown error',
          requestId: context.requestId,
          region: AWS_REGION,
          isPrimary: IS_PRIMARY_REGION
        })
      };
    }

    // Re-throw error for EventBridge events to trigger retry mechanisms
    throw error;
  }
}