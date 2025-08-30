package io.geodata.search.model;

import io.micronaut.serde.annotation.Serdeable;
import jakarta.validation.constraints.NotNull;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@Serdeable
public record ItemOut(
    String id,
    String collection,
    String datetime,
    List<Double> bbox
) {}
