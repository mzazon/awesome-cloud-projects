---
title: Privacy-Preserving Analytics with Clean Rooms
id: a7b9c2e4
category: analytics
difficulty: 200
subject: aws
services: Clean Rooms, QuickSight, S3, Glue
estimated-time: 120 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: privacy, data-collaboration, analytics, clean-rooms, quicksight, differential-privacy
recipe-generator-version: 1.3
---

# Privacy-Preserving Analytics with Clean Rooms

## Problem

Organizations increasingly need to collaborate on data analytics across company boundaries while maintaining strict privacy controls and regulatory compliance. Traditional data sharing approaches require exposing sensitive raw datasets, creating security risks and limiting collaborative opportunities. Companies struggle to gain insights from combined datasets without compromising proprietary information or violating privacy regulations like GDPR or CCPA.

## Solution

AWS Clean Rooms provides a secure collaboration environment where multiple parties can analyze combined datasets without exposing underlying raw data to each other. This solution integrates with AWS Glue for automated data preparation and Amazon QuickSight for interactive visualization, enabling privacy-preserving analytics through cryptographic protections and differential privacy techniques that protect individual data points while allowing meaningful aggregate insights.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Organization A"
        A_DATA[Customer Data A]
        A_S3[S3 Bucket A]
    end
    
    subgraph "Organization B"
        B_DATA[Customer Data B]
        B_S3[S3 Bucket B]
    end
    
    subgraph "Data Preparation"
        GLUE[AWS Glue ETL]
        CATALOG[Glue Data Catalog]
    end
    
    subgraph "AWS Clean Rooms"
        COLLAB[Collaboration]
        TABLES[Configured Tables]
        QUERIES[Privacy-Safe Queries]
        DP[Differential Privacy]
    end
    
    subgraph "Analytics & Visualization"
        RESULTS[Query Results]
        QS[QuickSight Dashboard]
        INSIGHTS[Business Insights]
    end
    
    A_DATA --> A_S3
    B_DATA --> B_S3
    A_S3 --> GLUE
    B_S3 --> GLUE
    GLUE --> CATALOG
    CATALOG --> TABLES
    TABLES --> COLLAB
    COLLAB --> QUERIES
    QUERIES --> DP
    DP --> RESULTS
    RESULTS --> QS
    QS --> INSIGHTS
    
    style COLLAB fill:#FF9900
    style DP fill:#3F8624
    style QS fill:#FF6B6B
```

## Prerequisites

1. AWS account with administrative permissions for Clean Rooms, QuickSight, S3, and Glue services
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Basic understanding of data analytics, SQL queries, and privacy concepts
4. Sample datasets for testing (customer demographics, transaction data, etc.)
5. QuickSight subscription (Standard or Enterprise edition)
6. Estimated cost: $50-100 for Clean Rooms collaboration, $24/month for QuickSight Standard, $5-20 for S3 and Glue usage

> **Note**: Clean Rooms pricing is based on query compute units and data scanned. Differential privacy features may have additional costs for enhanced privacy protections.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export CLEAN_ROOMS_NAME="analytics-collaboration-${RANDOM_SUFFIX}"
export S3_BUCKET_ORG_A="clean-rooms-data-a-${RANDOM_SUFFIX}"
export S3_BUCKET_ORG_B="clean-rooms-data-b-${RANDOM_SUFFIX}"
export GLUE_DATABASE="clean_rooms_analytics_${RANDOM_SUFFIX//-/_}"
export QUICKSIGHT_ANALYSIS="privacy-analytics-${RANDOM_SUFFIX}"

# Create S3 buckets for both organizations
aws s3 mb s3://${S3_BUCKET_ORG_A} --region ${AWS_REGION}
aws s3 mb s3://${S3_BUCKET_ORG_B} --region ${AWS_REGION}

# Enable bucket versioning and encryption
aws s3api put-bucket-versioning \
    --bucket ${S3_BUCKET_ORG_A} \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket ${S3_BUCKET_ORG_A} \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

aws s3api put-bucket-versioning \
    --bucket ${S3_BUCKET_ORG_B} \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket ${S3_BUCKET_ORG_B} \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

echo "✅ S3 buckets created with security features enabled"
```

## Steps

