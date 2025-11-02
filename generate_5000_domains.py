#!/usr/bin/env python3
# Generate 5000 creative .ai domain candidates
# Focus on pronounceable, memorable names while avoiding common English words

import itertools
import random

# Common English words to avoid (likely taken)
COMMON_WORDS = {
    'ace', 'act', 'add', 'age', 'ago', 'aid', 'aim', 'air', 'all', 'and', 'ant', 'any', 'ape', 'arc', 'are', 'ark', 'arm', 'art', 'ask', 'ate',
    'bad', 'bag', 'ban', 'bar', 'bat', 'bay', 'bed', 'bee', 'bet', 'bid', 'big', 'bin', 'bit', 'box', 'boy', 'bug', 'bus', 'but', 'buy',
    'cab', 'cam', 'can', 'cap', 'car', 'cat', 'cob', 'cod', 'cop', 'cot', 'cow', 'cry', 'cub', 'cup', 'cut',
    'dad', 'dam', 'day', 'den', 'dew', 'did', 'die', 'dig', 'dim', 'dip', 'dog', 'dot', 'dry', 'dub', 'dud', 'due', 'dug', 'duo',
    'ear', 'eat', 'eel', 'egg', 'ego', 'elf', 'elk', 'elm', 'emu', 'end', 'era', 'eve', 'eye',
    'fad', 'fan', 'far', 'fat', 'fax', 'fee', 'few', 'fig', 'fin', 'fir', 'fit', 'fix', 'fly', 'foe', 'fog', 'for', 'fox', 'fry', 'fun', 'fur',
    'gag', 'gap', 'gas', 'gel', 'gem', 'get', 'god', 'got', 'gum', 'gun', 'gut', 'guy', 'gym',
    'had', 'ham', 'has', 'hat', 'hay', 'hen', 'her', 'hew', 'hex', 'hey', 'hid', 'him', 'hip', 'his', 'hit', 'hog', 'hop', 'hot', 'how', 'hub', 'hue', 'hug', 'hum', 'hut',
    'ice', 'icy', 'ill', 'imp', 'ink', 'inn', 'ion', 'its', 'ivy',
    'jab', 'jag', 'jam', 'jar', 'jaw', 'jay', 'jet', 'jig', 'job', 'jog', 'joy', 'jug',
    'ken', 'key', 'kid', 'kin', 'kit',
    'lab', 'lad', 'lag', 'lap', 'law', 'lax', 'lay', 'lea', 'led', 'leg', 'let', 'lid', 'lie', 'lip', 'lit', 'log', 'lot', 'low', 'lux',
    'mad', 'man', 'map', 'mat', 'max', 'may', 'men', 'met', 'mid', 'mix', 'mob', 'mod', 'mom', 'mop', 'mud', 'mug',
    'nab', 'nag', 'nap', 'nav', 'nay', 'net', 'new', 'nil', 'nit', 'nod', 'nor', 'not', 'now', 'nun', 'nut',
    'oak', 'oar', 'oat', 'odd', 'off', 'oft', 'oil', 'old', 'one', 'opt', 'orb', 'ore', 'our', 'out', 'owe', 'owl', 'own',
    'pad', 'pal', 'pan', 'par', 'pat', 'paw', 'pax', 'pay', 'pea', 'peg', 'pen', 'pep', 'per', 'pet', 'pie', 'pig', 'pin', 'pit', 'pod', 'pop', 'pot', 'pry', 'pub', 'pug', 'pun', 'pup', 'put',
    'rad', 'rag', 'ram', 'ran', 'rap', 'rat', 'raw', 'ray', 'red', 'ref', 'rep', 'rev', 'rib', 'rid', 'rig', 'rim', 'rip', 'rob', 'rod', 'roe', 'rot', 'row', 'rub', 'rug', 'rum', 'run', 'rut', 'rye',
    'sac', 'sad', 'sag', 'sap', 'sat', 'saw', 'sax', 'say', 'sea', 'see', 'set', 'sew', 'shy', 'sin', 'sip', 'sir', 'sis', 'sit', 'six', 'ska', 'ski', 'sky', 'sly', 'sob', 'sod', 'son', 'sop', 'sow', 'sox', 'soy', 'spa', 'spy', 'sub', 'sum', 'sun', 'sup',
    'tab', 'tad', 'tag', 'tan', 'tap', 'tar', 'tat', 'tax', 'tea', 'tee', 'ten', 'the', 'thy', 'tic', 'tie', 'tin', 'tip', 'toe', 'ton', 'too', 'top', 'tot', 'tow', 'toy', 'try', 'tub', 'tug', 'two',
    'ump', 'urn', 'use',
    'van', 'var', 'vat', 'vet', 'via', 'vie', 'vow',
    'wad', 'wag', 'wan', 'war', 'was', 'wax', 'way', 'web', 'wed', 'wee', 'wet', 'who', 'why', 'wig', 'win', 'wit', 'woe', 'wok', 'won', 'woo', 'wow',
    'yak', 'yam', 'yap', 'yaw', 'yea', 'yes', 'yet', 'yew', 'yon', 'you', 'yow',
    'zap', 'zen', 'zip', 'zoo',
    # Tech words likely taken
    'api', 'app', 'bot', 'cpu', 'dev', 'dns', 'git', 'gpu', 'hub', 'lan', 'net', 'ops', 'ram', 'sdk', 'sql', 'ssh', 'ssl', 'tcp', 'tls', 'udp', 'url', 'usb', 'wan', 'web', 'wifi',
    # More tech
    'aws', 'cdn', 'cli', 'cms', 'css', 'dom', 'ftp', 'gui', 'html', 'http', 'ide', 'imap', 'jpeg', 'json', 'node', 'npm', 'php', 'rest', 'smtp', 'soap', 'unix', 'yaml',
    # Common names
    'bob', 'dan', 'don', 'ian', 'jay', 'jim', 'joe', 'jon', 'ken', 'kim', 'lee', 'len', 'lou', 'max', 'meg', 'pam', 'pat', 'ray', 'rob', 'ron', 'roy', 'sam', 'sue', 'ted', 'tim', 'tom', 'vic',
}

