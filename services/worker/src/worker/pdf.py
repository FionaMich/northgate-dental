"""HTML to PDF through the internal renderer (Gotenberg, headless Chromium, section 07 T7)."""

import httpx


class PdfError(Exception):
    pass


def render_pdf(base_url: str, html: str) -> bytes:
    try:
        response = httpx.post(f"{base_url}/forms/chromium/convert/html", timeout=20,
                              files={"files": ("index.html", html.encode(), "text/html")},
                              data={"paperWidth": "8.5", "paperHeight": "11", "marginTop": "0.6", "marginBottom": "0.6",
                                    "marginLeft": "0.6", "marginRight": "0.6", "printBackground": "true"})
    except httpx.HTTPError as error:
        raise PdfError(type(error).__name__) from error
    if response.status_code != 200 or not response.content.startswith(b"%PDF"):
        raise PdfError(f"renderer returned {response.status_code}")
    return response.content