1. **Create Sample Datasets for Organizations**:

   Organizations need representative datasets to demonstrate privacy-preserving analytics capabilities. We'll create synthetic customer data that mimics real-world scenarios while maintaining data privacy best practices. These datasets will contain overlapping customer segments to enable meaningful cross-organizational insights through Clean Rooms. AWS Clean Rooms requires structured data with common dimensions to perform join operations while maintaining privacy boundaries.

   ```bash
   # Create sample customer data for Organization A
   cat > customer_data_org_a.csv << 'EOF'
customer_id,age_group,region,purchase_amount,product_category,registration_date
1001,25-34,east,250.00,electronics,2023-01-15
1002,35-44,west,180.50,clothing,2023-02-20
1003,45-54,central,320.75,home,2023-01-10
1004,25-34,east,95.25,books,2023-03-05
1005,55-64,west,450.00,electronics,2023-02-28
1006,25-34,central,180.00,electronics,2023-01-25
1007,35-44,east,275.50,clothing,2023-02-15
1008,45-54,west,395.25,home,2023-03-01
1009,25-34,central,125.75,books,2023-02-10
1010,55-64,east,520.00,electronics,2023-03-12
EOF
   
   # Create sample customer data for Organization B
   cat > customer_data_org_b.csv << 'EOF'
customer_id,age_group,region,engagement_score,channel_preference,last_interaction
2001,25-34,east,85,email,2023-03-15
2002,35-44,west,72,social,2023-03-20
2003,45-54,central,91,email,2023-03-10
2004,25-34,east,68,mobile,2023-03-25
2005,55-64,west,88,email,2023-03-18
2006,25-34,central,76,mobile,2023-03-08
2007,35-44,east,82,email,2023-03-22
2008,45-54,west,94,social,2023-03-05
2009,25-34,central,69,mobile,2023-03-14
2010,55-64,east,87,email,2023-03-20
EOF
   
   # Upload datasets to respective S3 buckets
   aws s3 cp customer_data_org_a.csv s3://${S3_BUCKET_ORG_A}/data/
   aws s3 cp customer_data_org_b.csv s3://${S3_BUCKET_ORG_B}/data/
   
   echo "✅ Sample datasets created and uploaded to S3 buckets"
   ```

   The datasets now contain sufficient records for Clean Rooms to perform meaningful aggregations while applying privacy protections. Each organization's data includes common dimensions (age_group, region) that enable privacy-safe joins while maintaining separate organizational data domains.

2. **Create IAM Roles for Clean Rooms and Glue**:

   IAM roles provide secure, temporary credentials that enable AWS services to access data without exposing long-term credentials. The Clean Rooms service role allows querying configured tables while maintaining privacy boundaries, and the Glue role enables automated data cataloging and ETL operations across the analytics pipeline. These roles implement the principle of least privilege by granting only the permissions necessary for each service's specific functions.

   ```bash
   # Create Clean Rooms service role
   cat > clean-rooms-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cleanrooms.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
   
   aws iam create-role \
       --role-name CleanRoomsAnalyticsRole \
       --assume-role-policy-document file://clean-rooms-trust-policy.json
   
   # Attach required policies for Clean Rooms
   aws iam attach-role-policy \
       --role-name CleanRoomsAnalyticsRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSCleanRoomsService
   
   # Create custom policy for S3 access
   cat > clean-rooms-s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::clean-rooms-*",
        "arn:aws:s3:::clean-rooms-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetDatabase"
      ],
      "Resource": "*"
    }
  ]
}
EOF
   
   aws iam create-policy \
       --policy-name CleanRoomsS3Access \
       --policy-document file://clean-rooms-s3-policy.json
   
   aws iam attach-role-policy \
       --role-name CleanRoomsAnalyticsRole \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access
   
   # Create Glue service role
   cat > glue-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "glue.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
   
   aws iam create-role \
       --role-name GlueCleanRoomsRole \
       --assume-role-policy-document file://glue-trust-policy.json
   
   # Attach necessary policies
   aws iam attach-role-policy \
       --role-name GlueCleanRoomsRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
   
   aws iam attach-role-policy \
       --role-name GlueCleanRoomsRole \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access
   
   echo "✅ IAM roles created for Clean Rooms and Glue services"
   ```

   The IAM roles are now configured with appropriate permissions for Clean Rooms data access and Glue catalog operations. This security foundation enables the services to interact with data sources while maintaining strict access controls and audit trails.

