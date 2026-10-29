package io.github.np03042021.spr.config;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Greeting configuration. {@code app.greeting.prefix} is fed from the GREETING_PREFIX environment variable,
 * which in the cluster comes from the Kubernetes Secret that External Secrets syncs from Secrets Manager (spr/demo).
 *
 * <p>Validated at startup: a missing or oversized value fails fast instead of serving bad output.
 */
@Validated
@ConfigurationProperties("app.greeting")
public record GreetingProperties(
        @NotBlank @Size(max = 100) String prefix) {
}
