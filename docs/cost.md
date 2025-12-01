# Cost Model

## ECS Fargate
### Running task
- 0.25 vCPU + 0.5 GB RAM  
- ≈ $0.0416/hour  
- ≈ $1.25/day when running

### Idle
- $0 (no running tasks)

---

## Lambda
- wake: short-lived, occasional  
- autosleep: once per minute  
Total ≈ **$0.10–0.20/month**

---

## API Gateway (HTTP API)
- ~$1 per 1M requests  
Practical monthly cost ≈ **$0.05**

---

## CloudWatch Logs
- Largest cost in the stack if verbose  
Expected ≈ **$0.50–1.50/month**

---

## Total Expected Monthly Cost