FROM eclipse-temurin:17-jdk AS build
WORKDIR /build

RUN apt-get update && apt-get install -y maven && rm -rf /var/lib/apt/lists/*

COPY pom.xml .
RUN mvn dependency:go-offline -q

COPY src/ src/
RUN mvn package -DskipTests -q

FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=build /build/target/ target/
COPY --from=build /root/.m2/repository/ /root/.m2/repository/

RUN apt-get update && apt-get install -y maven && rm -rf /var/lib/apt/lists/*

COPY pom.xml .

ENV FLOCI_ENDPOINT=http://floci:4566

ENTRYPOINT ["mvn", "exec:java", "-q"]