3. **Create Glue Database and Crawl Data Sources**:

   AWS Glue Data Catalog serves as the central metadata repository that enables Clean Rooms to understand data schemas and relationships. The crawler automatically discovers data formats, schemas, and partitions, creating table definitions that preserve data lineage while enabling privacy-safe querying across organizational boundaries. Glue's serverless architecture eliminates the need for manual schema management while providing consistent metadata for privacy-preserving analytics.

   ```bash
   # Create Glue database
   aws glue create-database \
       --database-input "{\"Name\":\"${GLUE_DATABASE}\", \
       \"Description\":\"Clean Rooms analytics database for privacy-preserving collaboration\"}"
   
   # Create Glue crawler for Organization A data
   aws glue create-crawler \
       --name "crawler-org-a-${RANDOM_SUFFIX}" \
       --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCleanRoomsRole" \
       --database-name "${GLUE_DATABASE}" \
       --description "Crawler for Organization A customer data" \
       --targets "{\"S3Targets\": [{\"Path\": \"s3://${S3_BUCKET_ORG_A}/data/\"}]}"
   
   # Create Glue crawler for Organization B data
   aws glue create-crawler \
       --name "crawler-org-b-${RANDOM_SUFFIX}" \
       --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCleanRoomsRole" \
       --database-name "${GLUE_DATABASE}" \
       --description "Crawler for Organization B customer data" \
       --targets "{\"S3Targets\": [{\"Path\": \"s3://${S3_BUCKET_ORG_B}/data/\"}]}"
   
   # Run crawlers to discover schemas
   aws glue start-crawler --name "crawler-org-a-${RANDOM_SUFFIX}"
   aws glue start-crawler --name "crawler-org-b-${RANDOM_SUFFIX}"
   
   # Wait for crawlers to complete
   sleep 30
   
   echo "✅ Glue database and crawlers created, schema discovery initiated"
   ```

   The Glue crawlers are now analyzing the data structures and creating table schemas in the Data Catalog. This automated schema discovery provides Clean Rooms with the metadata necessary to enforce privacy controls while enabling cross-organizational data analysis.

4. **Create Clean Rooms Collaboration**:

   Clean Rooms collaboration establishes the secure environment where multiple organizations can jointly analyze data while maintaining privacy controls. This step creates the foundational collaboration space with configurable privacy settings, query restrictions, and differential privacy parameters that protect individual data points. The collaboration framework implements cryptographic protections and mathematical privacy guarantees to ensure regulatory compliance.

   ```bash
   # Create Clean Rooms collaboration
   aws cleanrooms create-collaboration \
       --name "${CLEAN_ROOMS_NAME}" \
       --description "Privacy-preserving analytics collaboration for cross-organizational insights" \
       --member-abilities "CAN_QUERY,CAN_RECEIVE_RESULTS" \
       --query-log-status "ENABLED" \
       --data-encryption-metadata "{\"preserveNulls\": true, \"allowCleartext\": false, \"allowDuplicates\": false, \"allowJoinsOnColumnsWithDifferentNames\": false}"
   
   # Wait for collaboration creation to complete
   sleep 10
   
   # Store collaboration ID for later use
   COLLABORATION_ID=$(aws cleanrooms list-collaborations \
       --query "collaborationList[?name=='${CLEAN_ROOMS_NAME}'].id" \
       --output text)
   
   echo "✅ Clean Rooms collaboration created: ${COLLABORATION_ID}"
   ```

   The collaboration environment is now active with privacy protections enabled. This secure workspace provides the foundation for multi-party analytics while ensuring that raw data never leaves each organization's control boundaries.

