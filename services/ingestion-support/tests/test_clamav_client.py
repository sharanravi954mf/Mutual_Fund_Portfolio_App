from __future__ import annotations

import asyncio
import struct

import pytest

from app.clamav import ClamavScanner
from app.errors import ServiceError


async def run_fake_clamd(reply: bytes, expected: bytes):
    received = bytearray()

    async def handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        command = await reader.readuntil(b"\0")
        if command == b"zPING\0":
            writer.write(b"PONG\0")
        else:
            assert command == b"zINSTREAM\0"
            while True:
                length = struct.unpack("!I", await reader.readexactly(4))[0]
                if length == 0:
                    break
                received.extend(await reader.readexactly(length))
            writer.write(reply)
        await writer.drain()
        writer.close()

    server = await asyncio.start_server(handler, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    scanner = ClamavScanner("127.0.0.1", port, 1)
    return server, scanner, received, expected


@pytest.mark.asyncio
async def test_clamav_instream_clean_and_readiness() -> None:
    body = b"synthetic clean content"
    server, scanner, received, expected = await run_fake_clamd(b"stream: OK\0", body)
    async with server:
        assert await scanner.ready() is True
        assert await scanner.scan(body) == "clean"
    assert bytes(received) == expected


@pytest.mark.asyncio
async def test_clamav_instream_infected_and_failure_are_distinct() -> None:
    body = b"synthetic test content"
    server, scanner, received, _expected = await run_fake_clamd(
        b"stream: Eicar-Signature FOUND\0", body
    )
    async with server:
        assert await scanner.scan(body) == "infected"
    assert bytes(received) == body

    failed_server, failed_scanner, _received, _ = await run_fake_clamd(
        b"stream: scanner error ERROR\0", body
    )
    async with failed_server:
        with pytest.raises(ServiceError, match="scanner_unavailable"):
            await failed_scanner.scan(body)
