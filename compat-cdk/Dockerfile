FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npx tsc

FROM node:20-alpine
RUN apk add --no-cache aws-cli bash python3
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/bin ./bin
COPY --from=builder /app/lib ./lib
COPY package.json cdk.json tsconfig.json ./
COPY run.sh ./
ENV PATH="/app/node_modules/.bin:$PATH"
ENTRYPOINT ["/bin/bash", "run.sh"]
