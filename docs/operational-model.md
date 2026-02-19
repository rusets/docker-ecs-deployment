## Default Timings

- **Wake delay:** ~40–60 seconds  
  Time for Fargate to pull the image, start the task, and pass container health checks.

- **Warm-up budget (`WAIT_MS`):** 120000 ms  
  Maximum time the Wake Lambda waits for the task to reach `RUNNING` before returning a response.

- **Idle timeout (`SLEEP_AFTER_MINUTES`):** 5 minutes  
  If no activity is detected during this window, the Auto-Sleep Lambda scales the service back to `desiredCount=0`.

- **Auto-sleep check interval:** 1 minute  
  EventBridge triggers the sleep check on a fixed schedule.