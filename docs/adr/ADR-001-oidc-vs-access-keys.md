# ADR-001: GitHub OIDC vs Long-Lived IAM Access Keys

## Status
Accepted

## Context
The project requires GitHub Actions to deploy infrastructure (Terraform) and push Docker images to ECR.  
Two authentication strategies exist:

1. **Long-lived IAM Access Keys**  
2. **GitHub OIDC (Secure, short-lived tokens)**

## Decision
Use **GitHub OIDC** for all CI/CD workflows.

## Rationale
- Eliminates static IAM keys → nothing to rotate or leak  
- AWS issues **short-lived** credentials (15 min)  
- Permissions scoped to a specific GitHub repository  
- Complies with AWS best practices for automation  
- Allows least-privilege role design  
- Zero secrets stored in GitHub → no leakage risk

## Consequences
- Infrastructure is safer and audit-friendly  
- No dependency on secret storage  
- Slight additional setup (trust relationship), but one-time only