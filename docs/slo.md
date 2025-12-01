# Service Level Objectives (SLO)

## 1. Availability
**Target:** 99% monthly  
Measured by: API Gateway 5xx, Lambda errors, ECS service health

---

## 2. Wake Latency
**Target:** < 40 seconds from API call to running task  
Measured by: Lambda duration + ECS service stabilization time

---

## 3. Cost
**Target:** <$5 per month  
Measured by: AWS Cost Explorer (ECS, Lambda, ECR, CloudWatch)

---

## 4. Autosleep Accuracy
**Target:** 100% idle detection  
Measured by: autosleep Lambda logs + ECS desiredCount history

---

## 5. Error Budget
With 99% SLO → allowed downtime ≈ **7 hours/month**