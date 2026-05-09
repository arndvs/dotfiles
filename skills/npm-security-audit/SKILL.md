---
name: npm-security-audit
description: "Layered security audit on npm/pnpm/yarn projects before installing or running. Use to vet a GitHub repo, npm package, or local project before npm install/start/npx."
---

# npm Security Audit Skill

Output "Read npm Security Audit skill." to chat to acknowledge you read this file.

Performs a layered security audit on an npm/pnpm/yarn project to detect supply chain attack vectors,
credential theft attempts, persistence mechanisms, and suspicious network behavior — before
any code is executed. Works on monorepos (multiple package.json files) and single-package repos.

## When to use
- User wants to audit a local cloned repo before running it
- Trigger phrases: 'check this repo before I run it', 'is this package safe', 'audit this project', 'scan this before installing', 'should I trust this repo'
- Trigger proactively if the user mentions cloning a random GitHub repo and running it
- User has only a GitHub URL: ask them to clone it first — this skill operates on files on disk

## Step 0 — Detect repo structure (monorepo vs single package)

Always run this first to know what you're dealing with. Do NOT assume `./package.json` exists at the repo root — some repos keep the Node app in a subdirectory.

```bash
# Find ALL package.json files, excluding node_modules
find . -name "package.json" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" | sort

# Workspaces declared in pnpm-workspace.yaml (pnpm doesn't put them in package.json)
if [ -f pnpm-workspace.yaml ]; then
  echo "Workspaces (pnpm-workspace.yaml):"
  grep -E '^[[:space:]]*-[[:space:]]' pnpm-workspace.yaml | head -20
fi

# Detect package manager and security posture for EACH discovered package.json
find . -name "package.json" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" -print0 | while IFS= read -r -d '' pkg; do
  echo "--- $pkg ---"
  python3 - "$pkg" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    p = json.load(f)
ws = p.get('workspaces') or p.get('packages')
pm = p.get('packageManager', '')
print(f'Workspaces (package.json): {ws}')
print(f'packageManager: {pm}')
built = p.get('pnpm', {}).get('onlyBuiltDependencies')
if built:
    print(f'GOOD: pnpm.onlyBuiltDependencies allowlist present: {built}')
    print('  (only these packages can run install scripts — all others blocked)')
else:
    print('NOTE: No pnpm.onlyBuiltDependencies — all transitive deps can run scripts')
PY
done
```

**If monorepo:** run Layers 1-3 against EVERY package.json found, not just the root.
A malicious hook in `packages/utils/package.json` is just as dangerous as one in the root.

---

## Audit Layers (run in order)

### Layer 1 — package.json Lifecycle Scripts (HIGHEST RISK)
These run automatically on `npm install`. Malicious actors hide code here.

```bash
# Scan ALL package.json files in the repo for lifecycle hooks.
# -print0 + read -d '' handles paths with spaces; pass path as argv to Python.
find . -name "package.json" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" -print0 | while IFS= read -r -d '' pkg; do
  echo "=== $pkg ==="
  python3 - "$pkg" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
scripts = p.get('scripts', {})
danger = ['preinstall','postinstall','install','prepare','prepack','prepublish']
found = False
for k in danger:
    if k in scripts:
        print(f'  WARNING [{k}]: {scripts[k]}')
        found = True
if not found:
    print('  OK: No lifecycle hooks')
PY
done
```

**Red flags:**
- Any `preinstall`/`postinstall` that runs a shell command, curl, wget, `node -e`, or eval
- Base64-encoded strings (e.g. `node -e "require('child_process').exec(Buffer.from(...).toString())"`)
- Scripts that reference files outside the project directory
- `prepare` hooks that run before `npm install` completes

**Expected legitimate patterns** (verify these are what they claim):
- `postinstall: node ./scripts/postinstall.mjs` — read that script before trusting it
- `prepare: husky install` — git hook installer, widely used, low risk
- `build: tsc` / `build: webpack` — normal build tooling

---

### Layer 2 — Lock File Integrity
Lock files are a common tamper point — a dependency can be swapped for a malicious version
without touching package.json. In a monorepo, every workspace can carry its own lock file,
so scan all of them, not just the root.

