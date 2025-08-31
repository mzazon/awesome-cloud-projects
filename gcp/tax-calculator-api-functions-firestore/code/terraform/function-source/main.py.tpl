"""
Tax Calculator API Cloud Functions
Serverless tax calculation and history retrieval functions for Google Cloud Platform

This module provides two HTTP-triggered Cloud Functions:
1. calculate_tax: Calculates federal income tax based on 2024 tax brackets
2. get_calculation_history: Retrieves user's calculation history from Firestore
"""

import json
import os
from datetime import datetime
from typing import Dict, List, Any, Tuple, Union

from google.cloud import firestore
import functions_framework
from flask import Request


# Initialize Firestore client with project ID
PROJECT_ID = "${firestore_project_id}"
db = firestore.Client(project=PROJECT_ID)

# 2024 US Federal Tax Brackets (Single Filer)
# Source: IRS Publication 15 and Form 1040 Instructions
TAX_BRACKETS = [
    {"min": 0, "max": 11600, "rate": 0.10},        # 10% bracket
    {"min": 11601, "max": 47150, "rate": 0.12},    # 12% bracket
    {"min": 47151, "max": 100525, "rate": 0.22},   # 22% bracket
    {"min": 100526, "max": 191950, "rate": 0.24},  # 24% bracket
    {"min": 191951, "max": 243725, "rate": 0.32},  # 32% bracket
    {"min": 243726, "max": 609350, "rate": 0.35},  # 35% bracket
    {"min": 609351, "max": float('inf'), "rate": 0.37}  # 37% bracket (highest)
]

# 2024 Standard Deduction amounts
STANDARD_DEDUCTIONS = {
    "single": 13850,
    "married_filing_jointly": 27700,
    "married_filing_separately": 13850,
    "head_of_household": 20800
}


def calculate_progressive_tax(taxable_income: float) -> Tuple[float, List[Dict[str, Any]]]:
    """
    Calculate federal income tax using progressive tax brackets.
    
    Args:
        taxable_income: The taxable income amount
        
    Returns:
        Tuple containing total tax amount and breakdown by bracket
    """
    total_tax = 0.0
    tax_details = []
    remaining_income = taxable_income
    
    for bracket in TAX_BRACKETS:
        if remaining_income <= 0:
            break
        
        # Determine income subject to this bracket's rate
        bracket_min = bracket["min"]
        bracket_max = bracket["max"]
        bracket_rate = bracket["rate"]
        
        # Calculate the range for this bracket
        if bracket_max == float('inf'):
            bracket_range = remaining_income
        else:
            bracket_range = min(remaining_income, bracket_max - bracket_min + 1)
        
        # Calculate tax for this bracket
        bracket_tax = bracket_range * bracket_rate
        total_tax += bracket_tax
        remaining_income -= bracket_range
        
        # Record bracket details if there's income in this bracket
        if bracket_range > 0:
            tax_details.append({
                "bracket_rate": f"{bracket_rate * 100:.0f}%",
                "income_in_bracket": round(bracket_range, 2),
                "tax_amount": round(bracket_tax, 2),
                "bracket_min": bracket_min,
                "bracket_max": bracket_max if bracket_max != float('inf') else None
            })
    
    return round(total_tax, 2), tax_details


