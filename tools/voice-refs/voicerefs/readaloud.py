"""Readaloud's planner API: list a book's chapters, fetch their text, upload voice plans."""

import os

import httpx

READALOUD_URL = os.environ.get("READALOUD_URL", "http://pylon:4000")


class Readaloud:
    def __init__(self, client: httpx.Client | None = None):
        self.client = client or httpx.Client(base_url=READALOUD_URL, timeout=60)

    def _json(self, resp: httpx.Response) -> dict:
        if resp.status_code >= 400:
            raise RuntimeError(f"{resp.request.method} {resp.request.url.path}: HTTP {resp.status_code} {resp.text[:300]}")
        return resp.json()

    def chapters(self, book_id: int) -> list[dict]:
        return self._json(self.client.get(f"/api/books/{book_id}/chapters"))["chapters"]

    def text(self, book_id: int, chapter_id: int) -> dict:
        return self._json(self.client.get(f"/api/books/{book_id}/chapters/{chapter_id}/text"))

    def put_plan(self, book_id: int, chapter_id: int, doc: dict) -> dict:
        return self._json(self.client.put(f"/api/books/{book_id}/chapters/{chapter_id}/voice-plan", json=doc))