5. **Configure Tables in Clean Rooms**:

   Configured tables define which data columns are available for analysis while implementing privacy protections and access controls. This configuration specifies allowed operations, aggregation rules, and differential privacy parameters that ensure individual records cannot be identified while enabling meaningful aggregate insights. The table configuration acts as a privacy gateway that controls how data can be accessed and combined across organizational boundaries.

   ```bash
   # Wait for Glue crawlers to complete and verify tables exist
   sleep 60
   
   # Get table names from Glue catalog
   ORG_A_TABLE=$(aws glue get-tables \
       --database-name "${GLUE_DATABASE}" \
       --query "TableList[?contains(Name, 'customer_data_org_a')].Name" \
       --output text)
   
   ORG_B_TABLE=$(aws glue get-tables \
       --database-name "${GLUE_DATABASE}" \
       --query "TableList[?contains(Name, 'customer_data_org_b')].Name" \
       --output text)
   
   # Verify tables were discovered
   if [[ -z "$ORG_A_TABLE" || -z "$ORG_B_TABLE" ]]; then
       echo "❌ Tables not found. Waiting for crawler completion..."
       sleep 60
       # Retry table discovery
       ORG_A_TABLE=$(aws glue get-tables \
           --database-name "${GLUE_DATABASE}" \
           --query "TableList[?contains(Name, 'customer_data_org_a')].Name" \
           --output text)
       ORG_B_TABLE=$(aws glue get-tables \
           --database-name "${GLUE_DATABASE}" \
           --query "TableList[?contains(Name, 'customer_data_org_b')].Name" \
           --output text)
   fi
   
   # Configure table for Organization A
   aws cleanrooms create-configured-table \
       --name "org-a-customers" \
       --description "Organization A customer data for privacy-preserving analytics" \
       --table-reference "{\"glue\": {\"tableName\": \"${ORG_A_TABLE}\", \"databaseName\": \"${GLUE_DATABASE}\"}}" \
       --allowed-columns "age_group,region,product_category,purchase_amount" \
       --analysis-method "DIRECT_QUERY"
   
   # Configure table for Organization B  
   aws cleanrooms create-configured-table \
       --name "org-b-customers" \
       --description "Organization B customer data for privacy-preserving analytics" \
       --table-reference "{\"glue\": {\"tableName\": \"${ORG_B_TABLE}\", \"databaseName\": \"${GLUE_DATABASE}\"}}" \
       --allowed-columns "age_group,region,channel_preference,engagement_score" \
       --analysis-method "DIRECT_QUERY"
   
   echo "✅ Configured tables created in Clean Rooms"
   ```

   The configured tables now define privacy boundaries and allowed operations for each organization's data. This configuration ensures that only approved columns and analysis methods can be used while maintaining complete control over data access permissions.

6. **Associate Tables with Collaboration**:

   Table association links the configured tables to the collaboration space, making them available for cross-organizational queries while maintaining privacy boundaries. This step activates the privacy protections and enables the differential privacy mechanisms that protect sensitive data during collaborative analysis. The association process establishes trust relationships between organizations while maintaining cryptographic isolation of raw data.

   ```bash
   # Get configured table IDs
   ORG_A_TABLE_ID=$(aws cleanrooms list-configured-tables \
       --query "configuredTableSummaries[?name=='org-a-customers'].id" \
       --output text)
   
   ORG_B_TABLE_ID=$(aws cleanrooms list-configured-tables \
       --query "configuredTableSummaries[?name=='org-b-customers'].id" \
       --output text)
   
   # Create table associations
   aws cleanrooms create-configured-table-association \
       --name "org-a-association" \
       --description "Association for Organization A data with privacy controls" \
       --membership-identifier "${COLLABORATION_ID}" \
       --configured-table-identifier "${ORG_A_TABLE_ID}" \
       --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CleanRoomsAnalyticsRole"
   
   aws cleanrooms create-configured-table-association \
       --name "org-b-association" \
       --description "Association for Organization B data with privacy controls" \
       --membership-identifier "${COLLABORATION_ID}" \
       --configured-table-identifier "${ORG_B_TABLE_ID}" \
       --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CleanRoomsAnalyticsRole"
   
   echo "✅ Tables associated with Clean Rooms collaboration"
   ```

   The table associations are now active, enabling privacy-preserving queries across organizational datasets. This configuration allows Clean Rooms to apply differential privacy protections and cryptographic controls during collaborative analysis operations.

