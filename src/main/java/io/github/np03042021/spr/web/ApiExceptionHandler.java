package io.github.np03042021.spr.web;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;

/**
 * Turns validation failures into an RFC 9457 problem response (application/problem+json).
 * The response never echoes the rejected input (no reflected XSS, no leaking what the validator saw)
 * and never includes exception class names or stack traces.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    static final String INVALID_NAME_DETAIL =
            "name must be 1-40 ASCII letters, optionally separated by single spaces, hyphens or apostrophes";

    @ExceptionHandler(HandlerMethodValidationException.class)
    public ProblemDetail invalidInput(HandlerMethodValidationException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, INVALID_NAME_DETAIL);
        problem.setTitle("Invalid request parameter");
        return problem;
    }
}
