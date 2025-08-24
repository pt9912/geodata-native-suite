
package io.geodata.search.api;

import io.micronaut.http.annotation.Controller;
import io.micronaut.http.annotation.Get;
import io.micronaut.http.HttpStatus;
import io.micronaut.http.annotation.Status;

@Controller
public class HealthController {
    @Get("/health")
    @Status(HttpStatus.OK)
    public String health() { return "OK"; }
}