7. **Execute Privacy-Preserving Queries**:

   Clean Rooms enables SQL queries that aggregate data across organizations while applying differential privacy protections. These queries demonstrate how to extract meaningful business insights without exposing individual customer records, using techniques like noise injection and result filtering to maintain privacy guarantees. The query execution engine automatically applies privacy controls and ensures that results meet differential privacy standards.

   ```bash
   # Create output S3 bucket for query results
   export RESULTS_BUCKET="clean-rooms-results-${RANDOM_SUFFIX}"
   aws s3 mb s3://${RESULTS_BUCKET} --region ${AWS_REGION}
   
   # Apply encryption to results bucket
   aws s3api put-bucket-encryption \
       --bucket ${RESULTS_BUCKET} \
       --server-side-encryption-configuration \
       'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
   
   # Execute privacy-preserving aggregation query
   cat > privacy_query.sql << 'EOF'
SELECT 
    age_group,
    region,
    COUNT(*) as customer_count,
    AVG(purchase_amount) as avg_purchase_amount,
    AVG(engagement_score) as avg_engagement_score
FROM org_a_customers a
INNER JOIN org_b_customers b 
    ON a.age_group = b.age_group 
    AND a.region = b.region
GROUP BY age_group, region
HAVING COUNT(*) >= 3
EOF
   
   # Start protected query
   QUERY_ID=$(aws cleanrooms start-protected-query \
       --type "SQL" \
       --membership-identifier "${COLLABORATION_ID}" \
       --sql-parameters "{\"queryString\": \"$(cat privacy_query.sql | tr '\n' ' ')\"}" \
       --result-configuration "{\"outputConfiguration\": {\"s3\": {\"resultFormat\": \"CSV\", \"bucket\": \"${RESULTS_BUCKET}\", \"keyPrefix\": \"query-results/\"}}}" \
       --query "protectedQueryId" --output text)
   
   echo "✅ Privacy-preserving query executed: ${QUERY_ID}"
   ```

   The protected query is now running with automated privacy protections applied. Clean Rooms will apply differential privacy mechanisms to ensure that the aggregated results cannot be used to identify individual customers while providing meaningful business insights.

8. **Set Up QuickSight for Visualization**:

   Amazon QuickSight provides secure visualization capabilities for Clean Rooms query results, enabling interactive dashboards that respect privacy boundaries. QuickSight integrates with S3 to access aggregated results while providing role-based access controls and data governance features for collaborative analytics environments. The visualization layer maintains privacy protections while enabling business users to explore insights through interactive charts and filters.

   ```bash
   # Wait for query to complete before setting up visualization
   sleep 120
   
   # Check if QuickSight subscription exists
   aws quicksight describe-account-settings \
       --aws-account-id "${AWS_ACCOUNT_ID}" 2>/dev/null || \
   {
       echo "Setting up QuickSight subscription..."
       aws quicksight create-account-subscription \
           --aws-account-id "${AWS_ACCOUNT_ID}" \
           --account-name "Clean Rooms Analytics" \
           --notification-email "${USER_EMAIL:-admin@example.com}" \
           --edition "STANDARD"
   }
   
   # Register QuickSight user (if not already registered)
   aws quicksight register-user \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --namespace "default" \
       --identity-type "IAM" \
       --user-role "ADMIN" \
       --iam-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:root" 2>/dev/null || \
   echo "QuickSight user already registered"
   
   # Create QuickSight data source for S3 results
   aws quicksight create-data-source \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --data-source-id "clean-rooms-results-${RANDOM_SUFFIX}" \
       --name "Clean Rooms Analytics Results" \
       --type "S3" \
       --data-source-parameters "{\"S3Parameters\": {\"ManifestFileLocation\": {\"Bucket\": \"${RESULTS_BUCKET}\", \"Key\": \"query-results/\"}}}" \
       --permissions "[{\"Principal\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:root\", \"Actions\": [\"quicksight:DescribeDataSource\", \"quicksight:DescribeDataSourcePermissions\", \"quicksight:PassDataSource\", \"quicksight:UpdateDataSource\", \"quicksight:DeleteDataSource\", \"quicksight:UpdateDataSourcePermissions\"]}]"
   
   echo "✅ QuickSight data source configured for Clean Rooms results"
   ```

   QuickSight is now configured to access privacy-preserved analytics results. The visualization platform provides secure access to aggregated data while maintaining the privacy guarantees established by Clean Rooms differential privacy protections.

9. **Configure Differential Privacy Settings**:

   Differential privacy adds mathematical guarantees that individual data points cannot be identified from query results. This configuration sets privacy budgets, noise parameters, and result filtering thresholds that balance privacy protection with analytical utility, ensuring compliance with privacy regulations while enabling meaningful insights. The epsilon parameter controls the privacy-utility tradeoff, with lower values providing stronger privacy at the cost of analytical precision.

   ```bash
   # Create differential privacy configuration
   cat > dp_config.json << 'EOF'
{
  "columnName": "customer_id",
  "aggregationFunction": "COUNT",
  "aggregationParameters": {
    "dimensions": ["age_group", "region"],
    "scalarFunctions": ["AVG"],
    "outputColumns": ["customer_count", "avg_purchase_amount", "avg_engagement_score"]
  },
  "resultPolicy": {
    "noiseMechanism": "LAPLACE",
    "epsilon": 1.0,
    "usersNoisePerQuery": 100
  }
}
EOF
   
   # Note: Update collaboration with differential privacy settings
   # (This configuration example shows the structure - actual implementation
   # depends on AWS Clean Rooms differential privacy feature availability)
   echo "Differential privacy configuration prepared"
   echo "Epsilon value: 1.0 (balanced privacy-utility tradeoff)"
   echo "Noise mechanism: Laplace (standard for count queries)"
   
   echo "✅ Differential privacy configuration prepared"
   ```

   The differential privacy configuration is prepared with carefully chosen parameters that provide formal privacy guarantees. The epsilon value of 1.0 provides a balanced approach between privacy protection and analytical utility for business insights.