```bash
# Check for recently modified lock files anywhere in the repo (tampering signal)
git log --oneline --since='14 days ago' --name-only -- \
  '*package-lock.json' '*yarn.lock' '*pnpm-lock.yaml' 2>/dev/null | head -30

# Scan EVERY pnpm-lock.yaml for non-registry package sources
find . -name 'pnpm-lock.yaml' -not -path '*/node_modules/*' -print0 | while IFS= read -r -d '' lock; do
  echo "=== Non-registry sources in $lock ==="
  grep -E '^[[:space:]]+(resolution|tarball):' "$lock" | \
    grep -v 'registry.npmjs.org\|registry.yarnpkg.com' | head -20
done

# Scan EVERY package-lock.json for non-registry resolved URLs
find . -name 'package-lock.json' -not -path '*/node_modules/*' -print0 | while IFS= read -r -d '' lock; do
  python3 - "$lock" <<'PY'
import json, sys
lock=json.load(open(sys.argv[1]))
pkgs=lock.get('packages',lock.get('dependencies',{}))
hits=[]
for name,info in pkgs.items():
    resolved=info.get('resolved','') if isinstance(info,dict) else ''
    if resolved and 'registry.npmjs.org' not in resolved and resolved.startswith('http'):
        hits.append(f'  NON-REGISTRY: {name} -> {resolved}')
if hits:
    print(f'=== {sys.argv[1]} ===')
    for h in hits: print(h)
PY
done

# Scan EVERY yarn.lock for non-registry resolved URLs
find . -name 'yarn.lock' -not -path '*/node_modules/*' -print0 | while IFS= read -r -d '' lock; do
  echo "=== Non-registry sources in $lock ==="
  grep -E '^[[:space:]]+resolved "' "$lock" | \
    grep -v 'registry.npmjs.org\|registry.yarnpkg.com' | head -20
done
```

---

### Layer 3 — Dependency Audit + Typosquatting
Use the audit command that matches the project's package manager. All three resolve
advisories from the same npm advisory database, but each only sees its own lock file.

```bash
# Pick the audit command for the package manager in use
if [ -f pnpm-lock.yaml ]; then
  echo '=== pnpm audit ===';     pnpm audit --json 2>/dev/null || echo '(pnpm audit failed or pnpm not installed)'
elif [ -f yarn.lock ]; then
  echo '=== yarn audit ===';     yarn npm audit --json 2>/dev/null || yarn audit --json 2>/dev/null || echo '(yarn audit failed or yarn not installed)'
elif [ -f package-lock.json ]; then
  npm audit --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
vulns=d.get('vulnerabilities',{})
high=[n for n,i in vulns.items() if i.get('severity') in ('high','critical')]
print(f'Total vulnerabilities: {len(vulns)}  (high/critical: {len(high)})')
for name,info in list(vulns.items())[:20]:
    sev=info.get('severity','unknown')
    print(f'  [{sev.upper()}] {name}')
" 2>/dev/null || echo "(npm audit requires node_modules — run after install)"
else
  echo 'No lock file found — cannot run audit'
fi

# Typosquatting check across ALL package.json files.
# -print0 + argv passing avoids quoting issues on paths with spaces.
find . -name "package.json" -not -path "*/node_modules/*" -print0 | while IFS= read -r -d '' pkg; do
  python3 - "$pkg" <<'PY'
import json, sys
path = sys.argv[1]
p = json.load(open(path))
deps = {**p.get('dependencies', {}), **p.get('devDependencies', {}), **p.get('peerDependencies', {})}
popular = ['react','express','lodash','axios','moment','chalk','commander','dotenv',
           'eslint','webpack','babel','typescript','jest','mocha','prettier','vite',
           'rollup','esbuild','vitest','zod','prisma','next','tailwindcss']
hits = []
for dep in deps:
    for pop in popular:
        if dep != pop and (dep.startswith(pop[:4]) or pop.startswith(dep[:4])):
            if abs(len(dep) - len(pop)) <= 3:
                hits.append(f'  WARN: "{dep}" resembles "{pop}"')
if hits:
    print(f'{path}:')
    for h in hits:
        print(h)
PY
done
```

---

### Layer 4 — Suspicious Code Patterns
Scans all source and config files. Many findings will be legitimate — use the context
notes below to determine what needs investigation.

```bash
python3 << 'PYEOF'
import os,re
from collections import defaultdict

patterns = [
    ('CRITICAL', r"require\s*\(\s*['\"]child_process['\"]\)", 'child_process import'),
    ('CRITICAL', r'eval\s*\(', 'eval()'),
    ('CRITICAL', r'Function\s*\(\s*[\'\"` ]', 'Function constructor (eval-like)'),
    ('HIGH',     r'Buffer\.from\([^)]+\)\.toString\(\)', 'base64 decode'),
    ('HIGH',     r'exec\s*\(|execSync\s*\(', 'shell exec'),
    ('HIGH',     r'spawn\s*\(|spawnSync\s*\(', 'process spawn'),
    ('MEDIUM',   r'https?://[^\s\'\";\`]+', 'outbound URL'),
    ('MEDIUM',   r'process\.env', 'env var access'),
    ('MEDIUM',   r'os\.homedir\s*\(|process\.env\.HOME', 'home dir access'),
    ('MEDIUM',   r'cron|launchd|LaunchAgent|systemd|schtasks', 'persistence keyword'),
    ('LOW',      r'fs\.readFile|fs\.readFileSync', 'file read'),
    ('LOW',      r'curl|wget', 'curl/wget reference'),
]

