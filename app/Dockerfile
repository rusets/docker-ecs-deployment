# Use a small official Node.js 20 image from AWS Public ECR (Alpine-based for minimal size)
FROM public.ecr.aws/docker/library/node:20-alpine

# Set working directory inside the container
WORKDIR /app

# Copy only dependency manifests first (package.json, package-lock.json)
# This allows Docker to cache dependency installation layers
# unless package files have changed (faster builds).
COPY package*.json ./

# Install production dependencies only
# "npm ci" ensures clean, reproducible installs
# "--omit=dev" excludes devDependencies → smaller image, faster runtime
RUN npm ci --omit=dev

# Copy the application source code
# Here we assume all source is inside "src/" directory
COPY src ./src

# Set environment variables for production
ENV NODE_ENV=production
ENV PORT=80

# Define container health check
# - Interval: every 30s
# - Timeout: fail after 3s
# - Start period: allow 10s before first check
# - Command: Run a Node one-liner that makes HTTP request to /health endpoint
#   → exits 0 if OK, exits 1 if failure
# Using Node's fetch avoids installing curl or wget, keeping the image slim.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
    CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Expose application port (for ECS, Kubernetes, etc.)
EXPOSE 80

# Default container startup command → "npm start" defined in package.json
CMD ["npm", "start"]