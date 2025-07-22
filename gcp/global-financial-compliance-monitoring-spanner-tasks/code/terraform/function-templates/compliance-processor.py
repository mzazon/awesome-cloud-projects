import json
import logging
from datetime import datetime
from google.cloud import spanner
from google.cloud import logging as cloud_logging
from google.cloud import tasks_v2
import functions_framework

# Initialize clients
spanner_client = spanner.Client()
tasks_client = tasks_v2.CloudTasksClient()
logging_client = cloud_logging.Client()

# Configuration from Terraform template variables
SPANNER_INSTANCE = "${spanner_instance}"
SPANNER_DATABASE = "${spanner_database}"
PROJECT_ID = "${project_id}"
COMPLIANCE_RULES = ${jsonencode(compliance_rules)}

@functions_framework.cloud_event
def process_compliance_check(cloud_event):
    """Process compliance check for financial transaction"""
    
    try:
        # Extract transaction data from event
        transaction_data = json.loads(cloud_event.data['message']['data'])
        transaction_id = transaction_data.get('transaction_id')
        
        if not transaction_id:
            logging.error("No transaction_id in event data")
            return {'status': 'error', 'message': 'Missing transaction_id'}
        
        # Connect to Spanner database
        instance = spanner_client.instance(SPANNER_INSTANCE)
        database = instance.database(SPANNER_DATABASE)
        
        # Retrieve transaction details
        with database.snapshot() as snapshot:
            results = snapshot.execute_sql(
                "SELECT * FROM transactions WHERE transaction_id = @transaction_id",
                params={'transaction_id': transaction_id},
                param_types={'transaction_id': spanner.param_types.STRING}
            )
            
            transaction_list = list(results)
            if not transaction_list:
                logging.error(f"Transaction {transaction_id} not found")
                return {'status': 'error', 'message': 'Transaction not found'}
            
            transaction = transaction_list[0]
            
            # Perform compliance checks
            compliance_results = perform_compliance_checks(transaction)
            
            # Update transaction with compliance status
            update_compliance_status(database, transaction_id, compliance_results)
            
            # Log compliance check results
            log_compliance_check(transaction_id, compliance_results)
            
            return {'status': 'completed', 'transaction_id': transaction_id}
            
    except Exception as e:
        logging.error(f"Error processing compliance check: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def perform_compliance_checks(transaction):
    """Perform various compliance checks on transaction"""
    results = {}
    
    # KYC Check
    results['kyc_verified'] = check_kyc_compliance(transaction)
    
    # AML Check
    results['aml_risk_score'] = calculate_aml_risk(transaction)
    
    # Cross-border compliance
    results['cross_border_compliant'] = check_cross_border_rules(transaction)
    
    # Determine overall compliance status
    results['compliance_status'] = determine_compliance_status(results)
    
    return results

def check_kyc_compliance(transaction):
    """Check KYC compliance based on transaction amount and rules"""
    kyc_threshold = COMPLIANCE_RULES.get('kyc_threshold', 10000)
    return float(transaction[2]) < kyc_threshold  # amount is at index 2

def calculate_aml_risk(transaction):
    """Calculate AML risk score based on various factors"""
    risk_score = 0
    
    # High-risk countries check
    high_risk_countries = COMPLIANCE_RULES.get('high_risk_countries', [])
    source_country = transaction[4]  # source_country at index 4
    destination_country = transaction[5]  # destination_country at index 5
    
    if source_country in high_risk_countries or destination_country in high_risk_countries:
        risk_score += 50
    
    # Large transaction check
    amount = float(transaction[2])  # amount at index 2
    if amount > 50000:
        risk_score += 30
    
    # Cross-border transaction risk
    if source_country != destination_country:
        risk_score += 20
    
    return min(risk_score, 100)

def check_cross_border_rules(transaction):
    """Check cross-border compliance rules"""
    source_country = transaction[4]
    destination_country = transaction[5]
    amount = float(transaction[2])
    cross_border_limit = COMPLIANCE_RULES.get('cross_border_limit', 100000)
    
    # Cross-border transactions must be under the limit
    if source_country != destination_country:
        return amount < cross_border_limit
    
    return True  # Domestic transactions are compliant

def determine_compliance_status(results):
    """Determine overall compliance status based on check results"""
    if not results['kyc_verified']:
        return 'KYC_FAILED'
    if results['aml_risk_score'] > COMPLIANCE_RULES.get('aml_high_risk_score', 75):
        return 'HIGH_RISK'
    if not results['cross_border_compliant']:
        return 'BLOCKED'
    return 'APPROVED'

def update_compliance_status(database, transaction_id, results):
    """Update transaction compliance status in Spanner"""
    with database.batch() as batch:
        batch.update(
            table='transactions',
            columns=['transaction_id', 'compliance_status', 'risk_score', 
                    'kyc_verified', 'aml_checked', 'updated_at'],
            values=[(
                transaction_id,
                results['compliance_status'],
                results['aml_risk_score'],
                results['kyc_verified'],
                True,
                spanner.COMMIT_TIMESTAMP
            )]
        )

def log_compliance_check(transaction_id, results):
    """Log compliance check results for audit trail"""
    logger = logging_client.logger('compliance-checks')
    logger.log_struct({
        'transaction_id': transaction_id,
        'compliance_results': results,
        'timestamp': datetime.utcnow().isoformat(),
        'severity': 'INFO',
        'component': 'compliance-processor'
    })