skip_dirs = {'node_modules','.git','dist','build','.next','coverage','__pycache__'}
skip_ext  = {'.png','.jpg','.jpeg','.gif','.svg','.ico','.woff','.ttf',
             '.lock','.sum','.snap','.map'}
findings  = defaultdict(list)

for root,dirs,files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for f in files:
        if any(f.endswith(e) for e in skip_ext) or f.endswith('.min.js'):
            continue
        path = os.path.join(root,f)
        try:
            with open(path,'r',errors='ignore') as fh:
                for i,line in enumerate(fh,1):
                    for sev,pat,label in patterns:
                        if re.search(pat,line,re.IGNORECASE):
                            findings[path].append((i,sev,label,line.strip()[:120]))
        except:
            pass

if not findings:
    print('No suspicious patterns found.')
else:
    print('=== CRITICAL / HIGH (investigate these) ===')
    for path in sorted(findings):
        hits=[h for h in findings[path] if h[1] in ('CRITICAL','HIGH')]
        if hits:
            print(f'\n{path}:')
            for lineno,sev,label,text in hits:
                print(f'  Line {lineno} [{sev}] {label}: {text}')
    print('\n=== MEDIUM / LOW (likely legitimate, verify by file location) ===')
    for path in sorted(findings):
        hits=[h for h in findings[path] if h[1] in ('MEDIUM','LOW')]
        if hits:
            print(f'\n{path}:')
            for lineno,sev,label,text in hits:
                print(f'  Line {lineno} [{sev}] {label}: {text}')
PYEOF
```

**Context for common false positives:**
- `child_process` in `scripts/build.mjs`, `tools/`, or test files = likely legitimate
- `child_process` in `eslint.config.js`, `.eslintrc`, or `prettier.config.js` = INVESTIGATE
- `exec` in build tooling = normal; `exec` in postinstall = red flag
- `process.env.API_KEY` in `src/config.ts` = normal config loading
- `Buffer.from(..., 'base64')` decoding **API responses** (images, binary) = legitimate
- `Buffer.from(..., 'base64').toString()` in **postinstall or config files** = investigate

The file location matters as much as the pattern itself.

---

### Layer 5 — Obfuscation Detection
Single-line compressed files are the exact technique used in real attacks (buried in eslint configs):

```bash
python3 << 'PYEOF'
import os,re

skip_dirs = {'node_modules','.git','dist','build','coverage'}
js_ext    = {'.js','.ts','.mjs','.cjs','.jsx','.tsx'}

for root,dirs,files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for f in files:
        if not any(f.endswith(e) for e in js_ext):
            continue
        path = os.path.join(root,f)
        try:
            with open(path,'r',errors='ignore') as fh:
                for i,line in enumerate(fh,1):
                    s=line.rstrip()
                    if len(s) > 200:
                        # Extra suspicious in config files vs source files
                        is_config = any(x in path for x in
                            ['eslint','prettier','.config','postinstall','preinstall','rc.js'])
                        sev = 'CRITICAL' if is_config else 'HIGH'
                        print(f'[{sev}] LONG LINE ({len(s)} chars): {path}:{i}')
                        print(f'  Preview: {s[:200]}...')
                    # Base64 blobs — lower risk in test/fixture/data files
                    if re.search(r'[A-Za-z0-9+/]{80,}={0,2}', s):
                        is_data = any(x in path for x in
                            ['fixture','test','mock','sample','data','asset','media'])
                        sev = 'INFO' if is_data else 'HIGH'
                        print(f'[{sev}] BASE64 BLOB: {path}:{i}')
                        print(f'  Preview: {s[:150]}')
        except:
            pass
PYEOF
```

---

### Layer 6 — Credential Exfiltration Pattern
Files that both read credentials AND make network calls are the highest-signal combined finding:

```bash
python3 << 'PYEOF'
import os,re

skip_dirs={'node_modules','.git','dist','build'}

for root,dirs,files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for f in files:
        if not f.endswith(('.js','.ts','.mjs','.cjs','.config.js','.config.ts')):
            continue
        path=os.path.join(root,f)
        content=open(path,'r',errors='ignore').read()
        has_cred=bool(re.search(
            r'readFileSync|homedir\(\)|\.env|id_rsa|\.aws|\.ssh|\.npmrc|\.netrc',
            content,re.I))
        has_net=bool(re.search(
            r"require\s*\(\s*['\"]https?['\"]|fetch\s*\(|axios\.|http\.|https\.",
            content,re.I))
        if has_cred and has_net:
            is_config = any(x in path for x in ['config','setup','init','auth','client'])
            flag = 'REVIEW' if is_config else 'CRITICAL'
            print(f'[{flag}]: {path} -- reads credentials AND makes network calls')
