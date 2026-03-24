FROM ghcr.io/opentofu/opentofu:1.8 AS opentofu

FROM amazon/aws-cli:2.15.52

# Copy tofu binary from official OpenTofu image
COPY --from=opentofu /usr/local/bin/tofu /usr/local/bin/tofu

WORKDIR /app
COPY . .
RUN chmod +x run.sh

ENV FLOCI_ENDPOINT=http://floci:4566
ENV AWS_ENDPOINT_URL=http://floci:4566
ENV AWS_ACCESS_KEY_ID=test
ENV AWS_SECRET_ACCESS_KEY=test
ENV AWS_DEFAULT_REGION=us-east-1

ENTRYPOINT ["./run.sh"]
