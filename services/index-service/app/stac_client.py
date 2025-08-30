import httpx
from typing import AsyncIterator, Dict, Any, List, Optional, Callable, Union
from pydantic import BaseModel, Field, HttpUrl
import logging
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from typing import Literal 


logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)

class StacSearchParameters(BaseModel):
    """Modell für STAC-Suchparameter mit Validierung."""
    collections: List[str] = Field(..., min_items=1, description="Liste der Collections")
    bbox: Optional[List[float]] = Field(
        None,
        min_items=4,
        max_items=4,
        description="Bounding Box [minx, miny, maxx, maxy]"
    )
    datetime: Optional[str] = Field(
        None,
        description="Zeitbereich (RFC 3339 oder Intervall)"
    )
    limit: int = Field(
        100,
        ge=1,
        le=10000,
        description="Maximale Anzahl der Ergebnisse pro Seite"
    )

class StacFeature(BaseModel):
    """Modell für ein STAC-Feature."""
    type: Literal["Feature"] = "Feature"
    id: str
    geometry: Optional[Dict[str, Any]]
    properties: Dict[str, Any]
    assets: Dict[str, Any]
    links: List[Dict[str, Any]] = Field(default_factory=list)

class StacResponse(BaseModel):
    """Modell für STAC-Antwort."""
    type: Literal["FeatureCollection"] = "FeatureCollection"
    features: List[StacFeature] = Field(default_factory=list)
    links: List[Dict[str, Any]] = Field(default_factory=list)

class StacClient:
    """Client für STAC-APIs mit Unterstützung für Paginierung und OpenTelemetry-Tracing."""

    def __init__(
        self,
        endpoint: Union[str, HttpUrl],
        header_provider: Optional[Callable[[], Dict[str, str]]] = None,
        timeout: int = 60,
        max_retries: int = 3
    ) -> None:
        """
        Initialisiert den STAC-Client.

        Args:
            endpoint: STAC-API-Endpoint
            header_provider: Funktion zur Bereitstellung von Headern
            timeout: Timeout für HTTP-Anfragen in Sekunden
            max_retries: Maximale Anzahl von Wiederholungsversuchen
        """
        self.endpoint = str(endpoint).rstrip("/")
        self.header_provider = header_provider
        self.timeout = timeout
        self.max_retries = max_retries
        self.client = httpx.AsyncClient(
            timeout=timeout,
            headers=self.header_provider() if self.header_provider else {}
        )

    async def __aenter__(self):
        """Kontextmanager für AsyncClient."""
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Schließt den HTTP-Client."""
        await self.client.aclose()

    async def _make_request(
        self,
        method: str,
        url: str,
        **kwargs
    ) -> httpx.Response:
        """
        Führt eine HTTP-Anfrage mit Retry-Logik und Tracing aus.

        Args:
            method: HTTP-Methode (GET, POST, etc.)
            url: Ziel-URL
            **kwargs: Zusätzliche Argumente für httpx

        Returns:
            httpx.Response: Antwortobjekt

        Raises:
            httpx.HTTPStatusError: Bei HTTP-Fehlern
            httpx.RequestError: Bei Netzwerkfehlern
        """
        for attempt in range(self.max_retries):
            try:
                with tracer.start_as_current_span(f"stac_{method.lower()}_request") as span:
                    span.set_attribute("http.method", method)
                    span.set_attribute("http.url", url)
                    span.set_attribute("http.attempt", attempt + 1)

                    response = await self.client.request(method, url, **kwargs)
                    response.raise_for_status()

                    span.set_attribute("http.status_code", response.status_code)
                    span.set_status(Status(StatusCode.OK))
                    return response

            except httpx.HTTPStatusError as e:
                span.record_exception(e)
                span.set_status(Status(StatusCode.ERROR))
                if response.status_code >= 500 and attempt < self.max_retries - 1:
                    logger.warning(
                        f"Server-Fehler (Versuch {attempt + 1}/{self.max_retries}): {str(e)}"
                    )
                    continue
                raise
            except httpx.RequestError as e:
                span.record_exception(e)
                span.set_status(Status(StatusCode.ERROR))
                if attempt < self.max_retries - 1:
                    logger.warning(
                        f"Netzwerkfehler (Versuch {attempt + 1}/{self.max_retries}): {str(e)}"
                    )
                    continue
                raise

        raise httpx.RequestError(f"Maximale Anzahl von Versuchen ({self.max_retries}) erreicht")

    async def search(
        self,
        collections: List[str],
        bbox: Optional[List[float]] = None,
        datetime: Optional[str] = None,
        limit: int = 100,
        **kwargs
    ) -> AsyncIterator[StacFeature]:
        """
        Führt eine STAC-Suche durch und gibt die Features als AsyncIterator zurück.

        Args:
            collections: Liste der Collections
            bbox: Bounding Box
            datetime: Zeitbereich
            limit: Maximale Anzahl der Ergebnisse pro Seite
            **kwargs: Zusätzliche Parameter für die Anfrage

        Yields:
            StacFeature: STAC-Features aus den Suchergebnissen

        Raises:
            httpx.HTTPStatusError: Bei API-Fehlern
            ValueError: Bei ungültigen Parametern
        """
        # Validierung der Parameter
        params = StacSearchParameters(
            collections=collections,
            bbox=bbox,
            datetime=datetime,
            limit=limit
        )

        url = f"{self.endpoint}/search"
        body = params.dict(exclude_none=True)

        with tracer.start_as_current_span("stac_search") as span:
            span.set_attribute("stac.collections", ",".join(collections))
            if bbox:
                span.set_attribute("stac.bbox", str(bbox))
            if datetime:
                span.set_attribute("stac.datetime", datetime)

            next_url = None
            while True:
                try:
                    response = await self._make_request(
                        "POST" if not next_url else "GET",
                        next_url or url,
                        json=body if not next_url else None
                    )

                    data = response.json()
                    validated_data = StacResponse(**data)

                    for feature in validated_data.features:
                        yield feature

                    # Paginierung
                    next_url = None
                    for link in validated_data.links:
                        if link.get("rel") == "next":
                            next_url = link.get("href")
                            if next_url and not next_url.startswith("http"):
                                next_url = f"{self.endpoint}{next_url}"
                            break

                    if not next_url:
                        break

                except httpx.HTTPStatusError as e:
                    span.record_exception(e)
                    span.set_status(Status(StatusCode.ERROR))
                    logger.error(f"STAC-Suche fehlgeschlagen: {str(e)}")
                    raise
                except Exception as e:
                    span.record_exception(e)
                    span.set_status(Status(StatusCode.ERROR))
                    logger.error(f"Unbekannter Fehler bei STAC-Suche: {str(e)}")
                    raise

    async def close(self):
        """Schließt den HTTP-Client."""
        await self.client.aclose()
