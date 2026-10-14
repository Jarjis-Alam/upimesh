package com.demo.upimesh;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC Security Configuration.
 * Restricts browser Cross-Origin Resource Sharing (CORS) on API endpoints.
 * Explicitly restricts cross-origin access to trusted local origins,
 * blocking arbitrary internet domains from triggering browser requests to local nodes.
 */
@Configuration
public class WebMvcSecurityConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins("http://localhost:8080", "http://127.0.0.1:8080")
                .allowedMethods("GET", "POST")
                .allowedHeaders("*")
                .allowCredentials(false)
                .maxAge(3600);
    }
}
