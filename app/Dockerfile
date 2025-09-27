# app/Dockerfile
FROM public.ecr.aws/docker/library/node:20-alpine

WORKDIR /app

# Copy only manifests first to leverage layer cache
COPY package*.json ./

# Install production dependencies
RUN npm ci --omit=dev

# Copy source
COPY src ./src

ENV NODE_ENV=production
ENV PORT=80

# Lightweight healthcheck (no curl/wget needed)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s   CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

EXPOSE 80
CMD ["npm", "start"]
