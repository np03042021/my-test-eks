package io.github.np03042021.spr;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan // binds and validates GreetingProperties at startup
public class SecurePavedRoadApplication {

    public static void main(String[] args) {
        SpringApplication.run(SecurePavedRoadApplication.class, args);
    }
}