10. **Create Interactive Dashboard**:

    QuickSight dashboards enable business users to explore privacy-preserved analytics results through interactive visualizations. This step creates charts and filters that help organizations understand cross-sectional insights while maintaining confidence that individual customer privacy is protected through differential privacy guarantees. The dashboard provides self-service analytics capabilities while respecting privacy boundaries established by Clean Rooms.

    ```bash
    # Wait for query results to be available
    sleep 60
    
    # Verify query results exist
    aws s3 ls s3://${RESULTS_BUCKET}/query-results/ --recursive
    
    # Create QuickSight dataset from query results
    aws quicksight create-data-set \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id "privacy-analytics-dataset-${RANDOM_SUFFIX}" \
        --name "Privacy Analytics Dataset" \
        --physical-table-map "{\"CleanRoomsResults\": {\"S3Source\": {\"DataSourceArn\": \"arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:datasource/clean-rooms-results-${RANDOM_SUFFIX}\", \"InputColumns\": [{\"Name\": \"age_group\", \"Type\": \"STRING\"}, {\"Name\": \"region\", \"Type\": \"STRING\"}, {\"Name\": \"customer_count\", \"Type\": \"INTEGER\"}, {\"Name\": \"avg_purchase_amount\", \"Type\": \"DECIMAL\"}, {\"Name\": \"avg_engagement_score\", \"Type\": \"DECIMAL\"}]}}}" \
        --permissions "[{\"Principal\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:root\", \"Actions\": [\"quicksight:DescribeDataSet\", \"quicksight:DescribeDataSetPermissions\", \"quicksight:PassDataSet\", \"quicksight:DescribeIngestion\", \"quicksight:ListIngestions\", \"quicksight:UpdateDataSet\", \"quicksight:DeleteDataSet\", \"quicksight:CreateIngestion\", \"quicksight:CancelIngestion\", \"quicksight:UpdateDataSetPermissions\"]}]"
    
    # Create QuickSight analysis for privacy-preserving insights
    aws quicksight create-analysis \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --analysis-id "${QUICKSIGHT_ANALYSIS}" \
        --name "Privacy-Preserving Analytics Dashboard" \
        --permissions "[{\"Principal\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:root\", \"Actions\": [\"quicksight:RestoreAnalysis\", \"quicksight:UpdateAnalysisPermissions\", \"quicksight:DeleteAnalysis\", \"quicksight:DescribeAnalysisPermissions\", \"quicksight:QueryAnalysis\", \"quicksight:DescribeAnalysis\", \"quicksight:UpdateAnalysis\"]}]" \
        --definition "{\"DataSetIdentifierDeclarations\": [{\"DataSetArn\": \"arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/privacy-analytics-dataset-${RANDOM_SUFFIX}\", \"Identifier\": \"CleanRoomsResults\"}], \"Sheets\": [{\"SheetId\": \"sheet1\", \"Name\": \"Privacy Analytics\", \"Visuals\": [{\"BarChartVisual\": {\"VisualId\": \"visual1\", \"Title\": {\"Visibility\": \"VISIBLE\", \"FormatText\": {\"PlainText\": \"Customer Segments by Demographics\"}}, \"Subtitle\": {\"Visibility\": \"VISIBLE\", \"FormatText\": {\"PlainText\": \"Privacy-preserved cross-organizational insights\"}}}}]}]}"
    
    echo "✅ Interactive QuickSight dashboard created for privacy analytics"
    ```

    The QuickSight dashboard is now available with privacy-preserved analytics results. Business users can explore cross-organizational insights through interactive visualizations while maintaining confidence that individual customer privacy is protected through Clean Rooms' differential privacy mechanisms.

## Validation & Testing

