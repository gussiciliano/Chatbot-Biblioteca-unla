# ETAPA DE CONSTRUCCION: COMPILA EL PROYECTO Y GENERA EL .JAR


FROM eclipse-temurin:17-jdk-noble AS build

WORKDIR /app

COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
COPY src src


RUN chmod +x mvnw && ./mvnw -B package -DskipTests
