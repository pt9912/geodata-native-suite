
import os, time, httpx
from typing import Optional

class EDLTokenManager:
    def __init__(self):
        self.token = os.getenv("EDL_TOKEN","")
        self.refresh_url = os.getenv("EDL_TOKEN_REFRESH_URL","")
        self.client_id = os.getenv("EDL_CLIENT_ID","")
        self.client_secret = os.getenv("EDL_CLIENT_SECRET","")
        self.expiry = 0
    async def get_token(self) -> Optional[str]:
        if not self.token and self.refresh_url and self.client_id:
            await self.refresh()
        if self.expiry and time.time() > self.expiry - 60:
            await self.refresh()
        return self.token or None
    async def refresh(self):
        if not self.refresh_url: return
        try:
            async with httpx.AsyncClient(timeout=30) as c:
                r = await c.post(self.refresh_url, data={
                    "grant_type":"client_credentials",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "audience":"cmr"
                })
                r.raise_for_status()
                data = r.json()
                self.token = data.get("access_token", self.token)
                self.expiry = int(time.time()) + int(data.get("expires_in", 3600))
        except Exception:
            pass