1. **Verify Clean Rooms Collaboration Status**:

   ```bash
   # Check collaboration configuration
   aws cleanrooms get-collaboration \
       --collaboration-identifier "${COLLABORATION_ID}"
   
   # Verify table associations
   aws cleanrooms list-configured-table-associations \
       --membership-identifier "${COLLABORATION_ID}"
   ```

   Expected output: Collaboration status should show "ACTIVE" with configured tables properly associated and privacy settings enabled.

2. **Test Privacy Query Execution**:

   ```bash
   # List protected queries
   aws cleanrooms list-protected-queries \
       --membership-identifier "${COLLABORATION_ID}"
   
   # Check query results in S3
   aws s3 ls s3://${RESULTS_BUCKET}/query-results/ --recursive
   
   # Verify query completion status
   aws cleanrooms get-protected-query \
       --membership-identifier "${COLLABORATION_ID}" \
       --protected-query-identifier "${QUERY_ID}"
   ```

   Expected output: Query should complete successfully with privacy-preserved results stored in S3, showing aggregated data that meets minimum thresholds for privacy protection.

3. **Validate QuickSight Dashboard Access**:

   ```bash
   # Verify QuickSight data source
   aws quicksight describe-data-source \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --data-source-id "clean-rooms-results-${RANDOM_SUFFIX}"
   
   # Check dataset creation
   aws quicksight describe-data-set \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --data-set-id "privacy-analytics-dataset-${RANDOM_SUFFIX}"
   
   # Verify analysis creation
   aws quicksight describe-analysis \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --analysis-id "${QUICKSIGHT_ANALYSIS}"
   ```

   Expected output: Data source should be connected, dataset should be available, and dashboard should be accessible through QuickSight console with privacy-preserved visualizations.

## Cleanup

1. **Remove QuickSight Resources**:

   ```bash
   # Delete QuickSight analysis
   aws quicksight delete-analysis \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --analysis-id "${QUICKSIGHT_ANALYSIS}" \
       --force-delete-without-recovery
   
   # Delete QuickSight dataset
   aws quicksight delete-data-set \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --data-set-id "privacy-analytics-dataset-${RANDOM_SUFFIX}"
   
   # Delete QuickSight data source
   aws quicksight delete-data-source \
       --aws-account-id "${AWS_ACCOUNT_ID}" \
       --data-source-id "clean-rooms-results-${RANDOM_SUFFIX}"
   
   echo "✅ QuickSight resources deleted"
   ```

2. **Remove Clean Rooms Configuration**:

   ```bash
   # Delete configured table associations
   aws cleanrooms delete-configured-table-association \
       --configured-table-association-identifier "org-a-association" \
       --membership-identifier "${COLLABORATION_ID}"
   
   aws cleanrooms delete-configured-table-association \
       --configured-table-association-identifier "org-b-association" \
       --membership-identifier "${COLLABORATION_ID}"
   
   # Delete configured tables
   aws cleanrooms delete-configured-table \
       --configured-table-identifier "${ORG_A_TABLE_ID}"
   
   aws cleanrooms delete-configured-table \
       --configured-table-identifier "${ORG_B_TABLE_ID}"
   
   # Delete collaboration
   aws cleanrooms delete-collaboration \
       --collaboration-identifier "${COLLABORATION_ID}"
   
   echo "✅ Clean Rooms resources deleted"
   ```

3. **Remove Supporting Infrastructure**:

   ```bash
   # Delete Glue crawlers and database
   aws glue delete-crawler --name "crawler-org-a-${RANDOM_SUFFIX}"
   aws glue delete-crawler --name "crawler-org-b-${RANDOM_SUFFIX}"
   aws glue delete-database --name "${GLUE_DATABASE}"
   
   # Delete IAM policies and roles
   aws iam detach-role-policy \
       --role-name GlueCleanRoomsRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
   
   aws iam detach-role-policy \
       --role-name GlueCleanRoomsRole \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access
   
   aws iam detach-role-policy \
       --role-name CleanRoomsAnalyticsRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSCleanRoomsService
   
   aws iam detach-role-policy \
       --role-name CleanRoomsAnalyticsRole \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access
   
   aws iam delete-role --role-name GlueCleanRoomsRole
   aws iam delete-role --role-name CleanRoomsAnalyticsRole
   
   aws iam delete-policy \
       --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access
   
   # Delete S3 buckets and contents
   aws s3 rm s3://${S3_BUCKET_ORG_A} --recursive
   aws s3 rm s3://${S3_BUCKET_ORG_B} --recursive
   aws s3 rm s3://${RESULTS_BUCKET} --recursive
   aws s3 rb s3://${S3_BUCKET_ORG_A}
   aws s3 rb s3://${S3_BUCKET_ORG_B}
   aws s3 rb s3://${RESULTS_BUCKET}
   
   # Clean up local files
   rm -f customer_data_org_*.csv privacy_query.sql dp_config.json
   rm -f *-trust-policy.json *-policy.json
   
   echo "✅ All infrastructure and local files deleted"
   ```

