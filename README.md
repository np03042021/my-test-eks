# secure-paved-road-eks

The application half of the **Secure Paved Road on EKS** demo: a small Spring Boot service that is built, scanned and
deployed through the paved road created by
[secure-paved-road-eks-infra](https://github.com/np03042021/secure-paved-road-eks-infra).

## The service

| Endpoint | Purpose |
|---|---|
| `GET /api/hello?name=<name>` | Returns `{"message": "<GREETING_PREFIX>, <name>"}`. `name` defaults to `World` |
| `GET /actuator/health` | Status only (`{"status":"UP"}`), no component details |
| `GET /actuator/health/liveness`, `/readiness` | Kubernetes probes |

Everything else under `/actuator` is disabled, not just hidden.

`GREETING_PREFIX` comes from the Kubernetes Secret that External Secrets syncs from AWS Secrets Manager (`spr/demo`).
Locally it defaults to `Hello`.

## Security choices

- **Allow-list input validation.** `name` must be 1–40 ASCII letters, with single spaces, hyphens or apostrophes
  between them. Markup, SQL fragments, CR/LF (log injection), `${...}` lookups, digits and path segments are rejected
  with a generic RFC 9457 `application/problem+json` 400 that never echoes the input.
  DEMO ONLY: ASCII-only rejects names like "José"; production would allow Unicode letters after normalisation.
- **Fail-fast config.** `GREETING_PREFIX` is validated at startup (not blank, at most 100 characters).
- **Actuator deny-by-default.** `management.endpoints.access.default=none`, then read-only access to `health` only.
- **No internals in errors.** No messages, stack traces, exception names or binding errors in responses.
- **Graceful shutdown** so rolling updates and Spot interruptions finish in-flight requests.
- **Pinned toolchain.** The Maven Wrapper scripts are byte-identical to Apache's official 3.3.4 release, and the
  wrapper verifies the Maven 3.10.0 download against a SHA-256 checksum. Library versions come from the Spring Boot
  4.1.2 BOM.

## Build and test

Requires JDK 21. No local Maven needed.

```bash
./mvnw verify                     # compile, 37 JUnit 5 tests, JaCoCo report + 80% line-coverage gate
open target/site/jacoco/index.html

GREETING_PREFIX="Hello from the secure paved road" java -jar target/secure-paved-road-app-0.1.0-SNAPSHOT.jar
curl 'localhost:8080/api/hello?name=Alice'
```

## Container image

[Dockerfile](Dockerfile) is a multi-stage build: Maven 3.10.0 builds the jar, and only the extracted jar layers are
copied onto `gcr.io/distroless/java21-debian13:nonroot`. Both base images are pinned as `tag@sha256` digests.
The image runs as UID 65532, has no shell or package manager, and works with a read-only root filesystem.

```bash
docker buildx build --platform linux/amd64 -t spr-app:after --load .     # EKS nodes are amd64
docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  -e GREETING_PREFIX="Hello" spr-app:after
./scripts/compare-images.sh       # before/after evidence: size, user, shell, lint, CVE counts
```

Before/after, linux/amd64, scanned 2026-10-29 ([docker/Dockerfile.before](docker/Dockerfile.before) is the
deliberately naive baseline):

| | Before | After |
|---|---|---|
| Pull size (compressed) | 327 MB | 85 MB |
| Unpacked size | 993 MB | 306 MB |
| Runs as | root | 65532:65532 |
| Shell available | yes | no |
| `.git` history in image | yes | no |
| CVEs (critical / high / total) | 0 / 9 / 164 | 0 / 4 / 66 |
| HIGH+CRITICAL with a fix available | 9 | **0** |

The four remaining HIGH CVEs are in Debian's `libuuid1` with no fix published yet, and all 66 come from the
distroless base itself; the application adds none.

## Helm chart (`charts/app`)

Deployed by Argo CD from this repo (path `charts/app`, branch `main`) into the `spr-app` namespace.

| Control | How |
|---|---|
| Pod Security Standards | Namespace labelled `restricted` for enforce, audit and warn, pinned to `v1.36` |
| Pod hardening | UID/GID 65532, `runAsNonRoot`, read-only root FS (memory `emptyDir` at `/tmp`), no privilege escalation, all capabilities dropped, seccomp `RuntimeDefault`, no ServiceAccount token, no service-link env vars |
| Network | Default-deny ingress and egress; egress to CoreDNS only; ingress on 8080 only from inside the VPC (ALB and kubelet) |
| Secrets | `ExternalSecret` syncs only `GREETING_PREFIX` from `spr/demo`; mounted read-only as a file and read via Spring `configtree`, not as an env var |
| Image | `repository@sha256:digest` only, written by the release workflow |
| Availability | 2 replicas spread across nodes, PodDisruptionBudget `minAvailable: 1`, startup/liveness/readiness probes, `preStop` sleep for ALB deregistration |
| Ingress | Internet-facing ALB, `target-type: ip`, health check `/actuator/health`, invalid header fields dropped |
| Guardrails | `values.schema.json` rejects a missing digest, tags, non-ECR registries, fewer than 2 replicas, UID below 10000, pods open to `0.0.0.0/0`, and secret-looking env var names |

```bash
./scripts/validate-chart.sh   # helm lint --strict, render, kubeconform (K8s 1.36), Checkov, guardrail tests
```

## Pipelines

**[ci.yml](.github/workflows/ci.yml)** runs on every PR and push to `main`. Each job is a required status check:

| Job | Gate |
|---|---|
| `gitleaks` | secrets in the full git history (gitleaks 8.30.1 pinned) |
| `maven-verify` | 38 JUnit 5 tests and the JaCoCo 80% line-coverage gate |
| `codeql` | CodeQL `security-extended` for Java |
| `trivy-fs` | SCA on the Maven dependencies: HIGH/CRITICAL with a fix fails |
| `chart` | `helm lint --strict`, kubeconform against Kubernetes 1.36, values-schema guardrail tests |
| `checkov` | Dockerfile, rendered chart and workflows |
| `image` | hadolint, Trivy Dockerfile config, linux/amd64 build, Trivy image gate (HIGH/CRITICAL with a fix fails) |

**[release.yml](.github/workflows/release.yml)** runs after `ci` succeeds on `main`, in the `production`
environment (manual approval). It assumes `github-actions-ecr-push` through OIDC, builds and Trivy-scans the exact
image, pushes it tagged with the commit SHA, reads the digest back from ECR, and commits it to
`charts/app/values.yaml`. Argo CD deploys that commit.

Supply-chain controls: every action is pinned to a full commit SHA (enforced by the repo setting), CLI tools are
installed from hash-pinned binaries ([scripts/ci/install-tools.sh](scripts/ci/install-tools.sh)), all jobs start
from `permissions: {}`, and Dependabot (with a 7-day cooldown) proposes updates for Maven, Docker base images and
actions. Suppressions live in [.trivyignore.yaml](.trivyignore.yaml) and [.checkov.yaml](.checkov.yaml), each with
a reason, an owner and an expiry.

Coming next: Jenkins shared library (Phase 7).
