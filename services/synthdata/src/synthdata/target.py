"""Refuse to load synthetic data anywhere except staging or a local database (E28)."""

from urllib.parse import urlsplit

PRODUCTION_REF = "orrmekwuuicmofemmitu"
STAGING_REF = "dxkfsslymzqbgtoijuut"
LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


class UnsafeTarget(Exception):
    """The database address is production or not on the allow-list."""


def check_target(url: str) -> None:
    """Raise UnsafeTarget unless url points at the staging project or a local database."""
    if PRODUCTION_REF in url:
        raise UnsafeTarget("refusing to load synthetic data into the production project")
    parts = urlsplit(url)
    if parts.hostname in LOCAL_HOSTS or STAGING_REF in (parts.username or "") or STAGING_REF in (parts.hostname or ""):
        return
    raise UnsafeTarget("only the staging project or a local database may receive generated data")