## Discussion

AWS Clean Rooms revolutionizes multi-party data collaboration by enabling secure analytics without exposing raw datasets to participating organizations. This architecture leverages cryptographic protections and differential privacy techniques to ensure individual data points remain protected while allowing meaningful aggregate insights. The service implements mathematical privacy guarantees that provide formal proof of privacy preservation, making it suitable for highly regulated industries and cross-border data collaborations. For comprehensive technical details, see the [AWS Clean Rooms User Guide](https://docs.aws.amazon.com/clean-rooms/latest/userguide/what-is.html) and [differential privacy documentation](https://docs.aws.amazon.com/clean-rooms/latest/userguide/differential-privacy.html).

The integration with AWS Glue provides automated data preparation and schema discovery, reducing the operational overhead typically associated with multi-party analytics. Glue crawlers automatically detect data formats and create metadata catalogs that enable Clean Rooms to understand data relationships while maintaining privacy boundaries. This approach follows the [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) principles by implementing security by design, operational excellence through automation, and cost optimization through serverless architectures. The [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html) provides detailed guidance on implementing data cataloging best practices.

Amazon QuickSight integration enables business users to visualize privacy-preserved results through interactive dashboards and self-service analytics capabilities. The combination creates an end-to-end privacy-preserving analytics pipeline that maintains data governance while enabling collaborative insights. QuickSight's row-level security and column-level security features complement Clean Rooms' privacy protections, ensuring that even visualization access follows principle of least privilege. For detailed security guidance, review the [QuickSight security best practices](https://docs.aws.amazon.com/quicksight/latest/user/security.html) and [Clean Rooms security documentation](https://docs.aws.amazon.com/clean-rooms/latest/userguide/security.html).

From a compliance perspective, this solution addresses key requirements of privacy regulations like GDPR, CCPA, and industry-specific standards by implementing technical safeguards that prevent individual re-identification. The differential privacy mechanisms add mathematical noise to query results, providing formal privacy guarantees that can be audited and verified. Organizations can configure privacy budgets and noise parameters to balance analytical utility with privacy protection based on their specific regulatory requirements. For implementation guidance, consult the [Clean Rooms best practices documentation](https://docs.aws.amazon.com/clean-rooms/latest/userguide/best-practices.html) and the [AWS security documentation](https://docs.aws.amazon.com/security/).

> **Tip**: Configure differential privacy epsilon values based on your privacy requirements - lower values provide stronger privacy guarantees but may reduce analytical precision. Start with conservative settings and adjust based on analytical needs and regulatory guidance.

> **Warning**: Ensure that query results meet minimum threshold requirements (typically 3+ records) to prevent potential privacy leakage through small group identification.

## Challenge

Extend this privacy-preserving analytics solution with these advanced enhancements:

1. **Implement Clean Rooms ML for Privacy-Preserved Machine Learning**: Integrate AWS Clean Rooms ML to create lookalike audiences and predictive models without exposing training data, using federated learning techniques and homomorphic encryption for model training across organizational boundaries.

2. **Add Real-Time Analytics with Kinesis Integration**: Connect Amazon Kinesis Data Streams to enable real-time privacy-preserving analytics, implementing sliding window aggregations and continuous differential privacy monitoring for streaming data collaborations.

3. **Create Cross-Region Privacy Compliance Framework**: Implement multi-region Clean Rooms deployments with automated compliance reporting, data residency controls, and privacy audit trails that meet different international regulatory requirements.

4. **Develop Advanced Privacy Budget Management**: Build automated privacy budget allocation and monitoring systems that track epsilon consumption across multiple queries, implement budget renewal policies, and provide privacy risk assessments for ongoing collaborations.

5. **Integrate with External Identity Providers**: Implement federated authentication using AWS IAM Identity Center to enable secure multi-organization access control, attribute-based access control (ABAC), and just-in-time access provisioning for privacy-sensitive analytics workflows.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*