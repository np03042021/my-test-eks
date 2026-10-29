# Hardened image for secure-paved-road-app.
#   docker buildx build --platform linux/amd64 -t spr-app:after --load .
# EKS nodes are amd64 (t3/t3a); Apple Silicon builds arm64 by default, hence --platform.
#
# Both base images are pinned as tag@digest of their multi-arch index (works for amd64 and arm64).
# Tags are mutable; a digest always means the same bytes. The tag stays for humans and scanners.
# Written as literal FROM lines (not ARGs) so Checkov and Dependabot can read and bump them. To update by hand:
#   docker buildx imagetools inspect <image>:<tag> --format '{{.Manifest.Digest}}'

############################ build stage (discarded) ############################
# Runs on the build machine's native platform: the jar is platform-independent, so there is no slow
# emulation for the Maven build. Only the runtime stage targets linux/amd64.
FROM --platform=$BUILDPLATFORM maven:3.10.0-eclipse-temurin-21-noble@sha256:be0d4ea47a9844740bd691de7af8c1e51e861bb7284068e055f383da5c6ccdb7 AS build
WORKDIR /workspace

# Official Maven image at the same version mvnw pins locally and in CI (3.10.0), so no wrapper download
# here. (mvnw needs `unzip`, which this image lacks; installing it via apt would add an unpinned dependency.)
COPY pom.xml ./
COPY src/ src/

# The cache mount keeps ~/.m2 between builds on this machine but is never part of an image layer.
# Tests run in CI's `mvnw verify` job before the image is built; the image build only packages.
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -ntp package -DskipTests

# Split the fat jar into layers that change at different rates (23 MB of dependencies vs 12 KB of app code),
# so a code change only rebuilds and pushes the tiny application layer.
RUN java -Djarmode=tools -jar target/secure-paved-road-app-*.jar \
        extract --layers --application-filename app.jar --destination /workspace/extracted

############################ runtime stage ############################
# Distroless: a JRE and CA certificates only. No shell, no package manager, no coreutils, so there is very
# little for an attacker to use and very little for scanners to flag. The :nonroot variant has UID 65532.
# Debian 13, not 12: on 2026-10-29 the debian12 variant had 10 fixable HIGH/CRITICAL CVEs (fails the CI gate);
# debian13 had 0 fixable (4 HIGH in libuuid1 with no Debian fix yet).
FROM gcr.io/distroless/java21-debian13:nonroot@sha256:a2aeb5a7a714cfe928b31fdf67b2d23f503ea6b9612705af062de22e0c50ba77

LABEL org.opencontainers.image.title="secure-paved-road-app" \
      org.opencontainers.image.description="Demo service for the Secure Paved Road on EKS" \
      org.opencontainers.image.source="https://github.com/np03042021/secure-paved-road-eks"

WORKDIR /app

# Least-changing layer first. Files stay owned by root and are read-only to the app user,
# so a compromised process cannot modify its own code.
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

# Numeric UID:GID, not the name "nonroot": Kubernetes runAsNonRoot can only verify a numeric user.
# The Helm chart (Phase 5) sets the same UID, plus readOnlyRootFilesystem with an emptyDir at /tmp.
USER 65532:65532

EXPOSE 8080

# No secrets here or in any layer: GREETING_PREFIX arrives at runtime from the Kubernetes Secret.
# MaxRAMPercentage sizes the heap from the container memory limit; ExitOnOutOfMemoryError lets
# Kubernetes restart a broken JVM instead of leaving it half-alive.
# checkov:skip=CKV_DOCKER_2:No HEALTHCHECK by design: distroless has no shell or curl, and Kubernetes liveness/readiness probes on /actuator/health/* do this job.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
