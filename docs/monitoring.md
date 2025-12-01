# Monitoring & Observability

## 1. Metrics

### ECS
- CPUUtilization
- MemoryUtilization
- RunningTaskCount
- DesiredTaskCount

### Lambda
- Invocations
- Errors
- Duration
- Throttles

### API Gateway
- Count
- Latency
- 4XXError
- 5XXError

---

## 2. Logs

### ECS app logs
- `/ecs/ecs-demo`

### Lambda logs
- `/aws/lambda/ecs-demo-wake`
- `/aws/lambda/ecs-demo-autosleep`

### API Gateway access logs
- `/apigw/ecs-demo-wake`

---

## 3. Alerts (Recommended)
- API 5xx > 1%
- Wake Lambda errors > 1
- Autosleep Lambda errors > 1
- ECS stuck in provisioning
- Wake latency > 60 seconds

---

## 4. Dashboards (Suggested)
- Wake latency graph  
- Autosleep invocation count  
- ECS desired vs running tasks  
- Error counts  
- Costs breakdown  