def is_pronounceable(s):
    """Check if a 3-letter combo is reasonably pronounceable."""
    vowels = set('aeiou')
    consonants = set('bcdfghjklmnpqrstvwxyz')

    # At least one vowel
    if not any(c in vowels for c in s):
        return False

    # Avoid 3 consonants in a row
    if all(c in consonants for c in s):
        return False

    # Avoid awkward patterns
    awkward = ['qx', 'qz', 'xq', 'zq', 'wx', 'xw', 'vx', 'xv']
    for pattern in awkward:
        if pattern in s:
            return False

    return True

def generate_candidates():
    """Generate domain candidates."""
    candidates = set()

    # 1. All 3-letter pronounceable combinations
    print("Generating 3-letter combinations...")
    for combo in itertools.product('abcdefghijklmnopqrstuvwxyz', repeat=3):
        word = ''.join(combo)
        if word not in COMMON_WORDS and is_pronounceable(word):
            candidates.add(word)

    # 2. 4-letter combinations with good patterns
    print("Generating 4-letter combinations...")
    # Pattern: consonant-vowel-consonant-vowel (CVCV) - very pronounceable
    consonants = 'bcdfghjklmnpqrstvwxyz'
    vowels = 'aeiou'
    for c1, v1, c2, v2 in itertools.product(consonants, vowels, consonants, vowels):
        word = c1 + v1 + c2 + v2
        if word not in COMMON_WORDS:
            candidates.add(word)

    # Pattern: vowel-consonant-vowel-consonant (VCVC)
    for v1, c1, v2, c2 in itertools.product(vowels, consonants, vowels, consonants):
        word = v1 + c1 + v2 + c2
        if word not in COMMON_WORDS:
            candidates.add(word)

    # 3. Jax-related variations (since that's your name)
    print("Generating Jax variations...")
    jax_patterns = [
        # j + vowel + consonant
        *[f"j{v}{c}" for v in vowels for c in consonants],
        # j + consonant + vowel
        *[f"j{c}{v}" for c in consonants for v in vowels],
        # consonant + ax
        *[f"{c}ax" for c in consonants if c != 'j'],
        # consonant + ex
        *[f"{c}ex" for c in consonants],
        # x variations
        *[f"{c}x{v}" for c in consonants for v in vowels],
        *[f"{v}x{c}" for v in vowels for c in consonants],
    ]
    for word in jax_patterns:
        if word not in COMMON_WORDS and len(word) >= 3:
            candidates.add(word)

    # 4. Lab/tech themed but creative
    print("Generating tech-themed variations...")
    tech_prefixes = ['lab', 'net', 'dev', 'ops', 'sys', 'pod', 'hub', 'box', 'bit', 'hex']
    tech_suffixes = ['x', 'z', 'k', 'r', 'n', 'm', 'y']
    for prefix in tech_prefixes:
        for suffix in tech_suffixes:
            word = prefix + suffix
            if word not in COMMON_WORDS:
                candidates.add(word)

    # 5. Double letters (memorable)
    print("Generating double-letter patterns...")
    for letter in 'abcdefghijklmnopqrstuvwxyz':
        # Pattern: Xab, Xac, etc.
        for c in 'abcdefghijklmnopqrstuvwxyz':
            word = letter + letter + c
            if word not in COMMON_WORDS and is_pronounceable(word):
                candidates.add(word)
            # Reverse: aXX, bXX
            word = c + letter + letter
            if word not in COMMON_WORDS and is_pronounceable(word):
                candidates.add(word)

    # 6. Number combinations (modern feel)
    print("Generating number combinations...")
    for c1 in consonants:
        for v in vowels:
            for n in '123456789':
                candidates.add(f"{c1}{v}{n}")
                candidates.add(f"{c1}{n}{v}")
                candidates.add(f"{n}{c1}{v}")

    return candidates

