package io.github.np03042021.spr.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.context.ConfigurationPropertiesAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.validation.autoconfigure.ValidationAutoConfiguration;
import org.springframework.context.annotation.Configuration;

/** Bad configuration must stop the app at startup (fail fast), not surface later as a broken response. */
class GreetingPropertiesTest {

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(GreetingProperties.class)
    static class Config {
    }

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(
                    ConfigurationPropertiesAutoConfiguration.class, ValidationAutoConfiguration.class))
            .withUserConfiguration(Config.class);

    @Test
    void bindsValidPrefix() {
        runner.withPropertyValues("app.greeting.prefix=Hello from the secure paved road")
                .run(ctx -> assertThat(ctx.getBean(GreetingProperties.class).prefix())
                        .isEqualTo("Hello from the secure paved road"));
    }

    @Test
    void failsStartupWhenPrefixIsBlank() {
        runner.withPropertyValues("app.greeting.prefix=   ")
                .run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void failsStartupWhenPrefixIsMissing() {
        runner.run(ctx -> assertThat(ctx).hasFailed());
    }

    @Test
    void failsStartupWhenPrefixIsTooLong() {
        runner.withPropertyValues("app.greeting.prefix=" + "x".repeat(101))
                .run(ctx -> assertThat(ctx).hasFailed());
    }
}
