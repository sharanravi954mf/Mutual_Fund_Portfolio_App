from __future__ import annotations

import asyncio
import struct
from typing import Literal, Protocol

from .errors import ServiceError


class MalwareScanner(Protocol):
    async def scan(self, body: bytes) -> Literal["clean", "infected"]: ...

    async def ready(self) -> bool: ...


class ClamavScanner:
    def __init__(self, host: str, port: int, timeout_seconds: float) -> None:
        self.host = host
        self.port = port
        self.timeout_seconds = timeout_seconds

    async def _connect(self) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        try:
            return await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port),
                timeout=self.timeout_seconds,
            )
        except (TimeoutError, OSError) as error:
            raise ServiceError(503, "scanner_unavailable") from error

    async def _read_reply(self, reader: asyncio.StreamReader) -> str:
        try:
            raw = await asyncio.wait_for(reader.readuntil(b"\0"), self.timeout_seconds)
        except (TimeoutError, OSError, asyncio.IncompleteReadError, asyncio.LimitOverrunError) as error:
            raise ServiceError(503, "scanner_unavailable") from error
        return raw.rstrip(b"\0\n").decode("utf-8", errors="replace")

    async def scan(self, body: bytes) -> Literal["clean", "infected"]:
        reader, writer = await self._connect()
        try:
            writer.write(b"zINSTREAM\0")
            for offset in range(0, len(body), 64 * 1024):
                chunk = body[offset : offset + 64 * 1024]
                writer.write(struct.pack("!I", len(chunk)))
                writer.write(chunk)
                await asyncio.wait_for(writer.drain(), self.timeout_seconds)
            writer.write(struct.pack("!I", 0))
            await asyncio.wait_for(writer.drain(), self.timeout_seconds)
            reply = await self._read_reply(reader)
        except ServiceError:
            raise
        except (TimeoutError, OSError, ConnectionError) as error:
            raise ServiceError(503, "scanner_unavailable") from error
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

        if reply == "stream: OK":
            return "clean"
        if reply.startswith("stream: ") and reply.endswith(" FOUND"):
            return "infected"
        raise ServiceError(503, "scanner_unavailable")

    async def ready(self) -> bool:
        try:
            reader, writer = await self._connect()
            writer.write(b"zPING\0")
            await asyncio.wait_for(writer.drain(), self.timeout_seconds)
            reply = await self._read_reply(reader)
            writer.close()
            await writer.wait_closed()
            return reply == "PONG"
        except (ServiceError, TimeoutError, OSError):
            return False
