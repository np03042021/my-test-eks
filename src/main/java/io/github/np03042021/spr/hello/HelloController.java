package io.github.np03042021.spr.hello;

import io.github.np03042021.spr.config.GreetingProperties;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api", produces = MediaType.APPLICATION_JSON_VALUE)
public class HelloController {

    /**
     * Allow-list, not deny-list: ASCII letters, with single spaces, hyphens or apostrophes BETWEEN letters
     * ("Mary-Jane O'Neil"). Anything else (markup, quotes+SQL, CR/LF for log injection, ${...} lookups,
     * digits, non-ASCII) is rejected before it reaches any logic.
     * DEMO ONLY: ASCII-only rejects names like "José"; production would allow Unicode letters (\p{L}) after NFC normalisation.
     */
    static final String NAME_PATTERN = "^[A-Za-z]+(?:[ '-][A-Za-z]+)*$";
    static final int NAME_MAX_LENGTH = 40;

    private final GreetingProperties greeting;

    public HelloController(GreetingProperties greeting) {
        this.greeting = greeting;
    }

    // Spring MVC (6.1+) validates constrained @RequestParam values automatically and throws
    // HandlerMethodValidationException on failure; ApiExceptionHandler turns that into a generic 400.
    @GetMapping("/hello")
    public HelloResponse hello(
            @RequestParam(defaultValue = "World")
            @Size(min = 1, max = NAME_MAX_LENGTH)
            @Pattern(regexp = NAME_PATTERN)
            String name) {
        // Returned as JSON (Content-Type: application/json), never rendered as HTML; and the input is not logged.
        return new HelloResponse(greeting.prefix() + ", " + name);
    }

    public record HelloResponse(String message) {
    }
}