def validate_calculation_input(request_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Validate input data for tax calculation.
    
    Args:
        request_data: The JSON request data
        
    Returns:
        Tuple of (is_valid, error_message)
    """
    if not request_data:
        return False, "Request body must contain JSON data"
    
    # Validate required fields
    if 'income' not in request_data:
        return False, "Missing required field: income"
    
    income = request_data.get('income')
    if not isinstance(income, (int, float)) or income < 0:
        return False, "Income must be a non-negative number"
    
    if income > 10000000:  # Reasonable upper limit
        return False, "Income amount exceeds maximum allowed value"
    
    # Validate optional fields
    filing_status = request_data.get('filing_status', 'single')
    if filing_status not in STANDARD_DEDUCTIONS:
        return False, f"Invalid filing status. Must be one of: {list(STANDARD_DEDUCTIONS.keys())}"
    
    deductions = request_data.get('deductions', 0)
    if not isinstance(deductions, (int, float)) or deductions < 0:
        return False, "Deductions must be a non-negative number"
    
    user_id = request_data.get('user_id', 'anonymous')
    if not isinstance(user_id, str) or len(user_id) > 100:
        return False, "User ID must be a string with maximum 100 characters"
    
    return True, ""


@functions_framework.http
def calculate_tax(request: Request) -> Tuple[Dict[str, Any], int]:
    """
    HTTP Cloud Function to calculate federal income tax.
    
    Expected JSON payload:
    {
        "income": 65000,
        "filing_status": "single",  # optional, defaults to "single"
        "deductions": 15000,        # optional, defaults to 0
        "user_id": "user123"        # optional, defaults to "anonymous"
    }
    
    Returns:
        JSON response with tax calculation results and HTTP status code
    """
    try:
        # Set CORS headers for browser compatibility
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        # Handle preflight OPTIONS requests
        if request.method == 'OPTIONS':
            return ('', 204, headers)
        
        # Only allow POST requests for calculations
        if request.method != 'POST':
            return ({"error": "Method not allowed. Use POST for tax calculations."}, 405)
        
        # Parse and validate request data
        request_json = request.get_json(silent=True)
        is_valid, error_message = validate_calculation_input(request_json)
        
        if not is_valid:
            return ({"error": error_message}, 400)
        
        # Extract validated inputs
        income = float(request_json['income'])
        filing_status = request_json.get('filing_status', 'single')
        deductions = float(request_json.get('deductions', 0))
        user_id = request_json.get('user_id', 'anonymous')
        
        # Calculate taxable income using standard or itemized deductions
        standard_deduction = STANDARD_DEDUCTIONS[filing_status]
        total_deductions = max(deductions, standard_deduction)
        taxable_income = max(0, income - total_deductions)
        
        # Calculate federal income tax
        total_tax, tax_details = calculate_progressive_tax(taxable_income)
        
        # Calculate effective and marginal tax rates
        effective_rate = (total_tax / income * 100) if income > 0 else 0
        
        # Determine marginal tax rate (rate of the highest bracket with income)
        marginal_rate = 0
        if tax_details:
            # Find the rate from the last bracket with income
            for detail in reversed(tax_details):
                if detail['income_in_bracket'] > 0:
                    marginal_rate = float(detail['bracket_rate'].replace('%', ''))
                    break
        
        # Prepare comprehensive calculation result
        calculation_result = {
            "income": round(income, 2),
            "filing_status": filing_status,
            "standard_deduction": standard_deduction,
            "itemized_deductions": round(deductions, 2) if deductions > standard_deduction else 0,
            "total_deductions": round(total_deductions, 2),
            "taxable_income": round(taxable_income, 2),
            "federal_tax": round(total_tax, 2),
            "effective_tax_rate": round(effective_rate, 2),
            "marginal_tax_rate": round(marginal_rate, 2),
            "tax_bracket_breakdown": tax_details,
            "after_tax_income": round(income - total_tax, 2),
            "calculated_at": datetime.utcnow().isoformat() + "Z",
            "user_id": user_id,
            "tax_year": 2024
        }
        
        # Store calculation in Firestore for history tracking
        doc_ref = db.collection('tax_calculations').document()
        doc_ref.set(calculation_result)
        calculation_result["calculation_id"] = doc_ref.id
        
        return (calculation_result, 200)
        
    except ValueError as e:
        return ({"error": f"Invalid input data: {str(e)}"}, 400)
    except Exception as e:
        # Log error for debugging (in production, use proper logging)
        print(f"Calculation error: {str(e)}")
        return ({"error": "Internal server error during tax calculation"}, 500)


@functions_framework.http
def get_calculation_history(request: Request) -> Tuple[Dict[str, Any], int]:
    """
    HTTP Cloud Function to retrieve user's tax calculation history.
    
    Query parameters:
    - user_id: User identifier (required)
    - limit: Maximum number of results (optional, default: 10, max: 50)
    - offset: Number of results to skip (optional, default: 0)
    
    Returns:
        JSON response with calculation history and HTTP status code
    """
    try:
        # Set CORS headers for browser compatibility
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        # Handle preflight OPTIONS requests
        if request.method == 'OPTIONS':
            return ('', 204, headers)
        
        # Only allow GET requests for history retrieval
        if request.method != 'GET':
            return ({"error": "Method not allowed. Use GET for history retrieval."}, 405)
        
        # Extract and validate query parameters
        user_id = request.args.get('user_id')
        if not user_id:
            return ({"error": "Missing required parameter: user_id"}, 400)
        
        if len(user_id) > 100:
            return ({"error": "User ID must be 100 characters or fewer"}, 400)
        
        # Parse limit parameter with validation
        try:
            limit = min(int(request.args.get('limit', 10)), 50)
            if limit < 1:
                limit = 10
        except (ValueError, TypeError):
            limit = 10
        
        # Parse offset parameter with validation
        try:
            offset = max(int(request.args.get('offset', 0)), 0)
        except (ValueError, TypeError):
            offset = 0
        
        # Query Firestore for user's calculation history
        calculations = []
        query = db.collection('tax_calculations').where('user_id', '==', user_id)
        
        # Order by calculation timestamp (most recent first)
        query = query.order_by('calculated_at', direction=firestore.Query.DESCENDING)
        
        # Apply offset and limit
        if offset > 0:
            # Get documents to skip
            skip_docs = query.limit(offset).stream()
            last_doc = None
            for doc in skip_docs:
                last_doc = doc
            
            if last_doc:
                query = query.start_after(last_doc)
        
        # Apply limit and execute query
        docs = query.limit(limit).stream()
        
        for doc in docs:
            calc_data = doc.to_dict()
            calc_data['calculation_id'] = doc.id
            
            # Ensure consistent field formatting
            if 'calculated_at' in calc_data:
                calc_data['calculated_at'] = calc_data['calculated_at']
            
            calculations.append(calc_data)
        
        # Prepare response with metadata
        response_data = {
            "user_id": user_id,
            "calculations": calculations,
            "returned_count": len(calculations),
            "limit": limit,
            "offset": offset,
            "has_more": len(calculations) == limit,  # Indicates if there might be more results
            "retrieved_at": datetime.utcnow().isoformat() + "Z"
        }
        
        return (response_data, 200)
        
    except Exception as e:
        # Log error for debugging (in production, use proper logging)
        print(f"History retrieval error: {str(e)}")
        return ({"error": "Internal server error during history retrieval"}, 500)


# Health check endpoint for monitoring
@functions_framework.http
def health_check(request: Request) -> Tuple[Dict[str, Any], int]:
    """
    Simple health check endpoint for function monitoring.
    
    Returns:
        JSON response indicating function health status
    """
    try:
        # Verify Firestore connectivity
        db.collection('health_check').limit(1).get()
        
        return ({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "services": {
                "firestore": "connected",
                "function": "running"
            }
        }, 200)
    except Exception as e:
        return ({
            "status": "unhealthy",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "error": str(e)
        }, 503)