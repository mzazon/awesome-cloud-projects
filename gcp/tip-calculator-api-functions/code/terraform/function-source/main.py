import json
from flask import Request
import functions_framework

@functions_framework.http
def calculate_tip(request: Request):
    """
    Calculate tip amounts and split bills among multiple people.
    
    Request JSON format:
    {
        "bill_amount": 100.00,
        "tip_percentage": 18,
        "number_of_people": 4
    }
    """
    
    # Set CORS headers for web applications
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        if request.method == 'GET':
            bill_amount = float(request.args.get('bill_amount', 0))
            tip_percentage = float(request.args.get('tip_percentage', 15))
            number_of_people = int(request.args.get('number_of_people', 1))
        else:  # POST request
            request_json = request.get_json(silent=True)
            if not request_json:
                return (json.dumps({'error': 'No JSON data provided'}), 400, headers)
            
            bill_amount = float(request_json.get('bill_amount', 0))
            tip_percentage = float(request_json.get('tip_percentage', 15))
            number_of_people = int(request_json.get('number_of_people', 1))
        
        # Validate input parameters
        if bill_amount <= 0:
            return (json.dumps({'error': 'Bill amount must be greater than 0'}), 400, headers)
        
        if tip_percentage < 0 or tip_percentage > 100:
            return (json.dumps({'error': 'Tip percentage must be between 0 and 100'}), 400, headers)
        
        if number_of_people <= 0:
            return (json.dumps({'error': 'Number of people must be greater than 0'}), 400, headers)
        
        # Calculate tip and totals
        tip_amount = bill_amount * (tip_percentage / 100)
        total_amount = bill_amount + tip_amount
        per_person_bill = bill_amount / number_of_people
        per_person_tip = tip_amount / number_of_people
        per_person_total = total_amount / number_of_people
        
        # Prepare response
        response_data = {
            'input': {
                'bill_amount': round(bill_amount, 2),
                'tip_percentage': tip_percentage,
                'number_of_people': number_of_people
            },
            'calculations': {
                'tip_amount': round(tip_amount, 2),
                'total_amount': round(total_amount, 2),
                'per_person': {
                    'bill_share': round(per_person_bill, 2),
                    'tip_share': round(per_person_tip, 2),
                    'total_share': round(per_person_total, 2)
                }
            },
            'formatted_summary': f"Bill: ${bill_amount:.2f} | Tip ({tip_percentage}%): ${tip_amount:.2f} | Total: ${total_amount:.2f} | Per person: ${per_person_total:.2f}"
        }
        
        return (json.dumps(response_data, indent=2), 200, headers)
        
    except ValueError as e:
        return (json.dumps({'error': f'Invalid input: {str(e)}'}), 400, headers)
    except Exception as e:
        return (json.dumps({'error': f'Internal error: {str(e)}'}), 500, headers)