#
# Build stage
#
FROM maven:3.8.6-openjdk-8-slim AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
# generate .jar in the folder /build/target
RUN mvn clean package

# Use simple image with just java 8
FROM eclipse-temurin:8-jre-alpine

WORKDIR /app

# Update Alpine packages and install curl
RUN apk update && apk add curl
# Default command bash
CMD /bin/bash
RUN echo "Downloading applicationinsights-agent-3.4.12.jar"
# Download application insights to monitor the app performance and metrics in real time
RUN curl "https://repo1.maven.org/maven2/com/microsoft/azure/applicationinsights-agent/3.4.12/applicationinsights-agent-3.4.12.jar" -o /app/applicationinsights-agent-3.4.12.jar

# Copy the .jar generated in the build and rename it
COPY --from=build /build/target/*.jar /app/petstorepetservice.jar
# Copy the configuration file for the application insights
COPY applicationinsights.json /app/applicationinsights.json
EXPOSE 8080
# Command to execute at the beginning
ENTRYPOINT ["java", "-javaagent:applicationinsights-agent-3.4.12.jar", "-jar","petstorepetservice.jar"]