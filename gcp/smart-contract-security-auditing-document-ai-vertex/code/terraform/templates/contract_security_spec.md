# VulnerableBank Smart Contract Security Specification

## Contract Overview
VulnerableBank is a demonstration smart contract showing common security vulnerabilities in DeFi applications.

## Security Requirements
- Only contract owner should have admin privileges
- All withdrawals must prevent reentrancy attacks
- Balance updates must occur before external calls
- Input validation required for all public functions
- Time-based logic should not depend on block.timestamp

## Known Vulnerabilities (Intentional)
1. **Access Control**: setAdmin function lacks proper access control
2. **Reentrancy**: withdraw function vulnerable to reentrancy attacks
3. **State Management**: External calls before state updates
4. **Timestamp Dependence**: isLuckyTime relies on block.timestamp

## Compliance Requirements
- Must pass OWASP Smart Contract Top 10 security checks
- Requires integration with OpenZeppelin security libraries
- All admin functions must emit appropriate events

## Audit History
- Initial deployment: Never audited (demonstration purposes)
- Known issues: Multiple critical vulnerabilities present