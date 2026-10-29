package io.github.np03042021.spr;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

/** Proves the Actuator lockdown: probes work, everything else is unreachable. */
@SpringBootTest
@AutoConfigureMockMvc
class ActuatorExposureTest {

    @Autowired
    MockMvcTester mvc;

    @Test
    void healthReportsStatusOnlyWithoutComponentDetails() {
        assertThat(mvc.get().uri("/actuator/health"))
                .hasStatusOk()
                .bodyJson().doesNotHavePath("$.components").extractingPath("$.status").isEqualTo("UP");
    }

    @ParameterizedTest
    @ValueSource(strings = {"/actuator/health/liveness", "/actuator/health/readiness"})
    void kubernetesProbesAreAvailable(String path) {
        assertThat(mvc.get().uri(path))
                .hasStatusOk()
                .bodyJson().extractingPath("$.status").isEqualTo("UP");
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "/actuator/env", "/actuator/heapdump", "/actuator/threaddump", "/actuator/beans",
            "/actuator/configprops", "/actuator/loggers", "/actuator/mappings", "/actuator/metrics",
            "/actuator/info", "/actuator/shutdown",
    })
    void sensitiveEndpointsAreNotExposed(String path) {
        assertThat(mvc.get().uri(path)).hasStatus(HttpStatus.NOT_FOUND);
    }
}
