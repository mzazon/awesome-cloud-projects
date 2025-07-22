/**
 * Kinesis Firehose Data Transformation Lambda
 * - Processes incoming log records
 * - Filters out records that don't match criteria
 * - Transforms and enriches valid records
 * - Returns both processed records and failed records
 */

// Configuration options from environment variables
const config = {
    // Minimum log level to process (logs below this level will be filtered out)
    // Values: DEBUG, INFO, WARN, ERROR
    minLogLevel: process.env.MIN_LOG_LEVEL || '${min_log_level}',
    
    // Whether to include timestamp in transformed data
    addProcessingTimestamp: process.env.ADD_PROCESSING_TIMESTAMP === 'true' || ${add_processing_timestamp},
    
    // Fields to remove from logs for privacy/compliance (PII, etc.)
    fieldsToRedact: JSON.parse(process.env.FIELDS_TO_REDACT || '${fields_to_redact}')
};

/**
 * Event structure expected in records:
 * {
 *   "timestamp": "2023-04-10T12:34:56Z",
 *   "level": "INFO|DEBUG|WARN|ERROR",
 *   "service": "service-name",
 *   "message": "Log message",
 *   // Additional fields...
 * }
 */
exports.handler = async (event, context) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    console.log('Configuration:', JSON.stringify(config, null, 2));
    
    const output = {
        records: []
    };
    
    // Process each record in the batch
    for (const record of event.records) {
        console.log('Processing record:', record.recordId);
        
        try {
            // Decode and parse the record data
            const buffer = Buffer.from(record.data, 'base64');
            const decodedData = buffer.toString('utf8');
            
            // Try to parse as JSON, fail gracefully if not valid JSON
            let parsedData;
            try {
                parsedData = JSON.parse(decodedData);
            } catch (e) {
                console.error('Invalid JSON in record:', decodedData);
                
                // Mark record as processing failed
                output.records.push({
                    recordId: record.recordId,
                    result: 'ProcessingFailed',
                    data: record.data
                });
                continue;
            }
            
            // Apply filtering logic - skip records with log level below minimum
            const logLevels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
            const currentLevelIndex = logLevels.indexOf(parsedData.level);
            const minLevelIndex = logLevels.indexOf(config.minLogLevel);
            
            if (parsedData.level && currentLevelIndex !== -1 && currentLevelIndex < minLevelIndex) {
                console.log(`Filtering out record with level $${parsedData.level}`);
                
                // Mark record as dropped
                output.records.push({
                    recordId: record.recordId,
                    result: 'Dropped', 
                    data: record.data
                });
                continue;
            }
            
            // Apply transformations
            
            // Add processing metadata
            if (config.addProcessingTimestamp) {
                parsedData.processedAt = new Date().toISOString();
            }
            
            // Add AWS request ID for traceability
            parsedData.lambdaRequestId = context.awsRequestId;
            
            // Add transformation metadata
            parsedData.transformationVersion = '1.0';
            parsedData.transformedBy = 'kinesis-firehose-lambda';
            
            // Redact any sensitive fields
            for (const field of config.fieldsToRedact) {
                if (parsedData[field]) {
                    parsedData[field] = '********';
                }
            }
            
            // Recursively redact nested objects
            function redactNestedFields(obj) {
                if (typeof obj === 'object' && obj !== null) {
                    for (const key in obj) {
                        if (config.fieldsToRedact.includes(key.toLowerCase())) {
                            obj[key] = '********';
                        } else if (typeof obj[key] === 'object') {
                            redactNestedFields(obj[key]);
                        }
                    }
                }
            }
            
            redactNestedFields(parsedData);
            
            // Add data quality metrics
            parsedData.dataQuality = {
                hasRequiredFields: !!(parsedData.timestamp && parsedData.level && parsedData.message),
                fieldCount: Object.keys(parsedData).length,
                recordSize: JSON.stringify(parsedData).length
            };
            
            // Convert transformed data back to string and encode as base64
            const transformedData = JSON.stringify(parsedData) + '\n';
            const encodedData = Buffer.from(transformedData).toString('base64');
            
            // Add transformed record to output
            output.records.push({
                recordId: record.recordId,
                result: 'Ok',
                data: encodedData
            });
            
        } catch (error) {
            console.error('Error processing record:', error);
            console.error('Error stack:', error.stack);
            
            // Mark record as processing failed
            output.records.push({
                recordId: record.recordId,
                result: 'ProcessingFailed',
                data: record.data
            });
        }
    }
    
    console.log('Processing complete, returning', output.records.length, 'records');
    
    // Log summary statistics
    const resultCounts = output.records.reduce((acc, record) => {
        acc[record.result] = (acc[record.result] || 0) + 1;
        return acc;
    }, {});
    
    console.log('Processing summary:', JSON.stringify(resultCounts));
    
    return output;
};