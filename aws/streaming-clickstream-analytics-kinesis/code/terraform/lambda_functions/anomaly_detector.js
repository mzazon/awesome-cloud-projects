const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sns = new AWS.SNS();

const TABLE_PREFIX = '${table_prefix}';
const SNS_TOPIC_ARN = '${sns_topic_arn}';

exports.handler = async (event) => {
    console.log('Checking for anomalies in', event.Records.length, 'records');
    
    for (const record of event.Records) {
        try {
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            await checkForAnomalies(clickEvent);
            
        } catch (error) {
            console.error('Error processing record for anomaly detection:', error);
        }
    }
    
    return { statusCode: 200 };
};

async function checkForAnomalies(event) {
    // Check for suspicious patterns
    const checks = await Promise.all([
        checkHighFrequencyClicks(event),
        checkSuspiciousUserAgent(event),
        checkUnusualPageSequence(event)
    ]);
    
    const anomalies = checks.filter(check => check.isAnomaly);
    
    if (anomalies.length > 0) {
        await sendAlert(event, anomalies);
    }
}

async function checkHighFrequencyClicks(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `$${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `session_events_$${event.session_id}`,
            time_window: minute
        }
    };
    
    try {
        const result = await dynamodb.get(params).promise();
        const eventCount = result.Item ? result.Item.event_count : 0;
        
        // Flag if more than 50 events per minute from same session
        return {
            isAnomaly: eventCount > 50,
            type: 'high_frequency_clicks',
            details: `$${eventCount} events in one minute`
        };
    } catch (error) {
        console.error('Error checking high frequency clicks:', error);
        return { isAnomaly: false };
    }
}

async function checkSuspiciousUserAgent(event) {
    const suspiciousPatterns = ['bot', 'crawler', 'spider', 'scraper'];
    const userAgent = (event.user_agent || '').toLowerCase();
    
    const isSuspicious = suspiciousPatterns.some(pattern => 
        userAgent.includes(pattern)
    );
    
    return {
        isAnomaly: isSuspicious,
        type: 'suspicious_user_agent',
        details: event.user_agent
    };
}

async function checkUnusualPageSequence(event) {
    // Simple check for direct access to checkout without viewing products
    if (event.page_url && event.page_url.includes('/checkout')) {
        const params = {
            TableName: `$${TABLE_PREFIX}-session-metrics`,
            Key: { session_id: event.session_id }
        };
        
        try {
            const result = await dynamodb.get(params).promise();
            const eventCount = result.Item ? result.Item.event_count : 0;
            
            // Flag if going to checkout with very few page views
            return {
                isAnomaly: eventCount < 3,
                type: 'unusual_page_sequence',
                details: `Direct checkout access with only $${eventCount} page views`
            };
        } catch (error) {
            console.error('Error checking page sequence:', error);
            return { isAnomaly: false };
        }
    }
    
    return { isAnomaly: false };
}

async function sendAlert(event, anomalies) {
    if (!SNS_TOPIC_ARN) {
        console.log('SNS Topic ARN not configured, skipping alert');
        return;
    }
    
    const message = {
        timestamp: event.timestamp,
        session_id: event.session_id,
        anomalies: anomalies,
        event_details: event
    };
    
    const params = {
        TopicArn: SNS_TOPIC_ARN,
        Message: JSON.stringify(message, null, 2),
        Subject: 'Clickstream Anomaly Detected'
    };
    
    try {
        await sns.publish(params).promise();
        console.log('Alert sent for anomalies:', anomalies.map(a => a.type));
    } catch (error) {
        console.error('Error sending SNS alert:', error);
    }
}