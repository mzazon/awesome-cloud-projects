const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    try {
        console.log('Processing blockchain event:', JSON.stringify(event, null, 2));
        
        // Extract blockchain event data
        const blockchainEvent = {
            eventType: event.eventType || 'UNKNOWN',
            agreementId: event.agreementId,
            organizationId: event.organizationId,
            dataId: event.dataId,
            timestamp: event.timestamp || Date.now(),
            metadata: event.metadata || {}
        };
        
        // Validate event data
        if (!blockchainEvent.agreementId) {
            throw new Error('Agreement ID is required');
        }
        
        // Store audit trail in DynamoDB
        const auditRecord = {
            TransactionId: `$${blockchainEvent.agreementId}-$${blockchainEvent.timestamp}`,
            Timestamp: blockchainEvent.timestamp,
            EventType: blockchainEvent.eventType,
            AgreementId: blockchainEvent.agreementId,
            OrganizationId: blockchainEvent.organizationId,
            DataId: blockchainEvent.dataId,
            Metadata: blockchainEvent.metadata
        };
        
        await dynamodb.put({
            TableName: process.env.TABLE_NAME,
            Item: auditRecord
        }).promise();
        
        // Process different event types
        switch (blockchainEvent.eventType) {
            case 'DataSharingAgreementCreated':
                await processAgreementCreated(blockchainEvent);
                break;
            case 'OrganizationJoinedAgreement':
                await processOrganizationJoined(blockchainEvent);
                break;
            case 'DataShared':
                await processDataShared(blockchainEvent);
                break;
            case 'DataAccessed':
                await processDataAccessed(blockchainEvent);
                break;
            default:
                console.log(`Unknown event type: $${blockchainEvent.eventType}`);
        }
        
        // Send notification via EventBridge
        await eventbridge.putEvents({
            Entries: [{
                Source: 'cross-org.blockchain',
                DetailType: blockchainEvent.eventType,
                Detail: JSON.stringify(blockchainEvent)
            }]
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Blockchain event processed successfully',
                eventType: blockchainEvent.eventType,
                agreementId: blockchainEvent.agreementId
            })
        };
        
    } catch (error) {
        console.error('Error processing blockchain event:', error);
        throw error;
    }
};

async function processAgreementCreated(event) {
    console.log(`Processing agreement creation: $${event.agreementId}`);
    
    // Create metadata record in S3
    const metadata = {
        agreementId: event.agreementId,
        creator: event.organizationId,
        createdAt: new Date(event.timestamp).toISOString(),
        status: 'ACTIVE',
        participants: [event.organizationId]
    };
    
    await s3.putObject({
        Bucket: process.env.BUCKET_NAME,
        Key: `agreements/$${event.agreementId}/metadata.json`,
        Body: JSON.stringify(metadata, null, 2),
        ContentType: 'application/json'
    }).promise();
}

async function processOrganizationJoined(event) {
    console.log(`Processing organization join: $${event.organizationId} to $${event.agreementId}`);
    
    // Update participant notification
    // In production, this would send targeted notifications to all participants
}

async function processDataShared(event) {
    console.log(`Processing data sharing: $${event.dataId} in $${event.agreementId}`);
    
    // Validate data integrity and compliance
    // In production, this would perform additional validation checks
}

async function processDataAccessed(event) {
    console.log(`Processing data access: $${event.dataId} by $${event.organizationId}`);
    
    // Log access for compliance and audit purposes
    // In production, this would trigger additional compliance checks
}