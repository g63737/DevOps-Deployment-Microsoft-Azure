# Étape 1 — Build du .jar avec Maven
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests

# Étape 2 — Exécution avec une image Java plus légère
FROM eclipse-temurin:17-jdk-jammy

WORKDIR /app

# On récupère juste le .jar compilé depuis l'étape précédente
COPY --from=builder /app/target/*.jar app.jar

ENV FLASK_URL=http://container-python:5000

EXPOSE 8080

CMD ["java", "-jar", "app.jar"]