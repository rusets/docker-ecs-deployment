# Threat Model (STRIDE Overview)

## 1. Spoofing
- IAM enforced via OIDC  
- ECS task roles isolated  
- No public access to Lambdas

## 2. Tampering
- ECR images immutable  
- Terraform state stored in S3 with DynamoDB lock  
- No inline credentials

## 3. Repudiation
- Full CloudWatch logging  
- ECS task, API GW, and Lambda logs preserved

## 4. Information Disclosure
- No private subnets → no RDS inside  
- App does not expose internal data  
- Least-privilege IAM roles

## 5. Denial of Service
- Autosleep ensures cost protection  
- Wake Lambda overload protected by API Gateway throttling  
- Fargate auto-scales (if enabled later)

## 6. Elevation of Privilege
- Lambda roles restricted  
- ECS tasks have no write access to AWS services  
- No public IAM keys

---

This model covers the minimal threat surface for a serverless ECS app.