package io.github.np03042021.spr.config;

import static org.assertj.core.api.Assertions.assertThat;

import io.github.np03042021.spr.SecurePavedRoadApplication;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;

/**
 * In Kubernetes the secret arrives as files (one per key) rather than environment variables.
 * Proves a mounted GREETING_PREFIX file is picked up through Spring's configtree import.
 */
class SecretFileConfigTest {

    @Test
    void readsGreetingPrefixFromMountedSecretFile(@TempDir Path secretDir) throws Exception {
        // Same shape as a Kubernetes Secret volume: the file name is the key, the content is the value.
        Files.writeString(secretDir.resolve("GREETING_PREFIX"), "Hello from a mounted secret");

        try (ConfigurableApplicationContext ctx = new SpringApplicationBuilder(SecurePavedRoadApplication.class)
                .web(WebApplicationType.NONE)
                .run("--spring.config.import=optional:configtree:" + secretDir + "/")) {
            assertThat(ctx.getBean(GreetingProperties.class).prefix()).isEqualTo("Hello from a mounted secret");
        }
    }
}
