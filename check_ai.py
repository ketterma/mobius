# check_ai.py
# Requires: aiohttp, asyncio
# pip install aiohttp

import asyncio
import aiohttp
import itertools
import string
from typing import List

RDAP_BASE = "https://rdap.identitydigital.services/rdap/domain/"

async def check_domain(session: aiohttp.ClientSession, domain: str) -> (str, bool):
    url = RDAP_BASE + domain
    try:
        async with session.get(url, timeout=10) as resp:
            data = await resp.json()
            # Check if errorCode is 404 in the JSON response
            if data.get("errorCode") == 404:
                return domain, True   # likely available
            else:
                return domain, False  # taken or other info present
    except Exception as e:
        # On network error, return False so you re-check later
        return domain, False

async def main() -> None:
    two_letters = (''.join(p) for p in itertools.product(string.ascii_lowercase, repeat=2))
    names = [f"{s}.ai" for s in two_letters]
    timeout = aiohttp.ClientTimeout(total=30)
    connector = aiohttp.TCPConnector(limit_per_host=10)  # throttle concurrency
    async with aiohttp.ClientSession(timeout=timeout, connector=connector) as session:
        tasks = [check_domain(session, d) for d in names]
        # run with bounded concurrency
        results = []
        semaphore = asyncio.Semaphore(20)
        async def sem_task(t):
            async with semaphore:
                return await t
        wrapped = [sem_task(t) for t in tasks]
        for fut in asyncio.as_completed(wrapped):
            domain, available = await fut
            results.append((domain, available))
            if available:
                print(f"[AVAILABLE] {domain}")
        # optional: write all results to file
        with open("ai_two_letter_availability.csv", "w") as f:
            f.write("domain,available\n")
            for d,a in sorted(results):
                f.write(f"{d},{a}\n")

if __name__ == "__main__":
    asyncio.run(main())
