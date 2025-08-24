
# Build Native Image
FROM ghcr.io/graalvm/native-image:ol9-java21-24.0.2 AS build
WORKDIR /work
COPY . .
# Hinweis: nutzt gradle wrapper, alternativ: gradle im Container bereitstellen
RUN ./gradlew -x test nativeCompile || (echo "Gradle Wrapper fehlt? Bitte lokal bauen." && exit 1)

# Runtime
FROM gcr.io/distroless/base-nossl:nonroot
WORKDIR /app
COPY --from=build /work/build/native/nativeCompile/search-service /app/search-service
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app/search-service"]