PYEOF
```

---

### Layer 7 — Git History Check

```bash
# Recent commits to config/tooling files (prime attack surface)
git log --oneline --since='30 days ago' -- \
  '*.json' '*.config.*' '.eslint*' '*.rc' '*.rc.js' 2>/dev/null | head -20

# Local history rewrites visible to this clone only.
# NOTE: reflog cannot detect upstream force-pushes that happened before you cloned.
# For that, compare against a known-good commit or check GitHub's events API.
git reflog --date=relative 2>/dev/null | grep -Ei 'forced-update|reset|rebase' | head -10

# Config files modified in the last 7 days
git log --oneline --diff-filter=M --name-only --since='7 days ago' \
  -- '*.json' '*.config.*' 2>/dev/null | head -20

# Was the pnpm onlyBuiltDependencies allowlist recently weakened?
git log --oneline -p -- package.json 2>/dev/null | \
  grep -A2 -B2 'onlyBuiltDependencies' | head -20
```

---

## Interpreting Results

| Finding | Risk Level | Action |
|---|---|---|
| `postinstall` runs `node -e`, curl, eval, base64 | CRITICAL | Do not install. Decode and read first. |
| Credential read + network call in same file | CRITICAL | Treat as exfiltration attempt |
| Long single line in eslint/prettier/config file | CRITICAL | Decompress and read before anything |
| Persistence mechanism (cron/launchd/schtasks) | CRITICAL | Do not run. Investigate fully. |
| `child_process` in a config or tooling file | HIGH | Verify the file's actual purpose |
| Non-registry source in lock file | HIGH | Verify the source is intentional |
| Base64 blob in non-data file | HIGH | Decode without executing |
| `child_process` in `scripts/` or `tools/` | MEDIUM | Likely build tooling — verify |
| `process.env` in `src/config.*` | LOW | Normal config loading pattern |
| `Buffer.from(...,'base64')` on API response | LOW | Legitimate if decoding known data |
| Missing `onlyBuiltDependencies` in pnpm project | MEDIUM | Consider adding for defense in depth |

---

## Safe Inspection Workflow

When something looks suspicious, read without executing:

```bash
# Read a suspicious minified/compressed file safely
cat ./suspicious-file.js | head -c 3000

# Decode a base64 blob without running it
echo "PASTE_BASE64_HERE" | base64 --decode | head -c 2000

# Prettify minified JS without executing
node -e "
const fs = require('fs');
const src = fs.readFileSync('./suspicious.js', 'utf8');
console.log(src);  // Just print — do NOT eval or require
"

# Research a suspicious domain
nslookup suspicious-domain.xyz
# Or: https://www.virustotal.com/gui/domain/suspicious-domain.xyz
```

---

## Quick One-Liner Pre-flight

Run this before `npm install` on any unfamiliar repo:

```bash
find . -name "package.json" -not -path "*/node_modules/*" -print0 | sort -z | while IFS= read -r -d '' pkg; do
  python3 - "$pkg" <<'PY'
import json, sys
path = sys.argv[1]
p = json.load(open(path))
s = p.get('scripts', {})
danger = ['preinstall', 'postinstall', 'prepare', 'install']
hits = [k for k in danger if k in s]
if hits:
    print(f'WARNING {path} -- LIFECYCLE HOOKS:')
    for h in hits: print(f'  {h}: {s[h]}')
else:
    print(f'OK {path} -- no lifecycle hooks')
PY
done
```

---

## Post-Incident Checklist

If you already ran a suspicious package:

1. **Disconnect from network** — stop any active exfiltration
2. **Rotate all credentials** — API keys, tokens, cloud credentials, secrets on disk
3. **Check for scheduled tasks**:
   - macOS: `launchctl list | grep -v com.apple`, `ls ~/Library/LaunchAgents/`
   - Linux: `crontab -l`, `systemctl list-timers --user`, `ls /etc/cron.d/`
   - Windows: `schtasks /query /fo LIST`
4. **Audit recent git pushes** across all repos connected to this machine
5. **Check SSH** `~/.ssh/known_hosts` and `~/.ssh/authorized_keys` for new entries
6. **Revoke and reissue** GitHub tokens, deploy keys, and OAuth apps
7. **Enable push protection** on GitHub to block future credential commits
8. **Review** `~/.gitconfig` — attackers sometimes add malicious hooks here too
