FROM amazon/aws-cli:2.22.35

WORKDIR /app

COPY test_all.sh .

ENV FLOCI_ENDPOINT=http://floci:4566

ENTRYPOINT ["/bin/bash", "test_all.sh"]
