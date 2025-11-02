#!/usr/bin/env python3
# Targeted .ai domain availability checker
# Checks only meaningful short domains that would be good for a homelab

import asyncio
import aiohttp
from typing import List, Tuple

RDAP_BASE = "https://rdap.identitydigital.services/rdap/domain/"

# Curated list of meaningful short domains
CANDIDATES = [
    # Jax variations
    "jax.ai", "jxl.ai", "jxb.ai", "jxk.ai", "jxn.ai", "jxs.ai",

    # Lab variations
    "lab.ai", "jab.ai", "jal.ai", "jlb.ai",

    # Short/memorable tech terms
    "dev.ai", "ops.ai", "net.ai", "hub.ai", "sys.ai", "kod.ai",
    "box.ai", "pod.ai", "node.ai", "core.ai", "edge.ai",

    # Pronounceable 3-letter combos
    "jak.ai", "jex.ai", "zax.ai", "pax.ai", "kex.ai", "vex.ai",
    "nyx.ai", "lux.ai", "rax.ai", "dax.ai", "kax.ai", "wax.ai",

    # Fun/creative
    "zap.ai", "zip.ai", "zen.ai", "yak.ai", "fox.ai", "hex.ai",
    "max.ai", "rex.ai", "neo.ai", "ace.ai", "sky.ai", "bay.ai",

    # Tech-adjacent
    "bit.ai", "cpu.ai", "ram.ai", "tcp.ai", "udp.ai", "dns.ai",
    "lan.ai", "wan.ai", "api.ai", "cli.ai", "git.ai", "ssh.ai",
]

async def check_domain(session: aiohttp.ClientSession, domain: str) -> Tuple[str, bool]:
    """Check if a domain is available via RDAP."""
    url = RDAP_BASE + domain
    try:
        async with session.get(url, timeout=10) as resp:
            data = await resp.json()
            # errorCode 404 means domain not found (available)
            available = data.get("errorCode") == 404
            return domain, available
    except Exception as e:
        print(f"Error checking {domain}: {e}")
        return domain, False

async def main() -> None:
    # Remove duplicates and sort
    domains = sorted(set(CANDIDATES))

    print(f"Checking {len(domains)} targeted .ai domains...\n")

    # Use conservative throttling to respect rate limits
    timeout = aiohttp.ClientTimeout(total=30)
    connector = aiohttp.TCPConnector(limit_per_host=5)

    async with aiohttp.ClientSession(timeout=timeout, connector=connector) as session:
        # Limit to 5 concurrent requests to be respectful
        semaphore = asyncio.Semaphore(5)

        async def sem_check(domain):
            async with semaphore:
                # Add small delay between requests
                await asyncio.sleep(0.2)
                return await check_domain(session, domain)

        tasks = [sem_check(d) for d in domains]
        results = await asyncio.gather(*tasks)

        # Separate available and taken
        available = []
        taken = []

        for domain, is_available in sorted(results):
            if is_available:
                available.append(domain)
                print(f"✓ AVAILABLE: {domain}")
            else:
                taken.append(domain)

        # Summary
        print(f"\n{'='*50}")
        print(f"Results: {len(available)} available, {len(taken)} taken")
        print(f"{'='*50}")

        if available:
            print(f"\nAvailable domains ({len(available)}):")
            for domain in available:
                print(f"  • {domain}")
        else:
            print("\nNo available domains found in this search.")

        # Write results to file
        with open("targeted_ai_results.txt", "w") as f:
            f.write("AVAILABLE DOMAINS\n")
            f.write("="*50 + "\n")
            for domain in available:
                f.write(f"{domain}\n")
            f.write(f"\nTAKEN DOMAINS ({len(taken)})\n")
            f.write("="*50 + "\n")
            for domain in taken:
                f.write(f"{domain}\n")

        print(f"\nResults saved to: targeted_ai_results.txt")

if __name__ == "__main__":
    asyncio.run(main())
