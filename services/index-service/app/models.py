from typing import Any, List, Optional
from pydantic import BaseModel, Field

class IndexRunRequest(BaseModel):
    mode: str = Field(..., pattern="^(stac|s3)$")
    endpoint: Optional[str] = None
    collections: Optional[List[str]] = None
    bbox: Optional[List[float]] = None
    datetime: Optional[str] = None
    limit: int = 100
    bucket: Optional[str] = None
    prefix: Optional[str] = None
    region: Optional[str] = None
    requester_pays: Optional[bool] = False
    async_: Optional[bool] = Field(default=False, alias="async")