def main():
    print("Generating creative .ai domain candidates...\n")

    candidates = generate_candidates()

    print(f"\nGenerated {len(candidates)} unique candidates")

    # Prioritize good patterns before trimming to 5000
    priority_domains = []
    regular_domains = []

    for domain in candidates:
        # Prioritize these patterns:
        # - Contains 'j' (for jax)
        # - Contains 'x' (cool factor)
        # - Ends in 'x' or 'z'
        # - 3-4 letters only (short is better)
        is_priority = False

        if 'j' in domain:
            is_priority = True
        elif 'x' in domain and len(domain) <= 4:
            is_priority = True
        elif domain.endswith(('x', 'z')) and len(domain) <= 4:
            is_priority = True
        elif len(domain) == 3:
            is_priority = True

        if is_priority:
            priority_domains.append(domain)
        else:
            regular_domains.append(domain)

    # Sort each group
    priority_domains.sort()
    regular_domains.sort()

    # Combine: priority first, then fill with regular
    domains = priority_domains + regular_domains

    print(f"  • {len(priority_domains)} priority domains (j, x, short)")
    print(f"  • {len(regular_domains)} regular domains")

    # Take first 5000
    if len(domains) > 5000:
        domains = domains[:5000]
        print(f"Trimmed to 5000 domains (kept all priority)")

    # Write to file (one per line, no .ai extension - easier for bulk checkers)
    with open("5000_domains.txt", "w") as f:
        for domain in domains:
            f.write(f"{domain}\n")

    # Also create a .ai version
    with open("5000_domains_with_ai.txt", "w") as f:
        for domain in domains:
            f.write(f"{domain}.ai\n")

    print(f"\nFiles created:")
    print(f"  • 5000_domains.txt (without .ai extension)")
    print(f"  • 5000_domains_with_ai.txt (with .ai extension)")

    # Show some samples
    print(f"\nSample domains:")
    random.seed(42)
    samples = random.sample(domains, min(30, len(domains)))
    for i, domain in enumerate(sorted(samples), 1):
        print(f"  {i:2d}. {domain}.ai")

if __name__ == "__main__":
    main()
