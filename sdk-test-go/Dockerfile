FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod tidy && go build -o /floci-test .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /floci-test /floci-test

ENV FLOCI_ENDPOINT=http://floci:4566
ENTRYPOINT ["/floci-test"]
