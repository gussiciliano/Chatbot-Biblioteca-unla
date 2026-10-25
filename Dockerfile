# ETAPA DE CONSTRUCCION: COMPILA EL PROYECTO Y GENERA EL .JAR


FROM eclipse-temurin:17-jdk-noble AS build

WORKDIR /app

# Dependencias primero: esta capa sólo se rehace si cambia el pom.xml
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
RUN chmod +x mvnw && ./mvnw -B dependency:go-offline

# Código al final: un cambio en src/ no vuelve a descargar dependencias
COPY src src
RUN ./mvnw -B package -DskipTests

# Etapa final: sólo el JRE y el .jar, ejecutado con un usuario sin privilegios
FROM eclipse-temurin:17-jre-noble AS production

WORKDIR /app

RUN useradd --system --create-home --shell /usr/sbin/nologin appuser

COPY --from=build /app/target/*.jar app.jar

USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]

